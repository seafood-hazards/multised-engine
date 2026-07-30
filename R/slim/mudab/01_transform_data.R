library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Read source data ──────────────────────────────────────────────────────
con_src <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_mudab.sqlite")

df_code_lookup        <- dbReadTable(con_src, "code_lookup")        |> as_tibble()
df_station            <- dbReadTable(con_src, "station")            |> as_tibble()
df_parameter          <- dbReadTable(con_src, "parameter")          |> as_tibble()
df_measurement_time   <- dbReadTable(con_src, "measurement_time")   |> as_tibble()
df_analysis_method    <- dbReadTable(con_src, "analysis_method")    |> as_tibble()
df_reference_material <- dbReadTable(con_src, "reference_material") |> as_tibble()
df_survey             <- dbReadTable(con_src, "survey")             |> as_tibble()
df_lod                <- dbReadTable(con_src, "lod")                |> as_tibble()
df_sample             <- dbReadTable(con_src, "sample")             |> as_tibble()
df_sediment           <- dbReadTable(con_src, "sediment")           |> as_tibble()

dbDisconnect(con_src)

# ── 1. Filter to 7 target elements ──────────────────────────────────────────
df_base_parameter <- df_parameter %>%
  filter(parameter %in% c("CO", "CU", "I", "MN", "MO", "SE", "ZN"))

df_base_sediment <- df_sediment %>%
  inner_join(df_base_parameter %>% distinct(parameter), by = "parameter")

df_base_sample <- df_sample %>%
  inner_join(df_base_sediment %>% distinct(sample_no))

df_base_survey <- df_survey %>%
  inner_join(df_base_sediment %>% distinct(survey_id))

df_base_station <- df_station %>%
  inner_join(df_base_sediment %>% distinct(station_no))

df_base_measurement_time <- df_measurement_time %>%
  inner_join(df_base_sediment %>% distinct(measurement_time_id))

df_base_analysis_method <- df_analysis_method %>%
  inner_join(df_base_sediment %>% distinct(analysis_method_id))

# ── 2. Reference elements ────────────────────────────────────────────────────
df_ref_parameter <- df_parameter %>%
  filter(parameter %in% c("FE", "AL", "CORG"))

df_ref_sediment <- df_sediment %>%
  inner_join(df_ref_parameter %>% distinct(parameter)) %>%
  inner_join(df_base_sample %>% distinct(sample_no)) %>%
  inner_join(df_base_survey %>% distinct(survey_id)) %>%
  inner_join(df_base_station %>% distinct(station_no)) %>%
  inner_join(df_base_measurement_time %>% distinct(measurement_time_id))

df_ref_sample <- df_sample %>%
  inner_join(df_ref_sediment %>% distinct(sample_no))

df_ref_survey <- df_survey %>%
  inner_join(df_ref_sediment %>% distinct(survey_id))

df_ref_station <- df_station %>%
  inner_join(df_ref_sediment %>% distinct(station_no))

df_ref_measurement_time <- df_measurement_time %>%
  inner_join(df_ref_sediment %>% distinct(measurement_time_id))

df_ref_analysis_method <- df_analysis_method %>%
  inner_join(df_ref_sediment %>% distinct(analysis_method_id))

# ── SED ──────────────────────────────────────────
df_sed_parameter <- df_parameter %>%
  filter((parameter_group == "P-PHY" &
           parameter != "LOIGN") |
           parameter %in% c("CORG"))

df_sed_sediment <- df_sediment %>%
  inner_join(df_sed_parameter %>% distinct(parameter), by = "parameter")

df_base_sediment_all <- df_base_sediment %>%
  inner_join(df_station, by="station_no") %>%
  inner_join(df_measurement_time, by="measurement_time_id") %>%
  inner_join(df_analysis_method, by="analysis_method_id") %>%
  inner_join(df_survey, by="survey_id") %>%
  inner_join(df_sample, by="sample_no") %>%
  inner_join(df_parameter, by="parameter") %>%
  inner_join(df_reference_material, by=c("reference_material_id", "parameter")) %>%
  inner_join(df_lod, by=c("lod_id", "parameter")) %>%
  mutate(lat_r = round(station_latitude, 3),
         lon_r = round(station_longitude, 3))

