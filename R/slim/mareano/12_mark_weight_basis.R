library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add weight_basis column (idempotent) ──────────────────────────────────
# Harmonised sample weight basis of each chemistry measurement: 'dry' or 'wet'
# weight. Grain-size composition is left NULL: the dry/wet-weight distinction is
# a concentration concept and does not apply to a grain-size fraction (its
# vol.%/wt.% basis is handled by the dedicated grain-size step). Dry weight is the
# sediment standard; wet-weight rows are review / conversion candidates for the
# clean stage. The body differs per source because the basis signal differs
# (a `basis` column, a unit suffix, or none).
if (!"weight_basis" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN weight_basis TEXT;")
}

# ── 2. Derive: Mareano reports every value on a dry-weight basis ─────────────
# Mareano carries no per-row basis field or unit suffix; all of its data are dry
# weight (confirmed), so every chemistry measurement is 'dry'.
el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
m  <- dbReadTable(con, "measurement") |> as_tibble() |> left_join(el, by = "symbol")
d  <- m |> mutate(is_chem = category %in% c("target", "reference", "organic"),
                  weight_basis = if_else(is_chem, "dry", NA_character_))

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_wb",
             d |> filter(!is.na(weight_basis)) |> select(measurement_id, weight_basis),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_wb ON qc_wb(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET weight_basis = (SELECT weight_basis FROM qc_wb q
                      WHERE q.measurement_id = measurement.measurement_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("weight_basis:\n")
print(dbGetQuery(con, "SELECT COALESCE(weight_basis,'(none)') weight_basis, COUNT(*) n
                       FROM measurement GROUP BY weight_basis ORDER BY n DESC"))

dbDisconnect(con)
