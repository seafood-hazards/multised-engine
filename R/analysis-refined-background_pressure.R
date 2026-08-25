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
  # than small ones at the same distance. Confounder, declared rather than controlled:
  # large farms are sited in deeper, higher-flow water, which disperses more, so a flat
  # size response is not by itself evidence of no pressure.
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
                 scope = "Norway (nearest finfish farm)")

  # ── 7. Write ─────────────────────────────────────────────────────────────────
  write_csv(percentiles, file.path(out_dir, "refined_pressure_percentiles.csv"))
  write_csv(compare,     file.path(out_dir, "refined_pressure_compare.csv"))
  write_csv(axis,        file.path(out_dir, "refined_pressure_axis.csv"))
  write_csv(dropped,     file.path(out_dir, "refined_pressure_axis_dropped.csv"))
  write_csv(size,        file.path(out_dir, "refined_pressure_size.csv"))
  write_csv(size_covariates,
            file.path(out_dir, "refined_pressure_size_covariates.csv"))
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
    cat("\nstated purpose against the distance bands (Vannmiljo only):\n")
    stated |> filter(pressure_class %in% c("aquaculture", "reference")) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
