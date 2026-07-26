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

# ── 2. Derive: FINS, else >63 um complement, else clay + silt sum ────────────
# Vannmiljø reports several grain-size codes (verified from the pilot parameter
# table). fines_lt63 is taken from the first available, in this order:
#   1. FINS      "Fines < 63 um"            -> the <63 um fraction directly.
#   2. GSMF_63   "Particle fraction >63 um" -> the COMPLEMENT (sand+); note the
#                naming is the OPPOSITE of the ICES GSMF63 (<63), so 100 - GSMF_63.
#                FINS + GSMF_63 ~ 100 (verified).
#   3. GSMF2 + GSMF2_63  "<2 um" (clay) + "2-63 um" (silt) -> the same clay+silt
#                sum used for Mareano, an exact <63 um for samples that carry the
#                fraction bins but neither of the direct codes above.
# All via the standardised value_std (grain-size -> %, step 9) so units are safe.
# Implausible values (a cumulative mass fraction outside 0-100 %) are excluded
# (left NULL); no correction is guessed here.
comps <- c("FINS", "GSMF_63", "GSMF2", "GSMF2_63")
g <- dbGetQuery(con, sprintf("
  SELECT subsample_id, symbol, value_std FROM measurement
  WHERE symbol IN (%s)", paste0("'", comps, "'", collapse = ","))) |>
  as_tibble() |>
  filter(!is.na(value_std), value_std >= 0, value_std <= 100)

per <- g |>
  group_by(subsample_id, symbol) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  pivot_wider(names_from = symbol, values_from = v)
for (c in comps) if (!c %in% names(per)) per[[c]] <- NA_real_

fines <- per |>
  mutate(clay_silt = GSMF2 + GSMF2_63) |>   # NA unless both bins present
  transmute(
    subsample_id,
    fines_lt63  = case_when(!is.na(FINS)      ~ FINS,
                            !is.na(GSMF_63)   ~ 100 - GSMF_63,
                            !is.na(clay_silt) ~ clay_silt),
    fines_basis = case_when(!is.na(FINS)      ~ "fins",
                            !is.na(GSMF_63)   ~ "gsmf_63_complement",
                            !is.na(clay_silt) ~ "clay_silt_sum")) |>
  filter(!is.na(fines_lt63), fines_lt63 >= 0, fines_lt63 <= 100)

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
