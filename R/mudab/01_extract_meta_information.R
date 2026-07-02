# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/raw/Mudab"
data_file <- file.path(data_path, "export_mudab_V_MESSWERTE_SEDIMENT.csv")
code_file <- file.path(data_path, "MUDAB_CODELISTEN.tsv")

# ------------------------------
# Read the whole data
# ------------------------------
col_translation <- c(
  station_name                    = "Name der Projektstation",
  station_id                      = "ProjektStationID",
  responsible_institute           = "Verantwortliches Institut",
  region                          = "Region",
  institute                       = "Institute",
  latitude                        = "Breitengrad",
  longitude                       = "Längengrad",
  organisation                    = "Organisation",
  project_affiliation             = "Projektzugehörigkeit",
  station_type                    = "Stationstyp",
  water_body_category             = "Gewässerkategorie",
  parameter                       = "Parameter",
  parameter_name                  = "Parametername",
  parameter_group                 = "Parametergruppe",
  cas_number                      = "CAS-Nummer",
  lawa_code                       = "LAWA-Code",
  measured_value                  = "Messwert",
  unit                            = "Einheit",
  year                            = "Jahr",
  measurement_date                = "Datum der Messung",
  measurement_time                = "Uhrzeit der Messung",
  data_qualifier                  = "Qualifizierung Messwert",
  measurement_method_code         = "Code der Messmethode",
  chemical_treatment              = "Chemische Behandlung der Probe",
  physical_treatment              = "Physikalische Behandlung der Probe",
  internal_qa_detection_limit     = "interne QS / Nachweisgrenze",
  internal_qa_quantification_limit = "interne QS / Bestimmungsgrenze",
  measurement_basis               = "Basis der Messung",
  expanded_uncertainty_pct        = "Angabe der erweiterten Messunsicherheit in %",
  uncertainty_method              = "Ermittlungsmethode der Messunsicherheit",
  accreditation                   = "Akkreditierung",
  analytical_laboratory           = "Analyselabor",
  control_chart_type              = "Typ der Kontrollkarte",
  internal_qa_count               = "Messanzahl interne QS",
  measurement_start               = "Beginn der Probenmessung",
  measurement_end                 = "Ende der Probenmessung",
  discipline                      = "Disziplin",
  proficiency_testing             = "Vergleichsprüfung",
  recovery_rate                   = "Wiederfindungsrate",
  reference                       = "Referenz",
  reference_material_code         = "Referenzmaterial Code",
  reference_material_basis        = "Referenzmaterial Basis",
  reference_material_type         = "Referenzmaterial Typ",
  reference_material_sd           = "Referenzmaterial Standardabweichung",
  reference_material_mean         = "Referenzmaterial Mittelwert",
  monitoring_station_name         = "Name der Messstation",
  measurement_depth               = "Messtiefe",
  station_latitude                = "Breitengrad der Messstation",
  station_longitude               = "Längengrad der Messstation",
  measurement_project             = "Messprojekt",
  survey_start                    = "Beginn der Reise",
  survey_end                      = "Ende der Reise",
  vessel_code                     = "Schiffcode",
  platform_type                   = "Typ der Plattform",
  vessel_name                     = "Schiffname",
  sample_id                       = "Proben-ID",
  layer_upper_boundary            = "Schicht - obere Grenze",
  layer_lower_boundary            = "Schicht - untere Grenze",
  sampling_method                 = "Methode der Probenentnahme",
  flag                            = "Flag",
  matrix                          = "Matrix",
  sediment_composition            = "Sedimentzusammensetzung",
  sediment_content                = "Sedimentinhalt",
  sampled_area                    = "Beprobte Fläche",
  storage_method                  = "Lagerungsmethode",
  preservation_method             = "Konservierungsmethode",
  cleaning_procedure              = "Reinigungsverfahren"
)

df_all <- read_csv(data_file, show_col_types = FALSE) |>
  rename(all_of(col_translation)) |>
  select(where(~ !all(is.na(.))))

# ------------------------------
# Create look-up table
# ------------------------------
df_code_list <- read_tsv(code_file) %>%
  fill(Catogory) %>%
  filter(!is.na(Value))

