# ── Analysis, refined generation: geo-accumulation index ─────────────────────

analysis_refined_background_igeo <- function(db_dir = multised_db_dir(),
                                             out_dir = multised_analysis_dir(),
                                             verbose = TRUE) {
  # ── Analysis stage, geo-accumulation index (REFINED database) ────────────────
  # Igeo answers the same question as the enrichment factor, "is this sample above
  # background", with one difference that decides where it can be used:
  #
  #     Igeo = log2( C / (IGEO_K * B) )
  #
  # It needs a BACKGROUND, not a NORMALISER. EF divides by aluminium; Igeo divides by
  # the background concentration of the same element. So Igeo can classify every row
  # that has a value, while EF can only classify rows that also carry aluminium on the
  # right measurement basis.
  #
  # That gap is the reason this step exists. EFSA asked for aquaculture monitoring data
  # by name, and it is the one request the pipeline answers with silence: Vannmiljo's
  # MOMC programme carries aluminium on 5 of 13,996 subsamples, so no sample near a fish
  # farm gets an EF. EFSA also names the way out, in the same paragraph that sets the EF
  # preference: "The Geo-accumulation Index (Igeo) and the Pollution Load Index (PLI)
  # can be considered as well in absence of EF."
  #
  # Section 6 reports what that buys, per fraction and per distance-to-fish-farm band,
  # against what EF manages on the same rows.
  #
  # THIS STEP DOES NOT ISSUE A VERDICT, and that is a decision rather than an omission
  # (2026-08-25). The pristine verdicts stay on EF and Igeo is reported alongside them.
  # Igeo's reach is the argument for promoting it; the texture confounding measured in
  # section 7 is the argument against, and in bulk it is strong enough (cobalt rho 0.70
  # against the mud fraction) that a verdict built on Igeo would be partly a verdict
  # about grain size. Reporting the index without promoting it keeps the coverage
  # visible to EFSA, who asked for Igeo in EF's absence, without changing what
  # "pristine" means here. Step 10 therefore sits AFTER the synthesis on purpose.
  #
  # THE BACKGROUND. B is the offshore (dist_to_coast > DIST_BG km) MEDIAN of the raw
  # concentration, per element and fraction: the same population the EF reference is cut
  # from, so the two indices disagree about method rather than about which samples count
  # as background. It is LOCAL and data-driven, which is EFSA's steer, and it is NOT
  # Turekian & Wedepohl: their deep-sea clay values run 9-24x above this background for
  # the clay-borne metals and four orders of magnitude below it for iodine, so adopting
  # them would decide the answer before the data spoke (docs/generation-gaps.md).
  #
  # WHY THE MEDIAN AND NOT THE P90. The 1.5 in the denominator is Muller's allowance for
  # lithological variability about a CENTRAL value; it is doing the job a higher
  # percentile would do. Using the P90 as B as well would apply the tolerance twice and
  # make almost everything read as unpolluted. The P90 is still reported in the reference
  # file, so the spread between the two is visible.
  #
  # WHY THE CLASSES ARE NOT MULLER'S. Muller's scale is calibrated against average shale.
  # B here is a local offshore median, which for these metals sits well below shale, so a
  # given Igeo means "this far above the local offshore background", not "this far above
  # the crust". The class boundaries are kept because they are the convention EFSA will
  # recognise; the meaning attached to them is not.
  #
  # WHAT IGEO DOES NOT CONTROL. Igeo divides by a background, not by a grain-size
  # carrier, so nothing in it separates "muddy" from "polluted". Section 7 measures that
  # directly, and the answer is not the simple one. In bulk, Igeo tracks the mud fraction
  # for every metal, worst for cobalt (rho 0.70). In the sieved fractions it barely does,
  # which is the D4 finding from the other side: a sieved sample is already grain-size
  # controlled, so there is little texture left for the index to pick up.
  #
  # EF is NOT uniformly the better instrument here. On the same rows it beats Igeo for
  # cobalt (0.24 against 0.70) and LOSES for copper (0.55 against 0.36), tying for zinc.
  # Dividing by aluminium demonstrably removes the texture signal for cobalt and
  # demonstrably does not for copper. So the case for Igeo is strongest exactly where EF
  # cannot run at all, the sieved fractions and the near-farm data, and a bulk Igeo
  # should be read with the texture caveat attached. The comparison is between different
  # row populations, since EF only exists where aluminium does, and is reported as a
  # scale rather than a like-for-like test.
  #
  # THE ALTERNATIVE THAT DOES NOT WORK. If the problem is a missing normaliser, the
  # obvious question is whether another one is present. Organic carbon is: 33.1% of bulk
  # target rows carry TOC and no aluminium, 28,397 measurements, and metals do sorb to
  # organic matter. Section 9 puts TOC through the same D4 test aluminium had to pass.
  #
  # It clears both limits in exactly ONE group of twenty, and that group cannot be used:
  # selenium sieved63, on 34 offshore rows, for an element whose verdicts are already
  # withheld because below-LOQ censoring deleted 68.6% of it. A strong fit to the top
  # third of a truncated distribution is not evidence about background.
  #
  # Everywhere it could matter it fails, and it fails in the way that is hardest to
  # argue with: the two measures disagree. Copper is the best case in bulk, rho 0.60
  # against R2 0.21, and copper sieved63 inverts it, R2 0.37 against rho 0.32. For
  # aluminium the two measures agreed on every group, which is what made D4 a clean
  # partition; for TOC they pull apart, so there is no cut that makes it a normaliser.
  # The 28,397 rows stay unnormalised, and Igeo remains the only route to a verdict for
  # them.
  #
  # WHAT IGEO DOES NOT FIX. Selenium and molybdenum stay withheld. Their exclusion is not
  # about normalisers: the clean stage removes below-LOQ rows, which deletes 68.6% of Se
  # and 52.2% of Mo, so what survives is an upper tail wearing the name "background"
  # (inst/extdata/loq-censoring/). A different index over the same truncated distribution
  # inherits the same problem, so the withholding is orthogonal to this step and survives
  # it. D4 normalisability, by contrast, does NOT apply: it asks whether aluminium
  # predicts the metal, and nothing here divides by aluminium.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_igeo_background.csv  per element x fraction: B (median + P90), n, reliability
  #   refined_igeo_dist.csv        Igeo distribution and class shares
  #   refined_igeo_pressure.csv    median Igeo by distance-to-fish-farm band, raw and
  #                                cleaned of stated pressure side by side
  #   refined_igeo_pressure_matched.csv  the same bands, cleaned AND texture-matched
  #   refined_igeo_band_cost.csv   what the two controls cost each band, in rows
  #   refined_igeo_paired.csv      bands paired inside one municipality
  #   refined_igeo_pair_reach.csv  how many municipalities each band could pair from
  #   refined_igeo_within_site.csv the same site before and during its farm, + placebos
  #   refined_igeo_within_reach.csv how far the before/after design reaches
  #   refined_igeo_coverage.csv    rows Igeo can classify against rows EF can, the point
  #   refined_igeo_confound.csv    Igeo against grain size, and EF against it for scale
  #   refined_igeo_toc_normaliser.csv  the D4 test with organic carbon as the normaliser
  #   refined_igeo_meta.csv        one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  DIST_BG   <- 10          # km: offshore subset defining the background median
  # the scale itself lives in R/analysis-refined-shared-igeo.R, because the flat
  # export republishes the same index and must not carry a second copy of the breaks
  IGEO_K    <- refined_igeo_k()
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  STATED_PRESSURE <- "pressure"   # the Vannmiljo class every band is cleaned of
  # % mud windows the bands are matched in. The first is the working window, wide
  # enough to leave a usable near-cage n; the second is a tighter sensitivity check, and
  # both are published so the match is not a single arbitrary cut.
  FINES_WINDOWS   <- list(c(50, 100), c(60, 90))
  FINES_WINDOW    <- FINES_WINDOWS[[1]]
  # Section 4c. Bands are paired inside one municipality, so the regional background
  # cancels. PAIR_MIN_CELL is rows a municipality x band cell needs to count; the
  # tolerance is how much sandier the near side may be before a pair is called
  # texture-balanced, in percentage points of mud.
  PAIR_MIN_CELL   <- 10L
  PAIR_FINES_TOL  <- -10
  # Section 4d. The same SITE before and during its farm. Zones are the distance
  # rings the design is run in; only the first is treated, the rest are placebos.
  # GAP_WINDOW is the years-between-samples window all zones are cut to, because an
  # unmatched gap compares a 4-year change against a 10-year one.
  WITHIN_ZONES    <- list(c(0, 1), c(1, 5), c(5, 20))
  GAP_WINDOW      <- c(2, 7)
  MIN_SITES       <- 10L
  MIN_N     <- refined_igeo_min_n()
  EF_BASIS  <- refined_ef_basis()
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")


  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull concentrations, with enough to say what EF could have done ───────
  con <- dbConnect(SQLite(), db_path)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.ratio_al,
           s.fines_lt63,
           si.site_id, si.dist_to_coast, si.dist_to_fish_farm, si.municipality,
           e.year, a.start_year, a.end_year, a.active,
           d.source, d.pressure_class,
           n.fe AS norm_fe, n.al AS norm_al, n.corg AS norm_corg
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    -- one normaliser row per subsample PER FRACTION, so match frac_class too
    LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
                          AND n.frac_class   = me.frac_class
    LEFT JOIN aquaculture a ON a.aqua_id = si.fish_farm_aqua_id
    WHERE me.outlier_flag IS NULL AND me.value_std IS NOT NULL AND me.value_std > 0
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    mutate(al_basis = refined_al_basis(norm_fe, norm_al),
           on_basis = refined_on_basis(al_basis, cat),
           # what EF manages on the same row: aluminium present, on the fraction's
           # adopted basis, and a group where aluminium predicts the metal (D4)
           ef_ok = !is.na(ratio_al) & ratio_al > 0 & on_basis &
                   refined_normalisable(symbol, cat),
           withheld = as.character(symbol) %in% refined_withheld_elements(),
           # Vannmiljo files why the sample was taken; "pressure" is contaminated
           # seabed, industry and sewage. Nothing else states a purpose, so a source
           # without a programme code keeps every row.
           stated_pressure = !is.na(pressure_class) &
                             pressure_class == STATED_PRESSURE)
  dbDisconnect(con)

  # ── 2. Local background: offshore median of the raw concentration ────────────
  background <- m |>
    filter(dist_to_coast > DIST_BG) |>
    group_by(symbol, cat) |>
    summarise(n_bg = n(),
              bg_median = median(value_std),
              bg_p90    = quantile(value_std, .9, names = FALSE),
              # B is NOT cleaned, and the two columns beside it are the reason it does
              # not need to be. The offshore pool is 5.0% stated pressure against 39.9%
              # in the > 20 km-from-a-farm band, and moving to the cleaned median shifts
              # B by at most 8% (copper), 0.11 of an Igeo unit. Cleaning B would also
              # cut it from a different population than the EF reference, which is the
              # one thing this step is built not to do.
              n_bg_stated = sum(stated_pressure),
              bg_median_clean = median(value_std[!stated_pressure]),
              # the texture B is cut from, so the near-cage bands can be compared with
              # the population the index divides by rather than assumed to match it
              bg_fines_p50 = round(median(fines_lt63, na.rm = TRUE), 1),
              .groups = "drop") |>
    mutate(reliable = n_bg >= MIN_N,
           pct_bg_stated = round(100 * n_bg_stated / n_bg, 1),
           bg_shift = round(bg_median / bg_median_clean, 3))

  # a group with too thin a reference gets no Igeo at all: the index would carry the
  # noise of its own denominator
  usable <- background |> filter(reliable) |> select(symbol, cat, bg_median)

  # The withheld elements get no Igeo, for the same reason they get no EF and no
  # background verdict: over half of selenium and molybdenum was deleted below the
  # LOQ, so BOTH ends of the ratio are truncated. The offshore median in the
  # denominator is an upper tail wearing the name "background", and the surviving
  # measurements in the numerator are the ones that cleared the limit. The quotient
  # is not an enrichment. Igeo needing no aluminium rescues it from D4, not from D1.
  #
  # The coverage table below has always applied this; `scored` did not, so the class
  # shares published Mo and Se while the 97.2% coverage figure beside them was
  # computed as though they were absent. One rule now.
  scored <- m |>
    filter(!withheld) |>
    inner_join(usable, by = c("symbol", "cat")) |>
    mutate(igeo = refined_igeo(value_std, bg_median),
           igeo_class = refined_igeo_class(igeo),
           dist_bin = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS, right = FALSE))

  # ── 3. Distribution and class shares ─────────────────────────────────────────
  dist_tbl <- scored |>
    group_by(symbol, cat) |>
    summarise(n = n(),
              igeo_p50 = round(median(igeo), 3),
              igeo_p90 = round(quantile(igeo, .9, names = FALSE), 3),
              pct_unpolluted = round(100 * mean(igeo <= 0), 1),
              pct_moderate_up = round(100 * mean(igeo > 1), 1),
              pct_heavy_up    = round(100 * mean(igeo > 3), 1),
              .groups = "drop") |>
    left_join(m |> distinct(symbol, withheld), by = "symbol") |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat)

  class_tbl <- scored |>
    count(symbol, cat, igeo_class, name = "n") |>
    group_by(symbol, cat) |>
    mutate(pct = round(100 * n / sum(n), 1)) |>
    ungroup()

  # ── 4. Against the fish-farm gradient, with both confounders removed ─────────
  # This section was published once WITHOUT the two controls below and reported that
  # distance to a fish farm is a poor axis for Igeo. That was an artefact of the bands,
  # not a property of the index, and the correction is kept visible rather than quietly
  # swapped (2026-08-26).
  #
  # CONFOUNDER 1, STATED PRESSURE. The > 20 km band is 39.9% Vannmiljo stated-pressure
  # monitoring in bulk: contaminated seabed, industry and sewage. Raw, it is a polluted
  # band rather than a remote one, which is why the far band did not read as the cleanest
  # band. The earlier note argued the bands need no cleaning because they describe where
  # the index lands rather than estimate a background. That is true of the ARITHMETIC and
  # false of the CONCLUSION drawn from it: a band that is two fifths urban harbour cannot
  # be read as "far from a farm" whatever it is being used for.
  #
  # CONFOUNDER 2, TEXTURE. Igeo divides by a background cut from offshore mud (median
  # 69.4% fines), while the < 1 km band is 34.8% fines. Half the mud carries roughly half
  # the metal, so near-cage sediment reads negative on grain size alone. Section 7
  # measures this correlation directly; here it is removed by comparing like with like,
  # restricting every band to FINES_WINDOW and reporting the achieved median fines so the
  # match can be checked rather than trusted.
  #
  # Both controls cost rows, and the texture one costs most of them: fines_lt63 is
  # present on 953 of 11,075 clean near-cage copper rows. The matched table is therefore
  # a SMALL, HONEST comparison beside a large confounded one, and both are published.
  band_stats <- function(df) {
    df |>
      group_by(symbol, cat, dist_bin) |>
      summarise(n = n(), igeo_p50 = round(median(igeo), 3),
                pct_unpolluted = round(100 * mean(igeo <= 0), 1), .groups = "drop")
  }

  binned <- scored |> filter(!is.na(dist_bin))

  pressure_tbl <- band_stats(binned) |>
    filter(n >= MIN_N) |>
    left_join(binned |>
                group_by(symbol, cat, dist_bin) |>
                summarise(pct_stated = round(100 * mean(stated_pressure), 1),
                          .groups = "drop"),
              by = c("symbol", "cat", "dist_bin")) |>
    left_join(band_stats(binned |> filter(!stated_pressure)) |>
                filter(n >= MIN_N) |>
                rename(n_clean = n, igeo_p50_clean = igeo_p50,
                       pct_unpolluted_clean = pct_unpolluted),
              by = c("symbol", "cat", "dist_bin")) |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat, dist_bin)

  # ── 4b. The same bands, cleaned AND texture-matched ──────────────────────────
  matched_one <- function(w) {
    binned |>
      filter(!stated_pressure, !is.na(fines_lt63),
             fines_lt63 >= w[1], fines_lt63 <= w[2]) |>
      group_by(symbol, cat, dist_bin) |>
      summarise(n = n(), fines_p50 = round(median(fines_lt63), 1),
                igeo_p50 = round(median(igeo), 3),
                pct_unpolluted = round(100 * mean(igeo <= 0), 1), .groups = "drop") |>
      filter(n >= MIN_N) |>
      mutate(window = sprintf("%d-%d%%", w[1], w[2]), .before = 1)
  }

  matched_tbl <- purrr::map(FINES_WINDOWS, matched_one) |>
    bind_rows() |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(window, symbol, cat, dist_bin)

  # what the two controls cost, so the reader can weigh the matched table's n
  band_cost <- binned |>
    group_by(cat, dist_bin) |>
    summarise(n_raw = n(),
              n_clean = sum(!stated_pressure),
              n_matched = sum(!stated_pressure & !is.na(fines_lt63) &
                              fines_lt63 >= FINES_WINDOW[1] &
                              fines_lt63 <= FINES_WINDOW[2]),
              fines_p50_raw = round(median(fines_lt63, na.rm = TRUE), 1),
              .groups = "drop") |>
    mutate(pct_kept_clean = round(100 * n_clean / n_raw, 1),
           pct_kept_matched = round(100 * n_matched / n_raw, 1))

  # ── 4c. The third control: pairing bands inside one municipality ─────────────
  # Cleaning and texture-matching both work on WHAT is in a band. Neither touches
  # WHERE the bands are, and the farm-size work on the pressure page showed location
  # is the confounder that bites hardest there: size bands that looked like a dose
  # response were reading out different coastlines, and pairing within a municipality
  # flattened the response completely. The same question is owed here.
  #
  # THE CONTROLS DO NOT STACK, and that is the first finding. Requiring both bands in
  # one municipality ON TOP of the mud window leaves a single municipality for copper,
  # because the texture match already costs 97.3% of the near-cage rows. So the
  # headline near-against-far number cannot be location-checked directly, and this
  # section does not pretend otherwise.
  #
  # PAIRED WITHOUT THE TEXTURE MATCH, THE CONTRAST AGAINST >20 km JUST REPLAYS THE
  # TEXTURE CONFOUNDER. Copper comes out at -0.41, positive in under a third of the 22
  # municipalities, which reads like a reversal and is not news: inside those pairs the
  # near side is 57 percentage points sandier (23.3% mud against 80.8%). Pairing on
  # location does nothing about grain size. That row is published so the trap is
  # visible rather than stepped in twice.
  #
  # THE CONTRAST THAT WORKS IS THE ADJACENT ONE. A near-cage site and a site a few
  # kilometres away usually share a municipality, so <1 km against 1-5 km pairs on 79
  # municipalities instead of 22, and the texture gap across it is small (7.6 pp)
  # rather than 57. It is also conservative in two independent ways: 1-5 km is not
  # farm-free, so the contrast understates the gradient, and the near side is still the
  # sandier of the two, which suppresses the metal. `fines_balanced` is the same
  # comparison restricted to pairs where the near side is not the sandier one, and it
  # is the row that shows how much the residual texture is costing.
  pair_cells <- function(df) {
    df |>
      filter(!is.na(municipality), municipality != "") |>
      group_by(symbol, cat, municipality, dist_bin) |>
      summarise(n = n(), igeo_p50 = median(igeo),
                fines_p50 = median(fines_lt63, na.rm = TRUE), .groups = "drop") |>
      filter(n >= PAIR_MIN_CELL)
  }

  # One contrast: near band against a comparison band, in the same municipality.
  # `balanced_only` keeps the pairs whose texture gap is inside PAIR_FINES_TOL, which
  # needs a mud median on both sides and so always costs pairs.
  pair_one <- function(cells, near, far, balanced_only = FALSE) {
    a <- cells |> filter(dist_bin == near) |>
      select(symbol, cat, municipality, igeo_near = igeo_p50, fines_near = fines_p50)
    b <- cells |> filter(dist_bin == far) |>
      select(symbol, cat, municipality, igeo_far = igeo_p50, fines_far = fines_p50)
    pairs <- inner_join(a, b, by = c("symbol", "cat", "municipality"))
    if (balanced_only) {
      pairs <- pairs |>
        filter(!is.na(fines_near), !is.na(fines_far),
               fines_near - fines_far >= PAIR_FINES_TOL)
    }
    pairs |>
      group_by(symbol, cat) |>
      summarise(n_muni = n(),
                diff_p25 = round(quantile(igeo_near - igeo_far, .25, names = FALSE), 3),
                diff_p50 = round(median(igeo_near - igeo_far), 3),
                diff_p75 = round(quantile(igeo_near - igeo_far, .75, names = FALSE), 3),
                n_positive = sum(igeo_near > igeo_far),
                n_fines_both = sum(!is.na(fines_near) & !is.na(fines_far)),
                fines_gap_p50 = round(median(fines_near - fines_far, na.rm = TRUE), 1),
                .groups = "drop") |>
      mutate(contrast = paste(near, "vs", far),
             pairs = if (balanced_only) "texture-balanced" else "all",
             .before = 1)
  }

  pair_grid <- tidyr::expand_grid(
    far = AQ_LABELS[-1],
    balanced_only = c(FALSE, TRUE)
  )
  cells_clean <- pair_cells(binned |> filter(!stated_pressure))
  paired_tbl <- purrr::pmap(pair_grid, function(far, balanced_only) {
    pair_one(cells_clean, AQ_LABELS[1], far, balanced_only)
  }) |>
    bind_rows() |>
    filter(n_muni >= 5) |>
    mutate(pct_positive = round(100 * n_positive / n_muni, 1),
           symbol = factor(symbol, levels = elem_levels),
           contrast = factor(contrast,
                             levels = paste(AQ_LABELS[1], "vs", AQ_LABELS[-1]))) |>
    arrange(pairs, contrast, symbol, cat)

  # How far the pairing reaches, per contrast: a municipality count is only meaningful
  # beside the number of municipalities that could ever have supplied one.
  pair_reach <- cells_clean |>
    group_by(symbol, cat, dist_bin) |>
    summarise(n_muni = n_distinct(municipality), n = sum(n), .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat, dist_bin)

  # ── 4d. The control that needs no matching: the same site, before its farm ───
  # Every control so far matches one population against another and pays for it:
  # texture matching spends 97.3% of the near-cage rows, municipality pairing cannot
  # be stacked on top of it, and the adjacent contrast that survives both is blunted
  # because 1-5 km is not farm-free. All three are approximations of one thing, which
  # is a farm-free reading of the SAME seabed. The refined DB can supply that directly:
  # `fish_farm_aqua_id` carries the farm's licence dates, so a site sampled before its
  # farm opened and again while it operated is its own control.
  #
  # WHAT THIS HOLDS FIXED that nothing else does: location exactly rather than by
  # municipality, water depth, the regional background, the sediment's provenance, and
  # the sampling programme (the pre-farm rows are almost all MOM baseline surveys, taken
  # a median of one year before the farm opens, so the comparison is a designed baseline
  # rather than an accident). It needs no grain-size measurement at all, which is what
  # made the other controls expensive.
  #
  # AND IT NEEDS A PLACEBO, because a before/after is a time series and metals in
  # Norwegian sediment are not stationary. The same contrast is therefore run in two
  # rings further out, split on the SAME farm's start year: whatever secular trend
  # exists shows up there without any farm deposition under the sampler. It is a real
  # trend and it runs downward, so reading the near-cage change on its own understates
  # it.
  #
  # THE GAP WINDOW IS NOT OPTIONAL. Raw, the near-cage pairs sit 4 years apart and the
  # 5-20 km pairs 10, so an unmatched comparison charges the placebo with six extra
  # years of decline. Both are reported: `gap_matched` cut to GAP_WINDOW, and a per-year
  # rate over all pairs, which is the same statement without discarding anything.
  #
  # WHAT IT CANNOT SEPARATE, stated because it changes the reading: a farm enriches the
  # sediment with organic matter, and organically enriched sediment is finer. Part of
  # the rise this design measures may be the seabed becoming muddier rather than the
  # metal load increasing. That is mediation rather than confounding, since the farm
  # caused both, but "the farm raised the metal" here includes "the farm changed the
  # sediment". No site has grain size in both periods, so it cannot be checked.
  farm_period <- m |>
    filter(!withheld) |>
    inner_join(usable, by = c("symbol", "cat")) |>
    mutate(igeo = refined_igeo(value_std, bg_median),
           period = case_when(
             is.na(year) | is.na(start_year) ~ NA_character_,
             year < start_year ~ "pre-farm",
             active == 1L | (!is.na(end_year) & year <= end_year) ~ "operating",
             TRUE ~ "post-closure")) |>
    filter(period %in% c("pre-farm", "operating"), !is.na(site_id))

  # One row per site x period, so a site sampled ten times in one period counts once.
  within_one <- function(zone) {
    site_period <- farm_period |>
      filter(dist_to_fish_farm >= zone[1], dist_to_fish_farm < zone[2]) |>
      group_by(symbol, cat, site_id, period) |>
      summarise(n = n(), igeo_p50 = median(igeo), year_p50 = median(year),
                .groups = "drop")
    pre <- site_period |> filter(period == "pre-farm") |>
      select(symbol, cat, site_id, igeo_pre = igeo_p50, year_pre = year_p50,
             n_pre = n)
    op <- site_period |> filter(period == "operating") |>
      select(symbol, cat, site_id, igeo_op = igeo_p50, year_op = year_p50,
             n_op = n)
    inner_join(pre, op, by = c("symbol", "cat", "site_id")) |>
      mutate(zone = sprintf("%g-%g km", zone[1], zone[2]),
             gap = year_op - year_pre,
             delta = igeo_op - igeo_pre)
  }
  within_pairs <- purrr::map(WITHIN_ZONES, within_one) |> bind_rows()

  summarise_within <- function(df, basis) {
    df |>
      group_by(symbol, cat, zone) |>
      summarise(n_sites = n(),
                gap_p50 = round(median(gap), 1),
                delta_p25 = round(quantile(delta, .25, names = FALSE), 3),
                delta_p50 = round(median(delta), 3),
                delta_p75 = round(quantile(delta, .75, names = FALSE), 3),
                n_rising = sum(delta > 0),
                rate_p50 = round(median(delta / gap), 4),
                .groups = "drop") |>
      mutate(basis = basis, .before = 1)
  }

  within_site <- bind_rows(
    summarise_within(within_pairs |>
                       filter(gap >= GAP_WINDOW[1], gap <= GAP_WINDOW[2]),
                     sprintf("gap %d-%d yr", GAP_WINDOW[1], GAP_WINDOW[2])),
    summarise_within(within_pairs |> filter(gap > 0), "per year, all pairs")
  ) |>
    filter(n_sites >= MIN_SITES) |>
    mutate(pct_rising = round(100 * n_rising / n_sites, 1),
           symbol = factor(symbol, levels = elem_levels),
           zone = factor(zone, levels = vapply(WITHIN_ZONES,
                                               function(z) sprintf("%g-%g km", z[1], z[2]),
                                               character(1)))) |>
    arrange(basis, symbol, cat, zone)

  # How the design reaches: sites that could ever supply a pair, against those that do.
  within_reach <- farm_period |>
    filter(dist_to_fish_farm < WITHIN_ZONES[[1]][2]) |>
    group_by(symbol, cat) |>
    summarise(n_sites_any = n_distinct(site_id),
              n_sites_pre = n_distinct(site_id[period == "pre-farm"]),
              n_rows_pre = sum(period == "pre-farm"),
              n_rows_op = sum(period == "operating"),
              lead_years_p50 = round(median(start_year[period == "pre-farm"] -
                                            year[period == "pre-farm"]), 1),
              .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat)

  # ── 5. The coverage this step exists for ─────────────────────────────────────
  # Every row that has a value gets an Igeo (given a usable reference); only rows with
  # aluminium on the right basis, in a normalisable group, get an EF.
  coverage <- m |>
    left_join(usable |> mutate(has_ref = TRUE), by = c("symbol", "cat")) |>
    mutate(has_ref = !is.na(has_ref),
           igeo_ok = has_ref & !withheld,
           ef_ok   = ef_ok & !withheld,
           dist_bin = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS, right = FALSE))

  cov_frac <- coverage |>
    group_by(cat) |>
    summarise(n = n(), n_ef = sum(ef_ok), n_igeo = sum(igeo_ok),
              pct_ef = round(100 * mean(ef_ok), 1),
              pct_igeo = round(100 * mean(igeo_ok), 1), .groups = "drop") |>
    mutate(axis = "fraction", band = cat, .before = 1) |>
    select(-cat)

  cov_aq <- coverage |>
    filter(!is.na(dist_bin)) |>
    group_by(dist_bin) |>
    summarise(n = n(), n_ef = sum(ef_ok), n_igeo = sum(igeo_ok),
              pct_ef = round(100 * mean(ef_ok), 1),
              pct_igeo = round(100 * mean(igeo_ok), 1), .groups = "drop") |>
    mutate(axis = "distance to fish farm", band = as.character(dist_bin), .before = 1) |>
    select(-dist_bin)

  cov_all <- coverage |>
    summarise(n = n(), n_ef = sum(ef_ok), n_igeo = sum(igeo_ok),
              pct_ef = round(100 * mean(ef_ok), 1),
              pct_igeo = round(100 * mean(igeo_ok), 1)) |>
    mutate(axis = "all", band = "all", .before = 1)

  cov_tbl <- bind_rows(cov_all, cov_frac, cov_aq)

  # ── 7. Is the index measuring texture? ───────────────────────────────────────
  # Spearman against the mud fraction, for Igeo and for metal/Al on the same rows. EF
  # proper divides metal/Al by a per-group constant, which cannot change a rank
  # correlation, so metal/Al stands in for it.
  rho <- function(a, b) {
    ok <- !is.na(a) & !is.na(b)
    if (sum(ok) < MIN_N) return(NA_real_)
    round(stats::cor(a[ok], b[ok], method = "spearman"), 3)
  }

  confound_tbl <- scored |>
    filter(!is.na(fines_lt63)) |>
    group_by(symbol, cat) |>
    filter(dplyr::n() >= MIN_N) |>
    summarise(n              = dplyr::n(),
              rho_igeo_fines = rho(igeo, fines_lt63),
              n_ef           = sum(!is.na(ratio_al) & ratio_al > 0),
              rho_ef_fines   = rho(ifelse(!is.na(ratio_al) & ratio_al > 0,
                                          log2(ratio_al), NA_real_), fines_lt63),
              .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat)

  # ── 9. Would organic carbon serve as the normaliser aluminium is not? ────────
  # The same two measures D4 applies to aluminium: OLS R2 on the offshore reference,
  # and Spearman over every row carrying the normaliser. No aluminium basis restriction
  # applies, because TOC is not the quantity the basis split is about.
  toc_one <- function(df) {
    off <- df |> filter(dist_to_coast > DIST_BG, !is.na(norm_corg), norm_corg > 0)
    all <- df |> filter(!is.na(norm_corg), norm_corg > 0)
    if (nrow(off) < MIN_N || nrow(all) < MIN_N) {
      return(tibble::tibble(n_off = nrow(off), n_all = nrow(all),
                            r2 = NA_real_, rho = NA_real_))
    }
    f <- stats::lm(value_std ~ norm_corg, data = off)
    tibble::tibble(n_off = nrow(off), n_all = nrow(all),
                   r2  = round(summary(f)$r.squared, 4),
                   rho = round(stats::cor(all$value_std, all$norm_corg,
                                          method = "spearman"), 3))
  }

  toc_tbl <- m |>
    group_by(symbol, cat) |>
    group_modify(~ toc_one(.x)) |>
    ungroup() |>
    mutate(normalisable_toc = !is.na(r2) & !is.na(rho) &
             r2 >= refined_r2_limit() & rho >= refined_rho_limit(),
           symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, cat)

  # ── 10. Write ────────────────────────────────────────────────────────────────
  meta <- tibble::tibble(
    formula     = "Igeo = log2(C / (1.5 * B))",
    background  = sprintf("offshore > %d km median of value_std, per element x fraction",
                          DIST_BG),
    k           = IGEO_K,
    min_n       = MIN_N,
    withheld    = paste(refined_withheld_elements(), collapse = ", "),
    d4_applies  = FALSE,
    band_controls = sprintf("bands reported raw, cleaned of pressure_class = '%s', and cleaned + matched on fines_lt63 in %s",
                            STATED_PRESSURE,
                            paste(vapply(FINES_WINDOWS,
                                         function(w) sprintf("%d-%d%%", w[1], w[2]),
                                         character(1)), collapse = " and ")),
    bg_cleaned  = FALSE,
    pair_unit   = "municipality",
    pair_min_cell = PAIR_MIN_CELL,
    pair_fines_tol_pp = PAIR_FINES_TOL,
    within_site_design = sprintf("same site pre-farm vs operating, gap matched to %d-%d yr, placebo zones %s",
                                 GAP_WINDOW[1], GAP_WINDOW[2],
                                 paste(vapply(WITHIN_ZONES[-1],
                                              function(z) sprintf("%g-%g km", z[1], z[2]),
                                              character(1)), collapse = " and ")),
    classes     = "Muller boundaries, local-background meaning; see the script header")

  write_csv(background,   file.path(out_dir, "refined_igeo_background.csv"))
  write_csv(dist_tbl,     file.path(out_dir, "refined_igeo_dist.csv"))
  write_csv(class_tbl,    file.path(out_dir, "refined_igeo_classes.csv"))
  write_csv(pressure_tbl, file.path(out_dir, "refined_igeo_pressure.csv"))
  write_csv(matched_tbl,  file.path(out_dir, "refined_igeo_pressure_matched.csv"))
  write_csv(band_cost,    file.path(out_dir, "refined_igeo_band_cost.csv"))
  write_csv(paired_tbl,   file.path(out_dir, "refined_igeo_paired.csv"))
  write_csv(pair_reach,   file.path(out_dir, "refined_igeo_pair_reach.csv"))
  write_csv(within_site,  file.path(out_dir, "refined_igeo_within_site.csv"))
  write_csv(within_reach, file.path(out_dir, "refined_igeo_within_reach.csv"))
  write_csv(cov_tbl,      file.path(out_dir, "refined_igeo_coverage.csv"))
  write_csv(confound_tbl, file.path(out_dir, "refined_igeo_confound.csv"))
  write_csv(toc_tbl,      file.path(out_dir, "refined_igeo_toc_normaliser.csv"))
  write_csv(meta,         file.path(out_dir, "refined_igeo_meta.csv"))

  if (verbose) {
    cat("\n-- Igeo background reference (offshore >", DIST_BG, "km median) --\n")
    print(as.data.frame(background), row.names = FALSE)
    cat("\n-- Igeo distribution --\n")
    print(as.data.frame(dist_tbl), row.names = FALSE)
    cat("\n-- fish-farm gradient: raw, then cleaned of stated pressure --\n")
    print(as.data.frame(pressure_tbl), row.names = FALSE)
    cat("\n-- the same bands, cleaned AND texture-matched --\n")
    print(as.data.frame(matched_tbl), row.names = FALSE)
    cat("\n-- bands paired inside one municipality (bulk) --\n")
    paired_tbl |> filter(cat == "bulk") |>
      select(pairs, contrast, symbol, n_muni, diff_p50, pct_positive,
             fines_gap_p50) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\n-- the same site, before its farm and during it, with placebos --\n")
    within_site |> filter(cat == "bulk") |>
      select(basis, symbol, zone, n_sites, gap_p50, delta_p50, pct_rising,
             rate_p50) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\n-- coverage: what Igeo classifies against what EF does --\n")
    print(as.data.frame(cov_tbl), row.names = FALSE)
    cat("\n-- is the index measuring texture? Spearman against mud fraction --\n")
    print(as.data.frame(confound_tbl), row.names = FALSE)
    cat("\n-- would organic carbon serve as a normaliser? (D4 limits: r2 >=",
        refined_r2_limit(), " rho >=", refined_rho_limit(), ") --\n")
    print(as.data.frame(toc_tbl), row.names = FALSE)
  }

  # analyze_data() reads the return value as the module's output DIRECTORY and calls
  # list.files() on it, so every analysis function returns out_dir. Returning the
  # results instead fails the whole module with "invalid 'path' argument".
  invisible(out_dir)
}
