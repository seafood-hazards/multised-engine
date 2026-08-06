# ── Clean stage shared helper: element_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/element_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared element metadata ─────────────────────────────────────
# Canonical name (+ CAS for chemistry) per symbol, applied by every source's
# 01_harmonise.R so the clean `element` table carries uniform values across
# sources.
#
# Chemistry rows (7 targets + FE/AL + organic carbon) get a single canonical
# Title-Case name and CAS. CAS numbers match Vannmiljo's `cas_no` for the eight it
# carries (AL, FE, CO, CU, MN, MO, SE, ZN); iodine (only in ICES-DOME) is added
# from the standard registry. Organic carbon (CORG / TOC63) is a measurand, not a
# compound, so its CAS is NULL.
#
# Grain-size composition names follow ICES-DOME (the naming reference): any source
# whose composition symbol appears in the ICES set below takes the ICES name, so
# shared symbols read identically (e.g. Vannmiljo `GSMF2`). Source-specific symbols
# that ICES does not use (Mareano's CLAY/SILT/SAND/GRAVEL, Vannmiljo's `_`-forms
# like `GSMF_63` = ">63µm") keep their own label. Composition CAS is NULL.

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

# ICES-DOME grain-size composition symbol -> canonical name (naming reference).
composition_meta <- tibble::tribble(
  ~symbol,         ~name,
  "GS>1000<2000",  "Grain Size Mass Fraction Range >1000 micron - <2000",
  "GS>125<250",    "Grain Size Mass Fraction Range >125 micron - <250",
  "GS>2000<4000",  "Grain Size Mass Fraction Range >2000 micron - <4000",
  "GS>200<600",    "Grain Size Mass Fraction Range >200 micron - <600",
  "GS>20<60",      "Grain Size Mass Fraction Range >20 micron - <60",
  "GS>250<500",    "Grain Size Mass Fraction Range >250 micron - <500",
  "GS>4000<8000",  "Grain Size Mass Fraction Range >4000 micron - <8000",
  "GS>500<1000",   "Grain Size Mass Fraction Range >500 micron - <1000",
  "GS>600<2000",   "Grain Size Mass Fraction Range >600 micron - <2000",
  "GS>60<200",     "Grain Size Mass Fraction Range >60 micron - <200",
  "GS>63<125",     "Grain Size Mass Fraction Range >63 micron - <125",
  "GS>63<2000",    "Grain Size Mass Fraction Range >63 micron - <2000 (sand)",
  "GSMF1",         "Grain Size Mass Fraction <1 micron",
  "GSMF1000",      "Grain Size Mass Fraction <1000 micron",
  "GSMF105",       "Grain Size Mass Fraction <105 micron",
  "GSMF1200",      "Grain Size Mass Fraction <1200 micron",
  "GSMF125",       "Grain Size Mass Fraction <125 micron",
  "GSMF15",        "Grain Size Mass Fraction <15 micron",
  "GSMF150",       "Grain Size Mass Fraction <150 micron",
  "GSMF16",        "Grain Size Mass Fraction <16 micron",
  "GSMF1700",      "Grain Size Mass Fraction <1700 micron",
  "GSMF2",         "Grain Size Mass Fraction <2 micron",
  "GSMF20",        "Grain Size Mass Fraction <20 micron",
  "GSMF200",       "Grain Size Mass Fraction <200 micron",
  "GSMF2000",      "Grain Size Mass Fraction <2000 micron",
  "GSMF210",       "Grain Size Mass Fraction <210 micron",
  "GSMF250",       "Grain Size Mass Fraction <250 micron",
  "GSMF3",         "Grain Size Mass Fraction <3 micron",
  "GSMF300",       "Grain Size Mass Fraction <300 micron",
  "GSMF31",        "Grain Size Mass Fraction <31 micron",
  "GSMF4",         "Grain Size Mass Fraction <4 micron",
  "GSMF420",       "Grain Size Mass Fraction <420 micron",
  "GSMF50",        "Grain Size Mass Fraction <50 micron",
  "GSMF500",       "Grain Size Mass Fraction <500 micron",
  "GSMF53",        "Grain Size Mass Fraction <53 micron",
  "GSMF600",       "Grain Size Mass Fraction <600 micron",
  "GSMF63",        "Grain Size Mass Fraction <63 micron (silt/clay)",
  "GSMF630",       "Grain Size Mass Fraction <630 micron",
  "GSMF7",         "Grain Size Mass Fraction <7 micron",
  "GSMF75",        "Grain Size Mass Fraction <75 micron",
  "GSMF8",         "Grain Size Mass Fraction <8 micron",
  "GSMF850",       "Grain Size Mass Fraction <850 micron",
  "GSMF90",        "Grain Size Mass Fraction <90 micron",
  "GSMF>2000",     "Grain Size Mass Fraction >2000 micron (gravel)",
  "GSMF>8000",     "Grain Size Mass Fraction >8000 micron"
)

# Rename the name column `element` -> `name`, overlay the canonical chemistry name
# + CAS and the ICES composition name (priority: chemistry, then ICES composition,
# else the source's own name), and return the uniform columns: symbol, name,
# category, cas. Composition symbols not in the ICES set keep their source name and
# get CAS NULL.
apply_element_meta <- function(element_df) {
  element_df |>
    dplyr::rename(name = element) |>
    dplyr::left_join(element_meta, by = "symbol", suffix = c("_src", "")) |>
    dplyr::left_join(dplyr::rename(composition_meta, name_ices = name), by = "symbol") |>
    dplyr::mutate(name = dplyr::coalesce(name, name_ices, name_src)) |>
    dplyr::select(symbol, name, category, cas)
}
