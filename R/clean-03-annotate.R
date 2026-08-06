# ── Clean step 3: annotate ───────────────────────────────────────────────────
# Operates on the clean database after steps 1 and 2. Splits the grain-size
# composition out of `measurement` and annotates the sediment fraction:
#
#   measurement          all chemistry (target + reference + organic). The raw ICES
#                        `matrix` gains user-facing frac_class ('bulk'/'sieved') +
#                        sieve_um; matrix is kept as provenance.
#   subsample            a fraction summary of the TARGET measurements only,
#                        target_frac_class ('bulk' / 'sieved' / 'mixed') +
#                        target_sieve_um; plus fines_lt63 / fines_basis from slim
#                        step 15. NULL where no target chemistry.
#   grain_size_fraction  one row per grain-size mass-fraction measurement, with
#                        parsed size bounds. Not built for 4Demon, which has no
#                        grain-size at all.
#
# The core is shared. What differs per source is only how a grain-size symbol maps
# to size bounds, because each source encodes grain-size differently -- the same
# reason slim step 15 is source-specific.

# ── ICES-DOME / MUDAB: cumulative GSMF codes on a matrix ─────────────────────
# Size bounds (um): GSMF<n> = 0..n, GSMF>n = n..inf, GS>a<b = a..b. Grain-size
# statistics (GSMEA/GSMED/GSSORT/...) are not fractions and are excluded.
clean_gsf_ices <- function(comp) {
  lo_um <- function(s) case_when(
    str_detect(s, "^GSMF[0-9]+$")     ~ 0,
    !is.na(str_match(s, "^GSMF>([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GSMF>([0-9]+)$")[, 2]),
    !is.na(str_match(s, "^GS>([0-9]+)<[0-9]+$")[, 2]) ~ as.numeric(str_match(s, "^GS>([0-9]+)<[0-9]+$")[, 2]),
    TRUE ~ NA_real_)
  hi_um <- function(s) case_when(
    !is.na(str_match(s, "^GSMF([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GSMF([0-9]+)$")[, 2]),
    str_detect(s, "^GSMF>[0-9]+$")    ~ NA_real_,
    !is.na(str_match(s, "^GS>[0-9]+<([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GS>[0-9]+<([0-9]+)$")[, 2]),
    TRUE ~ NA_real_)

  fraction <- comp |>
    filter(str_detect(symbol, "^GSMF|^GS>"),
           is.na(gs_corr) | gs_corr != "invalid",
           !is.na(value_std_corr)) |>
    transmute(subsample_id, symbol, matrix,
              lo_um = lo_um(symbol), hi_um = hi_um(symbol),
              value_pct = value_std_corr)

  # Keep only fractions of subsamples whose grain-size curve has a classifiable
  # (bulk/sieved) matrix: bulk if any whole/coarse matrix (SEDtot, or a cutoff
  # >= 1000 um), sieved if only fine matrices, unknown otherwise (dropped).
  mcut <- function(mx) suppressWarnings(as.numeric(sub("^SED", "", mx)))  # SEDtot -> NA
  class_ss <- comp |>
    mutate(cut = mcut(matrix),
           is_bulk   = matrix == "SEDtot" | (!is.na(cut) & cut >= 1000),
           is_sieved = !is.na(cut) & cut < 1000) |>
    group_by(subsample_id) |>
    summarise(frac_class = case_when(any(is_bulk, na.rm = TRUE)   ~ "bulk",
                                      any(is_sieved, na.rm = TRUE) ~ "sieved",
                                      TRUE                         ~ "unknown"),
              .groups = "drop") |>
    filter(frac_class != "unknown")

  fraction |> semi_join(class_ss, by = "subsample_id")
}

# ── Mareano: four named bins, no matrix ──────────────────────────────────────
clean_gsf_mareano <- function(comp) {
  bin_bounds <- tibble::tribble(
    ~symbol,   ~lo_um, ~hi_um,
    "CLAY",     0,      2,
    "SILT",     2,      63,
    "SAND",     63,     2000,
    "GRAVEL",   2000,   NA)
  comp |>
    filter(symbol %in% bin_bounds$symbol, !is.na(value_std)) |>
    left_join(bin_bounds, by = "symbol") |>
    transmute(subsample_id, symbol, matrix = NA_character_,
              lo_um, hi_um, value_pct = value_std)
}

