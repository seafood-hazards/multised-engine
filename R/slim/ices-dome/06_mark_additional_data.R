library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Classify each measurement via the element category (step 3) ───────────
# org_exist / comp_exist read element.category directly (organic carbon and
# grain-size composition). fe_exist / al_exist still need the specific Fe vs Al
# symbol, which the shared 'reference' category does not distinguish. Symbols are
# cased differently per source (Fe vs FE), so match on the upper-cased symbol.
el <- dbReadTable(con, "element") |> as_tibble() |>
  transmute(sym = str_to_upper(symbol), category)
m <- dbReadTable(con, "measurement") |> as_tibble() |>
  transmute(subsample_id, sym = str_to_upper(symbol)) |>
  left_join(el, by = "sym")

# ── 2. Per-subsample existence of normalisers / organic C / composition ──────
ex <- m |> group_by(subsample_id) |>
  summarise(fe_exist   = as.integer(any(sym == "FE")),
            al_exist   = as.integer(any(sym == "AL")),
            org_exist  = as.integer(any(category == "organic")),
            comp_exist = as.integer(any(category == "composition")),
            .groups = "drop")

# ── 3. Write exist flags back to subsample (idempotent) ──────────────────────
for (col in c("fe_exist", "al_exist", "org_exist", "comp_exist")) {
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
    org_exist  = (SELECT org_exist  FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
    comp_exist = (SELECT comp_exist FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id);")

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("subsample existence flags (count with each present / total):\n")
print(dbGetQuery(con, "SELECT SUM(fe_exist) fe, SUM(al_exist) al,
                              SUM(org_exist) org, SUM(comp_exist) comp,
                              COUNT(*) total FROM subsample"))

dbDisconnect(con)
