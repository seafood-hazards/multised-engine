# ── Pilot step 1, Mareano ────────────────────────────────────────────────────
# Mareano is the only pilot source whose parse was split across several
# scripts that handed data frames to one another:
#
#   01_extract_meta_information.R   INFO sheet: cruise, element and LLD metadata
#   02_extract_to_data_frames.R     INORGANIC sheet: cruise, core, sample,
#                                   sediment and unit blocks
#   03_merge_data_frames.R          joins the two into the six pilot tables
#   03_merge_p230_p250.R            appends the two 2023/2025 surface-sample
#                                   workbooks, which ship in a different layout
#
# They are joined here into one function. The read and correct bodies are
# reproduced verbatim; only the orchestration at the bottom is rewritten, and
# the hardcoded ./data/raw/Mareano paths become `raw_dir`.
#
# 03_merge_data_frames.R also computed `df_missing_batch_ids`, a nine-row
# diagnostic it printed and nothing consumed. It is not reproduced.

# ── Config: workbook sheets and the ranges each block occupies ───────────────

info_sheet <- "INFO"

mariano_cruise_range_1 <- "H69:M83"
mariano_cruise_range_2 <- "P69:U83"
mariano_cruise_range_3 <- "X69:AC83"
marinebase_cruise_range <- "AF69:AK83"

element_range_1 <- "A93:G140"
element_range_2 <- "A143:G155"

lld_range_1 <- "H91:AF141"
lld_range_2 <- "H91:AH141"

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

# ── INFO sheet: raw readers ─────────────────────────────────────────────────
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
    filter(!is.na(parameter)) %>%
    fill_from_right() %>%
    pivot_longer(!c(parameter), names_to = "batch_id", values_to = "value") %>%
    mutate(batch_id = map_chr(batch_id, ~str_replace(.x,  pattern = "X",
                                               replacement = ""))) %>%
    filter(!is.na(parameter)) %>%
    drop_na()
}

# LLD: comment
read_data_lld_comment <- function(info_df, lld_range = lld_range_2) {
  extract_block_header_in_range(info_df, lld_range, col_names = NULL) %>%
    rename(parameter = "X") %>%
    mutate(batch_id = "comment") %>%
    dplyr::select(parameter, comment = Comment) %>%
    drop_na()
}

# ── INFO sheet: corrections ─────────────────────────────────────────────────
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
    mutate(element = ifelse(parameter == "Cd_p", "Cadmium",
                            str_replace(element, "\\?m", "\u00b5m"))) %>%
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
           value = map_chr(value, ~str_replace_all(.x,  pattern = " - .*|>|\u00b5m",
                                                       replacement = "")),
           value = map_chr(value, ~str_replace(.x,  pattern = ",",
                                                   replacement = ".")) %>%
             as.numeric(),
    ) %>%
    dplyr::select(
      batch_id,
      parameter,
      value,
      comment
    )
}

# ── INORGANIC sheet: raw readers ────────────────────────────────────────────
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

# ── INORGANIC sheet: corrections ────────────────────────────────────────────
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


