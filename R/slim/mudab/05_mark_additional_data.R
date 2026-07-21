library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Read slim db ──────────────────────────────────────────────────────
con_src <- dbConnect(RSQLite::SQLite(), "./data/db/mudab_slim.sqlite")

df_element     <- dbReadTable(con_src, "element")     |> as_tibble()
df_dataset     <- dbReadTable(con_src, "dataset")     |> as_tibble()
df_site        <- dbReadTable(con_src, "site")        |> as_tibble()
df_event       <- dbReadTable(con_src, "event")       |> as_tibble()
df_method      <- dbReadTable(con_src, "method")      |> as_tibble()
df_subsample   <- dbReadTable(con_src, "subsample")   |> as_tibble()
df_measurement <- dbReadTable(con_src, "measurement") |> as_tibble()

dbDisconnect(con_src)
