# 01_extract_meta_information.R
library(tidyverse)
library(readxl)
library(stringr)
library(dplyr)
library(tidyr)

# ------------------------------
# Config
# ------------------------------
data_path <- "./data"
excel_file <- file.path(data_path, "Mareano.xlsx")

info_sheet <- "INFO"

mariano_cruise_range_1 <- "H69:M83"
mariano_cruise_range_2 <- "P69:U83"
mariano_cruise_range_3 <- "X69:AC83"
marinebase_cruise_range <- "AF69:AK83"

element_range_1 <- "A93:G140"
element_range_2 <- "A143:G155"

lld_range_1 <- "H91:AF141"


# ------------------------------
# Source common helpers
# ------------------------------
source(file.path("R", "mareano", "sedimeter_helpers.R"))

# ------------------------------
# Read the whole INFO sheet once (no headers)
# ------------------------------
info_full_raw <- read_sheet_raw(excel_file, info_sheet)

# ------------------------------
# Raw readers (no corrections)
# ------------------------------

# Cruise info: read three Mareano blocks + Marine base block; header is inside each block
read_data_cruise_info <- function(info_df,
                                  mareano_ranges = c(mariano_cruise_range_1,
                                                     mariano_cruise_range_2,
                                                     mariano_cruise_range_3),
                                  marinebase_range = marinebase_cruise_range) {

  # Mareano blocks
  list_mareano <- lapply(mareano_ranges, function(rg) {
    blk <- extract_block_header_in_range(info_df, rg, col_names = NULL)
    blk <- rename_first_match_base(blk, c("Mareano.cruise", "Mareano.cr."), "cruise_no2")
    blk
  })
  mareano_raw <- dplyr::bind_rows(list_mareano) %>%
    dplyr::mutate(cruise_no2 = as.character(.data$cruise_no2)) %>%
    dplyr::filter(!is.na(.data$cruise_no2))

  # Marinebase block
  marinebase_raw <- extract_block_header_in_range(info_df, marinebase_range, col_names = NULL) %>%
    rename_first_match_base(c("MARINE.BASEMAP.Cruise"), "cruise_no2") %>%
    dplyr::mutate(cruise_no2 = as.character(.data$cruise_no2)) %>%
    dplyr::filter(!is.na(.data$cruise_no2))

  dplyr::bind_rows(mareano_raw, marinebase_raw)
}

# Elements: two ranges, force column names
read_data_element_info <- function(info_df,
                                   element_ranges = c(element_range_1, element_range_2),
                                   forced_colnames = c("parameter", "element",
                                                       "c3", "method1", "method2",
                                                       "c4", "institute")) {
  lst <- lapply(element_ranges, function(rg) {
    extract_block_header_in_range(info_df, rg, col_names = forced_colnames)
  })
  dplyr::bind_rows(lst) %>% dplyr::filter(!is.na(.data$parameter))
}

# LLD: one ranges
read_data_lld_info <- function(info_df, lld_range = lld_range_1) {
  extract_block_header_in_range(info_df, lld_range, col_names = NULL) %>%
    rename(parameter = "X") %>%
    pivot_longer(!c(parameter), names_to = "batch_id", values_to = "value") %>%
    mutate(batch_id = map_chr(batch_id, ~str_replace(.x,  pattern = "X",
                                               replacement = ""))) %>%
    drop_na()
}

# ------------------------------
# Corrections
# ------------------------------

correct_df_cruise_info <- function(df) {
  df %>%
    dplyr::mutate(
      dplyr::across(where(is.character), function(x) trimws(x)),
      cruise_no2 = as.character(.data$cruise_no2)
    ) %>%
    dplyr::filter(!(.data$cruise_no2 %in% "26")) %>%
    dplyr::mutate(
      cruise_id = paste("MA", .data$Year, .data$`Cruise.nr`, sep = "-")
    ) %>%
    mutate(
      start = as.Date(as.integer(`from.date`), origin = "1899-12-30"),
      end   = as.Date(as.integer(`to.date`), origin = "1899-12-30"),
      start_year = as.integer(format(start, "%Y")),
      start_month = as.integer(format(start, "%m")),
      start_day = as.integer(format(start, "%d")),
      end_year = as.integer(format(end, "%Y")),
      end_month = as.integer(format(end, "%m")),
      end_day = as.integer(format(end, "%d")),
      start = as.character(start),
      end   = as.character(end),
      ) %>%
    dplyr::select(
      cruise_id,
      start,
      end,
      start_year,
      start_month,
      start_day,
      end_year,
      end_month,
      end_day,
      area  = Area,
      cruise_no2
    )
}

correct_df_element_info <- function(df) {
  df %>%
    drop_where(function(x) x$parameter == "Cs137" & x$institute == "IMR") %>%
    update_where(function(x) x$parameter == "Cs137",
                 list(
                   method2   = "661 and 662 keV gamma peak",
                   institute = "GDC-laboratory / IMR"
                 )) %>%
    drop_where(function(x) x$parameter == "Pb210 tot" & x$institute == "DHI") %>%
    update_where(function(x) x$parameter == "Pb210 tot",
                 list(
                   method1   = "gamma (?) spectroscopy, alpha (?) spectroscopy",
                   method2   = "46,5 keV gamma peak, Po-210 polonium activity",
                   institute = "IMR / GDC-laboratory / DHI"
                 )) %>%
    dplyr::select(parameter, element, method1, method2, institute) %>%
    separate(parameter, c("symbol"), remove = FALSE, extra = "drop") %>%
    dplyr::bind_rows(
      tibble::tibble(
        parameter = "S_p",
        element   = "Sulfur",
        method1   = NA_character_,
        method2   = NA_character_,
        institute = "NGU-Laboratory"
      )
    )
}

correct_df_lld_info <- function(df) {
  df %>%
    filter(!(("not analysed" == value) | (batch_id == ".1"))) %>%
    mutate(parameter = map_chr(parameter, ~str_replace(.x,  pattern = "fract.",
                                                     replacement = "fraction")),
           value = map_chr(value, ~str_replace_all(.x,  pattern = " - .*|>|µm",
                                                       replacement = "")),
           value = map_chr(value, ~str_replace(.x,  pattern = ",",
                                                   replacement = ".")) %>%
             as.numeric(),
    ) %>%
    dplyr::select(
      batch_id,
      parameter,
      value
    )
}

# ------------------------------
# Orchestration
# ------------------------------
df_cruise_info_raw  <- read_data_cruise_info(info_full_raw)
df_element_info_raw <- read_data_element_info(info_full_raw)
df_lld_info_raw <- read_data_lld_info(info_full_raw)

df_cruise_info  <- correct_df_cruise_info(df_cruise_info_raw)
df_element_info <- correct_df_element_info(df_element_info_raw)
df_lld_info <- correct_df_lld_info(df_lld_info_raw)
