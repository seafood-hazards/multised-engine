# ── Package configuration ────────────────────────────────────────────────────
# The pipeline scripts were run from the project root and hardcoded relative
# paths like "./data/db/mareano_slim.sqlite". A package cannot assume a working
# directory, so the two data locations become arguments with a configurable
# default.

#' The five data sources
#'
#' Source keys accepted by [create_db()] for the per-source generations.
#'
#' @return A character vector of the five source keys.
#' @export
#' @examples
#' multised_sources()
multised_sources <- function() {
  c("mareano", "vannmiljo", "ices-dome", "mudab", "4demon")
}

#' Where the databases, outputs and tools live
#'
#' `multised_db_dir()` is the directory holding the SQLite databases,
#' `multised_analysis_dir()` the directory analysis outputs are written to,
#' `multised_raw_dir()` the vendor files the pilot stage parses, and
#' `multised_seastamp_dir()` the seastamp reference datasets (GSHHG, GEBCO, IHO,
#' Natural Earth, GISCO) the geo steps need. All default to the layout used by
#' the project itself and can be overridden globally with [options()], or per
#' call via the `db_dir` and `seastamp_dir` arguments of [create_db()].
#'
#' `multised_seastamp_bin()` resolves the seastamp executable, checking
#' `getOption("multised.seastamp_bin")`, then `Sys.getenv("SEASTAMP_BIN")`, then
#' the `PATH`. Unlike the others it errors when nothing is found, since a
#' missing tool cannot be defaulted. Prefer the option or the environment
#' variable in RStudio: its console does not inherit the login shell's `PATH`,
#' so a binary the Terminal tab finds may still be invisible to the console.
#'
#' @return A length-one character path.
#' @export
#' @examples
#' multised_db_dir()
#'
#' \dontrun{
#' options(multised.db_dir = "~/sediment/db")
#' }
multised_db_dir <- function() {
  getOption("multised.db_dir", "data/db")
}

#' @rdname multised_db_dir
#' @export
multised_analysis_dir <- function() {
  getOption("multised.analysis_dir", "data/analysis")
}

#' @rdname multised_db_dir
#' @export
multised_raw_dir <- function() {
  getOption("multised.raw_dir", "data/raw")
}

#' @rdname multised_db_dir
#' @export
multised_seastamp_dir <- function() {
  getOption("multised.seastamp_dir", "data/seastamp")
}

# Source key -> database filename stem. The keys keep the hyphen used throughout
# the documentation ("ices-dome"), while the database files use an underscore.
source_stem <- function(source) {
  gsub("-", "_", source, fixed = TRUE)
}

# Validate a source key, with a message that lists the valid ones.
check_source <- function(source) {
  if (is.null(source) || length(source) != 1L || !is.character(source)) {
    stop("`source` must be a single source key, one of: ",
         paste(multised_sources(), collapse = ", "), call. = FALSE)
  }
  if (!source %in% multised_sources()) {
    stop("Unknown source ", sQuote(source), ". Valid sources: ",
         paste(multised_sources(), collapse = ", "), call. = FALSE)
  }
  source
}

