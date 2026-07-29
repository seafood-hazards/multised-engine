library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Grain-size correction step (source-specific; Vannmiljø). Unlike ICES-DOME /
# MUDAB, Vannmiljø's grain-size noise is not a whole-curve scale error but a
# handful of isolated values with an implausible magnitude (a cumulative fraction
# reported in the thousands of %). There is also no matrix column and the GSMF_63
# / GSMF_2000 codes mean ">n µm" rather than "<n", so the per-curve renormalisation
# used for ICES / MUDAB does not apply. These rows were exported
# (R/slim/review/export_vannmiljo_suspect_grainsize.R) and manually reviewed
# against the raw data: the error magnitude varies per row (x1000, x10, borderline)
# and the values were found incorrect / unreliable, so they are flagged INVALID for
# removal in the clean stage rather than rescaled. value_std_corr passes value_std
# through except for the invalid rows, which get NULL (no usable standardised
# value); the fines step (15) then reads one consistent column across sources.
con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add columns (idempotent) ──────────────────────────────────────────────
# value_std_corr : = value_std, except NULL for the invalid rows below.
# gs_corr        : 'invalid' where a grain-size fraction value is implausible
#                  (value_std > 100 %, impossible for a cumulative mass fraction),
#                  reviewed and confirmed unreliable; a removal marker for the clean
#                  stage. Else NULL.
for (coldef in c("value_std_corr REAL", "gs_corr TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "measurement")) {
    dbExecute(con, sprintf("ALTER TABLE measurement ADD COLUMN %s;", coldef))
  }
}

# ── 2. Pass value_std through; flag implausible grain-size fractions invalid ──
el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
m  <- dbReadTable(con, "measurement") |> as_tibble() |> left_join(el, by = "symbol")

d <- m |>
  mutate(
    invalid_gs     = category == "composition" & !is.na(value_std) & value_std > 100.5,
    gs_corr        = if_else(invalid_gs, "invalid", NA_character_),
    value_std_corr = if_else(invalid_gs, NA_real_, value_std))

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_gscorr",
             d |> select(measurement_id, value_std_corr, gs_corr),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_gscorr ON qc_gscorr(measurement_id);")
dbExecute(con, "
  UPDATE measurement SET
    value_std_corr = (SELECT value_std_corr FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id),
    gs_corr        = (SELECT gs_corr        FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("gs_corr distribution (composition rows):\n")
print(dbGetQuery(con, "SELECT COALESCE(gs_corr,'(none)') gs_corr, COUNT(*) n
                       FROM measurement m JOIN element e ON m.symbol=e.symbol
                       WHERE e.category='composition' GROUP BY gs_corr ORDER BY n DESC"))

dbDisconnect(con)
