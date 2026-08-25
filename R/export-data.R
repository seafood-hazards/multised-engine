# ── Public entry point: export a flat dataset ────────────────────────────────
# The third verb, alongside create_db() (builds a database) and analyze_data()
# (computes from one). An export denormalises a finished database into a single
# flat file for people who do not want the relational schema. It computes
# nothing, which is why it is not an analysis module.

# The export registry. Only the refined generation has an export today; the
# generation argument is kept so adding one is a registry line rather than a
# signature change.
export_table <- function() {
  tibble::tribble(
    ~generation, ~format,   ~fun,                      ~per_source,
    "refined",   "dataset", "export_refined_dataset",  FALSE,
    "refined",   "efsa",    "export_efsa_submission",  FALSE
  )
}

#' Export a flat dataset from a finished database
#'
#' Denormalises a pipeline database into a single flat, gzipped TSV plus a
#' column dictionary, for users who want the data without the relational
#' schema. It reads only, so re-running is always safe.
#'
#' The refined export writes to `out_dir/download/`, the path the
#' multised-refined site's pre-render step expects.
#'
#' The refined dataset carries the pristine and background verdicts alongside
#' the measurements. It does not derive them: the thresholds come from the
#' `background` module's outputs under `out_dir/background/`, so
#' `analyze_data("refined")` must have run against the same `out_dir` first.
#' If those files are missing the export stops and names them.
#'
#' @param generation Which database to export. Currently `"refined"` only.
#' @param format Which export. `"dataset"` (the default) is the flat analysis
#'   dataset; `"efsa"` is the EFSA submission table, the superset of the
#'   reporting workbook and the ReplyFHF extraction spec. Both are cut from the
#'   same frame, so they cannot disagree about scope or verdicts.
#' @param source Must be `NULL`. Present for symmetry with [create_db()]; no
#'   export is per-source yet.
#' @param db_dir Directory holding the databases. Defaults to
#'   [multised_db_dir()].
#' @param out_dir Directory the export is written under. Defaults to
#'   [multised_analysis_dir()].
#' @param verbose Print the summary as it runs.
#'
#' @return Invisibly, the paths of the files written.
#' @export
#' @examples
#' \dontrun{
#' export_data("refined")
#' export_data("refined", format = "efsa")
#' export_data("refined", out_dir = "~/sediment/exports")
#' }
export_data <- function(generation = c("refined"),
                        format = c("dataset", "efsa"),
                        source = NULL,
                        db_dir = multised_db_dir(),
                        out_dir = multised_analysis_dir(),
                        verbose = TRUE) {
  generation <- match.arg(generation)
  format <- match.arg(format)
  spec <- export_table()
  spec <- spec[spec$generation == generation & spec$format == format, ]

  if (!is.null(source) && !spec$per_source) {
    stop("The ", generation, " export covers every source, so `source` must ",
         "be NULL.", call. = FALSE)
  }

  fun <- get(spec$fun, mode = "function")
  msg(verbose, "\n== ", generation, " ", format, " export ==\n")
  dir <- fun(db_dir = db_dir, out_dir = out_dir, verbose = verbose)
  invisible(sort(list.files(dir, full.names = TRUE)))
}
