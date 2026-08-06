# ── Analysis, merged generation: outlier_review ──────────────────────────
# Converted from R/analysis/outlier_review/01_merged_outlier_review.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_outlier_review <- function(db_dir = multised_db_dir(),
                                           out_dir = multised_analysis_dir(),
                                           verbose = TRUE) {
  require_suggested("ggplot2", "The outlier_review analysis")

  # ── Analysis stage, REVIEW PROTOTYPE for a distributional outlier flag ────────
  # Not a pipeline step yet. The goal is to decide whether a data-driven
  # "potential outlier" label is worth adding for all chemistry elements, and to
  # tune its threshold, by eyeballing what it would flag. Many extreme values are
  # registration errors (decimal shifts, unit swaps) rather than real chemistry.
  #
  # Method (see docs / discussion):
  #   * chemistry only (element.category target / reference / organic); grain-size
  #     composition is bounded 0-100% and handled by the step-14 correction, so it
  #     is excluded here.
  #   * work on log10(value_std): concentrations are strictly positive and span up
  #     to ~4-5 orders of magnitude, roughly log-normal.
  #   * group on ELEMENT x FRACTION (bulk / sieved63 / sieved20). Fraction must be
  #     split: sieved medians run 1.5-3x bulk, so a pooled threshold mis-flags
  #     legitimate sieved values. Region is NOT stratified: regional spread (~2x)
  #     is trivial next to the 10-1000x registration errors we are after.
  #   * robust centre/spread per group: median +/- k * MAD on the log scale.
  #
  #   * DUAL CRITERION (this iteration): a row is flagged only when it is BOTH a
  #     statistical outlier (|robust_z| > K_FLAG) AND at least MIN_OOM orders of
  #     magnitude from the group median (|log10(value/median)| > MIN_OOM). The
  #     order-of-magnitude floor is what targets registration errors specifically:
  #     it keeps the wide-distribution catches (CU/ZN/MN/CORG) but spares narrow
  #     (SE, MAD ~0.13) and skewed real tails, where a value "far" in MAD units is
  #     still within the same order of magnitude. Equivalently, the effective
  #     boundary on the log scale is median +/- max(K_FLAG * MAD, MIN_OOM).
  #
  #   * small-n guard: groups below MIN_N are left unflagged (robust stats
  #     unreliable, e.g. Iodine); those rely on the existing generous range_flag.
  #
  # Note on the low tail: the merged DB has already had below-LOQ rows removed at
  # the clean stage (no below_loq column here), so surviving low values are
  # above-detection. Low flags are therefore genuine-low OR a dropped-decimal
  # error, and are kept for review rather than deferred to a detection flag.
  #
  # This complements, not replaces, the pipeline's existing markers: range_flag
  # (generous PHYSICAL bounds, misses an in-range 10x shift), invalid_flag
  # (negatives), below_loq, and 4Demon's native outlier_* flags. This one is the
  # statistical/distributional view.
  #
  # Outputs -> data/analysis/outlier_review/ (gitignored, review only):
  #   outlier_group_summary.csv   element x fraction robust stats + dual counts
  #   outlier_candidates.csv      the dual-flagged rows, with context to review
  #   outlier_dist_<category>.png  log10 distributions with effective thresholds

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)
  MIN_N   <- 100L                 # minimum group size to compute a threshold
  K_FLAG  <- 4                    # robust-z multiplier
  MIN_OOM <- 1.0                  # min |log10(value/median)| = orders of magnitude
  FRACTIONS <- c("bulk", "sieved63", "sieved20")

  out_dir <- file.path(out_dir, "outlier_review")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Chemistry measurements with context ───────────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  raw <- dbGetQuery(con, "
    SELECT m.measurement_id, m.symbol, e.category, e.name AS element_name,
           m.value_std, m.unit_std, m.frac_class, m.sieve_um_std,
           m.source,
           s.depth_from, s.depth_to,
           si.latitude AS lat, si.longitude AS lon,
           si.sea_name, si.country
    FROM measurement m
      JOIN element   e  ON e.symbol       = m.symbol
      JOIN subsample s  ON s.subsample_id = m.subsample_id
      JOIN event     ev ON ev.event_id    = s.event_id
      JOIN site      si ON si.site_id      = ev.site_id
    WHERE e.category IN ('target', 'reference', 'organic')
      AND m.value_std > 0
  ") |>
    as_tibble()
  dbDisconnect(con)

  ELEM_ORDER <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN", "FE", "AL",
                  "CORG", "TOC", "TOC63")

  d <- raw |>
    mutate(
      fraction = case_when(
        frac_class == "bulk"                        ~ "bulk",
        frac_class == "sieved" & sieve_um_std == 63 ~ "sieved63",
        frac_class == "sieved" & sieve_um_std == 20 ~ "sieved20",
        TRUE                                        ~ "other"),
      logv = log10(value_std)) |>
    filter(fraction %in% FRACTIONS)

  # ── 2. Robust per-group statistics (element x fraction) ──────────────────────
  grp <- d |>
    group_by(category, symbol, element_name, fraction) |>
    summarise(
      n      = n(),
      med_log = median(logv),
      mad_log = mad(logv),                       # constant 1.4826 (normal-consistent)
      .groups = "drop") |>
    mutate(enough = n >= MIN_N & mad_log > 0)

  # attach robust z and order-of-magnitude distance to every measurement
  dz <- d |>
    left_join(grp |> select(category, symbol, fraction, med_log, mad_log, enough),
              by = c("category", "symbol", "fraction")) |>
    mutate(
      robust_z = if_else(enough, (logv - med_log) / mad_log, NA_real_),
      oom      = if_else(enough, logv - med_log, NA_real_))   # signed log10 ratio

  # dual-criterion flag: statistical outlier AND >= min_oom from the median
  dual_flag <- function(z, oom, k, min_oom, dir) {
    hit <- abs(z) > k & abs(oom) > min_oom
    if (dir == "high") sum(hit & oom > 0, na.rm = TRUE)
    else               sum(hit & oom < 0, na.rm = TRUE)
  }

  # ── 3. Group summary: dual-criterion counts at two OOM floors ────────────────
  summary_tbl <- grp |>
    mutate(median_val = round(10^med_log, 3)) |>
    left_join(
      dz |>
        group_by(category, symbol, fraction) |>
        summarise(
          hi_oom1.0  = dual_flag(robust_z, oom, K_FLAG, 1.00, "high"),
          lo_oom1.0  = dual_flag(robust_z, oom, K_FLAG, 1.00, "low"),
          hi_oom0.75 = dual_flag(robust_z, oom, K_FLAG, 0.75, "high"),
          lo_oom0.75 = dual_flag(robust_z, oom, K_FLAG, 0.75, "low"),
          .groups = "drop"),
      by = c("category", "symbol", "fraction")) |>
    mutate(symbol = factor(symbol, levels = ELEM_ORDER),
           fraction = factor(fraction, levels = FRACTIONS)) |>
    arrange(category, symbol, fraction) |>
    mutate(symbol = as.character(symbol), fraction = as.character(fraction)) |>
    select(category, symbol, element_name, fraction, n, median_val, mad_log,
           enough, hi_oom1.0, lo_oom1.0, hi_oom0.75, lo_oom0.75)

  write_csv(summary_tbl, file.path(out_dir, "outlier_group_summary.csv"))

  # ── 4. Candidate list at (K_FLAG, MIN_OOM) — rows to eyeball ─────────────────
  candidates <- dz |>
    filter(!is.na(robust_z), abs(robust_z) > K_FLAG, abs(oom) > MIN_OOM) |>
    mutate(direction    = if_else(oom > 0, "high", "low"),
           group_median = round(10^med_log, 3),
           fold_vs_med  = round(10^oom, 2),      # value / median, linear scale
           robust_z     = round(robust_z, 2),
           oom          = round(oom, 2)) |>
    transmute(measurement_id, category, symbol, fraction,
              value_std = round(value_std, 4), unit_std,
              group_median, fold_vs_med, oom, robust_z, direction,
              source, sea_name, country, lat, lon, depth_from, depth_to) |>
    arrange(category, symbol, fraction, desc(abs(oom)))

  write_csv(candidates, file.path(out_dir, "outlier_candidates.csv"))

  # ── 5. Distribution plots (one per category), EFFECTIVE thresholds drawn ─────
  # effective boundary = median +/- max(K_FLAG * MAD, MIN_OOM); shows the OOM
  # floor pushing narrow-distribution thresholds outward.
  bulk_thr <- grp |>
    filter(fraction == "bulk", enough) |>
    mutate(half = pmax(K_FLAG * mad_log, MIN_OOM),
           lo = med_log - half, hi = med_log + half)

  plot_category <- function(cat) {
    dd <- d |> filter(category == cat)
    if (nrow(dd) == 0) return(invisible())
    thr <- bulk_thr |> filter(category == cat)
    p <- ggplot2::ggplot(dd, ggplot2::aes(logv, colour = fraction)) +
      ggplot2::geom_density(na.rm = TRUE) +
      ggplot2::geom_vline(data = thr, ggplot2::aes(xintercept = med_log),
                 linetype = "dotted", colour = "grey40") +
      ggplot2::geom_vline(data = thr, ggplot2::aes(xintercept = lo),
                 linetype = "dashed", colour = "firebrick") +
      ggplot2::geom_vline(data = thr, ggplot2::aes(xintercept = hi),
                 linetype = "dashed", colour = "firebrick") +
      ggplot2::facet_wrap(~ symbol, scales = "free") +
      ggplot2::labs(title = paste0("log10(value_std) by fraction, category: ", cat),
           subtitle = paste0("dotted = bulk median; dashed red = bulk effective ",
                             "boundary, median +/- max(", K_FLAG,
                             " x MAD, ", MIN_OOM, " oom)  (sieved in the CSV)"),
           x = "log10 value_std (mg/kg)", y = "density") +
      ggplot2::theme_bw(base_size = 10) +
      ggplot2::theme(legend.position = "bottom")
    ggplot2::ggsave(file.path(out_dir, paste0("outlier_dist_", cat, ".png")),
           p, width = 10, height = 7, dpi = 110)
  }
  walk(c("target", "reference", "organic"), plot_category)

  # ── 6. Console recap ─────────────────────────────────────────────────────────
  message("outlier review (dual criterion: |z|>", K_FLAG, " AND |oom|>", MIN_OOM,
          ") written to ", out_dir, ":")
  message("  groups summarised: ", nrow(summary_tbl),
          " (", sum(summary_tbl$enough), " with a usable threshold)")
  message("  candidates: ", nrow(candidates),
          " (high ", sum(candidates$direction == "high"),
          ", low ", sum(candidates$direction == "low"), ")")
  message("  of ", nrow(d), " chemistry measurements")


  invisible(out_dir)
}
