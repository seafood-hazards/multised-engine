# ── Analysis, merged generation: normalisation ───────────────────────────
# Converted from R/analysis/normalisation/01_merged_normalisation.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_normalisation <- function(db_dir = multised_db_dir(),
                                          out_dir = multised_analysis_dir(),
                                          verbose = TRUE) {
  # ── Analysis stage, Fe/Al normalisation (MERGED database) ────────────────────
  # The merged-database counterpart of 01_clean_normalisation.R. Same question:
  # normalise the seven target metals to the lithogenic normalisers aluminium (AL)
  # and iron (FE), because finer, more aluminosilicate-rich sediment carries more
  # of both the normaliser and the trace metals, so metal/normaliser corrects that
  # grain-size / mineralogical variation. Run once on multised_merged.sqlite, where
  # cross-source duplicates are already removed, so the four sources are POOLED
  # into one best estimate per element (Source kept for a per-source breakdown).
  #
  # Each target is paired with the AL and FE measured on the SAME subsample and
  # SAME fraction (frac_class): normalisation is only valid within a comparable
  # fraction, so bulk is matched with bulk. The headline is bulk (whole sample);
  # sieved pairs are computed too but reported apart.
  #
  # From the merge, two things the per-source clean version could not do:
  #   * outliers dropped. The distributional outlier_flag (registration errors,
  #     mostly) is excluded from BOTH target and normaliser, so a bad value does
  #     not distort a log-log fit or a ratio.
  #   * one pooled fit per element, not double-weighted across overlapping sources.
  #
  # All depths kept, reported by EFSA depth band (0-5 / 5-40 / >40 cm, midpoint).
  #
  # Outputs -> data/analysis/normalisation/ (gitignored). The multised-merged site
  # renders tables + figures from these files:
  #   merged_normalisation_pairs.csv        bulk target paired with AL/FE (figures)
  #   merged_normalisation_availability.csv  how much bulk target carries AL/FE
  #   merged_normalisation_correlation.csv   metal ~ normaliser fit (log-log)
  #   merged_normalisation_ratios.csv        metal/normaliser (normalised value)

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)

  TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  MIN_N       <- 30L

  out_dir <- file.path(out_dir, "normalisation")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  depth_band <- function(depth_from, depth_to) {
    mid <- (depth_from + depth_to) / 2
    band <- cut(mid, breaks = c(-Inf, 5, 40, Inf),
                labels = c("0-5", "5-40", ">40"), right = FALSE)
    as.character(band) |> replace_na("unknown")
  }
  band_levels <- c("0-5", "5-40", ">40", "unknown")
  elem_levels <- TARGETS

  # ── 1. Build target <-> AL/FE pairs (same subsample, same fraction) ──────────
  # Outliers excluded (targets and normalisers) so a bad value cannot enter a pair.
  con <- dbConnect(SQLite(), db_path)

  meas <- dbGetQuery(con, sprintf("
    SELECT m.subsample_id, m.source AS Source, m.frac_class, m.symbol, m.value_std
    FROM measurement m
    WHERE m.symbol IN (%s)
      AND m.value_std > 0
      AND m.outlier_flag IS NULL
  ", paste(sprintf("'%s'", c(TARGETS, NORMALISERS)), collapse = ", "))) |>
    as_tibble()

  ss <- dbGetQuery(con, "SELECT subsample_id, depth_from, depth_to FROM subsample") |>
    as_tibble()
  dbDisconnect(con)

  # Source is a per-row provenance; a subsample belongs to one source in the merged
  # DB, so keep the first for grouping. One value per subsample x fraction x symbol.
  agg <- meas |>
    group_by(subsample_id, Source, frac_class, symbol) |>
    summarise(v = mean(value_std), .groups = "drop")

  wide <- agg |>
    pivot_wider(names_from = symbol, values_from = v)
  for (s in c(TARGETS, NORMALISERS)) if (!s %in% names(wide)) wide[[s]] <- NA_real_

  bands <- ss |> transmute(subsample_id, band = depth_band(depth_from, depth_to))

  pairs <- wide |>
    left_join(bands, by = "subsample_id") |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std)) |>
    transmute(Source, subsample_id, frac_class,
              band = factor(band, levels = band_levels),
              symbol = factor(symbol, levels = elem_levels), value_std, AL, FE)

  # bulk is the analysable track for normalisation; keep it for pairs/availability.
  pairs_bulk <- pairs |> filter(frac_class == "bulk")

  # ── 2. Availability: how much bulk target data carries AL / FE, by band ──────
  availability <- pairs_bulk |>
    group_by(symbol, band) |>
    summarise(n_target = n(),
              n_with_AL = sum(!is.na(AL)),
              n_with_FE = sum(!is.na(FE)),
              pct_AL = round(100 * mean(!is.na(AL))),
              pct_FE = round(100 * mean(!is.na(FE))),
              .groups = "drop") |>
    arrange(symbol, band)

  # ── 3. metal ~ normaliser fit (log-log): pooled and per-source (bulk) ────────
  # Strong log-log correlation => the metal is grain-size / mineralogically
  # controlled, so the normaliser is a good baseline. r2 is that strength.
  long_norm <- pairs_bulk |>
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

  corr_pooled <- long_norm |>
    group_by(symbol, normaliser) |>
    filter(n() >= MIN_N) |>
    group_modify(~ fit_norm(.x)) |>
    ungroup() |>
    mutate(Source = "All (pooled)", .before = symbol)

  corr_source <- long_norm |>
    group_by(Source, symbol, normaliser) |>
    filter(n() >= MIN_N) |>
    group_modify(~ fit_norm(.x)) |>
    ungroup()

  correlation <- bind_rows(corr_pooled, corr_source) |>
    mutate(across(c(r, r2, slope, intercept), ~ round(.x, 3))) |>
    arrange(Source, symbol, normaliser)

  # ── 4. Normalised ratio (metal / normaliser) distribution, pooled (bulk) ─────
  ratios <- long_norm |>
    mutate(ratio = value_std / norm_val) |>
    group_by(symbol, normaliser) |>
    filter(n() >= MIN_N) |>
    summarise(n = n(),
              median = median(ratio),
              p25 = quantile(ratio, 0.25),
              p75 = quantile(ratio, 0.75),
              .groups = "drop") |>
    mutate(across(c(median, p25, p75), ~ signif(.x, 3))) |>
    arrange(symbol, normaliser)

  # ── 5. Write outputs ─────────────────────────────────────────────────────────
  # pairs CSV keeps only bulk rows that carry at least one normaliser (for figures).
  pairs_out <- pairs_bulk |>
    filter(!is.na(AL) | !is.na(FE)) |>
    transmute(Source, symbol = as.character(symbol), band = as.character(band),
              value_std, AL, FE)

  write_csv(pairs_out,    file.path(out_dir, "merged_normalisation_pairs.csv"))
  write_csv(availability, file.path(out_dir, "merged_normalisation_availability.csv"))
  write_csv(correlation,  file.path(out_dir, "merged_normalisation_correlation.csv"))
  write_csv(ratios,       file.path(out_dir, "merged_normalisation_ratios.csv"))

  if (verbose) {
    # ── 6. Console summary ───────────────────────────────────────────────────────
    cat("merged Fe/Al normalisation written to", out_dir, "\n\n")
    cat("bulk target measurements, and % carrying AL / FE (outliers dropped):\n")
    pairs_bulk |>
      group_by(symbol, .drop = FALSE) |>
      summarise(n_target = n(),
                pct_AL = round(100 * mean(!is.na(AL))),
                pct_FE = round(100 * mean(!is.na(FE))), .groups = "drop") |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\npooled log-log fit strength (r2) by element x normaliser:\n")
    corr_pooled |>
      mutate(r2 = round(r2, 2)) |>
      select(symbol, normaliser, n, r2) |>
      pivot_wider(names_from = normaliser, values_from = c(n, r2)) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
