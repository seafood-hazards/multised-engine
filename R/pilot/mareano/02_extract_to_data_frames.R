# 02_extract_to_data_frames.R
library(tidyverse)
library(readxl)
library(tidyr)
library(dplyr)
library(stringr)

# ------------------------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------------------------
data_path <- "./data/raw/Mareano"
excel_file <- file.path(data_path, "Mareano.xlsx")

inorganic_sheet          <- "INORGANIC"
inorganic_cruise_range   <- "A3:E3541"
inorganic_core_range     <- "D3:N3541"
inorganic_sample_range   <- "A3:P3541"
inorganic_sediment_range <- "A3:BY3541"
inorganic_unit_range <- "R1:BY2"

# Column names we prefer to treat as numeric (hinting) for the catalog
numeric_full_names <- c(
  "Cruise year",
  "Sample interval (top-bottom) from cm",
  "Sample interval (top-bottom) to cm",
  "DDE degrees",
  "DDN degrees",
  "mbsl m"
)

# Sample/Sediment corrections: table-driven (drop or fix specific Full-ID rows)
sample_sediment_corrections <- tibble::tribble(
  ~full_id,                        ~drop, ~new_from, ~new_to,
  "2021P2009010_0-2",               TRUE,      NA,      NA,
  "2021P2009012_0-2",               TRUE,      NA,      NA,
  "2021P2009015_0-2",               TRUE,      NA,      NA,
  "2021104R2669MC15c1_9-10",       FALSE,       9,      10,
  "2021115R2770MC17c1_9-10",       FALSE,       9,      10,
  "2021115R2869MC19c1_9-10",       FALSE,       9,      10
)

# ------------------------------------------------------------------------------
# Source common helpers
# ------------------------------------------------------------------------------
source(file.path("R", "pilot", "mareano", "sedimeter_helpers.R"))

# ------------------------------------------------------------------------------
# READ the sheet once + build catalog from top two rows
# ------------------------------------------------------------------------------
inorg_full_raw    <- read_sheet_raw(excel_file, inorganic_sheet)
df_inorganic_cols <- build_two_row_header_catalog(
  inorg_full_raw,
  header_rows = 1:2,
  numeric_full_names = numeric_full_names
)

# ------------------------------------------------------------------------------
# READ-DATA FUNCTIONS (RAW; NO FIXES, NO IDS)
# ------------------------------------------------------------------------------
read_data_inorganic_cruise <- function(sheet_df, catalog, cruise_range) {
  slice_block_with_catalog(sheet_df, catalog, cruise_range)
}

read_data_inorganic_core <- function(sheet_df, catalog, core_range) {
  slice_block_with_catalog(sheet_df, catalog, core_range)
}

read_data_inorganic_sample <- function(sheet_df, catalog, sample_range) {
  slice_block_with_catalog(sheet_df, catalog, sample_range)
}

read_data_inorganic_sediment <- function(sheet_df, catalog, sediment_range) {
  slice_block_with_catalog(sheet_df, catalog, sediment_range)
}

read_data_inorganic_unit <- function(catalog, unit_range) {
  dims <- parse_excel_range(unit_range)
  cols <- seq.int(dims$col1, dims$col2)

  cols <- intersect(cols, catalog$col_index)

  if (length(cols) == 0) {
    stop("read_data_inorganic_unit(): No overlapping columns found for range: ", unit_range)
  }

  subcat <- catalog[catalog$col_index %in% cols, , drop = FALSE]

  tibble::tibble(
    parameter = subcat$Row1,
    unit      = subcat$Row2,
    Full      = subcat$Full
  )
}

# ------------------------------------------------------------------------------
# CORRECT-DATA FUNCTIONS (FILTER, FIX, IDS, TYPES, SHAPE)
# ------------------------------------------------------------------------------
correct_data_inorganic_cruise <- function(df) {
  df <- dplyr::mutate(df, dplyr::across(where(is.character), function(x) stringr::str_trim(x)))
  if ("Cruise year" %in% names(df)) {
    df <- dplyr::filter(df, !is.na(.data$`Cruise year`) & .data$`Cruise year` != "")
  }
  has_mareano <- "MAREANO cruise" %in% names(df)
  has_mg      <- "Marine Grunnkart cruise" %in% names(df)

  df <- dplyr::mutate(
    df,
    year      = suppressWarnings(as.integer(.data$`Cruise year`)),
    cruise_no = as.character(.data$`Cruise number`),
    source    = "Mareano",
    cruise_type = ifelse(
      has_mareano & !is.na(.data$`MAREANO cruise`), "Mareano Cruise",
      ifelse(has_mg & !is.na(.data$`Marine Grunnkart cruise`), "Marine Basecamp Cruise", NA_character_)
    ),
    cruise_id = build_cruise_id(.data$`Cruise year`, .data$`Cruise number`)
  ) %>%
  dplyr::distinct(cruise_id, source, cruise_type, year, cruise_no)

  df
}

