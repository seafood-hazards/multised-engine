# 01_extract_meta_information.R
library(tidyverse)
library(readxl)
library(stringr)
library(dplyr)
library(tidyr)
library(sf)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data"
excel_file <- file.path(data_path, "Vannmilio_all.xlsx")
data_sheet <- "VannmiljoEksport"
data_range <- "A1:AK61184"
col_names <- c("site_code", "site_name", "label", "site_type", "activity_id", "activity_name", "client", "contractor", "param_id", "param_name", "cas_no", "medium_id", "medium_name", "taxon_id", "scientific_name", "sample_method", "analysis_method", "sample_time", "upper_depth", "lower_depth", "depth_unit", "is_filtered", "exclude_class", "operator", "value", "list_name", "unit", "sample_no", "lod", "loq", "origin", "n_values", "comment", "archive", "product_desc", "utm33_x", "utm33_y")

# ------------------------------
# Read the data
# ------------------------------
df <- readxl::read_excel(excel_file, sheet = data_sheet, range = data_range,
                         col_types = "text")
colnames(df) <- col_names

df <- df %>%
  mutate(contractor = ifelse(is.na(contractor), "Unknown", contractor),
         client = ifelse((is.na(client) | (client == "0")), "Unknown", client),
         sample_method = ifelse((is.na(sample_method) | (sample_method == "UKJENT")), "Unknown", sample_method),
         analysis_method = ifelse((is.na(analysis_method) | (analysis_method == "UKJENT")), "Unknown", analysis_method),
         upper_depth = ifelse(is.na(upper_depth), 0, upper_depth),
         lower_depth = ifelse(is.na(lower_depth), 0, lower_depth),
         filtered = ifelse(is_filtered == "Filtrert", TRUE, FALSE),
         archive = ifelse(archive == "j", TRUE, FALSE),
         param_name = case_when(
           param_name == "Kobber" ~ "Copper",
           param_name == "Sink" ~ "Zinc",
           param_name == "Mangan" ~ "Manganese",
           param_name == "Kobolt" ~ "Cobalt",
           param_name == "Molybden" ~ "Molybdenum",
           param_name == "Selen" ~ "Selenium",
         ))

# ------------------------------
# Activity
# ------------------------------
df_activity <- df %>% distinct(activity_id, activity_name)

# ------------------------------
# Client
# ------------------------------
df_client <- df %>% distinct(client, archive) %>%
  mutate(client_id = row_number()) %>%
  dplyr::select(client_id, client, archive)

# ------------------------------
# Contractor
# ------------------------------
df_contractor <- df %>% distinct(contractor) %>%
  mutate(contractor_id = row_number()) %>%
  dplyr::select(contractor_id, contractor)

# ------------------------------
# Site 20,501
# ------------------------------
# EPSG code 25833 is the official ETRS89 UTM 33N projection used in Norway (Vannmiljø/Kartverket)
# Transform the projection to standard Longitude/Latitude (WGS84)
# EPSG code 4326 is the universal code for GPS Long/Lat
df_site <- df %>% distinct(site_code, site_name, label, utm33_x, utm33_y) %>%
  mutate(
    utm33_x = as.numeric(utm33_x),
    utm33_y = as.numeric(utm33_y)
    ) %>%
  st_as_sf(coords = c("utm33_x", "utm33_y"), crs = 25833) %>%
  st_transform(crs = 4326) %>%
  mutate(
    lon = st_coordinates(.)[, "X"],
    lat = st_coordinates(.)[, "Y"]
  ) %>%
  st_drop_geometry()

# ------------------------------
# Sample method
# ------------------------------
df_sample_method <- df %>% distinct(sample_method) %>%
  mutate(method_id = row_number()) %>%
  dplyr::select(method_id, method = sample_method)


# ------------------------------
# Analysis method
# ------------------------------
df_analysis_method <- df %>% distinct(analysis_method, unit) %>%
  mutate(analysis_id = row_number()) %>%
  dplyr::select(analysis_id, analysis = analysis_method, unit)

# ------------------------------
# Sample 29,230
# ------------------------------
df_sample <- df %>%
  distinct(activity_id, site_code, client, contractor, sample_time, sample_method, upper_depth, lower_depth, filtered) %>%
  mutate(sample_date = substr(sample_time, 1, 10)) %>%
  group_by(activity_id, site_code, sample_date, upper_depth, lower_depth, filtered) %>%
  mutate(
    seq_number = row_number(),
    sample_id = paste(activity_id, site_code, sample_date, paste(upper_depth, lower_depth, sep="-"), seq_number, sep = "_")
  ) %>%
  ungroup() %>%
  inner_join(df_client, by = "client") %>%
  inner_join(df_contractor, by = "contractor") %>%
  inner_join(df_sample_method, by = c(sample_method = "method")) %>%
  dplyr::select(sample_id, activity_id, site_code, client_id, contractor_id, method_id,
                upper_depth, lower_depth, sample_time, filtered)

# ------------------------------
# Parameter
# ------------------------------
df_parameter <- df %>% distinct(param_id, param_name, cas_no)

# ------------------------------
# Sediment 61,183
# ------------------------------
df_sediment <- df %>%
  dplyr::select(activity_id, site_code,  sample_time, upper_depth, lower_depth, sample_method, analysis_method, param_id, value, operator, client, contractor, sample_method, unit, sample_no, n_values, lod, loq) %>%
  inner_join(df_client, by = "client") %>%
  inner_join(df_contractor, by = "contractor") %>%
  inner_join(df_sample_method, by = c(sample_method = "method")) %>%
  inner_join(df_analysis_method, by = c(analysis_method = "analysis", "unit")) %>%
  inner_join(df_sample, by = c("activity_id", "site_code", "client_id",
                               "contractor_id", "method_id", "sample_time",
                               "upper_depth", "lower_depth")) %>%
  dplyr::select(sample_id, param_id, analysis_id, value, operator, sample_no, n_values, lod, loq) %>%
  group_by(sample_id, param_id) %>%
  mutate(sediment_no = row_number()) %>%
  ungroup() %>%
  dplyr::select(sample_id, param_id, sediment_no, analysis_id, value, operator, sample_no, n_values, lod, loq)

# ------------------------------
# lld
# ------------------------------
df_lod <- df_sediment %>%
  filter(!is.na(lod)) %>%
  mutate(type = "LOD") %>%
  select(sample_id, param_id, sediment_no, type, value=lod)

df_loq <- df_sediment %>%
  filter(!is.na(loq)) %>%
  mutate(type = "LOQ") %>%
  select(sample_id, param_id, sediment_no, type, value=loq)

df_lld <- bind_rows(df_lod, df_loq)

df_sediment <- df_sediment %>% dplyr::select(-c(lod, loq))
