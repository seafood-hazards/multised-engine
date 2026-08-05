# ── Clean stage shared helper: fraction_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/fraction_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared sediment-fraction metadata ───────────────────────────
# Turns the raw ICES `matrix` code (the sediment fraction a chemistry value was
# measured on) into two user-facing columns on `measurement`, alongside the raw
# `matrix` which is kept as provenance:
#   frac_class  'bulk'   -- whole sample / <2mm  (SEDtot, or a cutoff >= 1000 um)
#               'sieved' -- a fine sub-fraction  (cutoff < 1000 um, e.g. <63 um)
#   sieve_um    the sieve cutoff in um for sieved rows (63 / 62 / 20 / 90 / 500),
#               NULL for bulk.
# A missing matrix (Mareano / Vannmiljø, whole-sample sources; a handful of stray
# nulls elsewhere) is taken as bulk. Because bulk/sieved is chosen per analysis and
# so varies between measurements of one subsample, it lives per-row on
# `measurement`; a per-subsample summary is derived from the TARGET rows only
# (target_frac_class / target_sieve_um on subsample) for convenient filtering, so it
# is unaffected by the reference / organic rows sharing the measurement table.

# common measurement column set (target + reference + organic chemistry)
MEASUREMENT_COLS <- c("measurement_id", "subsample_id", "symbol", "value", "unit",
                      "value_std", "unit_std", "value_sd", "n_rep", "value_uncrt",
                      "matrix", "frac_class", "sieve_um", "method_id")

.frac_um <- function(matrix) suppressWarnings(as.integer(sub("^SED", "", matrix)))

classify_fraction <- function(matrix) {
  um <- .frac_um(matrix)                        # SEDtot / non-numeric / NA -> NA
  cls <- dplyr::case_when(
    is.na(matrix)           ~ "bulk",           # no matrix = whole-sample bulk
    matrix == "SEDtot"      ~ "bulk",
    !is.na(um) & um >= 1000 ~ "bulk",           # <=2mm reference sediment
    !is.na(um)              ~ "sieved",
    TRUE                    ~ "bulk")            # any other non-numeric code -> bulk
  tibble::tibble(frac_class = cls,
                 sieve_um   = dplyr::if_else(cls == "sieved", as.numeric(um), NA_real_))
}

# add frac_class / sieve_um from matrix, keeping matrix (absent matrix = all bulk)
apply_fraction <- function(measurement) {
  if (!"matrix" %in% names(measurement)) measurement$matrix <- NA_character_
  fr <- classify_fraction(measurement$matrix)
  measurement$frac_class <- fr$frac_class
  measurement$sieve_um   <- fr$sieve_um
  measurement
}

# per-subsample summary from the TARGET rows only: bulk / sieved / mixed, and the
# sieve cutoff where unambiguous. Subsamples with no target chemistry get NULL.
summarise_fraction <- function(measurement, element) {
  tgt <- element$symbol[element$category == "target"]
  measurement |>
    dplyr::filter(symbol %in% tgt) |>
    dplyr::group_by(subsample_id) |>
    dplyr::summarise(
      target_frac_class = dplyr::if_else(dplyr::n_distinct(frac_class) > 1, "mixed",
                                         dplyr::first(frac_class)),
      target_sieve_um   = dplyr::if_else(dplyr::n_distinct(sieve_um) == 1,
                                         dplyr::first(sieve_um), NA_real_),
      .groups = "drop")
}

# replace any existing target fraction summary on subsample with a fresh one
attach_subsample_fraction <- function(subsample, measurement, element) {
  s <- dplyr::select(subsample, -dplyr::any_of(c("target_frac_class", "target_sieve_um")))
  dplyr::left_join(s, summarise_fraction(measurement, element), by = "subsample_id")
}
