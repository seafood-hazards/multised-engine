library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add below_loq column (idempotent) ─────────────────────────────────────
# Common cross-source flag: 1 = value is below the detection/quantification
# limit (an uncertain "less-than" reading), 0 = a quantified value. These rows
# are candidates for removal in the clean stage.
if (!"below_loq" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN below_loq INTEGER;")
}

# ── 2. Map the source detection flag onto below_loq ──────────────────────────
# Mareano carries `below_lld` (0/1) = below the lower limit of detection. It has
# no separate quantification limit, so LOD is the only signal available here.
dbExecute(con, "
  UPDATE measurement
  SET below_loq = CASE WHEN below_lld = 1 THEN 1 ELSE 0 END;")

# ── 3. Verify ────────────────────────────────────────────────────────────────
cat("below_lld -> below_loq crosstab:\n")
print(dbGetQuery(con, "SELECT COALESCE(CAST(below_lld AS TEXT),'(NULL)') below_lld,
                              below_loq, COUNT(*) n
                       FROM measurement GROUP BY below_lld, below_loq ORDER BY n DESC"))
cat("below_loq totals:\n")
print(dbGetQuery(con, "SELECT below_loq, COUNT(*) n
                       FROM measurement GROUP BY below_loq ORDER BY n DESC"))

dbDisconnect(con)
