library(tidyverse)
library(readxl)

# Files
data_path <- "./data"
excel_file <- file.path(data_path, "Mareano.xlsx")

# Excel info
inorganic_sheet <- "INORGANIC"
inorganic_col_range <- "A1:BY2"
inorganic_cruise_range <- "A3:E3541"
inorganic_core_range <- "D3:N3541"
inorganic_sample_range <- "A3:P3541"
inorganic_sediment_range <- "A3:BY3541"
inorganic_unit_range <- "R1:BY2"

repalce_na <- function(x) ifelse(is.na(x), "",  x)

# INORGANIC sheet - Column names
df_inorganic_cols <- read_excel(excel_file,
                                inorganic_sheet,
                                inorganic_col_range,
                                col_names = FALSE) |>
  t() |>
  as_tibble(.name_repair = ~c("Row1", "Row2")) |>
  fill(Row1) |>
  mutate(Full = paste(Row1, ifelse(is.na(Row2), "", Row2)) |>
           str_trim()) |>
  mutate(ColType = ifelse(Full %in% c("Cruise year",
                                     "Sample interval (top-bottom) from cm",
                                     "Sample interval (top-bottom) to cm",
                                     "DDE degrees",
                                     "DDN degrees",
                                     "mbsl m"),
                         "numeric", "text"))

# INORGANIC sheet - Cruise
v_inorganic_cruise_cols <- df_inorganic_cols |>
  slice(1:5) |>
  pull(Full)
v_inorganic_cruise_col_types <- df_inorganic_cols |>
  slice(1:5) |>
  pull(ColType)
df_inorganic_cruise <- read_excel(excel_file,
                                  inorganic_sheet,
                                  inorganic_cruise_range,
                                  col_names = v_inorganic_cruise_cols,
                                  col_types = v_inorganic_cruise_col_types) |>
  filter(!is.na(`Cruise year`)) |>
  mutate(cruise_id = paste("MA", `Cruise year`, `Cruise number`, sep="-"),
         source = "Mareano",
         type = ifelse(!is.na(`MAREANO cruise`), "Mareano Cruise",
                       ifelse(!is.na(`Marine Grunnkart cruise`),
                              "Marine Basecamp Cruise", NA_character_)),
         year = as.integer(`Cruise year`),
         month = NA_integer_,
         day = NA_integer_,
         cruise_no = as.character(`Cruise number`)) |>
  distinct(cruise_id, source, type, year, month, day, cruise_no)

# INORGANIC sheet - Core
v_inorganic_core_cols <- df_inorganic_cols |>
  slice(4:14) |>
  pull(Full)
v_inorganic_core_col_types <- df_inorganic_cols |>
  slice(4:14) |>
  pull(ColType)
df_inorganic_core <- read_excel(excel_file,
                                inorganic_sheet,
                                inorganic_core_range,
                                col_names = v_inorganic_core_cols,
                                col_types = v_inorganic_core_col_types) |>
  filter(!is.na(`Cruise year`)) |>
  dplyr::select(-c(`Sample interval (top-bottom) from cm`,
                   `Sample interval (top-bottom) to cm`)) |>
  distinct() |>
  mutate(cruise_id = paste("MA", `Cruise year`, `Cruise number`, sep="-"),
         core_id = paste(`Station number`,
                         `Sampling tool`,
                          ifelse(is.na(`SamplingTool serial ID`), "",  `SamplingTool serial ID`) |>
                            str_pad(width = 3, pad = "0"),
                          ifelse(is.na(`Sample core ID`), "00", `Sample core ID`),
                         sep="-")) |>
  dplyr::select(
    cruise_id,
    core_id,
    station_no = `Station number`,
    sampling_tool =`Sampling tool`,
    tool_id = `SamplingTool serial ID`,
    core_name = `Sample core ID`,
    dde = `DDE degrees`,
    ddn = `DDN degrees`,
    mbsl = `mbsl m`
  )

# INORGANIC sheet - Sample
v_inorganic_sample_cols <- df_inorganic_cols |>
  slice(1:16) |>
  pull(Full)
v_inorganic_sample_col_types <- df_inorganic_cols |>
  slice(1:16) |>
  pull(ColType)

df_inorganic_sample <- read_excel(excel_file,
                                  inorganic_sheet,
                                  inorganic_sample_range,
                                  col_names = v_inorganic_sample_cols,
                                  col_types = v_inorganic_sample_col_types) |>
  filter(!is.na(`Cruise year`)) |>
  dplyr::select(-c(`DDE degrees`, `DDN degrees`, `mbsl m`)) |>
  mutate(full_sample_id = paste0(`Cruise year`, `Cruise number`,
                                 `Station number`, `Sampling tool`,
                                 str_pad(`SamplingTool serial ID`, width = 3, pad = "0") |>
                                   repalce_na(),
                                 ifelse(is.na(`Sample core ID`), "", `Sample core ID`),
                                 "_", str_pad(`Sample interval (top-bottom) from cm`, width = 2, pad = "0"),
                                 "-", str_pad(`Sample interval (top-bottom) to cm`, width = 2, pad = "0")))

incorrect_sample_ids <- df_inorganic_sample |>
  filter(!is.na(`MAREANO cruise`)) |>
  dplyr::select(wrong_id = `1096MC002 Full-ID`,
                correct_id = full_sample_id,
                `Cruise year`, `Cruise number`, `Station number`, `Sampling tool`, `SamplingTool serial ID`) |>
  dplyr::filter(wrong_id != correct_id)