df_sed_sediment_all <- df_sediment %>%
  inner_join(df_sed_parameter %>% distinct(parameter), by = "parameter") %>%
  inner_join(df_station, by="station_no") %>%
  inner_join(df_measurement_time, by="measurement_time_id") %>%
  inner_join(df_analysis_method, by="analysis_method_id") %>%
  inner_join(df_survey, by="survey_id") %>%
  inner_join(df_sample, by="sample_no") %>%
  inner_join(df_parameter, by="parameter") %>%
  inner_join(df_reference_material, by=c("reference_material_id", "parameter")) %>%
  inner_join(df_lod, by=c("lod_id", "parameter")) %>%
  mutate(lat_r = round(station_latitude, 3),
         lon_r = round(station_longitude, 3)) %>%
  inner_join(df_base_sediment_all %>% distinct(measurement_date, lat_r, lon_r,
                                               sampling_method, station_id,
                                               measurement_time_id, survey_id,
                                               layer_upper_boundary,
                                               layer_lower_boundary,
                                               sampling_method, flag,
                                               sampled_area, sediment_content,
                                               sediment_composition),
             by = c("measurement_date", "lat_r", "lon_r",
                    "sampling_method", "station_id",
                    "measurement_time_id", "survey_id",
                    "layer_upper_boundary", "layer_lower_boundary",
                    "flag", "sampled_area", "sediment_content",
                    "sediment_composition"))

df_sed_sediment_keys <- df_sed_sediment_all %>%
  distinct(sample_no, survey_id, station_no, measurement_time_id)

df_sed_sediment <- df_sediment %>%
  inner_join(df_sed_parameter %>% distinct(parameter)) %>%
  inner_join(df_sed_sediment_all %>% distinct(sample_no)) %>%
  inner_join(df_sed_sediment_all %>% distinct(survey_id)) %>%
  inner_join(df_sed_sediment_all %>% distinct(station_no)) %>%
  inner_join(df_sed_sediment_all %>% distinct(measurement_time_id))

df_sed_sample <- df_sample %>%
  inner_join(df_sed_sediment %>% distinct(sample_no))

df_sed_survey <- df_survey %>%
  inner_join(df_sed_sediment %>% distinct(survey_id))

df_sed_station <- df_station %>%
  inner_join(df_sed_sediment %>% distinct(station_no))

df_sed_measurement_time <- df_measurement_time %>%
  inner_join(df_sed_sediment %>% distinct(measurement_time_id))

df_sed_analysis_method <- df_analysis_method %>%
  inner_join(df_sed_sediment %>% distinct(analysis_method_id))

# ── 3. Build dataset table ────────────────────────────────────────────
df_dataset <- bind_rows(df_base_station, df_ref_station, df_sed_station) %>%
  distinct(organisation, responsible_institute, station_no, region) %>%
  group_by(organisation, responsible_institute) %>%
  mutate(station_no = paste0(station_no, collapse = ", ")) %>%
  ungroup() %>%
  distinct(dataset_name = organisation, region,
           responsible_institute, station_no) %>%
  mutate(dataset_name = ifelse(is.na(dataset_name), "Unknown", dataset_name)) %>%
  group_by(dataset_name, responsible_institute, station_no) %>%
  summarise(region = paste0(unique(region), collapse = ", ")) %>%
  ungroup() %>%
  inner_join(df_code_lookup %>%
               filter(category_code == "MUDABCL_INSTITUTE")  %>%
               distinct(responsible_institute = code, code_name)) %>%
  mutate(source = "MUDAB",
         dataset_id   = row_number(),
         dataset_group = dataset_name,
         dataset_name = paste(dataset_name, responsible_institute, sep="/")) %>%
  select(dataset_id, source, dataset_group, dataset_name, region, institute_code = responsible_institute,
         institute = code_name, station_no)

df_station_to_dataset <- df_dataset %>%
  select(dataset_id, station_no) %>%
  separate_rows(station_no, sep = ",\\s*") %>%
  mutate(
    dataset_id = as.integer(dataset_id),
    station_no = as.integer(station_no)
  )

df_dataset <- df_dataset %>% dplyr::select(-station_no)

# ── 4. Build site table (keyed on lat/lon rounded to 3 d.p.) ──
df_site <- bind_rows(df_base_survey, df_ref_survey, df_sed_survey) %>%
  mutate(lat_r = round(station_latitude, 3),
         lon_r = round(station_longitude, 3)) %>%
  distinct(lat_r, lon_r, measurement_depth, dist_to_coast,
           est_country, country_code, municipality, sea_name, survey_id) %>%
  group_by(lat_r, lon_r, depth = measurement_depth, dist_to_coast,
           est_country, country_code, municipality, sea_name) %>%
  summarise(survey_id = paste0(survey_id, collapse = ", ")) %>%
  ungroup() %>%
  group_by(lat_r, lon_r) %>%
  summarise(dist_to_coast = min(dist_to_coast),
            country = first(est_country),
            country_code = first(country_code),
            municipality = first(municipality),
            sea_name = first(sea_name),
            survey_id = paste0(survey_id, collapse = ", ")) %>%
  ungroup() %>%
  mutate(site_id = row_number()) %>%
  select(site_id, latitude = lat_r, longitude = lon_r,
         country, country_code, dist_to_coast, municipality, sea_name, survey_id)

