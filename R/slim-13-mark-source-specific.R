# ── Slim step 13: mark source-specific ───────────────────────────────────────
# Adds `measurement.src_flag` (TEXT, NULL = pass), folding each source's native
# leftovers that the common flags (steps 3-12) miss.
#
# Source-specific, and present only for Vannmiljo, ICES-DOME and 4Demon: the
# other two carry nothing extra. The derivation differs per source; the
# write-back and verification are shared.

# Vannmiljo: `operator` (the relational sign) and `filtered`. Their
# below-detection meaning ('<' / 'ND') is already in below_loq (step 8); this
# captures the leftovers.
#   above_range — operator '>' : a right-censored "greater-than" reading (the
#                 value is only a lower bound).
#   filtered    — filtered = 1 : a filtered sample (filtered water rather than
#                 bulk sediment), only a couple of rows.
# The two are disjoint in the data; the combined label is kept as a guard in case
# a future rebuild produces a row that is both.
slim_src_flag_vannmiljo <- function(m) {
  m |> mutate(src_flag = case_when(
    operator == ">" & filtered == 1L ~ "above_range,filtered",
    operator == ">"                  ~ "above_range",
    filtered == 1L                   ~ "filtered",
    TRUE                             ~ NA_character_))
}

# ICES-DOME: the native VFLAG (originator's value-quality flag; meanings from the
# pilot `code_lookup` table).
#   suspect    — VFLAG 'S': "Suspect value - considered suspect by originator on
#                the basis of quality control or recorder/instrument/platform
#                performance".
#   calculated — VFLAG 'C': "Calculated value" (a derived value rather than a
#                direct measurement).
# VFLAG 'A' ("Acceptable value") and NULL pass. The other native columns are left
# unfolded on purpose: `dcflag` holds ICES DATSU screening/conversion codes (mostly
# benign unit conversions), and `metcu`/`uncrt`/`matrix` are uncertainty and
# sample-fraction metadata, not clean quality flags.
slim_src_flag_ices_dome <- function(m) {
  m |> mutate(src_flag = case_when(
    vflag == "S" ~ "suspect",
    vflag == "C" ~ "calculated",
    TRUE         ~ NA_character_))
}

# 4Demon: unlike Vannmiljo / ICES-DOME (a single native flag), 4Demon carries
# several independent quality flags that can co-occur on one row, so `src_flag`
# holds a comma-joined set of tokens. Meanings from the pilot metadata
# (inst/scripts or R/pilot/4demon/01_extract_meta_information.R):
#   suspect          — value_flag 1 : suspect value.
#   invalid          — value_flag 3 : invalid value.
#   range_check      — range_check_flag 1 : outside 4Demon's expected range.
#   outlier_moderate — outlier_extreme_flag 1 : moderate per-parameter outlier.
#   outlier_extreme  — outlier_extreme_flag 2 : extreme per-parameter outlier.
#   outlier_stdev    — outlier_stdev_flag 1 : outlier by a stdev threshold.
# value_flag 2 (below detection) is deliberately NOT folded: it duplicates
# `below_loq` (step 8, from the detection-limit flag). `corrected_value`,
# `fraction_range` and `matrix` are provenance/metadata, not quality flags.
slim_src_flag_4demon <- function(m) {
  m |>
    mutate(
      t_val = case_when(vflag == 1 ~ "suspect",
                        vflag == 3 ~ "invalid",
                        TRUE       ~ NA_character_),
      t_rng = if_else(range_check_flag == 1, "range_check", NA_character_),
      t_out = case_when(outlier_extreme_flag == 2 ~ "outlier_extreme",
                        outlier_extreme_flag == 1 ~ "outlier_moderate",
                        TRUE                      ~ NA_character_),
      t_std = if_else(outlier_stdev_flag == 1, "outlier_stdev", NA_character_)
    ) |>
    tidyr::unite("src_flag", t_val, t_rng, t_out, t_std, sep = ",", na.rm = TRUE) |>
    mutate(src_flag = na_if(src_flag, ""))
}

slim_mark_source_specific <- function(source, db_dir = multised_db_dir(),
                                      verbose = TRUE) {
  derive <- switch(
    source,
    "vannmiljo" = slim_src_flag_vannmiljo,
    "ices-dome" = slim_src_flag_ices_dome,
    "4demon"    = slim_src_flag_4demon,
    stop("Source ", sQuote(source), " has no source-specific flags (step 13 ",
         "applies to vannmiljo, ices-dome and 4demon only).", call. = FALSE)
  )

  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Add src_flag column (idempotent) ────────────────────────────────────
  add_column_if_missing(con, "measurement", "src_flag", "TEXT")

  # ── 2. Derive the source's native flags ────────────────────────────────────
  m <- dbReadTable(con, "measurement") |> as_tibble()
  d <- derive(m)

  # ── 3. Write back (idempotent) ─────────────────────────────────────────────
  dbWriteTable(con, "qc_src",
               d |> filter(!is.na(src_flag)) |> select(measurement_id, src_flag),
               temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_src ON qc_src(measurement_id);")
  dbExecute(con, "
    UPDATE measurement
    SET src_flag = (SELECT src_flag FROM qc_src q
                    WHERE q.measurement_id = measurement.measurement_id);")

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  # 4Demon combines tokens, so it also reports the overall flagged count.
  label <- if (identical(source, "4demon")) "(pass)" else "(none)"
  out <- dbGetQuery(con, sprintf(
    "SELECT COALESCE(src_flag,'%s') src_flag, COUNT(*) n
     FROM measurement GROUP BY src_flag ORDER BY n DESC", label))
  flagged <- NULL
  if (identical(source, "4demon")) {
    flagged <- dbGetQuery(con, "SELECT COUNT(*) total,
                                       SUM(CASE WHEN src_flag IS NOT NULL THEN 1 ELSE 0 END) flagged
                                FROM measurement")
  }
  if (verbose) {
    cat(if (identical(source, "4demon")) "src_flag (combined tokens):\n" else "src_flag:\n")
    print(out)
    if (!is.null(flagged)) {
      cat("\nrows flagged (any token) vs total:\n")
      print(flagged)
    }
  }
  invisible(if (is.null(flagged)) out else list(src_flag = out, flagged = flagged))
}
