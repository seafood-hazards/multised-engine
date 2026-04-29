# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/Mutab"
data_file <- file.path(data_path, "export_mudab_V_MESSWERTE_SEDIMENT.csv")

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
