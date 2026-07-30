library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, grain size (per source) ──────────────────────────────────
# For each <source>_clean.sqlite, characterise the sediment fraction and the
# <63um fines behind the seven target-element concentrations, following the EFSA
# data spec (docs/ReplyFHF_TypeDataForEFSA.md): distinguish bulk vs sieved
# analyses and relate concentration to grain size. The analysis is run SEPARATELY
# per source (results tagged by Source) to keep source-specific issues apart.
#
# All depths are kept but reported by the EFSA depth bands (0-5 / 5-40 / >40 cm),
# assigned from the subsample interval MIDPOINT.
#
# Outputs -> data/analysis/grainsize/ (gitignored, like the DBs). The
# multised-clean site renders summary tables + figures from these files:
#   grainsize_targets_fines.csv   one row per target measurement (for figures)
#   grainsize_fraction_summary.csv  bulk/sieved counts by element x band
#   grainsize_fines_summary.csv     <63um fines distribution by band
#   grainsize_conc_vs_fines.csv     concentration ~ fines relationship

# ── 0. Config ────────────────────────────────────────────────────────────────
sources <- tibble(
  Source = c("Mareano", "Vannmiljø", "ICES-DOME", "MUDAB", "4Demon"),
  stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

TARGETS <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
MIN_N   <- 10L   # minimum n per element x band for a concentration ~ fines fit

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

# ── 1. Build the per-source target/fines dataset ─────────────────────────────
build_dataset <- function(stem, Source) {
  con <- dbConnect(SQLite(), sprintf("data/db/%s_clean.sqlite", stem))
  on.exit(dbDisconnect(con))
  meas <- as_tibble(dbReadTable(con, "measurement"))
  ss   <- as_tibble(dbReadTable(con, "subsample"))

  # subsamples lacking fines carry NA (Mareano bulk have fines; 4Demon has none)
  if (!"fines_lt63" %in% names(ss)) ss$fines_lt63 <- NA_real_

  meas |>
    filter(symbol %in% TARGETS, !is.na(value_std), value_std > 0) |>
    left_join(ss |> select(subsample_id, depth_from, depth_to, fines_lt63),
              by = "subsample_id") |>
    transmute(Source, subsample_id, symbol,
              value_std, frac_class, sieve_um, fines_lt63,
              depth_from, depth_to,
              band = factor(depth_band(depth_from, depth_to), levels = band_levels))
}

dat <- pmap_dfr(sources, function(Source, stem) build_dataset(stem, Source))

# ── 2. Fraction split: bulk vs sieved by element x band ──────────────────────
frac_summary <- dat |>
  count(Source, symbol, band, frac_class, name = "n") |>
  arrange(Source, symbol, band, frac_class)

# ── 3. <63um fines distribution by band (subsample level) ────────────────────
fines_summary <- dat |>
  distinct(Source, subsample_id, band, fines_lt63) |>
  group_by(Source, band) |>
  summarise(
    n_subsamples = n(),
    n_with_fines = sum(!is.na(fines_lt63)),
    mean   = round(mean(fines_lt63, na.rm = TRUE), 1),
    median = round(median(fines_lt63, na.rm = TRUE), 1),
    p25    = round(quantile(fines_lt63, 0.25, na.rm = TRUE), 1),
    p75    = round(quantile(fines_lt63, 0.75, na.rm = TRUE), 1),
    mud_dominated = sum(fines_lt63 >= 50, na.rm = TRUE),   # >= 50% fines
    .groups = "drop") |>
  arrange(Source, band)

# ── 4. Concentration vs fines: the grain-size effect (BULK only) ─────────────
# Restricted to bulk (whole-sample) measurements: there the reported value is of
# the whole sample, so relating it to the sample's fines_lt63 is meaningful and
# the expected grain-size effect (finer sediment concentrates metals -> positive
# association) can be measured. A sieved <63um value is of the fine fraction, not
# the whole sample, so it is excluded here (compared separately in step 5).
# Spearman rho on raw values; slope of log10(value) ~ fines.
fit_conc_fines <- function(d) {
  tibble(
    n     = nrow(d),
    rho   = suppressWarnings(cor(d$fines_lt63, d$value_std, method = "spearman")),
    slope_log10 = tryCatch(unname(coef(lm(log10(value_std) ~ fines_lt63, d))[2]),
                           error = function(e) NA_real_))
}

conc_vs_fines <- dat |>
  filter(frac_class == "bulk", !is.na(fines_lt63)) |>
  group_by(Source, symbol, band) |>
  filter(n() >= MIN_N) |>
  group_modify(~ fit_conc_fines(.x)) |>
  ungroup() |>
  mutate(across(c(rho, slope_log10), ~ round(.x, 3))) |>
  arrange(Source, symbol, band)

# ── 5. Bulk vs sieved concentration comparison ───────────────────────────────
# The EFSA spec warns that sieved <63um analyses are not comparable to bulk: the
# fine fraction concentrates metals, so sieved values should sit above bulk for
# the same element. Compare the concentration distribution by fraction.
frac_conc <- dat |>
  group_by(Source, symbol, frac_class) |>
  summarise(n = n(),
            median = round(median(value_std), 3),
            p25    = round(quantile(value_std, 0.25), 3),
            p75    = round(quantile(value_std, 0.75), 3),
            .groups = "drop") |>
  arrange(Source, symbol, frac_class)

# ── 6. Write outputs ─────────────────────────────────────────────────────────
write_csv(dat,           file.path(out_dir, "grainsize_targets_fines.csv"))
write_csv(frac_summary,  file.path(out_dir, "grainsize_fraction_summary.csv"))
write_csv(fines_summary, file.path(out_dir, "grainsize_fines_summary.csv"))
write_csv(conc_vs_fines, file.path(out_dir, "grainsize_conc_vs_fines.csv"))
write_csv(frac_conc,     file.path(out_dir, "grainsize_bulk_vs_sieved.csv"))

# ── 7. Console summary ───────────────────────────────────────────────────────
cat("grain-size analysis written to", out_dir, "\n")
cat("target measurements per source:\n")
dat |> count(Source, name = "n_measurements") |> as.data.frame() |> print(row.names = FALSE)
cat("\nfraction split (target measurements):\n")
dat |> count(Source, frac_class) |>
  pivot_wider(names_from = frac_class, values_from = n, values_fill = 0) |>
  as.data.frame() |> print(row.names = FALSE)
