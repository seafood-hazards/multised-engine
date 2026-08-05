# ── Pilot step 1, Vannmiljø ──────────────────────────────────────────────────
# Parses the four Vannmiljo Excel exports (target elements, other elements,
# carbon/sulfur, particles) into the pilot tables.
#
# Vannmiljo exports Norwegian column headers and Norwegian parameter names, so
# the helpers below carry the English translations per export and the unit
# translations. Everything is read as text and coerced afterwards, since the
# exports mix numeric and sentinel values in the same column.
#
# `sf` is needed here to reproject the site coordinates from ETRS89 UTM 33N to
# WGS84, so it is guarded.

# Column order of every Vannmiljo export sheet.
VANNMILJO_COLS <- c(
  "site_code", "site_name", "label", "site_type", "activity_id", "activity_name",
  "client", "contractor", "param_id", "param_name", "cas_no", "medium_id",
  "medium_name", "taxon_id", "scientific_name", "sample_method",
  "analysis_method", "sample_time", "upper_depth", "lower_depth", "depth_unit",
  "is_filtered", "exclude_class", "operator", "value", "list_name", "unit",
  "sample_no", "lod", "loq", "origin", "n_values", "comment", "archive",
  "product_desc", "utm33_x", "utm33_y")

# Norwegian -> English parameter names, per export. The join also acts as the
# filter: only these parameters are carried through.
vannmiljo_translations <- function() {
  list(
    interest = tibble::tribble(
      ~param_id, ~param_name,
      "CU",      "Copper",
      "ZN",      "Zinc",
      "MN",      "Manganese",
      "CO",      "Cobalt",
      "MO",      "Molybdenum",
      "SE",      "Selenium"
    ),
    others = tibble::tribble(
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
    ),
    toc = tibble::tribble(
      ~param_id, ~param_name,
      "TOC",     "Total Organic Carbon (TOC)",
      "TOC63",   "Normalized TOC",
      "TC",      "Total Carbon",
      "S",       "Sulfur",
      "TIC",     "Total Inorganic Carbon"
    ),
    particle = tibble::tribble(
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
  )
}

# Norwegian unit strings -> the pipeline's forms ("t.v." = dry weight).
vannmiljo_units <- function() {
  tibble::tribble(
    ~unit,       ~new_unit,
    "%", "%",
    "g/kg", "g/kg",
    "g/kg C t.v.", "g/kg C dw",
    "g/kg P t.v.", "g/kg P dw",
    "mg/kg t.v.", "mg/kg dw",
    "µg/kg t.v.", "µg/kg dw",
  )
}

read_vannmiljo_excel <- function(excel_file, data_sheet, data_range) {
  df <- readxl::read_excel(excel_file,
                           sheet = data_sheet,
                           range = data_range,
                           col_types = "text")
  colnames(df) <- VANNMILJO_COLS
  df
}

correct_vannmiljo_data <- function(df, param_type) {
  df_translated <- vannmiljo_translations()
  df_unit <- vannmiljo_units()
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
    inner_join(df_unit, by = "unit") %>%
    mutate(param_name = x,
           unit = new_unit) %>%
    dplyr::select(-c(x, new_unit))
}

pilot_extract_vannmiljo <- function(raw_dir = multised_raw_dir(), verbose = TRUE) {
  require_suggested(c("readxl", "sf"), "The Vannmiljo pilot parser")

  data_path  <- file.path(raw_dir, "Vannmiljo")
  data_sheet <- "VannmiljoEksport"

  # Each export has a fixed row range, so the sheet is read as a block.
  sources <- tibble::tribble(
    ~type,       ~file,                                  ~range,
    "interest",  "Vannmilio_Elements_interest.xlsx",     "A1:AK61184",
    "others",    "Vannmilio_Elements_others.xlsx",       "A1:AK95215",
    "toc",       "Vannmilio_pH_Carbon_Sulfur_all.xlsx",  "A1:AK42150",
    "particle",  "Vannmilio_Partikler_all.xlsx",         "A1:AK39709")

  paths <- file.path(data_path, sources$file)
  absent <- paths[!file.exists(paths)]
  if (length(absent)) {
    stop("Vannmiljo export(s) not found: ", paste(absent, collapse = ", "),
         call. = FALSE)
  }

  df <- purrr::pmap(sources, function(type, file, range) {
    read_vannmiljo_excel(file.path(data_path, file), data_sheet, range) %>%
      correct_vannmiljo_data(type)
  }) |> bind_rows()

  # ── Activity ───────────────────────────────────────────────────────────────
  df_activity <- df %>% distinct(activity_id, activity_name)

  # ── Client ─────────────────────────────────────────────────────────────────
  df_client <- df %>% distinct(client, archive) %>%
    mutate(client_id = row_number()) %>%
    dplyr::select(client_id, client, archive)

  # ── Contractor ─────────────────────────────────────────────────────────────
  df_contractor <- df %>% distinct(contractor) %>%
    mutate(contractor_id = row_number()) %>%
    dplyr::select(contractor_id, contractor)

  # ── Site ───────────────────────────────────────────────────────────────────
  # EPSG 25833 is the official ETRS89 UTM 33N projection used in Norway
  # (Vannmiljo/Kartverket); transform to WGS84 lon/lat (EPSG 4326).
  df_site <- df %>% distinct(site_code, site_name, label, utm33_x, utm33_y) %>%
    group_by(site_code, site_name, utm33_x, utm33_y) %>%
    mutate(label = paste0(label, collapse = ",")) %>%
    ungroup() %>%
    group_by(site_code) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    sf::st_as_sf(coords = c("utm33_x", "utm33_y"), crs = 25833) %>%
    sf::st_transform(crs = 4326)
  df_site <- df_site %>%
    mutate(
      lat = sf::st_coordinates(df_site)[, "Y"],
      lon = sf::st_coordinates(df_site)[, "X"]
    ) %>%
    sf::st_drop_geometry()

  # ── Sample method ──────────────────────────────────────────────────────────
  df_sample_method <- df %>% distinct(sample_method) %>%
    mutate(method_id = row_number()) %>%
    dplyr::select(method_id, method = sample_method)

  # ── Analysis method ────────────────────────────────────────────────────────
  df_analysis_method <- df %>% distinct(analysis_method, unit) %>%
    mutate(analysis_id = row_number()) %>%
    dplyr::select(analysis_id, analysis = analysis_method, unit)

  # ── Sample ─────────────────────────────────────────────────────────────────
  df_sample <- df %>%
    distinct(activity_id, site_code, client, contractor, sample_time, sample_method, upper_depth, lower_depth, filtered) %>%
    mutate(sample_date = substr(sample_time, 1, 10)) %>%
    group_by(activity_id, site_code, sample_date, upper_depth, lower_depth, filtered) %>%
    mutate(
      seq_number = row_number(),
      sample_id = paste(activity_id, site_code, sample_date, paste(upper_depth, lower_depth, sep = "-"), seq_number, sep = "_"),
      upper_depth = as.numeric(upper_depth),
      lower_depth = as.numeric(lower_depth)
    ) %>%
    ungroup() %>%
    inner_join(df_client, by = "client") %>%
    inner_join(df_contractor, by = "contractor") %>%
    inner_join(df_sample_method, by = c(sample_method = "method")) %>%
    dplyr::select(sample_id, activity_id, site_code, client_id, contractor_id, method_id,
                  upper_depth, lower_depth, sample_time, filtered)

  # ── Parameter ──────────────────────────────────────────────────────────────
  df_parameter <- df %>% distinct(param_id, param_name, cas_no)

  # ── Sediment ───────────────────────────────────────────────────────────────
  df_sediment <- df %>%
    dplyr::select(activity_id, site_code,  sample_time, upper_depth, lower_depth, sample_method, analysis_method, param_id, value, operator, client, contractor, sample_method, unit, sample_no, n_values, lod, loq) %>%
    inner_join(df_client, by = "client") %>%
    inner_join(df_contractor, by = "contractor") %>%
    inner_join(df_sample_method, by = c(sample_method = "method")) %>%
    inner_join(df_analysis_method, by = c(analysis_method = "analysis", "unit")) %>%
    inner_join(df_sample, by = c("activity_id", "site_code", "client_id",
                                 "contractor_id", "method_id", "sample_time",
                                 "upper_depth", "lower_depth")) %>%
    dplyr::select(sample_id, param_id, analysis_id, value, operator, sample_no, n_values, lod, loq) %>%
    group_by(sample_id, param_id) %>%
    mutate(sediment_no = row_number()) %>%
    ungroup() %>%
    dplyr::select(sample_id, param_id, sediment_no, analysis_id, value, operator, sample_no, n_values, lod, loq)

  # ── lld: LOD and LOQ as long rows ──────────────────────────────────────────
  df_lod <- df_sediment %>%
    filter(!is.na(lod)) %>%
    mutate(type = "LOD",
           lod = as.numeric(lod)) %>%
    select(sample_id, param_id, sediment_no, type, value = lod)

  df_loq <- df_sediment %>%
    filter(!is.na(loq)) %>%
    mutate(type = "LOQ",
           loq = as.numeric(loq)) %>%
    select(sample_id, param_id, sediment_no, type, value = loq)

  df_lld <- bind_rows(df_lod, df_loq)

  df_sediment <- df_sediment %>% dplyr::select(-c(lod, loq))

  if (verbose) {
    cat(sprintf("vannmiljo parsed: site %d, sample %d, parameter %d, sediment %d, lld %d\n",
                nrow(df_site), nrow(df_sample), nrow(df_parameter),
                nrow(df_sediment), nrow(df_lld)))
  }

  list(activity        = df_activity,
       client          = df_client,
       contractor      = df_contractor,
       site            = df_site,
       sample_method   = df_sample_method,
       analysis_method = df_analysis_method,
       sample          = df_sample,
       parameter       = df_parameter,
       sediment        = df_sediment,
       lld             = df_lld)
}