df_survey_to_site <- df_site %>%
  select(site_id, survey_id) %>%
  separate_rows(survey_id, sep = ",\\s*") %>%
  mutate(
    site_id = as.integer(site_id),
    survey_id = as.integer(survey_id)
  )

df_site <- df_site %>% dplyr::select(-survey_id)

# ── 5. Build intermediate slim dataset ───────────────────────────────────────
df_slim <- bind_rows(df_base_sediment, df_ref_sediment, df_sed_sediment) %>%
  inner_join(df_station_to_dataset, by="station_no") %>%
  inner_join(df_survey_to_site, by="survey_id") %>%
  inner_join(df_measurement_time, by="measurement_time_id") %>%
  inner_join(df_analysis_method, by="analysis_method_id") %>%
  inner_join(df_sample, by="sample_no") %>%
  inner_join(df_parameter, by="parameter") %>%
  inner_join(df_reference_material, by=c("reference_material_id", "parameter")) %>%
  inner_join(df_lod, by=c("lod_id", "parameter"))

# ── 6. Build event table (one row per core, not per depth interval) ───
df_event_keys <- df_slim %>%
  distinct(dataset_id, site_id, sampling_method,
           year, measurement_date, measurement_time)  %>%
  mutate(event_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_event_keys %>% distinct(dataset_id, site_id, sampling_method,
                                        year, measurement_date, measurement_time, event_id),
             by = c("dataset_id", "site_id", "sampling_method",
                    "year", "measurement_date", "measurement_time"))

df_event <- df_event_keys %>%
  select(event_id, dataset_id, site_id, sampling_tool = sampling_method,
         year, date = measurement_date, time = measurement_time)

# ── 7. Build method table ─────────────────────────────────────────────
df_method <- df_slim %>%
  distinct(parameter, measurement_method_code,
           accreditation, analytical_laboratory,
           internal_qa_detection_limit, internal_qa_quantification_limit,
           expanded_uncertainty_pct) %>%
  mutate(method_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_method, by = c("parameter", "measurement_method_code",
                                "accreditation", "analytical_laboratory",
                                "internal_qa_detection_limit", "internal_qa_quantification_limit",
                                "expanded_uncertainty_pct"))

df_method <- df_method %>%
  left_join(df_code_lookup %>%
             filter(category_code == "ICESCL_METOA")  %>%
             distinct(measurement_method_code = code, method_description = code_name)) %>%
  left_join(df_code_lookup %>%
              filter(category_code == "ICESCL_RLABO")  %>%
              distinct(analytical_laboratory = code, analytical_laboratory_description = code_name)) %>%
  select(method_id, symbol = parameter, lab = analytical_laboratory, lab_name = analytical_laboratory_description,
         lod = internal_qa_detection_limit, loq = internal_qa_quantification_limit, uncertainty = expanded_uncertainty_pct,
         method = measurement_method_code,  method_description)

# ── 8. Build subsample table ──────────────────────────────────────────
df_subsample <- df_slim %>%
  distinct(event_id, layer_upper_boundary, layer_lower_boundary) %>%
  mutate(subsample_id = row_number()) %>%
  select(subsample_id, event_id, layer_upper_boundary, layer_lower_boundary)

df_slim <- df_slim %>%
  inner_join(df_subsample, by = c("event_id", "layer_upper_boundary", "layer_lower_boundary"))

df_subsample <- df_subsample %>%
  select(subsample_id, event_id, depth_from = layer_upper_boundary,
         depth_to = layer_lower_boundary)

# ── 9. Build measurement table ───────────────────────────────────────────────
## NB: There are multiple entries in chemical treatments in analysis_method table
##     37,488 -> 37,483 after de-duplication
df_measurement <- df_slim %>%
  distinct(sample_no, sediment_no, subsample_id, parameter, measured_value, unit, matrix, measurement_basis, data_qualifier, method_id) %>%
  mutate(measurement_id = row_number()) %>%
  select(measurement_id, subsample_id, symbol = parameter, value = measured_value, unit,
         basis = measurement_basis, matrix, qflag = data_qualifier, method_id)

# ── 10. Build element table ──────────────────────────────────────────────────
df_element <- bind_rows(df_base_parameter, df_ref_parameter, df_sed_parameter) %>%
  distinct(symbol = parameter, element = parameter_name,
           cas_no = cas_number)