desc_translation <- c(
  "Messwerte Meeressäuger. Spalte: Methode der Altersbestimmung"                                                                        = "Marine mammal measurements. Column: Age determination method",
  "Messwerte Meeressäuger. Spalte: Zustand bei der Probenahme"                                                                          = "Marine mammal measurements. Column: Condition at sampling",
  "Messwerte alle Kompartimente. Spalte: Basis der Messung"                                                                             = "All compartment measurements. Column: Basis of measurement",
  "Messwerte Biologie. Spalte: Datentyp"                                                                                                = "Biology measurements. Column: Data type",
  "Messwerte alle Kompartimente. Spalte: Matrix (für Wasser, Sediment, Biota) und Unterprobe (für Biologie)"                            = "All compartment measurements. Column: Matrix (water, sediment, biota) and sub-sample (biology)",
  "Messwerte alle Kompartimente. Spalte: Ermittlungsmethode der Messunsicherheit"                                                       = "All compartment measurements. Column: Uncertainty determination method",
  "Messwerte alle Kompartimente. Spalte: Chemische Behandlung der Probe"                                                                = "All compartment measurements. Column: Chemical treatment of sample",
  "Messwerte alle Kompartimente. Spalte: Code der Messmethode"                                                                         = "All compartment measurements. Column: Measurement method code",
  "Messwerte alle Kompartimente. Spalte: Physikalische Behandlung der Probe"                                                            = "All compartment measurements. Column: Physical treatment of sample",
  "Projektstation. Spalte MSTAT"                                                                                                        = "Project station. Column: MSTAT",
  "Messwerte alle Kompartimente. Spalte: Einheit"                                                                                       = "All compartment measurements. Column: Unit",
  "Messwerte Meeressäuger. Spalte: Specimen-Herkunft"                                                                                  = "Marine mammal measurements. Column: Specimen origin",
  "Messwerte/Parameter alle Kompartimente. Spalte: Parameter"                                                                           = "All compartment measurements/parameters. Column: Parameter",
  "Messwerte/Parameter alle Kompartimente. Spalte: Parametergruppe"                                                                     = "All compartment measurements/parameters. Column: Parameter group",
  "Messwerte alle Kompartimente. Spalte: Basis der Messung"                                                                             = "All compartment measurements. Column: Quality flag",
  "Messwerte alle Kompartimente. Spalte: Institute"                                                                                     = "All compartment measurements. Column: Institute",
  "Messwerte Biota. Spalte: Referenzliste"                                                                                              = "Biota measurements. Column: Reference list",
  "Messwerte Meeressäuger. Spalte: Sex-Code"                                                                                           = "Marine mammal measurements. Column: Sex code",
  "Messwerte alle Kompartimente. Spalte: Schiffscode"                                                                                   = "All compartment measurements. Column: Vessel code",
  "Messwerte Biologie. Spalte: Größenreferenz"                                                                                         = "Biology measurements. Column: Size reference",
  "Messwerte Biologie. Spalte: Stadium"                                                                                                 = "Biology measurements. Column: Life stage",
  "Messwerte alle Kompartimente. Spalte: Flag"                                                                                          = "All compartment measurements. Column: Flag",
  "Projektstation. Spalte: WLTYP"                                                                                                       = "Project station. Column: WLTYP",
  "Messwerte Meeressäuger. Spalte: Bulking"                                                                                            = "Marine mammal measurements. Column: Bulking",
  "Physikalische Stationsparameter. Spalte: Kompartiment"                                                                               = "Physical station parameters. Column: Compartment",
  "Messwerte Meeressäuger. Spalten: Weiterführende Ergebnisse Patho, Weiterführen…"                                                    = "Marine mammal measurements. Columns: Further pathology results",
  "Projektstation & Messwerte alle Kompartimente. Spalte: Institute & Verantwortliches Institut"                                        = "Project station & all compartment measurements. Column: Institute & responsible institute",
  "Messwerte Biota. Spalte: Längenmessung"                                                                                             = "Biota measurements. Column: Length measurement method",
  "Messwerte alle Kompartimente. Spalte: Medium"                                                                                        = "All compartment measurements. Column: Medium",
  "Messwerte Meeressäuger. Spalte: Altersklasse"                                                                                      = "Marine mammal measurements. Column: Age class",
  "Alle Kompartimente. Spalte: Organisation"                                                                                            = "All compartments. Column: Organisation",
  "Messwerte/Parameter alle Kompartimente. Spalte: Parameter"                                                                           = "All compartment measurements/parameters. Column: Parameter (CAS)",
  "Messwerte alle Kompartimente. Spalte: Typ der Plattform"                                                                            = "All compartment measurements. Column: Platform type",
  "Projektstation. Spalte: Stationstyp"                                                                                                = "Project station. Column: Station type",
  "Messwerte Biologie & Biota. Spalte: Spezie, APHIAID"                                                                                = "Biology & biota measurements. Column: Species, APHIAID"
)

category_lookup <- df_code_list |>
  distinct(Catogory) |>
  mutate(
    # Remove "Code-Liste:     " prefix
    stripped = str_remove(Catogory, "^Code-Liste:\\s+"),

    # Extract category code: first word before whitespace
    category_code = str_extract(stripped, "^\\S+"),

    # Extract description: text after " -   {optional duplicate code} - "
    # If the code appears again after " -   ", skip it; otherwise take directly
    description_raw = str_remove(stripped, "^\\S+\\s+-\\s+") |>
      str_remove(paste0("^", str_extract(stripped, "^\\S+"), "\\s+-\\s+")) |>
      str_trim()
  ) |>
  mutate(
    category_name = desc_translation[description_raw]
  ) |>
  select(category_code, category_name)

code_lookup <- df_code_list |>
  mutate(category_code = str_extract(
    str_remove(Catogory, "^Code-Liste:\\s+"), "^\\S+"
  )) |>
  left_join(category_lookup, by = "category_code") |>
  select(Catogory = category_code, `Category name` = category_name,
         Code = Value, `Code name` = Name)

col_to_codetype <- tribble(
  ~data_col,  ~Catogory,
  "responsible_institute",    "MUDABCL_INSTITUTE",
  "responsible_institute",    "ICESCL_RLABO",
  "institute",    "MUDABCL_INSTITUTE",
  "institute",    "ICESCL_RLABO",
  "organisation", "MUDABCL_ORGANISATION",
  "station_type",    "MUDABCL_STATIONTYPE",
  "parameter",    "ICESCL_PARAM",
  "parameter",    "MUDABCL_PARAMCAS",
  "parameter_group",    "ICESCL_PARAMGROUP",
  "unit",    "ICESCL_MUNIT",
  "data_qualifier",    "ICESCL_QFLAG",
  "measurement_method_code",    "ICESCL_METOA",
  "chemical_treatment",    "ICESCL_METCX",
  "physical_treatment",    "ICESCL_METPT",
  "measurement_basis",    "ICESCL_QFLAG",
  "uncertainty_method",    "ICESCL_METCU",
  "analytical_laboratory",    "MUDABCL_INSTITUTE",
  "analytical_laboratory",    "ICESCL_RLABO",
  "reference_material_basis",   "ICESCL_QFLAG",
  "vessel_code",   "ICESCL_SHIPC",
  "platform_type",   "MUDABCL_PLATFORMTYPE",
  "flag",   "ICESCL_VFLAG",
  "matrix",   "ICESCL_MATRIX"
)

