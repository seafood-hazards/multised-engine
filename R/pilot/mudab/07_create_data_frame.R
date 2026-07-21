library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_mudab.sqlite")

df_code_lookup <- dbReadTable(con, "code_lookup") |> as_tibble()
df_station <- dbReadTable(con, "station") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble()
df_measurement_time <- dbReadTable(con, "measurement_time") |> as_tibble()
df_analysis_method <- dbReadTable(con, "analysis_method") |> as_tibble()
df_reference_material <- dbReadTable(con, "reference_material") |> as_tibble()
df_survey <- dbReadTable(con, "survey") |> as_tibble()
df_lod <- dbReadTable(con, "lod") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()

df_mudab_sediment <- df_sediment %>%
  inner_join(df_station, by="station_no") %>%
  inner_join(df_measurement_time, by="measurement_time_id") %>%
  inner_join(df_analysis_method, by="analysis_method_id") %>%
  inner_join(df_survey, by="survey_id") %>%
  inner_join(df_sample, by="sample_no") %>%
  inner_join(df_parameter, by="parameter") %>%
  inner_join(df_reference_material, by=c("reference_material_id", "parameter")) %>%
  inner_join(df_lod, by=c("lod_id", "parameter")) %>%
  dplyr::select(station_no, measurement_time_id, analysis_method_id,
                reference_material_id, survey_id, sample_no, lod_id,
                organisation, project_affiliation, responsible_institute, region,
                water_body_category, year, survey_start, survey_end,
                station_latitude, station_longitude,
                dist_to_coast, est_country, country_code, municipality, sea_name,
                sampling_method, matrix, sediment_composition,
                sediment_no, layer_upper_boundary, layer_lower_boundary,
                parameter, parameter_name, parameter_group, cas_number,
                measured_value, unit, data_qualifier,
                analytical_laboratory, internal_qa_count,
                internal_qa_detection_limit, recovery_rate,
                internal_qa_quantification_limit, expanded_uncertainty_pct,
                uncertainty_method,
                measurement_method_code, chemical_treatment, physical_treatment,
                measurement_basis, accreditation)

# Disconnect
dbDisconnect(con)

write_tsv(df_mudab_sediment, "./data/pilot_mudab.tsv.gz")
