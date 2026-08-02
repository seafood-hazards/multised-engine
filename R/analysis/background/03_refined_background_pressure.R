library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, pressure-based background (REFINED database) ──────────────
# The third background page, and the aquaculture-relevant one. Instead of a spatial
# proxy (offshore), it uses a direct PRESSURE gradient: distance to the nearest
# aquaculture farm. Sites far from any farm are the low-pressure background; sites near
# the cages show the enrichment. Norway only (dist_to_aquaculture is Norwegian), which
# is where the aquaculture question is asked.
#
# Per element x fraction, the value_std distribution (median, P90) is taken in
# distance-to-aquaculture bins (<1, 1-5, 5-20, >20 km). The >20 km bin is read as the
# background; the near/far P90 ratio is the enrichment. Raw value (mg/kg); a grain-size
# caveat applies (near-cage sediment is often muddier / more organic), so the Al-
# normalised background (page 2) is the cross-check. Outliers dropped; fractions
# bulk/sieved63/sieved20.
#
# Outputs -> data/analysis/background/ (gitignored):
#   refined_pressure_percentiles.csv  element x fraction x aq_bin: n, P50, P90
#   refined_pressure_compare.csv      P90 per bin (wide) + near/far enrichment
#   refined_pressure_meta.csv         one-row config

db_path <- "./data/db/multised_refined.sqlite"

CATS      <- c("bulk", "sieved63", "sieved20")
AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
BG_BIN    <- ">20km"     # the background (far) bin
MIN_N     <- 30L
elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

out_dir <- "data/analysis/background"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Pull chemistry + distance to aquaculture (Norway rows only) ───────────
con <- dbConnect(SQLite(), db_path)
m <- as_tibble(dbGetQuery(con, "
  SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std,
         si.dist_to_aquaculture
  FROM measurement me
  JOIN subsample s ON s.subsample_id = me.subsample_id
  JOIN event e     ON e.event_id     = s.event_id
  JOIN site  si    ON si.site_id     = e.site_id
  WHERE me.value_std > 0 AND me.outlier_flag IS NULL
    AND si.dist_to_aquaculture IS NOT NULL
")) |>
  mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                         sieve_um_std == 63 ~ "sieved63",
                         sieve_um_std == 20 ~ "sieved20",
                         TRUE ~ NA_character_)) |>
  filter(cat %in% CATS) |>
  mutate(aq_bin = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS))

# ── 2. Distribution per aquaculture-distance bin ─────────────────────────────
percentiles <- m |>
  group_by(symbol, cat, aq_bin) |>
  summarise(n = n(), p50 = signif(median(value_std), 4),
            p90 = signif(quantile(value_std, .9, names = FALSE), 4), .groups = "drop") |>
  mutate(symbol = factor(symbol, levels = elem_levels),
         cat = factor(cat, levels = CATS),
         reliable = n >= MIN_N) |>
  arrange(symbol, cat, aq_bin)

# ── 3. Compare: P90 per bin wide + near/far enrichment ───────────────────────
wide <- percentiles |>
  mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
  select(symbol, cat, aq_bin, p90) |>
  pivot_wider(names_from = aq_bin, values_from = p90)
ncol_bin <- percentiles |>
  mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
  select(symbol, cat, aq_bin, n) |>
  pivot_wider(names_from = aq_bin, values_from = n, names_prefix = "n_")

compare <- wide |>
  left_join(ncol_bin, by = c("symbol", "cat")) |>
  mutate(enrich_near = round(`<1km` / .data[[BG_BIN]], 3),
         symbol = factor(symbol, levels = elem_levels),
         cat = factor(cat, levels = CATS)) |>
  arrange(symbol, cat)

meta <- tibble(bins = paste(AQ_LABELS, collapse = ","), bg_bin = BG_BIN,
               min_n = MIN_N, scope = "Norway (dist_to_aquaculture)")

# ── 4. Write ─────────────────────────────────────────────────────────────────
write_csv(percentiles, file.path(out_dir, "refined_pressure_percentiles.csv"))
write_csv(compare,     file.path(out_dir, "refined_pressure_compare.csv"))
write_csv(meta,        file.path(out_dir, "refined_pressure_meta.csv"))

# ── 5. Console summary ───────────────────────────────────────────────────────
cat("pressure-based background written to", out_dir, "\n\n")
cat("bulk P90 (mg/kg) by distance-to-aquaculture bin, near/far enrichment:\n")
compare |> filter(cat == "bulk") |>
  select(symbol, `<1km`, `1-5km`, `5-20km`, `>20km`, enrich_near) |>
  as.data.frame() |> print(row.names = FALSE)
