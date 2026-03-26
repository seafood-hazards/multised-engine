library(tidyverse)
library(readxl)

col_names <- c("site_code", "site_name", "label", "site_type", "activity_id", "activity_name", "client", "contractor", "param_id", "param_name", "cas_no", "medium_id", "medium_name", "taxon_id", "scientific_name", "sample_method", "analysis_method", "sample_time", "upper_depth", "lower_depth", "depth_unit", "is_filtered", "exclude_class", "operator", "value", "list_name", "unit", "sample_no", "lod", "loq", "origin", "n_values", "comment", "archive", "product_desc", "utm33_x", "utm33_y")

df_translated <- list()
df_translated[["interest"]] <- tribble(
  ~param_id, ~param_name,
  "CU",      "Copper",
  "ZN",      "Zinc",
  "MN",      "Manganese",
  "CO",      "Cobalt",
  "MO",      "Molybdenum",
  "SE",      "Selenium"
)

df_translated[["others"]] <- tribble(
  ~param_id, ~param_name,
  "PB",      "Lead",
  "FE",      "Iron",
  "AL",      "Aluminium",
  "NI",      "Nickel",
  "CD",      "Cadmium",
  "AS",      "Arsenic",
  "CR",      "Chromium",
  "MN",      "Manganese",
  "AG",      "Silver",
  "BA",      "Barium",
  "LI",      "Lithium",
  "BE",      "Beryllium",
  "SR",      "Strontium",
  "V",       "Vanadium",
  "P-TOT",   "Total Phosphorus",
  "K",       "Potassium",
  "CR6",     "Chromium (VI)",
  "SI",      "Silicon",
  "CA",      "Calcium",
  "TI",      "Titanium",
  "NA",      "Sodium",
  "S",       "Sulfur",
  "SC",      "Scandium",
  "Y",       "Yttrium",
  "CE",      "Cerium",
  "MG",      "Magnesium",
  "ZR",      "Zirconium",
  "CR3",     "Chromium (III)",
  "B",       "Boron"
)

df_translated[["toc"]] <- tribble(
  ~param_id, ~param_name,
  "TOC",     "Total Organic Carbon (TOC)",
  "TOC63",   "Normalized TOC",
  "TC",      "Total Carbon",
  "S",       "Sulfur",
  "TIC",     "Total Inorganic Carbon"
)

df_translated[["particle"]] <- tribble(
  ~param_id,       ~param_name,
  "TS",            "Total Solids (Dry Matter)",
  "GSMF2_63",      "Particle fraction 2 - 63 µm",
  "GSMF_2000",     "Particle fraction > 2000 µm",
  "GSMF125_250",   "Particle fraction 125 - 250 µm",
  "GSMF1000_2000", "Particle fraction 1000 - 2000 µm",
  "GSMF250_500",   "Particle fraction 250 - 500 µm",
  "GSMF63_125",    "Particle fraction 63 - 125 µm",
  "GSMF500_1000",  "Particle fraction 500 - 1000 µm",
  "GSMF_63",       "Particle fraction > 63 µm",
  "GSMF2",         "Particle fraction < 2 µm",
  "FINS",          "Fines < 63 µm",
  "T-GR",          "Total Residue on Ignition (Ash)"
)

read_vannmiljo_excel <- function(excel_file, data_sheet, data_range) {
  df <- readxl::read_excel(excel_file,
                           sheet = data_sheet,
                           range = data_range,
                           col_types = "text")
  colnames(df) <- col_names

  df
}

correct_vannmiljo_data <- function(df, param_type) {
  df %>%
    mutate(contractor = ifelse((is.na(contractor) | (contractor == "UKJENT")), "Unknown", contractor),
           client = ifelse((is.na(client) | (client == "0") | (client == "UKJENT")), "Unknown", client),
           sample_method = ifelse((is.na(sample_method) | (sample_method == "UKJENT")), "Unknown", sample_method),
           analysis_method = ifelse((is.na(analysis_method) | (analysis_method == "UKJENT")), "Unknown", analysis_method),
           upper_depth = ifelse(is.na(upper_depth), 0.0, as.numeric(upper_depth)),
           lower_depth = ifelse(is.na(lower_depth), 0.0, as.numeric(lower_depth)),
           filtered = ifelse(is_filtered == "Filtrert", TRUE, FALSE),
           utm33_x = round(as.numeric(utm33_x), 4),
           utm33_y = round(as.numeric(utm33_y), 4),
           archive = ifelse(archive == "j", TRUE, FALSE),
           n_values = as.integer(n_values),
           value = as.numeric(value)) %>%
    inner_join(df_translated[[param_type]] %>% select(param_id, x = param_name),
               by = "param_id") %>%
    mutate(param_name = x) %>%
    dplyr::select(-c(x))

}