pilot_extract_mareano <- function(raw_dir = multised_raw_dir(), verbose = TRUE) {
  require_suggested("readxl", "The Mareano pilot parser")

  data_path  <- file.path(raw_dir, "Mareano")
  excel_file <- file.path(data_path, "Mareano.xlsx")

  needed <- c(excel_file,
              file.path(data_path, "P2301_surfacedata_GISprepared_draft.xlsx"),
              file.path(data_path,
                        "P2501_surfacesamples_GISprepared_ICP_coulter_POPs.xlsx"))
  for (f in needed) {
    if (!file.exists(f)) stop("Mareano export not found: ", f, call. = FALSE)
  }

  # ── INFO sheet ────────────────────────────────────────────────────────────
  info_full_raw <- read_sheet_raw(excel_file, info_sheet)

  df_cruise_info_raw  <- read_data_cruise_info(info_full_raw)
  df_element_info_raw <- read_data_element_info(info_full_raw)
  df_lld_info_raw <- read_data_lld_info(info_full_raw) %>%
    left_join(read_data_lld_comment(info_full_raw))

  df_cruise_info  <- correct_df_cruise_info(df_cruise_info_raw)
  df_element_info <- correct_df_element_info(df_element_info_raw)
  df_lld_info <- correct_df_lld_info(df_lld_info_raw)

  # ── INORGANIC sheet ───────────────────────────────────
  inorg_full_raw    <- read_sheet_raw(excel_file, inorganic_sheet)
  df_inorganic_cols <- build_two_row_header_catalog(
    inorg_full_raw,
    header_rows = 1:2,
    numeric_full_names = numeric_full_names
  )
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

  # ── Merge the two sheets into the six pilot tables ────────────────
  df_cruise <- df_inorganic_cruise |>
    left_join(df_cruise_info, by="cruise_id")

  df_core <- df_inorganic_core |>
    inner_join(df_cruise |> distinct(cruise_id), by="cruise_id")

  df_sample <- df_inorganic_sample |>
    inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
    inner_join(df_core |> distinct(core_id), by="core_id") %>%
    mutate(depth_from = as.integer(depth_from),
           depth_to = as.integer(depth_to))

  df_parameter <- df_inorganic_unit |>
    left_join(df_element_info, by = "parameter")

  df_sediment <- df_inorganic_sediment |>
    inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
    inner_join(df_core |> distinct(core_id), by="core_id") |>
    inner_join(df_sample |> distinct(sample_id), by="sample_id") |>
    inner_join(df_parameter |> distinct(parameter), by="parameter")

  df_lld <- df_lld_info

  # ── Append the P2301 / P2501 surface-sample workbooks ────────────
  p230_df <- readxl::read_excel(file.path(data_path, "P2301_surfacedata_GISprepared_draft.xlsx")) %>%
    mutate(cruise_id = "MA-2023-230") %>%
    dplyr::select(cruise_id,
                  station = Stasjon,
                  station_no = Stasjon_kort,
                  ngu_id = `P2301_NGU ID`,
                  depth = `Water Depth`,
                  sample_depth = `Sample Depth`,
                  lat = N,
                  lon = E,
                  TS,
                  TC,
                  TOC,
                  CaCO3,
                  `Clay fraction` = Clay,
                  `Silt fraction` = Silt,
                  `Sand fraction` = Sand,
                  `Gravel fraction` = Slam,
                  Al_p = Al,
                  As_p = As,
                  B_p = B,
                  Ba_p = Ba,
                  Be_p = Be,
                  Ca_p = Ca,
                  Cd_p = Cd,
                  Ce_p = Ce,
                  Co_p = Co,
                  Cr_p = Cr,
                  Cu_p = Cu,
                  Fe_p = Fe,
                  K_p = K,
                  La_p = La,
                  Li_p = Li,
                  Mg_p = Mg,
                  Mn_p = Mn,
                  Mo_p = Mo,
                  Na_p = Na,
                  Ni_p = Ni,
                  P_p = P,
                  Pb_p = Pb,
                  S_p = S,
                  Sc_p = Sc,
                  Se_p = Se,
                  Si_p = Si,
                  Sr_p = Sr,
                  Ti_p = Ti,
                  V_p = V,
                  Y_p = Y,
                  Zn_p = Zn,
                  Zr_p = Zr,
                  Hg
                  #Fenantren,
                  #Antracen,
                  #Pyren,
                  #`Benzo[a]pyren`,
                  #Perylen,
                  #`Sum PAH`,
                  #`Sum NPD`,
                  #`Sum PAH16`,
                  #THC,
                  #`Sum PBDE`,
                  #`BDE 209`,
                  #PCB7,
                  #`Sum DDT`,
                  #`Sum HCH`,
                  #HCB,
                  #TNC,
                  #`Sum 7 PFAS`
                  )

  p250_df <- readxl::read_excel(file.path(data_path,
                       "P2501_surfacesamples_GISprepared_ICP_coulter_POPs.xlsx")) %>%
    mutate(cruise_id = "MA-2023-250",
           Naftalen = NA,
           Fenantren = NA,
           Antracen = NA,
           Pyren = NA,
           Perylen = NA) %>%
    dplyr::select(cruise_id,
                  station = Stasjon,
                  station_no = Stasjon_kort,
                  ngu_id = `P2301_NGU ID`,
                  depth = `Water Depth`,
                  sample_depth = `Sample Depth`,
                  lat = N,
                  lon = E,
                  TS,
                  TC,
                  TOC,
                  CaCO3,
                  `Clay fraction` = Leire,
                  `Silt fraction` = Silt,
                  `Sand fraction` = Sand,
                  `Gravel fraction` = Slam,
                  Al_p = Al,
                  As_p = As,
                  B_p = B,
                  Ba_p = Ba,
                  Be_p = Be,
                  Ca_p = Ca,
                  Cd_p = Cd,
                  Ce_p = Ce,
                  Co_p = Co,
                  Cr_p = Cr,
                  Cu_p = Cu,
                  Fe_p = Fe,
                  K_p = K,
                  La_p = La,
                  Li_p = Li,
                  Mg_p = Mg,
                  Mn_p = Mn,
                  Mo_p = Mo,
                  Na_p = Na,
                  Ni_p = Ni,
                  P_p = P,
                  Pb_p = Pb,
                  S_p = S,
                  Sc_p = Sc,
                  Se_p = Se,
                  Si_p = Si,
                  Sr_p = Sr,
                  Ti_p = Ti,
                  V_p = V,
                  Y_p = Y,
                  Zn_p = Zn,
                  Zr_p = Zr,
                  Hg
                  #Naftalen,
                  #Fenantren,
                  #Antracen,
                  #Pyren,
                  #`Benzo[a]pyren`,
                  #Perylen,
                  #`Sum PAH`,
                  #`Sum NPD` = NPD,
                  #`Sum PAH16` = PAH16,
                  #THC,
                  #`Sum PBDE`,
                  #`BDE 209`,
                  #PCB7,
                  #`Sum DDT`,
                  #`Sum HCH`,
                  #HCB,
                  #TNC,
                  #`Sum 7 PFAS` = `7 PFAS`
                  )

  cruise_info_p230_p250 <- tibble::tribble(
    ~cruise_id,    ~source,   ~cruise_type,             ~year, ~cruise_no, ~start, ~end,  ~start_year, ~start_month, ~start_day, ~end_year, ~end_month, ~end_day, ~area,      ~cruise_no2,
    "MA-2023-230", "Mareano", "Marine Basecamp Cruise", 2023,  "230",      NA,     NA,    NA,          NA,           NA,         NA,        NA,         NA,       "Vestland", NA,
    "MA-2023-250", "Mareano", "Marine Basecamp Cruise", 2025,  "250",      NA,     NA,    NA,          NA,           NA,         NA,        NA,         NA,       "Vestland", NA,
  )

  p230_p250_df <- bind_rows(p230_df, p250_df)

  core_tbl_p230_p250 <- p230_p250_df %>%
    mutate(core_id = paste(paste(station, station_no, sep = "_"),
                           "NA",
                           paste0("c", sample_depth),
                           sep = "-"),
           sampling_tool = NA,
           tool_id = NA,
           core_name = paste0("c", sample_depth),
           mbsl = depth * -1) %>%
    distinct(cruise_id,
             core_id,
             station_no = station,
             sampling_tool,
             tool_id,
             core_name,
             ddn = lat,
             dde = lon,
             mbsl)

  sample_tbl_p230_p250 <- p230_p250_df %>%
    mutate(core_id = paste(paste(station, station_no, sep = "_"),
                           "NA",
                           paste0("c", sample_depth),
                           sep = "-"),
           sample_id = paste(core_id, "0", "0", sep = "-"),
           batch_id = "2022.0016",
           sample_id2 = as.character(ngu_id)) %>%
    distinct(cruise_id,
             core_id,
             sample_id,
             depth_from = sample_depth,
             depth_to = sample_depth,
             batch_id,
             sample_id2)


  df_lld_tbl_p230_p250 <- df_lld %>%
    filter(batch_id == "2022.0016") %>%
    mutate(lld = as.numeric(value)) %>%
    dplyr::select(parameter, lld)

  sediment_tbl_p230_p250 <- p230_p250_df %>%
    mutate(core_id = paste(paste(station, station_no, sep = "_"),
                           "NA",
                           paste0("c", sample_depth),
                           sep = "-"),
           sample_id = paste(core_id, "0", "0", sep = "-")) %>%
    dplyr::select(-c(station, station_no, ngu_id, depth, sample_depth, lat, lon)) %>%
    pivot_longer(!c(cruise_id, core_id, sample_id), names_to = "parameter") %>%
    left_join(df_lld_tbl_p230_p250, by = c("parameter")) %>%
    filter(!is.na(lld)) %>%
    mutate(is_lld = ifelse(parameter %in% c("Clay fraction",
                                        "Silt fraction",
                                        "Sand fraction",
                                        "Gravel fraction"),
                           FALSE,
                           value <= lld)) %>%
    dplyr::select(-lld)


  df_cruise <- bind_rows(df_cruise, cruise_info_p230_p250)
  df_core <- bind_rows(df_core, core_tbl_p230_p250)
  df_sample <- bind_rows(df_sample, sample_tbl_p230_p250)
  df_sediment <- bind_rows(df_sediment, sediment_tbl_p230_p250)

  if (verbose) {
    cat(sprintf(paste0("mareano parsed: cruise %d, core %d, sample %d, ",
                       "parameter %d, sediment %d, lld %d\n"),
                nrow(df_cruise), nrow(df_core), nrow(df_sample),
                nrow(df_parameter), nrow(df_sediment), nrow(df_lld)))
  }

  list(cruise    = df_cruise,
       core      = df_core,
       sample    = df_sample,
       parameter = df_parameter,
       sediment  = df_sediment,
       lld       = df_lld)
}