duplicate_sample_ids <- df_inorganic_sample |>
  filter(`1096MC002 Full-ID` %in% c("2021104R2669MC15c1_8-9",
                                    "2021104R2669MC15c1_9-10",
                                    "2021115R2770MC17c1_8-9",
                                    "2021115R2770MC17c1_9-10",
                                    "2021115R2869MC19c1_8-9",
                                    "2021115R2869MC19c1_9-10",
                                    "2021P2009010_00-02",
                                    "2021P2009010_0-2",
                                    "2021P2009012_00-02",
                                    "2021P2009012_0-2",
                                    "2021P2009015_00-02",
                                    "2021P2009015_0-2"))

dim(df_inorganic_sample)

df_inorganic_sample <- df_inorganic_sample |>
  filter(!(`1096MC002 Full-ID` %in% c("2021P2009010_0-2",
                                      "2021P2009012_0-2",
                                      "2021P2009015_0-2"))) |>
  mutate(`Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021104R2669MC15c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021115R2770MC17c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021115R2869MC19c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021104R2669MC15c1_9-10",
                                                         10,
                                                         `Sample interval (top-bottom) to cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021115R2770MC17c1_9-10",
                                                         10,
                                                         `Sample interval (top-bottom) to cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021115R2869MC19c1_9-10",
                                                         10,
                                                         `Sample interval (top-bottom) to cm`))

dim(df_inorganic_sample)

df_inorganic_sample <- df_inorganic_sample |>
  mutate(cruise_id = paste("MA", `Cruise year`, `Cruise number`, sep="-"),
         core_id = paste(`Station number`,
                         `Sampling tool`,
                         ifelse(is.na(`SamplingTool serial ID`), "",  `SamplingTool serial ID`) |>
                           str_pad(width = 3, pad = "0"),
                         ifelse(is.na(`Sample core ID`), "00", `Sample core ID`),
                         sep="-"),
         sample_id = paste0(ifelse(is.na(`Sample core ID`), "00", `Sample core ID`), "_",
                            str_pad(`Sample interval (top-bottom) from cm`, width = 2, pad = "0"), "-",
                            str_pad(`Sample interval (top-bottom) to cm`, width = 2, pad = "0"))) |>
  dplyr::select(cruise_id,
                core_id,
                sample_id,
                depth_from = `Sample interval (top-bottom) from cm`,
                depth_to = `Sample interval (top-bottom) to cm`,
                sample_batch_id = `Sample batch ID`,
                sample_id2 = `Sample ID`)

df_inorganic_sample |> count(cruise_id, core_id, sample_id) |> filter(n > 1)

# INORGANIC sheet - Sediment
v_inorganic_sediment_cols <- df_inorganic_cols |>
  pull(Full)
v_inorganic_sediment_col_types <- df_inorganic_cols |>
  pull(ColType)

df_inorganic_sediment <- read_excel(excel_file,
                                   inorganic_sheet,
                                   inorganic_sediment_range,
                                   col_names = v_inorganic_sediment_cols,
                                   col_types = v_inorganic_sediment_col_types) |>
  filter(!is.na(`Cruise year`)) |>
  filter(!(`1096MC002 Full-ID` %in% c("2021P2009010_0-2",
                                      "2021P2009012_0-2",
                                      "2021P2009015_0-2"))) |>
  mutate(`Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021104R2669MC15c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021115R2770MC17c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) from cm` = ifelse(`1096MC002 Full-ID` == "2021115R2869MC19c1_9-10",
                                                         9,
                                                         `Sample interval (top-bottom) from cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021104R2669MC15c1_9-10",
                                                       10,
                                                       `Sample interval (top-bottom) to cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021115R2770MC17c1_9-10",
                                                       10,
                                                       `Sample interval (top-bottom) to cm`),
         `Sample interval (top-bottom) to cm` = ifelse(`1096MC002 Full-ID` == "2021115R2869MC19c1_9-10",
                                                       10,
                                                       `Sample interval (top-bottom) to cm`)) |>
  mutate(cruise_id = paste("MA", `Cruise year`, `Cruise number`, sep="-"),
         core_id = paste(`Station number`,
                         `Sampling tool`,
                         ifelse(is.na(`SamplingTool serial ID`), "",  `SamplingTool serial ID`) |>
                           str_pad(width = 3, pad = "0"),
                         ifelse(is.na(`Sample core ID`), "00", `Sample core ID`),
                         sep="-"),
         sample_id = paste0(ifelse(is.na(`Sample core ID`), "00", `Sample core ID`), "_",
                            str_pad(`Sample interval (top-bottom) from cm`, width = 2, pad = "0"), "-",
                            str_pad(`Sample interval (top-bottom) to cm`, width = 2, pad = "0"))) |>
  dplyr::select(-c(1:17)) |>
  pivot_longer(!c(cruise_id, core_id, sample_id),
               names_to = "Full", values_to = "value") |>
  filter(!is.na(value) & (value != "n.a.")) |>
  inner_join(df_inorganic_cols %>% dplyr::select(Full, Row1)) |>
  mutate(is_lld = stringr::str_detect(value, fixed("<")),
         new_value = str_remove_all(value, "<|±.*") |>
           as.numeric()) |>
  dplyr::select(cruise_id, core_id, sample_id, parameter=Row1,
                value=new_value, is_lld)

# INORGANIC sheet - Unit
df_inorganic_unit <- read_excel(excel_file,
                                inorganic_sheet,
                                inorganic_unit_range,
                                col_names = FALSE) |>
  t() |>
  as_tibble(.name_repair = ~c("parameter", "unit")) |>
  inner_join(df_inorganic_sediment |> distinct(parameter))