correct_data_inorganic_core <- function(df) {
  if ("Cruise year" %in% names(df)) {
    df <- dplyr::filter(df, !is.na(.data$`Cruise year`) & .data$`Cruise year` != "")
  }

  df <- dplyr::mutate(
    df,
    cruise_id = build_cruise_id(.data$`Cruise year`, .data$`Cruise number`),
    core_id   = build_core_id(.data$`Station number`,
                              .data$`Sampling tool`,
                              .data$`SamplingTool serial ID`,
                              .data$`Sample core ID`)
  )

  if ("DDN degrees" %in% names(df)) df[["DDN degrees"]] <- to_numeric_safe(df[["DDN degrees"]])
  if ("DDE degrees" %in% names(df)) df[["DDE degrees"]] <- to_numeric_safe(df[["DDE degrees"]])
  if ("mbsl m" %in% names(df))      df[["mbsl m"]]      <- to_numeric_safe(df[["mbsl m"]])

  df <- dplyr::select(
    df,
    cruise_id,
    core_id,
    station_no    = `Station number`,
    sampling_tool = `Sampling tool`,
    tool_id       = `SamplingTool serial ID`,
    core_name     = `Sample core ID`,
    ddn           = `DDN degrees`,
    dde           = `DDE degrees`,
    mbsl          = `mbsl m`
  ) %>%
  dplyr::distinct()

  df
}

correct_data_inorganic_sample <- function(df) {
  if ("Cruise year" %in% names(df)) {
    df <- dplyr::filter(df, !is.na(.data$`Cruise year`) & .data$`Cruise year` != "")
  }

  full_id_col <- "1096MC002 Full-ID"
  from_col    <- "Sample interval (top-bottom) from cm"
  to_col      <- "Sample interval (top-bottom) to cm"
  if (full_id_col %in% names(df)) {
    df <- apply_fullid_corrections(df, full_id_col, from_col, to_col, sample_sediment_corrections)
  }

  df <- dplyr::mutate(
    df,
    `SamplingTool serial ID` = repalce_na(.data$`SamplingTool serial ID`),
    `SamplingTool serial ID` = ifelse(.data$`SamplingTool serial ID` == "", "",
                                      stringr::str_pad(.data$`SamplingTool serial ID`, width = 3, side = "left", pad = "0")),
    cruise_id = build_cruise_id(.data$`Cruise year`, .data$`Cruise number`),
    core_id   = build_core_id(.data$`Station number`, .data$`Sampling tool`, .data$`SamplingTool serial ID`, .data$`Sample core ID`),
    sample_id = paste0(
      ifelse(is.na(.data$`Sample core ID`) | .data$`Sample core ID` == "", "00", .data$`Sample core ID`), "_",
      stringr::str_pad(as.character(.data$`Sample interval (top-bottom) from cm`), width = 2, side = "left", pad = "0"), "-",
      stringr::str_pad(as.character(.data$`Sample interval (top-bottom) to cm`),   width = 2, side = "left", pad = "0")
    )
  )

  df <- dplyr::select(
    df,
    cruise_id,
    core_id,
    sample_id,
    depth_from      = `Sample interval (top-bottom) from cm`,
    depth_to        = `Sample interval (top-bottom) to cm`,
    batch_id = `Sample batch ID`,
    sample_id2      = `Sample ID`
  )

  ##> df_missing_batch_ids
  # A tibble: 9 × 2
  ##cruise_id    batch_id
  ##<chr>        <chr>
  ##1 MA-2007-105  2008.0009
  ##2 MA-2007-111  2008.0009
  ##3 MA-2009-105  2010.021
  ##4 MA-2009-111  2010.021
  ##5 MA-2010-110  2011.003
  ##6 MA-2010-112  2011.003
  ##7 MA-2020-2002 2020.0118
  ##8 MA-2021-2005 2020.0161
  ##9 MA-2021-2102 2021.211

  df |>
    mutate(sample_id2 = ifelse(is.na(sample_id2), batch_id, sample_id2),
           batch_id = ifelse(cruise_id %in% c("MA-2021-103", "MA-2021-104", "MA-2021-115"),
                             "2021.0031", batch_id),
           batch_id = case_when(
             batch_id == "2008.0009" ~ "2008.0029",
             batch_id == "2010.021" ~ "2009.0222",
             batch_id == "2011.003" ~ "2011.0030",
             batch_id == "2020.0118" ~ "2020.0021",
             batch_id == "2020.0161" ~ "2020.0021",
             batch_id == "2021.211" ~ "2021.0003",
             .default = batch_id
           ))
}

