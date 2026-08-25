# ── Laboratory accreditation ─────────────────────────────────────────────────
# EFSA's optional `accLab` field: was the analysis done by an accredited lab?
#
# Two of the five sources say. Neither said so downstream before: Mareano's text
# reached the slim `method` table as a free-text `comment` and was dropped at the
# clean stage with the rest of the source-specific columns, and MUDAB's field was
# never selected at all.
#
# | Source    | Field                             | Vocabulary                                 |
# |-----------|-----------------------------------|--------------------------------------------|
# | Mareano   | `lld.comment`                     | English, three states, plus unrelated notes |
# | MUDAB     | `analysis_method.accreditation`   | y / true / ja / 1 against n / false         |
# | ICES-DOME | (none)                            |                                             |
# | Vannmiljø | (none)                            |                                             |
# | 4Demon    | (none)                            |                                             |
#
# We keep three states where the source has three, and map to EFSA's binary only
# at the export boundary. Same reasoning as `UNK` against `NON` in
# R/extraction-class.R: a distinction the source drew should not be thrown away
# upstream of the one consumer that cannot represent it.

# The three states, plus NA for "not reported".
ACCREDITATION_LEVELS <- c("yes", "partly", "no")

# Mareano's `lld.comment` is a mixed field: three accreditation phrases and a set
# of unrelated notes about a 2013 instrument change. Only the phrases are
# accreditation, so the mapping is an exact lookup rather than a pattern -- note
# that "accredited" is a substring of both "not accredited" and "partly
# accredited", so grepl() would read every row as accredited.
.accreditation_mareano <- c(
  "accredited"            = "yes",
  "partly accredited"     = "partly",
  "not accredited"        = "no",
  "not accredited method" = "no")

# MUDAB writes the same two answers seven ways across German and English.
.accreditation_mudab <- c(
  "y" = "yes", "yes" = "yes", "ja" = "yes", "true" = "yes", "1" = "yes",
  "n" = "no",  "no"  = "no",  "nein" = "no", "false" = "no", "0" = "no")

#' Canonicalise a source's accreditation field
#'
#' @param x The source's raw field.
#' @param source One of [multised_sources()]'s names, in the spelling the slim
#'   transforms use.
#' @return `"yes"`, `"partly"`, `"no"`, or `NA` where the source said nothing.
#'   An unrecognised non-blank value is `NA` rather than `"no"`: a vocabulary we
#'   do not know is a thing to look at, not a negative answer.
#' @noRd
accreditation_canon <- function(x, source) {
  x <- tolower(trimws(as.character(x)))
  blank <- is.na(x) | !nzchar(x)
  tbl <- switch(source,
    "Mareano"   = .accreditation_mareano,
    "MUDAB"     = .accreditation_mudab,
    "ICES-DOME" = NULL,
    "Vannmiljø" = NULL,
    "4Demon"    = NULL,
    stop("no accreditation mapping for source '", source, "'", call. = FALSE))

  out <- if (is.null(tbl)) rep(NA_character_, length(x)) else unname(tbl[x])
  out <- rep_len(out, length(x))
  out[blank] <- NA_character_
  out
}

#' EFSA's binary `accLab`
#'
#' EFSA sets no performance requirement and counts a lab "following a quality
#' control/quality assurance procedure, including reference samples" as
#' accredited, so `"partly"` maps to `Y`: the lab holds accreditation, it is the
#' parameter coverage that is partial. The original word travels in the export's
#' comment field so EFSA can disagree.
#'
#' @param accredited Output of [accreditation_canon()].
#' @return `"Y"`, `"N"`, or `NA`.
#' @noRd
accreditation_efsa_yn <- function(accredited) {
  dplyr::case_when(accredited %in% c("yes", "partly") ~ "Y",
                   accredited == "no"                 ~ "N",
                   TRUE                               ~ NA_character_)
}

# Mareano's `lld.comment` also carries notes about a 2013 instrument change,
# which are not accreditation and not a vocabulary drift. They are expected, so
# the drift check ignores them rather than warning on every rebuild.
.accreditation_ignore <- list("Mareano" = "^new lld=")

#' Warn when a source emits an accreditation value the table does not know
#'
#' The point is to catch a vocabulary drift, an eighth spelling of yes appearing
#' in a MUDAB refresh, rather than to police a free-text field.
#'
#' @param x The source's raw field.
#' @param source As in [accreditation_canon()].
#' @noRd
check_accreditation_values <- function(x, source) {
  tbl <- switch(source, "Mareano" = .accreditation_mareano,
                        "MUDAB"   = .accreditation_mudab, NULL)
  if (is.null(tbl)) return(invisible(character(0)))
  v <- tolower(trimws(as.character(x)))
  v <- v[!is.na(v) & nzchar(v)]
  ignore <- .accreditation_ignore[[source, exact = TRUE]]
  if (!is.null(ignore)) v <- v[!grepl(ignore, v)]
  unknown <- setdiff(unique(v), names(tbl))
  if (length(unknown)) {
    warning(source, ": accreditation value(s) not in the table, read as ",
            "not reported: ", paste(sQuote(unknown), collapse = ", "),
            call. = FALSE)
  }
  invisible(unknown)
}
