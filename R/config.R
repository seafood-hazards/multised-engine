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
#' `multised_analysis_dir()` the directory analysis outputs are written to. Both
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
  "accessed", "accreditation", "activity_id", "activity_name", "al",
  "analysis", "analysis_id", "analysis_method_id", "analytical_laboratory",
  "analytical_laboratory_description", "anchor", "aqua_id", "bad_depth",
  "basis", "bathymetry", "below_lld", "below_loq", "below_loq_num",
  "best_pref", "bin", "cas", "cas_no", "cas_number", "category",
  "category_code", "clean_n", "clean_total", "cluster", "code", "code_name",
  "core_id", "corg", "corrected_value", "country", "country_code",
  "cruise_id", "cruise_type", "data_col", "data_qualifier", "dataset_code",
  "dataset_group", "dataset_id", "dataset_name", "date_orig", "dcflag",
  "dde", "ddn", "denom", "depth", "depth_from", "depth_range", "depth_to",
  "description", "det_limit_flag", "disposition", "dist_chk",
  "dist_to_aquaculture", "dist_to_coast", "dup", "dup_flag",
  "dup_superseded_by", "element", "enough", "est_country", "event_id",
  "expanded_uncertainty_pct", "fe", "filtered", "final_total", "fines_lt63",
  "flag", "fold_vs_med", "frac", "frac_class", "fraction",
  "fraction_range_um", "gear_code", "gkey", "group", "group_code",
  "group_median", "gs_corr", "gsf_id", "GSMF2", "GSMF2_63", "half",
  "has_year", "hi_um", "high", "institute", "internal_qa_detection_limit",
  "internal_qa_quantification_limit", "invalid_gs", "is_chem", "is_lld",
  "lab", "lab_name", "labo", "lat", "lat_r", "lat3", "latitude",
  "layer_lower_boundary", "layer_upper_boundary", "limit", "limit_flag",
  "lld", "lo_um", "lod", "logv", "lon", "lon_r", "lon3", "longitude", "loq",
  "loser_source", "low", "lower_depth", "mad_log", "mar_value",
  "matrix_code", "max_value", "mbsl", "measured_value", "measurement_basis",
  "measurement_date", "measurement_depth", "measurement_id",
  "measurement_method_code", "measurement_time", "measurement_time_id",
  "med_log", "median_val", "merged_n", "merged_rows", "metcu", "method",
  "method_code", "method_description", "method_id", "method1", "metoa",
  "min_rel", "monotone", "municipality", "n", "n_high", "n_low", "n_rep",
  "n_years", "name", "name_ices", "name_src", "operator", "organisation",
  "outlier_extreme_flag", "outlier_flag", "outlier_stdev_flag", "param",
  "param_description", "param_id", "param_name", "parameter",
  "parameter_group", "parameter_name", "pref", "prio", "project",
  "project_id", "qflag", "range_check_flag", "range_flag", "raw_code",
  "refined_rows", "region", "rel_diff", "rel_gap", "repeat_group",
  "responsible_institute", "retained_pct", "rows", "sample_id", "sample_no",
  "sample_time", "sample_timestamp", "sample_type",
  "sample_type_description", "sampled_area", "sampling_method",
  "sampling_tool", "sea_name", "sediment_composition", "sediment_content",
  "sediment_no", "sieve_class", "sieve_key", "sieve_um", "sieve_um_std",
  "site_code", "site_id", "Source", "src_flag", "start", "start_year",
  "station_id", "station_latitude", "station_longitude", "station_no",
  "stem", "subsample_id", "survey_id", "survey_seq_no", "sym", "symbol",
  "t_out", "t_rng", "t_std", "t_val", "thr_hi", "thr_lo", "type", "uncrt",
  "unit", "unit_std", "unit2", "upper_depth", "v", "value", "value_analysis",
  "value_flag", "value_pct", "value_sd", "value_std", "value_std_corr",
  "value_uncrt", "vflag", "weight_basis", "winner_source"
))
