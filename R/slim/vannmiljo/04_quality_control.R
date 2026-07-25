library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_slim.sqlite")
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

# Physical upper bound per unit = "100 % of the sample mass" expressed in that
# unit. A fraction cannot exceed the whole, so anything above is impossible.
# Keyed on a canonical unit; the actual unit strings in the data are mapped onto
# these below (stripping dry/wet-weight suffixes and normalising the micro sign).
base_max <- tibble::tribble(
  ~unit_canon, ~max_value,
  "%",        1e2,
  "vol.%",    1e2,
  "wt.%",     1e2,
  "g/kg",     1e3,
  "g/kg c",   1e3,   # organic-carbon basis, e.g. vannmiljo TOC "g/kg C dw"
  "mg/g",     1e3,
  "mg/kg",    1e6,
  "ug/g",     1e6,
  "ppm",      1e6,
  "ug/kg",    1e9,
  "ng/g",     1e9,
  "ppb",      1e9
)

canon_unit <- function(u) {
  u |>
    str_to_lower() |>
    str_trim() |>
    str_remove("\\s*(dw|ww|dry weight|wet weight)$") |>
    str_trim() |>
    str_replace_all("µ|μ", "u")   # micro sign / greek mu -> u
}

# ── 2. Add flag columns (idempotent) ─────────────────────────────────────────
# NULL = passed; a short code names the failed check. Each check gets its own
# column: site.area_flag (out-of-scope location) and measurement.invalid_flag
# (physically invalid value).
flag_cols <- c(site = "area_flag", measurement = "invalid_flag")
for (tbl in names(flag_cols)) {
  if (!flag_cols[[tbl]] %in% dbListFields(con, tbl)) {
    dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s TEXT;", tbl, flag_cols[[tbl]]))
  }
}

# ── 3. Area QC: flag sites outside European seas ─────────────────────────────
dbExecute(con, sprintf(
  "UPDATE site SET area_flag = CASE
     WHEN latitude  BETWEEN %g AND %g
      AND longitude BETWEEN %g AND %g THEN NULL
     ELSE 'outside_europe' END;",
  europe_lat[1], europe_lat[2], europe_lon[1], europe_lon[2]))

# ── 4. Value QC: flag negative and physically-impossible values ──────────────
# Map the unit strings actually present onto their physical ceiling.
qc_unit_max <- dbGetQuery(con, "SELECT DISTINCT unit FROM measurement") |>
  as_tibble() |>
  mutate(unit_canon = canon_unit(unit)) |>
  left_join(base_max, by = "unit_canon")

unmapped <- qc_unit_max |> filter(is.na(max_value) & !is.na(unit))
if (nrow(unmapped) > 0) {
  warning("No value ceiling for unit(s): ",
          paste(unmapped$unit, collapse = ", "),
          " -- only the negative check applies to them.")
}

dbWriteTable(con, "qc_unit_max",
             qc_unit_max |> filter(!is.na(max_value)) |> select(unit, max_value),
             temporary = TRUE, overwrite = TRUE)

dbExecute(con, sprintf("
  UPDATE measurement SET invalid_flag = CASE
    WHEN value < %g THEN 'negative'
    WHEN value > (SELECT max_value FROM qc_unit_max u
                  WHERE u.unit = measurement.unit) THEN 'over_range'
    ELSE NULL END;", -neg_tol))

# ── 5. Verify ────────────────────────────────────────────────────────────────
cat("site area_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(area_flag,'(pass)') area_flag, COUNT(*) n
                       FROM site GROUP BY area_flag ORDER BY n DESC"))
cat("measurement invalid_flag:\n")
print(dbGetQuery(con, "SELECT COALESCE(invalid_flag,'(pass)') invalid_flag, COUNT(*) n
                       FROM measurement GROUP BY invalid_flag ORDER BY n DESC"))

dbDisconnect(con)
