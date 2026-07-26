library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Grain-size derivation step (source-specific; Mareano here). Adds a per-sample
# fines fraction: the mass/volume percentage of material finer than 63 um, the
# clay + silt ("mud") fraction. Mareano samples are all bulk grabs, so this is
# the <63 um fraction of the whole sample. It is a reusable derived quantity
# (sieved-vs-bulk comparison, Fe/Al normalisation context, cross-source merge),
# stored on `subsample`, not a flag.
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add fines columns (idempotent) ────────────────────────────────────────
# fines_lt63  : percentage finer than 63 um (REAL, %). NULL where the subsample
#               has no grain-size data.
# fines_basis : how it was derived, for provenance and cross-source comparison
#               ('sum_bins' = summed sub-63 grain-size bins; other sources will
#               use 'gsmf63' = a direct cumulative <63 um value).
for (coldef in c("fines_lt63 REAL", "fines_basis TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "subsample")) {
    dbExecute(con, sprintf("ALTER TABLE subsample ADD COLUMN %s;", coldef))
  }
}

# ── 2. Derive: <63 um = Clay + Silt ──────────────────────────────────────────
# Mareano stores grain-size as four named bins (element.category = 'composition'):
#   Clay   < 2 um
#   Silt   2 - 63 um
#   Sand   63 - 2000 um
#   Gravel > 2000 um
# The <63 um ("mud") fraction is Clay + Silt. Both are volume-% and share the
# same basis, so they sum cleanly; the standardised value_std (grain-size -> %,
# from step 9) is summed so the derivation is unit-safe. Sand/Gravel are the
# coarse remainder and are not part of <63 um. A subsample with neither Clay nor
# Silt gets no fines value (stays NULL). Values are left as reported here; noisy
# grain-size correction is a later step.
sub63 <- c("Clay", "Silt")
m <- dbGetQuery(con, "
  SELECT s.subsample_id, m.symbol, m.value_std
  FROM subsample s
  JOIN measurement m ON m.subsample_id = s.subsample_id
  JOIN element e     ON e.symbol = m.symbol
  WHERE e.category = 'composition'") |> as_tibble()

fines <- m |>
  filter(symbol %in% sub63, !is.na(value_std)) |>
  group_by(subsample_id) |>
  summarise(fines_lt63  = sum(value_std),
            fines_basis = "sum_bins",
            .groups = "drop")

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_fines", fines, temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_fines ON qc_fines(subsample_id);")
dbExecute(con, "
  UPDATE subsample SET
    fines_lt63  = (SELECT fines_lt63  FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id),
    fines_basis = (SELECT fines_basis FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("subsamples with a fines_lt63 value:\n")
print(dbGetQuery(con, "SELECT COUNT(*) n_with_fines FROM subsample WHERE fines_lt63 IS NOT NULL"))
cat("\nfines_lt63 (%) distribution:\n")
print(dbGetQuery(con, "
  SELECT ROUND(MIN(fines_lt63),2) vmin, ROUND(MAX(fines_lt63),2) vmax,
         ROUND(AVG(fines_lt63),2) vavg,
         SUM(CASE WHEN fines_lt63 > 100 THEN 1 ELSE 0 END) over_100
  FROM subsample WHERE fines_lt63 IS NOT NULL"))

dbDisconnect(con)
