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
# undefined globals, but R CMD check cannot tell, so declare them here.
utils::globalVariables(c(
  "sym", "symbol", "category", "n"
))