used_codes <- col_to_codetype |>
  mutate(
    Code = map(data_col, \(col) {
      df_all |>
        distinct(across(all_of(col))) |>
        pull(col) |>
        discard(is.na)
    })
  ) |>
  unnest(Code)

df_code_lookup <- code_lookup |>
  semi_join(used_codes, by = c("Catogory", "Code")) |>
  select(category_code = Catogory,
         category_name = `Category name`,
         code = Code,
         code_name = `Code name`)

# ------------------------------
# Station: 482
# ------------------------------
df_station <- df_all %>% distinct(station_name, station_id, responsible_institute, region,
                                  institute, latitude, longitude,
                                  organisation, project_affiliation,
                                  station_type, water_body_category) %>%
  mutate(station_no = row_number()) %>%
  dplyr::select(station_no, station_name, station_id, responsible_institute, region,
                institute, latitude, longitude, organisation, project_affiliation,
                station_type, water_body_category)

# ------------------------------
# Parameter: 32
# ------------------------------
df_parameter <- df_all %>% distinct(parameter, parameter_name, parameter_group,
                                    cas_number, lawa_code)

# ------------------------------
# Measurement time: 5,359
# ------------------------------
df_measurement_time <- df_all %>% distinct(year, measurement_date, measurement_time) %>%
  mutate(measurement_time_id = row_number()) %>%
  dplyr::select(measurement_time_id, year, measurement_date, measurement_time)

# ------------------------------
# Analysis method: 190
# ------------------------------
df_analysis_method <- df_all %>% distinct(measurement_method_code, chemical_treatment, physical_treatment,
                                          measurement_basis, accreditation, analytical_laboratory,
                                          control_chart_type, discipline, proficiency_testing) %>%
  mutate(analysis_method_id = row_number()) %>%
  dplyr::select(analysis_method_id, measurement_method_code, chemical_treatment, physical_treatment,
                measurement_basis, accreditation, analytical_laboratory,
                control_chart_type, discipline, proficiency_testing)

# ------------------------------
# Reference material: 475
# ------------------------------
df_reference_material <- df_all %>% distinct(parameter, reference_material_code, reference_material_basis,
                                             reference_material_type, reference_material_sd,
                                             reference_material_mean) %>%
  mutate(reference_material_id = row_number()) %>%
  dplyr::select(reference_material_id, parameter, reference_material_code, reference_material_basis,
                reference_material_type, reference_material_sd,
                reference_material_mean)

# ------------------------------
# Survey: 3897
# ------------------------------
df_survey <- df_all %>% distinct(monitoring_station_name, measurement_depth,
                                 station_latitude, station_longitude,
                                 measurement_project,
                                 survey_start, survey_end,
                                 vessel_code, platform_type, vessel_name) %>%
  mutate(survey_id = row_number()) %>%
  dplyr::select(survey_id, monitoring_station_name, measurement_depth,
                station_latitude, station_longitude,
                measurement_project,
                survey_start, survey_end,
                vessel_code, platform_type, vessel_name)

# ------------------------------
# Sample: 7067
# ------------------------------
df_sample <- df_all %>% distinct(sample_id,
                                 layer_upper_boundary, layer_lower_boundary,
                                 sampling_method, flag,
                                 matrix, sediment_composition, sediment_content,
                                 sampled_area) %>%
  mutate(sample_no = row_number()) %>%
  dplyr::select(sample_no, sample_id,
                layer_upper_boundary, layer_lower_boundary,
                sampling_method, flag,
                matrix, sediment_composition,
                sediment_content,
                sampled_area)


# ------------------------------
# LOD: 380
# ------------------------------
df_lod <- df_all %>% distinct(parameter,
                              internal_qa_detection_limit,
                              internal_qa_quantification_limit,
                              expanded_uncertainty_pct,
                              uncertainty_method) %>%
  mutate(lod_id = row_number()) %>%
  dplyr::select(lod_id, parameter, internal_qa_detection_limit,
                internal_qa_quantification_limit,
                expanded_uncertainty_pct,
                uncertainty_method)

# ------------------------------
# Sediment 109,544
# ------------------------------
df_sediment <- df_all %>%
  inner_join(df_station, by = c("station_name", "station_id",
                                "responsible_institute", "region", "institute",
                                "latitude", "longitude", "organisation",
                                "project_affiliation", "station_type", "water_body_category")) %>%
  inner_join(df_measurement_time, by = c("year", "measurement_date", "measurement_time")) %>%
  inner_join(df_analysis_method, by = c("measurement_method_code", "chemical_treatment",
                                        "physical_treatment", "measurement_basis", "accreditation",
                                        "analytical_laboratory", "control_chart_type", "discipline",
                                        "proficiency_testing")) %>%
  inner_join(df_reference_material, by = c("parameter", "reference_material_code", "reference_material_basis",
                                           "reference_material_type", "reference_material_sd", "reference_material_mean")) %>%
  inner_join(df_survey, by = c("monitoring_station_name", "measurement_depth", "station_latitude", "station_longitude",
                               "measurement_project", "survey_start", "survey_end", "vessel_code", "platform_type", "vessel_name")) %>%
  inner_join(df_sample, by = c("sample_id", "layer_upper_boundary", "layer_lower_boundary",
                               "sampling_method", "flag", "matrix", "sediment_composition",
                               "sediment_content", "sampled_area")) %>%
  inner_join(df_lod, by = c("parameter", "internal_qa_detection_limit", "internal_qa_quantification_limit",
                            "expanded_uncertainty_pct", "uncertainty_method")) %>%
  select(-c(station_name, station_id, responsible_institute, region, institute, latitude, longitude,
            organisation, project_affiliation, station_type, water_body_category)) %>%
  select(-c(parameter_name, parameter_group, cas_number, lawa_code)) %>%
  select(-c(year, measurement_date, measurement_time)) %>%
  select(-c(measurement_method_code, chemical_treatment, physical_treatment, measurement_basis,
            accreditation, analytical_laboratory, control_chart_type, discipline, proficiency_testing)) %>%
  select(-c(reference_material_code, reference_material_basis,
            reference_material_type, reference_material_sd, reference_material_mean)) %>%
  select(-c(monitoring_station_name, measurement_depth, station_latitude, station_longitude,
            measurement_project, survey_start, survey_end, vessel_code, platform_type, vessel_name)) %>%
  select(-c(sample_id, layer_upper_boundary, layer_lower_boundary, sampling_method, flag,
            matrix, sediment_composition, sediment_content, sampled_area)) %>%
  select(-c(internal_qa_detection_limit, internal_qa_quantification_limit, expanded_uncertainty_pct, uncertainty_method)) %>%
  group_by(station_no, measurement_time_id, analysis_method_id, reference_material_id,
           survey_id, sample_no, lod_id, parameter) %>%
  mutate(sediment_no = row_number()) %>%
  ungroup() %>%
  select(station_no, measurement_time_id, analysis_method_id, reference_material_id, survey_id, sample_no,
         lod_id, sediment_no, parameter, measurement_start, measurement_end, measured_value, unit, data_qualifier, internal_qa_count, recovery_rate)

