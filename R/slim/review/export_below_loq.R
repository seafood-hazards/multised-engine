# Export below-LOQ measurements for manual review.
#
# Reads the below_loq flag written by each source's 08_mark_below_loq.R and
# dumps every below-limit measurement (below_loq == 1) to a per-source CSV in
# ./data/qc_review/, with key context columns plus `source_flag` (the native
# detection flag value that caused the mark). Run from the project root.

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

# per-source name of the native detection flag, surfaced in the export for context
flag_col <- c(mareano = "below_lld", vannmiljo = "operator",
              "ices-dome" = "qflag", mudab = "qflag", "4demon" = "limit_flag")

out_dir <- "./data/qc_review"
summary_rows <- list()

for (src in names(sources)) {
  con <- dbConnect(RSQLite::SQLite(), sources[[src]])

  m  <- dbReadTable(con, "measurement") |> as_tibble()
  ss <- dbReadTable(con, "subsample")   |> as_tibble()
  ev <- dbReadTable(con, "event")       |> as_tibble()
  st <- dbReadTable(con, "site")        |> as_tibble()
  el <- dbReadTable(con, "element")     |> as_tibble()
  ds <- dbReadTable(con, "dataset")     |> as_tibble()
  mt <- dbReadTable(con, "method")      |> as_tibble()
  dbDisconnect(con)

  date_col <- intersect(c("date", "datetime", "year"), names(ev))[1]
  if (!"lab" %in% names(mt)) mt$lab <- NA_character_
  fc <- flag_col[[src]]

  out <- m |>
    filter(below_loq == 1) |>
    mutate(source_flag = as.character(.data[[fc]])) |>
    left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
              by = "subsample_id") |>
    left_join(ev |> transmute(event_id, dataset_id, site_id,
                              date = as.character(.data[[date_col]])),
              by = "event_id") |>
    left_join(st |> select(site_id, latitude, longitude), by = "site_id") |>
    left_join(el |> select(symbol, element), by = "symbol") |>
    left_join(ds |> select(dataset_id, dataset_name), by = "dataset_id") |>
    left_join(mt |> select(method_id, method, lab), by = "method_id") |>
    arrange(symbol, dataset_name, date) |>
    transmute(measurement_id, dataset_name, site_id, latitude, longitude, date,
              depth_from, depth_to, symbol, element, value, unit,
              source_flag, method, lab, method_id)

  path <- file.path(out_dir, paste0(gsub("-", "_", src), "_below_loq.csv"))
  write_csv(out, path)

  summary_rows[[src]] <- tibble(
    source = src, flag_col = fc, rows = nrow(out),
    distinct_elements = n_distinct(out$symbol), file = basename(path))
}

cat("\n===== below_loq export summary =====\n")
print(bind_rows(summary_rows), n = Inf)

cat("\n===== below_loq rows by element (per source) =====\n")
for (src in names(sources)) {
  path <- file.path(out_dir, paste0(gsub("-", "_", src), "_below_loq.csv"))
  tb <- read_csv(path, show_col_types = FALSE)
  if (nrow(tb) == 0) { cat("\n--", src, "-- (none)\n"); next }
  cat("\n--", src, "--\n")
  print(tb |> count(symbol, sort = TRUE), n = Inf)
}
