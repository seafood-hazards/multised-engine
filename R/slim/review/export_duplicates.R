# Export duplicate / technical-replicate measurements for manual review.
#
# Uses the dup_flag written by each source's 04_mark_duplicates.R. Re-derives the
# duplicate grouping key (site + date + depth + element + unit) so each flagged
# row can be shown together with its whole sibling group. Writes two per-source
# CSVs to ./data/qc_review/ :
#   <source>_duplicates.csv            -- groups containing a 'duplicate'
#   <source>_technical_replicates.csv  -- groups containing a 'technical_replicate'
# Both include every row of the qualifying groups (for side-by-side context) with
# a dup_flag column. Run from the project root.

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

  # same key as 04_mark_duplicates.R (incl. method identity), so dup_group
  # matches the flag grouping. `lab` is guaranteed present (NA where the source
  # records none), so grouping on it is a no-op for those sources.
  d <- m |>
    select(measurement_id, subsample_id, symbol, value, unit, method_id, dup_flag) |>
    left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
              by = "subsample_id") |>
    left_join(ev |> transmute(event_id, dataset_id, site_id,
                              date = as.character(.data[[date_col]])),
              by = "event_id") |>
    left_join(mt |> select(method_id, method, lab), by = "method_id") |>
    group_by(site_id, date, depth_from, depth_to, symbol, unit, method, lab) |>
    mutate(dup_group = cur_group_id()) |>
    ungroup()

  decorate <- function(df) {
    df |>
      left_join(st |> select(site_id, latitude, longitude), by = "site_id") |>
      left_join(el |> select(symbol, element), by = "symbol") |>
      left_join(ds |> select(dataset_id, dataset_name), by = "dataset_id") |>
      mutate(dup_group = dense_rank(dup_group)) |>
      arrange(dup_group, symbol, value) |>
      transmute(dup_group, dup_flag, measurement_id, dataset_name,
                site_id, latitude, longitude, date, depth_from, depth_to,
                symbol, element, value, unit, method, lab, method_id)
  }

  # one output per flag category: keep every row of any group that contains at
  # least one row with that flag (so differing values are visible side by side).
  for (flag in c("duplicate", "technical_replicate")) {
    grp <- d |> filter(dup_flag == flag) |> distinct(dup_group) |> pull(dup_group)
    out <- d |> filter(dup_group %in% grp) |> decorate()
    fname <- if (flag == "duplicate") "duplicates" else "technical_replicates"
    path <- file.path(out_dir, paste0(gsub("-", "_", src), "_", fname, ".csv"))
    write_csv(out, path)
    summary_rows[[paste(src, flag)]] <- tibble(
      source = src, flag = flag,
      flagged_rows = sum(out$dup_flag == flag, na.rm = TRUE),
      groups = n_distinct(out$dup_group),
      rows_incl_context = nrow(out), file = basename(path))
  }
}

cat("\n===== duplicate / technical-replicate export summary =====\n")
print(bind_rows(summary_rows), n = Inf)
