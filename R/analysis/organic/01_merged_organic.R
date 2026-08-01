library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, organic carbon (MERGED database) ─────────────────────────
# The merged-database counterpart of 01_clean_organic.R. Trace metals bind to
# organic matter, so total organic carbon (CORG) is a third control on their
# concentration alongside grain size and the Fe/Al normalisers. This relates each
# target metal to the co-located CORG to see which metals are organic-associated,
# expected for the chalcophile / redox-sensitive ones (e.g. MO, SE) that the Fe/Al
# normalisation did NOT explain. The EFSA spec records organic matter as TOC%, so
# distributions are reported in percent.
#
# Run once on multised_merged.sqlite (cross-source duplicates removed), so the
# four sources that carry organic carbon are POOLED into one estimate per element
# (Source kept for a per-source breakdown). Whole-sample organic carbon is CORG
# (all source TOC was harmonised to CORG in the clean stage). TOC63 ("Normalized
# TOC", the <63um-normalised organic carbon from Vannmiljo) is a DIFFERENT
# measurand, not whole-sample, so it is excluded here. 4Demon has none.
#
# Each target is paired with the CORG on the SAME subsample and SAME (bulk)
# fraction; normalisation is only valid within a comparable fraction, and bulk is
# the analysable track. Distributional outliers are dropped from target and CORG.
# CORG is in mg/kg (value_std); percent = value_std / 10000.
# All depths kept, reported by EFSA depth band (0-5 / 5-40 / >40 cm, midpoint).
#
# Outputs -> data/analysis/organic/ (gitignored). The multised-merged site
# renders tables + figures from these files:
#   merged_organic_pairs.csv         bulk target paired with CORG (figures)
#   merged_organic_availability.csv  how much bulk target carries CORG, by band
#   merged_organic_distribution.csv  CORG (%) distribution by band
#   merged_organic_correlation.csv   metal ~ CORG fit (log-log), pooled + source

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"

TARGETS    <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
ORGANIC    <- "CORG"      # whole-sample organic carbon
MG_PER_PCT <- 10000       # mg/kg per 1 % organic carbon
MIN_N      <- 30L

out_dir <- "data/analysis/organic"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

depth_band <- function(depth_from, depth_to) {
  mid <- (depth_from + depth_to) / 2
  band <- cut(mid, breaks = c(-Inf, 5, 40, Inf),
              labels = c("0-5", "5-40", ">40"), right = FALSE)
  as.character(band) |> replace_na("unknown")
}
band_levels <- c("0-5", "5-40", ">40", "unknown")
elem_levels <- TARGETS

# ── 1. Build target <-> CORG pairs (same subsample, bulk fraction) ───────────
con <- dbConnect(SQLite(), db_path)

meas <- dbGetQuery(con, sprintf("
  SELECT m.subsample_id, m.source AS Source, m.frac_class, m.symbol, m.value_std
  FROM measurement m
  WHERE m.symbol IN (%s)
    AND m.value_std > 0
    AND m.outlier_flag IS NULL
", paste(sprintf("'%s'", c(TARGETS, ORGANIC)), collapse = ", "))) |>
  as_tibble()

ss <- dbGetQuery(con, "SELECT subsample_id, depth_from, depth_to FROM subsample") |>
  as_tibble()
dbDisconnect(con)

agg <- meas |>
  filter(frac_class == "bulk") |>
  group_by(subsample_id, Source, symbol) |>
  summarise(v = mean(value_std), .groups = "drop")

wide <- agg |> pivot_wider(names_from = symbol, values_from = v)
for (s in c(TARGETS, ORGANIC)) if (!s %in% names(wide)) wide[[s]] <- NA_real_

bands <- ss |> transmute(subsample_id, band = depth_band(depth_from, depth_to))

pairs <- wide |>
  left_join(bands, by = "subsample_id") |>
  pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
  filter(!is.na(value_std)) |>
  transmute(Source, subsample_id,
            band = factor(band, levels = band_levels),
            symbol = factor(symbol, levels = elem_levels), value_std,
            CORG, corg_pct = CORG / MG_PER_PCT)

# ── 2. Availability: how much bulk target data carries CORG, by band ─────────
availability <- pairs |>
  group_by(symbol, band) |>
  summarise(n_target = n(),
            n_with_CORG = sum(!is.na(CORG)),
            pct_CORG = round(100 * mean(!is.na(CORG))),
            .groups = "drop") |>
  arrange(symbol, band)

# ── 3. Organic carbon distribution (percent), by band (subsample level) ──────
distribution <- pairs |>
  filter(!is.na(corg_pct)) |>
  distinct(subsample_id, band, corg_pct) |>
  group_by(band) |>
  summarise(n_subsamples = n(),
            median = round(median(corg_pct), 2),
            p25 = round(quantile(corg_pct, 0.25), 2),
            p75 = round(quantile(corg_pct, 0.75), 2),
            max = round(max(corg_pct), 1),
            .groups = "drop") |>
  arrange(band)

# ── 4. metal ~ CORG fit (log-log): pooled and per-source (bulk) ──────────────
# Strong log-log correlation => the metal is organic-associated. Compare with the
# Fe/Al result: a metal weak on Fe/Al but strong on CORG is organically controlled.
paired <- pairs |> filter(!is.na(CORG), CORG > 0)

fit_org <- function(d) {
  m <- lm(log10(value_std) ~ log10(CORG), d)
  tibble(n = nrow(d),
         r  = suppressWarnings(cor(log10(d$CORG), log10(d$value_std))),
         r2 = summary(m)$r.squared,
         slope = unname(coef(m)[2]))
}

corr_pooled <- paired |>
  group_by(symbol) |>
  filter(n() >= MIN_N) |>
  group_modify(~ fit_org(.x)) |>
  ungroup() |>
  mutate(Source = "All (pooled)", .before = symbol)

corr_source <- paired |>
  group_by(Source, symbol) |>
  filter(n() >= MIN_N) |>
  group_modify(~ fit_org(.x)) |>
  ungroup()

correlation <- bind_rows(corr_pooled, corr_source) |>
  mutate(across(c(r, r2, slope), ~ round(.x, 3))) |>
  arrange(Source, symbol)

# ── 5. Write outputs ─────────────────────────────────────────────────────────
pairs_out <- paired |>
  transmute(Source, symbol = as.character(symbol), band = as.character(band),
            value_std, CORG, corg_pct)

write_csv(pairs_out,    file.path(out_dir, "merged_organic_pairs.csv"))
write_csv(availability, file.path(out_dir, "merged_organic_availability.csv"))
write_csv(distribution, file.path(out_dir, "merged_organic_distribution.csv"))
write_csv(correlation,  file.path(out_dir, "merged_organic_correlation.csv"))

# ── 6. Console summary ───────────────────────────────────────────────────────
cat("merged organic-carbon analysis written to", out_dir, "\n\n")
cat("bulk target measurements, and % carrying CORG (outliers dropped):\n")
pairs |>
  group_by(symbol, .drop = FALSE) |>
  summarise(n_target = n(), pct_CORG = round(100 * mean(!is.na(CORG))),
            .groups = "drop") |>
  as.data.frame() |> print(row.names = FALSE)
cat("\npooled metal ~ CORG strength (bulk r2 of log-log fit):\n")
corr_pooled |>
  mutate(r2 = round(r2, 2)) |>
  select(symbol, n, r2) |>
  as.data.frame() |> print(row.names = FALSE)
