# ── Clean step 2: clean ──────────────────────────────────────────────────────
# Operates on the clean database built by step 1. Removes chemistry measurements
# that failed QC, then collapses duplicates and averages technical replicates.
# Grain-size (composition) rows pass through untouched; their cleaning is the
# Annotate step. Rewrites the measurement table.
#
# Order: standardise uncertainty -> remove flagged rows -> collapse per occasion.
# Removal (chemistry only): range_flag, invalid_flag, below_loq / below_loq_num,
# weight_basis = 'wet', any src_flag (all source-specific QC failures).
# Collapse key = sampling occasion + element + method: site + date + depth +
# symbol + unit + method + lab (mirrors slim step 5). Within a group the distinct
# value_std values are the technical replicates (identical values are duplicates,
# counted once); one row is emitted with value_std = mean, value_sd = SD,
# n_rep = number of distinct values, value_uncrt = mean standardised uncertainty.
#
# Shared across all five sources. Everything that varied is decided from the
# columns actually present rather than from the source name:
#   - `lab` exists only for mareano / ices-dome / mudab
#   - `matrix` is absent for mareano / vannmiljo
#   - `fraction_range` exists only for 4demon, where it is a real part of the
#     collapse key (it separates sieved fractions). It is added to the key and to
#     the output ONLY when present, so the other four do not gain an all-NA column.

# TRUE/FALSE per row for a flag column that may not exist in this source.
col_or_false <- function(df, col, pred) {
  if (col %in% names(df)) pred(df[[col]]) else rep(FALSE, nrow(df))
}

