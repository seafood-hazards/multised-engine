library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, grain size (MERGED database) ─────────────────────────────
# The merged-database counterpart of 01_clean_grainsize.R. Same question, the
# grain-size control on the seven target metals (bulk vs sieved, and the <63um
# fines effect on concentration), but run once on multised_merged.sqlite, where
# cross-source duplicates are already removed. So this POOLS the four sources
# that carry grain size (Mareano, Vannmiljo, ICES-DOME, MUDAB; 4Demon has none)
# into a single best estimate per element, rather than reporting each source
# apart. Source is kept as a column for an optional per-source breakdown.
#
# Two things the clean version could not do, both from the merge:
#   * outliers are dropped. The merged measurement.outlier_flag (registration
#     errors, mostly) is excluded from the concentration ~ fines fits, so a
#     handful of impossible values do not swing the slopes.
#   * one pooled relationship. Deduplication means a reading shared by two
#     sources is counted once, so the pooled fit is not double-weighted.
#
# All depths are kept but reported by the EFSA depth bands (0-5 / 5-40 / >40 cm),
# assigned from the subsample interval MIDPOINT (docs/ReplyFHF_TypeDataForEFSA.md).
#
# Outputs -> data/analysis/grainsize/ (gitignored). The multised-merged site
# renders summary tables + figures from these files:
#   merged_grainsize_targets_fines.csv   one row per bulk-or-sieved target meas.
#   merged_grainsize_fraction_summary.csv  bulk/sieved counts by element x band
#   merged_grainsize_fines_summary.csv     <63um fines distribution by band
#   merged_grainsize_conc_vs_fines.csv     concentration ~ fines (pooled + source)
#   merged_grainsize_bulk_vs_sieved.csv    bulk vs sieved concentration levels

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"

TARGETS <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
MIN_N   <- 30L   # minimum n per group for a concentration ~ fines fit

out_dir <- "data/analysis/grainsize"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# EFSA depth bands from the interval midpoint (cm); unknown where depth is absent.
depth_band <- function(depth_from, depth_to) {
  mid <- (depth_from + depth_to) / 2
  band <- cut(mid, breaks = c(-Inf, 5, 40, Inf),
              labels = c("0-5", "5-40", ">40"), right = FALSE)
  as.character(band) |> replace_na("unknown")
}
band_levels <- c("0-5", "5-40", ">40", "unknown")

elem_levels <- TARGETS   # fixed display order

# ── 1. Pull the target/fines dataset from the merged DB ──────────────────────
# measurement -> subsample (fines, depth) -> event/site kept minimal. Keep the
# outlier flag so it can be excluded from fits yet reported in the row-level CSV.
con <- dbConnect(SQLite(), db_path)

