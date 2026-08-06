# ── Clean step 1: harmonise ──────────────────────────────────────────────────
# Reads a source's slim database and writes its clean database in a uniform
# format. Value-preserving: no rows removed, originals kept.
#
# Harmonisations applied:
#   - symbol  -> ICES canonical (case-fold; TOC -> CORG)
#   - unit    -> ICES names (strip dw/ww suffix, micro sign -> u)
#   - depth   -> cm
#   - event   -> keep date/year, derive date from datetime where needed, drop
#                datetime/time
#   - method  -> keep LOD/LOQ, add limit_unit (the method's reporting unit)
# Already-folded raw columns (basis, qflag, vflag, dcflag) are dropped; the flags
# derived from them (weight_basis, below_loq, src_flag) and everything the later
# Clean / Annotate steps need are kept.
#
# ICES-DOME is the naming reference, so its maps are identity; the five sources
# differed only in the handful of parameters below, so the body is shared.

clean_harmonise_spec <- function(source) {
  switch(
    source,
    # depths in metres (confirmed: 0.01-2 m slices)
    "ices-dome" = list(depth_to_cm = 100),
    # depths already in cm (0-49 cm); `method` carries lld rather than lod
    "mareano"   = list(depth_to_cm = 1, rename_lld = TRUE),
    # depths already in cm (0.5-200 cm); MUDAB is German-operated
    "mudab"     = list(depth_to_cm = 1, country = "Germany"),
    # depths already in cm (0-20 cm)
    "4demon"    = list(depth_to_cm = 1),
    # depths are cm but a corrupt tail is nulled; units carry a "C" before dw/ww
    "vannmiljo" = list(depth_to_cm = 1, depth_max_cm = 300,
                       unit_suffix = "\\s*(c\\s+)?(dw|ww)\\b.*$"),
    stop("No clean-harmonise spec for source ", sQuote(source), call. = FALSE)
  )
}

# TOC / TOC63 -> CORG unification. A no-op for ICES (it has no TOC); the other
# sources map TOC -> CORG and keep TOC63. Chemistry symbols are already ICES.
harmonise_symbol <- function(sym) {
  s <- str_to_upper(str_trim(sym))
  recode(s, "TOC" = "CORG")
}

harmonise_unit <- function(u, suffix = "\\s*(dw|ww)\\b.*$") {
  u |>
    str_trim() |>
    str_replace_all("\u00b5|\u03bc", "u") |>          # micro sign / greek mu -> u
    str_remove(regex(suffix, ignore_case = TRUE)) |>  # drop the weight-basis suffix
    str_trim()
}

