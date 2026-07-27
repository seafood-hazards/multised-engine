# ── Clean stage: shared event metadata ───────────────────────────────────────
# Standardises the `event` table to a common column set and maps the raw sampling
# gear codes to short, source-independent descriptive names. Each source's codes
# either coincide in meaning (e.g. BC = box corer, VV = van Veen grab) or are
# source-unique (Mareano MC, Vannmiljø's NS-EN ISO strings), so one global lookup
# serves all. Codes not listed, and NULL, map to "unknown".
#
# `multi_flag` is dropped (it equals `n_layers > 1`); ICES-DOME's `tool_description`
# is dropped (folded into the descriptive name).

EVENT_COLS <- c("event_id", "dataset_id", "site_id", "year", "date",
                "sampling_tool", "n_layers")

# raw gear code -> short common name
tool_names <- c(
  # grabs
  "VV" = "van Veen grab", "DA" = "Day grab", "GS" = "grab", "OS" = "grab",
  "GR" = "grab", "SH" = "Shipek grab", "EK" = "Ekman grab",
  "BG" = "Backengreifer grab",
  # box corers
  "BC" = "box corer", "RN" = "Rieneck box corer",
  # corers
  "GC" = "gravity corer", "MU" = "multicorer", "BM" = "multicorer",
  "MC" = "multicorer", "HP" = "Haps corer", "NC" = "Niemisto corer",
  "GE" = "Gemini corer", "GX" = "Gemax corer", "KA" = "Kajak corer",
  "HC" = "hand corer", "DC" = "diver corer", "LC" = "liquid CO2 corer",
  "WN" = "Willner corer", "CR" = "CRAIB corer", "OC" = "corer (other)",
  # sediment traps / water
  "SDT-PMP" = "sediment trap (pump)", "SDT-PSV" = "sediment trap (passive)",
  "WAT" = "water sampler",
  # spoons / hand
  "SP" = "spoon", "SPH" = "spoon", "SPM" = "spoon",
  "HAN" = "hand-collected", "DIV" = "hand-collected",
  # explicit unknown
  "UD" = "unknown", "Unknown" = "unknown",
  # Vannmiljø standard references
  "NS-EN ISO 5667-19A" = "box corer",
  "NS-EN ISO 5667-19B" = "van Veen grab",
  "NS-EN ISO 5667-19C" = "tube corer",
  "HAANDCORER" = "hand corer",
  "NS 9410:2016" = "grab", "NS 9410:2007" = "grab")

standardise_event <- function(event) {
  e <- event
  nm <- unname(tool_names[e$sampling_tool])
  nm[is.na(nm)] <- "unknown"          # unlisted codes and NULL -> unknown
  e$sampling_tool <- nm
  dplyr::select(e, dplyr::all_of(EVENT_COLS))
}
