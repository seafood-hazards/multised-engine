# ── Clean stage shared helper: matrix_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/matrix_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared matrix metadata ──────────────────────────────────────
# Harmonises the measurement `matrix` column (the sediment fraction the chemistry
# was measured on) to one common vocabulary, the ICES `SED<µm>` codes:
#   - ICES-DOME / MUDAB already use it (SEDtot, SED2000, SED1000, SED500, SED90,
#     SED63, SED62, SED20) and pass through; MUDAB's stray `PK_default` sentinel
#     (matrix unrecorded) is nulled;
#   - 4Demon's two native codes are remapped: FS = fine sediment (<63 µm) -> SED63,
#     US = unsieved / bulk sediment -> SEDtot;
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

standardise_matrix <- function(measurement) {
  if (!"matrix" %in% names(measurement)) return(measurement)   # Mareano / Vannmiljø
  mapped <- unname(matrix_canon[measurement$matrix])
  # keep the original where the code is not in the remap table (already ICES / NA)
  measurement$matrix <- ifelse(measurement$matrix %in% names(matrix_canon),
                               mapped, measurement$matrix)
  measurement
}
