# ── Analysis, refined generation: background ─────────────────────────────

analysis_refined_pressure_controls <- function(db_dir = multised_db_dir(),
                                               out_dir = multised_analysis_dir(),
                                               verbose = TRUE) {
  # ── Analysis stage, controls on the pressure gradient (REFINED database) ─────
  # The pressure-based background reads the near/far P90 ratio as near-cage enrichment.
  # Two confounders make that reading optimistic, and both are testable here.
  #
  # 1. GEOGRAPHY. The far band is the national >20 km pool, which is open shelf, while the
  #    near band is fjord. Comparing them compares two settings as much as two pressures.
  #    Control: match WITHIN municipality, near (<1 km) against local far (>= 5 km), and
  #    take the median of the per-municipality ratios.
  #
  # 2. TIME. Every sample is keyed to its NEAREST farm, whether or not that farm existed
  #    when the sediment was sampled. The aquaculture reference carries start_year /
  #    end_year / active, so each near-farm measurement can be placed before the farm was
  #    licensed, during its operation, or after it closed. Only the operating ones are
  #    evidence about farm pressure.
  #
  # BOTH THE DISTANCE AND THE FARM IDENTITY ARE THE FISH FARM'S. This step used to band on
  # `dist_to_aquaculture` and take the licence dates from `aqua_id`, the nearest
  # aquaculture site of ANY kind, which may be a mussel raft or a land-based smolt plant.
  # It now bands on `dist_to_fish_farm` and reads the dates through `fish_farm_aqua_id`,
  # so the farm whose lifetime is tested is the farm the distance is measured to. That
  # column was added to clean step 5 in August 2026, so this step needs a clean DB built
  # after that date. See the pressure step for what the old axis was picking up.
  #
  # Neither control is free of its own bias, so the covariate table records how the
  # subsets differ in distance to coast and mud content: matching on municipality does
  # not match on sediment.
  #
  # Raw value_std (mg/kg), outliers dropped, Norway only (dist_to_fish_farm is
  # Norwegian). This analysis qualifies the pressure page; it does not replace it, and it
  # feeds no verdict.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_temporal_alignment.csv  element x fraction x band x farm period: n, P50, P90
  #   refined_pressure_controls.csv   the near/far ratio under each control, side by side
  #                                   (n_far is the national background band for the first
  #                                   two controls and the pooled local far band for the
  #                                   matched ones; ratio_p50 / n_mun / pct_mun_gt1 exist
  #                                   only for the matched rows)
  #   refined_matched_municipality.csv  per-municipality near/far ratios that pass
  #   refined_control_covariates.csv  what the subsets differ in besides pressure
  #   refined_pressure_controls_meta.csv  one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  NEAR_KM   <- 1      # the near band, as on the pressure page
  LOCAL_KM  <- 5      # the local far band used inside a municipality
  BG_KM     <- 20     # the national background band, as on the pressure page
  MIN_N     <- 30L    # per element x fraction x subset
  MIN_MATCH <- 10L    # per municipality per band, for a pair to count
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  p90 <- function(x) quantile(x, .9, names = FALSE)

  # ── 1. Pull chemistry, geography, sampling year and the linked farm's dates ──
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.source,
           si.municipality, si.dist_to_fish_farm, si.dist_to_coast,
           s.fines_lt63, e.year, d.pressure_class,
           a.start_year, a.end_year, a.active
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN element el  ON el.symbol      = me.symbol
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    LEFT JOIN aquaculture a ON a.aqua_id = si.fish_farm_aqua_id
    WHERE el.category = 'target' AND me.value_std > 0 AND me.outlier_flag IS NULL
      AND si.dist_to_fish_farm IS NOT NULL
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    mutate(
      band = case_when(dist_to_fish_farm < NEAR_KM ~ "near",
                       dist_to_fish_farm >= BG_KM ~ "background",
                       dist_to_fish_farm >= LOCAL_KM ~ "local far",
                       TRUE ~ "intermediate"),
      # the far bands are only a background if what is in them is unpressured, and the
      # raw >20 km pool is not: over half its copper and zinc is Vannmiljo stated-pressure
      # monitoring. Cleaned exactly as the pressure step cleans it, and only in the FAR
      # bands: a near-cage sample filed as aquaculture monitoring is the point, not a
      # contaminant.
      stated_pressure = !is.na(pressure_class) & pressure_class == "pressure",
      # a farm period only exists where the sample has a year and the farm has a start
      period = case_when(
        is.na(year) | is.na(start_year) ~ NA_character_,
        year < start_year ~ "pre-farm",
        active == 1L | (!is.na(end_year) & year <= end_year) ~ "operating",
        TRUE ~ "post-closure"))

  # ── 2. Where the near-farm samples sit in their farm's lifetime ──────────────
  temporal <- m |>
    filter(dist_to_fish_farm < LOCAL_KM, !is.na(period)) |>
    mutate(band = if_else(dist_to_fish_farm < NEAR_KM, "<1km", "1-5km")) |>
    group_by(symbol, cat, band, period) |>
    summarise(n = n(), p50 = signif(median(value_std), 4),
              p90 = signif(p90(value_std), 4),
              median_year = median(year), .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS),
           reliable = n >= MIN_N) |>
    arrange(symbol, cat, band, period)

  # ── 3. The national background band, as on the pressure page (cleaned) ───────
  bg <- m |>
    filter(band == "background", !stated_pressure) |>
    group_by(symbol, cat) |>
    summarise(n_bg = n(), p90_bg = p90(value_std), .groups = "drop")

  # ── 4. Control A: restrict the near band to samples taken while the farm ran ─
  near_ratio <- function(rows, label) {
    rows |>
      filter(band == "near") |>
      group_by(symbol, cat) |>
      summarise(n_near = n(), p90_near = p90(value_std), .groups = "drop") |>
      inner_join(bg, by = c("symbol", "cat")) |>
      transmute(symbol, cat, control = label, n_near, n_far = n_bg,
                ratio_p90 = signif(p90_near / p90_bg, 3))
  }

  # ── 5. Control B: match near against local far inside one municipality ───────
  matched_pairs <- function(rows, label) {
    pairs <- rows |>
      filter(band %in% c("near", "local far"), !is.na(municipality),
             band == "near" | !stated_pressure) |>
      group_by(symbol, cat, municipality, band) |>
      summarise(n = n(), p50 = median(value_std), p90 = p90(value_std), .groups = "drop") |>
      pivot_wider(names_from = band, values_from = c(n, p50, p90)) |>
      rename(n_near = `n_near`, n_far = `n_local far`,
             p50_near = `p50_near`, p50_far = `p50_local far`,
             p90_near = `p90_near`, p90_far = `p90_local far`) |>
      filter(!is.na(n_near), !is.na(n_far), n_near >= MIN_MATCH, n_far >= MIN_MATCH) |>
      mutate(control = label,
             ratio_p90 = signif(p90_near / p90_far, 3),
             ratio_p50 = signif(p50_near / p50_far, 3))
    pairs
  }

  operating_only <- m |> filter(band != "near" | period %in% "operating")

  controls <- bind_rows(
    near_ratio(m, "published"),
    near_ratio(operating_only, "operating only"))

  pairs_all <- matched_pairs(m, "municipality-matched")
  pairs_op  <- matched_pairs(operating_only, "matched + operating")
  pairs <- bind_rows(pairs_all, pairs_op)

  matched_summary <- pairs |>
    group_by(symbol, cat, control) |>
    # pct_mun_gt1 must be computed before ratio_p90 is replaced by its median:
    # summarise() evaluates in order and later expressions see the new column.
    summarise(n_mun = n(), n_near = sum(n_near), n_far = sum(n_far),
              pct_mun_gt1 = round(100 * mean(ratio_p90 > 1)),
              ratio_p90 = signif(median(ratio_p90), 3),
              ratio_p50 = signif(median(ratio_p50), 3), .groups = "drop") |>
    filter(n_mun >= 3)

  controls <- bind_rows(controls, matched_summary) |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS),
           control = factor(control, levels = c("published", "operating only",
                                                "municipality-matched",
                                                "matched + operating")),
           reliable = n_near >= MIN_N) |>
    arrange(symbol, cat, control)

  # ── 6. What the controls do not fix ─────────────────────────────────────────
  covariates <- m |>
    filter(cat == "bulk") |>
    mutate(subset = case_when(
      band == "background" & !stated_pressure ~ "background (>20 km)",
      band == "near" & period %in% "pre-farm" ~ "near, pre-farm",
      band == "near" & period %in% "operating" ~ "near, operating",
      band == "near" & period %in% "post-closure" ~ "near, post-closure",
      band == "local far" & !stated_pressure ~ "local far (5-20 km)",
      TRUE ~ NA_character_)) |>
    filter(!is.na(subset)) |>
    distinct(subset, municipality, year, dist_to_coast, fines_lt63, source,
             dist_to_fish_farm) |>
    group_by(subset) |>
    summarise(n_samples = n(),
              median_year = median(year, na.rm = TRUE),
              median_dist_to_coast_km = signif(median(dist_to_coast, na.rm = TRUE), 3),
              median_fines_pct = signif(median(fines_lt63, na.rm = TRUE), 3),
              pct_with_fines = round(100 * mean(!is.na(fines_lt63))),
              .groups = "drop")

  meta <- tibble(near_km = NEAR_KM, local_far_km = LOCAL_KM, background_km = BG_KM,
                 min_n = MIN_N, min_per_municipality = MIN_MATCH,
                 period_rule = paste("pre-farm: year < start_year;",
                                     "operating: year >= start_year and (active or",
                                     "year <= end_year); post-closure: closed and",
                                     "year > end_year"),
                 farm_link = paste("site.fish_farm_aqua_id, the NEAREST fish farm,",
                                   "which may not be the farm that was there at the time"),
                 far_band_excludes = "pressure_class = 'pressure' (stated pressure monitoring)",
                 scope = "Norway (dist_to_fish_farm), raw value_std, outliers dropped")

  # ── 7. Write ────────────────────────────────────────────────────────────────
  write_csv(temporal,   file.path(out_dir, "refined_temporal_alignment.csv"))
  write_csv(controls,   file.path(out_dir, "refined_pressure_controls.csv"))
  write_csv(pairs |> mutate(symbol = factor(symbol, levels = elem_levels)) |>
              arrange(symbol, cat, control, municipality),
            file.path(out_dir, "refined_matched_municipality.csv"))
  write_csv(covariates, file.path(out_dir, "refined_control_covariates.csv"))
  write_csv(meta,       file.path(out_dir, "refined_pressure_controls_meta.csv"))

  if (verbose) {
    # ── 8. Console summary ──────────────────────────────────────────────────────
    cat("pressure controls written to", out_dir, "\n\n")
    cat("bulk near/far P90 ratio under each control:\n")
    controls |> filter(cat == "bulk") |>
      select(symbol, control, n_near, ratio_p90) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nnear-farm bulk measurements by farm period:\n")
    temporal |> filter(cat == "bulk", band == "<1km") |>
      select(symbol, period, n, p90) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
