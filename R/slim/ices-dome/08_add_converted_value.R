library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Measurand classes ─────────────────────────────────────────────────────
# Chemistry (targets + Fe/Al normalisers + organic carbon) is standardised to
# mg/kg dry weight; everything else is grain-size composition, standardised to %.
targets     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
normalisers <- c("FE", "AL")
organic     <- c("CORG", "TOC", "TOC63")

# ── 2. Unit mass basis ("100 % of sample mass" expressed in each unit) ────────
# Same canonical-unit mapping as step 3. A value's mass fraction = value / denom;
# it is then scaled to the target unit's full scale (1e6 for mg/kg, 1e2 for %).
mass_basis <- tibble::tribble(
  ~unit_canon, ~denom,
  "%", 1e2, "vol.%", 1e2, "wt.%", 1e2,
  "g/kg", 1e3, "g/kg c", 1e3, "mg/g", 1e3,
  "mg/kg", 1e6, "ug/g", 1e6, "ppm", 1e6,
  "ug/kg", 1e9, "ng/g", 1e9, "ppb", 1e9
)
canon_unit <- function(u) {
  u |> str_to_lower() |> str_trim() |>
    str_remove("\\s*(dw|ww|dry weight|wet weight)$") |> str_trim() |>
    str_replace_all("µ|μ", "u")   # micro sign / greek mu -> u
}

# ── 3. Add value_std / unit_std columns (idempotent) ─────────────────────────
# A source-agnostic standardised value + its unit, reused by later steps
# (range check, Fe/Al normalisation) and cross-source analysis.
for (coldef in c("value_std REAL", "unit_std TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "measurement")) {
    dbExecute(con, sprintf("ALTER TABLE measurement ADD COLUMN %s;", coldef))
  }
}

# ── 4. Compute standardised value + unit ─────────────────────────────────────
# Chemistry -> mg/kg, grain-size -> %. Both go via the mass fraction value/denom.
# There is no length/µm grain-size in the data (all fractions), so grain-size is
# always %. vol.% is treated as % here; the mass-vs-volume distinction is left to
# the dedicated grain-size step. Units without a mass basis stay NULL (warned).
m <- dbReadTable(con, "measurement") |> as_tibble()

d <- m |>
  mutate(sym = str_to_upper(symbol),
         unit_canon = canon_unit(unit),
         is_chem = sym %in% c(targets, normalisers, organic)) |>
  left_join(mass_basis, by = "unit_canon") |>
  mutate(frac      = value / denom,
         value_std = if_else(is.na(denom), NA_real_,
                             if_else(is_chem, frac * 1e6, frac * 1e2)),
         unit_std  = if_else(is.na(denom), NA_character_,
                             if_else(is_chem, "mg/kg", "%")))

unconv <- d |> filter(is.na(denom), !is.na(unit)) |> distinct(unit)
if (nrow(unconv) > 0) {
  warning("No mass basis for unit(s): ", paste(unconv$unit, collapse = ", "),
          " -- value_std / unit_std left NULL for those rows.")
}

# ── 5. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_std",
             d |> select(measurement_id, value_std, unit_std),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_std ON qc_std(measurement_id);")
dbExecute(con, "
  UPDATE measurement SET
    value_std = (SELECT value_std FROM qc_std q WHERE q.measurement_id = measurement.measurement_id),
    unit_std  = (SELECT unit_std  FROM qc_std q WHERE q.measurement_id = measurement.measurement_id);")

# ── 6. Verify ─────────────────────────────────────────────────────────────────
cat("unit_std distribution:\n")
print(dbGetQuery(con, "SELECT COALESCE(unit_std,'(NULL)') unit_std, COUNT(*) n
                       FROM measurement GROUP BY unit_std ORDER BY n DESC"))
cat("sample conversions (per original unit):\n")
print(dbGetQuery(con, "SELECT UPPER(symbol) sym, unit, value, value_std, unit_std
                       FROM measurement GROUP BY unit, unit_std HAVING COUNT(*) > 0 LIMIT 12"))

dbDisconnect(con)