clean_clean <- function(source, db_dir = multised_db_dir(), verbose = TRUE) {
  check_source(source)
  chem_cats <- c("target", "reference", "organic")

  con <- multised_con(clean_db_path(source, db_dir))
  on.exit(dbDisconnect(con), add = TRUE)

  element   <- dbReadTable(con, "element")     |> as_tibble()
  method    <- dbReadTable(con, "method")      |> as_tibble()
  event     <- dbReadTable(con, "event")       |> as_tibble()
  subsample <- dbReadTable(con, "subsample")   |> as_tibble()
  m         <- dbReadTable(con, "measurement") |> as_tibble()
  site      <- dbReadTable(con, "site")        |> as_tibble()

  # This step consumes the QC flag columns and collapses rows (one-way). The clean
  # steps run in sequence on a fresh DB: harmonise -> clean -> annotate. Guard
  # against an accidental second run, which would reset n_rep / value_sd.
  if (!"range_flag" %in% names(m)) {
    stop("measurement carries no QC flags -- it looks already cleaned. ",
         "Re-run step 1 (harmonise) to rebuild the clean DB before step 2.",
         call. = FALSE)
  }

  # ── 0. Remove out-of-scope sites (area_flag = 'outside_europe') and cascade ─
  # Consume the slim area_flag: drop sites outside Europe (e.g. a corrupt Vannmiljo
  # coordinate in the Gulf of Guinea) and their linked event / subsample /
  # measurement rows, then drop the area_flag column. No-op where nothing is flagged.
  pr <- consume_area_flag(site, event, subsample, m)
  site <- pr$site; event <- pr$event; subsample <- pr$subsample; m <- pr$measurement
  if (pr$n_sites && verbose) {
    cat(sprintf("removed %d outside_europe site(s): %d events, %d subsamples, %d measurements\n",
                pr$n_sites, pr$n_events, pr$n_subsamples, pr$n_measurements))
  }

  # ── 1. Standardise analytical uncertainty to mg/kg (value_uncrt) ───────────
  # ICES uncrt + metcu: '%' = percent (relative), 'SD' = 1 sigma (absolute),
  # 'U2' = expanded uncertainty, coverage factor 2 (so 1 sigma = U2 / 2). Reduce to
  # a 1-sigma value in the measurement's unit, then convert to mg/kg like value_std.
  mass_basis <- tibble::tribble(
    ~unit_canon, ~denom,
    "%", 1e2, "vol.%", 1e2, "wt.%", 1e2,
    "g/kg", 1e3, "g/kg c", 1e3, "mg/g", 1e3,
    "mg/kg", 1e6, "ug/g", 1e6, "ppm", 1e6,
    "ug/kg", 1e9, "ng/g", 1e9, "ppb", 1e9)
  canon_unit <- function(u) u |> str_to_lower() |> str_trim() |>
    str_remove("\\s*(dw|ww)$") |> str_replace_all("\u00b5|\u03bc", "u")

  has_uncrt <- all(c("uncrt", "metcu") %in% names(m))
  m <- m |> left_join(element |> select(symbol, category), by = "symbol")
  m$unit_canon <- canon_unit(m$unit)
  m <- m |> left_join(mass_basis, by = "unit_canon")
  m$value_uncrt <- NA_real_
  if (has_uncrt) {
    sigma <- with(m, case_when(
      is.na(uncrt)   ~ NA_real_,
      metcu == "%"   ~ uncrt / 100 * value,   # relative -> absolute in the unit
      metcu == "U2"  ~ uncrt / 2,             # expanded (k=2) -> 1 sigma
      metcu == "SD"  ~ uncrt,
      TRUE           ~ NA_real_))
    m$value_uncrt <- if_else(m$category %in% chem_cats & !is.na(m$denom),
                             sigma / m$denom * 1e6, NA_real_)
  }

  # ── 2. Remove failed-QC chemistry rows ─────────────────────────────────────
  chem <- m |> filter(category %in% chem_cats)
  comp <- m |> filter(!category %in% chem_cats)

  drop <-
    col_or_false(chem, "range_flag",    function(x) !is.na(x)) |
    col_or_false(chem, "invalid_flag",  function(x) !is.na(x)) |
    col_or_false(chem, "below_loq",     function(x) coalesce(x == 1L, FALSE)) |
    col_or_false(chem, "below_loq_num", function(x) coalesce(x == 1L, FALSE)) |
    col_or_false(chem, "weight_basis",  function(x) coalesce(x == "wet", FALSE)) |
    col_or_false(chem, "src_flag",      function(x) !is.na(x))
  n_before <- nrow(chem)
  chem <- chem[!drop, ]
  if (verbose) {
    cat(sprintf("chemistry rows: %d -> %d (removed %d failed-QC)\n",
                n_before, nrow(chem), sum(drop)))
  }

  # ── 3. Collapse duplicates + average technical replicates ──────────────────
  mcols <- intersect(c("method", "lab"), names(method))   # vannmiljo / 4demon have no lab
  mkey <- method |> select(method_id, all_of(mcols))
  grp <- chem |>
    left_join(subsample |> select(subsample_id, event_id, depth_from, depth_to),
              by = "subsample_id") |>
    left_join(event |> select(event_id, site_id, date), by = "event_id") |>
    left_join(mkey, by = "method_id")

  if (!"matrix" %in% names(grp)) grp$matrix <- NA_character_

  # fraction_range is part of the occasion only where the source records it.
  has_fr <- "fraction_range" %in% names(grp)
  grp_keys <- c("site_id", "date", "depth_from", "depth_to", "symbol", "unit",
                if (has_fr) "fraction_range", mcols)

  collapsed <- grp |>
    group_by(across(all_of(grp_keys))) |>
    summarise(
      measurement_id = first(measurement_id),
      subsample_id   = first(subsample_id),
      method_id      = first(method_id),
      matrix         = first(matrix),
      unit_std       = first(unit_std),
      # value_sd / n_rep MUST be computed before value_std is overwritten below,
      # else they would see the scalar mean instead of the original column.
      n_rep          = n_distinct(value_std),
      value_sd       = if (n_distinct(value_std) > 1) sd(unique(value_std)) else NA_real_,
      value          = mean(unique(value)),
      value_std      = mean(unique(value_std)),
      value_uncrt    = if (all(is.na(value_uncrt))) NA_real_ else mean(value_uncrt, na.rm = TRUE),
      .groups = "drop") |>
    select(measurement_id, subsample_id, symbol, value, unit, value_std, unit_std,
           value_sd, n_rep, value_uncrt, matrix,
           any_of("fraction_range"), method_id)

  if (verbose) {
    cat(sprintf("chemistry after collapse: %d rows (%d technical-replicate groups averaged)\n",
                nrow(collapsed), sum(collapsed$n_rep > 1)))
  }

  # ── 4. Rebuild measurement: cleaned chemistry + untouched composition ──────
  comp <- comp |>
    select(any_of(c("measurement_id", "subsample_id", "symbol", "value", "unit",
                    "value_std", "unit_std", "value_std_corr", "gs_corr",
                    "matrix", "fraction_range", "method_id")))
  measurement <- bind_rows(collapsed, comp)  # bind_rows fills absent columns with NA

  dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
  dbWriteTable(con, "site", site, overwrite = TRUE)          # area_flag consumed + dropped
  if (pr$n_sites) {                                          # cascade: rewrite the pruned subtree
    dbWriteTable(con, "event", event, overwrite = TRUE)
    dbWriteTable(con, "subsample", subsample, overwrite = TRUE)
    dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_subsample_ev ON subsample(event_id)")
  }
  invisible(dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS ix_measurement_pk ON measurement(measurement_id)"))
  invisible(dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_measurement_ss ON measurement(subsample_id)"))

  # ── 5. Verify ──────────────────────────────────────────────────────────────
  cols <- dbListFields(con, "measurement")
  counts <- dbGetQuery(con, "SELECT
      SUM(CASE WHEN e.category IN ('target','reference','organic') THEN 1 ELSE 0 END) chemistry,
      SUM(CASE WHEN e.category='composition' THEN 1 ELSE 0 END) grain_size,
      COUNT(*) total
    FROM measurement m JOIN element e ON m.symbol=e.symbol")
  reps <- dbGetQuery(con, "SELECT n_rep, COUNT(*) groups FROM measurement WHERE n_rep>1 GROUP BY n_rep ORDER BY n_rep LIMIT 8")
  n_uncrt <- dbGetQuery(con, "SELECT COUNT(*) n FROM measurement WHERE value_uncrt IS NOT NULL")$n

  if (verbose) {
    cat("\nmeasurement columns:\n"); print(cols)
    cat("\nrow counts:\n");          print(counts)
    cat("\naveraged replicates (n_rep>1):\n"); print(reps)
    cat("\nvalue_uncrt present (chemistry):", n_uncrt, "\n")
  }
  invisible(list(columns = cols, counts = counts,
                 replicates = reps, n_uncrt = n_uncrt))
}
