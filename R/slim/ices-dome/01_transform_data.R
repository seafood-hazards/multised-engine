library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Read source data ──────────────────────────────────────────────────────
con_src <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_ices_dome.sqlite")

code_lookup        <- dbReadTable(con_src, "code_lookup")     |> as_tibble()
df_project         <- dbReadTable(con_src, "project")         |> as_tibble()
df_site            <- dbReadTable(con_src, "site")            |> as_tibble()
df_parameter       <- dbReadTable(con_src, "parameter")       |> as_tibble()
df_lld             <- dbReadTable(con_src, "lld")             |> as_tibble()
df_analysis_method <- dbReadTable(con_src, "analysis_method") |> as_tibble()
df_referance       <- dbReadTable(con_src, "reference")       |> as_tibble()
df_sample          <- dbReadTable(con_src, "sample")          |> as_tibble()
df_sediment        <- dbReadTable(con_src, "sediment")        |> as_tibble()

dbDisconnect(con_src)

# ── 1. Filter to 7 target elements ──────────────────────────────────────────
df_base_parameter <- df_parameter %>%
  filter(param %in% c("CO", "CU", "I", "MN", "MO", "SE", "ZN"))

df_base_sediment <- df_sediment %>%
  inner_join(df_base_parameter %>% distinct(param), by = "param")

df_base_sample <- df_sample %>%
  inner_join(df_base_sediment %>% distinct(sample_id))

df_base_site <- df_site %>%
  inner_join(df_base_sample %>% distinct(site_id))

df_base_project <- df_project %>%
  inner_join(df_base_sample %>% distinct(project_id))

# ── 2. Reference elements ────────────────────────────────────────────────────
df_ref_parameter <- df_parameter %>%
  filter(param %in% c("FE", "AL")
         | ((group_code == "P-PHY")
            & !(param %in% c("GSSKEW", "GSSORT", "LOIGN", "MOCON%",
                             "REDOX", "SEDAGE",
                             "GSKURT", "GSMEA", "GSMED"))))

df_ref_sediment <- df_sediment %>%
  inner_join(df_ref_parameter %>% distinct(param)) %>%
  inner_join(df_base_sample %>% distinct(sample_id))

# ── 3. Build dataset table ────────────────────────────────────────────
df_dataset <- df_base_project %>%
  inner_join(code_lookup %>%
               filter(data_col == "project")  %>%
               group_by(raw_code) %>%
               mutate(dataset_name = paste0(description, collapse = ", ")) %>%
               distinct(project = raw_code, dataset_name)) %>%
  group_by(project, dataset_name)  %>%
  mutate(country = paste0(country, collapse = ", "),
         institute = paste0(institute, collapse = ", "),
         project_id = paste0(project_id, collapse = ", "),) %>%
  ungroup() %>%
  distinct(project, country, institute, dataset_name, project_id) %>%
  mutate(source       = "ICES-DOME",
         dataset_id   = row_number()) %>%
  select(dataset_id, source,
         dataset_code = project, dataset_name, country, institute, project_id)

df_project_to_dataset <- df_dataset %>%
  select(dataset_id, project_id) %>%
  separate_rows(project_id, sep = ",\\s*") %>%
  mutate(
    dataset_id = as.integer(dataset_id),
    project_id = as.integer(project_id)
  )

df_dataset <- df_dataset %>% dplyr::select(-project_id)

# ── 4. Build site table (keyed on lat/lon rounded to 3 d.p.) ──
df_site <- df_base_site %>%
  mutate(lat_r = round(latitude, 3),
         lon_r = round(longitude, 3)) %>%
  distinct(lat_r, lon_r, dist_to_coast, est_country, country_code, municipality, sea_name) %>%
  group_by(lat_r, lon_r) %>%
  summarise(dist_to_coast = min(dist_to_coast),
            country = first(est_country),
            country_code = first(country_code),
            municipality = first(municipality),
            sea_name = first(sea_name)) %>%
  ungroup() %>%
  mutate(site_id = row_number()) %>%
  select(site_id, latitude = lat_r, longitude = lon_r,
         country, country_code, dist_to_coast, municipality, sea_name)

# ── 5. Build intermediate slim dataset ───────────────────────────────────────
df_slim <- bind_rows(df_base_sediment, df_ref_sediment) %>%
  inner_join(df_project_to_dataset, by="project_id") %>%
  inner_join(df_base_site, by="site_id") %>%
  inner_join(df_base_sample %>% dplyr::select(sample_id, year, date, sample_type, sample_type_description), by="sample_id") %>%
  inner_join(df_parameter, by="param") %>%
  left_join(df_lld, by=c("lld_id", "param")) %>%
  left_join(df_analysis_method , by=c("analysis_id", "param"))  %>%
  mutate(lat_r = round(latitude, 3), lon_r = round(longitude, 3)) %>%
  rename(old_site_id = site_id) %>%
  left_join(df_site %>% distinct(site_id, latitude, longitude),
            by = c("lat_r" = "latitude", "lon_r" = "longitude"))

# ── 6. Build event table (one row per core, not per depth interval) ───
df_event_keys <- df_slim %>%
  distinct(dataset_id, site_id, sample_type, sample_type_description,
           year, date)  %>%
  mutate(event_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_event_keys %>% distinct(dataset_id, site_id, sample_type,
                                        sample_type_description, event_id, year, date),
             by = c("dataset_id", "site_id", "sample_type",
                    "sample_type_description", "year", "date"))

df_event <- df_event_keys %>%
  mutate(date = as.Date(date, format = "%d/%m/%Y") %>% as.character()) %>%
  select(event_id, dataset_id, site_id, sampling_tool = sample_type,
         tool_description = sample_type_description, year, date)

# ── 7. Build method table ─────────────────────────────────────────────
df_method <- df_slim %>%
  distinct(param, metoa, lod, loq, labo) %>%
  mutate(method_id = row_number())

df_slim <- df_slim %>%
  inner_join(df_method, by = c("param", "metoa", "lod", "loq", "labo"))

df_method <- df_method %>%
  left_join(code_lookup %>%
             filter(data_col == "metoa")  %>%
             distinct(metoa = raw_code, method_description = description)) %>%
  left_join(code_lookup %>% filter(data_col == "labo") %>%
              distinct(labo = raw_code, lab_name = description)) %>%
  select(method_id, symbol = param, lab = labo, lab_name, lod, loq, method = metoa,
         method_description)

# ── 8. Build subsample table ──────────────────────────────────────────
df_subsample <- df_slim %>%
  distinct(event_id, depth_from, depth_to) %>%
  mutate(subsample_id = row_number()) %>%
  select(subsample_id, event_id, depth_from, depth_to) %>%
  mutate(depth_to = ifelse(is.na(depth_to), depth_from, depth_to))

df_slim <- df_slim %>%
  inner_join(df_subsample, by = c("event_id", "depth_from", "depth_to"))

# ── 9. Build measurement table ───────────────────────────────────────────────
df_measurement <- df_slim %>%
  distinct(sample_id, sediment_no, subsample_id, param, value, unit, basis, matrix, qflag, vflag, uncrt, metcu, dcflag, method_id) %>%
  mutate(measurement_id = row_number()) %>%
  select(measurement_id, subsample_id, symbol = param, value, unit, basis, matrix, qflag, vflag, uncrt, metcu, dcflag, method_id)

# ── 10. Build element table ──────────────────────────────────────────────────
df_element <- bind_rows(df_base_parameter, df_ref_parameter) %>%
  inner_join(df_measurement %>% distinct(param = symbol), by = "param") %>%
  distinct(symbol = param, element = param_description)
