# ── Clean stage: shared method metadata ──────────────────────────────────────
# Standardises the `method` table to a common column set and vocabulary:
#   - grain-size (composition-symbol) methods are dropped (grain-size no longer
#     lives in measurement; grain_size_fraction has no method_id, so nothing is
#     orphaned);
#   - `method` codes are mapped to the ICES-DOME vocabulary (MUDAB already uses it;
#     Mareano ICP-AES -> ICP-OES etc.; Vannmiljø ISO-standard refs -> the technique;
#     4Demon `campaign_technique_fraction` codes -> the technique). Unlisted / NULL
#     -> "unknown";
#   - `method_description` is kept where the source has one (ICES-DOME, MUDAB) and
#     filled from `method_desc` (the ICES wording) for the mapped canonical codes;
#   - `lod` / `loq` are converted to mg/kg (matching value_std) and `limit_unit`
#     set to "mg/kg";
#   - columns: method_id, symbol, method, method_description, lab, lab_name, lod,
#     loq, limit_unit. `comment` (Mareano) and `uncertainty` (MUDAB, unused) drop.

METHOD_COLS <- c("method_id", "symbol", "method", "method_description",
                 "lab", "lab_name", "lod", "loq", "limit_unit")

# raw method -> canonical ICES code (only non-identity mappings need listing;
# codes already in the ICES vocabulary, e.g. AAS / ICP-MS, pass through unchanged)
method_canon <- c(
  # Mareano
  "ICP-AES" = "ICP-OES", "LECO-analyser" = "CNA",
  # Vannmiljø ISO / NS standard references
  "NS-EN ISO 17294-2"      = "ICP-MS", "NS-EN ISO 17294-2:2016" = "ICP-MS",
  "NS-EN ISO 17294-2:2023" = "ICP-MS",
  "NS-EN ISO 11885"        = "ICP-OES", "NS-EN ISO 11885:2009"  = "ICP-OES",
  "NS-EN ISO 15586"        = "AAS-GF",
  "ISO 10694 IR" = "CNA", "ISO 10694 EL" = "CNA", "ISO 10694 GC" = "CNA",
  "NS-EN 13137:2001" = "CNA",
  "NS 4773" = "AAS", "NS 4781" = "AAS",
  "Unknown" = "unknown",
  # 4Demon campaign_technique_fraction codes
  "Monit1_AAS_63" = "AAS", "Monit1_AAS_500" = "AAS", "Monit1_AAS_2000" = "AAS",
  "Grieken_AAS_63" = "AAS", "Grieken_AAS_10000" = "AAS",
  "Monit2_OES_63" = "ICP-OES", "Monit2_OES_2000" = "ICP-OES",
  "Monit3_OES/MS_63" = "ICP-MS", "Monit3_OES/MS_2000" = "ICP-MS",
  "Grieken_XRF_63" = "XRF", "Grieken_XRF_10000" = "XRF", "Grieken_XR_10000" = "XRF",
  "PMPZ_37" = "unknown")

# canonical code -> description (ICES wording), for the codes the mapped sources
# produce; ICES-DOME / MUDAB keep their own method_description.
method_desc <- c(
  "AAS"     = "Atomic Absorption Spectrometry",
  "AAS-GF"  = "Atomic Absorption Spectrometry - graphite furnace",
  "ICP-OES" = "ICP-OES/AES Optical/Atom Emission Spectroscopy with Inductive Coupled Plasma",
  "ICP-MS"  = "Inductive Coupled Plasma-Mass Spectrometry",
  "CNA"     = "Carbon/nitrogen analyser - CHN analyser",
  "XRF"     = "X-ray fluorescence")

# mass basis for converting lod/loq (in limit_unit) to mg/kg
.limit_denom <- c("%" = 1e2, "vol.%" = 1e2, "wt.%" = 1e2, "g/kg" = 1e3,
                  "mg/g" = 1e3, "mg/kg" = 1e6, "ug/g" = 1e6, "ppm" = 1e6,
                  "ug/kg" = 1e9, "ng/g" = 1e9, "ppb" = 1e9)
.canon_unit <- function(u) {
  u <- tolower(trimws(u))
  u <- sub("\\s*(dw|ww)$", "", u)
  gsub("µ|μ", "u", u)
}

standardise_method <- function(method, element) {
  chem_syms <- element$symbol[element$category != "composition"]
  m <- method[method$symbol %in% chem_syms, , drop = FALSE]   # drop grain-size methods

  # method code -> canonical (keep if already an ICES code; NULL -> unknown)
  canon <- unname(method_canon[m$method])
  canon <- ifelse(is.na(canon), m$method, canon)
  canon[is.na(canon)] <- "unknown"
  m$method <- canon

  # description: keep the source's, else fill from the ICES wording
  if (!"method_description" %in% names(m)) m$method_description <- NA_character_
  m$method_description <- dplyr::coalesce(m$method_description,
                                          unname(method_desc[m$method]))

  # ensure the optional columns exist
  for (col in c("lab", "lab_name")) if (!col %in% names(m)) m[[col]] <- NA_character_
  for (col in c("lod", "loq"))      if (!col %in% names(m)) m[[col]] <- NA_real_

  # lod / loq -> mg/kg via the limit_unit mass basis; set limit_unit accordingly
  denom <- unname(.limit_denom[.canon_unit(m$limit_unit)])
  conv  <- 1e6 / denom
  m$lod <- ifelse(!is.na(denom), m$lod * conv, m$lod)
  m$loq <- ifelse(!is.na(denom), m$loq * conv, m$loq)
  m$limit_unit <- ifelse(!is.na(denom), "mg/kg", m$limit_unit)

  dplyr::select(m, dplyr::all_of(METHOD_COLS))
}