dat <- dbGetQuery(con, sprintf("
  SELECT m.measurement_id,
         m.source        AS Source,
         m.symbol,
         m.value_std,
         m.frac_class,
         m.sieve_um_std,
         m.outlier_flag,
         s.subsample_id,
         s.depth_from, s.depth_to,
         s.fines_lt63,
         si.sea_name
  FROM measurement m
    JOIN subsample s  ON s.subsample_id = m.subsample_id
    JOIN event     ev ON ev.event_id    = s.event_id
    JOIN site      si ON si.site_id      = ev.site_id
  WHERE m.symbol IN (%s)
    AND m.value_std > 0
", paste(sprintf("'%s'", TARGETS), collapse = ", "))) |>
  as_tibble() |>
  mutate(
    symbol = factor(symbol, levels = elem_levels),
    band   = factor(depth_band(depth_from, depth_to), levels = band_levels))

dbDisconnect(con)

# ── 2. Fraction split: bulk vs sieved by element x band ──────────────────────
frac_summary <- dat |>
  count(symbol, band, frac_class, name = "n") |>
  arrange(symbol, band, frac_class)

# ── 3. <63um fines distribution by band (subsample level) ────────────────────
# One row per subsample so a subsample with several target metals is not
# over-counted; fines is a subsample property.
fines_summary <- dat |>
  distinct(subsample_id, band, fines_lt63) |>
  group_by(band) |>
  summarise(
    n_subsamples = n(),
    n_with_fines = sum(!is.na(fines_lt63)),
    mean   = round(mean(fines_lt63, na.rm = TRUE), 1),
    median = round(median(fines_lt63, na.rm = TRUE), 1),
    p25    = round(quantile(fines_lt63, 0.25, na.rm = TRUE), 1),
    p75    = round(quantile(fines_lt63, 0.75, na.rm = TRUE), 1),
    mud_dominated = sum(fines_lt63 >= 50, na.rm = TRUE),   # >= 50% fines
    .groups = "drop") |>
  arrange(band)

# ── 4. Concentration vs fines: the grain-size effect (BULK only) ─────────────
# Bulk (whole-sample) measurements only: there the reported value is of the
# whole sample, so relating it to the sample's fines_lt63 is meaningful and the
# expected grain-size effect (finer sediment concentrates metals -> positive
# association) can be measured. A sieved <63um value is of the fine fraction, not
# the whole sample, so it is excluded here (compared separately in step 5).
# Outliers (registration errors) are dropped so they do not swing the slope.
# Spearman rho on raw values; slope of log10(value) ~ fines.
fit_conc_fines <- function(d) {
  tibble(
    n     = nrow(d),
    rho   = suppressWarnings(cor(d$fines_lt63, d$value_std, method = "spearman")),
    slope_log10 = tryCatch(unname(coef(lm(log10(value_std) ~ fines_lt63, d))[2]),
                           error = function(e) NA_real_))
}

conc_bulk <- dat |>
  filter(frac_class == "bulk", !is.na(fines_lt63), is.na(outlier_flag))

# pooled across all sources (the merged headline), by element x band ...
conc_pooled <- conc_bulk |>
  group_by(symbol, band) |>
  filter(n() >= MIN_N) |>
  group_modify(~ fit_conc_fines(.x)) |>
  ungroup() |>
  mutate(Source = "All (pooled)", .before = symbol)

# ... and a per-source breakdown (all depths together) for comparison.
conc_by_source <- conc_bulk |>
  group_by(Source, symbol) |>
  filter(n() >= MIN_N) |>
  group_modify(~ fit_conc_fines(.x)) |>
  ungroup() |>
  mutate(band = factor("all", levels = c(band_levels, "all")))

conc_vs_fines <- bind_rows(conc_pooled, conc_by_source) |>
  mutate(across(c(rho, slope_log10), ~ round(.x, 3))) |>
  arrange(Source, symbol, band)

# ── 5. Bulk vs sieved concentration comparison (pooled) ──────────────────────
# The EFSA spec warns sieved <63um analyses are not comparable to bulk: the fine
# fraction concentrates metals, so sieved values should sit above bulk for the
# same element. Compare the concentration distribution by fraction, outliers
# dropped. sieve_um_std splits the two sieved tracks (<63um and <20um).
frac_conc <- dat |>
  filter(is.na(outlier_flag)) |>
  mutate(fraction = case_when(
    frac_class == "bulk"                        ~ "bulk",
    frac_class == "sieved" & sieve_um_std == 63 ~ "sieved63",
    frac_class == "sieved" & sieve_um_std == 20 ~ "sieved20",
    TRUE                                        ~ "sieved_other")) |>
  group_by(symbol, fraction) |>
  summarise(n = n(),
            median = round(median(value_std), 3),
            p25    = round(quantile(value_std, 0.25), 3),
            p75    = round(quantile(value_std, 0.75), 3),
            .groups = "drop") |>
  arrange(symbol, fraction)

# ── 6. Write outputs ─────────────────────────────────────────────────────────
# The row-level CSV keeps only what the site's figures need (bulk, with fines),
# to stay a reasonable size; outlier rows are kept but flagged for optional show.
targets_fines_out <- dat |>
  filter(frac_class == "bulk", !is.na(fines_lt63)) |>
  transmute(Source, symbol = as.character(symbol), value_std, fines_lt63,
            band = as.character(band), outlier_flag, sea_name)

write_csv(targets_fines_out, file.path(out_dir, "merged_grainsize_targets_fines.csv"))
write_csv(frac_summary,      file.path(out_dir, "merged_grainsize_fraction_summary.csv"))
write_csv(fines_summary,     file.path(out_dir, "merged_grainsize_fines_summary.csv"))
write_csv(conc_vs_fines,     file.path(out_dir, "merged_grainsize_conc_vs_fines.csv"))
write_csv(frac_conc,         file.path(out_dir, "merged_grainsize_bulk_vs_sieved.csv"))

# ── 7. Console summary ───────────────────────────────────────────────────────
cat("merged grain-size analysis written to", out_dir, "\n\n")
cat("bulk target measurements with fines (outliers dropped):\n")
conc_bulk |> count(symbol, .drop = FALSE, name = "n") |>
  as.data.frame() |> print(row.names = FALSE)
cat("\npooled concentration ~ fines (all depths):\n")
conc_pooled |>
  filter(band == "0-5" | TRUE) |>
  group_by(symbol) |>
  summarise(bands = paste(sprintf("%s: rho=%.2f", band, rho), collapse = "  "),
            .groups = "drop") |>
  as.data.frame() |> print(row.names = FALSE)
