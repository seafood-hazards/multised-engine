library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Classify each element into a measurand category ───────────────────────
# One category per element symbol, the single source of truth for the later
# steps (supporting-data availability, unit conversion, range check, numeric
# below-limit), which read this column instead of redefining their own lists:
#   target      — the 7 trace-element targets (Co, Cu, I, Mn, Mo, Se, Zn)
#   reference   — the Fe/Al normalisers
#   organic     — organic carbon (CORG / TOC / TOC63)
#   composition — grain-size parameters (the remainder)
# Symbols are cased differently per source (Fe vs FE), so classify on the
# upper-cased symbol; the stored symbol keeps its original case.
targets    <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
references <- c("FE", "AL")
organic    <- c("CORG", "TOC", "TOC63")

el <- dbReadTable(con, "element") |> as_tibble() |>
  mutate(sym = str_to_upper(symbol),
         category = case_when(
           sym %in% targets    ~ "target",
           sym %in% references ~ "reference",
           sym %in% organic    ~ "organic",
           TRUE                ~ "composition"))

# ── 2. Add category column to element (idempotent) ───────────────────────────
if (!"category" %in% dbListFields(con, "element")) {
  dbExecute(con, "ALTER TABLE element ADD COLUMN category TEXT;")
}
dbWriteTable(con, "qc_cat", el |> select(symbol, category),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_cat ON qc_cat(symbol);")
dbExecute(con, "
  UPDATE element
  SET category = (SELECT category FROM qc_cat q WHERE q.symbol = element.symbol);")

# ── 3. Verify ─────────────────────────────────────────────────────────────────
cat("element categories:\n")
print(dbGetQuery(con, "SELECT category, COUNT(*) n FROM element
                       GROUP BY category ORDER BY n DESC"))

dbDisconnect(con)
