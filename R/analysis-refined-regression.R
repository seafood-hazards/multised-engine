# ── Analysis, refined generation: background ─────────────────────────────

analysis_refined_regression <- function(db_dir = multised_db_dir(),
                                        out_dir = multised_analysis_dir(),
                                        verbose = TRUE) {
  # ── Analysis stage, regression normalisation (REFINED database) ──────────────
  # The enrichment factor divides metal by Al, which assumes the two are proportional
  # THROUGH THE ORIGIN. Sediment geochemistry usually shows a non-zero intercept, and a
  # ratio then over-corrects sandy (low-Al) samples and under-corrects muddy ones. The
  # standard alternative fits metal = a + b*Al on a background population and calls a
  # sample enriched when it sits above a band around that line.
  #
  # This does not replace the EF pages. It asks two questions they cannot:
  #
  #   1. IS the intercept non-zero in this data, and by enough to matter? That is an
  #      empirical question about our own samples, not a general claim from the
  #      literature, and it decides whether the ratio was ever a problem here.
  #   2. Where the two methods disagree, WHICH samples are they, and does the
  #      regression verdict track the held-out aquaculture gradient any better?
  #
  # The reference population is exactly the EF reference: offshore (> DIST_BG km) samples
  # on the fraction's adopted aluminium basis. Fitting on the same rows is what makes the
  # two classifiers comparable; anything else would confound the method with its reference.
  #
  # The two verdicts are built to mirror the two EF references:
  #   residual <= 0            <-> EF < 1 against the offshore MEDIAN of metal/Al
  #   residual <= resid P90    <-> EF < 1 against the offshore P90 of metal/Al
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_regression_fits.csv     the fit per element x fraction, with the intercept test
  #   refined_regression_compare.csv  regression verdict against the EF verdict, and where
  #                                   they disagree
  #   refined_regression_pressure.csv the held-out aquaculture gradient under both methods
  #   refined_regression_bins.csv     Al-binned medians for plotting the relationship
  #   refined_regression_meta.csv     one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  DIST_BG   <- 10          # km: the offshore reference, as on the EF page
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  MIN_N     <- 30L
  N_BINS    <- 20L
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull metal, aluminium and the distances ──────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.ratio_al,
           si.dist_to_coast, si.dist_to_aquaculture,
           n.fe AS norm_fe, n.al AS norm_al
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
    WHERE me.outlier_flag IS NULL AND me.value_std > 0
      AND me.ratio_al IS NOT NULL AND me.ratio_al > 0
      AND n.al IS NOT NULL AND n.al > 0
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    mutate(al_basis = refined_al_basis(norm_fe, norm_al),
           on_basis = refined_on_basis(al_basis, cat),
           aq_bin = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS)) |>
    filter(on_basis)

  withheld <- refined_withheld_elements()

  # ── 2. Fit metal = a + b*Al on the offshore reference, per element x fraction ─
  ref <- m |> filter(dist_to_coast > DIST_BG)

  fit_one <- function(df) {
    f  <- stats::lm(value_std ~ norm_al, data = df)
    cf <- summary(f)$coefficients
    res <- stats::residuals(f)
    tibble(n = nrow(df),
           intercept = cf[1, 1], intercept_se = cf[1, 2], intercept_p = cf[1, 4],
           slope = cf[2, 1], slope_se = cf[2, 2], slope_p = cf[2, 4],
           r2 = summary(f)$r.squared,
           resid_sd = stats::sd(res),
           resid_p90 = quantile(res, .9, names = FALSE),
           mean_value = mean(df$value_std))
  }

  fits <- ref |>
    group_by(symbol, cat) |>
    filter(n() >= MIN_N) |>
    group_modify(~ fit_one(.x)) |>
    ungroup() |>
    mutate(
      # the practical question is not whether the intercept differs from zero (with
      # thousands of rows almost anything does) but whether it is large next to the
      # concentrations themselves. A 2% intercept is a rounding error; a 60% one means
      # the ratio is carrying a constant it should not.
      intercept_pct_of_mean = round(100 * intercept / mean_value),
      withheld = symbol %in% withheld) |>
    mutate(across(c(intercept, intercept_se, slope, slope_se, r2, resid_sd,
                    resid_p90, mean_value), ~ signif(.x, 4)),
           across(c(intercept_p, slope_p), ~ signif(.x, 3)))

  # ── 3. Apply the fit to every on-basis sample, and score it both ways ────────
  scored <- m |>
    inner_join(fits |> select(symbol, cat, intercept, slope, resid_p90, withheld),
               by = c("symbol", "cat")) |>
    mutate(predicted = intercept + slope * norm_al,
           residual = value_std - predicted,
           reg_line = residual <= 0,           # mirrors EF < 1 on the median reference
           reg_band = residual <= resid_p90)   # mirrors EF < 1 on the P90 reference

  # the EF verdicts on exactly the same rows, so the comparison is like for like
  ef_ref <- ref |>
    group_by(symbol, cat) |>
    filter(n() >= MIN_N) |>
    summarise(bg_ratio_al = median(ratio_al),
              bg_ratio_al_p90 = quantile(ratio_al, .9, names = FALSE), .groups = "drop")

  scored <- scored |>
    inner_join(ef_ref, by = c("symbol", "cat")) |>
    mutate(ef_median = ratio_al <= bg_ratio_al,
           ef_p90    = ratio_al <= bg_ratio_al_p90)

  pct <- function(x) round(100 * mean(x))
  compare <- scored |>
    group_by(symbol, cat) |>
    summarise(n = n(),
              pct_reg_line = pct(reg_line), pct_ef_median = pct(ef_median),
              pct_reg_band = pct(reg_band), pct_ef_p90 = pct(ef_p90),
              pct_agree_median = pct(reg_line == ef_median),
              pct_reg_only = pct(reg_line & !ef_median),
              pct_ef_only = pct(!reg_line & ef_median),
              .groups = "drop") |>
    left_join(fits |> select(symbol, cat, withheld), by = c("symbol", "cat")) |>
    mutate(across(starts_with("pct_"), ~ if_else(withheld, NA_real_, as.numeric(.x))))

  # ── 4. The held-out check: does either verdict track the farms? ──────────────
  pressure <- scored |>
    filter(!is.na(aq_bin)) |>
    group_by(symbol, cat, aq_bin) |>
    summarise(n = n(), pct_reg_line = pct(reg_line), pct_ef_median = pct(ef_median),
              .groups = "drop") |>
    left_join(fits |> select(symbol, cat, withheld), by = c("symbol", "cat")) |>
    mutate(reliable = n >= MIN_N,
           across(starts_with("pct_"), ~ if_else(withheld, NA_real_, as.numeric(.x))))

  # ── 5. Al-binned medians, so the page can draw the relationship ─────────────
  bins <- ref |>
    semi_join(fits, by = c("symbol", "cat")) |>
    group_by(symbol, cat) |>
    mutate(bin = ntile(norm_al, N_BINS)) |>
    group_by(symbol, cat, bin) |>
    summarise(n = n(),
              al = signif(median(norm_al), 4),
              value_p50 = signif(median(value_std), 4),
              value_p10 = signif(quantile(value_std, .1, names = FALSE), 4),
              value_p90 = signif(quantile(value_std, .9, names = FALSE), 4),
              .groups = "drop")

  meta <- tibble(
    model = "value_std ~ a + b * Al, ordinary least squares, untransformed mg/kg",
    reference = paste0("offshore > ", DIST_BG,
                       " km, on the fraction's adopted aluminium basis (the EF reference)"),
    verdict_line = "residual <= 0, the analogue of EF < 1 on the offshore median",
    verdict_band = "residual <= the offshore P90 of the residuals, the analogue of EF < 1 on the offshore P90",
    min_n = MIN_N, n_bins = N_BINS,
    withheld = paste(withheld, collapse = ","),
    note = "diagnostic and comparison only: no verdict on this page is carried into the dataset download")

  # ── 6. Write ────────────────────────────────────────────────────────────────
  ord <- function(df) df |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat)

  write_csv(ord(fits),     file.path(out_dir, "refined_regression_fits.csv"))
  write_csv(ord(compare),  file.path(out_dir, "refined_regression_compare.csv"))
  write_csv(ord(pressure), file.path(out_dir, "refined_regression_pressure.csv"))
  write_csv(ord(bins),     file.path(out_dir, "refined_regression_bins.csv"))
  write_csv(meta,          file.path(out_dir, "refined_regression_meta.csv"))

  if (verbose) {
    # ── 7. Console summary ──────────────────────────────────────────────────────
    cat("regression normalisation written to", out_dir, "\n\n")
    cat("fit per element x fraction (intercept as % of the mean concentration):\n")
    ord(fits) |>
      select(symbol, cat, n, intercept, intercept_pct_of_mean, intercept_p, slope, r2) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nregression verdict against the EF verdict:\n")
    ord(compare) |>
      select(symbol, cat, n, pct_reg_line, pct_ef_median, pct_agree_median) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
