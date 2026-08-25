# ── Shared: extraction class ─────────────────────────────────────────────────
#
# EFSA's "Extraction class" is the DIGESTION CHEMISTRY, not the sampling method: how
# aggressively the metal was liberated from the sediment before it reached the
# instrument. Three classes, defined in docs/ReplyFHF_TypeDataForEFSA.md:
#
#   1 strong    - aqua regia or strong acid digestion (HF, HNO3, HCl, HClO4
#                 combinations), aimed at total recovery
#   2 milder    - HNO3 alone or with H2O2, targeting labile, exchangeable or
#                 organically-bound metal
#   3 weak-none - no extraction, or poorly reported / undisclosed
#
# This is the RECORDED counterpart of the aluminium measurement basis that
# R/analysis-refined-shared-basis.R infers from Fe/Al with a cut at 1.0. The two can
# be cross-tabulated on ICES-DOME and MUDAB, the sources that carry both. See
# docs/efsa-submission.md.
#
# The canonical vocabulary is ICES METCX, which MUDAB already uses verbatim in
# `chemical_treatment` - the same arrangement clean-shared-method-meta.R relies on for
# method codes. One code is ours: UNK, "not reported". It is deliberately distinct from
# the ICES code NON, "None": NON is a positive statement that no extraction was
# performed, UNK is an absence of information. Both land in EFSA class 3, which covers
# each of them, but conflating them at the source would throw away the difference.
#
# The table is FROZEN in inst/extdata/extraction-class/ rather than derived at run
# time, for the same reason as inst/extdata/normalisability/ and
# inst/extdata/loq-censoring/: it encodes judgement calls, so it must not move silently
# under a rebuild. Six codes are judgement calls and say so in the `judgement` column,
# with the reasoning in the README.

# ── 1. The frozen table ──────────────────────────────────────────────────────

#' The frozen extraction-code table
#'
#' @return A data frame with `code`, `description`, `efsa_class`, `efsa_label`,
#'   `judgement`, `organic_solvent`, `note`.
#' @noRd
extraction_class_table <- function() {
  f <- system.file("extdata", "extraction-class", "extraction_class.csv",
                   package = "multised.engine")
  if (!nzchar(f))
    f <- file.path("inst", "extdata", "extraction-class", "extraction_class.csv")
  if (!file.exists(f))
    stop("the extraction-class table is missing (looked at ", f, "); see ",
         "inst/extdata/extraction-class/README.md for how to regenerate it",
         call. = FALSE)
  read_csv(f, show_col_types = FALSE)
}

#' EFSA extraction class for a canonical code
#'
#' Vectorised. An unrecognised code returns NA rather than being quietly binned into
#' class 3: an unmapped code means the source vocabulary has drifted, which is a thing
#' to fix rather than to average over. `check_extraction_codes()` reports them.
#' @noRd
extraction_efsa_class <- function(code) {
  tab <- extraction_class_table()
  tab$efsa_class[match(as.character(code), tab$code)]
}

#' Is this code an organic-solvent preparation?
#'
#' On a trace-element row it is a mis-tag, so the pipeline flags rather than trusts it.
#' @noRd
extraction_is_organic_solvent <- function(code) {
  tab <- extraction_class_table()
  out <- tab$organic_solvent[match(as.character(code), tab$code)]
  !is.na(out) & out
}

# ── 2. Source field -> canonical code ────────────────────────────────────────
# Only two sources record the extraction step at all. The other three are mapped to a
# constant, and the constant is UNK rather than a guess: Norwegian practice would
# usually put the Vannmiljo submissions at class 2, but that is an assumption about an
# unrecorded step, and assuming it would manufacture 62,017 rows of false precision.

#' Map a source's native extraction field to the canonical vocabulary
#'
#' @param x The native field: `metcx` (ICES-DOME), `chemical_treatment` (MUDAB),
#'   `method2` (Mareano), `method_code` (4Demon). Ignored for Vannmiljo.
#' @param source One of the pipeline source labels.
#' @return A character vector of canonical codes; never NA (unmapped becomes "UNK").
#' @noRd
extraction_canon <- function(x, source) {
  x <- as.character(x)
  blank <- is.na(x) | !nzchar(trimws(x))
  out <- switch(
    source,
    # both already speak METCX, so the native value IS the canonical code
    "ICES-DOME" = x,
    "MUDAB"     = x,
    # one method for every target element: "partial extraction by 7 M HNO3 in
    # autoclave". "Partial" and "HNO3" point the same way, so class 2.
    "Mareano"   = ifelse(grepl("HNO3", x, fixed = TRUE), "HNO", "UNK"),
    # programme_instrument_sieve (e.g. Monit3_OES/MS_63), which encodes no chemistry.
    # A single code names one outright.
    "4Demon"    = ifelse(grepl("^HNO3$", trimws(x)), "HNO", "UNK"),
    # the analysis field holds ISO DETERMINATION standards (NS-EN ISO 17294-2 is
    # ICP-MS), which say nothing about digestion, and 44% of it is "Unknown"
    "Vannmiljø" = "UNK",
    stop("no extraction mapping for source '", source, "'", call. = FALSE))
  # a branch that ignores `x` returns a scalar, so recycle before subsetting:
  # otherwise `out[blank] <- ` writes past the end and leaves NA behind.
  out <- rep_len(out, length(x))
  out[blank] <- "UNK"
  out
}

# ── 3. Conflicting extractions within one measurement ────────────────────────

#' Collapse an extraction that disagrees with itself
#'
#' Call inside a `group_by()` over the columns that identify ONE measurement. Where a
#' source reports the same measurement under two analysis-method rows that differ only
#' in the digestion, the extraction is not knowable and every row in the group becomes
#' `"UNK"`.
#'
#' This is not hypothetical: MUDAB reports six target measurements twice, once under
#' `HF-CB` (a total digestion) and once under `HNO` (a partial one), with identical
#' values. Both cannot be right, and nothing in the source says which is. Withholding
#' matches how the project treats every other untrustworthy reference.
#'
#' It also protects the row count. Extraction is part of method identity, so without
#' this the two rows take different `method_id`s, survive the `distinct()` that mints
#' the measurement table, and the measurement is silently counted twice.
#' @noRd
extraction_unambiguous <- function(extraction) {
  if (length(unique(extraction)) > 1) rep("UNK", length(extraction)) else extraction
}

# ── 4. Drift check ───────────────────────────────────────────────────────────

#' Warn if a source has produced codes the frozen table does not know
#'
#' @param codes Canonical codes, as returned by `extraction_canon()`.
#' @noRd
check_extraction_codes <- function(codes, source, verbose = TRUE) {
  tab <- extraction_class_table()
  bad <- sort(unique(as.character(codes)[!as.character(codes) %in% tab$code]))
  if (length(bad)) {
    warning(source, ": extraction codes absent from the frozen table: ",
            paste(bad, collapse = ", "),
            ". Add them to inst/extdata/extraction-class/ before relying on the class.",
            call. = FALSE)
  } else if (verbose) {
    cat(sprintf("extraction codes verified for %s (%d distinct)\n",
                source, length(unique(codes))))
  }
  invisible(!length(bad))
}