# ── Vannmiljo: its own code set, no matrix ───────────────────────────────────
# FINS -> 0..63; GSMF_<n> -> n..inf; GSMF<a>_<b> -> a..b; GSMF<n> -> 0..n.
# Note the naming trap: Vannmiljo's GSMF_63 means ">63 um", the opposite of the
# ICES GSMF63.
clean_gsf_vannmiljo <- function(comp) {
  gt_n  <- function(s) as.numeric(str_match(s, "^GSMF_([0-9]+)$")[, 2])   # >n
  bin_a <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)_([0-9]+)$")[, 2])
  bin_b <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)_([0-9]+)$")[, 3])
  lt_n  <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)$")[, 2])    # <n

  value_gs <- if ("value_std_corr" %in% names(comp)) comp$value_std_corr else comp$value_std
  gs_corr  <- if ("gs_corr" %in% names(comp)) comp$gs_corr else NA_character_

  comp |>
    mutate(value_pct = value_gs, gs_corr = gs_corr) |>
    filter(str_detect(symbol, "^FINS$|^GSMF"),
           is.na(gs_corr) | gs_corr != "invalid",
           !is.na(value_pct)) |>
    mutate(
      lo_um = case_when(symbol == "FINS"        ~ 0,
                        !is.na(gt_n(symbol))     ~ gt_n(symbol),
                        !is.na(bin_a(symbol))    ~ bin_a(symbol),
                        !is.na(lt_n(symbol))     ~ 0,
                        TRUE ~ NA_real_),
      hi_um = case_when(symbol == "FINS"        ~ 63,
                        !is.na(gt_n(symbol))     ~ NA_real_,
                        !is.na(bin_b(symbol))    ~ bin_b(symbol),
                        !is.na(lt_n(symbol))     ~ lt_n(symbol),
                        TRUE ~ NA_real_)) |>
    transmute(subsample_id, symbol, matrix = NA_character_, lo_um, hi_um, value_pct)
}

# Which grain-size builder a source uses, and how it detects that the step has
# already run. The guard differs by what each source actually has:
#   - ices-dome / mudab : the value_std_corr column (dropped by this step)
#   - 4demon            : the fraction_range column (it has no grain-size at all,
#                         so no composition rows to count, and no value_std_corr)
#   - mareano / vannmiljo : composition rows remaining in measurement. Mareano has
#                         no value_std_corr at all (it has no slim step 14), so a
#                         column guard there would fire on a perfectly fresh DB.
clean_annotate_spec <- function(source) {
  switch(
    source,
    "ices-dome" = list(gsf = clean_gsf_ices,      guard = "column:value_std_corr"),
    "mudab"     = list(gsf = clean_gsf_ices,      guard = "column:value_std_corr"),
    "mareano"   = list(gsf = clean_gsf_mareano,   guard = "composition_rows"),
    "vannmiljo" = list(gsf = clean_gsf_vannmiljo, guard = "composition_rows"),
    "4demon"    = list(gsf = NULL,                guard = "column:fraction_range"),
    stop("No clean-annotate spec for source ", sQuote(source), call. = FALSE)
  )
}

# Returns NULL if the step may proceed, else the reason it may not.
clean_annotate_blocked <- function(guard, m, element) {
  if (identical(guard, "composition_rows")) {
    comp_n <- m |>
      left_join(element |> select(symbol, category), by = "symbol") |>
      filter(category == "composition") |>
      nrow()
    if (comp_n == 0) return("no composition rows")
    return(NULL)
  }
  col <- sub("^column:", "", guard)
  if (!col %in% names(m)) return(paste0("no ", col))
  NULL
}

