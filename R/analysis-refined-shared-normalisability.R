# ── Shared: is aluminium a working normaliser for this group? ────────────────
#
# D4. The site withholds a verdict on two grounds already: where the sample sits on
# the wrong aluminium basis, and where most of an element's measurements fell below
# the limit of quantification. This is the third, and it follows from the same
# principle: where the reference cannot be trusted, issue none.
#
# The enrichment factor divides metal by aluminium. That is only a grain-size control
# if aluminium actually predicts the metal. Measured (see
# `analysis_refined_regression()`), it does so for cobalt, copper and zinc in BULK
# and for nothing else: R2 about 0.46-0.58 for those three against 0.10 or less for
# every other element.
#
# THE QUESTION IS ONLY ASKED WHERE ALUMINIUM IS THE INTENDED CONTROL, which means
# bulk. A sieved sample was grain-size controlled by the sieve before the chemistry
# started; aluminium is not the correction there, it is a spare measurement. Asking
# whether it predicts the metal and withholding a verdict when it does not would
# read "no correction needed" as "the correction failed" and penalise the fraction
# that needs no correcting. `refined_gs_control()` is that split, and the pristine
# rule branches on it. The sieved r2 and rho stay in the frozen table because they
# are still a useful diagnostic (they are what shows the sieve has already removed
# the texture signal); they carry `normalisable = NA`, meaning not asked, and
# nothing consults them to decide anything.
#
# Two measures, both of which must clear their limit:
#
#   r2  - ordinary least squares R2 of metal on Al over the offshore reference, the
#         same rows the EF reference is built from.
#   rho - Spearman's rho over every on-basis row. This exists to answer the obvious
#         objection to r2 alone: an R2 on a restricted range is attenuated, so a low
#         value there might mean a narrow reference rather than a failed normaliser.
#         rho uses the full range of aluminium and is rank based, so neither the
#         restricted range nor the skew of these distributions can flatten it.
#
# The two agree completely on this data: no group passes one and fails the other, and
# the limits could be moved anywhere in 0.10-0.46 (r2) or 0.47-0.65 (rho) without
# changing which groups qualify. The rule is therefore not sensitive to where the
# line is drawn, which is what makes it defensible.
#
# The decision table is FROZEN in inst/extdata/normalisability/ rather than recomputed
# at run time, for the same reason as inst/extdata/loq-censoring/: it is a rule, so it
# should not move silently under a rebuild, and the EF and pristine steps that consume
# it run before the regression step that measures it. `check_normalisability()` closes
# the drift risk by comparing the frozen table against what the regression step has
# just computed, over the groups the rule actually governs.

refined_r2_limit <- function() 0.3

refined_rho_limit <- function() 0.5

#' What controls grain size in this fraction?
#'
#' "aluminium" in bulk, where the correction is statistical and has to be earned;
#' "sieve" in the sieved fractions, where it is physical and already applied.
#' Vectorised over `cat`.
#' @noRd
refined_gs_control <- function(cat) {
  if_else(!is.na(cat) & cat == "bulk", "aluminium", "sieve")
}

refined_normalisability_table <- function() {
  path <- system.file("extdata", "normalisability", "refined_al_normalisability.csv",
                      package = "multised.engine")
  if (!nzchar(path)) {
    path <- file.path("inst", "extdata", "normalisability",
                      "refined_al_normalisability.csv")
  }
  if (!file.exists(path)) {
    stop("normalisability table not found: ", path, call. = FALSE)
  }
  read_csv(path, show_col_types = FALSE)
}

#' Is metal / Al a usable normalisation for this element and fraction?
#'
#' Vectorised over `symbol` and `cat`. A group absent from the table is NOT
#' normalisable: absence of a fit is absence of evidence that the normaliser works.
#' A sieved group carries `normalisable = NA` (the question is not asked) and so is
#' also FALSE here: metal/Al is not the control there. Read this as "may EF be
#' computed", never as "may this group be judged" - for that, branch on
#' `refined_gs_control()` first.
#' @noRd
refined_normalisable <- function(symbol, cat) {
  tab <- refined_normalisability_table()
  key <- paste(symbol, cat)
  ok  <- paste(tab$symbol, tab$cat)[!is.na(tab$normalisable) & tab$normalisable]
  !is.na(symbol) & !is.na(cat) & key %in% ok
}

#' The groups D4 withholds, as "SYMBOL fraction" labels, for reporting.
#'
#' Aluminium-controlled groups only: a sieved group is not withheld by D4, it is
#' outside D4.
#' @noRd
refined_unnormalisable_groups <- function() {
  tab <- refined_normalisability_table()
  keep <- !is.na(tab$normalisable) & !tab$normalisable
  paste(tab$symbol, tab$cat)[keep]
}

#' Warn if the frozen rule no longer describes the data it was cut from.
#'
#' Only over the groups the rule governs. A sieved group has no frozen verdict to
#' drift from, so a change in its r2 is a diagnostic moving, not a rule breaking.
#' @noRd
check_normalisability <- function(fits, verbose = TRUE) {
  frozen <- refined_normalisability_table() |>
    filter(refined_gs_control(cat) == "aluminium")
  now <- fits |>
    filter(refined_gs_control(as.character(cat)) == "aluminium") |>
    transmute(symbol = as.character(symbol), cat = as.character(cat),
              normalisable_now = normalisable)
  cmp <- frozen |>
    transmute(symbol = as.character(symbol), cat = as.character(cat),
              normalisable) |>
    full_join(now, by = c("symbol", "cat"))
  bad <- cmp |>
    filter(is.na(normalisable) | is.na(normalisable_now) |
             normalisable != normalisable_now)
  if (nrow(bad)) {
    warning("the frozen normalisability rule no longer matches the data: ",
            paste(bad$symbol, bad$cat, collapse = ", "),
            ". Re-cut inst/extdata/normalisability/ and re-run the background suite.",
            call. = FALSE)
  } else if (verbose) {
    cat("normalisability rule verified against", nrow(cmp), "aluminium-controlled groups\n")
  }
  invisible(!nrow(bad))
}
