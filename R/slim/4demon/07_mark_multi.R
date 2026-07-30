library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/4demon_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Count layers (subsamples) per event ───────────────────────────────────
# Each depth layer / core of a sampling event is one `subsample` row. An event
# with more than one is a multi-layer/-core sampling (a sliced core) as opposed
# to a single grab. Tool type alone does not determine this — the same gear code
# yields both single- and multi-layer events — so it is derived from the data.
lpe <- dbReadTable(con, "subsample") |> as_tibble() |>
  count(event_id, name = "n_layers")

# ── 2. Write n_layers + multi_flag to event (idempotent) ─────────────────────
for (col in c("n_layers", "multi_flag")) {
  if (!col %in% dbListFields(con, "event")) {
    dbExecute(con, sprintf("ALTER TABLE event ADD COLUMN %s INTEGER;", col))
  }
}
dbWriteTable(con, "qc_multi", lpe, temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_multi ON qc_multi(event_id);")
dbExecute(con, "
  UPDATE event SET
    n_layers   = COALESCE((SELECT n_layers FROM qc_multi q WHERE q.event_id = event.event_id), 0),
    multi_flag = (COALESCE((SELECT n_layers FROM qc_multi q WHERE q.event_id = event.event_id), 0) > 1);")

# ── 3. Verify ────────────────────────────────────────────────────────────────
cat("event multi_flag:\n")
print(dbGetQuery(con, "SELECT multi_flag, COUNT(*) n_events, SUM(n_layers) layers
                       FROM event GROUP BY multi_flag ORDER BY multi_flag;"))

dbDisconnect(con)
