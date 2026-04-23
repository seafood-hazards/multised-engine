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
data_path <- "./data/Vannmiljo"
data_sheet <- "VannmiljoEksport"

excel_file_interest <- file.path(data_path, "Vannmilio_Elements_interest.xlsx")
data_range_interest <- "A1:AK61184"

excel_file_others <- file.path(data_path, "Vannmilio_Elements_others.xlsx")
data_range_others <- "A1:AK95215"

excel_file_toc <- file.path(data_path, "Vannmilio_pH_Carbon_Sulfur_all.xlsx")
data_range_toc <- "A1:AK42150"

excel_file_particle <- file.path(data_path, "Vannmilio_Partikler_all.xlsx")
data_range_particle <- "A1:AK39709"

# ------------------------------
# Source common helpers
# ------------------------------
source(file.path("R", "vannmiljo", "vannmiljo_helpers.R"))

# ------------------------------
# Read the data
# ------------------------------
df_interest <- read_vannmiljo_excel(excel_file_interest,
                                    data_sheet,
                                    data_range_interest) %>%
  correct_vannmiljo_data("interest")

df_others <- read_vannmiljo_excel(excel_file_others,
                                  data_sheet,
                                  data_range_others) %>%
  correct_vannmiljo_data("others")


df_toc <- read_vannmiljo_excel(excel_file_toc,
                               data_sheet,
                               data_range_toc) %>%
  correct_vannmiljo_data("toc")

df_particle <- read_vannmiljo_excel(excel_file_particle,
                                    data_sheet,
                                    data_range_particle) %>%
  correct_vannmiljo_data("particle")

df <- bind_rows(df_interest, df_others, df_toc, df_particle)

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
  group_by(site_code, site_name, utm33_x, utm33_y) %>%
  mutate(label = paste0(label, collapse = ",")) %>%
  ungroup() %>%
  group_by(site_code) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  st_as_sf(coords = c("utm33_x", "utm33_y"), crs = 25833) %>%
  st_transform(crs = 4326) %>%
  mutate(
    lat = st_coordinates(.)[, "Y"],
    lon = st_coordinates(.)[, "X"]
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
    sample_id = paste(activity_id, site_code, sample_date, paste(upper_depth, lower_depth, sep="-"), seq_number, sep = "_"),
    upper_depth = as.numeric(upper_depth),
    lower_depth = as.numeric(lower_depth)
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
# Sediment 61,183 (efsa), 95,214 (others), 42,149 (toc), 39,708 (particle) = 238,254
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
  mutate(type = "LOD",
         lod = as.numeric(lod)) %>%
  select(sample_id, param_id, sediment_no, type, value=lod)

df_loq <- df_sediment %>%
  filter(!is.na(loq)) %>%
  mutate(type = "LOQ",
         loq = as.numeric(loq)) %>%
  select(sample_id, param_id, sediment_no, type, value=loq)

df_lld <- bind_rows(df_lod, df_loq)

df_sediment <- df_sediment %>% dplyr::select(-c(lod, loq))
