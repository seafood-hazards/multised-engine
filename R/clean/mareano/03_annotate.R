library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/subsample_meta.R")  # standardise_subsample()
source("R/clean/_shared/fraction_meta.R")   # apply_fraction() + attach_subsample_fraction()

# ── Clean stage, Step 3: Annotate (Mareano) ──────────────────────────────────
# Mareano variant of the grain-size split. Differences from the ICES template:
#   - grain-size is four named bins (CLAY <2, SILT 2-63, SAND 63-2000, GRAVEL
#     >2000 um), not GSMF/GS codes;
#   - there is no `matrix`, and all Mareano samples are bulk grabs, so the
#     chemistry is all bulk (measurement + subsample frac_class = 'bulk');
#   - there is no `value_std_corr` (grain-size is clean), so fractions use
#     value_std.
# Moves the grain-size detail into grain_size_fraction and annotates the sediment
# fraction on measurement / subsample (fraction_meta.R). Drops composition from
# measurement. Guarded.

clean_path     <- "./data/db/mareano_clean.sqlite"
chem_cats      <- c("target", "reference", "organic")

con <- dbConnect(RSQLite::SQLite(), clean_path)
element   <- dbReadTable(con, "element")     |> as_tibble()
subsample <- dbReadTable(con, "subsample")   |> as_tibble()
m         <- dbReadTable(con, "measurement") |> as_tibble()

m <- m |> left_join(element |> select(symbol, category), by = "symbol")
comp <- m |> filter(category == "composition")
if (nrow(comp) == 0) {
  dbDisconnect(con)
  stop("no composition rows -- measurement looks already annotated. ",
       "Re-run 01_harmonise.R -> 02_clean.R -> 03_annotate.R on a fresh clean DB.")
}

# ── 1. grain_size_fraction: the four named bins, with size bounds ────────────
bin_bounds <- tibble::tribble(
  ~symbol,   ~lo_um, ~hi_um,
  "CLAY",     0,      2,
  "SILT",     2,      63,
  "SAND",     63,     2000,
  "GRAVEL",   2000,   NA)
fraction <- comp |>
  filter(symbol %in% bin_bounds$symbol, !is.na(value_std)) |>
  left_join(bin_bounds, by = "symbol") |>
  transmute(subsample_id, symbol, matrix = NA_character_,
            lo_um, hi_um, value_pct = value_std)

# ── 2. Rebuild measurement + fraction annotation ─────────────────────────────────
# Chemistry (target/reference/organic) was collapsed in 02. Convert the raw ICES
# `matrix` into user-facing frac_class + sieve_um (fraction_meta.R), keeping matrix
# as provenance. All chemistry stays in one measurement table.
chem <- m
if (!"category" %in% names(chem))
  chem <- chem |> left_join(element |> select(symbol, category), by = "symbol")
measurement <- chem |> filter(category %in% chem_cats) |> apply_fraction() |>
  select(all_of(MEASUREMENT_COLS))

# subsample: fraction summary of the TARGET measurements (bulk / sieved / mixed) +
# target_sieve_um; fines_lt63 / fines_basis mud content is already present (slim step 15).
subsample <- attach_subsample_fraction(subsample, measurement, element) |>
  standardise_subsample()

# ── 3. Write back ─────────────────────────────────
dbWriteTable(con, "measurement",         measurement, overwrite = TRUE)
dbWriteTable(con, "subsample",           subsample,   overwrite = TRUE)
dbWriteTable(con, "grain_size_fraction", fraction,    overwrite = TRUE)
invisible(dbExecute(con, "DROP TABLE IF EXISTS grain_size"))      # folded onto subsample
invisible(dbExecute(con, "DROP TABLE IF EXISTS organic_carbon"))  # merged back into measurement
for (ix in c("CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)",
             "CREATE INDEX        IF NOT EXISTS ix_gsf_ss  ON grain_size_fraction(subsample_id)"))
  invisible(dbExecute(con, ix))

# ── 4. Verify ─────────────────────────────────
cat("measurement (all chemistry):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement")$n, "rows\n")
cat("measurement frac_class:\n")
print(dbGetQuery(con, "SELECT COALESCE(frac_class,'(NULL)') frac_class, COUNT(*) n FROM measurement GROUP BY frac_class ORDER BY n DESC"))
cat("subsample target_frac_class:\n")
print(dbGetQuery(con, "SELECT COALESCE(target_frac_class,'(NULL)') target_frac_class, COUNT(*) n FROM subsample GROUP BY target_frac_class ORDER BY n DESC"))
cat("grain_size_fraction rows:", nrow(fraction),
    "| distinct subsamples:", n_distinct(fraction$subsample_id), "\n")
cat("composition left in measurement (should be 0):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category='composition'")$n, "\n")

dbDisconnect(con)
