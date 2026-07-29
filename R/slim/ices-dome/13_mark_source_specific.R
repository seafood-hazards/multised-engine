library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Source-specific step: ICES-DOME only. Folds ICES's native VFLAG (value flag)
# into the common `src_flag` review marker. The QFLAG (detection/quantification)
# is already in below_loq (step 8) and BASIS in weight_basis (step 12).
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add src_flag column (idempotent) ──────────────────────────────────────
# One TEXT flag (NULL = pass) folding ICES's VFLAG, the originator's value-quality
# flag (meanings from the pilot `code_lookup` table):
#   suspect    — VFLAG 'S': "Suspect value - considered suspect by originator on
#                the basis of quality control or recorder/instrument/platform
#                performance".
#   calculated — VFLAG 'C': "Calculated value" (a derived value rather than a
#                direct measurement).
# VFLAG 'A' ("Acceptable value") and NULL pass. The other native columns are left
# unfolded on purpose: `dcflag` holds ICES DATSU screening/conversion codes (mostly
# benign unit conversions), and `metcu`/`uncrt`/`matrix` are uncertainty and
# sample-fraction metadata, not clean quality flags.
if (!"src_flag" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN src_flag TEXT;")
}

# ── 2. Derive from vflag ──────────────────────────────────────────────────────
m <- dbReadTable(con, "measurement") |> as_tibble()
d <- m |> mutate(src_flag = case_when(
  vflag == "S" ~ "suspect",
  vflag == "C" ~ "calculated",
  TRUE         ~ NA_character_))

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
