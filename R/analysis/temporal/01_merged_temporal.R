library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, temporal context (MERGED database) ───────────────────────
# The merged-database counterpart of 01_clean_temporal.R, and the time analogue of
# the spatial page. Does sampling year leave a trend after normalisation? Two
# questions, bulk samples, pooled across the merged database (outliers dropped):
#
#  (A) enrichment: does the ratio metal / normaliser (Fe primary, Al secondary)
#      trend over the years? A ratio that FALLS with year is a real improvement
#      signal (declining input relative to the lithogenic carrier); a flat ratio
#      means normalisation removed any temporal drift.
#  (B) covariate check: do the normalisers / covariates themselves (Al, Fe, CORG,
#      fines) trend with year? A drift here means the sampling / method mix changed
#      over time, which would confound (A).
#
# Caveats: this is an unbalanced observational series, not a fixed monitoring
# station, so year is confounded with WHERE and HOW the pooled sources sampled over
# time (station mix, gear, lab, and which source dominates which decade). These are
# associations, not station trends. Vannmiljo dominates the long Norwegian series
# (1975-2025); Mareano is 2003-2021 only.
#
# Outputs -> data/analysis/temporal/ (gitignored). The multised-merged site
# renders tables + figures from these files:
#   merged_temporal_enrichment.csv  (A) rho of metal/normaliser vs year
#   merged_temporal_covariate.csv   (B) rho of Al/Fe/CORG/fines vs year
#   merged_temporal_yearly.csv      yearly median metal/Fe enrichment (figure)
#   merged_temporal_pairs.csv        per-measurement (bulk) for the figures

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"

TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
NORMALISERS <- c("AL", "FE")
MIN_N       <- 50L
YEAR_MIN    <- 1980L   # yearly medians only where a decade of coverage exists
elem_levels <- TARGETS

out_dir <- "data/analysis/temporal"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

rho_by_group <- function(df, x, y, groups) {
  df |>
    filter(!is.na(.data[[x]]), !is.na(.data[[y]]), .data[[y]] > 0) |>
    group_by(across(all_of(groups))) |>
    filter(n() >= MIN_N) |>
    summarise(rho = cor(.data[[x]], .data[[y]], method = "spearman"),
              n = n(), .groups = "drop")
}

# ── 1. Build per-subsample chemistry + event year, bulk, outliers dropped ────
con <- dbConnect(SQLite(), db_path)

meas <- dbGetQuery(con, sprintf("
  SELECT m.subsample_id, m.source AS Source, m.symbol, m.value_std
  FROM measurement m
  WHERE m.frac_class = 'bulk' AND m.value_std > 0 AND m.outlier_flag IS NULL
    AND m.symbol IN (%s)
", paste(sprintf("'%s'", c(TARGETS, NORMALISERS, "CORG")), collapse = ", "))) |>
  as_tibble()

ctx <- dbGetQuery(con, "
  SELECT s.subsample_id, s.fines_lt63, e.year
  FROM subsample s JOIN event e ON e.event_id = s.event_id
") |> as_tibble()
dbDisconnect(con)

agg <- meas |>
  group_by(subsample_id, Source, symbol) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  pivot_wider(names_from = symbol, values_from = v)
for (s in c(TARGETS, NORMALISERS, "CORG")) if (!s %in% names(agg)) agg[[s]] <- NA_real_

dat <- agg |> left_join(ctx, by = "subsample_id")

# ── 2. (A) Enrichment (metal / normaliser) vs year ───────────────────────────
pairs <- dat |>
  pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
  filter(!is.na(value_std)) |>
  transmute(Source, symbol = factor(symbol, levels = elem_levels),
            value_std, AL, FE, year,
            ratio_AL = value_std / AL, ratio_FE = value_std / FE)

enrich_one <- function(ratio_col, norm_lab) {
  bind_rows(
    rho_by_group(pairs |> rename(v = !!ratio_col), "v", "year", "symbol") |>
      mutate(Source = "All (pooled)"),
    rho_by_group(pairs |> rename(v = !!ratio_col), "v", "year", c("Source","symbol"))) |>
    mutate(normaliser = norm_lab)
}

enrichment <- bind_rows(enrich_one("ratio_FE", "Fe"),
                        enrich_one("ratio_AL", "Al")) |>
  mutate(rho = round(rho, 3), variable = "year", symbol = as.character(symbol)) |>
  select(Source, symbol, normaliser, variable, n, rho) |>
  arrange(Source, symbol, normaliser)

# ── 3. (B) Normalisers / covariates vs year (pooled) ─────────────────────────
subs <- dat |>
  distinct(subsample_id, AL, FE, CORG, fines_lt63, year) |>
  rename(Al = AL, Fe = FE, Fines = fines_lt63)

covariate <- bind_rows(lapply(c("Al", "Fe", "CORG", "Fines"), function(f)
  rho_by_group(subs |> rename(v = !!f), "v", "year", character(0)) |>
    mutate(factor = f, variable = "year"))) |>
  mutate(rho = round(rho, 3)) |>
  select(factor, variable, n, rho) |>
  arrange(factor)

# ── 4. Yearly median metal/Fe enrichment (for the trend figure) ──────────────
yearly <- pairs |>
  filter(!is.na(ratio_FE), is.finite(ratio_FE), ratio_FE > 0,
         !is.na(year), year >= YEAR_MIN) |>
  group_by(symbol, year) |>
  summarise(n = n(), median_ratio_FE = median(ratio_FE), .groups = "drop") |>
  filter(n >= 20) |>
  mutate(symbol = as.character(symbol)) |>
  arrange(symbol, year)

# ── 5. Row-level pairs for the figures ───────────────────────────────────────
pairs_out <- pairs |>
  filter(!is.na(ratio_FE), is.finite(ratio_FE), ratio_FE > 0, !is.na(year)) |>
  transmute(symbol = as.character(symbol), value_std, FE, ratio_FE, year)

# ── 6. Write outputs ─────────────────────────────────────────────────────────
write_csv(enrichment, file.path(out_dir, "merged_temporal_enrichment.csv"))
write_csv(covariate,  file.path(out_dir, "merged_temporal_covariate.csv"))
write_csv(yearly,     file.path(out_dir, "merged_temporal_yearly.csv"))
write_csv(pairs_out,  file.path(out_dir, "merged_temporal_pairs.csv"))

# ── 7. Console summary ───────────────────────────────────────────────────────
cat("merged temporal analysis written to", out_dir, "\n\n")
cat("(B) covariate vs year (pooled rho):\n")
covariate |> as.data.frame() |> print(row.names = FALSE)
cat("\n(A) metal/Fe enrichment vs year (pooled; negative = declining over time):\n")
enrichment |> filter(Source == "All (pooled)", normaliser == "Fe") |>
  select(symbol, n, rho) |> as.data.frame() |> print(row.names = FALSE)
