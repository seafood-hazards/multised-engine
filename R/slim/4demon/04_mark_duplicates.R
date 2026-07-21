library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/4demon_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Assemble measurement context ──────────────────────────────────────────
# A measurement's "sampling occasion" = location (site) + date + depth interval.
# Duplicate detection groups measurements of the same element (+ unit) taken on
# the same occasion. Depth is part of the key: only Mareano has multi-depth
# cores, where it correctly separates distinct subsamples; for the other sources
# depth is uniform enough that it does not change the grouping.
m  <- dbReadTable(con, "measurement") |> as_tibble()
ss <- dbReadTable(con, "subsample")   |> as_tibble()
ev <- dbReadTable(con, "event")       |> as_tibble()

date_col <- intersect(c("date", "datetime", "year"), names(ev))[1]

d <- m |>
  select(measurement_id, subsample_id, symbol, value, unit) |>
  left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
            by = "subsample_id") |>
  left_join(ev |> transmute(event_id, site_id, date_key = .data[[date_col]]),
            by = "event_id")

# ── 2. Flag duplicates / technical replicates ────────────────────────────────
# Within a group (same location + date + depth + element + unit):
#   value repeated in the group        -> 'duplicate'
#   value unique within a multi-row group -> 'technical_replicate'
# Singletons stay unflagged (NULL). These are suspicious markers for manual
# review, not a definitive de-duplication.
d <- d |>
  group_by(site_id, date_key, depth_from, depth_to, symbol, unit) |>
  mutate(grp_n = n()) |>
  group_by(site_id, date_key, depth_from, depth_to, symbol, unit, value) |>
  mutate(val_rep = n()) |>
  ungroup() |>
  mutate(dup_flag = case_when(
    grp_n == 1   ~ NA_character_,
    val_rep >= 2 ~ "duplicate",
    TRUE         ~ "technical_replicate"))

# ── 3. Write dup_flag back (idempotent) ──────────────────────────────────────
if (!"dup_flag" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN dup_flag TEXT;")
}
dbWriteTable(con, "qc_dup",
             d |> filter(!is.na(dup_flag)) |> select(measurement_id, dup_flag),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_dup ON qc_dup(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET dup_flag = (SELECT dup_flag FROM qc_dup q
                  WHERE q.measurement_id = measurement.measurement_id);")

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("measurement dup_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(dup_flag,'(none)') dup_flag, COUNT(*) n
                       FROM measurement GROUP BY dup_flag ORDER BY n DESC"))

dbDisconnect(con)
