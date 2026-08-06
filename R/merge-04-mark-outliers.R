# ── Merge step 4: mark distributional outliers ───────────────────────────────
# Adds a soft `outlier_flag` ('high' / 'low' / NULL) to the merged measurement
# table: a review-not-delete marker complementing the physical range_flag.
#
# Dual criterion per element x fraction on log10(value_std), chemistry only:
#   * robust z: |value - median| > K_FLAG * MAD, on the log scale
#   * order of magnitude: |log10(value / median)| > MIN_OOM
#     Effective boundary = median +/- max(K_FLAG * MAD, MIN_OOM).
#   * small-n guard: groups below MIN_N are left NULL (robust stats unreliable,
#     e.g. Iodine); those still carry the generous range_flag.
#   * region is NOT stratified: regional spread (~2x) is trivial next to the
#     10-1000x errors this targets.
#
# Idempotent and re-runnable.
#
# Also writes the website summary CSVs read by the multised-merged "Outlier
# Flagging" page (as step 2 writes merge_dedup.csv):
#   merge_outlier_summary.csv   element x fraction: median, thresholds, hi/lo counts
#   merge_outlier_hist.csv      binned log10(value_std) per element x fraction
#   merge_outlier_examples.csv  the flagged rows with fold-vs-median + location

merge_mark_outliers <- function(db_dir = multised_db_dir(),
                                analysis_dir = multised_analysis_dir(),
                                verbose = TRUE) {
  # ── 0. Config ──────────────────────────────────────────────────────────────
  MIN_N     <- 100L                          # min group size to compute a threshold
  K_FLAG    <- 4                             # robust-z multiplier
  MIN_OOM   <- 1.0                           # min |log10(value/median)|
  FRACTIONS <- c("bulk", "sieved63", "sieved20")
  CHEM      <- c("target", "reference", "organic")

  con <- multised_con(merged_db_path(db_dir))
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Chemistry measurements + their category and fraction ────────────────
  m <- dbGetQuery(con, "
    SELECT m.measurement_id, m.symbol, m.value_std, e.category,
           m.frac_class, m.sieve_um_std
    FROM measurement m JOIN element e ON e.symbol = m.symbol") |>
    as_tibble()

  d <- m |>
    mutate(
      fraction = case_when(
        frac_class == "bulk"                        ~ "bulk",
        frac_class == "sieved" & sieve_um_std == 63 ~ "sieved63",
        frac_class == "sieved" & sieve_um_std == 20 ~ "sieved20",
        TRUE                                        ~ "other"),
      logv = if_else(category %in% CHEM & value_std > 0, log10(value_std),
                     NA_real_))

  # ── 2. Robust per element x fraction statistics ────────────────────────────
  grp <- d |>
    filter(category %in% CHEM, fraction %in% FRACTIONS, !is.na(logv)) |>
    group_by(symbol, fraction) |>
    summarise(n = n(), med_log = median(logv), mad_log = stats::mad(logv),
              .groups = "drop") |>
    mutate(enough = n >= MIN_N & mad_log > 0)

  # ── 3. Dual-criterion flag per measurement ─────────────────────────────────
  flagged <- d |>
    inner_join(grp |> filter(enough) |> select(symbol, fraction, med_log, mad_log),
               by = c("symbol", "fraction")) |>
    filter(!is.na(logv)) |>
    mutate(z   = (logv - med_log) / mad_log,
           oom = logv - med_log,
           outlier_flag = case_when(
             abs(z) > K_FLAG & oom >  MIN_OOM ~ "high",
             abs(z) > K_FLAG & oom < -MIN_OOM ~ "low",
             TRUE                             ~ NA_character_)) |>
    filter(!is.na(outlier_flag)) |>
    select(measurement_id, outlier_flag)

  # ── 4. Add outlier_flag column (idempotent) + write back ───────────────────
  # NULL = in-distribution, not chemistry, unbounded/small-n group, or no value.
  if (!"outlier_flag" %in% dbListFields(con, "measurement")) {
    dbExecute(con, "ALTER TABLE measurement ADD COLUMN outlier_flag TEXT;")
  } else {
    dbExecute(con, "UPDATE measurement SET outlier_flag = NULL;")   # reset on re-run
  }

  dbWriteTable(con, "qc_outlier", as.data.frame(flagged),
               temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX ix_qc_outlier ON qc_outlier(measurement_id);")
  dbExecute(con, "
    UPDATE measurement
    SET outlier_flag = (SELECT outlier_flag FROM qc_outlier q
                        WHERE q.measurement_id = measurement.measurement_id)
    WHERE measurement_id IN (SELECT measurement_id FROM qc_outlier);")
  dbExecute(con, "DROP TABLE qc_outlier;")

  # ── 5. Website summary CSVs ────────────────────────────────────────────────
  out_dir <- file.path(analysis_dir, "merge")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  usable <- grp |> filter(enough) |> select(symbol, fraction)

  # per element x fraction: robust thresholds (mg/kg) + flag counts
  counts <- d |>
    inner_join(usable, by = c("symbol", "fraction")) |>
    left_join(flagged, by = "measurement_id") |>
    filter(!is.na(outlier_flag)) |>
    count(symbol, fraction, outlier_flag) |>
    pivot_wider(names_from = outlier_flag, values_from = n, values_fill = 0)
  for (cc in c("high", "low")) if (!cc %in% names(counts)) counts[[cc]] <- 0L

  summary_out <- grp |> filter(enough) |>
    left_join(distinct(d, symbol, category), by = "symbol") |>
    mutate(half       = pmax(K_FLAG * mad_log, MIN_OOM),
           median_val = round(10^med_log, 3),
           thr_lo     = round(10^(med_log - half), 3),
           thr_hi     = round(10^(med_log + half), 3),
           mad_log    = round(mad_log, 3)) |>
    left_join(counts, by = c("symbol", "fraction")) |>
    mutate(n_high = coalesce(high, 0L), n_low = coalesce(low, 0L)) |>
    select(category, symbol, fraction, n, median_val, mad_log,
           thr_lo, thr_hi, n_high, n_low) |>
    arrange(category, symbol, fraction)
  write_csv(summary_out, file.path(out_dir, "merge_outlier_summary.csv"))

  # binned log10 distribution for the density facets (bin width 0.1)
  hist_out <- d |>
    inner_join(usable, by = c("symbol", "fraction")) |>
    filter(!is.na(logv)) |>
    mutate(bin = round(logv / 0.1) * 0.1) |>
    count(category, symbol, fraction, bin)
  write_csv(hist_out, file.path(out_dir, "merge_outlier_hist.csv"))

  # the flagged rows with context, most-extreme first (illustrative examples)
  ex_ctx <- dbGetQuery(con, "
    SELECT m.measurement_id, m.symbol, m.value_std, m.frac_class, m.sieve_um_std,
           m.source, si.sea_name, si.country,
           si.latitude AS lat, si.longitude AS lon
    FROM measurement m
      JOIN subsample s  ON s.subsample_id = m.subsample_id
      JOIN event     ev ON ev.event_id    = s.event_id
      JOIN site      si ON si.site_id      = ev.site_id
    WHERE m.outlier_flag IS NOT NULL") |>
    as_tibble()

  examples_out <- ex_ctx |>
    mutate(fraction = case_when(
             frac_class == "bulk"                        ~ "bulk",
             frac_class == "sieved" & sieve_um_std == 63 ~ "sieved63",
             frac_class == "sieved" & sieve_um_std == 20 ~ "sieved20",
             TRUE                                        ~ "other")) |>
    left_join(grp |> select(symbol, fraction, med_log), by = c("symbol", "fraction")) |>
    left_join(flagged, by = "measurement_id") |>
    mutate(group_median = round(10^med_log, 3),
           fold_vs_med  = round(value_std / group_median, 2),
           value_std    = round(value_std, 4)) |>
    transmute(symbol, fraction, direction = outlier_flag, value_std,
              group_median, fold_vs_med, source, sea_name, country, lat, lon) |>
    arrange(symbol, fraction, desc(abs(log10(fold_vs_med))))
  write_csv(examples_out, file.path(out_dir, "merge_outlier_examples.csv"))

  # ── 6. Verify ──────────────────────────────────────────────────────────────
  by_group <- dbGetQuery(con, "
    SELECT UPPER(m.symbol) sym,
           CASE WHEN m.frac_class='bulk' THEN 'bulk'
                ELSE 'sieved'||CAST(m.sieve_um_std AS INT) END frac,
           m.outlier_flag, COUNT(*) n
    FROM measurement m
    WHERE m.outlier_flag IS NOT NULL
    GROUP BY sym, frac, m.outlier_flag ORDER BY n DESC")
  totals <- dbGetQuery(con, "
    SELECT COALESCE(outlier_flag,'(in distribution)') outlier_flag, COUNT(*) n
    FROM measurement GROUP BY outlier_flag ORDER BY n DESC")

  if (verbose) {
    cat(sprintf("outlier_flag added (dual: |z|>%s AND |oom|>%s)\n", K_FLAG, MIN_OOM))
    cat("by element x fraction (flagged only):\n"); print(by_group, row.names = FALSE)
    cat("totals:\n");                               print(totals, row.names = FALSE)
  }
  invisible(list(by_group = by_group, totals = totals, summary = summary_out))
}
