library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Grain-size derivation step (source-specific; Vannmiljø here). Adds the per-sample
# fines fraction: the percentage of material finer than 63 um (clay + silt). Same
# columns and meaning as the Mareano step; the derivation differs because the
# source encodes grain-size differently. Vannmiljø has no `matrix` column, so its
# grain-size is taken as the whole-sample (bulk) fraction.
con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add fines columns (idempotent) ────────────────────────────────────────
for (coldef in c("fines_lt63 REAL", "fines_basis TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "subsample")) {
    dbExecute(con, sprintf("ALTER TABLE subsample ADD COLUMN %s;", coldef))
  }
}

# ── 2. Derive: FINS, else the >63 um complement ──────────────────────────────
# Vannmiljø reports two direct grain-size codes (verified from the pilot
# parameter table):
#   FINS     "Fines < 63 um"          -> the <63 um fraction directly
#   GSMF_63  "Particle fraction >63 um" -> the COMPLEMENT (sand+); note the naming
#            is the opposite of the ICES GSMF63 (<63). FINS + GSMF_63 ~ 100.
# So fines_lt63 = FINS where present; where only GSMF_63 exists, 100 - GSMF_63.
# The standardised value_std (grain-size -> %, step 9) is used so units are safe.
# Implausible values (value_std outside 0-100) are excluded (left NULL): a
# cumulative mass fraction cannot exceed 100 %, and no correction is guessed here.
g <- dbGetQuery(con, "
  SELECT subsample_id, symbol, value_std
  FROM measurement WHERE symbol IN ('FINS','GSMF_63')") |>
  as_tibble() |>
  filter(!is.na(value_std), value_std >= 0, value_std <= 100)

per <- g |>
  group_by(subsample_id, symbol) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  pivot_wider(names_from = symbol, values_from = v)
if (!"FINS"    %in% names(per)) per$FINS    <- NA_real_
if (!"GSMF_63" %in% names(per)) per$GSMF_63 <- NA_real_

fines <- per |>
  transmute(
    subsample_id,
    fines_lt63  = if_else(!is.na(FINS), FINS, 100 - GSMF_63),
    fines_basis = if_else(!is.na(FINS), "fins", "gsmf_63_complement")) |>
  filter(!is.na(fines_lt63))

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_fines", fines, temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_fines ON qc_fines(subsample_id);")
dbExecute(con, "
  UPDATE subsample SET
    fines_lt63  = (SELECT fines_lt63  FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id),
    fines_basis = (SELECT fines_basis FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("fines_basis distribution:\n")
print(dbGetQuery(con, "SELECT COALESCE(fines_basis,'(none)') fines_basis, COUNT(*) n
                       FROM subsample GROUP BY fines_basis ORDER BY n DESC"))
cat("\nfines_lt63 (%) range where present:\n")
print(dbGetQuery(con, "SELECT ROUND(MIN(fines_lt63),2) vmin, ROUND(MAX(fines_lt63),2) vmax,
                              ROUND(AVG(fines_lt63),2) vavg,
                              SUM(CASE WHEN fines_lt63 > 100 THEN 1 ELSE 0 END) over_100
                       FROM subsample WHERE fines_lt63 IS NOT NULL"))

dbDisconnect(con)
