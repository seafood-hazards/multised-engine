# ── Analysis, refined generation: background ─────────────────────────────
# Converted from R/analysis/background/01_refined_background.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_refined_background <- function(db_dir = multised_db_dir(),
                                        out_dir = multised_analysis_dir(),
                                        verbose = TRUE) {
  # ── Analysis stage, background estimation (REFINED database) ──────────────────
  # The first of the pristine / background-sediment analyses on the refined DB, feeding
  # the multised-refined site. For each element and fraction, summarise the "background"
  # concentration two ways and compare them:
  #
  #  (A) global distribution: percentiles of value_std over all sites (the natural range;
  #      the EFSA 90th percentile is one of these).
  #  (B) offshore subset: the same percentiles restricted to sites far from the coast
  #      (dist_to_coast > DIST_MAIN km). Local pressure, including aquaculture, is
  #      coastal, so an offshore-only distribution is a cleaner background; comparing it
  #      to (A) quantifies the coastal enrichment. Reported with a >20 / >50 km
  #      sensitivity so the cutoff choice is transparent.
  #
  # Categories are per FRACTION: bulk, sieved63, sieved20 (the two sieved cutoffs kept
  # apart, negligible sieved90/500 dropped). Raw value_std (mg/kg, the EFSA target unit);
  # normalised bases (metal/Al, metal/Fe) are a later page. Distributional outliers
  # dropped. Elements with too few rows (Iodine, and Selenium in the sieved fractions)
  # are kept but flagged unreliable (n < MIN_N).
  #
  # Outputs -> data/analysis/background/ (gitignored):
  # WEIGHTING. These percentiles are per MEASUREMENT, so a site sampled in ten years
  # counts ten times and a site sampled once counts once. That is pseudo-replication, and
  # it matters if repeat-sampled sites differ systematically from the rest, which is
  # exactly what a monitoring programme's revisits would do. The site-weighted percentiles
  # (one value per site, that site's median) are computed alongside as a SENSITIVITY, not
  # as a replacement: the size of the gap is what says whether the headline weighting
  # needs to change, and it is reported rather than assumed either way.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_background_percentiles.csv  per element x fraction x subset: full percentiles
  #   refined_background_compare.csv      global vs offshore P90 (+ sensitivity), the shift
  #   refined_background_sitewise.csv     the same P90s weighted one-per-site (sensitivity)
  #   refined_repeat_pressure.csv         are repeat-sampled sites the pressured ones?
  #   refined_background_meta.csv         one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  DIST_MAIN <- 10          # km: primary offshore cutoff
  DIST_SENS <- c(20, 50)   # km: sensitivity cutoffs
  MIN_N     <- 30L         # below this a percentile is flagged unreliable
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  PROBS <- c(min = 0, p5 = .05, p10 = .10, p25 = .25, p50 = .50,
             p75 = .75, p90 = .90, p95 = .95, max = 1)

  pctl <- function(v) {
    q <- quantile(v, PROBS, names = FALSE, na.rm = TRUE)
    bind_cols(tibble(n = length(v)),
              as_tibble(as.list(setNames(signif(q, 4), names(PROBS)))))
  }

  # ── 1. Pull target chemistry + distance to coast, categorised by fraction ────
  con <- dbConnect(SQLite(), db_path)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std,
           si.dist_to_coast, si.site_id, si.n_years, si.dist_to_aquaculture
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS, !is.na(value_std))
  dbDisconnect(con)

  # ── 2. Percentiles for each subset (global + offshore cutoffs) ───────────────
  subset_pctl <- function(df, label) {
    df |> group_by(symbol, cat) |> reframe(pctl(value_std)) |> mutate(subset = label)
  }

  percentiles <- bind_rows(
    subset_pctl(m, "global"),
    subset_pctl(m |> filter(dist_to_coast > DIST_MAIN), sprintf("offshore>%dkm", DIST_MAIN)),
    subset_pctl(m |> filter(dist_to_coast > DIST_SENS[1]), sprintf("offshore>%dkm", DIST_SENS[1])),
    subset_pctl(m |> filter(dist_to_coast > DIST_SENS[2]), sprintf("offshore>%dkm", DIST_SENS[2]))) |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS),
           reliable = n >= MIN_N) |>
    arrange(symbol, cat, subset) |>
    select(symbol, cat, subset, n, reliable, everything())

  # ── 3. Compare: global vs offshore P90 (the background shift) ────────────────
  key <- percentiles |> mutate(symbol = as.character(symbol), cat = as.character(cat))
  g   <- key |> filter(subset == "global")            |> select(symbol, cat, n_global = n, p50_global = p50, p90_global = p90)
  o10 <- key |> filter(subset == sprintf("offshore>%dkm", DIST_MAIN))  |> select(symbol, cat, n_off10 = n, p50_off10 = p50, p90_off10 = p90)
  o20 <- key |> filter(subset == sprintf("offshore>%dkm", DIST_SENS[1])) |> select(symbol, cat, p90_off20 = p90)
  o50 <- key |> filter(subset == sprintf("offshore>%dkm", DIST_SENS[2])) |> select(symbol, cat, p90_off50 = p90)

  compare <- g |>
    left_join(o10, by = c("symbol", "cat")) |>
    left_join(o20, by = c("symbol", "cat")) |>
    left_join(o50, by = c("symbol", "cat")) |>
    mutate(shift_p90 = round(p90_off10 / p90_global, 3),
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat)

  # ── 3b. Site-weighted sensitivity ────────────────────────────────────────────
  # One value per site (that site's median) before taking percentiles, so every site
  # counts once regardless of how often it was revisited.
  site_pctl <- function(df, label) {
    df |>
      group_by(symbol, cat, site_id) |>
      summarise(v = median(value_std), .groups = "drop_last") |>
      summarise(n_sites = n(),
                p50_site = signif(median(v), 4),
                p90_site = signif(quantile(v, .9, names = FALSE), 4),
                .groups = "drop") |>
      mutate(subset = label)
  }

  sitewise <- bind_rows(
    site_pctl(m, "global"),
    site_pctl(m |> filter(dist_to_coast > DIST_MAIN), sprintf("offshore>%dkm", DIST_MAIN))) |>
    left_join(key |> select(symbol, cat, subset, n_meas = n, p50_meas = p50, p90_meas = p90),
              by = c("symbol", "cat", "subset")) |>
    mutate(p90_ratio = round(p90_site / p90_meas, 3),
           reliable = n_sites >= MIN_N,
           symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
    select(symbol, cat, subset, n_meas, n_sites, p50_meas, p50_site,
           p90_meas, p90_site, p90_ratio, reliable) |>
    arrange(symbol, cat, subset)

  # ── 3c. Is the pseudo-replication actually biased? ───────────────────────────
  # The concern is not repeat sampling as such, it is repeat sampling that concentrates on
  # pressured places. That is testable: group the sites by how many years they were
  # sampled and look at where they are.
  repeat_pressure <- m |>
    distinct(site_id, n_years, dist_to_coast, dist_to_aquaculture) |>
    mutate(revisits = case_when(is.na(n_years) | n_years <= 1 ~ "1 year",
                                n_years <= 3                  ~ "2-3 years",
                                TRUE                          ~ "4+ years")) |>
    group_by(revisits) |>
    summarise(n_sites = n(),
              median_dist_to_coast_km = signif(median(dist_to_coast, na.rm = TRUE), 3),
              pct_offshore_gt10km     = round(100 * mean(dist_to_coast > DIST_MAIN,
                                                         na.rm = TRUE)),
              # distance to a farm exists for Norway only, so the farm columns are shares
              # of the sites that HAVE the measure. Counting the rest as "far from a farm"
              # would be counting "not Norwegian" as "not pressured".
              n_sites_with_aqua       = sum(!is.na(dist_to_aquaculture)),
              median_dist_to_aqua_km  = signif(median(dist_to_aquaculture, na.rm = TRUE), 3),
              pct_within_5km_of_farm  = round(100 * mean(dist_to_aquaculture < 5,
                                                         na.rm = TRUE)),
              .groups = "drop") |>
    arrange(factor(revisits, levels = c("1 year", "2-3 years", "4+ years")))

  meta <- tibble(dist_main_km = DIST_MAIN,
                 dist_sens_km = paste(DIST_SENS, collapse = ","),
                 min_n = MIN_N,
                 basis = "raw value_std (mg/kg)",
                 fractions = paste(CATS, collapse = ","),
                 weighting = "headline percentiles are per measurement; refined_background_sitewise.csv reweights one-per-site as a sensitivity")

  # ── 4. Write outputs ─────────────────────────────────────────────────────────
  write_csv(percentiles, file.path(out_dir, "refined_background_percentiles.csv"))
  write_csv(compare,     file.path(out_dir, "refined_background_compare.csv"))
  write_csv(sitewise,    file.path(out_dir, "refined_background_sitewise.csv"))
  write_csv(repeat_pressure, file.path(out_dir, "refined_repeat_pressure.csv"))
  write_csv(meta,        file.path(out_dir, "refined_background_meta.csv"))

  if (verbose) {
    # ── 5. Console summary ───────────────────────────────────────────────────────
    cat("refined background analysis written to", out_dir, "\n\n")
    cat(sprintf("global vs offshore (>%d km) P90 by element x fraction (mg/kg), shift = off/global:\n",
                DIST_MAIN))
    compare |>
      transmute(symbol, cat, n_global, p90_global, n_off10, p90_off10, shift_p90) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nsite-weighted sensitivity (bulk, offshore): one value per site vs per measurement:\n")
    sitewise |> filter(cat == "bulk", subset == sprintf("offshore>%dkm", DIST_MAIN), reliable) |>
      select(symbol, n_meas, n_sites, p90_meas, p90_site, p90_ratio) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nare repeat-sampled sites the pressured ones?\n")
    repeat_pressure |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
