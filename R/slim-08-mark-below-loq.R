# ── Slim step 8: mark below LOQ ──────────────────────────────────────────────
# Adds `measurement.below_loq` (0/1), folding each source's own
# detection/quantification signal into one common below-limit marker for removal
# in the clean stage.
#
# Source-specific: the signal differs per source, so each has its own column and
# rule. Two shapes: an integer 0/1 flag column, or a code column matched against
# a set of below-limit codes.

# Per-source detection signal.
#
# `warn_unmapped` is only set for the two ICES-coded sources: an unexpected qflag
# there is genuinely unaudited, whereas Vannmiljo's other operators ('=' normal,
# '>' above-range) are known and deliberately not below-limit, so warning on them
# would be noise.
slim_below_loq_spec <- function(source) {
  switch(
    source,
    "mareano"   = list(col = "below_lld",  codes = NULL, warn_unmapped = FALSE,
                       note = "below the lower limit of detection; no separate quantification limit"),
    "4demon"    = list(col = "limit_flag", codes = NULL, warn_unmapped = FALSE,
                       note = "value is below the detection limit"),
    "vannmiljo" = list(col = "operator",
                       codes = c("<", "ND"), warn_unmapped = FALSE,
                       note = "'<' below the limit and 'ND' not detected; '=' normal, '>' above-range"),
    "ices-dome" = list(col = "qflag",
                       codes = c("<", "D", "Q", "<~Q", "<~D"), warn_unmapped = TRUE,
                       note = "ICES qflag below-limit codes"),
    "mudab"     = list(col = "qflag",
                       codes = c("<", "D", "Q"), warn_unmapped = TRUE,
                       note = "ICES qflag below-limit codes"),
    stop("No below-LOQ signal defined for source ", sQuote(source), call. = FALSE)
  )
}

slim_mark_below_loq <- function(source, db_dir = multised_db_dir(),
                                verbose = TRUE) {
  spec <- slim_below_loq_spec(source)
  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Add below_loq column (idempotent) ───────────────────────────────────
  # Common cross-source flag: 1 = value is below the detection/quantification
  # limit (an uncertain "less-than" reading), 0 = a quantified value. These rows
  # are candidates for removal in the clean stage.
  add_column_if_missing(con, "measurement", "below_loq", "INTEGER")

  # ── 2. Map the source detection flag onto below_loq ────────────────────────
  if (is.null(spec$codes)) {
    # An integer 0/1 flag column.
    dbExecute(con, sprintf("
      UPDATE measurement
      SET below_loq = CASE WHEN %s = 1 THEN 1 ELSE 0 END;", spec$col))
  } else {
    # A code column. Any unexpected non-NULL code is reported so the mapping
    # stays auditable after a rebuild.
    if (isTRUE(spec$warn_unmapped)) {
      present <- dbGetQuery(con, sprintf(
        "SELECT DISTINCT %s AS code FROM measurement WHERE %s IS NOT NULL",
        spec$col, spec$col))$code
      unmapped <- setdiff(present, spec$codes)
      if (length(unmapped) > 0) {
        warning("Unmapped non-NULL ", spec$col, " code(s): ",
                paste(unmapped, collapse = ", "),
                " -- treated as NOT below_loq (0). Review whether they are below-limit.")
      }
    }
    dbExecute(con, sprintf("
      UPDATE measurement
      SET below_loq = CASE WHEN %s IN (%s) THEN 1 ELSE 0 END;",
      spec$col, paste(sprintf("'%s'", spec$codes), collapse = ", ")))
  }

  # ── 3. Verify ──────────────────────────────────────────────────────────────
  crosstab <- dbGetQuery(con, sprintf(
    "SELECT COALESCE(CAST(%s AS TEXT),'(NULL)') %s, below_loq, COUNT(*) n
     FROM measurement GROUP BY %s, below_loq ORDER BY n DESC",
    spec$col, spec$col, spec$col))
  totals <- dbGetQuery(con, "SELECT below_loq, COUNT(*) n
                             FROM measurement GROUP BY below_loq ORDER BY n DESC")
  if (verbose) {
    cat(spec$col, " -> below_loq crosstab:\n", sep = "")
    print(crosstab)
    cat("below_loq totals:\n")
    print(totals)
  }
  invisible(list(crosstab = crosstab, totals = totals))
}
