library(tidyverse)
library(readxl)

# Files
data_path <- "./data"
excel_file <- file.path(data_path, "Mareano.xlsx")

# Excel info
info_sheet <- "INFO"
mariano_cruise_range_1 <- "H69:M83"
mariano_cruise_range_2 <- "P69:U83"
mariano_cruise_range_3 <- "X69:AC83"
marinebase_cruise_range <- "AF69:AK83"
element_range_1 <- "A93:G140"
element_range_2 <- "A143:G155"


repalce_na <- function(x) ifelse(is.na(x), "",  x)

# Info sheet - Cruise info
df_info_mariano_cruise <- read_excel(excel_file,
                                     info_sheet,
                                     mariano_cruise_range_1,
                                     col_names = TRUE) |>
  rename(cruise_no2 = `Mareano cruise`)  |>
  bind_rows(read_excel(excel_file,
                       info_sheet,
                       mariano_cruise_range_2,
                       col_names = TRUE) |>
              rename(cruise_no2 = `Mareano cr.`) |>
              mutate(cruise_no2 = as.character(cruise_no2))) |>
  bind_rows(read_excel(excel_file,
                       info_sheet,
                       mariano_cruise_range_3,
                       col_names = TRUE) |>
              rename(cruise_no2 = `Mareano cr.`) |>
              mutate(cruise_no2 = as.character(cruise_no2))) |>
  filter(!is.na(cruise_no2))

df_info_marinebase_cruise <- read_excel(excel_file,
                                        info_sheet,
                                        marinebase_cruise_range,
                                        col_names = TRUE) |>
  rename(cruise_no2 = `MARINE BASEMAP Cruise`) |>
  mutate(cruise_no2 = as.character(cruise_no2)) |>
  filter(!is.na(cruise_no2))

df_info_cruise <- bind_rows(df_info_mariano_cruise,
                            df_info_marinebase_cruise) |>
  mutate(cruise_id = paste("MA", Year, `Cruise nr`, sep="-")) |>
  dplyr::select(
    cruise_id,
    start = `from date`,
    end = `to date`,
    area = Area,
    cruise_no2
  ) |>
  filter(!(cruise_no2 %in% "26"))

# Info sheet - Elements
df_info_ngu_element <- read_excel(excel_file,
                                  info_sheet,
                                  element_range_1,
                                  col_names = c("parameter",
                                                "element",
                                                "c3", "method1", "method2",
                                                "c4", "institute")) |>
  filter(!is.na(parameter))

df_info_extern_element <- read_excel(excel_file,
                                  info_sheet,
                                  element_range_2,
                                  col_names = c("parameter",
                                                "element",
                                                "c3", "method1", "method2",
                                                "c4", "institute")) |>
  filter(!is.na(parameter))

df_info_extern_element <- df_info_extern_element |>
  filter(!(parameter == "Cs137" & institute == "IMR")) |>
  mutate(method2 = ifelse(parameter == "Cs137", "661 and 662 keV gamma peak", method2),
         institute = ifelse(parameter == "Cs137", "GDC-laboratory / IMR", institute)) |>
filter(!(parameter == "Pb210 tot" & institute == "DHI")) |>
  mutate(method1 = ifelse(parameter == "Pb210 tot", "gamma (?) spectroscopy, alpha (?) spectroscopy", method1),
         method2 = ifelse(parameter == "Pb210 tot", "46,5 keV gamma peak, Po-210 polonium activity", method2),
         institute = ifelse(parameter == "Pb210 tot", "IMR / GDC-laboratory / DHI", institute))



df_info_element <- bind_rows(df_info_ngu_element, df_info_extern_element) |>
  dplyr::select(parameter, element,
                method1, method2, institute) |>
  bind_rows(tibble(parameter = "S_p",
                   element = "Sulfur",
                   method1 = NA_character_,
                   method2 = NA_character_,
                   institute = "NGU-Laboratory"))
