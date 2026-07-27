# ── Clean stage: shared element metadata ─────────────────────────────────────
# Canonical name + CAS number per chemistry symbol, applied by every source's
# 01_harmonise.R so the clean `element` table carries uniform values across
# sources. The chemistry rows (7 targets + FE/AL + organic carbon) get a single
# canonical Title-Case name and CAS; grain-size composition symbols differ per
# source and keep their own descriptive label (CAS NULL, they are not chemicals).
#
# CAS numbers match Vannmiljo's `cas_no` for the eight it carries (AL, FE, CO, CU,
# MN, MO, SE, ZN); iodine (only in ICES-DOME) is added from the standard registry.
# Organic carbon (CORG / TOC63) is a measurand, not a compound, so its CAS is NULL.

element_meta <- tibble::tribble(
  ~symbol, ~name,                  ~cas,
  "CO",    "Cobalt",               "7440-48-4",
  "CU",    "Copper",               "7440-50-8",
  "I",     "Iodine",               "7553-56-2",
  "MN",    "Manganese",            "7439-96-5",
  "MO",    "Molybdenum",           "7439-98-7",
  "SE",    "Selenium",             "7782-49-2",
  "ZN",    "Zinc",                 "7440-66-6",
  "FE",    "Iron",                 "7439-89-6",
  "AL",    "Aluminium",            "7429-90-5",
  "CORG",  "Total Organic Carbon", NA_character_,
  "TOC63", "Normalized TOC",       NA_character_
)

# Rename the name column `element` -> `name`, overlay the canonical name + CAS on
# the chemistry rows (composition rows keep their source name and get CAS NULL),
# and return the uniform column set: symbol, name, category, cas.
apply_element_meta <- function(element_df) {
  element_df |>
    dplyr::rename(name = element) |>
    dplyr::left_join(element_meta, by = "symbol", suffix = c("_src", "")) |>
    dplyr::mutate(name = dplyr::coalesce(name, name_src)) |>
    dplyr::select(symbol, name, category, cas)
}
