library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/subsample_meta.R")  # standardise_subsample()
source("R/clean/_shared/fraction_meta.R")   # apply_fraction() + attach_subsample_fraction()

# ── Clean stage, Step 3: Annotate (Vannmiljø) ────────────────────────────────
# Vannmiljø variant of the grain-size split. Differences from the ICES template:
#   - grain-size codes are Vannmiljø's own: FINS (<63), GSMF<n> (<n),
#     GSMF_<n> (>n), GSMF<a>_<b> (a-b bin);
#   - there is no `matrix`; Vannmiljø is environmental sediment sampling with no
#     sieving metadata, so grain-size is taken as whole-sample (frac_class =
#     'bulk', an assumption -- see docs/clean-pipeline.md);
#   - fractions use the corrected value_std_corr, and gs_corr='invalid' rows
#     (reviewed unreliable) are excluded;
#   - no `matrix`, so the chemistry is all bulk (measurement + subsample
#     frac_class = 'bulk').
# Moves the grain-size detail into grain_size_fraction and annotates the sediment
# fraction on measurement / subsample (fraction_meta.R). Drops composition from
# measurement. Guarded.

clean_path     <- "./data/db/vannmiljo_clean.sqlite"
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

# ── 1. grain_size_fraction: parse Vannmiljø codes to size bounds ─────────────
# FINS -> 0..63; GSMF_<n> -> n..inf; GSMF<a>_<b> -> a..b; GSMF<n> -> 0..n.
gt_n  <- function(s) as.numeric(str_match(s, "^GSMF_([0-9]+)$")[, 2])   # >n
bin_a <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)_([0-9]+)$")[, 2])
bin_b <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)_([0-9]+)$")[, 3])
lt_n  <- function(s) as.numeric(str_match(s, "^GSMF([0-9]+)$")[, 2])    # <n

value_gs <- if ("value_std_corr" %in% names(comp)) comp$value_std_corr else comp$value_std
gs_corr  <- if ("gs_corr" %in% names(comp)) comp$gs_corr else NA_character_

fraction <- comp |>
  mutate(value_pct = value_gs, gs_corr = gs_corr) |>
  filter(str_detect(symbol, "^FINS$|^GSMF"),
         is.na(gs_corr) | gs_corr != "invalid",
         !is.na(value_pct)) |>
  mutate(
    lo_um = case_when(symbol == "FINS"        ~ 0,
                      !is.na(gt_n(symbol))     ~ gt_n(symbol),
                      !is.na(bin_a(symbol))    ~ bin_a(symbol),
                      !is.na(lt_n(symbol))     ~ 0,
                      TRUE ~ NA_real_),
    hi_um = case_when(symbol == "FINS"        ~ 63,
                      !is.na(gt_n(symbol))     ~ NA_real_,
                      !is.na(bin_b(symbol))    ~ bin_b(symbol),
                      !is.na(lt_n(symbol))     ~ lt_n(symbol),
                      TRUE ~ NA_real_)) |>
  transmute(subsample_id, symbol, matrix = NA_character_, lo_um, hi_um, value_pct)

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
