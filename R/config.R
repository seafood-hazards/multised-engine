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

#' Where the databases and analysis outputs live
#'
#' `multised_db_dir()` is the directory holding the SQLite databases, and
#' `multised_analysis_dir()` the directory analysis outputs are written to, and
#' `multised_raw_dir()` the vendor files the pilot stage parses. All
#' default to the layout used by the project itself and can be overridden
#' globally with [options()], or per call via the `db_dir` argument of
#' [create_db()].
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
  "accessed", "accreditation", "activity_id", "activity_name", "Al", "al",
  "ALABO", "analysis", "analysis_id", "analysis_method",
  "analysis_method_id", "analytical_laboratory",
  "analytical_laboratory_description", "anchor", "aqua_id", "archive",
  "Area", "As", "B", "Ba", "bad_depth", "basis", "batch_id", "bathymetry",
  "Be", "below_lld", "below_loq", "below_loq_num", "best_pref", "bin", "Ca",
  "CaCO3", "campaign_code", "cas", "cas_no", "cas_number", "category",
  "Category name", "category_code", "category_name", "Catogory", "Cd", "Ce",
  "chemical_treatment", "Clay", "clean_n", "clean_total", "client",
  "client_id", "cluster", "Co", "Code", "code", "Code name", "code_name",
  "CodeType", "Comment", "contractor", "contractor_id", "control_chart_type",
  "core_id", "core_name", "corg", "corrected_value", "country",
  "country_code", "Cr", "cruise_id", "cruise_no", "cruise_no2",
  "cruise_type", "Cu", "data_col", "data_qualifier", "dataset_code",
  "dataset_group", "dataset_id", "dataset_name", "date_orig", "dcflag",
  "dde", "DDE degrees", "ddn", "DDN degrees", "denom", "depth", "depth_from",
  "depth_range", "depth_to", "Description", "description", "description_raw",
  "det_limit_flag", "discipline", "disposition", "dist_chk",
  "dist_to_aquaculture", "dist_to_coast", "dup", "dup_flag",
  "dup_superseded_by", "E", "element", "end", "end_day", "end_month",
  "end_year", "english", "enough", "est_country", "event_id",
  "expanded_uncertainty_pct", "Fe", "fe", "filtered", "final_total",
  "fines_lt63", "flag", "fold_vs_med", "frac", "frac_class", "fraction",
  "fraction_range_um", "from.date", "gear_code", "german", "gkey", "group",
  "group_code", "group_description", "group_median", "gs_corr", "gsf_id",
  "GSMF2", "GSMF2_63", "half", "has_year", "Hg", "hi_um", "high",
  "institute", "internal_qa_count", "internal_qa_detection_limit",
  "internal_qa_quantification_limit", "invalid_gs", "is_chem", "is_filtered",
  "is_lld", "K", "La", "lab", "lab_name", "label", "labo", "lat", "lat3",
  "lat_r", "latitude", "lawa_code", "layer_lower_boundary",
  "layer_upper_boundary", "Leire", "Li", "limit", "limit_flag", "lld",
  "lld_id", "lo_um", "lod", "lod_id", "logv", "lon", "lon3", "lon_r",
  "Longitude", "longitude", "loq", "loser_source", "low", "lower_depth",
  "mad_log", "mar_value", "matrix_code", "MATRX", "max_value", "mbsl",
  "mbsl m", "measured_value", "measurement_basis", "measurement_date",
  "measurement_depth", "measurement_end", "measurement_id",
  "measurement_method_code", "measurement_project", "measurement_start",
  "measurement_time", "measurement_time_id", "med_log", "median_val",
  "merged_n", "merged_rows", "metcu", "metcx", "method", "method1",
  "method2", "method_code", "method_description", "method_id",
  "method_seq_no", "metoa", "metps", "metpt", "metst", "Mg", "min_rel", "Mn",
  "Mo", "monitoring_station_name", "monotone", "month", "municipality", "N",
  "n", "n_high", "n_low", "n_rep", "n_values", "n_years", "Na", "Name",
  "name", "name_ices", "name_src", "new", "new_unit", "ngu_id", "Ni",
  "operator", "organisation", "outlier_extreme_flag", "outlier_flag",
  "outlier_stdev_flag", "P", "P2301_NGU ID", "PARAM", "param",
  "param_description", "param_id", "param_name", "parameter",
  "parameter_group", "parameter_name", "PARGROUP", "Pb",
  "physical_treatment", "platform_type", "pref", "prio",
  "proficiency_testing", "project", "project_affiliation", "project_id",
  "project_survey_id", "purpose", "qflag", "range_check_flag", "range_flag",
  "raw_code", "recovery_rate", "ref", "ref_description", "ref_id",
  "reference_material_basis", "reference_material_code",
  "reference_material_id", "reference_material_mean",
  "reference_material_sd", "reference_material_type", "refined_rows",
  "region", "rel_diff", "rel_gap", "repeat_group", "replicate_number",
  "responsible_institute", "retained_pct", "RLABO", "rows", "S",
  "Sample batch ID", "Sample core ID", "Sample Depth", "Sample ID",
  "Sample interval (top-bottom) from cm",
  "Sample interval (top-bottom) to cm", "sample_date", "sample_depth",
  "sample_id", "sample_id2", "sample_method", "sample_no", "sample_ref_code",
  "sample_seq_no", "sample_time", "sample_timestamp", "sample_type",
  "sample_type_description", "sampled_area", "Sampling tool",
  "sampling_method", "sampling_tool", "SamplingTool serial ID", "Sand", "Sc",
  "Se", "sea_name", "season", "sediment_composition", "sediment_content",
  "sediment_no", "seq_number", "Si", "sieve_class", "sieve_key", "sieve_um",
  "sieve_um_std", "Silt", "site_code", "site_id", "site_name", "Slam",
  "Source", "Sr", "src_flag", "start", "start_date", "start_day",
  "start_month", "start_year", "Stasjon", "Stasjon_kort", "station",
  "Station number", "station_code", "station_group", "station_id",
  "station_latitude", "station_longitude", "station_name", "station_no",
  "station_type", "stem", "stripped", "sub_no", "subsample_id", "survey_end",
  "survey_id", "survey_seq_no", "survey_start", "sym", "symbol", "t_out",
  "t_rng", "t_std", "t_val", "TC", "thr_hi", "thr_lo", "Ti", "to.date",
  "TOC", "tool_id", "TS", "type", "uncertainty_method", "uncrt", "unit",
  "unit2", "unit_std", "upper_depth", "utm33_x", "utm33_y", "V", "v",
  "Value", "value", "value_analysis", "value_flag", "value_pct", "value_sd",
  "value_std", "value_std_corr", "value_uncrt", "vessel_code", "vessel_name",
  "vflag", "Water Depth", "water_body_category", "weight_basis",
  "winner_source", "x", "Y", "Zn", "Zr"
))
