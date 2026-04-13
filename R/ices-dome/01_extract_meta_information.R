# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/ICES DOME/Metals and matalloids"
data_file <- file.path(data_path, "ContaminantsSediment_2026032611051738.csv")
code_path <- "./data/ICES DOME/code"

# ------------------------------
# Source common helpers
# ------------------------------
#source(file.path("R", "mareano", "sedimeter_helpers.R"))

# ------------------------------
# Read the whole data
# ------------------------------
all_data <- read_csv(data_file)

# ------------------------------
# Read code data
# ------------------------------

code_files <- file.path(code_path, c(
  "RECO_Export_13-08-2026-02-08-51.csv",
  "RECO_Export_13-09-2026-02-09-21.csv",
  "RECO_Export_13-08-2026-12-08-07.csv",
  "RECO_Export_13-08-2026-12-08-41.csv",
  "RECO_Export_13-10-2026-12-10-39.csv",
  "RECO_Export_13-16-2026-12-16-53.csv",
  "RECO_Export_13-20-2026-12-20-47.csv",
  "RECO_Export_13-23-2026-12-23-21.csv",
  "RECO_Export_13-32-2026-12-32-07.csv",
  "RECO_Export_13-32-2026-12-32-26.csv",
  "RECO_Export_13-36-2026-12-36-40.csv",
  "RECO_Export_13-37-2026-12-37-45.csv",
  "RECO_Export_13-40-2026-12-40-21.csv",
  "RECO_Export_13-41-2026-12-41-37.csv",
  "RECO_Export_13-46-2026-12-46-49.csv",
  "RECO_Export_13-57-2026-11-57-46.csv",
  "RECO_Export_13-57-2026-11-57-56.csv",
  "RECO_Export_13-58-2026-11-58-58.csv"
))

combined_codes <- code_files |>
  map(\(f) read_csv(f, col_select = c(Code, Description, CodeType), show_col_types = FALSE)) |>
  list_rbind()

# ------------------------------
# Create look-up table
# ------------------------------

#all_data %>% dplyr::distinct(MPROG, PURPM, RLABO, MATRX, PARGROUP, PARAM, BASIS, QFLAG, VFLAG, METCU, ALABO, REFSK, METST, METPT, METPS, METCX, METOA, SMTYP, DCFLGs)

# --- Column → CodeType mapping -------------------------------------------
# Note: RLABO/ALABO both map to "RLABO"; PARGROUP maps to "Pargroup"; DCFLGs to "DCFLG"

col_to_codetype <- tribble(
  ~data_col,  ~CodeType,
  "MPROG",    "MPROG",
  "PURPM",    "PURPM",
  "RLABO",    "RLABO",
  "MATRX",    "MATRX",
  "PARGROUP", "Pargroup",
  "PARAM",    "PARAM",
  "BASIS",    "BASIS",
  "QFLAG",    "QFLAG",
  "VFLAG",    "VFLAG",
  "METCU",    "METCU",
  "ALABO",    "RLABO",
  "REFSK",    "REFSK",
  "METST",    "METST",
  "METPT",    "METPT",
  "METPS",    "METPS",
  "METCX",    "METCX",
  "METOA",    "METOA",
  "SMTYP",    "SMTYP",
  "DCFLGs",   "DCFLG"
)

multi_code_cols <- c("MPROG", "PURPM", "QFLAG", "VFLAG", "DCFLGs")

# --- Step 1: Extract distinct raw codes, expand multi-codes --------------

used_codes <- col_to_codetype |>
  mutate(
    raw_code = map(data_col, \(col) {
      all_data |>
        distinct(across(all_of(col))) |>
        pull(col) |>
        discard(is.na)
    })
  ) |>
  unnest(raw_code) |>
  mutate(
    Code = map2(data_col, raw_code, \(col, val) {
      if (col %in% multi_code_cols) str_split_1(val, "~") else val
    })
  ) |>
  unnest(Code)

# --- Step 2: Filter combined_codes to only codes used in all_data --------

used_combined_codes <- combined_codes |>
  semi_join(used_codes, by = c("CodeType", "Code"))

# --- Step 3: Build lookup table ------------------------------------------
# raw_code: the original value in all_data (e.g. "T~S")
# Code:     the individual split code     (e.g. "T", "S")

code_lookup <- used_codes |>
  left_join(
    combined_codes |> select(CodeType, Code, Description),
    by = c("CodeType", "Code")
  )

# ------------------------------
# Update column names
# ------------------------------

col_rename <- tribble(
  ~old,         ~new,
  "MPROG",      "project",
  "PURPM",      "purpose",
  "Country",    "country",
  "RLABO",      "institute",
  "STATN",      "station",
  "MYEAR",      "year",
  "DATE",       "date",
  "Latitude",   "latitude",
  "Longitude",  "longitude",
  "DEPHU",      "depth_from",
  "DEPHL",      "depth_to",
  "MATRX",      "matrix",
  "PARGROUP",   "group",
  "PARAM",      "param",
  "BASIS",      "basis",
  "QFLAG",      "qflag",
  "Value",      "value",
  "MUNIT",      "unit",
  "VFLAG",      "vflag",
  "DETLI",      "detli",
  "LMQNT",      "loq",
  "UNCRT",      "uncrt",
  "METCU",      "metcu",
  "ALABO",      "labo",
  "REFSK",      "ref",
  "METST",      "metst",
  "METPT",      "metpt",
  "METPS",      "metps",
  "METCX",      "metcx",
  "METOA",      "metoa",
  "SMTYP",      "sample_type",
  "SUBNO",      "sub_no",
  "DCFLGs",     "dcflag"
)

# Rename and select all_data in one step
# select() accepts a named vector where names=new, values=old
df_all <- all_data |>
  select(all_of(deframe(col_rename[, c("new", "old")])))

# Update code_lookup using the same col_rename
code_lookup <- code_lookup |>
  left_join(col_rename, by = c("data_col" = "old")) |>
  mutate(data_col = coalesce(new, data_col)) |>
  select(data_col, code_type = CodeType, raw_code, code = Code,
         description = Description)

# Also update the multi_code_cols vector used in lookups
multi_code_cols <- c("project", "purpose", "qflag", "vflag", "dcflag")

# ------------------------------
# Project
# ------------------------------
df_project <- df_all %>% distinct(project, purpose, country, institute) %>%
  arrange(country, institute, project, purpose) %>%
  mutate(project_id = row_number()) %>%
  dplyr::select(project_id, project, purpose, country, institute)

# ------------------------------
# Site
# ------------------------------
df_site <- df_all %>% distinct(station, latitude, longitude) %>%
  arrange(station, latitude, longitude) %>%
  mutate(site_id = row_number()) %>%
  dplyr::select(site_id, station, latitude, longitude)

# ------------------------------
# Sample
# ------------------------------
df_sample <- df_all %>% count(project, purpose, country, institute,
                               station, latitude, longitude,
                               year, date) %>%
  inner_join(df_project, by=c("project", "purpose", "country", "institute")) %>%
  inner_join(df_site, by=c("station", "latitude", "longitude")) %>%
  mutate(sample_id = row_number()) %>%
  dplyr::select(sample_id, project_id, site_id, year, date, sample_size = n)

# ------------------------------
# Parameter
# ------------------------------
df_parameter <- df_all %>% count(group, param) %>%
  inner_join(
    code_lookup %>% filter(data_col == "group") %>% select(raw_code, group_description = description),
    by = c("group" = "raw_code")
  ) %>%
  left_join(
    code_lookup %>% filter(data_col == "param") %>% select(raw_code, param_description = description),
    by = c("param" = "raw_code")
  )