clean_annotate <- function(source, db_dir = multised_db_dir(), verbose = TRUE) {
  check_source(source)
  spec <- clean_annotate_spec(source)
  chem_cats <- c("target", "reference", "organic")

  con <- multised_con(clean_db_path(source, db_dir))
  on.exit(dbDisconnect(con), add = TRUE)

  element   <- dbReadTable(con, "element")     |> as_tibble()
  subsample <- dbReadTable(con, "subsample")   |> as_tibble()
  m         <- dbReadTable(con, "measurement") |> as_tibble()

  blocked <- clean_annotate_blocked(spec$guard, m, element)
  if (!is.null(blocked)) {
    stop("measurement: ", blocked, " -- it looks already annotated. ",
         "Re-run steps 1-3 on a fresh clean DB.", call. = FALSE)
  }

  # ── 1. grain_size_fraction (sources with grain-size only) ──────────────────
  fraction <- NULL
  if (!is.null(spec$gsf)) {
    comp <- m |>
      left_join(element |> select(symbol, category), by = "symbol") |>
      filter(category == "composition")
    fraction <- spec$gsf(comp)
  }

  # ── 2. Rebuild measurement + fraction annotation ───────────────────────────
  # Chemistry was collapsed in step 2. Convert the raw ICES `matrix` into
  # user-facing frac_class + sieve_um, keeping matrix as provenance. All chemistry
  # stays in one measurement table.
  chem <- m
  if (!"category" %in% names(chem)) {
    chem <- chem |> left_join(element |> select(symbol, category), by = "symbol")
  }
  measurement <- chem |> filter(category %in% chem_cats) |> apply_fraction() |>
    select(all_of(MEASUREMENT_COLS))

  # subsample: fraction summary of the TARGET measurements (bulk / sieved / mixed)
  # + target_sieve_um; fines_lt63 / fines_basis is already present (slim step 15).
  subsample <- attach_subsample_fraction(subsample, measurement, element) |>
    standardise_subsample()

  # ── 3. Write back ──────────────────────────────────────────────────────────
  dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
  dbWriteTable(con, "subsample",   subsample,   overwrite = TRUE)
  if (!is.null(fraction)) {
    fraction <- fraction |> mutate(gsf_id = row_number(), .before = 1)  # surrogate PK
    dbWriteTable(con, "grain_size_fraction", fraction, overwrite = TRUE)
    invisible(dbExecute(con, "DROP TABLE IF EXISTS grain_size"))      # folded onto subsample
    invisible(dbExecute(con, "DROP TABLE IF EXISTS organic_carbon"))  # merged into measurement
    for (ix in c("CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)",
                 "CREATE INDEX        IF NOT EXISTS ix_gsf_ss  ON grain_size_fraction(subsample_id)",
                 "CREATE UNIQUE INDEX IF NOT EXISTS ix_gsf_pk  ON grain_size_fraction(gsf_id)")) {
      invisible(dbExecute(con, ix))
    }
  } else {
    invisible(dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)"))
    invisible(dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_meas_ss ON measurement(subsample_id)"))
  }

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  n_meas <- dbGetQuery(con, "SELECT COUNT(*) n FROM measurement")$n
  frac_class <- dbGetQuery(con, "SELECT COALESCE(frac_class,'(NULL)') frac_class, COUNT(*) n FROM measurement GROUP BY frac_class ORDER BY n DESC")
  target_class <- dbGetQuery(con, "SELECT COALESCE(target_frac_class,'(NULL)') target_frac_class, COUNT(*) n FROM subsample GROUP BY target_frac_class ORDER BY n DESC")
  n_comp_left <- dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category='composition'")$n

  if (verbose) {
    cat("measurement (all chemistry):", n_meas, "rows\n")
    cat("measurement frac_class:\n");        print(frac_class)
    cat("subsample target_frac_class:\n");   print(target_class)
    if (!is.null(fraction)) {
      cat("grain_size_fraction rows:", nrow(fraction),
          "| distinct subsamples:", n_distinct(fraction$subsample_id), "\n")
    }
    cat("composition left in measurement (should be 0):", n_comp_left, "\n")
  }
  invisible(list(n_measurement = n_meas, frac_class = frac_class,
                 target_frac_class = target_class,
                 n_grain_size_fraction = if (is.null(fraction)) 0L else nrow(fraction),
                 n_composition_left = n_comp_left))
}
