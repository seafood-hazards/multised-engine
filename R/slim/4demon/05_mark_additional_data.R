library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/4demon_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Classify each measurement's element ───────────────────────────────────
# The element table holds only the 7 targets, the FE/AL normalisers, and the
# grain-size composition parameters, so anything that is not a target and not
# FE/AL is composition. Symbols are cased differently per source (Fe vs FE).
targets <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
m <- dbReadTable(con, "measurement") |> as_tibble() |>
  transmute(subsample_id, sym = str_to_upper(symbol),
            cat = case_when(sym == "FE"       ~ "fe",
                            sym == "AL"       ~ "al",
                            sym %in% targets  ~ "target",
                            TRUE              ~ "comp"))

# ── 2. Per-subsample existence of normalisers / composition ──────────────────
ex <- m |> group_by(subsample_id) |>
  summarise(fe_exist   = as.integer(any(cat == "fe")),
            al_exist   = as.integer(any(cat == "al")),
            comp_exist = as.integer(any(cat == "comp")),
            .groups = "drop")

# ── 3. Write exist flags back to subsample (idempotent) ──────────────────────
for (col in c("fe_exist", "al_exist", "comp_exist")) {
  if (!col %in% dbListFields(con, "subsample")) {
    dbExecute(con, sprintf("ALTER TABLE subsample ADD COLUMN %s INTEGER;", col))
  }
}
dbWriteTable(con, "qc_exist", ex, temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_exist ON qc_exist(subsample_id);")
dbExecute(con, "
  UPDATE subsample SET
    fe_exist   = (SELECT fe_exist   FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
    al_exist   = (SELECT al_exist   FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
    comp_exist = (SELECT comp_exist FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id);")

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("subsample existence flags (count with each present / total):\n")
print(dbGetQuery(con, "SELECT SUM(fe_exist) fe, SUM(al_exist) al,
                              SUM(comp_exist) comp, COUNT(*) total FROM subsample"))

dbDisconnect(con)
