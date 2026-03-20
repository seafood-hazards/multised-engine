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
col_names <- c("site_code", "site_name", "label", "site_type", "activity_id", "activity_name", "client", "contractor", "param_id", "param_name", "cas_nr", "medium_id", "medium_name", "taxon_id", "scientific_name", "sample_method", "analysis_method", "sample_time", "upper_depth", "lower_depth", "depth_unit", "is_filtered", "exclude_class", "operator", "value", "list_name", "unit", "sample_no", "lod", "loq", "origin", "n_values", "comment", "archive", "product_desc", "utm33_x", "utm33_y")

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
         lower_depth = ifelse(is.na(lower_depth), 0, lower_depth))

# ------------------------------
# Activity
# ------------------------------
df_activity <- df %>% distinct(activity_id, activity_name)

# ------------------------------
# site
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
# Sample 29,230
# ------------------------------
df_sample <- df %>%
  distinct(activity_id, site_code, client, contractor, sample_time, sample_method, upper_depth, lower_depth) %>%
  mutate(sample_date = substr(sample_time, 1, 10)) %>%
  group_by(activity_id, site_code, sample_date, upper_depth, lower_depth) %>%
  mutate(
    seq_number = row_number(),
    sample_id = paste(activity_id, site_code, sample_date, paste(upper_depth, lower_depth, sep="-"), seq_number, sep = "_")
  ) %>%
  ungroup() %>%
  select(sample_id, everything(), -sample_date, -seq_number)

# ------------------------------
# Sediment
# ------------------------------
df
