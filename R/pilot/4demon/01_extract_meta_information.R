# 01_extract_meta_information.R
library(tidyverse)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data/raw/4Demon"
data_file <- file.path(data_path, "20200713_1007454DEMON_HeavyMetals_PCBs_in_sediment.csv")

col_rename <- tribble(
  ~old,                          ~new,                          ~description,

  # --- Sample identifiers ---
  "SPE_SEQNO",                   "sample_seq_no",               "Sequential sample identifier. Groups all parameters measured from the same physical sample (1,612 unique samples in the dataset).",
  "SVE_SEQNO",                   "survey_seq_no",               "Sequential survey value identifier. Unique per row — one measurement per row.",
  "SAMPLE_REFERENCE_CODE",       "sample_ref_code",             "Original sample reference code combining station, gear, and timestamp (e.g. 99_1979-120-VV-1/01/1979 12:00).",
  "SON_CPN_CODE",                "campaign_code",               "Campaign (survey leg) code combining project prefix and year (e.g. 99_1979). Groups all samples collected in the same annual survey.",
  "SON_TIMESTAMP",               "sample_timestamp",            "Timestamp assigned to the sample event, format DD/MM/YYYY HH:MM. Often set to 01/01/YYYY 12:00 when exact date is unknown.",
  "START_DATE",                  "start_date",                  "Actual sampling date and time where known, format DD/MM/YYYY HH:MM. May differ from sample_timestamp for samples with a recorded date.",

  # --- Time ---
  "YEAR",                        "year",                        "Year of sampling (1971–2014).",
  "month",                       "month",                       "Month of sampling (1–12).",
  "quadri",                      "season",                      "Seasonal quadrimester: 1 = Jan–Apr (winter/spring), 2 = May–Aug (summer), 3 = Sep–Dec (autumn).",

  # --- Sample collection ---
  "SGR_CODE",                    "gear_code",                   "Sampling gear code: VV = Van Veen grab (bulk surface sediment), BC = box corer (intact core).",
  "SSA_DEPTH_RANGE",             "depth_range",                 "Sediment depth range sampled, always '0-20' cm in this dataset.",
  "FSE_RANGE",                   "fraction_range_um",           "Grain size fraction analysed in micrometres (e.g. 0-63 = fine fraction <63 µm, 0-2000 = bulk sediment <2 mm).",
  "REPLICATE_NUMBER",            "replicate_number",            "Replicate index for repeated measurements on the same sample (1, 2, or 3).",

  # --- Station ---
  "STN_GROUP",                   "station_group",               "Station group: BCP = Belgian Continental Platform (offshore), BCP_nearby_coast_(<500m) = nearshore stations within 500 m of coast.",
  "STN_CODE",                    "station_code",                "Station identifier code (162 unique stations).",
  "START_LATITUDE_corr",         "latitude",                    "Corrected latitude of the sampling station (decimal degrees, WGS84).",
  "START_LONGITUDE_corr",        "longitude",                   "Corrected longitude of the sampling station (decimal degrees, WGS84).",

  # --- Project ---
  "PROJECT",                     "project",                     "Monitoring or research project name: BAGGER (dredging monitoring), MONIT_SED (long-term sediment monitoring), MMP_NS_RBINS-MUMM, PMPZ-DBII_PMPZ_COAST, UA_VAN_GRIEKEN.",
  "PJT_SVE_ID",                  "project_survey_id",           "Numeric project identifier (1 = UA_VAN_GRIEKEN, 2 = BAGGER, 3 = MONIT_SED, 7 = PMPZ-DBII_PMPZ_COAST).",

  # --- Matrix and method ---
  "PMX_MTX_CODE",                "matrix_code",                 "Sediment matrix code: FS = fine sediment (<63 µm fraction), US = unsieved / bulk sediment.",
  "AMD_SEQNO",                   "method_seq_no",               "Sequential analytical method identifier (102 unique methods).",
  "AMD_SEQNO_new",               "method_code",                 "Harmonised analytical method code combining project, technique, and fraction (e.g. Monit3_OES/MS_63 = monitoring period 3, ICP-OES/MS, <63 µm fraction).",

  # --- Parameter and value ---
  "PMX_PRR_CODE",                "parameter",                   "Parameter code: metals (AL, AS, CD, CR, CU, FE, HG, NI, PB, ZN) and PCB congeners (CB28, CB52, CB101, CB118, CB138, CB153, CB180).",
  "VALUE_ORIG",                  "value",                       "Original measured value in the reported unit (µg/g dry weight).",
  "VALUE_CORR",                  "corrected_value",             "Corrected or standardised value after quality control (e.g. below-detection substitutions, unit conversions). Use this column for analysis.",
  "PMX_UNT_CODE",                "unit",                        "Unit of measurement: µg/g dry weight (all rows). Note: raw encoding may show as '\\xb5g/g dw' due to the µ character.",

  # --- Quality flags ---
  "VALUE_FLAG",                  "value_flag",                  "Data quality flag: 0 = valid, 1 = suspect, 2 = below detection limit, 3 = invalid.",
  "DETLIMFLAG",                  "det_limit_flag",              "Detection limit flag: 0 = value above detection limit, 1 = value is at or below the detection limit.",
  "range_check_flag",            "range_check_flag",            "Range check flag: 0 = within expected range, 1 = outside expected range, NA = range not checked.",
  "OUTLIER_EXTREME_PRR",         "outlier_extreme_flag",        "Extreme outlier flag per parameter: 0 = normal, 1 = moderate outlier, 2 = extreme outlier.",
  "OUTLIER_FLAG_stdev",          "outlier_stdev_flag",          "Standard deviation outlier flag: 0 = within normal range, 1 = outlier based on standard deviation threshold.",

  # --- Corrected reference ---
  "SAMPLE_REFERENCE_CODE_CORR",  "corrected_sample_ref_code",   "Corrected version of sample_ref_code after resolving duplicates or transcription errors (1,611 unique values vs 1,612 in the original)."
)

