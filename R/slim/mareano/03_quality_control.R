library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. QC parameters ─────────────────────────────────────────────────────────
# Area QC: coarse bounding box around the European seas and oceans. Sites whose
# rounded lat/lon fall outside are flagged (can be refined later with the IHO
# `sea_name` whitelist that `site.sea_name` is derived from).
europe_lon <- c(-32, 45)   # W  … E
europe_lat <- c( 30, 84)   # S  … N (incl. Svalbard / Barents Sea)

# Value QC: negatives within this tolerance of zero are floating-point noise
# around a true 0 (e.g. Gravel wt.% at ~-1e-14) and are accepted as valid.
neg_tol <- 1e-6

# Value QC: physical upper bound per unit = "100 % of the sample mass" expressed
# in that unit. A fraction cannot exceed the whole, so anything above is
# impossible. Units not listed here get no upper-bound check (only the negative
# check applies). Legitimately high values (e.g. Mn, Fe, Al in mg/kg) are far
# below their ceiling and are accepted.
unit_max <- tibble::tribble(
  ~unit,      ~max_value,
  "%",             1e2,
  "vol.%",         1e2,
  "wt.%",          1e2,
  "g/kg",          1e3,
  "mg/g",          1e3,
  "mg/kg",         1e6,
  "ug/g",          1e6,
  "µg/g",     1e6,
  "ppm",           1e6,
  "ug/kg",         1e9,
  "ng/g",          1e9,
  "ppb",           1e9
)

# ── 2. Add qc_flag columns (idempotent) ──────────────────────────────────────
# NULL qc_flag = passed. A short code names the failed check.
for (tbl in c("site", "measurement")) {
  if (!"qc_flag" %in% dbListFields(con, tbl)) {
    dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN qc_flag TEXT;", tbl))
  }
}

# ── 3. Area QC: flag sites outside European seas ─────────────────────────────
dbExecute(con, sprintf(
  "UPDATE site SET qc_flag = CASE
     WHEN latitude  BETWEEN %g AND %g
      AND longitude BETWEEN %g AND %g THEN NULL
     ELSE 'outside_europe' END;",
  europe_lat[1], europe_lat[2], europe_lon[1], europe_lon[2]))

# ── 4. Value QC: flag negative and physically-impossible values ──────────────
dbWriteTable(con, "qc_unit_max", unit_max, temporary = TRUE, overwrite = TRUE)
dbExecute(con, sprintf("
  UPDATE measurement SET qc_flag = CASE
    WHEN value < %g THEN 'negative'
    WHEN value > (SELECT max_value FROM qc_unit_max u
                  WHERE u.unit = measurement.unit) THEN 'over_range'
    ELSE NULL END;", -neg_tol))

# ── 5. Verify ────────────────────────────────────────────────────────────────
cat("site qc_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(qc_flag,'(pass)') qc_flag, COUNT(*) n
                       FROM site GROUP BY qc_flag ORDER BY n DESC"))
cat("measurement qc_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(qc_flag,'(pass)') qc_flag, COUNT(*) n
                       FROM measurement GROUP BY qc_flag ORDER BY n DESC"))

dbDisconnect(con)
