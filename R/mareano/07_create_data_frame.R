library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_mareano.sqlite")

df_cruise <- dbReadTable(con, "cruise") |> as_tibble()
df_core <- dbReadTable(con, "core") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble()
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()
df_lld <- dbReadTable(con, "lld") |> as_tibble()

# Disconnect
dbDisconnect(con)


df_mariano_sed_gran <- df_sediment |>
  filter(parameter %in% c("Clay fraction", "Silt fraction", "Sand fraction", "Gravel fraction")) |>
  mutate(parameter = factor(parameter, levels = c("Clay fraction", "Silt fraction", "Sand fraction", "Gravel fraction"),
                            labels = c("clay", "silt", "sand", "gravel"))) |>
  dplyr::select(-c(is_lld)) |>
  pivot_wider(names_from = parameter, values_from = value)

df_mariano_cruise <- df_cruise |>
  dplyr::select(cruise_id, cruise_type, year)

df_mariano_core <- df_core |>
  dplyr::select(cruise_id, core_id, sampling_tool, core_name, dde, ddn, mbsl, dist_to_coast)

df_mariano_sample <- df_sample |>
  dplyr::select(cruise_id, core_id, sample_id, depth_from, depth_to, batch_id)

df_mariano_element_params <- df_parameter |>
  filter(unit %in% c("mg/kg") | parameter %in% c("TS", "TC", "TOC")) |>
  dplyr::select(parameter, element)

df_mariano_sediment <- df_sediment |>
  inner_join(df_mariano_element_params, by = "parameter") |>
  inner_join(df_mariano_sed_gran, by = c("cruise_id", "core_id", "sample_id")) |>
  inner_join(df_mariano_cruise, by = "cruise_id") |>
  inner_join(df_mariano_core, by = c("cruise_id", "core_id") ) |>
  inner_join(df_mariano_sample, by = c("cruise_id", "core_id", "sample_id")) |>
  left_join(df_lld %>% rename(lld = "value"), by = c("batch_id", "parameter")) |>
  dplyr::select(cruise_id, core_id, sample_id, cruise_type, year, core_name, sampling_tool,
                dde, ddn, mbsl, dist_to_coast, clay, silt, sand, gravel,
                depth_from, depth_to, element, parameter, value, is_lld, lld)

write_tsv(df_mariano_sediment, "./data/pilot_mareano.tsv.gz")