# ------------------------------
# Translation
# ------------------------------

# ------------------------------
# Station: 482
# ------------------------------
region_translation <- c(
  "Nordsee" = "North Sea",
  "Ostsee" = "Baltic Sea")

df_station <- df_station %>%
  mutate(region = region_translation[region]) %>%
  dplyr::select(station_no, station_name, station_id, responsible_institute, region,
                institute, latitude, longitude, organisation, project_affiliation,
                station_type, water_body_category)

# ------------------------------
# Sample: 7067
# ------------------------------
sediment_translations <- tribble(
  ~german,                                                                           ~english,
  "Feinsand/ Schlick, braun-schwarz, geruchlos",                                    "Fine sand / silt, brown-black, odourless",
  "Feinsand/ Schlick,grau-schwarz, geruchlos",                                      "Fine sand / silt, grey-black, odourless",
  "NA",                                                                              NA_character_,
  "Feinsand / Schlick, grau-schwarz, ohne Geruch",                                  "Fine sand / silt, grey-black, no odour",
  "Schlick, grau-schwarz, geruch nach Fisch",                                       "Silt, grey-black, fishy odour",
  "Schlick, grau-schwarz, geruchlos",                                                "Silt, grey-black, odourless",
  "f.h.Sd.",                                                                         "Fine light sand",
  "Sd.",                                                                             "Sand",
  "gr.Sd.,gr.Sk.",                                                                   "Coarse sand, coarse shell gravel",
  "f.gr.+s.Sd.",                                                                     "Fine coarse + black sand",
  "f.gr.Sd.",                                                                        "Fine coarse sand",
  "s.Sk.br.Sd.",                                                                     "Black shell gravel, brown sand",
  "br.Sd.gr.Sk",                                                                     "Brown sand, coarse shell gravel",
  "gr.Sk.f.gr.Sd.",                                                                  "Coarse shell gravel, fine coarse sand",
  "f.gr.Sd.gr.Sk.",                                                                  "Fine coarse sand, coarse shell gravel",
  "f.gr.Sd.br.Sk.",                                                                  "Fine coarse sand, brown shell gravel",
  "f.gr.Sd.T.",                                                                      "Fine coarse sand, clay",
  "f.gr.+sSd.",                                                                      "Fine coarse + black sand",
  "s.+br.Sk.,M.",                                                                    "Black + brown shell gravel, mussels",
  "s.+br.Sk.",                                                                       "Black + brown shell gravel",
  "sand.gr.Ton",                                                                     "Sandy coarse clay",
  "br.Sk.",                                                                          "Brown shell gravel",
  "br.T.Sk.",                                                                        "Brown clay, shell gravel",
  "br.+gr.Sk.",                                                                      "Brown + coarse shell gravel",
  "gr.s.sd.T.",                                                                      "Coarse black sandy clay",
  "gr.Sd.St.M.",                                                                     "Coarse sand, stones, mussels",
  "f.br.Sd.",                                                                        "Fine brown sand",
  ")",                                                                               NA_character_,
  "-999",                                                                            NA_character_,
  "Schlick",                                                                         "Silt",
  "M",                                                                               "Mussels",
  "f.gr.Sd.M.",                                                                      "Fine coarse sand, mussels",
  "Schlick, schwarz, nach H2S",                                                      "Silt, black, H2S odour",
  "Schlick, schwarz, n. H2S",                                                        "Silt, black, H2S odour",
  "Schlick, schwarz, leicht nach H2S",                                               "Silt, black, slight H2S odour",
  "Schlickwatt",                                                                     "Muddy tidal flat",
  "Sandwatt",                                                                        "Sandy tidal flat",
  "Vorland",                                                                         "Salt marsh / foreland",
  "Feinsand",                                                                        "Fine sand",
  "Feinsand, bräunlich, ohne Geruch",                                                "Fine sand, brownish, no odour",
  "Feinsand, braeunlich, geruchlos",                                                 "Fine sand, brownish, odourless",
  "Feinsand, braeunlich-grau, geruchlos",                                            "Fine sand, brownish-grey, odourless",
  "Feinsand, grau-braun",                                                            "Fine sand, grey-brown",
  "Feinsand, hellbraun",                                                             "Fine sand, light brown",
  "grau-schwarzer Feinsand ohne Geruch",                                             "Grey-black fine sand, no odour",
  "Feinsand, grau-braun, Geruch nach Fisch",                                         "Fine sand, grey-brown, fishy odour",
  "br.Sk.T.",                                                                        "Brown shell gravel, clay",
  "br.Sk.gr.T.",                                                                     "Brown shell gravel, coarse clay",
  "gr.T.",                                                                           "Coarse clay",
  "gr.Sd.",                                                                          "Coarse sand",
  "br.Sk.bel",                                                                       "Brown shell gravel, biogenic",
  "gr.T.s.Ein.",                                                                     "Coarse clay, black inclusions",
  "mud",                                                                             "Mud",
  "br-gr.sd.Sk.",                                                                    "Brown-grey sandy shell gravel",
  "Sd.gr.T.",                                                                        "Sand, coarse clay",
  "subox.T.",                                                                        "Suboxic clay",
  "gr.Sk.",                                                                          "Coarse shell gravel",
  "Mischwatt",                                                                       "Mixed tidal flat",
  "br.Sk.weich",                                                                     "Brown shell gravel, soft",
  "Feinsand/Schlick, grau-schwarz, schwach nach H2S",                                "Fine sand / silt, grey-black, slight H2S odour",
  "br-gr.T.",                                                                        "Brown-grey clay",
  "g./grün L.",                                                                      "Yellow-green loam",
  "gr./grün Sk.",                                                                    "Grey-green shell gravel",
  "grgrün Sd.",                                                                      "Grey-green sand",
  "Feinsand, grau, geruchlos",                                                       "Fine sand, grey, odourless",
  "Feinsand, grau-braun, geruchlos",                                                 "Fine sand, grey-brown, odourless",
  "s.Sk.",                                                                           "Black shell gravel",
  "gr.Sk.Schill",                                                                    "Coarse shell gravel, shell debris",
  "f.gr.+s.Sd.M.",                                                                   "Fine coarse + black sand, mussels",
  "gr.Sk.,f.Sd.",                                                                    "Coarse shell gravel, fine sand",
  "gb.bnt.Sd.kl.St.",                                                                "Yellowish multicoloured sand, small stones",
  "gr.Sk. H2S",                                                                      "Coarse shell gravel, H2S",
  "gr.Sk.M.",                                                                        "Coarse shell gravel, mussels",
  "br.Sed.fest",                                                                     "Brown sediment, firm",
  "br.Sed./s.E.",                                                                    "Brown sediment / black inclusions",
  "s.Sk. H2S",                                                                       "Black shell gravel, H2S",
  "gr.Sd.St.",                                                                       "Coarse sand, stones",
  "gr.Lehm",                                                                         "Coarse loam",
  "br.+s.Sk.",                                                                       "Brown + black shell gravel",
  "s.Sk.Schill",                                                                     "Black shell gravel, shell debris",
  "gr.+s.Sk.",                                                                       "Coarse + black shell gravel",
  "f.gr.+br.Sd.",                                                                    "Fine coarse + brown sand",
  "s.Sk",                                                                            "Black shell gravel",
  "s.Sk.gr.Einschl",                                                                 "Black shell gravel, coarse inclusions",
  "gr.+br.Sk.",                                                                      "Coarse + brown shell gravel",
  "gr.Sk.s.Einschl",                                                                 "Coarse shell gravel, black inclusions",
  "gr.Sk.,",                                                                         "Coarse shell gravel",
  "Schill,",                                                                         "Shell debris",
  "St.",                                                                             "Stones",
  "f.bnt.Sd.",                                                                       "Fine multicoloured sand",
  "br.+ s.Sk.",                                                                      "Brown + black shell gravel",
  "gr.Ton",                                                                          "Coarse clay",
  "f.Sd.gr.Sk.",                                                                     "Fine sand, coarse shell gravel",
  "s.Sk.f.gr.Sd.",                                                                   "Black shell gravel, fine coarse sand",
  "f.gr.Sd.s.Sk.",                                                                   "Fine coarse sand, black shell gravel",
  "h.Sd.",                                                                           "Light sand",
  "gr.Sd.Schill",                                                                    "Coarse sand, shell debris",
  "s.Sk.M.",                                                                         "Black shell gravel, mussels",
  "s.Sk.M.Kohle",                                                                    "Black shell gravel, mussels, coal",
  "s.Sk.Pflz.",                                                                      "Black shell gravel, plant remains",
  "s.+gr.Sk.",                                                                       "Black + coarse shell gravel",
  "s.+gr.Sk.M.",                                                                     "Black + coarse shell gravel, mussels",
  "gr.Sk.gr.T.",                                                                     "Coarse shell gravel, coarse clay",
  "br.+gr.Sk",                                                                       "Brown + coarse shell gravel",
  "Sk.",                                                                             "Shell gravel",
  "gr.Sk.f.Sd.",                                                                     "Coarse shell gravel, fine sand",
  "gr.Sd.T.",                                                                        "Coarse sand, clay",
  "br.Sd.gr.Sk.",                                                                    "Brown sand, coarse shell gravel",
  "br.Sd.",                                                                          "Brown sand",
  "br.Sd.Schill",                                                                    "Brown sand, shell debris",
  "s-br.Sk.",                                                                        "Black-brown shell gravel",
  "gr.Sk.T.",                                                                        "Coarse shell gravel, clay",
  "br.Sd.br.Sk.",                                                                    "Brown sand, brown shell gravel",
  "br.Sd.Sk.M.",                                                                     "Brown sand, shell gravel, mussels",
  "f.Sd.,Sk.",                                                                       "Fine sand, shell gravel",
  "gr.+s.Sd.",                                                                       "Coarse + black sand",
  "br.Sk.s.Sk.",                                                                     "Brown shell gravel, black shell gravel",
  "f.Sd.",                                                                           "Fine sand",
  "f.Sd. schw. Spuren",                                                              "Fine sand, faint traces",
  "grob.Sd.",                                                                        "Coarse sand",
  "gr.Sk.gr.Sd.",                                                                    "Coarse shell gravel, coarse sand",
  "g.gr.Sd.",                                                                        "Yellow-coarse sand",
  "f.dkl.Sd.",                                                                       "Fine dark sand",
  "f.gr.Sd.Sk.",                                                                     "Fine coarse sand, shell gravel",
  "gr.T.,f.Sd.",                                                                     "Coarse clay, fine sand",
  "Sd.St.Schill",                                                                    "Sand, stones, shell debris",
  "f.gr.Sd.(Sk.)",                                                                   "Fine coarse sand (shell gravel)",
  "weicher T.",                                                                      "Soft clay",
  "gr./grün T.",                                                                     "Grey-green clay",
  "br.Sk.M.",                                                                        "Brown shell gravel, mussels",
  "gr.Sk.Sd.T.",                                                                     "Coarse shell gravel, sand, clay",
  "br.gr.sd.Sk.",                                                                    "Brown-grey sandy shell gravel",
  "T.,Sd.,Sk.",                                                                      "Clay, sand, shell gravel",
  "gr.Sk.Schn.",                                                                     "Coarse shell gravel, snails",
  "s.Sk.Grs.",                                                                       "Black shell gravel, coarse sand",
  "s.Sk.f.gr.Sd.Grs.",                                                               "Black shell gravel, fine coarse sand, coarse sand",
  "gb.bnt.Sd.",                                                                      "Yellowish multicoloured sand",
  "gr.Sd.gr.Sk.",                                                                    "Coarse sand, coarse shell gravel",
  "gr.Sk.Schlacke",                                                                  "Coarse shell gravel, slag",
  "br.Sk.f.gr.Sd.",                                                                  "Brown shell gravel, fine coarse sand",
  "gr.Sd.br.Sk",                                                                     "Coarse sand, brown shell gravel",
  "br.Sk",                                                                           "Brown shell gravel",
  "gr.Sk.f.Sd.T.",                                                                   "Coarse shell gravel, fine sand, clay",
  "br.+s.Sk",                                                                        "Brown + black shell gravel",
  "gr.+s.Sk.T.",                                                                     "Coarse + black shell gravel, clay",
  "gr.T.Sk.",                                                                        "Coarse clay, shell gravel",
  "gr.Sd.M.",                                                                        "Coarse sand, mussels",
  "sd.Ton",                                                                          "Sandy clay",
  "sk.Sd.",                                                                          "Shelly sand",
  "br.Sd.M.",                                                                        "Brown sand, mussels",
  "br.Sd.s.Sk.Schill",                                                               "Brown sand, black shell gravel, shell debris",
  "gr.+s.Sk.f.gr.Sd.",                                                               "Coarse + black shell gravel, fine coarse sand",
  "gr.+s.Sk.M.",                                                                     "Coarse + black shell gravel, mussels",
  "s.Sk.gr.Sd.",                                                                     "Black shell gravel, coarse sand",
  "gr.Sd.s.Sk.",                                                                     "Coarse sand, black shell gravel",
  "gr.Sk.kl.St.",                                                                    "Coarse shell gravel, small stones",
  "gr.+s.Sk.Torf",                                                                   "Coarse + black shell gravel, peat",
  "gr.sd.Sk.",                                                                       "Coarse sandy shell gravel",
  "s.+gr.sd.Sk.",                                                                    "Black + coarse sandy shell gravel",
  "s.sd.Sk.",                                                                        "Black sandy shell gravel",
  "gr.Sd.gr.+s.Sk.",                                                                 "Coarse sand, coarse + black shell gravel",
  "gr.Sk.Sd.",                                                                       "Coarse shell gravel, sand",
  "br.Sk.f.Sd.M",                                                                    "Brown shell gravel, fine sand, mussels",
  "gr.Sk.f.Sd.M",                                                                    "Coarse shell gravel, fine sand, mussels",
  "f.gr.Sd.Sk.M.",                                                                   "Fine coarse sand, shell gravel, mussels",
  "Verlandungszone",                                                                  "Silting zone",
  "gr.Sk.,Torf",                                                                     "Coarse shell gravel, peat",
  "br.+gr.Sk.M.",                                                                    "Brown + coarse shell gravel, mussels",
  "f.gr.Sd.Torf",                                                                    "Fine coarse sand, peat",
  "f.gr.Sd.Sk.Torf",                                                                 "Fine coarse sand, shell gravel, peat",
  "br.Sk.f.gr.Sd.M.",                                                                "Brown shell gravel, fine coarse sand, mussels",
  "f.gr.+dkl.Sd.",                                                                   "Fine coarse + dark sand",
  "gr.br.sd.Sk.",                                                                    "Coarse brown sandy shell gravel",
  "br.T.Sd.",                                                                        "Brown clay, sand",
  "br.T.",                                                                           "Brown clay",
  "br.gr.Sk.",                                                                       "Brown-coarse shell gravel",
  "br.Sk.kl.St.",                                                                    "Brown shell gravel, small stones",
  "s.Sk.f.Sd.",                                                                      "Black shell gravel, fine sand",
  "s.Sk.gr.T",                                                                       "Black shell gravel, coarse clay",
  "M, Ton stark wasserhaltig",                                                       "Mussels, clay highly water-saturated",
  "f.S",                                                                             "Fine sand",
  "S",                                                                               "Sand",
  "etwas M/S",                                                                       "Some mussels / sand",
  "S-gr.S",                                                                          "Sand - coarse sand",
  "f.S, wenig M",                                                                    "Fine sand, little mussel",
  "wenig M/S/M",                                                                     "Little mussel / sand / mussel",
  "M+S",                                                                             "Mussels + sand",
  "S, Muschelbruch",                                                                 "Sand, crushed shells",
  "M/S",                                                                             "Mussels / sand",
  "gr.S",                                                                            "Coarse sand",
  "S/Kies",                                                                          "Sand / gravel",
  "s.Sk.Torf",                                                                       "Black shell gravel, peat",
  "T.",                                                                              "Clay",
  "gr.Ton,s.Einsch",                                                                 "Coarse clay, black inclusions",
  "gr. Sk.",                                                                         "Coarse shell gravel",
  "br. Sk.",                                                                         "Brown shell gravel",
  "mgr.T./Le.",                                                                      "Medium-coarse clay / loam",
  "gr.Sk.,T.",                                                                       "Coarse shell gravel, clay",
  "gr.Sd.,Sk.",                                                                      "Coarse sand, shell gravel",
  "br.,gr.Sk.",                                                                      "Brown, coarse shell gravel",
  "Muschelteile in der Probe bewirken hohen Überkornanteil",                         "Shell fragments in sample cause high oversize fraction",
  "f.g.Sd.M.s.Sk.",                                                                  "Fine yellow sand, mussels, black shell gravel",
  "dkl.gr.Sk.",                                                                      "Dark coarse shell gravel",
  "br.,s.Sk.",                                                                       "Brown, black shell gravel",
  "s.Sk.,kl.St.",                                                                    "Black shell gravel, small stones",
  "s.Sk.Torf,M.",                                                                    "Black shell gravel, peat, mussels",
  "br.sd.Sk.",                                                                       "Brown sandy shell gravel",
  "wch.h.Sk.",                                                                       "Soft light shell gravel",
  "gr.Sd.Sk.M.",                                                                     "Coarse sand, shell gravel, mussels",
  "gr.Sd.Sk.",                                                                       "Coarse sand, shell gravel",
  "gr.Sd.s.Sk.M",                                                                    "Coarse sand, black shell gravel, mussels",
  "kl.M.s.Sk.",                                                                      "Small mussels, black shell gravel",
  "f.gr.Sd.gr.Sk.Schill",                                                            "Fine coarse sand, coarse shell gravel, shell debris",
  "s.Sk.f.gr.Sd.Schill",                                                             "Black shell gravel, fine coarse sand, shell debris",
  "schw. Slk.",                                                                      "Weak silt",
  "s.Sk.f.br.Sd.Schill",                                                             "Black shell gravel, fine brown sand, shell debris",
  "Sk.,Sd.",                                                                         "Shell gravel, sand",
  "gr.Sk./f.Sd.",                                                                    "Coarse shell gravel / fine sand",
  "f.dkl.gr. Sk.M.",                                                                 "Fine dark coarse shell gravel, mussels",
  "gr.+s.Sk.kl.St.",                                                                 "Coarse + black shell gravel, small stones",
  "gr.s.f.Sk.",                                                                      "Coarse black fine shell gravel",
  "br.s.Sk",                                                                         "Brown black shell gravel",
  "Feinsand, +Seegras, dunkelgrau",                                                  "Fine sand, seagrass, dark grey",
  "Feinsand/Schlick",                                                                 "Fine sand / silt",
  "braun-grauer Feinsand  ohne Geruch+Seegras",                                      "Brown-grey fine sand, no odour, seagrass",
  "Feinsand, braun",                                                                  "Fine sand, brown",
  "Feinsand / Schlick, braun-schwarz, ohne Geruch",                                  "Fine sand / silt, brown-black, no odour",
  "Feinsand / Schlick, schwarz-bräunlich, ohne Geruch",                              "Fine sand / silt, black-brownish, no odour",
  "Feinsand/Schlick, braun-schwarz, geruchlos",                                      "Fine sand / silt, brown-black, odourless",
  "braun-schwarzer Sand ohne Geruch",                                                 "Brown-black sand, no odour",
  "Feinsand, grau-schwarz",                                                           "Fine sand, grey-black",
  "Grobsand",                                                                         "Coarse sand",
  "Sand, 0-4 cm: hell, >4cm: grauschwarz, schwach H2S",                              "Sand, 0-4 cm: light, >4cm: grey-black, slight H2S",
  "Feinsand, bräunlich-schwarz, ohne Geruch",                                         "Fine sand, brownish-black, no odour",
  "gr.Sk.T.M.",                                                                       "Coarse shell gravel, clay, mussels",
  "Feinsand, grau/braun",                                                             "Fine sand, grey/brown",
  "Feinsand, grau/oliv",                                                              "Fine sand, grey/olive",
  "Schlick, grau-schwarz, H2S",                                                       "Silt, grey-black, H2S",
  "Schlick, H2S",                                                                     "Silt, H2S",
  "Schlick, schwarz, H2S",                                                            "Silt, black, H2S",
  "Schlick, schwarz, H2S-Geruch",                                                     "Silt, black, H2S odour",
  "Schlick, schwarz, n.H2S",                                                          "Silt, black, H2S odour",
  "Schlick, grau-schwarz, leicht nach H2S",                                           "Silt, grey-black, slight H2S odour",
  "Schlick, dkl.grau, leicht H2S",                                                    "Silt, dark grey, slight H2S",
  "Grs.s.Sk.",                                                                        "Coarse sand, black shell gravel",
  "f.dkl.Sd.gr.Sk.",                                                                  "Fine dark sand, coarse shell gravel",
  "dkl.Sd.s.Sk.kl.St.",                                                               "Dark sand, black shell gravel, small stones",
  "gr.s.Sk.",                                                                         "Coarse black shell gravel",
  "gr.Sk",                                                                            "Coarse shell gravel",
  "Feinsand/Schlick, grau, ohne",                                                     "Fine sand / silt, grey, no odour",
  "Schlick, grau-schwarz, H2S-Geruch",                                                "Silt, grey-black, H2S odour",
  "Schlick, oliv-schwarz, H2S-Geruch",                                                "Silt, olive-black, H2S odour",
  "br.+gr.SK.",                                                                       "Brown + coarse shell gravel",
  "br.s.Sk.",                                                                         "Brown black shell gravel",
  "Sand",                                                                             "Sand",
  "fine sand",                                                                        "Fine sand",
  "Schlick auf RS",                                                                   "Silt on rocky substrate",
  "sandiger Schlick",                                                                  "Sandy silt",
  "Schlick, dkl.grau, hellbr.Auflage, leicht H2S",                                   "Silt, dark grey, light brown surface layer, slight H2S",
  "Schlick, schwarz-bräunlich, ohne Geruch",                                          "Silt, black-brownish, no odour",
  "Feinsand/Schlick, H2S",                                                            "Fine sand / silt, H2S",
  "Schlick, grau-schwarz, moderig",                                                   "Silt, grey-black, musty odour",
  "Schlick, grau-braun, H2S-Geruch",                                                  "Silt, grey-brown, H2S odour",
  "Schlick, schwarz-braun, H2S-Geruch",                                               "Silt, black-brown, H2S odour",
  "Schlick, braun-schwarz, H2S",                                                      "Silt, brown-black, H2S",
  "schwarze Farbe; muffiger Geruch; hoher organischer Anteil",                        "Black colour; musty odour; high organic content",
  "Farbe: dunkelgrau-olive; ohne Geruch; kein organischer Anteil erkennba",           "Colour: dark grey-olive; no odour; no organic content visible",
  "Schlick mit Sandanteil; Farbe: dunkel, grau; ohne Geruch; festere Kons",           "Silt with sand fraction; colour: dark grey; no odour; firmer consistency",
  "Schlick, wenig Feinsand, grauoliv, Schwefelwasserstoff",                           "Silt, little fine sand, grey-olive, hydrogen sulphide",
  "Schlick, oliv-schwarz, H2S",                                                       "Silt, olive-black, H2S",
  "Schlick, dunkelgrau, Schwefelwasserstoff",                                         "Silt, dark grey, hydrogen sulphide",
  "Schlick, grau/schwarz, H2S",                                                       "Silt, grey/black, H2S",
  "Schlick, braun-schwarz, H2S-Geruch",                                               "Silt, brown-black, H2S odour",
  "coarse sand-gravel",                                                               "Coarse sand-gravel",
  "Schlick, schwarz, schwach nach H2S",                                               "Silt, black, slight H2S odour",
  "Feinsand/Schlick, bräunlich-schwarz, ohne Geruch",                                 "Fine sand / silt, brownish-black, no odour",
  "Schlick, dunkelgrau/schwarz",                                                      "Silt, dark grey/black",
  "braun-schwarzer Schlick ohne Geruch",                                              "Brown-black silt, no odour",
  "Feinsand-Schlick, braun",                                                          "Fine sand-silt, brown",
  "Feinsand/ Schlick, grau-schwarz, geruchlos",                                       "Fine sand / silt, grey-black, odourless",
  "g.Sd.",                                                                            "Yellow sand",
  "f.Sd.+Steine",                                                                     "Fine sand + stones",
  "br.Sk.f.Sd.",                                                                      "Brown shell gravel, fine sand",
  "br.+s.Sk.f.Sd.",                                                                   "Brown + black shell gravel, fine sand",
  "br.schl.Sd",                                                                       "Brown silty sand",
  "s.Sd.",                                                                            "Black sand",
  "gr.+br.Sd.",                                                                       "Coarse + brown sand",
  "br.gr. f. Sd. M.",                                                                 "Brown-grey fine sand, mussels",
  "braun-schwarzer Feinsand ohne Geruch",                                             "Brown-black fine sand, no odour",
  "Feinsand, bräunlich-grau",                                                         "Fine sand, brownish-grey",
  "f.br.Sd.br.Sk.",                                                                   "Fine brown sand, brown shell gravel",
  "f.gr.+br.Sd.-",                                                                    "Fine coarse + brown sand",
  "f.Sd.Sk.",                                                                         "Fine sand, shell gravel"
)

