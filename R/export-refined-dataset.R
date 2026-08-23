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

  db_path <- refined_db_path(db_dir)
  out_dir <- file.path(out_dir, "download")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Pull and denormalise ──────────────────────────────────────────────────
  con <- dbConnect(SQLite(), db_path)
  df <- as_tibble(dbGetQuery(con, "
    SELECT m.source                    AS source,
           si.latitude                 AS latitude,
           si.longitude                AS longitude,
           e.year                      AS year,
           sub.depth_from              AS depth_from_cm,
           sub.depth_to                AS depth_to_cm,
           m.symbol                    AS element,
           m.frac_class                AS frac_class,
           m.sieve_um_std              AS sieve_um_std,
           m.value_std                 AS value_mgkg,
           m.ratio_al                  AS ratio_al,
           nz.al                       AS al_mgkg,
           nz.fe                       AS fe_mgkg,
           nz.corg                     AS corg_mgkg,
           sub.fines_lt63              AS fines_pct,
           si.dist_to_coast            AS dist_to_coast_km,
           si.dist_to_aquaculture      AS dist_to_aquaculture_km,
           m.outlier_flag              AS outlier_flag
    FROM measurement m
      JOIN subsample sub ON sub.subsample_id = m.subsample_id
      JOIN event e       ON e.event_id       = sub.event_id
      JOIN site si       ON si.site_id       = e.site_id
      LEFT JOIN normaliser nz
             ON nz.subsample_id = m.subsample_id
            AND nz.frac_class   = m.frac_class")) |>
    # a single readable fraction token (bulk / sieved63 / sieved20 / ...)
    mutate(fraction = if_else(frac_class == "bulk", "bulk",
                              paste0("sieved", as.integer(sieve_um_std))))
  dbDisconnect(con)

  # ── 1b. Background references and the pristine / background verdicts ──────────
  # The verdicts are not stored in the database: they are the refined background
  # analyses' own output, and the reference values live in their CSVs. Joining them
  # here is what keeps this file agreeing with the site's Background and Pristine
  # Classification pages, rather than re-deriving thresholds that would drift.
  df <- add_background_flags(df, out_dir = dirname(out_dir))

  df <- df |>
    select(source, latitude, longitude, year, depth_from_cm, depth_to_cm,
           element, fraction, value_mgkg, al_mgkg, fe_mgkg, corg_mgkg,
           fines_pct, dist_to_coast_km, dist_to_aquaculture_km, outlier_flag,
           ef, classifiable, pristine_ef, pristine_strict,
           background_p90, background_mixture,
           bg_ratio_al, p90_off, mixture_threshold) |>
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
    "value_mgkg",              "mg/kg",      "Standardised element concentration (dry weight), the value all analyses use.",
    "al_mgkg",                 "mg/kg",      "Aluminium concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
    "fe_mgkg",                 "mg/kg",      "Iron concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
    "corg_mgkg",               "mg/kg",      "Organic carbon concentration for the same subsample and fraction (organic normaliser); empty if not measured.",
    "fines_pct",               "%",          "Percentage of material finer than 63 micrometre (the mud fraction, clay + silt); empty if no grain size.",
    "dist_to_coast_km",        "km",         "Great-circle distance from the site to the nearest coastline.",
    "dist_to_aquaculture_km",  "km",         "Distance to the nearest marine aquaculture farm (Norway only; empty elsewhere).",
    "outlier_flag",            "",           "Distributional outlier marker (high / low); empty = kept. The analyses exclude flagged rows.",
    "ef",                      "",           "Enrichment factor: (element/Al) divided by the offshore background (element/Al) for the same element and fraction. EF < 1 means at or below background. Empty where aluminium is missing.",
    "classifiable",            "",           "TRUE where an EF could be computed, so a pristine verdict exists. FALSE otherwise; the two pristine columns are then empty.",
    "pristine_ef",             "",           "Pristine under the permissive rule: EF < 1. Empty where not classifiable.",
    "pristine_strict",         "",           "Pristine under the conservative rule: EF < 1 AND below the mixture threshold AND below the offshore P90. Empty where not classifiable.",
    "background_p90",          "",           "TRUE where the concentration is below the offshore P90 for its element and fraction (the Global Background definition). Not grain-size controlled.",
    "background_mixture",      "",           "TRUE where the concentration is below the distribution-mixture threshold separating the background from the enriched population. Not grain-size controlled.",
    "al_basis",                "",           "Inferred aluminium measurement basis for this subsample, from Fe/Al: 'total', 'extraction' (acid-leachable, which under-reports Al), or 'unplaced' where iron was not measured. Only samples on the basis their fraction adopted (bulk: extraction; sieved: total) receive an ef and a pristine verdict; see the Enrichment Factor page.",
    "(withheld elements)",     "",           "Selenium and molybdenum carry no ef, pristine or background verdict at all: over half their measurements (Se 68.6%, Mo 52.2%) were below the limit of quantification and removed upstream, so what survives is an upper tail rather than a background. Their concentrations are published; only the verdicts are withheld.",
    "bg_ratio_al",             "",           "Reference used for ef: the offshore background element/Al ratio for this element and fraction, computed within the adopted aluminium basis.",
    "p90_off",                 "mg/kg",      "Reference used for background_p90: the offshore P90 concentration for this element and fraction.",
    "mixture_threshold",       "mg/kg",      "Reference used for background_mixture: the mixture-model threshold for this element and fraction."
  )
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
            mix = "refined_mixture_components.csv")  # 05, the mixture threshold
  missing <- need[!file.exists(file.path(adir, need))]
  if (length(missing))
    stop("the refined background analyses have not been run, so the verdict ",
         "references are missing: ", paste(missing, collapse = ", "),
         " (looked under ", adir, "). Run analyze_data(\"refined\") first.",
         call. = FALSE)

  rd <- function(f, cols) read_csv(file.path(adir, f), show_col_types = FALSE) |>
    mutate(symbol = as.character(symbol), cat = as.character(cat)) |>
    select(all_of(cols))

  ref <- rd(need[["bg"]],  c("symbol", "cat", "bg_ratio_al")) |>
    full_join(rd(need[["off"]], c("symbol", "cat", "p90_off10")), by = c("symbol", "cat")) |>
    full_join(rd(need[["mix"]], c("symbol", "cat", "threshold", "usable")),
              by = c("symbol", "cat")) |>
    rename(element = symbol, fraction = cat,
           p90_off = p90_off10, mixture_threshold = threshold,
           mixture_usable = usable)

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
      ef_raw = if_else(in_scope & on_al_basis & !is.na(ratio_al) &
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
      background_p90     = if_else(in_scope, value_mgkg < p90_off, NA),
      background_mixture = if_else(in_scope, value_mgkg < mixture_threshold, NA),
      # the references, blanked where they were not applied, so a row never shows a
      # threshold it was not judged against
      bg_ratio_al       = if_else(in_scope & on_al_basis, bg_ratio_al, NA_real_),
      p90_off           = if_else(in_scope, p90_off, NA_real_),
      mixture_threshold = if_else(in_scope, mixture_threshold, NA_real_)) |>
    select(-in_scope, -ef_raw, -on_al_basis, -mix_ok, -mixture_usable, -withheld) |>
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
