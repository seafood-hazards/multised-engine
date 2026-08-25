# ── Export, refined generation: EFSA submission table ────────────────────────
# The superset of the two things EFSA asked for, which are not the same thing:
#
#   1. docs/ReplyFHF_TypeDataForEFSA.md, the data-extraction spec for EFSA's
#      systematic review. Defines "Extraction class" and "pH of porewater".
#   2. "EFSA form-reporting-tool-trace-elements-IMR.xlsx", the submission workbook
#      itself. Has phSed / phWater and no extraction field at all.
#
# The workbook's column order is reproduced exactly, so a submitter can paste the
# block straight into its `dataReported` sheet, and the fields only the ReplyFHF
# spec asks for follow after it. Term codes come from the workbook's own catalogue
# sheets (PARAM, UNIT, EXPRRES, MTX, YESNO, ANLYMD), not from memory.
#
# It derives nothing: scope, references and verdicts all come from
# refined_export_base(), the same frame the flat dataset is cut from, so the two
# cannot disagree. That means the refined background analyses must have run first,
# exactly as for the flat dataset.
#
# Output -> <out_dir>/download/ :
#   multised_efsa_submission.tsv.gz     one row per target measurement
#   efsa_submission_dictionary.csv      column -> EFSA field, catalogue, how it is filled

# ── 1. EFSA catalogue codes ──────────────────────────────────────────────────
# Copied from the workbook's catalogue sheets. Frozen here rather than read from the
# xlsx at run time: the workbook is a raw input that may be replaced by a new version,
# and a submission table must not change shape because someone downloaded a new form.

# PARAM catalogue: the element itself
efsa_trace_el <- c(CO = "RF-00000161-CHE", CU = "RF-00000167-CHE",
                   I  = "RF-00000050-CHE", MN = "RF-00000176-CHE",
                   MO = "RF-00000179-CHE", SE = "RF-00000184-CHE",
                   ZN = "RF-00000205-CHE")

# PARAM catalogue: the "(Total)" speciation, which is what a sediment digest measures.
# Iodine has no code: the workbook leaves I (Total) blank and notes "check CAS number,
# ECHA". That is EFSA's own gap, so the cell is left empty rather than invented.
efsa_spec_code <- c(CO = "RF-00000162-CHE", CU = "RF-00000168-CHE",
                    I  = NA_character_,     MN = "RF-00000177-CHE",
                    MO = "RF-00000180-CHE", SE = "RF-00000186-CHE",
                    ZN = "RF-00000206-CHE")

efsa_el_text <- c(CO = "Co", CU = "Cu", I = "I", MN = "Mn",
                  MO = "Mo", SE = "Se", ZN = "Zn")

# ANLYMD catalogue. Our method vocabulary is the ICES one (see
# clean-shared-method-meta.R); anything with no EFSA equivalent becomes "Other", which
# the workbook allows on condition the real method is named in `comments`.
efsa_meth_an <- c(
  "ICP-MS"     = "F064A", "ICP-MS-CC" = "F064A", "ICP-MS-WC" = "F064A",
  "ICP-SFMS"   = "F064A", "MS-SIM"    = "F064A",
  "ICP-OES"    = "F057A",
  "AAS"        = "F350A", "AAS-AA"    = "F350A", "AAS-FL"    = "F350A",
  "AAS-LS"     = "F350A",
  "AAS-GF"     = "F054A",
  "XRF"        = "F832A")
efsa_meth_text <- c(
  "F064A" = "ICP-MS", "F057A" = "ICP-AES", "F350A" = "FAAS",
  "F054A" = "ETAAS (GFAAS)", "F832A" = "WD-XRFS")

EFSA_ENV_COMP      <- "marine sediment"
EFSA_ENV_COMP_CODE <- "A198T#F34.A16YY"   # MTX: Sediment, HOST-SAMPLED = Seawater
EFSA_UNIT_CONC     <- "mg/kg"
EFSA_UNIT_CONC_CODE<- "G061A"             # UNIT
EFSA_UNIT_PCT_CODE <- "G138A"             # UNIT, percent (ocSed / TextureSed)
EFSA_WEIGHT        <- "dw"
EFSA_WEIGHT_CODE   <- "B002A"             # EXPRRES, dry weight

