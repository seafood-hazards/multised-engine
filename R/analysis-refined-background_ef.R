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
  # The background reference is a median over a MIXTURE OF SOURCES, and the sources do not
  # contribute evenly. If their metal/Al levels differ, the reference is close to whichever
  # source dominates it, and every other source is judged against a population it does not
  # belong to. Sections 6-7 measure that: 6 compares each source's own offshore reference
  # (and the verdict it would get from it) with the pooled one; 7 repeats the comparison
  # WITHIN a sea area, so a spread that is really geology can be told from one that is
  # really method. Both are diagnostics: they change no verdict here.
  #
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_ef_background.csv  per element x fraction: the (metal/Al) background reference
  #   refined_ef_dist.csv        EF distribution + class shares (incl. % EF<1, pristine)
  #   refined_ef_pressure.csv    median EF by distance-to-aquaculture band (Norway)
  #   refined_ef_source.csv      per source: its own reference vs the pooled one, and the
  #                              verdict shift that follows (diagnostic)
  #   refined_ef_region.csv      the same spread within one sea area, source against
  #                              region (diagnostic)
  #   refined_ef_meta.csv        one-row config

  db_path <- refined_db_path(db_dir)

  CATS      <- c("bulk", "sieved63", "sieved20")
  DIST_BG   <- 10          # km: offshore subset defining the background (metal/Al) median
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
  MIN_N     <- 30L
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

  out_dir <- file.path(out_dir, "background")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull metal/Al + distances ─────────────────────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  m <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.ratio_al,
           si.dist_to_coast, si.dist_to_aquaculture, si.sea_name, d.source
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    JOIN dataset d   ON d.dataset_id   = e.dataset_id
    WHERE me.outlier_flag IS NULL AND me.ratio_al IS NOT NULL AND me.ratio_al > 0
  ")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS)
  dbDisconnect(con)

  # ── 2. Local background reference: offshore median of metal/Al ───────────────
  background <- m |>
    filter(dist_to_coast > DIST_BG) |>
    group_by(symbol, cat) |>
    summarise(n_bg = n(), bg_ratio_al = median(ratio_al), .groups = "drop") |>
    filter(n_bg >= MIN_N)

  # ── 3. EF per row ────────────────────────────────────────────────────────────
  ef <- m |>
    inner_join(background |> select(symbol, cat, bg_ratio_al), by = c("symbol", "cat")) |>
    mutate(EF = ratio_al / bg_ratio_al,
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
              .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           cat = factor(cat, levels = CATS), reliable = n >= MIN_N) |>
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
  bg_source <- m |>
    filter(dist_to_coast > DIST_BG) |>
    group_by(symbol, cat, source) |>
    summarise(n_bg = n(), bg_src = median(ratio_al), .groups = "drop") |>
    group_by(symbol, cat) |>
    mutate(bg_share = round(100 * n_bg / sum(n_bg))) |>
    ungroup()

  ef_source <- ef |>
    left_join(bg_source |> select(symbol, cat, source, n_bg, bg_src, bg_share),
              by = c("symbol", "cat", "source")) |>
    group_by(symbol, cat, source, n_bg, bg_src, bg_share, bg_ratio_al) |>
    summarise(n = n(),
              ef_p50      = signif(median(EF), 3),
              pct_lt1     = round(100 * mean(EF < 1)),
              pct_gt5     = round(100 * mean(EF >= 5)),
              # the same rows judged against this source's own offshore reference
              ef_p50_own  = signif(median(ratio_al / bg_src), 3),
              pct_lt1_own = round(100 * mean(ratio_al / bg_src < 1)),
              .groups = "drop") |>
    mutate(bg_src = signif(bg_src, 4), bg_ratio_al = signif(bg_ratio_al, 4),
           bg_rel = round(bg_src / bg_ratio_al, 2),
           symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
           reliable = n >= MIN_N & !is.na(n_bg) & n_bg >= MIN_N) |>
    select(symbol, cat, source, n, n_bg, bg_share, bg_src, bg_ratio_al, bg_rel,
           ef_p50, pct_lt1, pct_gt5, ef_p50_own, pct_lt1_own, reliable) |>
    arrange(symbol, cat, source)

  # ── 7. Source against region ─────────────────────────────────────────────────
  # Sources sample different seas, so a cross-source spread can be geology rather than
  # method. Hold the sea area fixed and look again: `spread_sea` is the max/min of the
  # offshore metal/Al medians across the sources sampling ONE sea area, `spread_all` the
  # same across all sources pooled over every sea. spread_sea near 1 with spread_all
  # large says the spread is regional; the two close together says it is not.
  spread_all <- bg_source |>
    filter(n_bg >= MIN_N) |>
    group_by(symbol, cat) |>
    filter(n_distinct(source) >= 2) |>
    summarise(spread_all = signif(max(bg_src) / min(bg_src), 3), .groups = "drop")

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

  bg_out <- background |>
    mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
           bg_ratio_al = signif(bg_ratio_al, 4)) |>
    arrange(symbol, cat)

  meta <- tibble(normaliser = "Al", background = sprintf("offshore >%d km median of metal/Al", DIST_BG),
                 ef_lt1 = "adequate / at-or-below local background", min_n = MIN_N,
                 note = "EF relative to LOCAL offshore background, not crustal (Turekian/Wedepohl avoided)")

  # ── 6. Write ─────────────────────────────────────────────────────────────────
  write_csv(bg_out,      file.path(out_dir, "refined_ef_background.csv"))
  write_csv(ef_dist,     file.path(out_dir, "refined_ef_dist.csv"))
  write_csv(ef_pressure, file.path(out_dir, "refined_ef_pressure.csv"))
  write_csv(ef_source,   file.path(out_dir, "refined_ef_source.csv"))
  write_csv(ef_region,   file.path(out_dir, "refined_ef_region.csv"))
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
      select(symbol, source, n_bg, bg_share, bg_rel, pct_lt1, pct_lt1_own) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nregion check (bulk): cross-source spread within one sea area vs pooled over all seas\n")
    cat("(spread_sea near 1 with spread_all large would mean the spread is geology, not method):\n")
    ef_region |> filter(cat == "bulk") |>
      distinct(symbol, sea_name, n_sources, spread_sea, spread_all) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
