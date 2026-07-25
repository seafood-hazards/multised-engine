library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Source-specific step: Vannmiljø only. Vannmiljø carries two native columns the
# common flags (steps 3-12) do not cover: `operator` (the relational sign) and
# `filtered`. Their below-detection meaning ('<' / 'ND') is already in below_loq
# (step 8); this step captures the leftovers.
con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add src_flag column (idempotent) ──────────────────────────────────────
# One TEXT flag (NULL = pass) folding Vannmiljø's source-native review markers,
# kept for review / removal in the clean stage:
#   above_range — operator '>' : a right-censored "greater-than" reading (the
#                 value is only a lower bound), distinct from the '<' / 'ND'
#                 below-detection case already folded into below_loq (step 8).
#   filtered    — filtered = 1 : a filtered sample (filtered water rather than
#                 bulk sediment), only a couple of rows.
# The two are disjoint in the data; the combined label is kept as a guard in case
# a future rebuild produces a row that is both.
if (!"src_flag" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN src_flag TEXT;")
}

# ── 2. Derive from operator / filtered ───────────────────────────────────────
m <- dbReadTable(con, "measurement") |> as_tibble()
d <- m |> mutate(src_flag = case_when(
  operator == ">" & filtered == 1L ~ "above_range,filtered",
  operator == ">"                  ~ "above_range",
  filtered == 1L                   ~ "filtered",
  TRUE                             ~ NA_character_))

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_src",
             d |> filter(!is.na(src_flag)) |> select(measurement_id, src_flag),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_src ON qc_src(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET src_flag = (SELECT src_flag FROM qc_src q
                  WHERE q.measurement_id = measurement.measurement_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("src_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(src_flag,'(none)') src_flag, COUNT(*) n
                       FROM measurement GROUP BY src_flag ORDER BY n DESC"))

dbDisconnect(con)
