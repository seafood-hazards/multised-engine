library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge stage 5: summary outputs for the website ───────────────────────────
# Compares the final multised_merged.sqlite against the five clean DBs, so the merge pages
# can show what each source contributed and how much survived deduplication.
#
# Outputs -> data/analysis/merge/ (gitignored):
#   merge_retention.csv   per source x table: clean_n, merged_n, retained %
#   merge_stage_totals.csv per table: clean total (union) vs final (post-dedup)
#   (merge_dedup.csv is written by 02_dedup.R)

SOURCES <- tribble(
  ~Source,      ~stem,
  "Mareano",    "mareano",
  "4Demon",     "4demon",
  "MUDAB",      "mudab",
  "Vannmiljø",  "vannmiljo",
  "ICES-DOME",  "ices_dome")

# tables that carry a `source` column in the merged DB (element is shared)
TABLES <- c("dataset", "site", "event", "subsample", "measurement",
            "method", "grain_size_fraction")

out_dir <- "data/analysis/merge"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Clean counts per source x table ───────────────────────────────────────
clean_counts <- pmap_dfr(SOURCES, function(Source, stem) {
  con <- dbConnect(SQLite(), sprintf("data/db/%s_clean.sqlite", stem))
  on.exit(dbDisconnect(con))
  have <- dbListTables(con)
  map_dfr(TABLES, function(t) tibble(Source = Source, table = t,
    clean_n = if (t %in% have) dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM %s", t))$n else 0L))
})

# ── 2. Merged counts per source x table ──────────────────────────────────────
con <- dbConnect(SQLite(), "data/db/multised_merged.sqlite")
merged_counts <- map_dfr(TABLES, function(t)
  dbGetQuery(con, sprintf("SELECT source AS Source, COUNT(*) merged_n FROM %s GROUP BY source", t)) |>
    mutate(table = t))
dbDisconnect(con)

# ── 3. Retention ─────────────────────────────────────────────────────────────
retention <- clean_counts |>
  left_join(merged_counts, by = c("Source", "table")) |>
  mutate(merged_n = replace_na(merged_n, 0L),
         retained_pct = if_else(clean_n > 0, round(100 * merged_n / clean_n, 1), NA_real_))

stage_totals <- retention |>
  group_by(table) |>
  summarise(clean_total = sum(clean_n), final_total = sum(merged_n),
            removed = clean_total - final_total,
            retained_pct = round(100 * final_total / clean_total, 1), .groups = "drop")

write_csv(retention,    file.path(out_dir, "merge_retention.csv"))
write_csv(stage_totals, file.path(out_dir, "merge_stage_totals.csv"))

# ── 4. Console summary ───────────────────────────────────────────────────────
cat("merge summary written to", out_dir, "\n\nmeasurement retention by source:\n")
retention |> filter(table == "measurement") |>
  select(Source, clean_n, merged_n, retained_pct) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\nstage totals:\n"); as.data.frame(stage_totals) |> print(row.names = FALSE)
