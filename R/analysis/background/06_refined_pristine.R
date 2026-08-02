library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, pristine classification (REFINED database) ───────────────
# The synthesis: a per-measurement "pristine" (at/below background) verdict per element
# x fraction, built ONLY on grain-size-controlled criteria. A raw-concentration flag was
# rejected: it is confounded by grain size (sandy near-cage sediment slips under a
# threshold regardless of pressure), and Al coverage is anti-correlated with aquaculture
# proximity, so a concentration fallback validated backwards. So where aluminium (hence
# the enrichment factor) is missing, a sample is left UNCLASSIFIED rather than guessed.
#
# Two flags, both defined only where Al is present (else NA = unclassified):
#   pristine_ef     : EF < 1 (EF = (metal/Al) / offshore-median(metal/Al))   [permissive, EFSA]
#   pristine_strict : EF<1 AND value_std < mixture threshold AND value_std < offshore P90
#                     (all three background criteria agree; conservative)
# Reference values reused from the earlier pages: EF background (04), mixture threshold
# (05), offshore P90 (01).
#
# The headline is a data-gap: how much of the data (and especially the near-cage data) is
# even classifiable. Distance to aquaculture / coast VALIDATE the flag (not define it).
# Fractions bulk/sieved63/sieved20; outliers dropped.
#
# Outputs -> data/analysis/background/ (gitignored):
#   refined_pristine_summary.csv     per element x fraction: % classifiable, % pristine (both rules)
#   refined_pristine_coverage.csv    % classifiable (has Al) by distance band  (the data gap)
#   refined_pristine_validation.csv  % pristine by distance band, among classifiable samples
#   refined_pristine_meta.csv        one-row config

db_path <- "./data/db/multised_refined.sqlite"
adir    <- "data/analysis/background"
CATS  <- c("bulk", "sieved63", "sieved20")
MIN_N <- 30L
AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf);  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
CO_BREAKS <- c(-Inf, 1, 10, 50, Inf); CO_LABELS <- c("<1km", "1-10km", "10-50km", ">50km")
elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

rd <- function(f) read_csv(file.path(adir, f), show_col_types = FALSE) |>
  mutate(symbol = as.character(symbol), cat = as.character(cat))
bg  <- rd("refined_ef_background.csv")      |> select(symbol, cat, bg_ratio_al)
off <- rd("refined_background_compare.csv") |> select(symbol, cat, p90_off = p90_off10)
mix <- rd("refined_mixture_components.csv") |> select(symbol, cat, threshold)

# ── Measurements + criteria + the two grain-size-controlled flags ────────────
con <- dbConnect(SQLite(), db_path)
m <- as_tibble(dbGetQuery(con, "
  SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.ratio_al,
         si.dist_to_coast, si.dist_to_aquaculture
  FROM measurement me
  JOIN subsample s ON s.subsample_id = me.subsample_id
  JOIN event e     ON e.event_id     = s.event_id
  JOIN site  si    ON si.site_id     = e.site_id
  WHERE me.value_std > 0 AND me.outlier_flag IS NULL")) |>
  mutate(cat = case_when(frac_class == "bulk" ~ "bulk", sieve_um_std == 63 ~ "sieved63",
                         sieve_um_std == 20 ~ "sieved20", TRUE ~ NA_character_)) |>
  filter(cat %in% CATS) |>
  left_join(bg, by = c("symbol", "cat")) |>
  left_join(off, by = c("symbol", "cat")) |>
  left_join(mix, by = c("symbol", "cat")) |>
  mutate(
    EF          = if_else(!is.na(ratio_al) & !is.na(bg_ratio_al) & bg_ratio_al > 0,
                          ratio_al / bg_ratio_al, NA_real_),
    classifiable = !is.na(EF),
    pristine_ef  = if_else(classifiable, EF < 1, NA),
    pristine_strict = if_else(classifiable,
                        (EF < 1) & (value_std < threshold) & (value_std < p90_off), NA))

# ── Summary per element x fraction ───────────────────────────────────────────
summary_tbl <- m |>
  group_by(symbol, cat) |>
  summarise(n = n(),
            pct_classifiable = round(100 * mean(classifiable)),
            n_classifiable   = sum(classifiable),
            pct_ef     = round(100 * mean(pristine_ef, na.rm = TRUE)),
            pct_strict = round(100 * mean(pristine_strict, na.rm = TRUE)),
            .groups = "drop") |>
  mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
         reliable = n_classifiable >= MIN_N) |>
  arrange(symbol, cat)

# ── Coverage (the data gap) and validation, by distance band ─────────────────
by_band <- function(df, axis) {
  df |> group_by(band) |>
    summarise(n = n(),
              pct_classifiable = round(100 * mean(classifiable)),
              n_class = sum(classifiable),
              ef     = round(100 * mean(pristine_ef, na.rm = TRUE)),
              strict = round(100 * mean(pristine_strict, na.rm = TRUE)), .groups = "drop") |>
    mutate(axis = axis)
}
banded <- bind_rows(
  m |> filter(!is.na(dist_to_aquaculture)) |>
    mutate(band = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS)) |>
    by_band("distance to aquaculture"),
  m |> mutate(band = cut(dist_to_coast, CO_BREAKS, labels = CO_LABELS)) |>
    by_band("distance to coast"))

coverage <- banded |> select(axis, band, n, pct_classifiable)
validation <- banded |>
  filter(n_class >= MIN_N) |>
  select(axis, band, n_class, ef, strict) |>
  pivot_longer(c(ef, strict), names_to = "rule", values_to = "pct_pristine")

meta <- tibble(rule_ef = "EF<1 (grain-size-controlled); unclassified where Al absent",
               rule_strict = "EF<1 AND below mixture threshold AND below offshore P90",
               fallback = "none (no raw-concentration fallback; confounded, dropped)",
               min_n = MIN_N)

write_csv(summary_tbl, file.path(adir, "refined_pristine_summary.csv"))
write_csv(coverage,    file.path(adir, "refined_pristine_coverage.csv"))
write_csv(validation,  file.path(adir, "refined_pristine_validation.csv"))
write_csv(meta,        file.path(adir, "refined_pristine_meta.csv"))

# ── Console summary ──────────────────────────────────────────────────────────
cat("pristine classification written to", adir, "\n\n")
cat("% classifiable (has Al) and % pristine among classifiable (bulk):\n")
summary_tbl |> filter(cat == "bulk", reliable) |>
  select(symbol, n, pct_classifiable, n_classifiable, pct_ef, pct_strict) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\nthe data gap: % classifiable by distance to aquaculture:\n")
coverage |> filter(axis == "distance to aquaculture") |> as.data.frame() |> print(row.names = FALSE)
cat("\nvalidation (classifiable only): % pristine by distance to aquaculture:\n")
validation |> filter(axis == "distance to aquaculture") |>
  pivot_wider(names_from = rule, values_from = pct_pristine) |> as.data.frame() |> print(row.names = FALSE)
