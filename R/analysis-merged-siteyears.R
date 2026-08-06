# ── Analysis, merged generation: siteyears ───────────────────────────────
# Converted from R/analysis/siteyears/01_merged_siteyears.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_siteyears <- function(db_dir = multised_db_dir(),
                                      out_dir = multised_analysis_dir(),
                                      verbose = TRUE) {
  # ── Analysis stage, repeat-sampled locations over years (MERGED database) ─────
  # A location-controlled companion to 01_merged_temporal.R. The temporal page
  # pools every bulk measurement against its sampling year, so "year" is confounded
  # with WHERE and HOW the pooled sources sampled over time (station mix, gear, lab,
  # which source owns which decade). Here we instead keep only locations that were
  # sampled in MORE THAN ONE year and measure the trend WITHIN each location, so the
  # spatial signal is (largely) differenced out and what remains is closer to a real
  # temporal change at a fixed place.
  #
  # A "location" is a grid cell: latitude/longitude rounded to GRID_DP decimals
  # (2 dp ~= 1.1 km; 1 dp ~= 11 km). Coarser than the 3 dp site key so nearby
  # revisits of the same station group together. Cells with >= MIN_YEARS distinct
  # years and >= MIN_OBS bulk measurements are kept.
  #
  # Three questions, bulk samples, outliers dropped:
  #  (A) within-cell trend: Spearman rho of value_std vs year inside each cell, then
  #      the distribution of those rhos per element (median, fraction rising vs
  #      declining, sign test). At a fixed location, are metals trending over time?
  #  (B) does the trend survive normalisation: the same within-cell rho on the
  #      metal / Fe enrichment ratio (Fe measured in the same subsample).
  #  (C) pooled location-anomaly series: express each measurement as a log10
  #      deviation from its own cell's median, then take the yearly median anomaly
  #      per element. This is the overall temporal drift with location removed.
  #
  # Caveats: still observational and unbalanced (a cell can hold a few sub-stations,
  # and its year coverage is whatever the sources happened to sample); differencing
  # location does not difference out changes in gear/lab within a cell. Associations,
  # not controlled trends.
  #
  # Outputs -> data/analysis/siteyears/ (gitignored):
  #   merged_siteyears_trends.csv   (A)/(B) per-element rho distribution summary
  #   merged_siteyears_cells.csv    per cell x element rho (for the distribution figure)
  #   merged_siteyears_pooled.csv   (C) yearly median cell-anomaly per element
  #   merged_siteyears_meta.csv     one-row cohort description (grid, cells, coverage)

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)

  TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  GRID_DP   <- 2L    # lat/lon rounding for the location cell (~1.1 km); 1L ~= 11 km
  MIN_YEARS <- 3L    # a cell must span at least this many distinct years
  MIN_OBS   <- 8L    # ... and hold at least this many measurements of the element
  MIN_CELLS <- 10L   # only summarise an element with at least this many cells
  elem_levels <- TARGETS

  out_dir <- file.path(out_dir, "siteyears")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # within-cell Spearman rho of `yvar` vs year, per cell x element, on cells that
  # meet the coverage bar (>= MIN_YEARS distinct years, >= MIN_OBS rows)
  cell_rho <- function(df, yvar) {
    df |>
      filter(!is.na(.data[[yvar]]), is.finite(.data[[yvar]]), .data[[yvar]] > 0,
             !is.na(year)) |>
      group_by(symbol, cell) |>
      filter(n() >= MIN_OBS, n_distinct(year) >= MIN_YEARS) |>
      summarise(nyear = n_distinct(year),
                span  = max(year) - min(year),
                n     = n(),
                rho   = cor(year, .data[[yvar]], method = "spearman"),
                .groups = "drop") |>
      filter(!is.na(rho))
  }

  # collapse a set of per-cell rhos to one summary row per element
  summarise_rho <- function(cells, measure_lab) {
    cells |>
      group_by(symbol) |>
      filter(n() >= MIN_CELLS) |>
      summarise(measure       = measure_lab,
                n_cells       = n(),
                median_rho    = round(median(rho), 3),
                frac_declining = round(mean(rho < 0), 3),
                frac_rising    = round(mean(rho > 0), 3),
                median_span    = median(span),
                median_n_cell  = median(n),
                # two-sided sign test: is rising as common as declining?
                p_sign = signif(binom.test(sum(rho > 0),
                                           sum(rho != 0))$p.value, 3),
                .groups = "drop")
  }

  # ── 1. Build per-subsample chemistry + year + location, bulk, outliers dropped ─
  con <- dbConnect(SQLite(), db_path)

  meas <- dbGetQuery(con, sprintf("
    SELECT m.subsample_id, m.source AS Source, m.symbol, m.value_std,
           e.year, si.latitude, si.longitude
    FROM measurement m
    JOIN subsample s ON s.subsample_id = m.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    WHERE m.frac_class = 'bulk' AND m.value_std > 0 AND m.outlier_flag IS NULL
      AND e.year IS NOT NULL
      AND m.symbol IN (%s)
  ", paste(sprintf("'%s'", c(TARGETS, NORMALISERS)), collapse = ", "))) |>
    as_tibble()
  dbDisconnect(con)

  # one value per subsample x symbol, then wide (for the metal / Fe ratio)
  agg <- meas |>
    group_by(subsample_id, symbol) |>
    summarise(value_std = mean(value_std),
              year = first(year), latitude = first(latitude),
              longitude = first(longitude), .groups = "drop")

  wide <- agg |>
    select(subsample_id, symbol, value_std, year, latitude, longitude) |>
    pivot_wider(names_from = symbol, values_from = value_std)
  for (s in c(TARGETS, NORMALISERS)) if (!s %in% names(wide)) wide[[s]] <- NA_real_

  wide <- wide |>
    mutate(cell = paste(round(latitude, GRID_DP), round(longitude, GRID_DP)))

  # ── 2. (A) within-cell trend of the raw value ────────────────────────────────
  val_long <- wide |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std)) |>
    mutate(symbol = factor(symbol, levels = elem_levels))

  val_cells <- cell_rho(val_long, "value_std") |>
    mutate(measure = "value")

  # ── 3. (B) within-cell trend of the metal / Fe enrichment ratio ──────────────
  enr_long <- wide |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std), !is.na(FE), FE > 0) |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           ratio_FE = value_std / FE)

  enr_cells <- cell_rho(enr_long, "ratio_FE") |>
    mutate(measure = "enrich_FE")

  cells_out <- bind_rows(val_cells, enr_cells) |>
    mutate(symbol = as.character(symbol)) |>
    select(symbol, measure, cell, nyear, span, n, rho) |>
    mutate(rho = round(rho, 3)) |>
    arrange(measure, symbol, desc(n))

  trends <- bind_rows(summarise_rho(val_cells, "value"),
                      summarise_rho(enr_cells, "enrich_FE")) |>
    mutate(symbol = as.character(symbol)) |>
    select(symbol, measure, n_cells, median_rho, frac_declining, frac_rising,
           median_span, median_n_cell, p_sign) |>
    arrange(measure, symbol)

  # ── 4. (C) pooled location-anomaly series ────────────────────────────────────
  # within each qualifying cell x element, centre log10(value) on the cell median,
  # then take the yearly median of that anomaly across all cells. Removes the mean
  # level of each place, leaving the shared temporal drift.
  anomaly <- val_long |>
    group_by(symbol, cell) |>
    filter(n() >= MIN_OBS, n_distinct(year) >= MIN_YEARS) |>
    mutate(lval = log10(value_std),
           anom = lval - median(lval)) |>
    ungroup()

  pooled <- anomaly |>
    group_by(symbol, year) |>
    summarise(n = n(), n_cells = n_distinct(cell),
              median_anom = round(median(anom), 4), .groups = "drop") |>
    filter(n >= 10) |>
    mutate(symbol = as.character(symbol)) |>
    arrange(symbol, year)

  # ── 5. Cohort description (one row) ──────────────────────────────────────────
  n_cells_total <- n_distinct(wide$cell)
  multi_cells   <- val_long |> group_by(cell) |>
    summarise(ny = n_distinct(year), .groups = "drop") |> filter(ny >= MIN_YEARS)
  meta <- tibble(
    grid_dp        = GRID_DP,
    grid_km        = if (GRID_DP == 2L) 1.1 else if (GRID_DP == 1L) 11 else NA_real_,
    min_years      = MIN_YEARS,
    min_obs        = MIN_OBS,
    cells_total    = n_cells_total,
    cells_multiyear = nrow(multi_cells),
    cells_used_value = n_distinct(val_cells$cell),
    meas_in_cohort   = nrow(anomaly))

  # ── 6. Write outputs ─────────────────────────────────────────────────────────
  write_csv(trends,  file.path(out_dir, "merged_siteyears_trends.csv"))
  write_csv(cells_out, file.path(out_dir, "merged_siteyears_cells.csv"))
  write_csv(pooled,  file.path(out_dir, "merged_siteyears_pooled.csv"))
  write_csv(meta,    file.path(out_dir, "merged_siteyears_meta.csv"))

  if (verbose) {
    # ── 7. Console summary ───────────────────────────────────────────────────────
    cat("merged site-years analysis written to", out_dir, "\n\n")
    cat(sprintf("grid %d dp (~%.1f km): %d cells total, %d multi-year (>=%d yr)\n",
                GRID_DP, meta$grid_km, meta$cells_total, meta$cells_multiyear, MIN_YEARS))
    cat("\n(A)/(B) within-cell trend distribution per element:\n")
    trends |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
