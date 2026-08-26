# ── Analysis, refined generation: background ─────────────────────────────
# Converted from R/analysis/background/03_refined_background_pressure.R, then
# extended in August 2026 to key on the fish farm rather than on aquaculture of
# any kind, and to carry farm size and the provider's stated purpose.

analysis_refined_background_pressure <- function(db_dir = multised_db_dir(),
                                                 out_dir = multised_analysis_dir(),
                                                 verbose = TRUE) {
  # ── Analysis stage, pressure-based background (REFINED database) ──────────────
  # The third background page, and the aquaculture-relevant one. Instead of a spatial
  # proxy (offshore), it uses a direct PRESSURE gradient: distance to the nearest fish
  # farm. Sites far from any farm are the low-pressure background; sites near the cages
  # show the enrichment. Norway only (the aquaculture reference is Norwegian), which is
  # where the aquaculture question is asked.
  #
  # THE AXIS IS THE FISH FARM, NOT AQUACULTURE. `dist_to_fish_farm` is the distance to
  # the nearest FINFISH farm; `dist_to_aquaculture` is the distance to the nearest
  # aquaculture site of any kind, and a mussel raft is aquaculture. The pressure this
  # work is about is feed and the copper in net antifouling, so a shellfish or kelp site
  # in the near band is a sample with none of the pressure sitting in the band that is
  # supposed to isolate it. That dilutes toward the null, so it made the old ratios
  # conservative rather than inflated, but it is still the wrong axis. Both are computed
  # here and reported side by side, so the change is auditable rather than silent.
  #
  # SIZE. A 780 t farm and a 19,000 t farm at the same distance are not the same
  # pressure, and the licensed MTB is on `site` already. Splitting the near band by size
  # band is a better test than near-against-far, because it holds the fjord setting
  # roughly constant: if the gradient is real, large farms should show it more strongly
  # than small ones at the same distance. It does not hold it constant enough, and
  # section 5b is the control for that. Short version: depth was the confounder we
  # named and it turned out not to be the one that mattered, location was, and once
  # farms are compared inside one municipality the size response is flat.
  #
  # STATED PURPOSE. Vannmiljo files why the sample was taken (`dataset.pressure_class`:
  # aquaculture / pressure / reference / survey / unknown). That is stated evidence,
  # independent of the geometry, so it cross-checks the distance proxy: rows the provider
  # filed as aquaculture monitoring should sit near a farm. Vannmiljo only, so it covers
  # part of the Norwegian rows and nothing else.
  #
  # AND IT IS LOAD-BEARING, not decoration. The far band is only a background if what is
  # in it is unpressured, and it is not: over half the >20 km copper is Vannmiljo
  # `pressure`, the contaminated-seabed / industry / sewage programmes, which is urban
  # fjord sediment carrying the very metals being measured. Reading the raw far band as
  # the background therefore sets the bar at the harbour rather than at the seabed, and
  # every near/far ratio taken against it understates the farm signal. So the enrichment
  # is reported twice: against the raw far band, and against the far band with the
  # stated-pressure rows removed. The second is the one to read.
  #
  # Per element x fraction, the value_std distribution (median, P90) is taken in
  # distance bins (<1, 1-5, 5-20, >20 km). The >20 km bin is read as the background; the
  # near/far P90 ratio is the enrichment. Raw value (mg/kg); a grain-size caveat applies
  # (near-cage sediment is often muddier / more organic), so the Al-normalised background
  # (page 2) is the cross-check. Outliers dropped; fractions bulk/sieved63/sieved20.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_pressure_percentiles.csv  element x fraction x dist_bin: n, P50, P90
  #   refined_pressure_compare.csv      P90 per bin (wide) + near/far enrichment, raw
  #                                     and against the stated-pressure-free far band
  #   refined_pressure_axis.csv         fish-farm axis against the aquaculture axis
  #   refined_pressure_axis_dropped.csv what the aquaculture axis had in the near band
  #   refined_pressure_size.csv         near band split by farm size band
  #   refined_pressure_size_covariates.csv  how the size bands differ besides size
  #   refined_pressure_size_depth.csv   the size split up a ladder of controls
  #   refined_pressure_size_depth_cost.csv  what each rung of that ladder costs
  #   refined_pressure_size_strata.csv  the size split inside coarse depth strata
  #   refined_pressure_size_paired.csv  size contrasts within one municipality
  #   refined_pressure_size_geography.csv   which coast each size band sits on
  #   refined_pressure_stated.csv       stated purpose against the distance bands
  #   refined_pressure_meta.csv         one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  BG_BIN    <- ">20km"     # the background (far) bin
  NEAR_BIN  <- "<1km"      # the near band the size split is taken in
  BANDS     <- c("small", "medium", "large")
  STATED_PRESSURE <- "pressure"   # the Vannmiljo class the far band is cleaned of
  MIN_N     <- 30L

  # Controls for the size comparison (section 5b). The depth window is the common
  # band all three size bands are cut to; the strata are the same axis read coarsely,
  # so a window that happens to flatter one band can be checked against it. The fines
  # window is deliberately wide because grain size is recorded on under a tenth of
  # near-cage rows and a tighter cut leaves nothing to compare.
  DEPTH_WINDOW  <- c(50, 150)
  DEPTH_BREAKS  <- c(-Inf, 50, 100, 150, 250, Inf)
  DEPTH_LABELS  <- c("<50m", "50-100m", "100-150m", "150-250m", ">250m")
  FINES_WINDOW  <- c(20, 80)
  # Farm pairs, higher capacity first, so a ratio above 1 means the bigger farm
  # carries more.
  CONTRASTS     <- list(c("large", "small"), c("large", "medium"),
                        c("medium", "small"))
  PAIR_MIN_CELL <- 10L   # rows a municipality x band cell needs to enter a pair
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  p90 <- function(x) quantile(x, .9, names = FALSE)

  # ── 1. Pull chemistry, both distances, farm size and stated purpose ──────────
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std,
           si.site_id, si.depth, si.dist_to_coast,
           si.dist_to_fish_farm, si.dist_to_aquaculture,
           si.fish_farm_band, si.fish_farm_mtb_t,
           si.municipality, si.sea_name,
           s.fines_lt63, d.pressure_class
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL
      AND si.dist_to_fish_farm IS NOT NULL
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    mutate(dist_bin = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS),
           aq_bin   = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS),
           stated_pressure = !is.na(pressure_class) &
                             pressure_class == STATED_PRESSURE)

  # ── 2. Distribution per distance bin (the fish-farm axis) ────────────────────
  bin_stats <- function(df, bin) {
    df |>
      group_by(across(all_of(c("symbol", "cat", bin)))) |>
      summarise(n = n(), p50 = signif(median(value_std), 4),
                p90 = signif(p90(value_std), 4), .groups = "drop") |>
      mutate(symbol = factor(symbol, levels = elem_levels),
             cat = factor(cat, levels = CATS),
             reliable = n >= MIN_N) |>
      arrange(symbol, cat, .data[[bin]])
  }

  percentiles <- bin_stats(m, "dist_bin")

  # ── 3. Compare: P90 per bin wide + near/far enrichment ───────────────────────
  wide_p90 <- function(df, bin_col) {
    df |>
      mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
      select(symbol, cat, all_of(bin_col), p90) |>
      pivot_wider(names_from = all_of(bin_col), values_from = p90)
  }
  wide_n <- function(df, bin_col) {
    df |>
      mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
      select(symbol, cat, all_of(bin_col), n) |>
      pivot_wider(names_from = all_of(bin_col), values_from = n, names_prefix = "n_")
  }

  # The far band with the stated-pressure rows removed: the same >20 km pool minus
  # the Vannmiljo contaminated-seabed / industry / sewage programmes. Unlabelled rows
  # (the four non-Vannmiljo sources, which record no programme) are kept, so this
  # removes stated pressure only, never inferred pressure.
  far_clean <- m |>
    filter(dist_bin == BG_BIN, !stated_pressure) |>
    group_by(symbol, cat) |>
    summarise(p90_far_clean = signif(p90(value_std), 4),
              p50_far_clean = signif(median(value_std), 4),
              n_far_clean = n(), .groups = "drop")

  compare <- wide_p90(percentiles, "dist_bin") |>
    left_join(wide_n(percentiles, "dist_bin"), by = c("symbol", "cat")) |>
    left_join(far_clean, by = c("symbol", "cat")) |>
    mutate(enrich_near = round(.data[[NEAR_BIN]] / .data[[BG_BIN]], 3),
           enrich_near_clean = round(.data[[NEAR_BIN]] / p90_far_clean, 3),
           pct_far_stated = round(100 * (1 - n_far_clean / .data[[paste0("n_", BG_BIN)]]), 1),
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat)

  # ── 4. The axis change, made auditable ───────────────────────────────────────
  # The same near/far enrichment computed on each axis, plus how many measurements
  # each axis puts in the near band. `n_near_gain` is what the aquaculture axis adds
  # to the near band that is not within the same distance of any fish farm.
  aq_percentiles <- bin_stats(m, "aq_bin")
  aq_compare <- wide_p90(aq_percentiles, "aq_bin") |>
    left_join(wide_n(aq_percentiles, "aq_bin"), by = c("symbol", "cat")) |>
    transmute(symbol, cat,
              p90_near_aqua = .data[[NEAR_BIN]], p90_far_aqua = .data[[BG_BIN]],
              n_near_aqua = .data[[paste0("n_", NEAR_BIN)]],
              enrich_near_aqua = round(.data[[NEAR_BIN]] / .data[[BG_BIN]], 3))

  axis <- compare |>
    mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
    transmute(symbol, cat,
              p90_near_farm = .data[[NEAR_BIN]], p90_far_farm = .data[[BG_BIN]],
              n_near_farm = .data[[paste0("n_", NEAR_BIN)]],
              enrich_near_farm = enrich_near) |>
    left_join(aq_compare, by = c("symbol", "cat")) |>
    mutate(n_near_gain = n_near_aqua - n_near_farm,
           enrich_shift = round(enrich_near_farm - enrich_near_aqua, 3),
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat)

  # What the aquaculture axis put in the near band that the fish-farm axis does not.
  # The aquaculture reference is in the refined DB, so the dropped rows can be named
  # rather than merely counted: this is the evidence for the axis change.
  dropped <- as_tibble(dbGetQuery(con, sprintf("
    SELECT a.placement, a.capacity_unit,
           CASE WHEN a.fish_farm = 1 THEN 'finfish, at sea'
                ELSE 'other' END AS kind,
           COUNT(*) AS n
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN aquaculture a ON a.aqua_id    = si.aqua_id
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL
      AND si.dist_to_aquaculture < %f AND si.dist_to_fish_farm >= %f
    GROUP BY 1, 2, 3
  ", AQ_BREAKS[2], AQ_BREAKS[2]))) |>
    mutate(placement = if_else(is.na(placement) | placement == "",
                               "(not recorded)", placement)) |>
    group_by(placement, capacity_unit) |>
    summarise(n = sum(n), .groups = "drop") |>
    mutate(pct = round(100 * n / sum(n), 1)) |>
    arrange(desc(n))

  # ── 5. Near band by farm size ────────────────────────────────────────────────
  # Within <1 km of a farm, split by the size band of that farm, against the same
  # far background. Size is licensed MTB in standard 780 t concessions, so it is a
  # capacity ceiling rather than the stock that was in the water when the sediment
  # was sampled.
  far_p90 <- percentiles |>
    filter(dist_bin == BG_BIN) |>
    transmute(symbol = as.character(symbol), cat = as.character(cat),
              p90_far = p90, n_far = n) |>
    left_join(far_clean |>
                mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
                select(symbol, cat, p90_far_clean, n_far_clean),
              by = c("symbol", "cat"))

  size <- m |>
    filter(dist_bin == NEAR_BIN, fish_farm_band %in% BANDS) |>
    group_by(symbol, cat, band = fish_farm_band) |>
    summarise(n = n(),
              mtb_median = signif(median(fish_farm_mtb_t, na.rm = TRUE), 4),
              p50 = signif(median(value_std), 4),
              p90 = signif(p90(value_std), 4), .groups = "drop") |>
    mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
    left_join(far_p90, by = c("symbol", "cat")) |>
    mutate(enrich = round(p90 / p90_far, 3),
           enrich_clean = round(p90 / p90_far_clean, 3),
           reliable = n >= MIN_N,
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS),
           band = factor(band, levels = BANDS)) |>
    arrange(symbol, cat, band)

  # The siting confounder, measured rather than asserted. Large farms are licensed
  # into deeper, more exposed water, which disperses more, so a flat or inverted size
  # response is not by itself evidence that the pressure is absent. This table is what
  # the size table has to be read against.
  size_covariates <- m |>
    filter(dist_bin == NEAR_BIN, fish_farm_band %in% BANDS) |>
    distinct(site_id, band = fish_farm_band, depth, dist_to_coast, fines_lt63,
             fish_farm_mtb_t) |>
    group_by(band) |>
    summarise(n_sites = n(),
              mtb_median = signif(median(fish_farm_mtb_t, na.rm = TRUE), 4),
              median_depth_m = signif(median(depth, na.rm = TRUE), 3),
              median_dist_coast_km = signif(median(dist_to_coast, na.rm = TRUE), 3),
              median_fines_pct = signif(median(fines_lt63, na.rm = TRUE), 3),
              pct_with_fines = round(100 * mean(!is.na(fines_lt63))),
              .groups = "drop") |>
    mutate(band = factor(band, levels = BANDS)) |>
    arrange(band)

  # ── 5b. Separating farm size from where the farm was sited ───────────────────
  # The size table above is confounded and says so: large farms are licensed into
  # deeper water, so a size response could be a depth response wearing its clothes.
  # This section is the test that was owed, and it is built as a ladder of controls
  # rather than a single matched number, because each rung removes something
  # different and the answer changes twice on the way up.
  #
  #   raw            the near band as the size table reports it
  #   clean          stated-pressure rows removed. Not cosmetic: the small-farm near
  #                  band is 13.8% Vannmiljo `pressure` against 1.3% for large, so
  #                  the raw comparison charges small farms for contaminated-seabed
  #                  monitoring that happens to sit near a small farm.
  #   depth          all three bands cut to one depth window, with the achieved
  #                  median depth reported per band so the match is checked, not
  #                  trusted
  #   depth+texture  a fines window on top. Small n by construction: grain size is
  #                  recorded on under a tenth of near-cage rows.
  #
  # DEPTH DOES NOT EXPLAIN IT, AND THAT IS THE POINT OF THE STRATA TABLE. Matching
  # depth leaves the inversion intact (copper P90 large 50.7, medium 96.4, small
  # 65.1 in 50-150 m), and it is present in every one of the five depth strata, so
  # it is not a window artefact either. The named confounder was not the confounder.
  #
  # LOCATION IS. Large farms are 83.7% Norwegian Sea and 5.4% Barents; small farms
  # are 27.8% North Sea and have no Barents rows at all. The size bands are reading
  # out different coastlines. `size_paired` therefore compares farms of different
  # size WITHIN one municipality and takes the ratio there, which holds the regional
  # background fixed by construction, and the response goes flat: every contrast
  # lands near 1, the sign flips between configurations, and about half the paired
  # municipalities fall each way. That is a null, and it is reported as one.
  #
  # So licensed MTB is not a usable proxy for seabed load at the licence point. That
  # is a statement about the proxy, not about fish farming: the near/far enrichment
  # on the page above is unaffected, and capacity is a ceiling on stock rather than
  # the stock that was in the water when the sediment was sampled.
  near_all <- m |>
    filter(dist_bin == NEAR_BIN, fish_farm_band %in% BANDS) |>
    mutate(band = factor(fish_farm_band, levels = BANDS))
  near_clean <- near_all |> filter(!stated_pressure)

  in_depth <- function(df) {
    filter(df, !is.na(depth),
           depth >= DEPTH_WINDOW[1], depth <= DEPTH_WINDOW[2])
  }
  in_fines <- function(df) {
    filter(df, !is.na(fines_lt63),
           fines_lt63 >= FINES_WINDOW[1], fines_lt63 <= FINES_WINDOW[2])
  }

  tier_stats <- function(df, tier) {
    df |>
      group_by(symbol, cat, band) |>
      summarise(n = n(), n_sites = n_distinct(site_id),
                depth_p50 = signif(median(depth, na.rm = TRUE), 3),
                fines_p50 = signif(median(fines_lt63, na.rm = TRUE), 3),
                pct_with_fines = round(100 * mean(!is.na(fines_lt63)), 1),
                mtb_median = signif(median(fish_farm_mtb_t, na.rm = TRUE), 4),
                p50 = signif(median(value_std), 4),
                p90 = signif(p90(value_std), 4), .groups = "drop") |>
      mutate(tier = tier, .before = 1)
  }

  size_depth <- bind_rows(
    tier_stats(near_all,                            "raw"),
    tier_stats(near_clean,                          "clean"),
    tier_stats(in_depth(near_clean),                "depth"),
    tier_stats(in_fines(in_depth(near_clean)),      "depth+texture")
  ) |>
    mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
    left_join(far_p90, by = c("symbol", "cat")) |>
    mutate(enrich_clean = round(p90 / p90_far_clean, 3),
           reliable = n >= MIN_N,
           tier = factor(tier, levels = c("raw", "clean", "depth",
                                          "depth+texture")),
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(tier, symbol, cat, band)

  # What each rung costs, so the shrinking n is visible rather than inferred from
  # the tier table.
  size_depth_cost <- near_all |>
    group_by(band) |>
    summarise(n_raw = n(),
              n_clean = sum(!stated_pressure),
              n_depth = sum(!stated_pressure & !is.na(depth) &
                            depth >= DEPTH_WINDOW[1] & depth <= DEPTH_WINDOW[2]),
              n_texture = sum(!stated_pressure & !is.na(depth) &
                              depth >= DEPTH_WINDOW[1] & depth <= DEPTH_WINDOW[2] &
                              !is.na(fines_lt63) &
                              fines_lt63 >= FINES_WINDOW[1] &
                              fines_lt63 <= FINES_WINDOW[2]),
              pct_stated = round(100 * mean(stated_pressure), 1),
              depth_p50_raw = signif(median(depth, na.rm = TRUE), 3),
              .groups = "drop") |>
    mutate(pct_kept_depth = round(100 * n_depth / n_raw, 1),
           pct_kept_texture = round(100 * n_texture / n_raw, 1))

  # The same contrast read inside coarse depth strata. This is the check that the
  # single window is not doing the work: if the ordering survives at every depth,
  # no choice of window created it.
  size_strata <- near_clean |>
    filter(!is.na(depth)) |>
    mutate(depth_band = cut(depth, DEPTH_BREAKS, labels = DEPTH_LABELS)) |>
    group_by(symbol, cat, depth_band, band) |>
    summarise(n = n(), n_sites = n_distinct(site_id),
              p50 = signif(median(value_std), 4),
              p90 = signif(p90(value_std), 4), .groups = "drop") |>
    mutate(reliable = n >= MIN_N,
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat, depth_band, band)

  # Within-municipality pairing: the control that actually bites. One median per
  # municipality x size band, then the ratio between two bands in the SAME
  # municipality, then the median of those ratios. `n_above_1` is the sign test that
  # goes with it: near half of the pairs is a null however the ratio reads.
  paired_ratios <- function(df, config, min_cell) {
    cell <- df |>
      filter(!is.na(municipality), municipality != "") |>
      group_by(symbol, cat, municipality, band) |>
      summarise(n = n(), v = median(value_std), .groups = "drop") |>
      filter(n >= min_cell)
    purrr::map(CONTRASTS, function(p) {
      hi <- cell |> filter(band == p[1]) |>
        select(symbol, cat, municipality, v_hi = v)
      lo <- cell |> filter(band == p[2]) |>
        select(symbol, cat, municipality, v_lo = v)
      inner_join(hi, lo, by = c("symbol", "cat", "municipality")) |>
        group_by(symbol, cat) |>
        summarise(n_muni = n(),
                  ratio_p25 = round(quantile(v_hi / v_lo, .25, names = FALSE), 3),
                  ratio_p50 = round(median(v_hi / v_lo), 3),
                  ratio_p75 = round(quantile(v_hi / v_lo, .75, names = FALSE), 3),
                  n_above_1 = sum(v_hi > v_lo), .groups = "drop") |>
        mutate(contrast = paste(p, collapse = "/"), .before = 1)
    }) |>
      bind_rows() |>
      mutate(config = config, min_cell = min_cell, .before = 1)
  }

  size_paired <- bind_rows(
    paired_ratios(in_depth(near_clean),
                  sprintf("%d-%dm", DEPTH_WINDOW[1], DEPTH_WINDOW[2]),
                  PAIR_MIN_CELL),
    paired_ratios(near_clean, "any depth", PAIR_MIN_CELL),
    paired_ratios(near_clean |> filter(!is.na(depth), depth >= 30, depth <= 200),
                  "30-200m", PAIR_MIN_CELL)
  ) |>
    filter(n_muni >= 5) |>
    mutate(pct_above_1 = round(100 * n_above_1 / n_muni, 1),
           symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(config, symbol, cat, contrast)

  # Where the size bands sit on the coast, which is what the pairing controls for.
  size_geography <- near_clean |>
    filter(!is.na(sea_name), sea_name != "") |>
    distinct(site_id, band, sea_name) |>
    count(band, sea_name) |>
    group_by(band) |>
    mutate(pct_of_band = round(100 * n / sum(n), 1)) |>
    ungroup() |>
    arrange(band, desc(n))

  # ── 6. Stated purpose against the distance bands ─────────────────────────────
  # Vannmiljo only; the other four sources record no programme, so their rows are
  # dropped here rather than pooled into a residual class they did not state.
  stated <- m |>
    filter(!is.na(pressure_class), pressure_class != "") |>
    group_by(pressure_class, dist_bin) |>
    summarise(n = n(), n_target = sum(symbol %in% elem_levels),
              .groups = "drop") |>
    group_by(pressure_class) |>
    mutate(pct_of_class = round(100 * n / sum(n), 1)) |>
    ungroup() |>
    arrange(pressure_class, dist_bin)

  meta <- tibble(bins = paste(AQ_LABELS, collapse = ","), bg_bin = BG_BIN,
                 near_bin = NEAR_BIN, min_n = MIN_N,
                 axis = "dist_to_fish_farm",
                 far_clean_excludes = STATED_PRESSURE,
                 axis_prev = "dist_to_aquaculture",
                 size_bands = paste(BANDS, collapse = ","),
                 mtb_concession_t = 780,
                 size_depth_window_m = paste(DEPTH_WINDOW, collapse = "-"),
                 size_fines_window_pct = paste(FINES_WINDOW, collapse = "-"),
                 size_pair_unit = "municipality",
                 size_pair_min_cell = PAIR_MIN_CELL,
                 scope = "Norway (nearest finfish farm)")

  # ── 7. Write ─────────────────────────────────────────────────────────────────
  write_csv(percentiles, file.path(out_dir, "refined_pressure_percentiles.csv"))
  write_csv(compare,     file.path(out_dir, "refined_pressure_compare.csv"))
  write_csv(axis,        file.path(out_dir, "refined_pressure_axis.csv"))
  write_csv(dropped,     file.path(out_dir, "refined_pressure_axis_dropped.csv"))
  write_csv(size,        file.path(out_dir, "refined_pressure_size.csv"))
  write_csv(size_covariates,
            file.path(out_dir, "refined_pressure_size_covariates.csv"))
  write_csv(size_depth,  file.path(out_dir, "refined_pressure_size_depth.csv"))
  write_csv(size_depth_cost,
            file.path(out_dir, "refined_pressure_size_depth_cost.csv"))
  write_csv(size_strata, file.path(out_dir, "refined_pressure_size_strata.csv"))
  write_csv(size_paired, file.path(out_dir, "refined_pressure_size_paired.csv"))
  write_csv(size_geography,
            file.path(out_dir, "refined_pressure_size_geography.csv"))
  write_csv(stated,      file.path(out_dir, "refined_pressure_stated.csv"))
  write_csv(meta,        file.path(out_dir, "refined_pressure_meta.csv"))

  if (verbose) {
    # ── 8. Console summary ───────────────────────────────────────────────────────
    cat("pressure-based background written to", out_dir, "\n\n")
    cat("bulk P90 (mg/kg) by distance-to-fish-farm bin, near/far enrichment:\n")
    compare |> filter(cat == "bulk") |>
      select(symbol, `<1km`, `1-5km`, `5-20km`, `>20km`,
             p90_far_clean, pct_far_stated, enrich_near, enrich_near_clean) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\naxis change, bulk (farm vs any aquaculture):\n")
    axis |> filter(cat == "bulk") |>
      select(symbol, n_near_farm, n_near_gain,
             enrich_near_farm, enrich_near_aqua, enrich_shift) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nnear band (<1km) by farm size, bulk:\n")
    size |> filter(cat == "bulk", reliable) |>
      select(symbol, band, n, mtb_median, p90, p90_far_clean, enrich_clean) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nwhat the aquaculture axis had in the near band and the farm axis drops:\n")
    dropped |> head(6) |> as.data.frame() |> print(row.names = FALSE)
    cat("\nwhat else differs between the size bands:\n")
    size_covariates |> as.data.frame() |> print(row.names = FALSE)
    cat("\nsize response up the ladder of controls, bulk copper and zinc:\n")
    size_depth |> filter(cat == "bulk", symbol %in% c("CU", "ZN"), reliable) |>
      select(tier, symbol, band, n, depth_p50, fines_p50, p50, p90,
             enrich_clean) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nsame contrast within one municipality (a null: see pct_above_1):\n")
    size_paired |> filter(cat == "bulk", symbol %in% c("CU", "ZN")) |>
      select(config, symbol, contrast, n_muni, ratio_p50, pct_above_1) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nwhich coast each size band sits on:\n")
    size_geography |> filter(pct_of_band >= 5) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nstated purpose against the distance bands (Vannmiljo only):\n")
    stated |> filter(pressure_class %in% c("aquaculture", "reference")) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
