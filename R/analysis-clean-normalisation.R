# ── Analysis, clean generation: normalisation ────────────────────────────
# Converted from R/analysis/normalisation/01_clean_normalisation.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_clean_normalisation <- function(db_dir = multised_db_dir(),
                                         out_dir = multised_analysis_dir(),
                                         verbose = TRUE) {
  # ── Analysis stage, Fe/Al normalisation (per source) ─────────────────────────
  # Normalise the seven target metals to the lithogenic normalisers aluminium (AL)
  # and iron (FE): finer, more aluminosilicate-rich sediment carries more of both
  # the normaliser and the trace metals, so metal/normaliser corrects that
  # grain-size / mineralogical variation. This underpins the enrichment-factor /
  # pristine determination the EFSA spec describes (that cutoff is a later,
  # merged-stage step; here we establish the normalisation itself).
  #
  # Run SEPARATELY per source. Each target is paired with the AL and FE measured on
  # the SAME subsample and SAME fraction (frac_class) -- normalisation is only valid
  # within a comparable fraction, so bulk is matched with bulk, sieved with sieved.
  # All depths kept, reported by EFSA depth band (0-5 / 5-40 / >40 cm, midpoint).
  #
  # Outputs -> data/analysis/normalisation/ (gitignored, like the DBs):
  #   normalisation_pairs.csv        one row per target paired with AL/FE (figures)
  #   normalisation_availability.csv how much target data can be normalised, by band
  #   normalisation_correlation.csv  metal ~ normaliser fit (log-log) by fraction
  #   normalisation_ratios.csv       metal/normaliser distribution (normalised value)

  # ── 0. Config ────────────────────────────────────────────────────────────────
  sources <- tibble(
    Source = c("Mareano", "Vannmilj\u00f8", "ICES-DOME", "MUDAB", "4Demon"),
    stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

  TARGETS    <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  MIN_N      <- 10L

  out_dir <- file.path(out_dir, "normalisation")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  depth_band <- function(depth_from, depth_to) {
    mid <- (depth_from + depth_to) / 2
    band <- cut(mid, breaks = c(-Inf, 5, 40, Inf),
                labels = c("0-5", "5-40", ">40"), right = FALSE)
    as.character(band) |> replace_na("unknown")
  }
  band_levels <- c("0-5", "5-40", ">40", "unknown")

  # ── 1. Build target <-> AL/FE pairs (same subsample, same fraction) ──────────
  build_pairs <- function(stem, Source) {
    con <- dbConnect(SQLite(), file.path(db_dir, sprintf("%s_clean.sqlite", stem)))
    on.exit(dbDisconnect(con))
    meas <- as_tibble(dbReadTable(con, "measurement"))
    ss   <- as_tibble(dbReadTable(con, "subsample"))

    # one value per subsample x fraction x symbol (targets + normalisers)
    agg <- meas |>
      filter(symbol %in% c(TARGETS, NORMALISERS), !is.na(value_std), value_std > 0) |>
      group_by(subsample_id, frac_class, symbol) |>
      summarise(v = mean(value_std), .groups = "drop")

    wide <- agg |> pivot_wider(names_from = symbol, values_from = v)
    for (s in c(TARGETS, NORMALISERS)) if (!s %in% names(wide)) wide[[s]] <- NA_real_

    bands <- ss |> transmute(subsample_id,
                             band = depth_band(depth_from, depth_to))

    wide |>
      left_join(bands, by = "subsample_id") |>
      pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
      filter(!is.na(value_std)) |>
      transmute(Source, subsample_id, frac_class,
                band = factor(band, levels = band_levels),
                symbol, value_std, AL, FE)
  }

  pairs <- pmap_dfr(sources, function(Source, stem) build_pairs(stem, Source))

  # ── 2. Availability: how much target data carries AL / FE ────────────────────
  availability <- pairs |>
    group_by(Source, band) |>
    summarise(n_target = n(),
              n_with_AL = sum(!is.na(AL)),
              n_with_FE = sum(!is.na(FE)),
              pct_AL = round(100 * mean(!is.na(AL))),
              pct_FE = round(100 * mean(!is.na(FE))),
              .groups = "drop") |>
    arrange(Source, band)

  # ── 3. metal ~ normaliser fit (log-log), per source x element x normaliser x fraction
  # Strong log-log correlation => the metal is grain-size / mineralogically
  # controlled, so the normaliser is a good baseline. r2 is that strength.
  long_norm <- pairs |>
    pivot_longer(all_of(NORMALISERS), names_to = "normaliser", values_to = "norm_val") |>
    filter(!is.na(norm_val), norm_val > 0)

  fit_norm <- function(d) {
    m <- lm(log10(value_std) ~ log10(norm_val), d)
    tibble(n = nrow(d),
           r  = suppressWarnings(cor(log10(d$norm_val), log10(d$value_std))),
           r2 = summary(m)$r.squared,
           slope     = unname(coef(m)[2]),
           intercept = unname(coef(m)[1]))
  }

  correlation <- long_norm |>
    group_by(Source, symbol, normaliser, frac_class) |>
    filter(n() >= MIN_N) |>
    group_modify(~ fit_norm(.x)) |>
    ungroup() |>
    mutate(across(c(r, r2, slope, intercept), ~ round(.x, 3))) |>
    arrange(Source, symbol, normaliser, frac_class)

  # ── 4. Normalised ratio (metal / normaliser) distribution ────────────────────
  ratios <- long_norm |>
    mutate(ratio = value_std / norm_val) |>
    group_by(Source, symbol, normaliser, frac_class) |>
    filter(n() >= MIN_N) |>
    summarise(n = n(),
              median = median(ratio),
              p25 = quantile(ratio, 0.25),
              p75 = quantile(ratio, 0.75),
              .groups = "drop") |>
    mutate(across(c(median, p25, p75), ~ signif(.x, 3))) |>
    arrange(Source, symbol, normaliser, frac_class)

  # ── 5. Write outputs ─────────────────────────────────────────────────────────
  write_csv(pairs,        file.path(out_dir, "normalisation_pairs.csv"))
  write_csv(availability, file.path(out_dir, "normalisation_availability.csv"))
  write_csv(correlation,  file.path(out_dir, "normalisation_correlation.csv"))
  write_csv(ratios,       file.path(out_dir, "normalisation_ratios.csv"))

  if (verbose) {
    # ── 6. Console summary ───────────────────────────────────────────────────────
    cat("Fe/Al normalisation written to", out_dir, "\n")
    cat("target measurements paired, and % carrying AL / FE, per source:\n")
    pairs |>
      group_by(Source) |>
      summarise(n_target = n(),
                pct_AL = round(100 * mean(!is.na(AL))),
                pct_FE = round(100 * mean(!is.na(FE))), .groups = "drop") |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nAl-normalisation strength (median r2 of log-log metal~AL, per source):\n")
    correlation |>
      filter(normaliser == "AL") |>
      group_by(Source) |>
      summarise(median_r2 = round(median(r2, na.rm = TRUE), 2), n_fits = n(), .groups = "drop") |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
