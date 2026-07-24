library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Plausible concentration range per element (mg/kg dry weight) ───────────
# Draft, deliberately generous bounds meant to catch clearly implausible values
# — impossibly high AND impossibly low — not to impose strict geochemical
# limits. Adjust with domain input. Covers the 7 targets, the Fe/Al normalisers,
# and organic carbon (as carbon mass). Grain-size composition carries no bound
# and is never flagged here (noisy; handled by a later dedicated step).
bounds <- tibble::tribble(
  ~sym,    ~min_mgkg, ~max_mgkg,
  "CO",       0.1,      3e2,
  "CU",       0.5,      1e4,
  "I",        0.1,      1e3,
  "MN",       1,        5e4,
  "MO",       0.05,     5e2,
  "SE",       0.01,     1e2,
  "ZN",       1,        2e4,
  "FE",       500,      2.5e5,
  "AL",       500,      2e5,
  "CORG",     100,      3e5,
  "TOC",      100,      3e5,
  "TOC63",    100,      3e5
)

# ── 2. Add range_flag column (idempotent) ────────────────────────────────────
# NULL = within range, no bound for the element, or a below-LOQ reading.
# 'below_min' / 'above_max' mark quantified values outside the plausible range —
# review / removal candidates for the clean stage.
if (!"range_flag" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN range_flag TEXT;")
}

# ── 3. Compare the standardised mg/kg value (step 8) against the bounds ───────
m <- dbReadTable(con, "measurement") |> as_tibble()
if (!"value_std" %in% names(m)) {
  stop("value_std is missing -- run 08_add_converted_value.R first.")
}
has_loq <- "below_loq" %in% names(m)   # common column from step 7

d <- m |>
  mutate(sym = str_to_upper(symbol),
         loq = if (has_loq) below_loq else 0L) |>
  left_join(bounds, by = "sym") |>
  mutate(range_flag = case_when(
    is.na(min_mgkg)       ~ NA_character_,   # element not bounded (e.g. grain size)
    loq == 1L             ~ NA_character_,   # below-LOQ reading is a limit, not a value
    is.na(value_std)      ~ NA_character_,   # unit was not convertible in step 8
    value_std < min_mgkg  ~ "below_min",
    value_std > max_mgkg  ~ "above_max",
    TRUE                  ~ NA_character_))

# ── 4. Write range_flag back (idempotent) ────────────────────────────────────
dbWriteTable(con, "qc_range",
             d |> filter(!is.na(range_flag)) |> select(measurement_id, range_flag),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_range ON qc_range(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET range_flag = (SELECT range_flag FROM qc_range q
                    WHERE q.measurement_id = measurement.measurement_id);")

# ── 5. Verify ─────────────────────────────────────────────────────────────────
cat("range_flag by element:\n")
print(dbGetQuery(con, "SELECT range_flag, UPPER(symbol) sym, COUNT(*) n
                       FROM measurement WHERE range_flag IS NOT NULL
                       GROUP BY range_flag, sym ORDER BY range_flag, n DESC"))
cat("range_flag totals:\n")
print(dbGetQuery(con, "SELECT COALESCE(range_flag,'(in range)') range_flag, COUNT(*) n
                       FROM measurement GROUP BY range_flag ORDER BY n DESC"))

dbDisconnect(con)