sediment_content_translations <- tribble(
  ~german,                         ~english,
  "-999",                          NA_character_,
  "grau/braun",                    "grey/brown",
  "grau/schwarz",                  "grey/black",
  "schwarz",                       "black",
  "oliv/schwarz",                  "olive/black",
  "Miesmuscheln, Seegrasbewuchs",  "blue mussels, seagrass growth",
  "wenig Muschelschill",           "little shell debris",
  "grau",                          "grey"
)

df_sample <- df_sample %>%
  left_join(
    sediment_translations |> rename(sediment_composition = german),
    by = "sediment_composition"
  ) |>
  mutate(sediment_composition_de = sediment_composition,
         sediment_composition = english) |>
  select(-english) |>
  left_join(
    sediment_content_translations |> rename(sediment_content = german),
    by = "sediment_content"
  ) |>
  mutate(sediment_content_de = sediment_content,
         sediment_content = english) |>
  dplyr::select(sample_no, sample_id,
                layer_upper_boundary, layer_lower_boundary,
                sampling_method, flag,
                matrix, sediment_composition,
                sediment_content,
                sampled_area)

# ------------------------------
# Write data
# ------------------------------

write_tsv(df_all, file.path(data_path, "df_all.tsv"))
write_tsv(code_lookup, file.path(data_path, "code_lookup.tsv"))
dd = df_all %>% count(station_id, latitude, longitude, monitoring_station_name, station_latitude, station_longitude)
write_tsv(dd, file.path(data_path, "location.tsv"))