clean_harmonise <- function(source, db_dir = multised_db_dir(), verbose = TRUE) {
  check_source(source)
  spec <- clean_harmonise_spec(source)
  DEPTH_TO_CM <- spec$depth_to_cm

  clean_path <- clean_db_path(source, db_dir)

  # ── 1. Read slim tables ────────────────────────────────────────────────────
  scon <- slim_con(source, db_dir)
  element     <- dbReadTable(scon, "element")     |> as_tibble()
  dataset     <- dbReadTable(scon, "dataset")     |> as_tibble()
  site        <- dbReadTable(scon, "site")        |> as_tibble()
  event       <- dbReadTable(scon, "event")       |> as_tibble()
  method      <- dbReadTable(scon, "method")      |> as_tibble()
  subsample   <- dbReadTable(scon, "subsample")   |> as_tibble()
  measurement <- dbReadTable(scon, "measurement") |> as_tibble()
  dbDisconnect(scon)

  # ── 2. Harmonisation maps ──────────────────────────────────────────────────
  unit_suffix <- spec$unit_suffix %||% "\\s*(dw|ww)\\b.*$"

  element     <- element     |> mutate(symbol = harmonise_symbol(symbol))
  measurement <- measurement |> mutate(symbol = harmonise_symbol(symbol),
                                       unit   = harmonise_unit(unit, unit_suffix))
  method      <- method      |> mutate(symbol = harmonise_symbol(symbol))

  # Mareano's slim `method` carries the collapsed representative limit as `lld`.
  if (isTRUE(spec$rename_lld) && "lld" %in% names(method)) {
    method <- method |> rename(lod = lld)
  }

  # ── 3. Depth -> cm ─────────────────────────────────────────────────────────
  if (!is.null(spec$depth_max_cm)) {
    # Vannmiljo has a corrupt tail: depths beyond the plausible maximum, inverted
    # intervals, or negatives. They are nulled and marked rather than kept.
    DEPTH_MAX_CM <- spec$depth_max_cm
    n_bad <- with(subsample,
      sum(depth_to > DEPTH_MAX_CM | depth_from > depth_to | depth_from < 0, na.rm = TRUE))
    subsample <- subsample |>
      mutate(depth_from = depth_from * DEPTH_TO_CM,
             depth_to   = depth_to   * DEPTH_TO_CM,
             bad_depth  = coalesce(depth_to > DEPTH_MAX_CM | depth_from > depth_to | depth_from < 0, FALSE),
             depth_flag = if_else(bad_depth, "implausible", NA_character_),
             depth_from = if_else(bad_depth, NA_real_, depth_from),
             depth_to   = if_else(bad_depth, NA_real_, depth_to)) |>
      select(-bad_depth)
    if (verbose) cat("Vannmiljo depths nulled as implausible:", n_bad, "\n")
  } else {
    subsample <- subsample |>
      mutate(depth_from = depth_from * DEPTH_TO_CM,
             depth_to   = depth_to   * DEPTH_TO_CM)
  }

  # ── 4. Event: date from datetime, drop datetime/time ───────────────────────
  if (!"date" %in% names(event) && "datetime" %in% names(event)) {
    event$date <- substr(as.character(event$datetime), 1, 10)
  } else if ("datetime" %in% names(event) && "date" %in% names(event)) {
    event$date <- coalesce(event$date, substr(as.character(event$datetime), 1, 10))
  }
  event <- event |> select(-any_of(c("datetime", "time")))

  # ── 5. Method: LOD/LOQ reporting unit ──────────────────────────────────────
  # lod/loq are in the reporting unit of the method's measurements. A few methods
  # span two units (e.g. ug/g + ug/kg); limit_unit takes the modal one (documented
  # approximation, mirrors how slim step 11 converted limits per measurement).
  limit_unit <- measurement |>
    filter(!is.na(unit)) |>
    count(method_id, unit) |>
    group_by(method_id) |>
    slice_max(n, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(method_id, limit_unit = unit)
  method <- method |> left_join(limit_unit, by = "method_id")

  # ── 6. Column selection (drop already-folded raw columns) ──────────────────
  element <- apply_element_meta(element)   # rename element->name, add canonical name + cas
  dataset <- if (!is.null(spec$country)) {
    standardise_dataset(mutate(dataset, country = spec$country))
  } else {
    standardise_dataset(dataset)           # uniform columns + url / accessed / source_type
  }
  site      <- standardise_site(site)      # uniform columns (adds depth where absent)
  event     <- standardise_event(event)    # short tool names + drop multi_flag / tool_description
  subsample <- standardise_subsample(subsample)    # common column set + order
  method    <- standardise_method(method, element) # ICES vocab, drop grain-size methods, lod/loq -> mg/kg
  measurement <- measurement |> select(any_of(c(
    "measurement_id", "subsample_id", "symbol", "value", "unit",
    "value_std", "unit_std", "value_std_corr", "gs_corr", "matrix", "fraction_range",
    "uncrt", "metcu", "method_id",
    "invalid_flag", "dup_flag", "below_loq", "below_loq_num",
    "range_flag", "weight_basis", "src_flag")))
  measurement <- standardise_matrix(measurement)   # matrix -> ICES SED* vocab

  # ── 7. Write clean DB ──────────────────────────────────────────────────────
  if (file.exists(clean_path)) invisible(file.remove(clean_path))
  ccon <- multised_con(clean_path, must_exist = FALSE)
  on.exit(dbDisconnect(ccon), add = TRUE)
  tbls <- list(element = element, dataset = dataset, site = site, event = event,
               method = method, subsample = subsample, measurement = measurement)
  for (nm in names(tbls)) dbWriteTable(ccon, nm, tbls[[nm]], overwrite = TRUE)
  for (ix in c("CREATE UNIQUE INDEX ix_element_pk ON element(symbol)",
               "CREATE UNIQUE INDEX ix_measurement_pk ON measurement(measurement_id)",
               "CREATE INDEX ix_measurement_ss ON measurement(subsample_id)",
               "CREATE INDEX ix_subsample_ev ON subsample(event_id)")) {
    dbExecute(ccon, ix)
  }

  # ── 8. Verify ──────────────────────────────────────────────────────────────
  counts <- data.frame(
    table = dbListTables(ccon),
    rows  = vapply(dbListTables(ccon),
                   function(t) dbGetQuery(ccon, paste0("SELECT COUNT(*) FROM ", t))[[1]],
                   numeric(1)),
    row.names = NULL)
  depths <- dbGetQuery(ccon, "SELECT ROUND(MIN(depth_from),1) dmin, ROUND(MAX(depth_to),1) dmax FROM subsample")
  symbols <- dbGetQuery(ccon, "SELECT DISTINCT m.symbol FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category IN ('target','reference','organic') ORDER BY m.symbol")
  limits <- dbGetQuery(ccon, "SELECT COALESCE(limit_unit,'(none)') limit_unit, COUNT(*) n FROM method GROUP BY limit_unit ORDER BY n DESC")

  if (verbose) {
    cat("Tables written to", clean_path, ":\n")
    for (i in seq_len(nrow(counts))) {
      cat(sprintf("  %-12s %d rows\n", counts$table[i], counts$rows[i]))
    }
    cat("\ndepth range now (cm):\n");        print(depths)
    cat("\nchemistry symbols:\n");           print(symbols)
    cat("\nlimit_unit coverage (methods):\n"); print(limits)
  }
  invisible(list(counts = counts, depths = depths,
                 symbols = symbols, limit_unit = limits))
}
