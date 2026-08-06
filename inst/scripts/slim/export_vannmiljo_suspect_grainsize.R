# Export the Vannmiljø grain-size rows the correction step (step 14) flags
# `gs_corr = 'invalid'`, for the record and any further checking.
#
# Step 14 renormalises the internally-consistent-but-scaled grain-size curves of
# ICES-DOME / MUDAB, but Vannmiljø's noise is not a whole-curve scale error: it is a
# handful of isolated values with an implausible magnitude (a cumulative mass
# fraction, which cannot exceed 100 %, reported in the hundreds or tens of
# thousands). The error factor differs from row to row (some look x1000, some x10,
# some only just over 100), so no single rescaling is safe. These rows were
# exported by this script and manually reviewed against the raw data, found
# incorrect / unreliable, and so flagged `gs_corr = 'invalid'` (value_std_corr
# nulled) for removal in the clean stage rather than corrected.
#
# This script lists those rows with their location/date/depth context and a rough
# `likely_factor` hint (the power of ten that would bring the value back into
# 0-100), plus whether the same subsample carries a plausible FINS/GSMF_63 value.
# Writes ./data/qc_review/vannmiljo_suspect_grainsize.csv. Run from the project root.

library(DBI)
library(RSQLite)
library(tidyverse)

db       <- "./data/db/vannmiljo_slim.sqlite"
out_path <- "./data/qc_review/vannmiljo_suspect_grainsize.csv"

con <- dbConnect(RSQLite::SQLite(), db)
m  <- dbReadTable(con, "measurement") |> as_tibble()
ss <- dbReadTable(con, "subsample")   |> as_tibble()
ev <- dbReadTable(con, "event")       |> as_tibble()
st <- dbReadTable(con, "site")        |> as_tibble()
el <- dbReadTable(con, "element")     |> as_tibble()
ds <- dbReadTable(con, "dataset")     |> as_tibble()
dbDisconnect(con)

date_col <- intersect(c("date", "datetime", "year"), names(ev))[1]

# plausible <63 value already present in the same subsample (for the reviewer)
plausible <- m |>
  filter(symbol %in% c("FINS", "GSMF_63"), !is.na(value_std),
         value_std >= 0, value_std <= 100) |>
  group_by(subsample_id) |>
  summarise(other_ok_fines = paste0(symbol, "=", round(value_std, 1),
                                     collapse = "; "),
            .groups = "drop")

susp <- m |>
  filter(gs_corr == "invalid") |>
  mutate(
    likely_factor = case_when(value_std > 1000 ~ "/1000?",
                              value_std > 300  ~ "/10?",
                              TRUE             ~ "borderline (~100)"),
    rescaled_hint = case_when(value_std > 1000 ~ value_std / 1000,
                              value_std > 300  ~ value_std / 10,
                              TRUE             ~ value_std)) |>
  left_join(plausible, by = "subsample_id") |>
  left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
            by = "subsample_id") |>
  left_join(ev |> transmute(event_id, dataset_id, site_id,
                            date = as.character(.data[[date_col]])),
            by = "event_id") |>
  left_join(st |> select(site_id, latitude, longitude), by = "site_id") |>
  left_join(el |> select(symbol, element), by = "symbol") |>
  left_join(ds |> select(dataset_id, source, dataset_name), by = "dataset_id") |>
  arrange(desc(value_std)) |>
  select(measurement_id, source, dataset_name, site_id, latitude, longitude,
         date, depth_from, depth_to, subsample_id, symbol, element,
         value, unit, value_std, gs_corr,
         likely_factor, rescaled_hint, other_ok_fines)

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(susp, out_path)

cat("\n===== Vannmiljø invalid grain-size export =====\n")
cat("invalid rows:", nrow(susp),
    "| affected subsamples:", n_distinct(susp$subsample_id), "\n")
cat("written to:", out_path, "\n\n")
cat("by symbol and likely factor:\n")
print(susp |> count(symbol, likely_factor, name = "rows"))
