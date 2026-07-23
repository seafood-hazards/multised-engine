# Export over-range measurements (failed the physical-ceiling QC) for review.
#
# Uses the measurement.qc_flag == 'over_range' mark from 03_quality_control.R:
# values that exceed "100 % of the sample mass" for their unit. Writes one
# per-source CSV to ./data/qc_review/<source>_over_range.csv, including the
# `ceiling` that was exceeded (recomputed with the same unit map as step 3) plus
# whichever source-specific flag/method columns are present. Sources with no
# over_range rows (mareano, 4demon) are skipped. Run from the project root.

library(DBI)
library(RSQLite)
library(tidyverse)

sources <- c(
  mareano   = "./data/db/mareano_slim.sqlite",
  vannmiljo = "./data/db/vannmiljo_slim.sqlite",
  "ices-dome" = "./data/db/ices_dome_slim.sqlite",
  mudab     = "./data/db/mudab_slim.sqlite",
  "4demon"  = "./data/db/4demon_slim.sqlite"
)

# Physical ceiling per unit = 100 % of sample mass in that unit (mirror of step 3).
base_max <- tibble::tribble(
  ~unit_canon, ~ceiling,
  "%", 1e2, "vol.%", 1e2, "wt.%", 1e2,
  "g/kg", 1e3, "mg/g", 1e3,
  "mg/kg", 1e6, "ug/g", 1e6, "ppm", 1e6,
  "ug/kg", 1e9, "ng/g", 1e9, "ppb", 1e9
)
canon_unit <- function(u) {
  u |> str_to_lower() |> str_trim() |>
    str_remove("\\s*(dw|ww|dry weight|wet weight)$") |> str_trim() |>
    str_replace_all("µ|μ", "u")   # micro sign / greek mu -> u
}

# source-specific columns to append when present (measurement flags then method)
extra_meas   <- c("below_lld", "operator", "filtered",
                  "basis", "matrix", "qflag", "vflag", "limit_flag")
extra_method <- c("lab", "method", "lod", "loq")

out_dir <- "./data/qc_review"
summary_rows <- list()

for (src in names(sources)) {
  con <- dbConnect(RSQLite::SQLite(), sources[[src]])
  m  <- dbReadTable(con, "measurement") |> as_tibble() |> filter(qc_flag == "over_range")
  if (nrow(m) == 0) { dbDisconnect(con); next }
  ss <- dbReadTable(con, "subsample") |> as_tibble()
  ev <- dbReadTable(con, "event")     |> as_tibble()
  st <- dbReadTable(con, "site")      |> as_tibble()
  el <- dbReadTable(con, "element")   |> as_tibble()
  ds <- dbReadTable(con, "dataset")   |> as_tibble()
  mt <- dbReadTable(con, "method")    |> as_tibble()
  dbDisconnect(con)

  date_col <- intersect(c("date", "datetime", "year"), names(ev))[1]
  ceil <- tibble(unit = unique(m$unit)) |>
    mutate(unit_canon = canon_unit(unit)) |>
    left_join(base_max, by = "unit_canon") |>
    select(unit, ceiling)

  meas_cols   <- intersect(extra_meas, names(m))
  method_cols <- intersect(extra_method, names(mt))

  out <- m |>
    select(measurement_id, subsample_id, symbol, value, unit, method_id,
           all_of(meas_cols)) |>
    left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
              by = "subsample_id") |>
    left_join(ev |> transmute(event_id, dataset_id, site_id,
                              date = as.character(.data[[date_col]])),
              by = "event_id") |>
    left_join(st |> select(site_id, latitude, longitude), by = "site_id") |>
    left_join(el |> select(symbol, element), by = "symbol") |>
    left_join(ds |> select(dataset_id, source, dataset_name), by = "dataset_id") |>
    left_join(mt |> select(method_id, all_of(method_cols)), by = "method_id") |>
    mutate(ceiling = ceil$ceiling[match(unit, ceil$unit)]) |>
    arrange(symbol, dataset_name, desc(value)) |>
    select(measurement_id, source, dataset_name, site_id, latitude, longitude,
           date, depth_from, depth_to, symbol, element, value, unit, ceiling,
           all_of(meas_cols), all_of(method_cols))

  path <- file.path(out_dir, paste0(gsub("-", "_", src), "_over_range.csv"))
  write_csv(out, path)
  summary_rows[[src]] <- tibble(
    source = src, rows = nrow(out), distinct_elements = n_distinct(out$symbol),
    file = basename(path))
}

cat("\n===== over_range export summary =====\n")
print(bind_rows(summary_rows), n = Inf)
