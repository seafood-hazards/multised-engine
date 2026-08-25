# ── Clean stage shared helper: matrix_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/matrix_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared matrix metadata ──────────────────────────────────────
# Harmonises the measurement `matrix` column (the sediment fraction the chemistry
# was measured on) to one common vocabulary, the ICES `SED<µm>` codes:
#   - ICES-DOME / MUDAB already use it (SEDtot, SED2000, SED1000, SED500, SED90,
#     SED63, SED62, SED20) and pass through; MUDAB's stray `PK_default` sentinel
#     (matrix unrecorded) is nulled;
#   - 4Demon carries two fields, and the sieve is in the second one. `matrix_code`
#     is FS or US on every row; the fraction actually analysed is `fraction_range`,
#     "<lo>-<hi>" in µm, which `pilot-01-extract-4demon.R` documents as "0-63 =
#     fine fraction <63 um, 0-2000 = bulk sediment <2 mm". The range wins where it
#     is present, and the codes are the fallback (FS -> SED63, US -> SEDtot);
#   - Mareano / Vannmiljø have no matrix (stays absent / NULL).
# Value-preserving relabel; run in 01_harmonise (before the measurement select).

# raw matrix -> canonical ICES code. Only non-identity mappings are listed; codes
# already in the ICES vocabulary (SED*) pass through unchanged. NA maps to NA.
matrix_canon <- c(
  # 4Demon native codes
  "FS" = "SED63",     # fine sediment, <63 µm fraction
  "US" = "SEDtot",    # unsieved / bulk sediment
  # MUDAB sentinel for an unrecorded matrix -> NULL
  "PK_default" = NA_character_)

# "<lo>-<hi>" in µm -> the ICES SED<hi> code, or NA where it is not a cutoff.
#
# Only a range starting at zero is a sieve cutoff. "63-2000" would be a band of
# coarse material, and naming it by its upper edge would call it fine, so such a
# range yields NA and the matrix code stands.
fraction_range_matrix <- function(fraction_range) {
  parts <- strsplit(as.character(fraction_range), "-", fixed = TRUE)
  vapply(parts, function(p) {
    if (length(p) != 2L) return(NA_character_)
    lo <- suppressWarnings(as.numeric(p[[1L]]))
    hi <- suppressWarnings(as.numeric(p[[2L]]))
    if (anyNA(c(lo, hi)) || lo != 0 || hi <= 0 || hi != round(hi)) {
      return(NA_character_)
    }
    paste0("SED", format(hi, scientific = FALSE, trim = TRUE))
  }, character(1L))
}

standardise_matrix <- function(measurement) {
  if (!"matrix" %in% names(measurement)) return(measurement)   # Mareano / Vannmiljø
  mapped <- unname(matrix_canon[measurement$matrix])
  # keep the original where the code is not in the remap table (already ICES / NA)
  measurement$matrix <- ifelse(measurement$matrix %in% names(matrix_canon),
                               mapped, measurement$matrix)

  # The recorded range is the better evidence, so it overrides the code. Without
  # this, 4Demon's FS -> SED63 called 640 bulk rows (0-2000) sieved at 63 µm and
  # put 246 more (0-37, 0-500) at a cutoff they were never measured at.
  if ("fraction_range" %in% names(measurement)) {
    from_range <- fraction_range_matrix(measurement$fraction_range)
    measurement$matrix <- ifelse(is.na(from_range), measurement$matrix, from_range)
  }
  measurement
}
