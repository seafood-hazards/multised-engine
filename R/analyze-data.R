# ── Public entry point: run an analysis generation ───────────────────────────
# Analyses read a finished database and write tidy CSVs (and, for one module,
# plots) under `out_dir/<module>/`. They never modify a pipeline database.

# The analysis registry. `module` groups the scripts a site page set is cut
# from; `step` orders them within a module. Only `background` has more than one
# step: its ten scripts build on each other and map onto the background and
# enrichment pages of multised-refined.
#
# Modules are otherwise independent, with one exception: `refined`/`summary`
# assembles what `refined`/`background` has written, so it is listed after it and
# a full analyze_data("refined") run reaches it in that order. Run on its own it
# errors rather than reading a stale directory.
analysis_module_table <- function() {
  tibble::tribble(
    ~generation, ~module,          ~step, ~fun,
    "clean",   "grainsize",       1L, "analysis_clean_grainsize",
    "clean",   "normalisation",   1L, "analysis_clean_normalisation",
    "clean",   "organic",         1L, "analysis_clean_organic",
    "clean",   "spatial",         1L, "analysis_clean_spatial",
    "clean",   "temporal",        1L, "analysis_clean_temporal",
    "clean",   "uncertainty",     1L, "analysis_clean_uncertainty",

    "merged",  "merged_summary",  1L, "analysis_merged_data_summary",
    "merged",  "grainsize",       1L, "analysis_merged_grainsize",
    "merged",  "normalisation",   1L, "analysis_merged_normalisation",
    "merged",  "organic",         1L, "analysis_merged_organic",
    "merged",  "spatial",         1L, "analysis_merged_spatial",
    "merged",  "temporal",        1L, "analysis_merged_temporal",
    "merged",  "depthprofile",    1L, "analysis_merged_depthprofile",
    "merged",  "enrichment",      1L, "analysis_merged_enrichment",
    "merged",  "clustering",      1L, "analysis_merged_clustering",
    "merged",  "hotspots",        1L, "analysis_merged_hotspots",
    "merged",  "regions",         1L, "analysis_merged_regions",
    "merged",  "siteyears",       1L, "analysis_merged_siteyears",
    "merged",  "outlier_review",  1L, "analysis_merged_outlier_review",

    "refined", "background",      1L, "analysis_refined_background",
    "refined", "background",      2L, "analysis_refined_background_gsnorm",
    "refined", "background",      3L, "analysis_refined_background_pressure",
    "refined", "background",      4L, "analysis_refined_background_ef",
    "refined", "background",      5L, "analysis_refined_background_mixture",
    "refined", "background",      6L, "analysis_refined_pristine",
    "refined", "background",      7L, "analysis_refined_pressure_controls",
    "refined", "background",      8L, "analysis_refined_regression",
    "refined", "background",      9L, "analysis_refined_method_changes",
    "refined", "background",     10L, "analysis_refined_background_igeo",

    "refined", "summary",         1L, "analysis_refined_summary"
  )
}
# The refined flat-dataset export used to sit here as a "download" module. It
# denormalises rather than computing anything, so it moved to export_data();
# see R/export-data.R. It is deliberately not reachable from both.

#' Which analysis modules a generation has
#'
#' @param generation One of `"clean"`, `"merged"` or `"refined"`.
#'
#' @return A data frame of the generation's modules, with columns `module`,
#'   `step` and `fun`, in run order.
#' @export
#' @examples
#' analysis_modules("refined")
analysis_modules <- function(generation = c("clean", "merged", "refined")) {
  generation <- match.arg(generation)
  tbl <- analysis_module_table()
  tbl[tbl$generation == generation, c("module", "step", "fun")]
}

#' Run the analyses for a generation
#'
#' Analyses read a finished database and write tidy CSVs under
#' `out_dir/<module>/`, one directory per module. They never modify a pipeline
#' database, so re-running is always safe.
#'
#' The `outlier_review` module is a review prototype rather than a site input:
#' it settled the outlier rule the merge stage now applies, and writes candidate
#' CSVs and distribution plots for eyeballing. It is included in a full
#' `"merged"` run, and needs the suggested package ggplot2.
#'
#' For the flat downloadable dataset, see [export_data()] - it denormalises
#' rather than computing, so it is not an analysis module.
#'
#' @param generation Which database to read: `"clean"` (per source),
#'   `"merged"` or `"refined"`.
#' @param module Optional module name, for example `"grainsize"`. `NULL` runs
#'   every module for the generation. See [analysis_modules()].
#' @param steps Optional subset of step numbers within a module. Only
#'   `"background"` has more than one step.
#' @param db_dir Directory holding the databases. Defaults to
#'   [multised_db_dir()].
#' @param out_dir Directory the CSVs are written under. Defaults to
#'   [multised_analysis_dir()].
#' @param verbose Print each analysis's console summary as it runs.
#'
#' @return Invisibly, a named list with one element per module run, holding the
#'   paths of the files in that module's output directory.
#' @export
#' @examples
#' \dontrun{
#' # every analysis for the merged database
#' analyze_data("merged")
#'
#' # one module
#' analyze_data("clean", module = "grainsize")
#'
#' # re-run only the enrichment-factor step of the background suite
#' analyze_data("refined", module = "background", steps = 4)
#' }
analyze_data <- function(generation = c("clean", "merged", "refined"),
                         module = NULL,
                         steps = NULL,
                         db_dir = multised_db_dir(),
                         out_dir = multised_analysis_dir(),
                         verbose = TRUE) {
  generation <- match.arg(generation)
  applicable <- analysis_module_table()
  applicable <- applicable[applicable$generation == generation, ]

  if (!is.null(module)) {
    if (length(module) != 1L || !is.character(module)) {
      stop("`module` must be a single module name.", call. = FALSE)
    }
    if (!module %in% applicable$module) {
      stop("The ", generation, " generation has no module ", sQuote(module),
           ". Available: ", paste(unique(applicable$module), collapse = ", "),
           ".", call. = FALSE)
    }
    applicable <- applicable[applicable$module == module, ]
  }

  if (!is.null(steps)) {
    if (is.null(module)) {
      stop("`steps` selects within one module, so `module` is required with it.",
           call. = FALSE)
    }
    steps <- as.integer(steps)
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("Module ", sQuote(module), " has steps ",
           paste(applicable$step, collapse = ", "), "; got ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }

  out <- list()
  for (i in seq_len(nrow(applicable))) {
    mod  <- applicable$module[i]
    step <- applicable$step[i]
    fun  <- get(applicable$fun[i], mode = "function")
    label <- if (max(applicable$step[applicable$module == mod]) > 1L) {
      paste0(mod, " step ", step)
    } else {
      mod
    }
    msg(verbose, "\n== ", generation, " analysis: ", label, " ==\n")
    mod_dir <- fun(db_dir = db_dir, out_dir = out_dir, verbose = verbose)
    # A multi-step module writes into one directory across its steps, so union
    # rather than overwrite: the last step must not hide the earlier outputs.
    out[[mod]] <- sort(unique(c(out[[mod]],
                                list.files(mod_dir, full.names = TRUE))))
  }
  invisible(out)
}
