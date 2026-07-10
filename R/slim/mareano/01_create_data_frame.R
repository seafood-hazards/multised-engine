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

dbDisconnect(con)

# 2. Select 7 target elements
df_base_parameter <- df_parameter %>%
  filter(element %in% c("Cobalt", "Copper", "Iodine",
                        "Manganese", "Molybdenum", "Selenium", "Zinc"))

df_base_sediment <- df_sediment %>%
  inner_join(df_base_parameter %>% distinct(parameter))

df_base_lld <- df_lld %>%
  inner_join(df_base_parameter %>% distinct(parameter))

df_base_sample <- df_sample %>%
  inner_join(df_base_sediment %>% distinct(cruise_id, core_id, sample_id))

df_base_core <- df_core %>%
  inner_join(df_base_sample %>% distinct(cruise_id, core_id))

df_base_cruise <- df_cruise %>%
  inner_join(df_base_core %>% distinct(cruise_id))

# 3. Select 2 reference elements that can be linked to the 7 target elements
df_ref_parameter <- df_parameter %>%
  filter(element %in% c("Iron", "Aluminium") | symbol %in% c("Clay", "Silt", "Sand", "Gravel"))

df_ref_sediment <- df_sediment %>%
  inner_join(df_ref_parameter %>% distinct(parameter)) %>%
  inner_join(df_base_sample %>% distinct(cruise_id, core_id, sample_id))

# 4. Create the dataset data set
df_dataset_slim <- df_base_cruise %>%
  distinct(cruise_type) %>%
  mutate(source_db = "Mareano",
         country = "Norway",
         institute = "IMR",
         dataset_id = row_number()) %>%
  dplyr::select(dataset_id,
                source_db,
                country,
                institute,
                dataset_name = cruise_type)

# 5. Create the site data set
df_site_slim <- df_base_core %>%
  distinct(ddn, dde, mbsl, country, country_code, dist_to_coast,
           municipality, sea_name) %>%
  mutate(depth = mbsl * -1,
         site_id = row_number()) %>%
  dplyr::select(site_id,
                latitude = ddn,
                longitude = dde,
                depth,
                country,
                country_code,
                dist_to_coast,
                municipality,
                sea_name)

# 6. Create the full data set (old/current version) with new dataset and site IDs
df_sediment_slim <- bind_rows(df_base_sediment, df_ref_sediment) |>
  inner_join(bind_rows(df_base_parameter, df_ref_parameter), by = "parameter") |>
  inner_join(df_base_cruise, by = "cruise_id") |>
  inner_join(df_base_core, by = c("cruise_id", "core_id") ) |>
  inner_join(df_base_sample, by = c("cruise_id", "core_id", "sample_id")) |>
  left_join(df_lld %>% rename(lld = "value"), by = c("batch_id", "parameter"))  |>
  left_join(df_dataset_slim %>% distinct(cruise_type = dataset_name, dataset_id), by="cruise_type") |>
  left_join(df_site_slim %>% mutate(mbsl = depth * -1) %>%
              distinct(site_id, ddn = latitude, dde = longitude, mbsl),
            by=c("ddn", "dde", "mbsl")) %>%
  rename(sample_id_old = sample_id)

# 7. Create the event data set
df_event_id <- df_sediment_slim %>%
  distinct(cruise_id, core_id, sample_id_old, dataset_id, site_id, sampling_tool, start, start_year)  |>
  mutate(event_id = row_number())

df_sediment_slim <- df_sediment_slim |>
  inner_join(df_event_id |> distinct(cruise_id, core_id, sample_id_old, event_id),
             by=c("cruise_id", "core_id", "sample_id_old"))

df_event_slim <- df_event_id %>%
  dplyr::select(event_id, dataset_id, site_id, sampling_tool,
                year = start_year, date = start)

# 8. Create the method data set
df_null_lld <- df_sediment_slim %>%
  filter(!(symbol %in% c("Clay", "Silt", "Sand", "Gravel"))) %>%
  filter(is.na(lld)) %>%
  distinct(symbol, parameter, method1, batch_id)

df_method_slim <- df_sediment_slim %>%
  distinct(symbol, method = method1, lab = institute, lld, comment) %>%
  mutate(method_id = row_number()) %>%
  dplyr::select(method_id, symbol, method, lab, lld, comment)

df_batches_with_method_id <- df_sediment_slim %>%
  distinct(parameter, batch_id, symbol, method = method1, lab = institute, lld, comment) %>%
  inner_join(df_method_slim %>% distinct()) %>%
  distinct(parameter, batch_id, method_id)

df_sediment_slim <- df_sediment_slim |>
  inner_join(df_batches_with_method_id,
             by=c("parameter", "batch_id"))

# 9. Create the subsample data set
df_subsample_slim <- df_sediment_slim %>%
  distinct(event_id, depth_from, depth_to) %>%
  mutate(subsample_id = row_number()) %>%
  dplyr::select(subsample_id, event_id, depth_from, depth_to)

df_sediment_slim <- df_sediment_slim |>
  inner_join(df_subsample_slim,
             by=c("event_id", "depth_from", "depth_to"))

# 10. Create the measurement data set
df_measurement_slim <- df_sediment_slim %>%
  distinct(subsample_id, symbol, value, unit, is_lld, method_id) %>%
  mutate(measurement_id = row_number()) %>%
  dplyr::select(measurement_id, subsample_id, symbol, value, unit, below_lld = is_lld, method_id)

# 11. Create the element data set
df_element_slim <- df_parameter %>%
  inner_join(df_measurement_slim %>% distinct(symbol)) %>%
  distinct(symbol, element)