# ── 2. Field derivations ─────────────────────────────────────────────────────

#' EFSA's ordinal sediment-sample depth
#'
#' Three ranges, keyed on the TOP of the layer. The spec prefers the upper 5 cm as the
#' match for its PEC scenario, so where a layer starts governs which band it belongs to.
#' @noRd
efsa_depth_range <- function(depth_from) {
  ifelse(is.na(depth_from), NA_character_,
         ifelse(depth_from < 5, "0-5 cm",
                ifelse(depth_from <= 40, "5-40 cm", ">40 cm")))
}

#' Coordinates in the workbook's "decimal degrees, hemisphere" form
#' @noRd
efsa_coords <- function(lat, lon) {
  ifelse(is.na(lat) | is.na(lon), NA_character_,
         sprintf("%.5f %s; %.5f %s",
                 abs(lat), ifelse(lat >= 0, "N", "S"),
                 abs(lon), ifelse(lon >= 0, "E", "W")))
}

#' Yes/No in the YESNO catalogue's single-letter form, NA-preserving
#' @noRd
efsa_yn <- function(x) ifelse(is.na(x), NA_character_, ifelse(x, "Y", "N"))

export_efsa_submission <- function(db_dir = multised_db_dir(),
                                   out_dir = multised_analysis_dir(),
                                   verbose = TRUE) {
  out_dir_root <- out_dir
  out_dir <- file.path(out_dir, "download")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  base <- refined_export_base(db_dir = db_dir, analysis_dir = out_dir_root)

  df <- base |>
    mutate(
      # ── identity ──────────────────────────────────────────────────────────
      # sampleId is the sampling occasion and layer; recId adds the measurand, which
      # is the workbook's own convention ("Korsfjorden I" / "Korsfjorden I_Cu (Total)").
      spec_text = paste0(unname(efsa_el_text[element]), " (Total)"),
      sampleId  = sprintf("%s_%.3f_%.3f_%s_%s-%s", source, latitude, longitude,
                          ifelse(is.na(year), "NA", as.character(year)),
                          ifelse(is.na(depth_from_cm), "NA", as.character(depth_from_cm)),
                          ifelse(is.na(depth_to_cm), "NA", as.character(depth_to_cm))),
      recId     = paste0(sampleId, "_", spec_text),

      envComp     = EFSA_ENV_COMP,
      envCompCode = EFSA_ENV_COMP_CODE,

      # ── pristine ──────────────────────────────────────────────────────────
      # EFSA asks for a local-background enrichment factor and warns against Turekian
      # and Wedepohl reference values, which is what pristine_ef already is. It exists
      # only where aluminium predicts the metal (D4), so most rows are empty rather
      # than "No": an absent verdict is not a finding of non-pristine.
      pristineLoc = efsa_yn(pristine_ef),

      sampleLocGC = efsa_coords(latitude, longitude),
      sampleLocCM = ifelse(is.na(country) & is.na(municipality), NA_character_,
                           paste0(ifelse(is.na(country), "", country),
                                  ifelse(is.na(municipality), "",
                                         paste0(", ", municipality)))),
      # the spec accepts the year alone, and asks for the full date only where a point
      # was sampled repeatedly; `date` is populated for some sources and not others.
      sampleDate  = ifelse(!is.na(date) & nzchar(date), date, as.character(year)),

      traceElText = unname(efsa_el_text[element]),
      traceElCode = unname(efsa_trace_el[element]),
      specText    = spec_text,
      specCode    = unname(efsa_spec_code[element]),

      conc        = value_mgkg,
      unitText    = EFSA_UNIT_CONC,  unitCode   = EFSA_UNIT_CONC_CODE,
      weightText  = EFSA_WEIGHT,     weightCode = EFSA_WEIGHT_CODE,

      methAnCode  = unname(efsa_meth_an[method]),
      methAnText  = ifelse(is.na(methAnCode), "Other",
                           unname(efsa_meth_text[methAnCode])),

      # the limits are held in mg/kg from clean step 1 onward (limit_unit), matching
      # conc, so no conversion is needed here. LOD is reported where present; the spec
      # says to fall back to LOQ and say so in the notes.
      LOD = lod, LOQ = loq,

      # accLab is Y for "yes" and for "partly", since EFSA counts a lab running
      # QA/QC as accredited and a partly accredited lab holds the accreditation;
      # it is the parameter coverage that is partial. Empty where the source does
      # not say, which is ICES-DOME, Vannmiljo and 4Demon entirely.
      accLab = accreditation_efsa_yn(accredited),

      # ── not available ─────────────────────────────────────────────────────
      # phSed / phWater: no source has porewater pH and the one sediment pH series
      # is 22 ICES rows outside this scope (docs/efsa-submission.md section 5).
      # hardWater / DOC: water-column measurands, not sediment.
      phSed = NA_real_, phWater = NA_real_,
      hardWater = NA_character_, DOC = NA_real_,

      # clay and silt are not separable in refined: it carries fines_lt63, the combined
      # sub-63 micrometre share, not the grain-size fractions. Sand is its complement.
      TextureSedClay = NA_real_, TextureSedSilt = NA_real_,
      TextureSedSand = ifelse(is.na(fines_pct), NA_real_, round(100 - fines_pct, 1)),
      unitText2 = ifelse(is.na(TextureSedSand), NA_character_, "%"),
      unitCode2 = ifelse(is.na(TextureSedSand), NA_character_, EFSA_UNIT_PCT_CODE),
      weightText2 = ifelse(is.na(TextureSedSand), NA_character_, EFSA_WEIGHT),
      weightCode2 = ifelse(is.na(TextureSedSand), NA_character_, EFSA_WEIGHT_CODE),

      # organic carbon: the spec wants TOC%, the database holds mg/kg
      ocSed     = ifelse(is.na(corg_mgkg), NA_real_, round(corg_mgkg / 1e4, 3)),
      unitText3 = ifelse(is.na(ocSed), NA_character_, "%"),
      unitCode3 = ifelse(is.na(ocSed), NA_character_, EFSA_UNIT_PCT_CODE),
      weightText3 = ifelse(is.na(ocSed), NA_character_, EFSA_WEIGHT),
      weightCode3 = ifelse(is.na(ocSed), NA_character_, EFSA_WEIGHT_CODE),
      unitText5 = NA_character_, unitCode5 = NA_character_,

      # whether the submitter may publish is theirs to state, not ours to assume
      publicData = NA_character_, refPublication = NA_character_,
      comments = ifelse(methAnText == "Other" & !is.na(method) & method != "unknown",
                        paste0("Analytical method reported as: ", method), NA_character_),

      # ── the ReplyFHF-only fields ──────────────────────────────────────────
      extractionClass = extraction_class,
      extractionCode  = extraction,
      depthRange   = efsa_depth_range(depth_from_cm),
      # the spec counts a < 20 micrometre sieve as "sieve < 63", and treats an
      # unsieved sample as bulk. The test is the CUTOFF, not merely "was it sieved":
      # 31 rows are sieved at 90 or 500 micrometre, which is neither a < 63 fraction
      # nor an unsieved one, and answering Y to sieve63 for them would tell EFSA the
      # sample was finer than it is. Both answers are N there, and `fraction` carries
      # the actual cutoff for a reviewer who wants it.
      sieve63      = efsa_yn(fraction != "bulk" & sieve_um_std <= 63),
      bulkAnalysis = efsa_yn(fraction == "bulk"),
      # whether that answer was read off the source or inferred from its silence.
      # Most "bulk" is the latter, and a submitter should be able to see which.
      fracBasis    = fraction_basis,
      SD           = value_sd,
      nReplicates  = n_rep,
      confidential = NA_character_) |>
    select(
      # the workbook's `dataReported` column order, unchanged
      sampleId, recId, envComp, pristineLoc, sampleLocGC, sampleLocCM, sampleDate,
      traceElText, traceElCode, specText, specCode, conc, unitText, unitCode,
      weightText, weightCode, methAnText, methAnCode, LOD, LOQ, accLab, phSed,
      TextureSedClay, TextureSedSilt, TextureSedSand, unitText2, unitCode2,
      weightText2, weightCode2, ocSed, unitText3, unitCode3, weightText3,
      weightCode3, phWater, hardWater, DOC, unitText5, unitCode5, publicData,
      refPublication, comments,
      # then what only the ReplyFHF spec asks for, plus the provenance a reviewer needs
      envCompCode, extractionCode, extractionClass, depthRange, depth_from_cm,
      depth_to_cm, sieve63, bulkAnalysis, fracBasis, SD, nReplicates, confidential,
      source, fraction, dist_to_coast_km, dist_to_aquaculture_km,
      dist_to_fish_farm_km, fish_farm_band, pressure_class, igeo, igeo_class,
      sea_name) |>
    arrange(traceElText, source, sampleId)

  tsv_path <- file.path(out_dir, "multised_efsa_submission.tsv.gz")
  write_tsv(df, tsv_path, na = "")

  dict <- tribble(
    ~column,           ~efsa_field,                          ~catalogue, ~filled_from,
    "sampleId",        "Sample Identifier",                  "",         "source, coordinates, year and layer, which together identify one sampling occasion",
    "recId",           "Record Identifier",                  "",         "sampleId plus the measurand, the workbook's own convention",
    "envComp",         "Environmental Compartment",          "MTX",      "constant: marine sediment",
    "pristineLoc",     "Pristine Location",                  "YESNO",    "pristine_ef, the local-background EF<1 verdict; empty where no verdict exists (D4)",
    "sampleLocGC",     "Sampling Location Geographical Coordinates", "", "site latitude and longitude, decimal degrees",
    "sampleLocCM",     "Sampling Location Country, Municipality", "",    "site country and municipality, from the geo-enrichment step",
    "sampleDate",      "Sampling Date",                      "",         "event date where the source gives one, else the year",
    "traceElText",     "Trace Element",                      "PARAM",    "element symbol",
    "traceElCode",     "Trace Element (code)",               "PARAM",    "catalogue term for the element",
    "specText",        "Speciation",                         "PARAM",    "always the (Total) form: a sediment digest measures total",
    "specCode",        "Speciation (code)",                  "PARAM",    "catalogue term; EMPTY FOR IODINE, which the workbook itself leaves blank",
    "conc",            "Measured Concentration",             "",         "value_std, the standardised concentration",
    "unitText",        "unit",                               "UNIT",     "constant: mg/kg",
    "unitCode",        "unit (code)",                        "UNIT",     "constant: G061A",
    "weightText",      "Expression of product",              "EXPRRES",  "constant: dry weight",
    "weightCode",      "Expression of product (code)",       "EXPRRES",  "constant: B002A",
    "methAnText",      "Method of Analysis",                 "ANLYMD",   "method mapped from the ICES vocabulary; Other where EFSA has no equivalent",
    "methAnCode",      "Method of Analysis (code)",          "ANLYMD",   "catalogue term; empty where the method maps to Other",
    "LOD",             "Limit of Detection",                 "",         "method lod, mg/kg",
    "LOQ",             "Limit of Quantification",            "",         "method loq, mg/kg",
    "accLab",          "Accredited Laboratory",              "YESNO",    "Y where the source states the lab was accredited, including partly accredited; N where it states otherwise; empty where it does not say (ICES-DOME, Vannmiljo, 4Demon)",
    "phSed",           "pH of sediment",                     "",         "NOT AVAILABLE: the only sediment pH in the project is 22 ICES rows outside this scope",
    "TextureSedClay",  "Texture, clay",                      "",         "NOT AVAILABLE: refined carries combined fines, not separate grain-size fractions",
    "TextureSedSilt",  "Texture, silt",                      "",         "NOT AVAILABLE: as clay",
    "TextureSedSand",  "Texture, sand",                      "",         "100 minus fines_lt63, the share coarser than 63 micrometre",
    "ocSed",           "Organic matter content",             "",         "organic carbon converted from mg/kg to TOC%",
    "phWater",         "pH of porewater",                    "",         "NOT AVAILABLE: no source holds porewater pH; see docs/efsa-submission.md section 5",
    "hardWater",       "Water hardness",                     "hardWater","NOT AVAILABLE: a water-column measurand",
    "DOC",             "Dissolved organic carbon",           "",         "NOT AVAILABLE: a water-column measurand",
    "publicData",      "Public data",                        "YESNO",    "LEFT EMPTY: whether the data may be published is the submitter's statement, not a derived value",
    "refPublication",  "Reference publication",              "",         "LEFT EMPTY: submitter's to state",
    "comments",        "Notes",                              "",         "names the real analytical method where methAnText is Other and the source records one; empty where the source itself reports the method as unknown, which is most of the Other rows",
    "envCompCode",     "Environmental Compartment (code)",   "MTX",      "constant: A198T#F34.A16YY",
    "extractionCode",  "Extraction (source code)",           "",         "ICES METCX code for the digestion chemistry",
    "extractionClass", "Extraction class",                   "",         "1 strong, 2 milder, 3 weak or none; see inst/extdata/extraction-class/",
    "depthRange",      "Depth of sediment sample",           "",         "EFSA's ordinal band, keyed on the top of the layer",
    "depth_from_cm",   "(supporting) layer top",             "",         "subsample depth_from",
    "depth_to_cm",     "(supporting) layer bottom",          "",         "subsample depth_to",
    "sieve63",         "Sieve <63 um",                       "YESNO",    "Y where the sieve cutoff was 63 um or finer; the spec counts <20 um as <63 um. N for the 31 rows sieved at 90 or 500 um, which are neither <63 nor unsieved: see fraction for the actual cutoff",
    "bulkAnalysis",    "Bulk analysis",                      "YESNO",    "Y where the sample was not sieved",
    "fracBasis",       "(provenance) fraction basis",        "",         "reported = the source stated the sieve or stated that none was used; assumed = the source was silent and bulk was inferred. Most bulk rows are assumed",
    "SD",              "SD",                                 "",         "measurement value_sd where the source reports one",
    "nReplicates",     "(supporting) replicate count",       "",         "measurement n_rep, so a reader can judge whether SD is meaningful",
    "confidential",    "Confidentiality of the data",        "",         "LEFT EMPTY: submitter's to state",
    "source",          "(provenance) source database",       "",         "Mareano, Vannmiljo, ICES-DOME, MUDAB or 4Demon",
    "fraction",        "(provenance) fraction",              "",         "bulk / sieved63 / sieved20",
    "dist_to_coast_km","(provenance) distance to coast",     "",         "supports the spec's offshore-is-pristine judgement, which it says must be case by case",
    "dist_to_aquaculture_km", "(provenance) distance to farm", "",       "nearest marine aquaculture site of any kind; supports the spec's interest in samples near sea cages",
    "dist_to_fish_farm_km", "(provenance) distance to fish farm", "",    "nearest FINFISH farm in sea or offshore cages, the subset the spec is actually about; Norway only",
    "fish_farm_band",  "(provenance) fish farm size",        "",         "size of that nearest fish farm in standard 780 t concessions: small (<=2), medium (<=4), large (>4)",
    "pressure_class",  "(provenance) stated sampling purpose", "",       "why the provider says the sample was taken: aquaculture / pressure / reference / survey / unknown. Vannmiljo only. The aquaculture rows are the monitoring data under sea cages the spec names",
    "igeo",            "(provenance) geo-accumulation index", "",        "log2(conc / (1.5 * local offshore median)) for the same element and fraction. Uses no aluminium, so it covers about 97% of rows where pristineLoc covers 10%. It is NOT a verdict: in bulk it is confounded with grain size",
    "igeo_class",      "(provenance) Igeo class",            "",         "Muller class of igeo, 0 unpolluted to 6 extreme, read against the LOCAL offshore background rather than the continental crust",
    "sea_name",        "(provenance) sea or ocean",          "",         "supports the spec's marine-region field")

  dict_path <- file.path(out_dir, "efsa_submission_dictionary.csv")
  write_csv(dict, dict_path)

  if (verbose) {
    cat("EFSA submission table written to", out_dir, "\n")
    cat(sprintf("  rows %d, columns %d\n", nrow(df), ncol(df)))
    cat("  pristine verdict present on", sum(!is.na(df$pristineLoc)), "rows\n")
    cat("  extraction class recorded (not defaulted) on",
        sum(df$extractionCode != "UNK"), "rows\n")
    cat("  analytical method mapped to an EFSA term on",
        sum(!is.na(df$methAnCode)), "rows\n")
  }

  invisible(out_dir)
}
