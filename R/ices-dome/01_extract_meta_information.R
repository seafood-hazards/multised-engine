# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/ICES DOME/Metals and matalloids"
data_file <- file.path(data_path, "ContaminantsSediment_2026032611051738.csv")

data_path <- "./data/ICES DOME"
data_file <- file.path(data_path, "DomeSediment_Data_0326015962.csv")

code_path <- "./data/ICES DOME/code"

# ------------------------------
# Read the whole data
# ------------------------------
all_data <- read_csv(data_file) |>
  mutate(PARAM = if_else(is.na(PARAM), "NA", toupper(PARAM)),
         MATRX = if_else(MATRX == "SEDTOT", "SEDtot", MATRX),
         RLABO = ifelse(RLABO == "LNUG", "LUNG", RLABO),
         ALABO = ifelse(ALABO == "LNUG", "LUNG", ALABO)) |>
  filter(Longitude >= -30 & Longitude <= 30) %>%
  filter(PARGROUP %in% c("B-BIO", "I-MAJ", "I-MET", "P-PHY"))

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
  list_rbind() |>
  mutate(Code = ifelse(Description == "sodium", "NA", Code))


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

multi_code_cols <- c("MPROG", "PURPM", "QFLAG", "VFLAG", "DCFLGs", "METPT", "METCX")

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
  unnest(Code) |>
  mutate(Code = ifelse(Code == "21-CONVR-1", "21-METPT-1", Code))

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
  "PARGROUP",   "group_code",
  "PARAM",      "param",
  "BASIS",      "basis",
  "QFLAG",      "qflag",
  "Value",      "value",
  "MUNIT",      "unit",
  "VFLAG",      "vflag",
  "DETLI",      "lod",
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
  distinct(data_col, code_type = CodeType, raw_code, code = Code,
           description = Description)

# Also update the multi_code_cols vector used in lookups
multi_code_cols <- c("project", "purpose", "qflag", "vflag", "dcflag", "metpt", "metcx")

# ------------------------------
# Project 140 (I-MET) -> 147 (I-MET & I-MAJ)
# ------------------------------
df_project <- df_all %>% distinct(project, purpose, country, institute) %>%
  arrange(country, institute, project, purpose) %>%
  mutate(project_id = row_number()) %>%
  dplyr::select(project_id, project, purpose, country, institute)

# ------------------------------
# Site 8,130 (I-MET) -> 11,071 (I-MET & I-MAJ)
# ------------------------------
df_site <- df_all %>% distinct(station, latitude, longitude) %>%
  arrange(station, latitude, longitude) %>%
  mutate(site_id = row_number()) %>%
  dplyr::select(site_id, station, latitude, longitude)

# ------------------------------
# Sample 13,977 (I-MET) -> 17,318 (I-MET & I-MAJ)
# ------------------------------
df_sample <- df_all %>% count(project, purpose, country, institute,
                               station, latitude, longitude,
                               year, date, sample_type) %>%
  inner_join(df_project, by=c("project", "purpose", "country", "institute")) %>%
  inner_join(df_site, by=c("station", "latitude", "longitude")) %>%
  mutate(sample_id = row_number()) %>%
  left_join(
    code_lookup %>% filter(data_col == "sample_type") %>% select(raw_code, sample_type_description = description),
    by = c("sample_type" = "raw_code")
  )  %>%
  dplyr::select(sample_id, project_id, site_id, year, date, sample_type, sample_type_description, row_count = n)

# ------------------------------
# Parameter 119 (I-MET) -> 138 (I-MET & I-MAJ)
# ------------------------------
df_parameter <- df_all %>% count(group_code, param) %>%
  inner_join(
    code_lookup %>% filter(data_col == "group_code") %>% select(raw_code, group_description = description),
    by = c("group_code" = "raw_code")
  ) %>%
  inner_join(
    code_lookup %>% filter(data_col == "param") %>% select(raw_code, param_description = description),
    by = c("param" = "raw_code")
  ) %>%
  dplyr::select(param, param_description, group_code, group_description, row_count=n)

# ------------------------------
# LLD 1,422 (I-MET) -> 1,480 (I-MET & I-MAJ)
# ------------------------------
df_lld <- df_all %>% count(param, lod, loq)  %>%
  mutate(lld_id = row_number()) %>%
  dplyr::select(lld_id, param, lod, loq, row_count = n)

# ------------------------------
# Analysis method 2,526 (I-MET) -> 2,453 (I-MET & I-MAJ)
# ------------------------------
df_analysis_method <- df_all %>% count(param, labo, metst, metpt, metps, metcx, metoa)  %>%
  mutate(analysis_id = row_number()) %>%
  dplyr::select(analysis_id, param, labo, metst, metpt, metps, metcx, metoa, row_count = n)

# ------------------------------
# Reference 25
# ------------------------------
df_referance <- df_all %>% count(ref) %>%
  left_join(
    code_lookup %>% filter(data_col == "ref") %>% select(raw_code, ref_description = description),
    by = c("ref" = "raw_code")
    ) %>%
  mutate(ref_id = row_number()) %>%
  dplyr::select(ref_id, ref, ref_description, row_count = n)

# ------------------------------
# Sediment 302,159 -> 296,027 (I-MET) -> 325,893 (I-MET & I-MAJ)
# ------------------------------
df_sediment <- df_all %>%
  inner_join(df_project, by = c("project", "purpose", "country", "institute")) %>%
  inner_join(df_site, by = c("station", "latitude", "longitude")) %>%
  inner_join(df_sample, by = c("project_id", "site_id", "year", "date", "sample_type")) %>%
  inner_join(df_parameter, by = c("param", "group_code")) %>%
  inner_join(df_lld, by = c("param", "lod", "loq")) %>%
  inner_join(df_analysis_method, by = c("param", "labo", "metst", "metpt", "metps", "metcx", "metoa")) %>%
  inner_join(df_referance, by = "ref") %>%
  dplyr::select(project_id, site_id, sample_id, year, date, sample_type,
                depth_from, depth_to, matrix, param, value, unit,
                basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                sub_no, dcflag) %>%
  arrange(project_id, site_id, year, date, param, depth_from, depth_to) %>%
  group_by(project_id, site_id, year, date, param) %>%
  mutate(sediment_no = row_number()) %>%
  ungroup() %>%
  dplyr::select(project_id, site_id, sample_id, param,
                sediment_no, depth_from, depth_to, matrix,
                value, unit,
                basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                sub_no, dcflag)
