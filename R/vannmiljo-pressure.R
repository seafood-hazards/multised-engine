# ── Vannmiljø programme pressure class ───────────────────────────────────────
# Vannmiljø files every record under an `activity`, its monitoring programme, and
# the programme usually says why the sample was taken. "Overvåking av forurenset
# sjøbunn" is contaminated seabed; "Basisovervåking - referanseforhold" is
# reference conditions; "Miljøovervåking akvakulturanlegg" is monitoring under fish
# farms, which is the data EFSA asked for by name.
#
# That is **stated** evidence of pressure, independent of the geometric proxies
# (dist_to_coast, dist_to_aquaculture) and of the chemical one (EF). The pristine
# work currently validates EF against distance alone, so this is a third axis.
#
# The code survives into refined as `dataset.dataset_code` already; only the
# meaning was missing. It lands in a new `pressure_class` column rather than the
# existing `dataset_group`, which MUDAB already uses for its own dataset grouping.
#
# Read the table through this file, never directly.

#' The frozen Vannmiljø programme table
#'
#' @return A data frame: `code`, `name_no`, `name_en`, `pressure_class`,
#'   `judgement`, `note`.
#' @noRd
vannmiljo_programme_table <- function() {
  f <- system.file("extdata", "vannmiljo-programmes", "pressure_class.csv",
                   package = "multised.engine")
  if (!nzchar(f))
    f <- file.path("inst", "extdata", "vannmiljo-programmes", "pressure_class.csv")
  if (!file.exists(f))
    stop("the Vannmiljø programme table is missing (looked at ", f, "); see ",
         "inst/extdata/vannmiljo-programmes/README.md",
         call. = FALSE)
  read_csv(f, show_col_types = FALSE)
}

#' Pressure class for a Vannmiljø activity code
#'
#' @param code The `activity_id` / `dataset_code`.
#' @return One of `"aquaculture"`, `"pressure"`, `"reference"`, `"survey"`,
#'   `"unknown"`, or `NA` for a code the table does not hold. `NA` rather than
#'   `"unknown"`: the source has its own `ANNE` ("Annet", other) which *is*
#'   `"unknown"`, and a code we have never seen is a different thing from a code
#'   the source itself declines to classify.
#' @noRd
vannmiljo_pressure_class <- function(code) {
  tbl <- vannmiljo_programme_table()
  unname(stats::setNames(tbl$pressure_class, tbl$code)[as.character(code)])
}

#' Warn when Vannmiljø emits a programme code the table does not hold
#'
#' @param code The codes actually present in a build.
#' @noRd
check_vannmiljo_programmes <- function(code) {
  tbl <- vannmiljo_programme_table()
  unknown <- setdiff(unique(as.character(code[!is.na(code)])), tbl$code)
  if (length(unknown)) {
    warning("Vannmiljø: programme code(s) not in the pressure table, left ",
            "unclassified: ", paste(sQuote(unknown), collapse = ", "),
            "\nAdd them to inst/extdata/vannmiljo-programmes/pressure_class.csv.",
            call. = FALSE)
  }
  invisible(unknown)
}
