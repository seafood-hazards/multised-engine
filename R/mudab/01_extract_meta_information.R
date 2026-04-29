# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/Mudab"
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

write_tsv(code_lookup, file.path(data_path, "code_lookup.tsv"))

responsible_institute: MUDABCL_INSTITUTE
institute: MUDABCL_INSTITUTE
organisation: MUDABCL_ORGANISATION
parameter: ICESCL_PARAM
station_type: MUDABCL_STATIONTYPE

# ------------------------------
# Project 140 (I-MET) -> 147 (I-MET & I-MAJ)
# ------------------------------
df_project <- df_all %>% distinct(project, purpose, country, institute) %>%
  arrange(country, institute, project, purpose) %>%
  mutate(project_id = row_number()) %>%
  dplyr::select(project_id, project, purpose, country, institute)

# ------------------------------
# Site 8,130 (I-MET) -> 11,071 (I-MET & I-MAJ)
# ------------------------------
df_site <- df_all %>% distinct(station, latitude, longitude) %>%
  arrange(station, latitude, longitude) %>%
  mutate(site_id = row_number()) %>%
  dplyr::select(site_id, station, latitude, longitude)

# ------------------------------
# Sample 13,977 (I-MET) -> 17,318 (I-MET & I-MAJ)
# ------------------------------
df_sample <- df_all %>% count(project, purpose, country, institute,
                               station, latitude, longitude,
                               year, date, sample_type) %>%
  inner_join(df_project, by=c("project", "purpose", "country", "institute")) %>%
  inner_join(df_site, by=c("station", "latitude", "longitude")) %>%
  mutate(sample_id = row_number()) %>%
  left_join(
    code_lookup %>% filter(data_col == "sample_type") %>% select(raw_code, sample_type_description = description),
    by = c("sample_type" = "raw_code")
  )  %>%
  dplyr::select(sample_id, project_id, site_id, year, date, sample_type, sample_type_description, row_count = n)

# ------------------------------
# Parameter 119 (I-MET) -> 138 (I-MET & I-MAJ)
# ------------------------------
df_parameter <- df_all %>% count(group_code, param) %>%
  inner_join(
    code_lookup %>% filter(data_col == "group_code") %>% select(raw_code, group_description = description),
    by = c("group_code" = "raw_code")
  ) %>%
  inner_join(
    code_lookup %>% filter(data_col == "param") %>% select(raw_code, param_description = description),
    by = c("param" = "raw_code")
  ) %>%
  dplyr::select(param, param_description, group_code, group_description, row_count=n)

# ------------------------------
# LLD 1,422 (I-MET) -> 1,480 (I-MET & I-MAJ)
# ------------------------------
df_lld <- df_all %>% count(param, lod, loq)  %>%
  mutate(lld_id = row_number()) %>%
  dplyr::select(lld_id, param, lod, loq, row_count = n)

# ------------------------------
# Analysis method 2,526 (I-MET) -> 2,453 (I-MET & I-MAJ)
# ------------------------------
df_analysis_method <- df_all %>% count(param, labo, metst, metpt, metps, metcx, metoa)  %>%
  mutate(analysis_id = row_number()) %>%
  dplyr::select(analysis_id, param, labo, metst, metpt, metps, metcx, metoa, row_count = n)

# ------------------------------
# Reference 25
# ------------------------------
df_referance <- df_all %>% count(ref) %>%
  left_join(
    code_lookup %>% filter(data_col == "ref") %>% select(raw_code, ref_description = description),
    by = c("ref" = "raw_code")
    ) %>%
  mutate(ref_id = row_number()) %>%
  dplyr::select(ref_id, ref, ref_description, row_count = n)

# ------------------------------
# Sediment 302,159 -> 296,027 (I-MET) -> 325,893 (I-MET & I-MAJ)
# ------------------------------
df_sediment <- df_all %>%
  inner_join(df_project, by = c("project", "purpose", "country", "institute")) %>%
  inner_join(df_site, by = c("station", "latitude", "longitude")) %>%
  inner_join(df_sample, by = c("project_id", "site_id", "year", "date", "sample_type")) %>%
  inner_join(df_parameter, by = c("param", "group_code")) %>%
  inner_join(df_lld, by = c("param", "lod", "loq")) %>%
  inner_join(df_analysis_method, by = c("param", "labo", "metst", "metpt", "metps", "metcx", "metoa")) %>%
  inner_join(df_referance, by = "ref") %>%
  dplyr::select(project_id, site_id, sample_id, year, date, sample_type,
                depth_from, depth_to, matrix, param, value, unit,
                basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                sub_no, dcflag) %>%
  arrange(project_id, site_id, sample_id, param, depth_from, depth_to) %>%
  group_by(project_id, site_id, sample_id, param) %>%
  mutate(sediment_no = row_number()) %>%
  ungroup() %>%
  dplyr::select(project_id, site_id, sample_id, param,
                sediment_no, depth_from, depth_to, matrix,
                value, unit,
                basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                sub_no, dcflag)
