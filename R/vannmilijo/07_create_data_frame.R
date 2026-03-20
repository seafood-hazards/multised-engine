library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_vannmilijo.sqlite")

df_activity <- dbReadTable(con, "activity") |> as_tibble()
df_client <- dbReadTable(con, "client") |> as_tibble()
df_contractor <- dbReadTable(con, "contractor") |> as_tibble()
df_site <- dbReadTable(con, "site") |> as_tibble()
df_sample_method <- dbReadTable(con, "sample_method") |> as_tibble()
df_analysis_method <- dbReadTable(con, "analysis_method") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble()
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()
df_lld <- dbReadTable(con, "lld") |> as_tibble()

# Disconnect
dbDisconnect(con)

df_vannmilio_sediment <- df_sediment %>%
  inner_join(df_sample %>%
               inner_join(df_activity, by = "activity_id") %>%
               inner_join(df_site, by = "site_code") %>%
               inner_join(df_client, by = "client_id") %>%
               inner_join(df_contractor, by = "contractor_id") %>%
               inner_join(df_sample_method, by = "method_id"),
             by = "sample_id") %>%
  inner_join(df_parameter, by="param_id") %>%
  inner_join(df_analysis_method, by="analysis_id") %>%
  left_join(df_lld %>% filter(type == "LOD") %>% mutate(lod = value) %>%
              dplyr::select(sample_id, param_id, sediment_no, lod),
            by = c("sample_id", "param_id", "sediment_no")) %>%
  left_join(df_lld %>% filter(type == "LOQ") %>% mutate(loq = value) %>%
              dplyr::select(sample_id, param_id, sediment_no, loq),
            by = c("sample_id", "param_id", "sediment_no")) %>%
  dplyr::select(activity_id, activity_name, site_code, site_name,
                lon, lat, dist_to_coast, country, country_code, municipality, sea_name,
                sample_time, upper_depth, lower_depth, sample_no, n_values,
                param_id, param_name, method, analysis, value, unit, operator, lod, loq)


write_tsv(df_vannmilio_sediment, "./data/pilot_vannmilio.tsv.gz")
