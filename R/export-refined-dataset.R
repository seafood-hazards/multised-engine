# ── Export, refined generation: flat dataset ───────────────────────────────
# Converted from R/analysis/download/01_refined_dataset.R. The body is unchanged;
# only the hardcoded paths and the console output are parameterised.
#
# This denormalises rather than computing anything of its own, so it is reached
# through export_data("refined") rather than analyze_data(). The output directory
# stays <out_dir>/download/ because multised-refined's CI pre-render downloads the
# file from a release built off that path.
#
# It does carry the pristine and background verdicts, but it does not derive them:
# the thresholds come from the refined background analyses' CSVs, so the analyses
# must have been run first. See add_background_flags() at the foot of this file.

#' The rows both refined exports are built from
#'
#' Factored out so the flat dataset and the EFSA submission table cannot disagree
#' about scope, references or verdicts: they select different columns from one frame,
#' rather than each running its own pull. Carries more columns than the flat dataset
#' publishes; the EFSA table needs the method, the limits and the location names.
#'
#' @param analysis_dir The analysis root (NOT its `download/` subdirectory), because
#'   `add_background_flags()` reads the background module's CSVs from under it.
#' @noRd
refined_export_base <- function(db_dir = multised_db_dir(),
                                analysis_dir = multised_analysis_dir()) {
  con <- dbConnect(SQLite(), refined_db_path(db_dir))
  on.exit(dbDisconnect(con), add = TRUE)
  as_tibble(dbGetQuery(con, "
    SELECT m.source                    AS source,
           si.latitude                 AS latitude,
           si.longitude                AS longitude,
           si.country                  AS country,
           si.municipality             AS municipality,
           si.sea_name                 AS sea_name,
           e.year                      AS year,
           e.date                      AS date,
           sub.depth_from              AS depth_from_cm,
           sub.depth_to                AS depth_to_cm,
           m.symbol                    AS element,
           m.frac_class                AS frac_class,
           m.sieve_um_std              AS sieve_um_std,
           m.frac_basis                AS fraction_basis,
           m.value_std                 AS value_mgkg,
           m.value_sd                  AS value_sd,
           m.n_rep                     AS n_rep,
           m.ratio_al                  AS ratio_al,
           nz.al                       AS al_mgkg,
           nz.fe                       AS fe_mgkg,
           nz.corg                     AS corg_mgkg,
           sub.fines_lt63              AS fines_pct,
           si.dist_to_coast            AS dist_to_coast_km,
           si.dist_to_aquaculture      AS dist_to_aquaculture_km,
           si.dist_to_fish_farm        AS dist_to_fish_farm_km,
           si.fish_farm_mtb_t          AS fish_farm_mtb_t,
           si.fish_farm_band           AS fish_farm_band,
           d.pressure_class            AS pressure_class,
           m.outlier_flag              AS outlier_flag,
           me.method                   AS method,
           me.lod                      AS lod,
           me.loq                      AS loq,
           me.limit_unit               AS limit_unit,
           me.extraction               AS extraction,
           me.extraction_class         AS extraction_class,
           me.accredited               AS accredited
    FROM measurement m
      JOIN subsample sub ON sub.subsample_id = m.subsample_id
      JOIN event e       ON e.event_id       = sub.event_id
      JOIN site si       ON si.site_id       = e.site_id
      -- dataset_id is unique in `dataset`, so this is 1:1 and adds no rows. It is
      -- here for pressure_class, which only Vannmiljo populates.
      JOIN dataset d     ON d.dataset_id     = e.dataset_id
      LEFT JOIN normaliser nz
             ON nz.subsample_id = m.subsample_id
            AND nz.frac_class   = m.frac_class
      -- method_id is unique in `method` and populated on every measurement, so this
      -- is 1:1 and cannot fan the rows out the way the normaliser join once did.
      LEFT JOIN method me ON me.method_id = m.method_id")) |>
    # a single readable fraction token (bulk / sieved63 / sieved20 / ...)
    mutate(fraction = if_else(frac_class == "bulk", "bulk",
                              paste0("sieved", as.integer(sieve_um_std)))) |>
    add_background_flags(out_dir = analysis_dir)
}

export_refined_dataset <- function(db_dir = multised_db_dir(),
                                     out_dir = multised_analysis_dir(),
                                     verbose = TRUE) {
  # ── Analysis stage, downloadable flat dataset (REFINED database) ──────────────
  # A single denormalised table for external users who want to try their own
  # background / enrichment methods, without needing the full relational database.
  # It keeps only the values those analyses actually need: location, sampling
  # metadata (source, year, depth), the target concentration, the Fe/Al/organic
  # normalisers and grain-size fines, and the two distances (coast, aquaculture).
  # Everything else (surrogate keys, provenance, uncertainty, method detail) is
  # dropped. One row per target measurement.
  #
  # Output -> data/analysis/download/ (gitignored):
  #   multised_refined_dataset.tsv.gz   the flat dataset (tab-separated, gzip)
  #   refined_dataset_dictionary.csv    column -> description (drives the site page)

  out_dir_root <- out_dir
  out_dir <- file.path(out_dir, "download")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull and denormalise ──────────────────────────────────────────────────
  # Shared with the EFSA submission table; see refined_export_base() above. The
  # verdicts are not stored in the database: they are the refined background
  # analyses' own output, and the reference values live in their CSVs. Joining them
  # there is what keeps this file agreeing with the site's Background and Pristine
  # Classification pages, rather than re-deriving thresholds that would drift.
  df <- refined_export_base(db_dir = db_dir, analysis_dir = out_dir_root)

  df <- df |>
    select(source, latitude, longitude, year, depth_from_cm, depth_to_cm,
           element, fraction, fraction_basis, value_mgkg, al_mgkg, fe_mgkg, corg_mgkg,
           fines_pct, dist_to_coast_km, dist_to_aquaculture_km,
           dist_to_fish_farm_km, fish_farm_mtb_t, fish_farm_band, pressure_class,
           outlier_flag,
           extraction, extraction_class, accredited,
           al_basis, ef, ef_p90ref, classifiable, pristine_ef, pristine_ef_p90ref,
           pristine_strict,
           background_p90, background_mixture,
           igeo, igeo_class,
           bg_ratio_al, bg_ratio_al_p90, p90_off, mixture_threshold,
           igeo_background) |>
    arrange(element, fraction, source, latitude, longitude)

  # ── 2. Write the gzipped TSV ──────────────────────────────────────────────────
  tsv_path <- file.path(out_dir, "multised_refined_dataset.tsv.gz")
  write_tsv(df, tsv_path, na = "")

  # ── 3. Column dictionary (drives the Dataset Download page) ───────────────────
  dict <- tribble(
    ~column,                   ~unit,        ~description,
    "source",                  "",           "Original data source the measurement came from (Mareano, Vannmiljo, ICES-DOME, MUDAB, 4Demon).",
    "latitude",                "deg",        "Site latitude, decimal degrees (WGS84), rounded to 3 dp.",
    "longitude",               "deg",        "Site longitude, decimal degrees (WGS84), rounded to 3 dp.",
    "year",                    "",           "Sampling year.",
    "depth_from_cm",           "cm",         "Top of the sediment layer sampled (0 = surface).",
    "depth_to_cm",             "cm",         "Bottom of the sediment layer sampled.",
    "element",                 "",           "Target element symbol: CO, CU, I, MN, MO, SE, ZN.",
    "fraction",                "",           "Sediment fraction: bulk (whole sample) or sieved<n> (< n micrometre sieve cutoff, e.g. sieved63, sieved20).",
    "fraction_basis",          "",           "Where the fraction label comes from: reported (the source stated the sieve, or stated that none was used) or assumed (the source was silent and bulk was inferred). Roughly three fifths of bulk rows are assumed, so a reader treating bulk as a measured property should filter on this.",
    "value_mgkg",              "mg/kg",      "Standardised element concentration (dry weight), the value all analyses use.",
    "al_mgkg",                 "mg/kg",      "Aluminium concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
    "fe_mgkg",                 "mg/kg",      "Iron concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
    "corg_mgkg",               "mg/kg",      "Organic carbon concentration for the same subsample and fraction (organic normaliser); empty if not measured.",
    "fines_pct",               "%",          "Percentage of material finer than 63 micrometre (the mud fraction, clay + silt); empty if no grain size.",
    "dist_to_coast_km",        "km",         "Great-circle distance from the site to the nearest coastline.",
    "dist_to_aquaculture_km",  "km",         "Distance to the nearest marine aquaculture farm (Norway only; empty elsewhere).",
    "dist_to_fish_farm_km",    "km",         "Distance to the nearest marine FISH farm, the subset of aquaculture that grows finfish in sea or offshore cages. dist_to_aquaculture_km counts every marine site including shellfish and land-based ones, so this is the column to use for a feed-related pressure (Norway only; empty elsewhere).",
    "fish_farm_mtb_t",         "t",          "Licensed maximum permitted standing biomass (MTB) of that nearest fish farm, in tonnes. The regulator licenses capacity, not stock, so this is the ceiling rather than what was in the water when the sediment was sampled.",
    "fish_farm_band",          "",           "Size band of that nearest fish farm, in standard concessions of 780 t MTB: small (<= 2), medium (<= 4), large (> 4). Banding rather than raw tonnage because licences are issued in concession units and the raw figure is not comparable across licence types.",
    "pressure_class",          "",           "Why the sample was taken, as the data provider itself files it: aquaculture (fish-farm monitoring), pressure (a named or presumed pressure), reference (deliberately unpressured), survey (status or mapping work), unknown (the provider's own residual category). Vannmiljo only; the other four sources do not record a programme, so the column is empty for them. This is stated evidence, independent of the geometric proxies and of EF.",
    "outlier_flag",            "",           "Distributional outlier marker (high / low); empty = kept. The analyses exclude flagged rows.",
    "extraction",              "",           "Digestion chemistry used to liberate the metal, as an ICES METCX code (AQR = aqua regia, HNO = nitric acid, HF-CB = HF total digestion, NON = no extraction, UNK = not reported).",
    "accredited",              "",           "Whether the analysing laboratory was accredited, as the source states it: yes, partly (the lab holds accreditation but not for every parameter), no. Empty where the source does not say, which is ICES-DOME, Vannmiljo and 4Demon entirely.",
    "extraction_class",        "",           "EFSA extraction class derived from the code: 1 = strong (aqua regia or strong acid digestion, aimed at total recovery), 2 = milder (nitric acid, with or without peroxide), 3 = weak or none (no extraction, or not reported). Only ICES-DOME, MUDAB and Mareano record the digestion; Vannmiljo and 4Demon do not, so they are all class 3.",
    "ef",                      "",           "Enrichment factor: (element/Al) divided by the offshore background (element/Al) for the same element and fraction. EF < 1 means at or below background. Empty where aluminium is missing, where the sample is off its fraction's aluminium basis, or where aluminium does not predict that element (see the row on which groups get an ef).",
    "classifiable",            "",           "TRUE where an EF could be computed, so a pristine verdict exists. FALSE otherwise; the two pristine columns are then empty.",
    "pristine_ef",             "",           "Pristine under the permissive rule: EF < 1. Empty where not classifiable.",
    "pristine_strict",         "",           "Pristine under the conservative rule: EF < 1 AND below the mixture threshold AND below the offshore P90. Empty where not classifiable.",
    "background_p90",          "",           "TRUE where the concentration is below the offshore P90 for its element and fraction (the Global Background definition). Not grain-size controlled.",
    "background_mixture",      "",           "TRUE where the concentration is below the distribution-mixture threshold separating the background from the enriched population. Not grain-size controlled.",
    "igeo",                    "",           "Geo-accumulation index: log2(concentration / (1.5 * local background)), where the local background is the offshore (> 10 km) median for the same element and fraction. Uses no aluminium, so it is present on about 97% of rows, against 10% for ef. Empty for selenium and molybdenum on the same grounds as their other verdicts: a background censored at the LOQ is in the denominator. It is NOT a verdict and is not part of pristine_ef: in bulk it correlates with grain size strongly enough (cobalt rho 0.70) that a verdict built on it would be partly a verdict about texture. Read it beside ef, not instead of it.",
    "igeo_class",              "",           "Muller class of igeo: 0 unpolluted (<= 0) through 6 extreme (> 5). The boundaries are Muller's and are kept because they are recognisable, but the meaning is not: here class 2 is above the LOCAL offshore median, not above the continental crust.",
    "al_basis",                "",           "Inferred aluminium measurement basis for this subsample, from Fe/Al: 'total', 'extraction' (acid-leachable, which under-reports Al), or 'unplaced' where iron was not measured. Only samples on the basis their fraction adopted (bulk: extraction; sieved: total) receive an ef and a pristine verdict; see the Enrichment Factor page.",
    "(no column: Se and Mo)",  "",           "Selenium and molybdenum carry no ef, pristine or background verdict at all: over half their measurements (Se 68.6%, Mo 52.2%) were below the limit of quantification and removed upstream, so what survives is an upper tail rather than a background. Their concentrations are published; only the verdicts are withheld.",
    "(no column: which groups get an ef)", "", "ef and the pristine columns exist only for cobalt, copper and zinc in the BULK fraction. Aluminium predicts those three (R-squared 0.46-0.58) and predicts nothing else: manganese, molybdenum and selenium in bulk, and every sieved fraction of every element, sit at 0.10 or below, so metal/Al there is not a grain-size control. Concentrations, and the non-normalised background_p90 and background_mixture verdicts, are published for every group as before.",
    "ef_p90ref",               "",           "The same enrichment factor against the second reference: the offshore 90th percentile of element/Al rather than its median. A larger denominator, so more permissive, and it makes ef < 1 mean 'below the offshore P90', which is how background_p90 and the Global Background page define background. Reported beside ef so the spread between the two references is visible.",
    "pristine_ef_p90ref",      "",           "TRUE where ef_p90ref < 1. The permissive rule read against the second reference; pristine_ef keeps its original definition so an earlier download stays a subset of this one.",
    "bg_ratio_al",             "",           "Reference used for ef: the offshore background element/Al ratio for this element and fraction, computed within the adopted aluminium basis.",
    "bg_ratio_al_p90",         "",           "Reference used for ef_p90ref: the offshore 90th percentile of element/Al for this element and fraction, computed within the adopted aluminium basis.",
    "p90_off",                 "mg/kg",      "Reference used for background_p90: the offshore P90 concentration for this element and fraction.",
    "mixture_threshold",       "mg/kg",      "Reference used for background_mixture: the mixture-model threshold for this element and fraction.",
    "igeo_background",         "mg/kg",      "Reference used for igeo: the offshore median concentration for this element and fraction. Empty where no igeo was computed, which is where fewer than 30 offshore samples back the reference (iodine in every fraction, selenium in sieved20).",
  )
  check_dictionary_covers(df, dict)
  write_csv(dict, file.path(out_dir, "refined_dataset_dictionary.csv"))

  if (verbose) {
    # ── 4. Console summary ────────────────────────────────────────────────────────
    cat("flat dataset written to", tsv_path, "\n")
    cat("rows:", nrow(df), " columns:", ncol(df), "\n")
    cat("size:", round(file.size(tsv_path) / 1024^2, 2), "MB\n\n")
    df |> count(element, fraction) |> pivot_wider(names_from = fraction, values_from = n, values_fill = 0) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nverdicts (share of all rows):\n")
    cat("  classifiable      ", sprintf("%5.1f%%", 100 * mean(df$classifiable)), "\n")
    for (v in c("pristine_ef", "pristine_strict", "background_p90", "background_mixture"))
      cat(sprintf("  %-18s %5.1f%% of the %s rows that carry a verdict\n",
                  v, 100 * mean(df[[v]], na.rm = TRUE),
                  format(sum(!is.na(df[[v]])), big.mark = ",")))
  }

  invisible(out_dir)
}


# ── Pristine / background verdicts ────────────────────────────────────────────
# Joins the reference values published by the refined background analyses onto the
# flat rows and applies the same rules, so the dataset and the site agree by
# construction. `out_dir` is the analysis root, not the download subdirectory.
#
# Scope matches the analyses: fractions bulk / sieved63 / sieved20, outliers
# dropped, non-positive values dropped. Rows outside it get empty verdicts rather
# than verdicts computed on a different basis from the published ones.
add_background_flags <- function(df, out_dir) {
  adir <- file.path(out_dir, "background")
  CATS <- c("bulk", "sieved63", "sieved20")

  need <- c(bg  = "refined_ef_background.csv",       # 04, the EF background ratio
            off = "refined_background_compare.csv",  # 01, the offshore P90
            mix = "refined_mixture_components.csv",  # 05, the mixture threshold
            igb = "refined_igeo_background.csv")     # 10, the Igeo local background
  missing <- need[!file.exists(file.path(adir, need))]
  if (length(missing))
    stop("the refined background analyses have not been run, so the verdict ",
         "references are missing: ", paste(missing, collapse = ", "),
         " (looked under ", adir, "). Run analyze_data(\"refined\") first.",
         call. = FALSE)

  rd <- function(f, cols) read_csv(file.path(adir, f), show_col_types = FALSE) |>
    mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
    select(all_of(cols))

  ref <- rd(need[["bg"]],  c("symbol", "cat", "bg_ratio_al", "bg_ratio_al_p90")) |>
    full_join(rd(need[["off"]], c("symbol", "cat", "p90_off10")), by = c("symbol", "cat")) |>
    full_join(rd(need[["mix"]], c("symbol", "cat", "threshold", "usable")),
              by = c("symbol", "cat")) |>
    full_join(rd(need[["igb"]], c("symbol", "cat", "bg_median", "reliable")),
              by = c("symbol", "cat")) |>
    rename(element = symbol, fraction = cat,
           p90_off = p90_off10, mixture_threshold = threshold,
           mixture_usable = usable,
           igeo_background = bg_median, igeo_reliable = reliable)

  df |>
    left_join(ref, by = c("element", "fraction")) |>
    mutate(
      # over half of these elements' measurements were deleted below the LOQ, so their
      # background is an upper tail: no background or pristine verdict is published for
      # them. See inst/extdata/loq-censoring/README.md.
      withheld = element %in% refined_withheld_elements(),
      in_scope = fraction %in% CATS & is.na(outlier_flag) &
                 !is.na(value_mgkg) & value_mgkg > 0 & !withheld,
      # the verdicts are taken from the unrounded EF: rounding first would push
      # values just under 1 up to 1.000 and flip them out of pristine
      # the aluminium basis gate: a sample off its fraction's adopted basis, or with no Fe
      # to place it, gets no EF and so no pristine verdict, rather than being divided by a
      # reference from a different measurement basis. Same rule as the analyses, from
      # R/analysis-refined-shared-basis.R; the finding is in docs/ef-source-bias.md.
      al_basis = refined_al_basis(fe_mgkg, al_mgkg),
      on_al_basis = refined_on_basis(al_basis, fraction),
      # D4, the normalisability gate: metal/Al is only a grain-size control where
      # aluminium predicts the metal, which it does for CO/CU/ZN in bulk and nowhere
      # else. Those groups get no EF and so no pristine verdict. It gates ONLY the
      # aluminium-derived columns: background_p90 and background_mixture use no
      # aluminium and are unaffected. See inst/extdata/normalisability/README.md.
      normalisable = refined_normalisable(element, fraction),
      al_ok = in_scope & on_al_basis & normalisable,
      ef_raw = if_else(al_ok & !is.na(ratio_al) &
                         !is.na(bg_ratio_al) & bg_ratio_al > 0,
                       ratio_al / bg_ratio_al, NA_real_),
      classifiable    = !is.na(ef_raw),
      pristine_ef     = if_else(classifiable, ef_raw < 1, NA),
      # an unusable mixture threshold is not applied; see the Distribution-Mixture page
      mix_ok = case_when(is.na(mixture_usable) ~ NA,
                         !mixture_usable       ~ TRUE,
                         TRUE                  ~ value_mgkg < mixture_threshold),
      pristine_strict = if_else(classifiable,
                                (ef_raw < 1) & mix_ok & (value_mgkg < p90_off), NA),
      # 6 significant digits, not 3 decimals: at 3 dp an EF of 0.9996 prints as
      # 1.000 next to pristine_ef = TRUE, and a reader checking `ef < 1` gets a
      # different answer from the flag. Asserted below.
      ef = signif(ef_raw, 6),
      # the second reference from D1, reported beside the headline one. The existing ef /
      # pristine_ef columns keep their definition so an earlier download stays a subset.
      ef_p90ref_raw = if_else(al_ok & !is.na(ratio_al) &
                                !is.na(bg_ratio_al_p90) & bg_ratio_al_p90 > 0,
                              ratio_al / bg_ratio_al_p90, NA_real_),
      ef_p90ref = signif(ef_p90ref_raw, 6),
      pristine_ef_p90ref = if_else(!is.na(ef_p90ref_raw), ef_p90ref_raw < 1, NA),
      bg_ratio_al_p90 = if_else(al_ok, bg_ratio_al_p90, NA_real_),
      background_p90     = if_else(in_scope, value_mgkg < p90_off, NA),
      background_mixture = if_else(in_scope, value_mgkg < mixture_threshold, NA),
      # the references, blanked where they were not applied, so a row never shows a
      # threshold it was not judged against
      bg_ratio_al       = if_else(al_ok, bg_ratio_al, NA_real_),
      p90_off           = if_else(in_scope, p90_off, NA_real_),
      mixture_threshold = if_else(in_scope, mixture_threshold, NA_real_),
      # Igeo, background step 10. It uses no aluminium, so neither the basis gate nor
      # D4 applies to it -- that is the whole reason it is here, since it reaches most
      # of the rows EF cannot. Two gates remain. D1, through `in_scope`: the withheld
      # elements get no Igeo either, because a background censored at the LOQ sits in
      # the denominator. And the reference itself: a group whose offshore sample is
      # thinner than the step's minimum gets no Igeo, since the index would carry the
      # noise of its own denominator. That is the `reliable` flag the step wrote, read
      # here rather than recomputed, so this file and the site's Igeo page apply one
      # rule and not two.
      igeo_ok = in_scope & !is.na(igeo_reliable) & igeo_reliable,
      igeo = if_else(igeo_ok, refined_igeo(value_mgkg, igeo_background), NA_real_),
      igeo_class = if_else(igeo_ok, refined_igeo_class(igeo), NA_character_),
      igeo_background = if_else(igeo_ok, igeo_background, NA_real_)) |>
    select(-in_scope, -ef_raw, -ef_p90ref_raw, -on_al_basis, -mix_ok, -mixture_usable,
           -withheld, -normalisable, -al_ok, -igeo_ok, -igeo_reliable) |>
    check_ef_consistent()
}


# The published `ef` must never disagree with the flag derived from it, or the
# file contradicts itself for anyone applying their own cutoff.
check_ef_consistent <- function(df) {
  bad <- sum(!is.na(df$ef) & (df$ef < 1) != df$pristine_ef)
  if (bad > 0)
    stop("rounding `ef` flipped ", bad, " row(s) across the EF = 1 boundary, so ",
         "the column disagrees with pristine_ef. Increase the precision in ",
         "add_background_flags().", call. = FALSE)
  df
}


# The dictionary drives the site's Dataset Download page, so a column that reaches
# the file without a description reaches the reader without one too. Adding a column
# and forgetting its row is the obvious way for that to happen, so it is an error
# rather than a silent gap.
#
# The dictionary also carries rows whose `column` is a note in brackets rather than a
# column name -- what Se and Mo do not have, which groups get an EF. Those explain
# absences, so they have no column to match and are exempt.
check_dictionary_covers <- function(df, dict) {
  documented <- dict$column[!grepl("^\\(", dict$column)]
  undocumented <- setdiff(names(df), documented)
  orphaned    <- setdiff(documented, names(df))
  if (length(undocumented))
    stop("the export writes column(s) the dictionary does not describe: ",
         paste(undocumented, collapse = ", "),
         ". Add a row to `dict` in export_refined_dataset().", call. = FALSE)
  if (length(orphaned))
    stop("the dictionary describes column(s) the export no longer writes: ",
         paste(orphaned, collapse = ", "),
         ". Remove the row from `dict` in export_refined_dataset().", call. = FALSE)
  invisible(df)
}