# ------------------------------
# Read the whole data 23,542
# ------------------------------
# Apply to the data frame
all_data <- read_csv(data_file) |>
  rename(all_of(setNames(col_rename$old, col_rename$new))) |>
  mutate(unit = ifelse(unit == "\xb5g/g dw", "µg/g dw", unit))

# ------------------------------
# project: one row per project_survey_id 222
# ------------------------------
df_project <- all_data |>
  distinct(project_survey_id, project, campaign_code, year, month, season) |>
  arrange(project_survey_id) |>
  mutate(project_id = row_number()) |>
  arrange(project_survey_id) |>
  select(project_id, project_survey_id, project, campaign_code, year, month, season)

# ------------------------------
# station: deduplicate on station_code + lat/lon, assign surrogate key 166
# ------------------------------
df_station <- all_data |>
  distinct(station_code, station_group, latitude, longitude) |>
  arrange(station_code) |>
  mutate(station_id = row_number()) |>
  select(station_id, station_code, station_group, latitude, longitude)

# ------------------------------
# parameter: classify as metal or PCB 17
# ------------------------------
metal_codes <- c("AL", "AS", "CD", "CR", "CU", "FE", "HG", "NI", "PB", "ZN")

parameter_names <- c(
  "AL"   = "aluminium",
  "AS"   = "arsenic",
  "CD"   = "cadmium",
  "CR"   = "chromium",
  "CU"   = "copper",
  "FE"   = "iron",
  "HG"   = "mercury",
  "NI"   = "nickel",
  "PB"   = "lead",
  "ZN"   = "zinc",
  "CB28"  = "PCB congener 28",
  "CB52"  = "PCB congener 52",
  "CB101" = "PCB congener 101",
  "CB118" = "PCB congener 118",
  "CB138" = "PCB congener 138",
  "CB153" = "PCB congener 153",
  "CB180" = "PCB congener 180"
)

df_parameter <- all_data |>
  distinct(parameter) |>
  arrange(parameter) |>
  mutate(
    parameter_name = parameter_names[parameter],
    parameter_type = if_else(parameter %in% metal_codes, "metal", "PCB")
  )

# ------------------------------
# method 176
# ------------------------------
df_method <- all_data |>
  distinct(method_seq_no, method_code, matrix_code, fraction_range_um) |>
  arrange(method_seq_no) |>
  mutate(method_id = row_number()) |>
  select(method_id, method_seq_no, method_code, matrix_code, fraction_range_um)

# ------------------------------
# --- Build sample table (needs station_id FK) --- 1,796
# ------------------------------
df_sample <- all_data |>
  distinct(sample_seq_no, station_code, latitude, longitude,
           project_survey_id, project, campaign_code, year, month,
           sample_ref_code, sample_timestamp,
           start_date, gear_code, depth_range, replicate_number) |>
  left_join(df_station |> select(station_id, station_code, latitude, longitude),
            by = c("station_code", "latitude", "longitude")) |>
  left_join(df_project |> select(project_id, project_survey_id, project, campaign_code, year, month),
            by = c("project_survey_id", "project", "campaign_code", "year", "month")) |>
  arrange(sample_seq_no) |>
  mutate(sample_id = row_number()) |>
  select(sample_id, sample_seq_no, station_id, project_id,
         sample_ref_code, sample_timestamp, start_date,
         gear_code, depth_range, replicate_number)

# ------------------------------
# --- Build sediment fact table --- 23,542
# ------------------------------
df_sediment <- all_data |>
  left_join(df_method |> select(method_id, method_seq_no, method_code, matrix_code, fraction_range_um),
            by = c("method_seq_no", "method_code", "matrix_code", "fraction_range_um")) |>
  left_join(df_station |> select(station_id, station_code, latitude, longitude),
            by = c("station_code", "latitude", "longitude")) |>
  left_join(df_project |> select(project_id, project_survey_id, project, campaign_code, year, month),
            by = c("project_survey_id", "project", "campaign_code", "year", "month")) |>
  left_join(df_sample |> select(sample_id, sample_seq_no, station_id, project_id, replicate_number),
            by = c("sample_seq_no", "station_id", "project_id", "replicate_number")) |>
  select(survey_seq_no, sample_id, method_id, parameter,
         value, corrected_value, unit,
         value_flag, det_limit_flag, range_check_flag,
         outlier_extreme_flag, outlier_stdev_flag) |>
  arrange(survey_seq_no)
