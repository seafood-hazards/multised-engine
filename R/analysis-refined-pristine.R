# ── Analysis, refined generation: background ─────────────────────────────
# Converted from R/analysis/background/06_refined_pristine.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_refined_pristine <- function(db_dir = multised_db_dir(),
                                      out_dir = multised_analysis_dir(),
                                      verbose = TRUE) {
  # ── Analysis stage, pristine classification (REFINED database) ───────────────
  # The synthesis: a per-measurement "pristine" (at/below background) verdict per element
  # x fraction, built ONLY on grain-size-controlled criteria. A raw-concentration flag was
  # rejected: it is confounded by grain size (sandy near-cage sediment slips under a
  # threshold regardless of pressure), and Al coverage is anti-correlated with aquaculture
  # proximity, so a concentration fallback validated backwards. So where aluminium (hence
  # the enrichment factor) is missing, a sample is left UNCLASSIFIED rather than guessed.
  #
  # The grain-size control differs by fraction, and so do the criteria that apply.
  # BULK is controlled statistically, by aluminium, and only where aluminium earns it:
  #   pristine_ef     : EF < 1 (EF = (metal/Al) / offshore-median(metal/Al))   [permissive, EFSA]
  #   pristine_strict : EF<1 AND value_std < mixture threshold AND value_std < offshore P90
  # SIEVED is controlled physically, by the sieve, which is the stronger control of the
  # two (the offshore background moves 1.7-2.5x between seas in sieved63 against
  # 4.4-4.9x in Al-normalised bulk). Aluminium is not the correction there, so no EF:
  #   pristine_ef     : NA (undefined; the EFSA field keeps its EF-only meaning)
  #   pristine_strict : value_std < mixture threshold AND value_std < offshore P90
  # Reference values reused from the earlier pages: EF background (04), mixture threshold
  # (05), offshore P90 (01).
  #
  # The headline is a data-gap: how much of the data (and especially the near-cage data) is
  # even classifiable. Distance to fish farm / coast VALIDATE the flag (not define it).
  # Fractions bulk/sieved63/sieved20; outliers dropped.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_pristine_summary.csv     per element x fraction: % classifiable, % pristine (both rules)
  #   refined_pristine_reference.csv   per fraction: what its offshore reference population IS
  #   refined_pristine_sea_spread.csv  per group: how far the background moves between seas,
  #                                    raw and after / Al (which control actually travels)
  #   refined_pristine_coverage.csv    % classifiable by distance band  (the data gap)
  #   refined_pristine_validation.csv  % pristine by distance band, among classifiable samples
  #   refined_pristine_validation_source.csv  the same, WITHIN each source (the confounding test)
  #   refined_pristine_meta.csv        one-row config

  db_path <- refined_db_path(db_dir)
  adir <- file.path(out_dir, "background")
  CATS  <- c("bulk", "sieved63", "sieved20")
  MIN_N <- 30L
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf);  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  CO_BREAKS <- c(-Inf, 1, 10, 50, Inf); CO_LABELS <- c("<1km", "1-10km", "10-50km", ">50km")
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  rd <- function(f) read_csv(file.path(adir, f), show_col_types = FALSE) |>
    mutate(symbol = as.character(symbol), cat = as.character(cat))
  bg  <- rd("refined_ef_background.csv")      |> select(symbol, cat, bg_ratio_al)
  off <- rd("refined_background_compare.csv") |> select(symbol, cat, p90_off = p90_off10)
  mix <- rd("refined_mixture_components.csv") |> select(symbol, cat, threshold, usable)

  # ── Measurements + criteria + the two grain-size-controlled flags ────────────
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.ratio_al,
           si.dist_to_coast, si.dist_to_fish_farm, si.latitude, si.depth, si.sea_name,
           n.fe AS norm_fe, n.al AS norm_al, d.source AS source
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    -- the normaliser table holds one row per subsample PER FRACTION CLASS, so this
    -- join must match frac_class too. Without it a subsample carrying both a bulk and
    -- a sieved normaliser duplicates its measurements and can attach the wrong
    -- fraction's aluminium, which corrupts the basis test and every ratio built on it.
    LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
                          AND n.frac_class   = me.frac_class
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk", sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20", TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    left_join(bg, by = c("symbol", "cat")) |>
    left_join(off, by = c("symbol", "cat")) |>
    left_join(mix, by = c("symbol", "cat")) |>
    mutate(
      al_basis = refined_al_basis(norm_fe, norm_al),
      on_basis = refined_on_basis(al_basis, cat),
      # a sample off its fraction's adopted aluminium basis, or with no Fe to place it, is
      # left unclassified rather than divided by a reference from a different measurement
      # basis. See R/analysis-refined-shared-basis.R and docs/ef-source-bias.md.
      # a withheld element gets no verdict at all: over half its measurements were deleted
      # below the LOQ, so its "background" is an upper tail. See
      # R/analysis-refined-shared-censoring.R and inst/extdata/loq-censoring/README.md.
      # in BULK a group whose metal aluminium does not predict gets no verdict: metal/Al
      # is not a grain-size control there, whatever form the normalisation takes. See
      # R/analysis-refined-shared-normalisability.R and
      # inst/extdata/normalisability/README.md.
      withheld = symbol %in% refined_withheld_elements(),
      # Which correction controls grain size here, and therefore which gates apply.
      # Bulk earns its control statistically (aluminium has to predict the metal, and
      # the sample has to sit on the fraction's aluminium basis). A sieved sample was
      # cut to size before the chemistry started, so it needs neither gate: aluminium
      # is a spare measurement there, not the correction. Withholding a sieved verdict
      # because aluminium fails would read "no correction needed" as "the correction
      # failed" and penalise the fraction that had the better control all along.
      gs_control = refined_gs_control(cat),
      al_gated   = gs_control == "aluminium",
      unnormalisable = al_gated & !refined_normalisable(symbol, cat),
      EF          = if_else(al_gated & !withheld & !unnormalisable & on_basis &
                              !is.na(ratio_al) &
                              !is.na(bg_ratio_al) & bg_ratio_al > 0,
                            ratio_al / bg_ratio_al, NA_real_),
      classifiable = if_else(al_gated, !is.na(EF),
                             !withheld & !is.na(value_std) & !is.na(p90_off)),
      # the permissive rule stays exactly EF < 1, so it stays empty off the aluminium
      # -controlled fraction and the EFSA pristineLoc field keeps its definition. The
      # sieved fractions carry the conservative verdict only, which is the right way
      # round while their offshore reference cannot be checked in the north (about 90
      # sieved measurements above 60N in the whole database).
      pristine_ef  = if_else(al_gated & classifiable, EF < 1, NA),
      # an unusable mixture threshold (no second population for it to bound) is not
      # applied: the criterion drops out rather than being enforced with a number that
      # marks nothing. A group with no mixture fit at all still has no strict verdict.
      mix_ok = case_when(is.na(usable)  ~ NA,
                         !usable        ~ TRUE,
                         TRUE           ~ value_std < threshold),
      # every criterion that applies to the fraction has to agree. In bulk that is all
      # three; in the sieved fractions the enrichment factor is not one of them, and
      # the two concentration criteria stand on the sieve for their grain-size control.
      pristine_strict = case_when(
        !classifiable            ~ NA,
        al_gated                 ~ (EF < 1) & mix_ok & (value_std < p90_off),
        TRUE                     ~ mix_ok & (value_std < p90_off)))

  # ── Summary per element x fraction ───────────────────────────────────────────
  summary_tbl <- m |>
    group_by(symbol, cat) |>
    summarise(gs_control = dplyr::first(gs_control),
              withheld = any(withheld), unnormalisable = any(unnormalisable), n = n(),
              pct_classifiable = round(100 * mean(classifiable)),
              n_classifiable   = sum(classifiable),
              pct_ef     = round(100 * mean(pristine_ef, na.rm = TRUE)),
              pct_strict = round(100 * mean(pristine_strict, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
           reliable = n_classifiable >= MIN_N) |>
    arrange(symbol, cat)

  # ── Coverage (the data gap) and validation, by distance band ─────────────────
  by_band <- function(df, axis) {
    df |> group_by(band) |>
      summarise(n = n(),
                pct_classifiable = round(100 * mean(classifiable)),
                n_class = sum(classifiable),
                ef     = round(100 * mean(pristine_ef, na.rm = TRUE)),
                strict = round(100 * mean(pristine_strict, na.rm = TRUE)), .groups = "drop") |>
      mutate(axis = axis)
  }
  # The coverage figure answers "where is the aluminium missing?", so it must be computed
  # only over groups that could be classified at all. Including a group whose verdict is
  # withheld everywhere (manganese, the sieved fractions, Se and Mo) would mix "no
  # aluminium here" with "no verdict for this element anywhere" and read as a worse data
  # gap than there is. Same restriction on the validation, for the same reason.
  # Both diagnostics ask an ALUMINIUM question ("where is the Al missing?" and "does the
  # Al-based verdict hold up against a pressure gradient?"), so both stay on the fraction
  # aluminium controls. Pooling the sieved fractions in would move every denominator
  # without adding a case: they are ~100% classifiable and, having been sampled almost
  # entirely by the German and Belgian programmes, carry 0 measurements within 5 km of a
  # Norwegian fish farm, so they cannot inform the near-cage bands at all.
  eligible <- m |> filter(!withheld, !unnormalisable, al_gated)

  banded <- bind_rows(
    eligible |> filter(!is.na(dist_to_fish_farm)) |>
      mutate(band = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS)) |>
      by_band("distance to fish farm"),
    eligible |> mutate(band = cut(dist_to_coast, CO_BREAKS, labels = CO_LABELS)) |>
      by_band("distance to coast"))

  coverage <- banded |> select(axis, band, n, pct_classifiable)

  # The coverage gradient looks like a property of near-cage sampling and is not: it is
  # which PROGRAMME sampled where. Splitting the same measurements by source shows Al
  # coverage that barely moves with distance inside a source, while the source mix moves
  # a great deal. Typed into the page before this existed, and therefore unverifiable.
  coverage_source <- eligible |>
    filter(!is.na(dist_to_fish_farm)) |>
    mutate(band = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS)) |>
    group_by(band) |>
    mutate(n_band = n()) |>
    group_by(band, source, n_band) |>
    summarise(n = n(), pct_classifiable = round(100 * mean(classifiable), 1),
              .groups = "drop") |>
    mutate(pct_of_band = round(100 * n / n_band, 1)) |>
    select(band, source, n, pct_classifiable, pct_of_band) |>
    arrange(band, desc(n))
  validation <- banded |>
    filter(n_class >= MIN_N) |>
    select(axis, band, n_class, ef, strict) |>
    pivot_longer(c(ef, strict), names_to = "rule", values_to = "pct_pristine")

  meta <- tibble(rule_ef = "bulk only: EF<1 (grain-size-controlled); unclassified where Al absent or off the fraction's Al basis. Undefined in the sieved fractions, where Al is not the control",
                 rule_strict = "every criterion that applies to the fraction agrees. bulk (Al-controlled): EF<1 AND below mixture threshold AND below offshore P90. sieved (sieve-controlled): below mixture threshold AND below offshore P90",
                 gs_control = "bulk=aluminium; sieved63/sieved20=sieve",
                 fallback = "none (no raw-concentration fallback; confounded, dropped)",
                 al_basis_used = paste(sprintf("%s=%s", names(refined_ef_basis()),
                                               refined_ef_basis()), collapse = "; "),
                 min_n = MIN_N)

  # ── The distance validation, run WITHIN each source ──────────────────────────
  # The aquaculture bands are not sampled by the same programmes (the near ones are
  # largely Vannmiljo, the far ones Mareano), so a gradient across them pooled over
  # sources could be a difference between programmes wearing a distance label. Repeating
  # it inside one source is the test that settles it; both sources that span more than one
  # band show the same rise, so the gradient is not a source artefact.
  validation_source <- m |>
    filter(cat == "bulk", classifiable, !is.na(dist_to_fish_farm)) |>
    mutate(band = cut(dist_to_fish_farm, AQ_BREAKS, labels = AQ_LABELS)) |>
    group_by(source, band) |>
    summarise(n = n(),
              pct_ef     = round(100 * mean(pristine_ef, na.rm = TRUE)),
              pct_strict = round(100 * mean(pristine_strict, na.rm = TRUE)),
              .groups = "drop") |>
    filter(n >= MIN_N) |>
    group_by(source) |>
    filter(n_distinct(band) >= 2) |>
    ungroup() |>
    arrange(source, band)

  # ── What each fraction's offshore reference actually is ──────────────────────
  # The verdict is only as good as the population it is referenced to, and the two
  # fractions are not referenced to the same sea. Sieving is a national convention
  # rather than a property of a sample: Norway reports bulk and Germany, Belgium and
  # the Netherlands sieve, so "offshore > 10 km" resolves to the deep Norwegian and
  # Barents Sea in bulk and to the southern North Sea and Baltic in the sieved
  # fractions. That is the standing caveat on a sieved verdict, and the pages that
  # carry the caveat read its numbers from here rather than restating them.
  # the latitude that counts as "the far north" for this caveat, published with the
  # counts so a page can label the column from the data instead of restating it
  NORTH_CUT <- 60
  FARM_NEAR <- 5
  reference <- m |>
    filter(dist_to_coast > 10, !withheld) |>
    group_by(cat) |>
    summarise(gs_control = dplyr::first(gs_control),
              n = n(),
              lat_p50   = round(median(latitude, na.rm = TRUE), 1),
              depth_p50 = round(median(depth, na.rm = TRUE)),
              top_seas  = paste(names(sort(table(sea_name), decreasing = TRUE))[1:2],
                                collapse = ", "),
              .groups = "drop") |>
    left_join(
      m |> filter(!withheld) |>
        group_by(cat) |>
        summarise(n_north = sum(latitude > NORTH_CUT, na.rm = TRUE),
                  n_farm_near = sum(dist_to_fish_farm < FARM_NEAR, na.rm = TRUE),
                  .groups = "drop"),
      by = "cat") |>
    mutate(north_cut_deg = NORTH_CUT, farm_near_km = FARM_NEAR) |>
    mutate(cat = factor(cat, levels = CATS)) |>
    arrange(cat)

  # ── Which control actually travels between seas ──────────────────────────────
  # The claim behind the per-fraction rule is that the sieve is the better grain-size
  # control, not merely a different one. This measures it: take each fraction's
  # offshore background sea by sea and ask how far it moves, as the largest sea median
  # over the smallest. A control that works should leave a background that is close to
  # the same number in every sea. Reported raw and after dividing by aluminium, so the
  # two controls are compared on one scale. Some of the spread is real contamination
  # rather than method noise, which is why this is only read as a comparison between
  # the two columns and never as an absolute.
  MIN_SEA <- 30L
  fold <- function(x) {
    x <- x[!is.na(x)]
    if (length(x) < 2) return(NA_real_)
    round(max(x) / min(x), 1)
  }
  sea_spread <- m |>
    filter(dist_to_coast > 10, !withheld, !is.na(sea_name)) |>
    group_by(symbol, cat, sea_name) |>
    summarise(n = n(),
              med_raw = median(value_std, na.rm = TRUE),
              med_al  = if (sum(!is.na(ratio_al)) >= MIN_SEA)
                          median(ratio_al, na.rm = TRUE) else NA_real_,
              .groups = "drop") |>
    filter(n >= MIN_SEA) |>
    group_by(symbol, cat) |>
    summarise(n_seas = n(), n = sum(n),
              fold_raw = fold(med_raw),
              n_seas_al = sum(!is.na(med_al)),
              fold_al = fold(med_al), .groups = "drop") |>
    filter(n_seas >= 3) |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat)

  write_csv(summary_tbl, file.path(adir, "refined_pristine_summary.csv"))
  write_csv(reference,   file.path(adir, "refined_pristine_reference.csv"))
  write_csv(sea_spread,  file.path(adir, "refined_pristine_sea_spread.csv"))
  write_csv(validation_source, file.path(adir, "refined_pristine_validation_source.csv"))
  write_csv(coverage,    file.path(adir, "refined_pristine_coverage.csv"))
  write_csv(coverage_source,
            file.path(adir, "refined_pristine_coverage_source.csv"))
  write_csv(validation,  file.path(adir, "refined_pristine_validation.csv"))
  write_csv(meta,        file.path(adir, "refined_pristine_meta.csv"))

  if (verbose) {
    # ── Console summary ──────────────────────────────────────────────────────────
    cat("pristine classification written to", adir, "\n\n")
    cat("% classifiable and % pristine among them (bulk: has Al, on the fraction's Al basis):\n")
    summary_tbl |> filter(cat == "bulk", reliable) |>
      select(symbol, n, pct_classifiable, n_classifiable, pct_ef, pct_strict) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nthe sieved fractions, controlled by the sieve (conservative verdict only):\n")
    summary_tbl |> filter(cat != "bulk", reliable) |>
      select(symbol, cat, n, pct_classifiable, n_classifiable, pct_strict) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nthe data gap (aluminium-controlled fraction): % classifiable by distance to fish farm:\n")
    coverage |> filter(axis == "distance to fish farm") |> as.data.frame() |> print(row.names = FALSE)
    cat("\nthe same validation WITHIN each source (is the gradient a source artefact?):\n")
    validation_source |> as.data.frame() |> print(row.names = FALSE)
    cat("\nvalidation (classifiable only): % pristine by distance to fish farm:\n")
    validation |> filter(axis == "distance to fish farm") |>
      pivot_wider(names_from = rule, values_from = pct_pristine) |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(adir)
}
