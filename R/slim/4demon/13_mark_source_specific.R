library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Source-specific step: 4Demon only. Folds 4Demon's several native quality flags
# into the common `src_flag` review marker. The detection-limit flag (`limit_flag`)
# is already in below_loq (step 8) and `basis` in weight_basis (step 12).
con <- dbConnect(RSQLite::SQLite(), "./data/db/4demon_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add src_flag column (idempotent) ──────────────────────────────────────
# Unlike Vannmiljø / ICES-DOME (a single native flag), 4Demon carries several
# independent quality flags that can co-occur on one row, so `src_flag` holds a
# comma-joined set of tokens (NULL = pass). Meanings from the pilot metadata
# (R/pilot/4demon/01_extract_meta_information.R):
#   suspect          — value_flag 1 : suspect value.
#   invalid          — value_flag 3 : invalid value.
#   range_check      — range_check_flag 1 : outside 4Demon's expected range.
#   outlier_moderate — outlier_extreme_flag 1 : moderate per-parameter outlier.
#   outlier_extreme  — outlier_extreme_flag 2 : extreme per-parameter outlier.
#   outlier_stdev    — outlier_stdev_flag 1 : outlier by a stdev threshold.
# value_flag 2 (below detection) is deliberately NOT folded: it duplicates
# `below_loq` (step 8, from the detection-limit flag). `corrected_value`,
# `fraction_range` and `matrix` are provenance/metadata, not quality flags.
if (!"src_flag" %in% dbListFields(con, "measurement")) {
  dbExecute(con, "ALTER TABLE measurement ADD COLUMN src_flag TEXT;")
}

# ── 2. Build one token per native flag, then join the present ones ───────────
m <- dbReadTable(con, "measurement") |> as_tibble()
d <- m |>
  mutate(
    t_val = case_when(vflag == 1 ~ "suspect",
                      vflag == 3 ~ "invalid",
                      TRUE       ~ NA_character_),
    t_rng = if_else(range_check_flag == 1, "range_check", NA_character_),
    t_out = case_when(outlier_extreme_flag == 2 ~ "outlier_extreme",
                      outlier_extreme_flag == 1 ~ "outlier_moderate",
                      TRUE                      ~ NA_character_),
    t_std = if_else(outlier_stdev_flag == 1, "outlier_stdev", NA_character_)
  ) |>
  unite("src_flag", t_val, t_rng, t_out, t_std, sep = ",", na.rm = TRUE) |>
  mutate(src_flag = na_if(src_flag, ""))

# ── 3. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_src",
             d |> filter(!is.na(src_flag)) |> select(measurement_id, src_flag),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_src ON qc_src(measurement_id);")
dbExecute(con, "
  UPDATE measurement
  SET src_flag = (SELECT src_flag FROM qc_src q
                  WHERE q.measurement_id = measurement.measurement_id);")

# ── 4. Verify ─────────────────────────────────────────────────────────────────
cat("src_flag (combined tokens):\n")
print(dbGetQuery(con, "SELECT COALESCE(src_flag,'(pass)') src_flag, COUNT(*) n
                       FROM measurement GROUP BY src_flag ORDER BY n DESC"))
cat("\nrows flagged (any token) vs total:\n")
print(dbGetQuery(con, "SELECT COUNT(*) total,
                              SUM(CASE WHEN src_flag IS NOT NULL THEN 1 ELSE 0 END) flagged
                       FROM measurement"))

dbDisconnect(con)
