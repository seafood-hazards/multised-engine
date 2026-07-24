library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/mareano_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Measurand classes + unit mass basis (mirror of step 8) ─────────────────
# Needed to convert a method limit into the same standardised unit as value_std
# (chemistry -> mg/kg, grain-size -> %), so value and limit are compared like for
# like.
targets     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
normalisers <- c("FE", "AL")
organic     <- c("CORG", "TOC", "TOC63")

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
    str_replace_all("µ|μ", "u")
}

# ── 2. Add below_loq_num column (idempotent) ─────────────────────────────────
# A numeric cross-check of the label-based `below_loq` (step 7), since a source's
# detection label can be wrong. 1 = value below the method's numeric
# detection/quantification limit; 0 = above it; NULL = the method carries no
# numeric limit (not assessable, e.g. 4Demon). At the limit exactly, the source
# detection flag decides: some sources substitute the value at the limit (Mareano
# reports value == LLD for below-detection results), so a value == limit is
# below-limit only when `below_loq` is set; a genuine reading equal to the limit
# (flag off) stays 0. The clean stage can union `below_loq = 1 OR below_loq_num = 1`.
if (!"below_loq_num" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN below_loq_num INTEGER;")
}

# ── 3. One numeric limit per method: LOQ, else LOD, else LLD ──────────────────
# Prefer the quantification limit (higher, more inclusive) where present. Sources
# expose different columns; a source with none (4Demon) yields no limit at all.
me <- dbReadTable(con, "method") |> as_tibble()
me_lim <- me |> select(method_id, any_of(c("loq", "lod", "lld")))
me_lim$limit <- NA_real_
for (col in c("loq", "lod", "lld")) {
  if (col %in% names(me_lim)) me_lim$limit <- coalesce(me_lim$limit, me_lim[[col]])
}

# ── 4. Flag values at or below the (standardised) limit ──────────────────────
m <- dbReadTable(con, "measurement") |> as_tibble()
if (!"value_std" %in% names(m)) {
  stop("value_std is missing -- run 08_add_converted_value.R first.")
}
if (!"below_loq" %in% names(m)) {
  stop("below_loq is missing -- run 07_mark_below_loq.R first.")
}

d <- m |>
  left_join(me_lim |> select(method_id, limit), by = "method_id") |>
  mutate(sym = str_to_upper(symbol),
         unit_canon = canon_unit(unit),
         is_chem = sym %in% c(targets, normalisers, organic)) |>
  left_join(mass_basis, by = "unit_canon") |>
  mutate(limit_std = limit / denom * if_else(is_chem, 1e6, 1e2),
         below_loq_num = case_when(
           is.na(limit_std) | is.na(value_std) | limit_std <= 0 ~ NA_integer_,
           value_std <  limit_std  ~ 1L,
           value_std == limit_std  ~ as.integer(below_loq == 1L),  # at the limit, defer to the flag
           TRUE                    ~ 0L))

# ── 5. Write back (idempotent) ───────────────────────────────────────────────
# Assessable rows (0/1) go to the temp table; rows with no usable limit are left
# NULL by the correlated update.
dbWriteTable(con, "qc_bloqn",
             d |> filter(!is.na(below_loq_num)) |> select(measurement_id, below_loq_num),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_bloqn ON qc_bloqn(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET below_loq_num = (SELECT below_loq_num FROM qc_bloqn q
                       WHERE q.measurement_id = measurement.measurement_id);")

# ── 6. Verify ─────────────────────────────────────────────────────────────────
cat("below_loq_num totals:\n")
print(dbGetQuery(con, "SELECT COALESCE(CAST(below_loq_num AS TEXT),'(no limit)') below_loq_num,
                              COUNT(*) n
                       FROM measurement GROUP BY below_loq_num ORDER BY n DESC"))
cat("label (below_loq) vs numeric (below_loq_num), where assessable:\n")
print(dbGetQuery(con, "SELECT below_loq, below_loq_num, COUNT(*) n
                       FROM measurement WHERE below_loq_num IS NOT NULL
                       GROUP BY below_loq, below_loq_num ORDER BY below_loq, below_loq_num"))

dbDisconnect(con)