correct_data_inorganic_sediment <- function(df, catalog) {
  if ("Cruise year" %in% names(df)) {
    df <- dplyr::filter(df, !is.na(.data$`Cruise year`) & .data$`Cruise year` != "")
  }

  full_id_col <- "1096MC002 Full-ID"
  from_col    <- "Sample interval (top-bottom) from cm"
  to_col      <- "Sample interval (top-bottom) to cm"
  if (full_id_col %in% names(df)) {
    df <- apply_fullid_corrections(df, full_id_col, from_col, to_col, sample_sediment_corrections)
  }

  df <- dplyr::mutate(
    df,
    `SamplingTool serial ID` = repalce_na(.data$`SamplingTool serial ID`),
    `SamplingTool serial ID` = ifelse(.data$`SamplingTool serial ID` == "", "",
                                      stringr::str_pad(.data$`SamplingTool serial ID`, width = 3, side = "left", pad = "0")),
    cruise_id = build_cruise_id(.data$`Cruise year`, .data$`Cruise number`),
    core_id   = build_core_id(.data$`Station number`, .data$`Sampling tool`, .data$`SamplingTool serial ID`, .data$`Sample core ID`),
    sample_id = paste0(
      ifelse(is.na(.data$`Sample core ID`) | .data$`Sample core ID` == "", "00", .data$`Sample core ID`), "_",
      stringr::str_pad(as.character(.data$`Sample interval (top-bottom) from cm`), width = 2, side = "left", pad = "0"), "-",
      stringr::str_pad(as.character(.data$`Sample interval (top-bottom) to cm`),   width = 2, side = "left", pad = "0")
    )
  )

  # Use common helper to pivot measurement columns using catalog Row2 (units)
  long_df <- pivot_measurements_long(
    df,
    catalog = catalog,
    id_cols = c("cruise_id", "core_id", "sample_id")
  )

  long_df
}

correct_data_inorganic_unit <- function(unit_df, sediment_df) {
  unit_df %>%
    dplyr::filter(!is.na(.data$unit) & .data$unit != "") %>%
    dplyr::select(parameter = .data$parameter, unit = .data$unit) %>%
    dplyr::inner_join(dplyr::distinct(sediment_df, .data$parameter), by = "parameter")
}

# ------------------------------------------------------------------------------
# Orchestration — read once, then pipe through
# ------------------------------------------------------------------------------
df_inorganic_cruise_raw   <- read_data_inorganic_cruise(inorg_full_raw, df_inorganic_cols, inorganic_cruise_range)
df_inorganic_core_raw     <- read_data_inorganic_core(inorg_full_raw,   df_inorganic_cols, inorganic_core_range)
df_inorganic_sample_raw   <- read_data_inorganic_sample(inorg_full_raw, df_inorganic_cols, inorganic_sample_range)
df_inorganic_sediment_raw <- read_data_inorganic_sediment(inorg_full_raw, df_inorganic_cols, inorganic_sediment_range)
df_inorganic_unit_raw     <- read_data_inorganic_unit(df_inorganic_cols, inorganic_unit_range)

df_inorganic_cruise   <- correct_data_inorganic_cruise(df_inorganic_cruise_raw)
df_inorganic_core     <- correct_data_inorganic_core(df_inorganic_core_raw)
df_inorganic_sample   <- correct_data_inorganic_sample(df_inorganic_sample_raw)
df_inorganic_sediment <- correct_data_inorganic_sediment(df_inorganic_sediment_raw, df_inorganic_cols)
df_inorganic_unit     <- correct_data_inorganic_unit(df_inorganic_unit_raw, df_inorganic_sediment)
