library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge dedup REVIEW: year-based cross-source overlap by dataset name ───────
# Explore whether a YEAR-based match (vs exact date) would find cross-source
# duplicates the current exact-date rule misses, and whether those overlaps
# concentrate in a few (dataset_name x dataset_name) pairs -- which would flag two
# datasets as the same re-hosted data (the ICES<->MUDAB analogue of the
# Vannmiljo-MAREANO case). REVIEW only; reads the current merged DB.

TOL <- 0.01   # relative value tolerance for "same reading"

con <- dbConnect(SQLite(), "data/db/multised_merged.sqlite")
d <- dbGetQuery(con, "
  SELECT round(si.latitude,3)  AS lat3,
         round(si.longitude,3) AS lon3,
         e.year,
         s.depth_from, s.depth_to,
         m.symbol, m.frac_class, COALESCE(m.sieve_um_std,-1) AS sieve_key,
         m.value_std, m.source,
         ds.dataset_name
  FROM measurement m
    JOIN subsample s ON s.subsample_id = m.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site si     ON si.site_id     = e.site_id
    JOIN dataset ds  ON ds.dataset_id  = e.dataset_id
  WHERE m.value_std > 0 AND e.year IS NOT NULL
") |> as_tibble()
dbDisconnect(con)

# sample key: same place / year / depth / element / track
d <- d |>
  mutate(skey = paste(lat3, lon3, year, depth_from, depth_to,
                      symbol, frac_class, sieve_key, sep = "|"))

# ── 1. Keep clusters that span >1 source with values agreeing within TOL ─────
clusters <- d |>
  group_by(skey) |>
  filter(n_distinct(source) > 1,
         (max(value_std) - min(value_std)) / min(value_std) <= TOL) |>
  ungroup()

cat("year-based cross-source duplicate clusters (within",
    scales::percent(TOL), "value):\n")
cat("  clusters:", n_distinct(clusters$skey),
    " rows involved:", nrow(clusters), "\n\n")

# ── 2. By source pair ────────────────────────────────────────────────────────
pair_of <- function(x) paste(sort(unique(x)), collapse = " + ")

by_srcpair <- clusters |>
  group_by(skey) |>
  summarise(src_pair = pair_of(source), .groups = "drop") |>
  count(src_pair, sort = TRUE, name = "clusters")

cat("by source pair:\n")
by_srcpair |> as.data.frame() |> print(row.names = FALSE)

# ── 3. By dataset-name pair (the concentration test) ─────────────────────────
# For each cluster, the sorted set of "SOURCE: dataset_name" strings across its
# rows. If a few of these dominate, those dataset pairs are the same data.
by_dspair <- clusters |>
  mutate(tag = paste0(substr(source, 1, 3), ": ", dataset_name)) |>
  group_by(skey) |>
  summarise(ds_pair = pair_of(tag), src_pair = pair_of(source), .groups = "drop") |>
  count(src_pair, ds_pair, sort = TRUE, name = "clusters")

cat("\ntop dataset-name pairs (cross-source clusters):\n")
by_dspair |> filter(str_detect(src_pair, " \\+ ")) |> head(15) |>
  as.data.frame() |> print(row.names = FALSE)

dir.create("data/analysis/merge", recursive = TRUE, showWarnings = FALSE)
write_csv(by_dspair, "data/analysis/merge/merge_year_overlap_datasets.csv")
cat("\nfull breakdown -> data/analysis/merge/merge_year_overlap_datasets.csv\n")
