# ── Analysis, refined generation: summary ────────────────────────────────────
# The assembly step behind the multised-summary site (generation 6).
#
# This module DERIVES NO VERDICT. Every background value, every pristine share and
# every enrichment number below is read from the CSVs the `background` module has
# already written, and is only reshaped into one row per element so a page can draw
# it without arithmetic. What it does compute itself is EXTENT: how many
# measurements, sites, datasets and years stand behind each element, the per-source
# and per-stage counts for the Methods pages, and the site-level aggregation the
# interactive maps need.
#
# The rule the site rests on is the one the two refined summary pages already
# follow: a summary page recomputes nothing. A number the site needs that no CSV
# holds belongs here, in the pipeline, not typed into a page. That is the whole
# reason this module exists rather than the site reading the 65 background CSVs and
# composing them in-page.
#
# Requires the `background` module to have run first: analyze_data("refined").
#
# Outputs -> data/analysis/summary/ (gitignored):
#   summary_elements.csv    one row per element x fraction: extent, and what can be said
#   summary_background.csv  long: every background estimate from every method
#   summary_verdicts.csv    per element x fraction: classifiable %, pristine %, Igeo classes
#   summary_coverage.csv    the classifiability gap by distance band, on both axes
#   summary_censoring.csv   below-LOQ shares per element and source: why two are withheld
#   summary_pressure.csv    long: the aquaculture gradient, concentration and Igeo
#   summary_controls.csv    the four independent near-vs-far controls, side by side
#   summary_sources.csv     per source: what each of the five contributes
#   summary_flow.csv        per stage: the pilot -> refined funnel
#   summary_map_sites.csv   per site x element x fraction: the full-resolution layer
#   summary_map_grid.csv    the same on a 0.1 degree grid: what the site draws
#   summary_meta.csv        one-row provenance

