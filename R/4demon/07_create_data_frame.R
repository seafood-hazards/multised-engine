library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_4demon.sqlite")

df_project <- dbReadTable(con, "project") |> as_tibble()
df_station <- dbReadTable(con, "station") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble()
df_method <- dbReadTable(con, "method") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()

df_4demon_sediment <- df_sediment %>%
  left_join(df_sample, by = "sample_id") |>
  left_join(df_method, by = "method_id") |>
  left_join(df_parameter, by = "parameter") |>
  left_join(df_project, by = "project_id") |>
  left_join(df_station, by = "station_id") |>
  select(survey_seq_no,
         project_id, project, campaign_code, year, month,
         station_id, station_code, latitude, longitude,
         dist_to_coast, est_country, country_code, municipality, sea_name,
         sample_id, gear_code, depth_range,
         method_id, method_code, matrix_code, fraction_range_um,
         replicate_number, parameter, parameter_type, parameter_name,
         value, corrected_value, unit,
         value_flag, det_limit_flag, range_check_flag,
         outlier_extreme_flag, outlier_stdev_flag)

# Disconnect
dbDisconnect(con)

write_tsv(df_4demon_sediment, "./data/pilot_4demon.tsv.gz")
