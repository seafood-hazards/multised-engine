library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mudab_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Unit mass basis ("100 % of sample mass" expressed in each unit) ────────
# Same canonical-unit mapping as the quality-control step (step 4). A value's
# mass fraction = value / denom; it is then scaled to the target unit's full
# scale (1e6 for mg/kg, 1e2 for %).
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

# ── 2. Add value_std / unit_std columns (idempotent) ─────────────────────────
# A source-agnostic standardised value + its unit, reused by later steps
# (range check, numeric below-limit, Fe/Al normalisation) and cross-source work.
for (coldef in c("value_std REAL", "unit_std TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "measurement")) {
    dbExecute(con, sprintf("ALTER TABLE measurement ADD COLUMN %s;", coldef))
  }
}

# ── 3. Compute standardised value + unit ─────────────────────────────────────
# Standardisation is by measurand class (element.category from step 3): chemistry
# (target / reference / organic) -> mg/kg dry weight; grain-size composition -> %.
# Both go via the mass fraction value/denom. There is no length/µm grain-size in
# the data (all fractions), so composition is always %. vol.% is treated as %
# here; the mass-vs-volume distinction is left to the dedicated grain-size step.
# Units without a mass basis stay NULL (warned).
el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
m  <- dbReadTable(con, "measurement") |> as_tibble()

# Analysis value: prefer a source-provided QC-corrected value where present
# (4Demon's `corrected_value`: scale-error fixes, below-detection substitutions,
# unit normalisation -- the column 4Demon recommends for analysis). The raw
# `value` is kept untouched as provenance; other sources have no such column, so
# this is a no-op for them.
m$value_analysis <- if ("corrected_value" %in% names(m)) {
  coalesce(m$corrected_value, m$value)
} else {
  m$value
}

d <- m |>
  left_join(el, by = "symbol") |>
  mutate(unit_canon = canon_unit(unit),
         is_chem    = category %in% c("target", "reference", "organic")) |>
  left_join(mass_basis, by = "unit_canon") |>
  mutate(frac      = value_analysis / denom,
         value_std = if_else(is.na(denom), NA_real_,
                             if_else(is_chem, frac * 1e6, frac * 1e2)),
         unit_std  = if_else(is.na(denom), NA_character_,
                             if_else(is_chem, "mg/kg", "%")))

unconv <- d |> filter(is.na(denom), !is.na(unit)) |> distinct(unit)
if (nrow(unconv) > 0) {
  warning("No mass basis for unit(s): ", paste(unconv$unit, collapse = ", "),
          " -- value_std / unit_std left NULL for those rows.")
}

# ── 4. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_std",
             d |> select(measurement_id, value_std, unit_std),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_std ON qc_std(measurement_id);")
dbExecute(con, "
  UPDATE measurement SET
    value_std = (SELECT value_std FROM qc_std q WHERE q.measurement_id = measurement.measurement_id),
    unit_std  = (SELECT unit_std  FROM qc_std q WHERE q.measurement_id = measurement.measurement_id);")

# ── 5. Verify ─────────────────────────────────────────────────────────────────
cat("unit_std distribution:\n")
print(dbGetQuery(con, "SELECT COALESCE(unit_std,'(NULL)') unit_std, COUNT(*) n
                       FROM measurement GROUP BY unit_std ORDER BY n DESC"))

dbDisconnect(con)
