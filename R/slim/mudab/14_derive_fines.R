library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Grain-size derivation step (source-specific; MUDAB here). Adds the per-sample
# fines fraction: the percentage of material finer than 63 um (clay + silt). Same
# columns and meaning as the Mareano step; the derivation differs because the
# source encodes grain-size differently.
con <- dbConnect(RSQLite::SQLite(), "./data/db/mudab_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add fines columns (idempotent) ────────────────────────────────────────
for (coldef in c("fines_lt63 REAL", "fines_basis TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "subsample")) {
    dbExecute(con, sprintf("ALTER TABLE subsample ADD COLUMN %s;", coldef))
  }
}

# ── 2. Derive: GSMF63 on a bulk matrix ───────────────────────────────────────
# MUDAB reports the cumulative code GSMF63 ("Grain Size Mass Fraction <63
# micron, silt/clay", ICES vocabulary): the <63 um
# fraction directly. But it is <63 um *of the matrix it was measured on*, so the
# matrix must be combined in:
#   SEDtot            -> <63 um of the whole sample (what we want)
#   SED2000 / SED1000 -> <63 um of the <2 mm / <1 mm material; these are
#                        bulk-equivalent (coarse sieving removes gravel), so used
#                        as the whole-sample fines when SEDtot is absent
#   finer matrices (SED63, SED20, ...) -> trivially ~100 %, excluded
# Priority SEDtot > SED2000 > SED1000; the standardised value_std (grain-size ->
# %, step 9) is used so g/kg and % are handled together. Implausible values
# (value_std outside 0-100) are excluded (left NULL); no correction is guessed.
bulk_prio <- c(SEDtot = 1L, SED2000 = 2L, SED1000 = 3L)

g <- dbGetQuery(con, "
  SELECT subsample_id, matrix, value_std
  FROM measurement WHERE symbol = 'GSMF63'") |>
  as_tibble() |>
  filter(!is.na(value_std), value_std >= 0, value_std <= 100,
         matrix %in% names(bulk_prio))

fines <- g |>
  mutate(prio = bulk_prio[matrix]) |>
  group_by(subsample_id, matrix, prio) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  group_by(subsample_id) |>
  slice_min(prio, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(subsample_id,
            fines_lt63  = v,
            fines_basis = paste0("gsmf63_", str_to_lower(matrix)))

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
