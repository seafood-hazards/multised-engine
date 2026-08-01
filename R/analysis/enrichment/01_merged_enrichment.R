library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, bulk vs sieved enrichment (MERGED database) ──────────────
# Sieving sediment to a fine cutoff (<63um mud, or <20um finer still) discards the
# coarse, metal-poor grains, so a sieved analysis reads higher than a bulk (whole
# sample) one for the same metal. The EFSA spec warns the two are NOT comparable;
# this quantifies the enrichment factor (sieved / bulk) so the tracks can be
# related.
#
# A merged-only analysis. The strong version is PAIRED WITHIN SITE: at a site that
# carries both a bulk and a sieved value for the same element, their ratio is a
# direct enrichment factor with location held fixed, so it is not confounded by
# sieved samples happening to come from muddier or more contaminated places (the
# weakness of a pooled median-vs-median comparison). Sites are the merged site_id
# (lat/lon rounded to 3 dp). A pooled distributional view is kept alongside for the
# elements too sparse to pair and as a cross-check.
#
# Run once on multised_merged.sqlite. value_std (mg/kg); distributional outliers
# dropped; one value per site x element x fraction (mean). Ratios are skewed, so
# summarised by median and IQR.
#
# Outputs -> data/analysis/enrichment/ (gitignored). The multised-merged site
# renders tables + figures from these files:
#   merged_enrichment_paired.csv  per element x cutoff: within-site ratio summary
#   merged_enrichment_pairs.csv   row-level paired ratios (for the figure)
#   merged_enrichment_pooled.csv  per element x fraction: pooled median (context)

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"

TARGETS   <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
MIN_SITES <- 15L    # paired sites needed to report an element x cutoff
elem_levels <- TARGETS

out_dir <- "data/analysis/enrichment"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Site x element x fraction table (bulk / <63um / <20um) ────────────────
con <- dbConnect(SQLite(), db_path)

raw <- dbGetQuery(con, sprintf("
  SELECT si.site_id, m.symbol, m.value_std,
         CASE WHEN m.frac_class = 'bulk' THEN 'bulk'
              WHEN m.frac_class = 'sieved' AND m.sieve_um_std = 63 THEN 's63'
              WHEN m.frac_class = 'sieved' AND m.sieve_um_std = 20 THEN 's20'
              ELSE 'other' END AS frac
  FROM measurement m
    JOIN subsample s  ON s.subsample_id = m.subsample_id
    JOIN event     e  ON e.event_id     = s.event_id
    JOIN site      si ON si.site_id     = e.site_id
  WHERE m.value_std > 0 AND m.outlier_flag IS NULL
    AND m.symbol IN (%s)
", paste(sprintf("'%s'", TARGETS), collapse = ", "))) |>
  as_tibble() |>
  filter(frac != "other") |>
  mutate(symbol = factor(symbol, levels = elem_levels))

dbDisconnect(con)

# one value per site x element x fraction
site_frac <- raw |>
  group_by(site_id, symbol, frac) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  pivot_wider(names_from = frac, values_from = v)
for (f in c("bulk", "s63", "s20")) if (!f %in% names(site_frac)) site_frac[[f]] <- NA_real_

# ── 2. Paired within-site enrichment ratios (long over the two cutoffs) ──────
pairs <- bind_rows(
  site_frac |> filter(!is.na(bulk), !is.na(s63)) |>
    transmute(site_id, symbol, cutoff = "<63um", bulk, sieved = s63),
  site_frac |> filter(!is.na(bulk), !is.na(s20)) |>
    transmute(site_id, symbol, cutoff = "<20um", bulk, sieved = s20)) |>
  mutate(ratio = sieved / bulk) |>
  filter(is.finite(ratio), ratio > 0)

paired <- pairs |>
  group_by(symbol, cutoff) |>
  summarise(n_sites      = n(),
            median_ratio = round(median(ratio), 2),
            p25          = round(quantile(ratio, 0.25), 2),
            p75          = round(quantile(ratio, 0.75), 2),
            geomean      = round(exp(mean(log(ratio))), 2),
            pct_enriched = round(100 * mean(ratio > 1)),
            .groups = "drop") |>
  filter(n_sites >= MIN_SITES) |>
  arrange(symbol, cutoff)

# ── 3. Pooled distributional view (all data, not paired) ─────────────────────
pooled <- raw |>
  group_by(symbol, frac) |>
  summarise(n = n(), median = round(median(value_std), 2), .groups = "drop") |>
  pivot_wider(names_from = frac, values_from = c(n, median)) |>
  mutate(ratio_s63 = round(median_s63 / median_bulk, 2),
         ratio_s20 = round(median_s20 / median_bulk, 2)) |>
  arrange(symbol)

# ── 4. Row-level paired ratios for the figure (report-worthy elements) ───────
keep <- paired |> distinct(symbol) |> pull(symbol)
pairs_out <- pairs |>
  filter(symbol %in% keep) |>
  transmute(symbol = as.character(symbol), cutoff, ratio = round(ratio, 3))

# ── 5. Write outputs ─────────────────────────────────────────────────────────
write_csv(paired,    file.path(out_dir, "merged_enrichment_paired.csv"))
write_csv(pairs_out, file.path(out_dir, "merged_enrichment_pairs.csv"))
write_csv(pooled,    file.path(out_dir, "merged_enrichment_pooled.csv"))

# ── 6. Console summary ───────────────────────────────────────────────────────
cat("merged bulk-vs-sieved enrichment written to", out_dir, "\n\n")
cat("within-site enrichment factor (sieved / bulk), median:\n")
paired |> as.data.frame() |> print(row.names = FALSE)
