library(DBI)
library(RSQLite)
library(tidyverse)

# 1. Connect and Enable Foreign Keys
con <- dbConnect(RSQLite::SQLite(), "./data/db/pilot_ices_dome.sqlite")

code_lookup <- dbReadTable(con, "code_lookup") |> as_tibble()
df_project <- dbReadTable(con, "project") |> as_tibble()
df_site <- dbReadTable(con, "site") |> as_tibble()
df_parameter <- dbReadTable(con, "parameter") |> as_tibble()
df_lld <- dbReadTable(con, "lld") |> as_tibble()
df_analysis_method <- dbReadTable(con, "analysis_method") |> as_tibble()
df_referance <- dbReadTable(con, "reference") |> as_tibble()
df_sample <- dbReadTable(con, "sample") |> as_tibble()
df_sediment <- dbReadTable(con, "sediment") |> as_tibble()

df_ices_dome_sediment <- df_sediment %>%
  inner_join(df_project, by="project_id") %>%
  inner_join(df_site, by="site_id") %>%
  inner_join(df_sample %>% dplyr::select(sample_id, year, date, sample_type, sample_type_description), by="sample_id") %>%
  inner_join(df_parameter, by="param") %>%
  left_join(df_lld, by=c("lld_id", "param")) %>%
  left_join(df_analysis_method , by=c("analysis_id", "param")) %>%
  dplyr::select(project_id, project, country,
                site_id, latitude, longitude, dist_to_coast, est_country, country_code, municipality, sea_name,
                param, param_description,
                year, date, sample_type, sample_type_description,
                depth_from, depth_to, sediment_no,
                value, unit, basis, qflag, vflag, metcu,
                lod, loq, uncrt, metcu,
                labo, metst, metpt, metps, metcx, metoa)

# Disconnect
dbDisconnect(con)

write_tsv(df_ices_dome_sediment, "./data/pilot_ices_dome.tsv.gz")


project_table <- df_ices_dome_sediment%>%
  filter(param %in% c("CO", "CU", "MN", "MO", "SE", "ZN")) %>%
  mutate(param = factor(param, levels=c("CO", "CU", "MN", "MO", "SE", "ZN"),
                        labels = c("Co", "Cu", "Mn", "Mo", "Se", "Zn"))) %>%
  count(project, country, year, param) %>%
  arrange(param) %>%
  pivot_wider(names_from = param, values_from = n) %>%
  arrange(project, country, year) %>%
  dplyr::select(Project = project, Country = country, Year = year,
                Cobalt = Co, Copper  =Cu, Manganese = Mn, Molybdenum = Mo, Zinc = Zn, Selenium = Se)

write_tsv(project_table, "./data/ices_dome_projects.tsv.gz")