# Column names used unquoted by dplyr inside the pipeline bodies. They are not
# undefined globals, but R CMD check cannot tell, so declare them here. The list
# is generated from the check output; regenerate it when a step is added.
utils::globalVariables(c(
  "1-5km", "5-20km", "<1km", ">20km", "accessed", "accreditation",
  "activity_id", "activity_name", "AL", "Al", "al", "al_exist", "al_mgkg",
  "ALABO", "analysis", "analysis_id", "analysis_method",
  "analysis_method_id", "analytical_laboratory",
  "analytical_laboratory_description", "anchor", "anom", "aq_bin", "aqua_id",
  "archive", "Area", "As", "axis", "B", "Ba", "bad_depth", "band", "basis",
  "batch_id", "bathymetry", "Be", "below_lld", "below_loq", "below_loq_num",
  "best_pref", "bg_ratio_al", "bin", "bulk", "bulk_multi", "bulk_single",
  "Ca", "CaCO3", "campaign_code", "cas", "cas_no", "cas_number", "category",
  "Category name", "category_code", "category_name", "Catogory", "Cd", "Ce",
  "cell", "chem", "chemical_treatment", "classifiable", "Clay", "clean_n",
  "clean_total", "client", "client_id", "cluster", "Co", "Code", "code",
  "Code name", "code_name", "CodeType", "Comment", "comp_exist", "constant",
  "contractor", "contractor_id", "control_chart_type", "core_id",
  "core_layers", "core_median", "core_name", "CORG", "corg", "corg_mgkg",
  "corg_pct", "corrected_value", "country", "country_code", "Cr",
  "cruise_id", "cruise_no", "cruise_no2", "cruise_type", "Cu", "cutoff",
  "data_col", "data_qualifier", "dataset_code", "dataset_group",
  "dataset_id", "dataset_name", "date_orig", "dcflag", "dde", "DDE degrees",
  "ddn", "DDN degrees", "deep", "denom", "depth", "depth_from",
  "depth_from_cm", "depth_range", "depth_to", "depth_to_cm", "Description",
  "description", "description_raw", "det_limit_flag", "direction",
  "discipline", "disposition", "dist_chk", "dist_to_aquaculture",
  "dist_to_aquaculture_km", "dist_to_coast", "dist_to_coast_km", "dup",
  "dup_flag", "dup_superseded_by", "E", "EF", "ef", "ef_p50", "ef_p90",
  "element", "element_name", "end", "end_day", "end_month", "end_year",
  "english", "enough", "enrich_near", "est_country", "event_id",
  "expanded_uncertainty_pct", "FE", "Fe", "fe", "fe_exist", "fe_mgkg",
  "feature", "few", "filtered", "final_total", "fines_lt63", "fines_pct",
  "flag", "fold_vs_med", "frac", "frac_class", "frac_declining",
  "frac_rising", "fraction", "fraction_range_um", "from.date", "gear_code",
  "geo_km", "german", "gkey", "gm_bg", "group", "group_code",
  "group_description", "group_median", "gs_corr", "gsf_id", "GSMF2",
  "GSMF2_63", "half", "has_uncrt", "has_year", "Hg", "hi", "hi_oom0.75",
  "hi_oom1.0", "hi_um", "high", "hotspot_id", "institute", "intercept",
  "internal_qa_count", "internal_qa_detection_limit",
  "internal_qa_quantification_limit", "invalid_gs", "is_chem", "is_filtered",
  "is_lld", "K", "k", "k_chosen", "La", "lab", "lab_name", "label", "labo",
  "lat", "lat3", "lat_r", "latitude", "lawa_code", "layer_lower_boundary",
  "layer_upper_boundary", "Leire", "Li", "limit", "limit_flag", "lld",
  "lld_id", "lo", "lo_oom0.75", "lo_oom1.0", "lo_um", "lod", "lod_id",
  "logv", "lon", "lon3", "lon_r", "Longitude", "longitude", "loq",
  "loser_source", "low", "lower_depth", "lval", "mad_log", "mar_value",
  "matrix_code", "MATRX", "max_value", "mbsl", "mbsl m", "mean_sil",
  "measure", "measured_value", "measurement_basis", "measurement_date",
  "measurement_depth", "measurement_end", "measurement_id",
  "measurement_method_code", "measurement_project", "measurement_start",
  "measurement_time", "measurement_time_id", "med_log", "med_rel_pct",
  "med_value", "median_bulk", "median_n_cell", "median_rho", "median_s20",
  "median_s63", "median_span", "median_val", "median_value", "merged_n",
  "merged_rows", "metcu", "metcx", "method", "method1", "method2",
  "method_code", "method_description", "method_id", "method_seq_no", "metoa",
  "metps", "metpt", "metric", "metst", "Mg", "mid_depth", "min_rel", "Mn",
  "Mo", "monitoring_station_name", "monotone", "month", "municipality", "N",
  "n", "n_bg", "n_cells", "n_class", "n_classifiable", "n_cores",
  "n_distinct_rel", "n_global", "n_high", "n_layers", "n_low", "n_off",
  "n_off10", "n_rep", "n_sites", "n_values", "n_years", "Na", "Name", "name",
  "name_ices", "name_src", "new", "new_unit", "ngu_id", "Ni", "norm_val",
  "normaliser", "ny", "nyear", "oom", "operator", "org_exist",
  "organisation", "other", "outlier_extreme_flag", "outlier_flag",
  "outlier_stdev_flag", "P", "P2301_NGU ID", "p25", "p25_rel_pct", "p50",
  "p75", "p75_rel_pct", "p90", "p90_global", "p90_off", "p90_off10",
  "p_sign", "PARAM", "param", "param_description", "param_id", "param_name",
  "parameter", "parameter_group", "parameter_name", "PARGROUP", "Pb",
  "pct_bg", "pct_classifiable", "pct_ef", "pct_gt5", "pct_lt1",
  "pct_pristine", "pct_strict", "physical_treatment", "platform_type",
  "pref", "prio", "pristine_ef", "pristine_strict", "proficiency_testing",
  "project", "project_affiliation", "project_id", "project_survey_id",
  "purpose", "qflag", "r", "r2", "range_check_flag", "range_flag", "ratio",
  "ratio_AL", "ratio_al", "ratio_FE", "ratio_fe", "raw_code",
  "recovery_rate", "ref", "ref_description", "ref_id",
  "reference_material_basis", "reference_material_code",
  "reference_material_id", "reference_material_mean",
  "reference_material_sd", "reference_material_type", "refined_rows",
  "region", "rel", "rel_diff", "rel_gap", "rel_median_pct", "rel_pct",
  "reliable", "repeat_group", "replicate_number", "responsible_institute",
  "retained_pct", "rho", "RLABO", "robust_z", "rows", "rule", "S", "s20",
  "s63", "Sample batch ID", "Sample core ID", "Sample Depth", "Sample ID",
  "Sample interval (top-bottom) from cm",
  "Sample interval (top-bottom) to cm", "sample_date", "sample_depth",
  "sample_id", "sample_id2", "sample_method", "sample_no", "sample_ref_code",
  "sample_seq_no", "sample_time", "sample_timestamp", "sample_type",
  "sample_type_description", "sampled_area", "Sampling tool",
  "sampling_method", "sampling_tool", "SamplingTool serial ID", "Sand", "Sc",
  "Se", "sea_area", "sea_name", "season", "sediment_composition",
  "sediment_content", "sediment_no", "separated", "seq_number", "shift_p90",
  "Si", "sieve_class", "sieve_key", "sieve_um", "sieve_um_std", "sieved",
  "sieved20", "sieved20_multi", "sieved20_single", "sieved63",
  "sieved63_multi", "sieved63_single", "Silt", "site_code", "site_id",
  "site_name", "Slam", "slope", "slope_log10", "Source", "span", "Sr",
  "src_flag", "start", "start_date", "start_day", "start_month",
  "start_year", "Stasjon", "Stasjon_kort", "station", "Station number",
  "station_code", "station_group", "station_id", "station_latitude",
  "station_longitude", "station_name", "station_no", "station_type", "stem",
  "strict", "stripped", "sub_no", "subsample_id", "surf", "survey_end",
  "survey_id", "survey_seq_no", "survey_start", "sym", "symbol", "t_out",
  "t_rng", "t_std", "t_val", "TC", "thr_hi", "thr_lo", "threshold", "Ti",
  "to.date", "TOC", "tool_id", "total", "TS", "type", "uncertainty_method",
  "uncrt", "unit", "unit2", "unit_std", "upper_depth", "utm33_x", "utm33_y",
  "V", "v", "val", "Value", "value", "value_analysis", "value_flag",
  "value_mgkg", "value_pct", "value_sd", "value_std", "value_std_corr",
  "value_uncrt", "variable", "vessel_code", "vessel_name", "vflag",
  "Water Depth", "water_body_category", "weight_basis", "winner_source",
  "wss", "x", "Y", "Zn", "Zr"
))
