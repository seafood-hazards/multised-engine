# ── Refined analyses, shared: below-LOQ censoring ────────────────────────────
# Which elements have too much of their distribution deleted for a background to mean
# anything. Used by the EF analysis, the pristine synthesis and the flat export so the
# three agree about which verdicts are publishable.
#
# The clean stage removes below-LOQ rows outright (clean-02-clean.R), which is correct for
# contamination screening and wrong for background estimation: a background IS the low end
# of the distribution, and the non-detects are evidence about that end. For five of the
# seven targets it removes under 2% and does not matter. For selenium (68.6%) and
# molybdenum (52.2%) it removes the majority, and what remains is an upper tail wearing the
# name "background".
#
# The measured shares, and how to regenerate them, are in
# inst/extdata/loq-censoring/README.md.

# Above this share of censored measurements, an element's background and pristine verdicts
# are withheld. The observed shares leave a wide gap to put it in: SE 68.6%, MO 52.2%, then
# nothing above 4.3%.
refined_censoring_limit <- function() 20

#' The measured below-LOQ share per element
#'
#' @param source_filter Which source's rows to return; `"ALL"` (the default) is the pooled
#'   figure the withholding decision uses.
#' @return A data frame with `symbol`, `source`, `n_slim`, `n_censored`, `pct_censored`.
#' @noRd
refined_censoring_table <- function(source_filter = "ALL") {
  f <- system.file("extdata", "loq-censoring", "refined_loq_censoring.csv",
                   package = "multised.engine")
  if (!nzchar(f))
    f <- file.path("inst", "extdata", "loq-censoring", "refined_loq_censoring.csv")
  if (!file.exists(f))
    stop("the below-LOQ censoring table is missing (looked at ", f, "); see ",
         "inst/extdata/loq-censoring/README.md for how to regenerate it", call. = FALSE)
  tab <- utils::read.csv(f, stringsAsFactors = FALSE)
  if (!is.null(source_filter)) tab <- tab[tab$source == source_filter, , drop = FALSE]
  tab
}

#' Elements whose background and pristine verdicts are withheld
#'
#' @return An upper-case character vector of element symbols.
#' @noRd
refined_withheld_elements <- function() {
  tab <- refined_censoring_table("ALL")
  sort(tab$symbol[tab$pct_censored > refined_censoring_limit()])
}
