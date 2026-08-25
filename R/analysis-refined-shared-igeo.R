# ── Refined analyses, shared: the Igeo scale ─────────────────────────────────
# The constants of the geo-accumulation index, held in one place because two files
# apply them: background step 10 computes the index and its class shares, and the
# flat export republishes both per measurement. A second copy of the breaks would
# let the download disagree with the page it is documented on.
#
#   Igeo = log2( C / (k * B) )
#
# B is the LOCAL background, the offshore (> 10 km from the coast) median of the
# same element and fraction, not a crustal reference: EFSA warns against Turekian
# and Wedepohl, and docs/generation-gaps.md section 3 measured why for this data.
#
# The class boundaries are Muller's, kept because a reader recognises them. Their
# MEANING here is not Muller's: "moderate" is two-and-a-bit times the local
# offshore median, not two-and-a-bit times the upper continental crust. The Igeo
# page says so; so does the export dictionary.

# Muller's allowance for lithological variability in the background itself.
refined_igeo_k <- function() 1.5

# A group whose offshore reference is thinner than this gets no Igeo at all: the
# index would carry the noise of its own denominator. Applied by step 10, which
# writes the outcome as `reliable` in refined_igeo_background.csv; the export
# reads that flag rather than recomputing it.
refined_igeo_min_n <- function() 30L

refined_igeo_breaks <- function() c(-Inf, 0, 1, 2, 3, 4, 5, Inf)

refined_igeo_labels <- function() {
  c("0 unpolluted", "1 unpolluted-moderate", "2 moderate", "3 moderate-heavy",
    "4 heavy", "5 heavy-extreme", "6 extreme")
}

#' Cut an Igeo value into its Muller class
#'
#' @param igeo Numeric index values.
#' @return Character class labels, `NA` where `igeo` is `NA`.
#' @noRd
refined_igeo_class <- function(igeo) {
  as.character(cut(igeo, refined_igeo_breaks(), labels = refined_igeo_labels(),
                   right = TRUE))
}

#' The index itself
#'
#' Both callers go through this so the published number and the class shares are
#' computed once. The rounding is part of the definition rather than a display
#' choice: cutting the unrounded value into classes and publishing the rounded one
#' lets a reader who applies the boundaries to the printed number get a different
#' class from the one printed beside it. Six significant digits, the same precision
#' the export uses for EF and for the same reason.
#'
#' @param value Concentration, mg/kg.
#' @param background The local (offshore) background for the same element and
#'   fraction, mg/kg.
#' @return The index, `NA` where either input is missing or non-positive.
#' @noRd
refined_igeo <- function(value, background) {
  ok <- !is.na(value) & value > 0 & !is.na(background) & background > 0
  out <- rep(NA_real_, length(ok))
  out[ok] <- signif(log2(value[ok] / (refined_igeo_k() * background[ok])), 6)
  out
}
