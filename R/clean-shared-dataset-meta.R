# ── Clean stage shared helper: dataset_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/dataset_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared dataset metadata ─────────────────────────────────────
# Standardises each source's `dataset` table to a common column set and fills the
# provenance columns. Existing per-source values are carried into the shared
# columns (NA where a source lacks one); comma-joined country/institute lists
# (ICES-DOME, where a programme spans many nations/labs) are de-duplicated and
# sorted, kept for back-tracing. `url` + `accessed` come from the lookup below;
# `source_type` is "database" for every current source (may gain "paper"/"website"
# later); `doi` is NULL for now.

dataset_meta <- tibble::tribble(
  ~source,     ~url,                                                    ~accessed,
  "Mareano",   "https://mareano.no",                                    "2026-02-04",
  "Vannmilj\u00f8", "https://vannmiljo.miljodirektoratet.no",                "2026-03-24",
  "ICES-DOME", "https://www.ices.dk/data/data-portals/Pages/DOME.aspx", "2026-04-13",
  "MUDAB",     "https://www.mudab.de",                                  "2026-04-29",
  "4Demon",    "https://www.vliz.be/projects/4demon",                   "2026-05-05"
)

DATASET_COLS <- c(
  "dataset_id", "dataset_name", "dataset_code", "dataset_group",
  "pressure_class",
  "source", "source_type", "url", "doi", "country", "region",
  "institute", "institute_code", "accessed")

# De-duplicate a comma-joined value ("a, a, b" -> "a, b", sorted); single values
# and NA pass through unchanged.
dedup_list <- function(x) {
  vapply(x, function(v) {
    if (is.na(v)) return(NA_character_)
    parts <- trimws(strsplit(v, ",", fixed = TRUE)[[1]])
    parts <- parts[parts != ""]
    if (!length(parts)) return(NA_character_)
    paste(sort(unique(parts)), collapse = ", ")
  }, character(1), USE.NAMES = FALSE)
}

# Add any missing common columns (NA), set source_type / doi, de-duplicate the
# country / institute lists, fill url + accessed from the lookup, and return the
# columns in the common order.
standardise_dataset <- function(dataset) {
  d <- dataset
  for (col in DATASET_COLS)
    if (!col %in% names(d)) d[[col]] <- NA_character_
  d |>
    dplyr::mutate(
      source_type = "database",
      doi         = NA_character_,
      country     = dedup_list(country),
      institute   = dedup_list(institute)) |>
    dplyr::select(-url, -accessed) |>
    dplyr::left_join(dataset_meta, by = "source") |>
    dplyr::select(dplyr::all_of(DATASET_COLS))
}
