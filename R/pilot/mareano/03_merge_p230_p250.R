library(tidyverse)
library(readxl)

p230_df <- read_excel("./data/raw/Mareano/P2301_surfacedata_GISprepared_draft.xlsx") %>%
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

p250_df <- read_excel("./data/raw/Mareano/P2501_surfacesamples_GISprepared_ICP_coulter_POPs.xlsx") %>%
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