analysis_refined_summary <- function(db_dir = multised_db_dir(),
                                     out_dir = multised_analysis_dir(),
                                     verbose = TRUE) {

  db_path <- refined_db_path(db_dir)
  bdir <- file.path(out_dir, "background")
  adir <- file.path(out_dir, "summary")
  dir.create(adir, recursive = TRUE, showWarnings = FALSE)

  CATS  <- c("bulk", "sieved63", "sieved20")
  MIN_N <- 30L
  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
  AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")

  if (!dir.exists(bdir))
    stop("the background module has not run: ", bdir, " does not exist. ",
         "Run analyze_data(\"refined\", module = \"background\") first.", call. = FALSE)

  rd <- function(f) {
    p <- file.path(bdir, f)
    if (!file.exists(p))
      stop("missing ", f, " in ", bdir, ": re-run the background module.", call. = FALSE)
    read_csv(p, show_col_types = FALSE)
  }

  # ── 1. What the background module already decided ────────────────────────────
  cmp  <- rd("refined_background_compare.csv")
  mix  <- rd("refined_mixture_components.csv")
  gsp  <- rd("refined_gsnorm_percentiles.csv")
  prc  <- rd("refined_pressure_compare.csv")
  prp  <- rd("refined_pressure_percentiles.csv")
  efb  <- rd("refined_ef_background.csv")
  igb  <- rd("refined_igeo_background.csv")
  igc  <- rd("refined_igeo_classes.csv")
  igm  <- rd("refined_igeo_pressure_matched.csv")
  ps   <- rd("refined_pristine_summary.csv")
  pcov <- rd("refined_pristine_coverage.csv")
  pref <- rd("refined_pristine_reference.csv")
  pspr <- rd("refined_pristine_sea_spread.csv")
  pctl <- rd("refined_pressure_controls.csv")
  iws  <- rd("refined_igeo_within_site.csv")
  cens <- rd("refined_censoring.csv")

  # ── 2. Extent, straight from the refined database ────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)

  ext <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std,
           e.site_id, e.dataset_id, e.year, me.source
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS)

  elem_names <- as_tibble(dbGetQuery(con, "SELECT symbol, name FROM element"))

  # Element-level counts as well as fraction-level ones. A site measured in two
  # fractions is one site, so the per-fraction counts must not be added up: a page
  # that sums them reports more sites than exist. Carried as columns rather than a
  # second file so the two can never be joined wrongly.
  extent_elem <- ext |>
    group_by(symbol) |>
    summarise(n_elem = n(),
              n_sites_elem   = n_distinct(site_id),
              n_sources_elem = n_distinct(source),
              year_min_elem  = suppressWarnings(min(year, na.rm = TRUE)),
              year_max_elem  = suppressWarnings(max(year, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(across(c(year_min_elem, year_max_elem),
                  ~ ifelse(is.finite(.x), .x, NA_integer_)))

  extent <- ext |>
    group_by(symbol, cat) |>
    summarise(n = n(),
              n_sites    = n_distinct(site_id),
              n_datasets = n_distinct(dataset_id),
              n_sources  = n_distinct(source),
              year_min   = suppressWarnings(min(year, na.rm = TRUE)),
              year_max   = suppressWarnings(max(year, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(across(c(year_min, year_max), ~ ifelse(is.finite(.x), .x, NA_integer_))) |>
    left_join(extent_elem, by = "symbol")

  # ── 3. summary_elements: extent plus what can be said about it ───────────────
  # The two withholding rules are read from their frozen tables rather than
  # re-derived, so this page cannot disagree with the pages it summarises.
  withheld <- refined_withheld_elements()
  cens_all <- cens |> filter(source == "ALL") |> select(symbol, pct_censored)

  # D4's own measures travel with the flag it produced. Without them the summary
  # can only assert that aluminium fails on the sieved fractions, and the obvious
  # reading of that is "not enough sieved data", which is the wrong one: copper
  # sieved below 63 um has 2 203 aluminium-paired samples and an r-squared of
  # 0.003. The numbers are the answer, so they are published rather than described.
  al <- refined_normalisability_table() |>
    transmute(symbol, cat, al_n = n_all, al_r2 = r2, al_rho = rho)

  elements <- extent |>
    left_join(elem_names, by = "symbol") |>
    left_join(cens_all, by = "symbol") |>
    left_join(al, by = c("symbol", "cat")) |>
    mutate(
      withheld     = symbol %in% withheld,
      # what controls grain size here, and so which gate the verdict has to pass.
      # Aluminium is the control in bulk and has to earn it (D4); in the sieved
      # fractions the sieve is the control and did the job before the chemistry
      # started, so D4 does not apply and the r2 beside it is a diagnostic only.
      gs_control   = refined_gs_control(cat),
      normalisable = refined_normalisable(symbol, cat),
      al_tested    = !is.na(al_n),
      has_background = n >= MIN_N & !withheld,
      has_verdict    = has_background & (gs_control == "sieve" | normalisable),
      # one plain-English clause per group, for the Results landing matrix. The
      # order matters: censoring is checked first because a withheld element has no
      # background to normalise in the first place.
      note = case_when(
        withheld ~ sprintf("withheld: %s%% of measurements fell below the limit of quantification",
                           format(pct_censored, trim = TRUE)),
        n < MIN_N ~ sprintf("too few measurements (%d, the reporting threshold is %d)", n, MIN_N),
        gs_control == "sieve" ~ "full: concentrations, background and a pristine verdict, grain-size controlled by the sieve rather than by aluminium",
        !normalisable ~ "concentrations and background only: aluminium does not predict this element, so no enrichment factor",
        TRUE ~ "full: concentrations, background and a pristine verdict"
      )
    ) |>
    select(symbol, name, cat, n, n_sites, n_datasets, n_sources, year_min, year_max,
           n_elem, n_sites_elem, n_sources_elem, year_min_elem, year_max_elem,
           pct_censored, withheld, gs_control, al_tested, al_n, al_r2, al_rho,
           normalisable, has_background, has_verdict, note) |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS))

  # ── 4. summary_background: every estimate, one row each ──────────────────────
  # Five methods that rest on different assumptions and partly different samples.
  # They are stacked, not averaged: where they agree the agreement is the evidence.
  bg_long <- bind_rows(
    cmp |> transmute(symbol, cat, method = "offshore",
                     label = "Offshore median (>10 km from the coast)",
                     value = p50_off10, n = n_off10),
    cmp |> transmute(symbol, cat, method = "offshore_p90",
                     label = "Offshore 90th percentile",
                     value = p90_off10, n = n_off10),
    mix |> transmute(symbol, cat, method = "mixture",
                     label = "Distribution-mixture upper bound",
                     value = threshold, n = n, usable),
    # Bulk only. This is now enforced upstream, in
    # analysis_refined_background_gsnorm(), which stopped computing a fines basis off
    # bulk once it was clear that `fines_lt63` describes the PARENT sediment rather
    # than the sieved aliquot. The filter stays as an assertion: if a sieved fines row
    # ever reappears in the input it should not reach a summary page.
    gsp |> filter(basis == "fines", subset == "offshore>10km", cat == "bulk") |>
      transmute(symbol, cat, method = "gsnorm",
                label = "Grain-size-normalised offshore median", value = p50, n = n),
    prc |> transmute(symbol, cat, method = "pressure_far",
                     label = "Far from any fish farm (>20 km), stated pressure removed",
                     value = p50_far_clean, n = n_far_clean),
    igb |> transmute(symbol, cat, method = "igeo_b",
                     label = "Igeo reference B (offshore median)",
                     value = bg_median, n = n_bg)
  ) |>
    mutate(usable = ifelse(is.na(usable), TRUE, usable),
           # A withheld element is withheld here too. Its rows are kept so the
           # decision is auditable rather than invisible, but `reliable` is FALSE,
           # and the pages show nothing for it. Without this the site printed a
           # molybdenum background two paragraphs above the sentence saying it has
           # none.
           withheld = symbol %in% withheld,
           reliable = !is.na(value) & !is.na(n) & n >= MIN_N & usable & !withheld,
           symbol = factor(symbol, levels = elem_levels)) |>
    select(symbol, cat, method, label, value, n, withheld, reliable) |>
    arrange(symbol, match(cat, CATS), method)

  # ── 5. summary_verdicts: the classification, per element x fraction ──────────
  igeo_clean <- igc |>
    group_by(symbol, cat) |>
    summarise(n_igeo = sum(n),
              pct_igeo_class0 = round(100 * sum(n[igeo_class == "0 unpolluted"]) / sum(n), 1),
              .groups = "drop")

  verdicts <- ps |>
    select(symbol, cat, n, pct_classifiable, n_classifiable,
           pct_ef, pct_strict, withheld, unnormalisable, reliable) |>
    left_join(igeo_clean, by = c("symbol", "cat")) |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS))

  # The classifiability gap, by distance band on both axes. Carried through as its
  # own table because it is a finding in its own right, not a caveat: near a fish
  # farm, aluminium is almost never measured, so almost nothing there can be judged.
  coverage <- pcov |>
    mutate(axis = factor(axis, levels = unique(axis))) |>
    arrange(axis)

  # The per-source censoring detail, for the pages of the two withheld elements. A
  # page that says "withheld" without showing the measurement behind it is asking to
  # be taken on trust.
  censoring <- cens |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, desc(pct_censored))

  # ── 6. summary_pressure: the aquaculture gradient, two ways ──────────────────
  # Concentration by band is the direct reading; the texture-matched Igeo is the
  # controlled one. They are kept as separate measures rather than merged, because
  # they rest on different row populations: see the Igeo page for what the controls
  # cost.
  pressure <- bind_rows(
    prp |> transmute(symbol, cat, measure = "concentration", band = dist_bin,
                     n, value = p50, reliable),
    igm |> filter(window == "50-100%") |>
      transmute(symbol, cat, measure = "igeo_matched", band = dist_bin,
                n, value = igeo_p50, reliable = n >= MIN_N)
  ) |>
    mutate(band = factor(band, levels = AQ_LABELS),
           symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS), measure, band)

  gradient <- prc |>
    transmute(symbol, cat,
              enrich_near, enrich_near_clean, pct_far_stated,
              symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS))

  # The four near-vs-far controls on one axis, so a page can put them side by side
  # without knowing how each was computed. They run on four different row
  # populations by design: a single control can always be an accident of which
  # samples it happened to keep, and four agreeing cannot.
  #
  # The Igeo control is expressed as a concentration ratio so it is comparable with
  # the other three. Igeo is a log2 index, so a near-minus-far difference of d is a
  # factor of 2^d.
  igeo_ratio <- igm |>
    filter(window == "50-100%") |>
    select(symbol, cat, dist_bin, igeo_p50, n) |>
    pivot_wider(names_from = dist_bin, values_from = c(igeo_p50, n)) |>
    filter(!is.na(`igeo_p50_<1km`), !is.na(`igeo_p50_>20km`)) |>
    transmute(symbol, cat, control = "texture-matched",
              n_near = `n_<1km`, n_far = `n_>20km`,
              ratio = round(2 ^ (`igeo_p50_<1km` - `igeo_p50_>20km`), 2))

  # The within-site control compares a site with itself over time, so it has no
  # near/far ratio at all. What it reports is the share of sites whose Igeo is
  # rising, under the cages against the outer ring.
  within_site <- iws |>
    filter(basis == "gap 2-7 yr", zone %in% c("0-1 km", "5-20 km")) |>
    select(symbol, cat, zone, pct_rising, n_sites) |>
    pivot_wider(names_from = zone, values_from = c(pct_rising, n_sites)) |>
    transmute(symbol, cat, control = "same site over time",
              n_near = `n_sites_0-1 km`, n_far = `n_sites_5-20 km`,
              ratio = NA_real_,
              detail = sprintf("%.1f%% of near-cage sites rising, against %.1f%% at 5-20 km",
                               `pct_rising_0-1 km`, `pct_rising_5-20 km`))

  controls <- bind_rows(
    pctl |> filter(control == "published") |>
      transmute(symbol, cat, control = "concentration by band",
                n_near, n_far, ratio = ratio_p90, reliable),
    pctl |> filter(control == "municipality-matched") |>
      transmute(symbol, cat, control = "same municipality",
                n_near, n_far, ratio = ratio_p90, reliable),
    igeo_ratio, within_site
  ) |>
    mutate(
      reliable = ifelse(is.na(reliable), TRUE, reliable),
      holds = c(`concentration by band` = "nothing beyond removing monitored pollution",
                `texture-matched`       = "grain size",
                `same municipality`     = "region and local geology",
                `same site over time`   = "everything about the location")[control],
      detail = ifelse(is.na(detail) & !is.na(ratio),
                      sprintf("%.2fx", ratio), detail),
      control = factor(control, levels = c("concentration by band", "texture-matched",
                                           "same municipality", "same site over time")),
      symbol = factor(symbol, levels = elem_levels)) |>
    select(symbol, cat, control, holds, n_near, n_far, ratio, detail, reliable) |>
    arrange(symbol, match(cat, CATS), control)

  # ── 7. summary_sources: what each of the five brings ─────────────────────────
  # Counted over the SAME rows as everything else on the site: `ext` already holds
  # them, so the per-source table is cut from it rather than from a second query
  # that could quietly use a different filter. It did once, and the home page
  # showed two different totals.
  src_names <- as_tibble(dbGetQuery(con,
    "SELECT dataset_id, source FROM dataset")) |> rename(src = source)
  sources <- ext |>
    left_join(src_names, by = "dataset_id") |>
    group_by(source = src) |>
    summarise(n = n(),
              n_sites    = n_distinct(site_id),
              n_datasets = n_distinct(dataset_id),
              n_elements = n_distinct(symbol),
              year_min   = suppressWarnings(min(year, na.rm = TRUE)),
              year_max   = suppressWarnings(max(year, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(across(c(year_min, year_max), ~ ifelse(is.finite(.x), .x, NA_integer_)),
           pct = round(100 * n / sum(n), 1)) |>
    arrange(desc(n))

  # ── 8. summary_flow: the funnel, counted in the databases themselves ─────────
  # Read rather than remembered. A stage whose database is absent is reported as NA
  # instead of being dropped, so a gap in the working area is visible on the page.
  stage_db <- function(gen) {
    if (gen == "merged") return(file.path(db_dir, "multised_merged.sqlite"))
    if (gen == "refined") return(db_path)
    vapply(multised_sources(), function(s)
      file.path(db_dir, paste0(source_stem(s), "_", gen, ".sqlite")), character(1))
  }
  count_stage <- function(gen) {
    paths <- stage_db(gen)
    paths <- paths[file.exists(paths)]
    if (!length(paths)) return(tibble(n = NA_integer_, n_sites = NA_integer_))
    tot <- lapply(paths, function(p) {
      cn <- dbConnect(SQLite(), p); on.exit(dbDisconnect(cn), add = TRUE)
      tbls <- dbListTables(cn)
      if (!all(c("measurement", "site") %in% tbls)) return(tibble(n = NA_integer_, n_sites = NA_integer_))
      tibble(n = dbGetQuery(cn, "SELECT COUNT(*) n FROM measurement")$n,
             n_sites = dbGetQuery(cn, "SELECT COUNT(*) n FROM site")$n)
    })
    bind_rows(tot) |> summarise(n = sum(n), n_sites = sum(n_sites))
  }
  flow <- bind_rows(lapply(c("slim", "clean", "merged", "refined"), function(g)
    count_stage(g) |> mutate(stage = g, .before = 1))) |>
    bind_rows(tibble(stage = "analysed", n = nrow(ext),
                     n_sites = n_distinct(ext$site_id))) |>
    mutate(what = case_when(
      stage == "slim"    ~ "One database per source, in a shared 7-table schema",
      stage == "clean"   ~ "Quality flags applied, below-LOQ and invalid rows removed",
      stage == "merged"  ~ "The five sources unioned, cross-source duplicates removed",
      stage == "refined" ~ "The mart for this work: target elements, normalisers, ratios",
      stage == "analysed" ~ "What this site reports: positive values, no outliers, bulk or a standard sieved fraction"))

  # ── 9. summary_map_sites: one point per site x element x fraction ────────────
  # The site is the unit here, not the measurement, because a map draws points. A
  # site whose measurements straddle a threshold lands on one side of it once
  # averaged, so these flags are a coarser classifier than the per-measurement ones
  # on the analysis pages, and the pages remain the authoritative count.
  thr <- cmp |> select(symbol, cat, p90_off = p90_off10) |>
    left_join(mix |> select(symbol, cat, mix_thr = threshold, mix_usable = usable),
              by = c("symbol", "cat")) |>
    left_join(efb |> select(symbol, cat, bg_ratio_al), by = c("symbol", "cat")) |>
    left_join(igb |> select(symbol, cat, bg_median), by = c("symbol", "cat"))

  # The pristine classification is applied PER MEASUREMENT, with the predicate of
  # `analysis_refined_pristine()` and none of its own: same thresholds,
  # same gates, same treatment of an unusable mixture bound. This module still
  # derives no verdict, it only carries one down to a point on a map. Doing it per
  # measurement rather than on the site median is what keeps it agreeing with the
  # published shares; the aggregation to a site and then to a cell is a majority at
  # each step, and both compositions travel with the point so a reader can see the
  # mixing rather than infer it.
  map_meas <- as_tibble(dbGetQuery(con, "
    SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std, me.ratio_al,
           si.site_id, si.latitude, si.longitude,
           si.dist_to_coast, si.dist_to_fish_farm,
           n.fe AS norm_fe, n.al AS norm_al
    FROM measurement me
    JOIN subsample s ON s.subsample_id = me.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    -- the normaliser table holds one row per subsample PER FRACTION CLASS, so this
    -- join must match frac_class too, or a subsample carrying both a bulk and a
    -- sieved normaliser duplicates its measurements and can attach the wrong
    -- fraction's aluminium. Same trap as in the pristine module.
    LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
                          AND n.frac_class   = me.frac_class
    WHERE me.value_std > 0 AND me.outlier_flag IS NULL
      AND si.latitude IS NOT NULL AND si.longitude IS NOT NULL")) |>
    mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                           sieve_um_std == 63 ~ "sieved63",
                           sieve_um_std == 20 ~ "sieved20",
                           TRUE ~ NA_character_)) |>
    filter(cat %in% CATS) |>
    left_join(thr, by = c("symbol", "cat")) |>
    mutate(
      al_basis   = refined_al_basis(norm_fe, norm_al),
      on_basis   = refined_on_basis(al_basis, cat),
      withheld_el = symbol %in% refined_withheld_elements(),
      al_gated   = refined_gs_control(cat) == "aluminium",
      unnorm     = al_gated & !refined_normalisable(symbol, cat),
      EF = if_else(al_gated & !withheld_el & !unnorm & on_basis &
                     !is.na(ratio_al) & !is.na(bg_ratio_al) & bg_ratio_al > 0,
                   ratio_al / bg_ratio_al, NA_real_),
      classifiable = if_else(al_gated, !is.na(EF),
                             !withheld_el & !is.na(value_std) & !is.na(p90_off)),
      # an unusable mixture bound drops out of the test rather than being enforced
      # with a number that marks nothing, exactly as the pristine module has it.
      mix_ok = case_when(is.na(mix_usable) ~ NA,
                         !mix_usable       ~ TRUE,
                         TRUE              ~ value_std < mix_thr),
      pristine_ef = if_else(al_gated & classifiable, EF < 1, NA),
      pristine_strict = case_when(
        !classifiable ~ NA,
        al_gated      ~ (EF < 1) & mix_ok & (value_std < p90_off),
        TRUE          ~ mix_ok & (value_std < p90_off)))

  map_sites <- map_meas |>
    group_by(symbol, cat, site_id) |>
    summarise(latitude = round(first(latitude), 4),
              longitude = round(first(longitude), 4),
              n = n(),
              value_p50 = median(value_std),
              dist_to_coast = round(first(dist_to_coast), 1),
              dist_to_fish_farm = round(first(dist_to_fish_farm), 1),
              n_class  = sum(classifiable %in% TRUE),
              n_ef     = sum(pristine_ef %in% TRUE),
              n_strict = sum(pristine_strict %in% TRUE),
              .groups = "drop") |>
    left_join(thr, by = c("symbol", "cat")) |>
    mutate(
      offshore  = !is.na(dist_to_coast) & dist_to_coast > 10,
      below_p90 = !is.na(p90_off) & value_p50 < p90_off,
      below_mix = !is.na(mix_thr) & mix_usable & value_p50 < mix_thr,
      # No Igeo for a withheld element. The Igeo step still computes a B for
      # molybdenum and selenium, but that B is cut from a distribution whose low
      # end was deleted, so an index built on it would be a number with no
      # meaning drawn on a map. Concentration is still shown.
      igeo      = ifelse(is.na(bg_median) | bg_median <= 0 |
                           symbol %in% withheld, NA_real_,
                         round(refined_igeo(value_p50, bg_median), 3)),
      value_p50 = signif(value_p50, 4),
      # the strictest class a majority of the site's classifiable measurements meet.
      # `pristine_ef` is NA off the aluminium-controlled fraction, so `ef` cannot
      # arise on a sieved map: the fraction that has no EF cannot be labelled with
      # one, and that is enforced here by the data rather than by a caption.
      pristine_class = case_when(
        n_class == 0             ~ "unclassified",
        2 * n_strict > n_class   ~ "strict",
        2 * n_ef     > n_class   ~ "ef",
        TRUE                     ~ "not")) |>
    # a group with no verdict carries no class at all, which is not the same as a
    # site that could not be classified. Iodine's sieved fraction would pass the
    # concentration criteria, but its background sits under the reporting
    # threshold, so there is nothing there to be pristine against.
    left_join(elements |> select(symbol, cat, has_verdict, gs_control, normalisable),
              by = c("symbol", "cat")) |>
    mutate(pristine_class = if_else(has_verdict, pristine_class, NA_character_),
           verdict_basis = case_when(
             !has_verdict                    ~ NA_character_,
             gs_control == "aluminium" & normalisable ~ "ef",
             TRUE                            ~ "conservative")) |>
    select(symbol, cat, site_id, latitude, longitude, n, value_p50, igeo,
           dist_to_coast, dist_to_fish_farm, offshore, below_p90, below_mix,
           n_class, n_ef, n_strict, pristine_class, verdict_basis) |>
    mutate(symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS), site_id)

  # A 0.1 degree grid (roughly 11 km) over the same points. This is what the site
  # actually draws: 20 000 overlapping site markers is not a summary, and at this
  # resolution a reader sees the regional picture the page is claiming. The
  # site-level file above stays published for anyone who wants the finer layer.
  map_grid <- map_sites |>
    mutate(lat = round(latitude, 1), lon = round(longitude, 1)) |>
    group_by(symbol, cat, lat, lon) |>
    summarise(n_sites = n(),
              n = sum(n),
              value_p50 = signif(median(value_p50), 4),
              igeo_p50 = round(median(igeo, na.rm = TRUE), 3),
              pct_below_p90 = round(100 * mean(below_p90), 1),
              pct_offshore = round(100 * mean(offshore), 1),
              dist_to_fish_farm = round(median(dist_to_fish_farm, na.rm = TRUE), 1),
              # sites, not measurements, because the map draws sites. `strict` is a
              # subset of `ef`, so the EF count includes it.
              n_sites_class  = sum(pristine_class %in% c("strict", "ef", "not")),
              n_sites_strict = sum(pristine_class %in% "strict"),
              n_sites_ef     = sum(pristine_class %in% c("strict", "ef")),
              verdict_basis  = dplyr::first(verdict_basis),
              .groups = "drop") |>
    mutate(pristine_class = case_when(
             is.na(verdict_basis)                ~ NA_character_,
             n_sites_class == 0                  ~ "unclassified",
             2 * n_sites_strict > n_sites_class  ~ "strict",
             2 * n_sites_ef     > n_sites_class  ~ "ef",
             TRUE                                ~ "not"),
           igeo_p50 = ifelse(is.finite(igeo_p50), igeo_p50, NA_real_),
           dist_to_fish_farm = ifelse(is.finite(dist_to_fish_farm),
                                      dist_to_fish_farm, NA_real_),
           symbol = factor(symbol, levels = elem_levels)) |>
    arrange(symbol, match(cat, CATS), lat, lon)

  # ── 10. Provenance ───────────────────────────────────────────────────────────
  meta <- tibble(
    generated     = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    refined_db    = basename(db_path),
    db_modified   = format(file.info(db_path)$mtime, "%Y-%m-%d"),
    n_measurement = nrow(ext),
    n_sites       = n_distinct(ext$site_id),
    n_elements    = n_distinct(ext$symbol),
    min_n         = MIN_N,
    # D4's limit, so a page can say what "aluminium predicts it" means without
    # typing the number that decides it.
    al_r2_limit   = refined_r2_limit(),
    withheld      = paste(withheld, collapse = " "),
    source_module = "background")

  # ── 11. Write ────────────────────────────────────────────────────────────────
  wr <- function(x, f) { write_csv(x, file.path(adir, f), na = ""); invisible(x) }
  # What each fraction's offshore reference actually is, and which grain-size control
  # holds a background steady across seas. Both travel to the summary layer because the
  # sieved verdicts cannot be read honestly without them: the pages that carry the
  # caveat must read its numbers rather than restate them.
  reference <- pref |>
    transmute(cat, gs_control, n, lat_p50, depth_p50, top_seas,
              n_north, north_cut_deg, n_farm_near, farm_near_km,
              label = if_else(gs_control == "sieve",
                              "grain-size controlled by the sieve",
                              "grain-size controlled by aluminium"))
  sea_spread <- pspr |> transmute(symbol, cat, n_seas, n, fold_raw, fold_al)

  wr(elements,   "summary_elements.csv")
  wr(reference,  "summary_reference.csv")
  wr(sea_spread, "summary_sea_spread.csv")
  wr(bg_long,    "summary_background.csv")
  wr(verdicts,   "summary_verdicts.csv")
  wr(coverage,   "summary_coverage.csv")
  wr(censoring,  "summary_censoring.csv")
  wr(pressure,   "summary_pressure.csv")
  wr(gradient,   "summary_gradient.csv")
  wr(controls,   "summary_controls.csv")
  wr(sources,    "summary_sources.csv")
  wr(flow,       "summary_flow.csv")
  wr(map_sites,  "summary_map_sites.csv")
  wr(map_grid,   "summary_map_grid.csv")
  wr(meta,       "summary_meta.csv")

  if (verbose) {
    cat("\n== Summary assembly (refined) ==\n")
    cat("measurements:", nrow(ext), " sites:", n_distinct(ext$site_id), "\n")
    cat("full verdict for:",
        paste(unique(paste(elements$symbol, elements$cat)[elements$has_verdict]),
              collapse = ", "), "\n")
    cat("background only:",
        paste(unique(paste(elements$symbol, elements$cat)[
          elements$has_background & !elements$has_verdict]), collapse = ", "), "\n")
    cat("withheld:", paste(withheld, collapse = ", "), "\n")
    cat("map points:", nrow(map_sites), "sites,", nrow(map_grid), "grid cells\n")
    cat("written to:", adir, "\n")
  }

  invisible(list.files(adir, full.names = TRUE))
}
