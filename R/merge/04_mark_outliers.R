library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge stage 4: mark distributional outliers ──────────────────────────────
# Add a soft `outlier_flag` ('high' / 'low' / NULL) to the merged `measurement`
# table: a data-driven marker for values that sit implausibly far from their
# element's distribution, most of which are registration errors (decimal shifts,
# unit swaps) rather than real chemistry. A review/removal candidate for
# downstream use, NOT a deletion, so genuine extremes (e.g. a truly contaminated
# fjord) survive for a human to judge.
#
# It complements, not replaces, the pipeline's existing markers carried up from
# slim: range_flag (generous PHYSICAL bounds, misses an in-range 10x shift),
# invalid_flag (negatives), below_loq (already applied: the clean stage dropped
# below-LOQ rows, so surviving lows are above-detection), and 4Demon's native
# outlier_* flags. This is the statistical/distributional view, computed on the
# pooled merged distribution where it is richest.
#
# Rule (settled from R/analysis/outlier_review/, dual criterion):
#   * chemistry only (element.category target / reference / organic); grain-size
#     composition is bounded 0-100% and left NULL.
#   * per ELEMENT x FRACTION group (bulk / sieved63 / sieved20), on
#     log10(value_std). Fraction must be split: sieved medians run 1.5-3x bulk.
#   * robust centre/spread: median and MAD (log scale). Flag when a value is
#     BOTH a statistical outlier (|z| > K_FLAG, z = (log - median)/MAD) AND at
#     least MIN_OOM orders of magnitude from the median (|log10(value/median)| >
#     MIN_OOM). The order-of-magnitude floor targets registration errors and
#     spares narrow real tails (e.g. Se) that a MAD-only rule over-flags.
#     Effective boundary = median +/- max(K_FLAG * MAD, MIN_OOM).
#   * small-n guard: groups below MIN_N are left NULL (robust stats unreliable,
#     e.g. Iodine); those still carry the generous range_flag.
#   * region is NOT stratified: regional spread (~2x) is trivial next to the
#     10-1000x errors this targets.
#
# Reads/writes data/db/multised_merged.sqlite. Idempotent and re-runnable.
#
# Also writes website summary CSVs -> data/analysis/merge/ (gitignored), read by
# the multised-merged "Outlier Flagging" analysis page (as 02_dedup writes
# merge_dedup.csv):
#   merge_outlier_summary.csv   element x fraction: median, thresholds, hi/lo counts
#   merge_outlier_hist.csv      binned log10(value_std) per element x fraction
#   merge_outlier_examples.csv  the flagged rows with fold-vs-median + location

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path   <- "data/db/multised_merged.sqlite"
MIN_N     <- 100L                          # min group size to compute a threshold
K_FLAG    <- 4                             # robust-z multiplier
MIN_OOM   <- 1.0                           # min |log10(value/median)|
FRACTIONS <- c("bulk", "sieved63", "sieved20")
CHEM      <- c("target", "reference", "organic")

con <- dbConnect(SQLite(), db_path)
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Chemistry measurements + their category and fraction ──────────────────
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

# ── 2. Robust per element x fraction statistics ──────────────────────────────
grp <- d |>
  filter(category %in% CHEM, fraction %in% FRACTIONS, !is.na(logv)) |>
  group_by(symbol, fraction) |>
  summarise(n = n(), med_log = median(logv), mad_log = mad(logv),
            .groups = "drop") |>
  mutate(enough = n >= MIN_N & mad_log > 0)

# ── 3. Dual-criterion flag per measurement ───────────────────────────────────
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

# ── 4. Add outlier_flag column (idempotent) + write back ─────────────────────
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

# ── 5. Website summary CSVs (read by the multised-clean outlier page) ─────────
out_dir <- "data/analysis/merge"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

usable <- grp |> filter(enough) |> select(symbol, fraction)

# per element x fraction: robust thresholds (mg/kg) + flag counts
counts <- d |>
  inner_join(usable, by = c("symbol", "fraction")) |>
  left_join(flagged, by = "measurement_id") |>
  filter(!is.na(outlier_flag)) |>
  count(symbol, fraction, outlier_flag) |>
  pivot_wider(names_from = outlier_flag, values_from = n, values_fill = 0)
for (c in c("high", "low")) if (!c %in% names(counts)) counts[[c]] <- 0L

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

# ── 6. Verify ────────────────────────────────────────────────────────────────
cat(sprintf("outlier_flag added (dual: |z|>%s AND |oom|>%s)\n", K_FLAG, MIN_OOM))
cat("by element x fraction (flagged only):\n")
print(dbGetQuery(con, "
  SELECT UPPER(m.symbol) sym,
         CASE WHEN m.frac_class='bulk' THEN 'bulk'
              ELSE 'sieved'||CAST(m.sieve_um_std AS INT) END frac,
         m.outlier_flag, COUNT(*) n
  FROM measurement m
  WHERE m.outlier_flag IS NOT NULL
  GROUP BY sym, frac, m.outlier_flag ORDER BY n DESC"), row.names = FALSE)
cat("totals:\n")
print(dbGetQuery(con, "
  SELECT COALESCE(outlier_flag,'(in distribution)') outlier_flag, COUNT(*) n
  FROM measurement GROUP BY outlier_flag ORDER BY n DESC"), row.names = FALSE)

dbDisconnect(con)
