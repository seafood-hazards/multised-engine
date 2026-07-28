# ── Clean stage: shared sediment-fraction metadata ───────────────────────────
# Turns the raw ICES `matrix` code (the sediment fraction a chemistry value was
# measured on) into two user-facing columns on `measurement`:
#   frac_class  'bulk'   -- whole sample / <2mm  (SEDtot, or a cutoff >= 1000 um)
#               'sieved' -- a fine sub-fraction  (cutoff < 1000 um, e.g. <63 um)
#   sieve_um    the sieve cutoff in um for sieved rows (63 / 62 / 20 / 90 / 500),
#               NULL for bulk.
# A missing matrix (Mareano / Vannmiljø, whole-sample sources; a handful of stray
# nulls elsewhere) is taken as bulk. Because bulk/sieved is chosen per analysis and
# so varies between measurements of one subsample, it lives on `measurement`; a
# per-subsample summary (bulk / sieved / mixed) is derived from the target rows for
# convenient filtering. `matrix` is dropped once converted (fully recovered by the
# two columns; only the SEDtot-vs-assumed-bulk provenance is not distinguished).

# common measurement column set (target + reference), and the organic_carbon table
MEASUREMENT_COLS <- c("measurement_id", "subsample_id", "symbol", "value", "unit",
                      "value_std", "unit_std", "value_sd", "n_rep", "value_uncrt",
                      "frac_class", "sieve_um", "method_id")

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

# add frac_class / sieve_um from matrix, then drop matrix (absent matrix = all bulk)
apply_fraction <- function(measurement) {
  mx <- if ("matrix" %in% names(measurement)) measurement$matrix else NA_character_
  fr <- classify_fraction(mx)
  measurement$frac_class <- fr$frac_class
  measurement$sieve_um   <- fr$sieve_um
  measurement$matrix     <- NULL
  measurement
}

# per-subsample summary from the TARGET rows: bulk / sieved / mixed, and the sieve
# cutoff where unambiguous. Subsamples with no target chemistry get NULL.
summarise_fraction <- function(measurement, element) {
  tgt <- element$symbol[element$category == "target"]
  measurement |>
    dplyr::filter(symbol %in% tgt) |>
    dplyr::group_by(subsample_id) |>
    dplyr::summarise(
      frac_class = dplyr::if_else(dplyr::n_distinct(frac_class) > 1, "mixed",
                                  dplyr::first(frac_class)),
      sieve_um   = dplyr::if_else(dplyr::n_distinct(sieve_um) == 1,
                                  dplyr::first(sieve_um), NA_real_),
      .groups = "drop")
}

# replace any existing frac_class / sieve_um on subsample with the target summary
attach_subsample_fraction <- function(subsample, measurement, element) {
  s <- dplyr::select(subsample, -dplyr::any_of(c("frac_class", "sieve_um")))
  dplyr::left_join(s, summarise_fraction(measurement, element), by = "subsample_id")
}
