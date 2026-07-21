library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Read source data ──────────────────────────────────────────────────────
con_src <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_mareano.sqlite")

df_cruise    <- dbReadTable(con_src, "cruise")    |> as_tibble()
df_core      <- dbReadTable(con_src, "core")      |> as_tibble()
df_sample    <- dbReadTable(con_src, "sample")    |> as_tibble()
df_parameter <- dbReadTable(con_src, "parameter") |> as_tibble()
df_sediment  <- dbReadTable(con_src, "sediment")  |> as_tibble()
df_lld       <- dbReadTable(con_src, "lld")       |> as_tibble()

dbDisconnect(con_src)

# ── 1. Filter to 7 target elements ──────────────────────────────────────────
df_base_parameter <- df_parameter %>%
  filter(element %in% c("Cobalt", "Copper", "Iodine",
                         "Manganese", "Molybdenum", "Selenium", "Zinc"))

df_base_sediment <- df_sediment %>%
  inner_join(df_base_parameter %>% distinct(parameter), by = "parameter")

df_base_sample <- df_sample %>%
  inner_join(df_base_sediment %>% distinct(cruise_id, core_id, sample_id),
             by = c("cruise_id", "core_id", "sample_id"))

df_base_core <- df_core %>%
  inner_join(df_base_sample %>% distinct(cruise_id, core_id),
             by = c("cruise_id", "core_id"))

df_base_cruise <- df_cruise %>%
  inner_join(df_base_core %>% distinct(cruise_id), by = "cruise_id")

# ── 2. Reference elements ────────────────────────────────────────────────────
df_ref_parameter <- df_parameter %>%
  filter(element %in% c("Iron", "Aluminium") |
           symbol %in% c("Clay", "Silt", "Sand", "Gravel"))

df_ref_sediment <- df_sediment %>%
  inner_join(df_ref_parameter %>% distinct(parameter), by = "parameter") %>%
  inner_join(df_base_sample %>% distinct(cruise_id, core_id, sample_id),
             by = c("cruise_id", "core_id", "sample_id"))

# ── 3. Build dataset table ────────────────────────────────────────────
df_dataset <- df_base_cruise %>%
  distinct(cruise_type) %>%
  mutate(source       = "Mareano",
         country      = "Norway",
         institute    = "IMR",
         dataset_id   = row_number()) %>%
  select(dataset_id, source, country, institute,
         dataset_name = cruise_type)

# ── 4. Build site table (keyed on lat/lon rounded to 3 d.p. + depth) ──
df_site <- df_base_core %>%
  mutate(lat_r = round(ddn, 3),
         lon_r = round(dde, 3),
         depth = mbsl * -1) %>%
  group_by(lat_r, lon_r, depth, country, country_code,
           municipality, sea_name) %>%
  summarise(dist_to_coast = min(dist_to_coast)) %>%
  ungroup() %>%
  mutate(site_id = row_number()) %>%
  select(site_id, latitude = lat_r, longitude = lon_r, depth,
         country, country_code, dist_to_coast, municipality, sea_name)

# ── 5. Build intermediate slim dataset ───────────────────────────────────────
df_slim <- bind_rows(df_base_sediment, df_ref_sediment) %>%
  inner_join(bind_rows(df_base_parameter, df_ref_parameter), by = "parameter") %>%
  inner_join(df_base_cruise, by = "cruise_id") %>%
  inner_join(df_base_core,   by = c("cruise_id", "core_id")) %>%
  inner_join(df_base_sample, by = c("cruise_id", "core_id", "sample_id")) %>%
  left_join(df_lld %>% rename(lld = value), by = c("batch_id", "parameter")) %>%
  mutate(lat_r = round(ddn, 3), lon_r = round(dde, 3), depth = mbsl * -1) %>%
  left_join(df_dataset %>% distinct(cruise_type = dataset_name, dataset_id),
            by = "cruise_type") %>%
  left_join(df_site %>% distinct(site_id, latitude, longitude, depth),
            by = c("lat_r" = "latitude", "lon_r" = "longitude", "depth"))

# ── 6. Build event table (one row per core, not per depth interval) ───
df_event_keys <- df_slim %>%
  distinct(cruise_id, core_id, dataset_id, site_id, sampling_tool,
           start, start_year) %>%
  mutate(event_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_event_keys %>% distinct(cruise_id, core_id, event_id),
             by = c("cruise_id", "core_id"))

df_event <- df_event_keys %>%
  select(event_id, dataset_id, site_id, sampling_tool,
         year = start_year, date = start)

# ── 7. Build method table ─────────────────────────────────────────────
df_method <- df_slim %>%
  distinct(symbol, method = method1, lab = institute, lld, comment) %>%
  mutate(method_id = row_number()) %>%
  select(method_id, symbol, method, lab, lld, comment)

df_slim <- df_slim %>%
  inner_join(
    df_method %>% rename(method1 = method, institute = lab),
    by = c("symbol", "method1", "institute", "lld", "comment")
  )

# ── 8. Build subsample table ──────────────────────────────────────────
df_subsample <- df_slim %>%
  distinct(event_id, depth_from, depth_to) %>%
  mutate(subsample_id = row_number()) %>%
  select(subsample_id, event_id, depth_from, depth_to)

df_slim <- df_slim %>%
  inner_join(df_subsample, by = c("event_id", "depth_from", "depth_to"))

# ── 9. Build measurement table ───────────────────────────────────────────────
df_measurement <- df_slim %>%
  distinct(subsample_id, symbol, value, unit, below_lld = is_lld, method_id) %>%
  mutate(measurement_id = row_number()) %>%
  select(measurement_id, subsample_id, symbol, value, unit, below_lld, method_id)

# ── 10. Build element table ──────────────────────────────────────────────────
df_element <- bind_rows(df_base_parameter, df_ref_parameter) %>%
  inner_join(df_measurement %>% distinct(symbol), by = "symbol") %>%
  distinct(symbol, element)
