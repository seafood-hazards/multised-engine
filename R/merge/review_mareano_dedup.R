library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge dedup REVIEW: Vannmiljo's re-hosted Mareano dataset ─────────────────
# Vannmiljo carries a dataset literally named "Kartlegging av miljogifter i
# sedimenter - MAREANO" (dataset_id 18): re-hosted Mareano data. Mareano is the
# preferred native source, so its Vannmiljo copies are duplicates and should be
# dropped -- BUT only where native Mareano actually has the sample. Our native
# Mareano source spans ~2003-2021, while the re-hosted copy runs 1999-2024, so a
# blanket delete would lose the samples native Mareano never had.
#
# This is a REVIEW prototype (not a pipeline step): it classifies every
# measurement in the Vannmiljo-MAREANO dataset against native Mareano and writes
# a CSV to eyeball before the rule is locked into 02_dedup.R.
#
# Match key: rounded location (lat/lon 3 dp) + year + element + track
# (frac_class + sieve). Re-hosting shifts the exact date and nudges the value, so
# the date is NOT in the key (year is) and the value tolerance is a loose 5%
# (vs the global 1%), justified here because provenance is known.
#
#   decision = drop_duplicate    native match, value within 5%  -> drop van copy
#            = review_value_mismatch  native key match, value >5% apart -> keep, check
#            = keep_unique        no native match                -> keep (only copy)
#
# Output -> data/analysis/merge/merge_dedup_mareano.csv (gitignored).

TOL_DROP <- 0.05

out_dir <- "data/analysis/merge"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Vannmiljo-MAREANO measurements (loc/year/element/track + value) ───────
vcon <- dbConnect(SQLite(), "data/db/vannmiljo_clean.sqlite")
van <- dbGetQuery(vcon, "
  SELECT m.measurement_id AS van_measurement_id,
         round(si.latitude,3)  AS lat3,
         round(si.longitude,3) AS lon3,
         e.year, s.depth_from, s.depth_to,
         m.symbol, m.frac_class, m.sieve_um, m.value_std
  FROM dataset d
    JOIN event e      ON e.dataset_id   = d.dataset_id
    JOIN site si      ON si.site_id     = e.site_id
    JOIN subsample s  ON s.event_id     = e.event_id
    JOIN measurement m ON m.subsample_id = s.subsample_id
  WHERE d.dataset_name LIKE '%MAREANO%' AND m.value_std > 0
") |> as_tibble() |>
  mutate(sieve_key = coalesce(sieve_um, -1))
dbDisconnect(vcon)

# ── 2. Native Mareano measurements on the same key ───────────────────────────
mcon <- dbConnect(SQLite(), "data/db/mareano_clean.sqlite")
mar <- dbGetQuery(mcon, "
  SELECT round(si.latitude,3)  AS lat3,
         round(si.longitude,3) AS lon3,
         e.year, m.symbol, m.frac_class, m.sieve_um,
         m.value_std AS mar_value
  FROM measurement m
    JOIN subsample s ON s.subsample_id = m.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site si     ON si.site_id     = e.site_id
  WHERE m.value_std > 0
") |> as_tibble() |>
  mutate(sieve_key = coalesce(sieve_um, -1))
dbDisconnect(mcon)

# ── 3. Match each Vannmiljo row to native Mareano, keep the nearest value ─────
key <- c("lat3", "lon3", "year", "symbol", "frac_class", "sieve_key")

matched <- van |>
  left_join(mar |> select(all_of(key), mar_value), by = key,
            relationship = "many-to-many") |>
  mutate(rel_diff = abs(mar_value - value_std) / value_std) |>
  group_by(van_measurement_id) |>
  summarise(
    n_native_key = sum(!is.na(mar_value)),
    nearest_mar  = if (all(is.na(mar_value))) NA_real_ else mar_value[which.min(rel_diff)],
    min_rel_diff = if (all(is.na(mar_value))) NA_real_ else min(rel_diff, na.rm = TRUE),
    .groups = "drop")

review <- van |>
  left_join(matched, by = "van_measurement_id") |>
  mutate(decision = case_when(
    n_native_key == 0                       ~ "keep_unique",
    min_rel_diff <= TOL_DROP                 ~ "drop_duplicate",
    TRUE                                     ~ "review_value_mismatch")) |>
  transmute(van_measurement_id, lat3, lon3, year, depth_from, depth_to,
            symbol, frac_class,
            van_value_std = round(value_std, 4),
            n_native_key,
            nearest_mar   = round(nearest_mar, 4),
            rel_diff      = round(min_rel_diff, 4),
            decision) |>
  arrange(decision, symbol, year, lat3, lon3)

write_csv(review, file.path(out_dir, "merge_dedup_mareano.csv"))

# ── 4. Console summary ───────────────────────────────────────────────────────
cat("Vannmiljo-MAREANO dedup review ->", file.path(out_dir, "merge_dedup_mareano.csv"), "\n\n")
cat("measurements:", nrow(review), "\n\n")
cat("by decision:\n")
review |> count(decision) |>
  mutate(pct = round(100 * n / sum(n), 1)) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\ndrop_duplicate by element:\n")
review |> filter(decision == "drop_duplicate") |> count(symbol, sort = TRUE) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\nkeep_unique year span (data native Mareano lacks):\n")
review |> filter(decision == "keep_unique") |>
  summarise(n = n(), yr_min = min(year, na.rm = TRUE), yr_max = max(year, na.rm = TRUE)) |>
  as.data.frame() |> print(row.names = FALSE)
