library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/subsample_meta.R")  # standardise_subsample()
source("R/clean/_shared/fraction_meta.R")   # apply_fraction() + attach_subsample_fraction()

# ── Clean stage, Step 3: Annotate (4Demon) ───────────────────────────────────
# Operates on 4demon_clean.sqlite (after 01_harmonise, 02_clean). 4Demon has only
# chemistry (7 targets + Fe/Al; no organic carbon, no grain-size), so this step is
# just the sediment-fraction annotation shared with the other sources:
#   - measurement: the raw `matrix` (FS/US -> SED63/SEDtot in 01) gains the
#     user-facing frac_class + sieve_um (fraction_meta.R); matrix is kept as
#     provenance, and the 4Demon-only `fraction_range` is dropped (now redundant).
#   - subsample: a fraction summary of the TARGET measurements, target_frac_class
#     ('bulk' / 'sieved' / 'mixed') + target_sieve_um.
# No organic_carbon or grain_size_fraction table (4Demon has neither). One-way;
# guarded against a second run.

clean_path <- "./data/db/4demon_clean.sqlite"

con <- dbConnect(RSQLite::SQLite(), clean_path)
element   <- dbReadTable(con, "element")     |> as_tibble()
subsample <- dbReadTable(con, "subsample")   |> as_tibble()
m         <- dbReadTable(con, "measurement") |> as_tibble()

if (!"fraction_range" %in% names(m)) {
  dbDisconnect(con)
  stop("measurement carries no fraction_range -- it looks already annotated. ",
       "Re-run 01_harmonise.R -> 02_clean.R -> 03_annotate.R on a fresh clean DB.")
}

# ── 1. measurement: matrix -> frac_class + sieve_um (matrix kept) ─────────────
measurement <- apply_fraction(m) |> select(all_of(MEASUREMENT_COLS))

# ── 2. subsample: fraction summary of the TARGET measurements ────────────────
subsample <- attach_subsample_fraction(subsample, measurement, element) |>
  standardise_subsample()

# ── 3. Write back ────────────────────────────────────────────────────────────
dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
dbWriteTable(con, "subsample",   subsample,   overwrite = TRUE)
invisible(dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)"))
invisible(dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_meas_ss ON measurement(subsample_id)"))

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("measurement (chemistry):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement")$n, "rows\n")
cat("measurement frac_class:\n")
print(dbGetQuery(con, "SELECT COALESCE(frac_class,'(NULL)') frac_class, COUNT(*) n FROM measurement GROUP BY frac_class ORDER BY n DESC"))
cat("subsample target_frac_class:\n")
print(dbGetQuery(con, "SELECT COALESCE(target_frac_class,'(NULL)') target_frac_class, COUNT(*) n FROM subsample GROUP BY target_frac_class ORDER BY n DESC"))

dbDisconnect(con)
