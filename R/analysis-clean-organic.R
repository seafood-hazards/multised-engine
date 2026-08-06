# ── Analysis, clean generation: organic ──────────────────────────────────
# Converted from R/analysis/organic/01_clean_organic.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_clean_organic <- function(db_dir = multised_db_dir(),
                                   out_dir = multised_analysis_dir(),
                                   verbose = TRUE) {
  # ── Analysis stage, organic carbon (per source) ──────────────────────────────
  # Trace metals bind to organic matter, so total organic carbon (CORG) is a third
  # control on their concentration alongside grain size and the Fe/Al normalisers.
  # This relates each target metal to the co-located CORG, per source, to see which
  # metals are organic-associated (expected for the chalcophile / redox-sensitive
  # ones, e.g. MO, which the Fe/Al normalisation did NOT explain). The EFSA spec
  # records organic matter as TOC%, so distributions are reported in percent.
  #
  # Run SEPARATELY per source. Each target is paired with the CORG on the SAME
  # subsample and SAME fraction (bulk with bulk, sieved with sieved). CORG is in
  # mg/kg (value_std); percent = value_std / 10000. 4Demon has no organic carbon.
  # All depths kept, reported by EFSA depth band (0-5 / 5-40 / >40 cm, midpoint).
  #
  # Outputs -> data/analysis/organic/ (gitignored, like the DBs):
  #   organic_pairs.csv         one row per target paired with CORG (figures)
  #   organic_availability.csv  how much target data carries CORG, by band
  #   organic_distribution.csv  CORG (%) distribution by band / fraction
  #   organic_correlation.csv   metal ~ CORG fit (log-log) by fraction

  # ── 0. Config ────────────────────────────────────────────────────────────────
  sources <- tibble(
    Source = c("Mareano", "Vannmilj\u00f8", "ICES-DOME", "MUDAB", "4Demon"),
    stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

  TARGETS <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  ORGANIC <- "CORG"        # whole-sample organic carbon (TOC -> CORG in clean)
  MG_PER_PCT <- 10000      # mg/kg per 1 % organic carbon
  MIN_N   <- 10L

  out_dir <- file.path(out_dir, "organic")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  depth_band <- function(depth_from, depth_to) {
    mid <- (depth_from + depth_to) / 2
    band <- cut(mid, breaks = c(-Inf, 5, 40, Inf),
                labels = c("0-5", "5-40", ">40"), right = FALSE)
    as.character(band) |> replace_na("unknown")
  }
  band_levels <- c("0-5", "5-40", ">40", "unknown")

  # ── 1. Build target <-> CORG pairs (same subsample, same fraction) ───────────
  build_pairs <- function(stem, Source) {
    con <- dbConnect(SQLite(), file.path(db_dir, sprintf("%s_clean.sqlite", stem)))
    on.exit(dbDisconnect(con))
    meas <- as_tibble(dbReadTable(con, "measurement"))
    ss   <- as_tibble(dbReadTable(con, "subsample"))

    agg <- meas |>
      filter(symbol %in% c(TARGETS, ORGANIC), !is.na(value_std), value_std > 0) |>
      group_by(subsample_id, frac_class, symbol) |>
      summarise(v = mean(value_std), .groups = "drop")

    wide <- agg |> pivot_wider(names_from = symbol, values_from = v)
    for (s in c(TARGETS, ORGANIC)) if (!s %in% names(wide)) wide[[s]] <- NA_real_

    bands <- ss |> transmute(subsample_id, band = depth_band(depth_from, depth_to))

    wide |>
      left_join(bands, by = "subsample_id") |>
      pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
      filter(!is.na(value_std)) |>
      transmute(Source, subsample_id, frac_class,
                band = factor(band, levels = band_levels),
                symbol, value_std,
                CORG, corg_pct = CORG / MG_PER_PCT)
  }

  pairs <- pmap_dfr(sources, function(Source, stem) build_pairs(stem, Source))

  # ── 2. Availability: how much target data carries CORG ───────────────────────
  availability <- pairs |>
    group_by(Source, band) |>
    summarise(n_target = n(),
              n_with_CORG = sum(!is.na(CORG)),
              pct_CORG = round(100 * mean(!is.na(CORG))),
              .groups = "drop") |>
    arrange(Source, band)

  # ── 3. Organic carbon distribution (percent), by band / fraction ─────────────
  distribution <- pairs |>
    filter(!is.na(corg_pct)) |>
    distinct(Source, subsample_id, frac_class, band, corg_pct) |>
    group_by(Source, band, frac_class) |>
    summarise(n_subsamples = n(),
              median = round(median(corg_pct), 2),
              p25 = round(quantile(corg_pct, 0.25), 2),
              p75 = round(quantile(corg_pct, 0.75), 2),
              max = round(max(corg_pct), 1),
              .groups = "drop") |>
    arrange(Source, band, frac_class)

  # ── 4. metal ~ CORG fit (log-log), per source x element x fraction ───────────
  # Strong log-log correlation => the metal is organic-associated. Compare with the
  # Fe/Al result: metals weak on Al but strong on CORG are organically controlled.
  fit_org <- function(d) {
    m <- lm(log10(value_std) ~ log10(CORG), d)
    tibble(n = nrow(d),
           r  = suppressWarnings(cor(log10(d$CORG), log10(d$value_std))),
           r2 = summary(m)$r.squared,
           slope = unname(coef(m)[2]))
  }

  correlation <- pairs |>
    filter(!is.na(CORG), CORG > 0) |>
    group_by(Source, symbol, frac_class) |>
    filter(n() >= MIN_N) |>
    group_modify(~ fit_org(.x)) |>
    ungroup() |>
    mutate(across(c(r, r2, slope), ~ round(.x, 3))) |>
    arrange(Source, symbol, frac_class)

  # ── 5. Write outputs ─────────────────────────────────────────────────────────
  write_csv(pairs,        file.path(out_dir, "organic_pairs.csv"))
  write_csv(availability, file.path(out_dir, "organic_availability.csv"))
  write_csv(distribution, file.path(out_dir, "organic_distribution.csv"))
  write_csv(correlation,  file.path(out_dir, "organic_correlation.csv"))

  if (verbose) {
    # ── 6. Console summary ───────────────────────────────────────────────────────
    cat("organic-carbon analysis written to", out_dir, "\n")
    cat("target measurements paired, and % carrying CORG, per source:\n")
    pairs |>
      group_by(Source) |>
      summarise(n_target = n(), pct_CORG = round(100 * mean(!is.na(CORG))),
                .groups = "drop") |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nmetal ~ CORG strength (bulk r2 of log-log fit, per element, pooled sources):\n")
    correlation |>
      filter(frac_class == "bulk") |>
      group_by(symbol) |>
      summarise(median_r2 = round(median(r2, na.rm = TRUE), 2), n_fits = n(),
                .groups = "drop") |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
