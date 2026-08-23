# ── Analysis, refined generation: background ─────────────────────────────
# Converted from R/analysis/background/04_refined_background_ef.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_refined_background_ef <- function(db_dir = multised_db_dir(),
                                           out_dir = multised_analysis_dir(),
                                           verbose = TRUE) {
  # ── Analysis stage, enrichment factor (REFINED database) ─────────────────────
  # The fourth background page, turning the background into a per-sample classifier. The
  # enrichment factor is
  #
  #     EF = (metal / Al)_sample  /  (metal / Al)_background
  #
  # relative to a LOCAL, data-driven background: the offshore (dist_to_coast > DIST_BG km)
  # MEDIAN of metal / Al, per element and fraction. This follows EFSA's steer to use a
  # local background and to AVOID literature crustal values (Turekian & Wedepohl). Al is
  # the normaliser (the grain-size carrier), so EF already controls for grain size.
  #
  # EF < 1 is read as adequate / at-or-below background (an EFSA convention); classes
  # 1-2 / 2-5 / >5 mark rising enrichment RELATIVE TO THE LOCAL OFFSHORE BACKGROUND (not
  # the crust, so the numbers are not the usual Sutherland scale). We report, per element
  # x fraction: the background reference value, the EF distribution and class shares, and
  # EF across the distance-to-aquaculture bands (does the near-cage enrichment survive
  # grain-size normalisation). Fractions bulk/sieved63/sieved20; outliers dropped.
  #
  # THE ALUMINIUM BASIS. Sections 6-7 (added as a diagnostic, see docs/ef-source-bias.md)
  # showed that the sources do not all measure Al the same way: some report near-total
  # aluminium, some report what an acid extraction leaches, which is 2-3x less. Al is the
  # denominator of every EF, so pooling the two bases makes the reference meaningless and
  # pushes the under-recovered samples toward falsely pristine.
  #
  # There is no digestion field to read (the refined `method` table carries no AL row), so
  # the basis is inferred per sample from Fe/Al. Fe and Al are both lithogenic and both
  # track grain size, so their ratio is nearly grain-size free, and an acid extraction
  # depresses Al far more than Fe: crustal Fe/Al is about 0.5, and Fe/Al at or above
  # FE_AL_CUT marks aluminium under-recovery. The cut separates a real bimodality WITHIN a
  # single source (ICES-DOME rows either side of it differ 1.7-2.5x in metal/Al), which is
  # what says it is finding protocol rather than geology.
  #
  # Each fraction is then restricted to ONE basis (EF_BASIS), the one carrying that
  # fraction's data, and samples on the other basis, or with no Fe to place them, are left
  # UNCLASSIFIED rather than judged against a reference they do not belong to. That is the
  # same stance the pristine pages already take for samples with no Al at all. It costs
  # roughly half the EF rows and buys a reference that means one thing.
  #
  # EF is therefore internally comparable within a fraction, and NOT comparable with
  # literature EF values for bulk, whose aluminium is on the extraction basis.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_ef_background.csv  per element x fraction: the (metal/Al) background reference
  #   refined_ef_dist.csv        EF distribution + class shares (incl. % EF<1, pristine)
  #   refined_ef_pressure.csv    median EF by distance-to-aquaculture band (Norway)
  #   refined_ef_source.csv      per source: its own reference vs the adopted one, and the
  #                              verdict shift that follows (diagnostic)
  #   refined_ef_region.csv      the same spread within one sea area, source against
  #                              region (diagnostic)
  #   refined_ef_basis.csv       the Al-basis strata per fraction and what the restriction
  #                              costs (diagnostic)
  #   refined_ef_basis_refs.csv  the adopted and rejected reference side by side
  #   refined_ef_meta.csv        one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  DIST_BG   <- 10          # km: offshore subset defining the background (metal/Al) median
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  MIN_N     <- 30L
  FE_AL_CUT <- refined_fe_al_cut()      # see R/analysis-refined-shared-basis.R
  EF_BASIS  <- refined_ef_basis()
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull metal/Al + distances ─────────────────────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.ratio_al,
           si.dist_to_coast, si.dist_to_aquaculture, si.sea_name, d.source,
           n.fe AS norm_fe, n.al AS norm_al
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
    WHERE me.outlier_flag IS NULL AND me.ratio_al IS NOT NULL AND me.ratio_al > 0
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    mutate(al_basis = refined_al_basis(norm_fe, norm_al),
           on_basis = refined_on_basis(al_basis, cat))
  dbDisconnect(con)

  # ── 2. Local background reference: offshore median of metal/Al ───────────────
  background <- m |>
    filter(dist_to_coast > DIST_BG, on_basis) |>
    group_by(symbol, cat) |>
    summarise(n_bg = n(), bg_ratio_al = median(ratio_al),
              # the second reference. EF < 1 against the MEDIAN of the offshore
              # population fails half of that population by construction, which is why
              # about half of everything comes out adequate: the number is arithmetic
              # before it is ecology. Against the P90 of the same population, EF < 1 means
              # "below the offshore 90th percentile", which is the background definition
              # the other pages already use, so the two references also expose an
              # inconsistency the site was carrying. The P90 reference is the LARGER
              # denominator and therefore the more permissive of the two; both are
              # reported so the spread between them is visible instead of one being
              # presented as the answer.
              bg_ratio_al_p90 = quantile(ratio_al, .9, names = FALSE), .groups = "drop") |>
    filter(n_bg >= MIN_N) |>
    mutate(al_basis = unname(EF_BASIS[cat]))

  # the reference each fraction did NOT adopt, kept for the diagnostic only
  background_off <- m |>
    filter(dist_to_coast > DIST_BG, !on_basis, al_basis != "unplaced") |>
    group_by(symbol, cat, al_basis) |>
    summarise(n_bg = n(), bg_ratio_al = median(ratio_al), .groups = "drop")

  # ── 3. EF per row ────────────────────────────────────────────────────────────
  ef <- m |>
    filter(on_basis) |>
    inner_join(background |> select(symbol, cat, bg_ratio_al, bg_ratio_al_p90),
               by = c("symbol", "cat")) |>
    mutate(EF = ratio_al / bg_ratio_al,
           EF_p90ref = ratio_al / bg_ratio_al_p90,
           ef_class = cut(EF, c(-Inf, 1, 2, 5, Inf),
                          labels = c("<1", "1-2", "2-5", ">5")))

  # ── 4. EF distribution + class shares per element x fraction ─────────────────
  ef_dist <- ef |>
    group_by(symbol, cat) |>
    summarise(n = n(),
              ef_p50 = signif(median(EF), 3),
              ef_p90 = signif(quantile(EF, .9, names = FALSE), 3),
              pct_lt1 = round(100 * mean(EF < 1)),
              pct_1_2 = round(100 * mean(EF >= 1 & EF < 2)),
              pct_2_5 = round(100 * mean(EF >= 2 & EF < 5)),
              pct_gt5 = round(100 * mean(EF >= 5)),
              ef_p50_p90ref = signif(median(EF_p90ref), 3),
              pct_lt1_p90ref = round(100 * mean(EF_p90ref < 1)),
              .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS), reliable = n >= MIN_N,
           # too much of the distribution was deleted below the LOQ for the reference to
           # mean anything; see R/analysis-refined-shared-censoring.R
           withheld = as.character(symbol) %in% refined_withheld_elements()) |>
    # a withheld element keeps its row and its n, so a reader sees that it exists and why
    # it is blank, but publishes no EF figure that would be read as a verdict
    mutate(across(c(ef_p50, ef_p90, pct_lt1, pct_1_2, pct_2_5, pct_gt5,
                    ef_p50_p90ref, pct_lt1_p90ref),
                  ~ if_else(withheld, NA_real_, as.numeric(.x)))) |>
    arrange(symbol, cat)

  # ── 5. EF vs distance to aquaculture (Norway) ────────────────────────────────
  ef_pressure <- ef |>
    filter(!is.na(dist_to_aquaculture)) |>
    mutate(aq_bin = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS)) |>
    group_by(symbol, cat, aq_bin) |>
    summarise(n = n(), ef_p50 = signif(median(EF), 3), .groups = "drop") |>
    filter(n >= MIN_N) |>
    mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat, aq_bin)

  # ── 6. Is the pooled reference source-biased? ────────────────────────────────
  # Per source: how much of the pooled reference it supplies, what its OWN offshore
  # reference would be, and how the EF verdict moves between the two. `bg_rel` above 1
  # means this source runs richer in metal/Al than the pooled reference, so judging it
  # against the pool inflates its EF; below 1 pushes it toward falsely pristine.
  # computed twice: `pooled` is every basis mixed, the state that produced the defect and
  # that the site pages describe; `adopted` is after the basis restriction, which is the
  # evidence that the restriction fixed it. Same code, different row set.
  source_check <- function(rows, set_label) {
    bg_src_tbl <- rows |>
      filter(dist_to_coast > DIST_BG) |>
      group_by(symbol, cat, source) |>
      summarise(n_bg = n(), bg_src = median(ratio_al), .groups = "drop") |>
      group_by(symbol, cat) |>
      mutate(bg_share = round(100 * n_bg / sum(n_bg))) |>
      ungroup()
    ref <- rows |>
      filter(dist_to_coast > DIST_BG) |>
      group_by(symbol, cat) |>
      summarise(n_ref = n(), ref_ratio_al = median(ratio_al), .groups = "drop") |>
      filter(n_ref >= MIN_N)
    rows |>
      inner_join(ref, by = c("symbol", "cat")) |>
      left_join(bg_src_tbl, by = c("symbol", "cat", "source")) |>
      group_by(symbol, cat, source, n_bg, bg_src, bg_share, ref_ratio_al) |>
      summarise(n = n(),
                ef_p50      = signif(median(ratio_al / ref_ratio_al), 3),
                pct_lt1     = round(100 * mean(ratio_al / ref_ratio_al < 1)),
                pct_gt5     = round(100 * mean(ratio_al / ref_ratio_al >= 5)),
                # the same rows judged against this source's own offshore reference
                ef_p50_own  = signif(median(ratio_al / bg_src), 3),
                pct_lt1_own = round(100 * mean(ratio_al / bg_src < 1)),
                .groups = "drop") |>
      mutate(set = set_label,
             bg_src = signif(bg_src, 4), ref_ratio_al = signif(ref_ratio_al, 4),
             bg_rel = round(bg_src / ref_ratio_al, 2),
             reliable = n >= MIN_N & !is.na(n_bg) & n_bg >= MIN_N)
  }

  ef_source <- bind_rows(source_check(m, "pooled"),
                         source_check(m |> filter(on_basis), "adopted")) |>
    mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
           set = factor(set, levels = c("pooled", "adopted"))) |>
    select(set, symbol, cat, source, n, n_bg, bg_share, bg_src,
           ref_ratio_al, bg_rel, ef_p50, pct_lt1, pct_gt5, ef_p50_own, pct_lt1_own, reliable) |>
    arrange(set, symbol, cat, source)

  # ── 7. Source against region ─────────────────────────────────────────────────
  # Sources sample different seas, so a cross-source spread can be geology rather than
  # method. Hold the sea area fixed and look again: `spread_sea` is the max/min of the
  # offshore metal/Al medians across the sources sampling ONE sea area, `spread_all` the
  # same across all sources pooled over every sea. spread_sea near 1 with spread_all
  # large says the spread is regional; the two close together says it is not.
  spread_all <- m |>
    filter(dist_to_coast > DIST_BG) |>
    group_by(symbol, cat, source) |>
    summarise(n_bg = n(), bg_src = median(ratio_al), .groups = "drop") |>
    filter(n_bg >= MIN_N) |>
    group_by(symbol, cat) |>
    filter(n_distinct(source) >= 2) |>
    summarise(spread_all = signif(max(bg_src) / min(bg_src), 3), .groups = "drop")

  # unrestricted on purpose: this is the evidence that the spread is method rather than
  # geology, which is what motivates the restriction. Restricting it first would erase it.
  ef_region <- m |>
    filter(dist_to_coast > DIST_BG, !is.na(sea_name)) |>
    group_by(symbol, cat, sea_name, source) |>
    summarise(n_bg = n(), bg_sea_src = median(ratio_al), .groups = "drop") |>
    filter(n_bg >= MIN_N) |>
    group_by(symbol, cat, sea_name) |>
    filter(n_distinct(source) >= 2) |>
    mutate(n_sources = n_distinct(source),
           spread_sea = signif(max(bg_sea_src) / min(bg_sea_src), 3)) |>
    ungroup() |>
    left_join(spread_all, by = c("symbol", "cat")) |>
    mutate(bg_sea_src = signif(bg_sea_src, 4),
           symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
    select(symbol, cat, sea_name, source, n_bg, bg_sea_src, n_sources, spread_sea, spread_all) |>
    arrange(symbol, cat, sea_name, desc(n_bg))

  # ── 8. The basis restriction itself ──────────────────────────────────────────
  # What each fraction's strata look like, what each stratum's own offshore reference
  # would be, and what the restriction costs. `adopted` marks the stratum EF is computed
  # on; every other row is left unclassified.
  ef_basis <- m |>
    group_by(cat, al_basis) |>
    summarise(n = n(),
              n_offshore = sum(dist_to_coast > DIST_BG, na.rm = TRUE),
              n_aq_lt1km = sum(!is.na(dist_to_aquaculture) & dist_to_aquaculture < 1),
              n_sources  = n_distinct(source),
              .groups = "drop") |>
    group_by(cat) |>
    mutate(pct_of_frac = round(100 * n / sum(n))) |>
    ungroup() |>
    mutate(adopted = al_basis == unname(EF_BASIS[cat]),
           cat = factor(cat, levels = CATS)) |>
    select(cat, al_basis, adopted, n, pct_of_frac, n_offshore, n_aq_lt1km, n_sources) |>
    arrange(cat, desc(adopted), desc(n))

  # the two references side by side, so the size of what the restriction avoided is on
  # the record rather than only in the commit message
  basis_refs <- background |>
    select(symbol, cat, al_basis, n_bg, bg_ratio_al) |>
    bind_rows(background_off |> select(symbol, cat, al_basis, n_bg, bg_ratio_al)) |>
    filter(n_bg >= MIN_N) |>
    mutate(bg_ratio_al = signif(bg_ratio_al, 4),
           adopted = al_basis == unname(EF_BASIS[cat]),
           symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
    arrange(symbol, cat, desc(adopted))

  bg_out <- background |>
    mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
           bg_ratio_al = signif(bg_ratio_al, 4)) |>
    mutate(withheld = as.character(symbol) %in% refined_withheld_elements(),
           bg_ratio_al_p90 = signif(bg_ratio_al_p90, 4)) |>
    select(symbol, cat, al_basis, n_bg, bg_ratio_al, bg_ratio_al_p90, withheld) |>
    arrange(symbol, cat)

  meta <- tibble(normaliser = "Al", background = sprintf("offshore >%d km median of metal/Al", DIST_BG),
                 background_2 = sprintf("offshore >%d km P90 of metal/Al (second reference; larger denominator, so more permissive, and it makes EF<1 mean 'below the offshore P90' as the other pages define background)", DIST_BG),
                 headline = "the median reference; the P90 one is reported beside it as ef_*_p90ref",
                 ef_lt1 = "adequate / at-or-below local background", min_n = MIN_N,
                 al_basis_rule = sprintf("per sample: Fe/Al >= %.1f -> extraction, else total, no Fe -> unplaced",
                                         FE_AL_CUT),
                 al_basis_used = paste(sprintf("%s=%s", names(EF_BASIS), EF_BASIS), collapse = "; "),
                 unplaced = "left unclassified, as samples with no Al already are",
                 note = "EF relative to LOCAL offshore background, not crustal (Turekian/Wedepohl avoided); bulk Al is on the extraction basis, so bulk EF is NOT comparable with literature EF values")

  # ── 6. Write ─────────────────────────────────────────────────────────────────
  write_csv(bg_out,      file.path(out_dir, "refined_ef_background.csv"))
  write_csv(ef_dist,     file.path(out_dir, "refined_ef_dist.csv"))
  write_csv(ef_pressure, file.path(out_dir, "refined_ef_pressure.csv"))
  write_csv(ef_source,   file.path(out_dir, "refined_ef_source.csv"))
  write_csv(ef_region,   file.path(out_dir, "refined_ef_region.csv"))
  write_csv(ef_basis,    file.path(out_dir, "refined_ef_basis.csv"))
  write_csv(basis_refs,  file.path(out_dir, "refined_ef_basis_refs.csv"))
  write_csv(meta,        file.path(out_dir, "refined_ef_meta.csv"))

  if (verbose) {
    # ── 7. Console summary ───────────────────────────────────────────────────────
    cat("enrichment-factor analysis written to", out_dir, "\n\n")
    cat("EF distribution (bulk): median, P90, and % of samples adequate (EF<1):\n")
    ef_dist |> filter(cat == "bulk", reliable) |>
      select(symbol, n, ef_p50, ef_p90, pct_lt1, pct_gt5) |> as.data.frame() |> print(row.names = FALSE)
    cat("\nmedian EF by distance to aquaculture (bulk; does near-cage enrichment survive Al-normalisation?):\n")
    ef_pressure |> filter(cat == "bulk") |>
      select(symbol, aq_bin, ef_p50) |> pivot_wider(names_from = aq_bin, values_from = ef_p50) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nsource check (bulk): each source's offshore metal/Al against the pooled reference,\n")
    cat("and the % adequate it gets from the pool vs from its own reference:\n")
    ef_source |> filter(cat == "bulk", reliable) |>
      select(set, symbol, source, n_bg, bg_share, bg_rel, pct_lt1, pct_lt1_own) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nAl-basis strata per fraction (EF is computed on the adopted one only):\n")
    ef_basis |> as.data.frame() |> print(row.names = FALSE)
    cat("\nregion check (bulk): cross-source spread within one sea area vs pooled over all seas\n")
    cat("(spread_sea near 1 with spread_all large would mean the spread is geology, not method):\n")
    ef_region |> filter(cat == "bulk") |>
      distinct(symbol, sea_name, n_sources, spread_sea, spread_all) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
