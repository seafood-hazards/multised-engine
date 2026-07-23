library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Read source data ──────────────────────────────────────────────────────
con_src <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_vannmiljo.sqlite")

df_activity <- dbReadTable(con_src, "activity") |> as_tibble()
df_client <- dbReadTable(con_src, "client") |> as_tibble()
df_contractor <- dbReadTable(con_src, "contractor") |> as_tibble()
df_site <- dbReadTable(con_src, "site") |> as_tibble()
df_sample_method <- dbReadTable(con_src, "sample_method") |> as_tibble()
df_analysis_method <- dbReadTable(con_src, "analysis_method") |> as_tibble()
df_sample <- dbReadTable(con_src, "sample") |> as_tibble()
df_parameter <- dbReadTable(con_src, "parameter") |> as_tibble()
df_sediment <- dbReadTable(con_src, "sediment") |> as_tibble()
df_lld <- dbReadTable(con_src, "lld") |> as_tibble()

dbDisconnect(con_src)

# ── 1. Filter to 7 target elements ──────────────────────────────────────────
df_base_parameter <- df_parameter %>%
  filter(param_id %in% c("CO", "CU", "I", "MN", "MO", "SE", "ZN"))

df_base_sediment <- df_sediment %>%
  inner_join(df_base_parameter %>% distinct(param_id), by = "param_id")

df_base_method <- df_analysis_method %>%
  inner_join(df_base_sediment %>% distinct(analysis_id))

df_base_lld <- df_lld %>%
  inner_join(df_base_sediment %>% distinct(sample_id, param_id, sediment_no))

df_base_sample <- df_sample %>%
  inner_join(df_base_sediment %>% distinct(sample_id))

df_base_sampling_tool <- df_sample_method %>%
  inner_join(df_base_sample %>% distinct(method_id))

df_base_site <- df_site %>%
  inner_join(df_base_sample %>% distinct(site_code))

df_base_activity <- df_activity %>%
  inner_join(df_base_sample %>% distinct(activity_id))

# ── 2. Reference elements ────────────────────────────────────────────────────
df_ref_parameter <- df_parameter %>%
  filter(param_id %in% c("FE", "AL",
                         "GSMF2_63", "GSMF_2000", "GSMF125_250", "GSMF1000_2000",
                         "GSMF250_500", "GSMF63_125", "GSMF500_1000",
                         "GSMF_63", "GSMF2", "FINS",
                         "TOC", "TOC63"))

df_ref_sediment <- df_sediment %>%
  inner_join(df_ref_parameter %>% distinct(param_id)) %>%
  inner_join(df_base_sample %>% distinct(sample_id))

# ── 3. Build dataset table ────────────────────────────────────────────
df_dataset <- df_base_activity %>%
  distinct(dataset_code = activity_id, dataset_name = activity_name) %>%
  mutate(source       = "Vannmiljø",
         country      = "Norway",
         dataset_id   = row_number()) %>%
  select(dataset_id, source,
         dataset_code, dataset_name, country)

# ── 4. Build site table (keyed on lat/lon rounded to 3 d.p.) ──
df_site <- df_base_site %>%
  mutate(lat_r = round(lat, 3),
         lon_r = round(lon, 3)) %>%
  distinct(lat_r, lon_r, dist_to_coast, country, country_code, municipality, sea_name) %>%
  group_by(lat_r, lon_r) %>%
  summarise(dist_to_coast = min(dist_to_coast),
            country = first(country),
            country_code = first(country_code),
            municipality = first(municipality),
            sea_name = first(sea_name)) %>%
  ungroup() %>%
  mutate(site_id = row_number()) %>%
  select(site_id, latitude = lat_r, longitude = lon_r,
         country, country_code, dist_to_coast, municipality, sea_name)

# ── 5. Build intermediate slim dataset ───────────────────────────────────────
df_slim <- bind_rows(df_base_sediment, df_ref_sediment) %>%
  inner_join(df_base_sample %>%
               inner_join(df_base_activity, by = "activity_id") %>%
               inner_join(df_base_site, by = "site_code") %>%
               inner_join(df_base_sampling_tool, by = "method_id"),
             by = "sample_id") %>%
  inner_join(bind_rows(df_base_parameter, df_ref_parameter), by = "param_id") %>%
  inner_join(df_analysis_method, by="analysis_id") %>%
  left_join(df_lld %>% filter(type == "LOD") %>% mutate(lod = value) %>%
              dplyr::select(sample_id, param_id, sediment_no, lod),
            by = c("sample_id", "param_id", "sediment_no")) %>%
  left_join(df_lld %>% filter(type == "LOQ") %>% mutate(loq = value) %>%
              dplyr::select(sample_id, param_id, sediment_no, loq),
            by = c("sample_id", "param_id", "sediment_no")) %>%
  mutate(lat_r = round(lat, 3), lon_r = round(lon, 3)) %>%
  left_join(df_dataset %>% distinct(activity_id = dataset_code, dataset_id),
            by = "activity_id") %>%
  left_join(df_site %>% distinct(site_id, latitude, longitude),
            by = c("lat_r" = "latitude", "lon_r" = "longitude")) %>%
  rename(sample_tool_id = method_id)

# ── 6. Build event table (one row per core, not per depth interval) ───
df_event_keys <- df_slim %>%
  distinct(dataset_id, site_id, method, sample_time) %>%
  mutate(event_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_event_keys %>% distinct(dataset_id, site_id, method, sample_time, event_id),
             by = c("dataset_id", "site_id", "method", "sample_time"))

df_event <- df_event_keys %>%
  mutate(year = as.integer(str_sub(sample_time, 1, 4))) %>%
  select(event_id, dataset_id, site_id, sampling_tool = method,
         year, datetime = sample_time)

# ── 7. Build method table ─────────────────────────────────────────────
df_method <- df_slim %>%
  distinct(symbol = param_id, method = analysis, lod, loq) %>%
  mutate(method_id = row_number()) %>%
  select(method_id, symbol, method, lod, loq)

df_slim <- df_slim %>%
  inner_join(
    df_method %>% rename(analysis = method, param_id = symbol),
    by = c("param_id", "analysis", "lod", "loq")
  )

# ── 8. Build subsample table ──────────────────────────────────────────
df_subsample <- df_slim %>%
  distinct(event_id, depth_from = upper_depth, depth_to = lower_depth) %>%
  mutate(subsample_id = row_number()) %>%
  select(subsample_id, event_id, depth_from, depth_to)

df_slim <- df_slim %>%
  inner_join(df_subsample %>% rename(upper_depth = depth_from,
                                     lower_depth = depth_to),
             by = c("event_id", "upper_depth", "lower_depth"))

# ── 9. Build measurement table ───────────────────────────────────────────────
df_measurement <- df_slim %>%
  distinct(sample_id, sediment_no, subsample_id, param_id, value, unit, operator, filtered, method_id) %>%
  mutate(measurement_id = row_number()) %>%
  select(measurement_id, subsample_id, symbol = param_id, value, unit, operator, filtered, method_id)

# ── 10. Build element table ──────────────────────────────────────────────────
df_element <- bind_rows(df_base_parameter, df_ref_parameter) %>%
  inner_join(df_measurement %>% distinct(param_id = symbol), by = "param_id") %>%
  distinct(symbol = param_id, element = param_name, cas_no)
