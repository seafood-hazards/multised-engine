library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_pilot.sqlite")

df_activity <- dbReadTable(con, "activity") |> as_tibble()
df_client <- dbReadTable(con, "client") |> as_tibble()
df_contractor <- dbReadTable(con, "contractor") |> as_tibble()
df_site <- dbReadTable(con, "site") |> as_tibble()
df_sample_method <- dbReadTable(con, "sample_method") |> as_tibble()
df_analysis_method <- dbReadTable(con, "analysis_method") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble() %>%
  mutate(category = case_when(
    param_id %in% c("TOC", "TOC63", "TC", "TIC", "TS")  ~ "tcs",
    param_id %in% c("GSMF2_63", "GSMF_2000", "GSMF125_250", "GSMF1000_2000", "GSMF250_500", "GSMF63_125", "GSMF500_1000", "GSMF_63", "GSMF2", "FINS")  ~ "p",
    param_id %in% c("CO", "CU", "I", "MN", "MO", "SE", "ZN")  ~ "efsa",
    TRUE ~ "other"
  ))
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()
df_lld <- dbReadTable(con, "lld") |> as_tibble()

df_vannmiljo_sediment <- df_sediment %>%
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
                lat, lon, dist_to_coast, country, country_code, municipality, sea_name,
                sample_id, sample_time, sediment_no, upper_depth, lower_depth, sample_no, n_values,
                param_id, param_name, method, analysis, value, unit, operator, lod, loq,
                category)

# Disconnect
dbDisconnect(con)

write_tsv(df_vannmiljo_sediment, "./data/pilot_vannmiljo_all.tsv.gz")


activity_table <- df_vannmiljo_sediment %>% count(activity_id, activity_name, param_name) %>%
  pivot_wider(names_from = param_name, values_from = n) %>%
  dplyr::select(Activity = activity_id, Name = activity_name,
                Cobalt, Copper, Manganese, Molybdenum, Zinc, Selenium)

write_tsv(activity_table, "./data/vannmiljo_activities.tsv.gz")

