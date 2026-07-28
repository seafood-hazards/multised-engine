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
# Moves the grain-size detail into grain_size_fraction, splits organic carbon into
# organic_carbon, and annotates the sediment fraction on measurement / subsample
# (fraction_meta.R). Drops composition from measurement. Guarded.

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

# ── 2. Rebuild measurement + split organic carbon ────────────────────────────
# Chemistry (target/reference/organic) was collapsed in 02. Convert the raw ICES
# `matrix` into user-facing frac_class + sieve_um (fraction_meta.R), then split:
# the 7 target elements + Fe/Al normalisers stay in `measurement`; organic carbon
# (CORG / TOC*) moves to its own `organic_carbon` table (supplementary, not a main
# analyte, and often measured on a different fraction than the metals).
chem <- m
if (!"category" %in% names(chem))
  chem <- chem |> left_join(element |> select(symbol, category), by = "symbol")
chem <- chem |> filter(category %in% chem_cats) |> apply_fraction()
measurement    <- chem |> filter(category %in% c("target", "reference")) |> select(all_of(MEASUREMENT_COLS))
organic_carbon <- chem |> filter(category == "organic")                  |> select(all_of(MEASUREMENT_COLS))

# subsample: per-target fraction summary (bulk / sieved / mixed) + sieve_um; the
# fines_lt63 / fines_basis mud content is already present from slim step 15.
subsample <- attach_subsample_fraction(subsample, measurement, element) |>
  standardise_subsample()

# ── 3. Write back ────────────────────────────────────────────────────────────
dbWriteTable(con, "measurement",         measurement,    overwrite = TRUE)
dbWriteTable(con, "organic_carbon",      organic_carbon, overwrite = TRUE)
dbWriteTable(con, "subsample",           subsample,      overwrite = TRUE)
dbWriteTable(con, "grain_size_fraction", fraction,       overwrite = TRUE)
invisible(dbExecute(con, "DROP TABLE IF EXISTS grain_size"))  # summary folded onto subsample
for (ix in c("CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)",
             "CREATE UNIQUE INDEX IF NOT EXISTS ix_org_pk  ON organic_carbon(measurement_id)",
             "CREATE INDEX        IF NOT EXISTS ix_org_ss  ON organic_carbon(subsample_id)",
             "CREATE INDEX        IF NOT EXISTS ix_gsf_ss  ON grain_size_fraction(subsample_id)"))
  invisible(dbExecute(con, ix))

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("measurement (target + reference):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement")$n, "rows\n")
cat("organic_carbon:",
    dbGetQuery(con, "SELECT COUNT(*) n FROM organic_carbon")$n, "rows\n")
cat("measurement frac_class:\n")
print(dbGetQuery(con, "SELECT COALESCE(frac_class,'(NULL)') frac_class, COUNT(*) n FROM measurement GROUP BY frac_class ORDER BY n DESC"))
cat("subsample frac_class (target summary):\n")
print(dbGetQuery(con, "SELECT COALESCE(frac_class,'(NULL)') frac_class, COUNT(*) n FROM subsample GROUP BY frac_class ORDER BY n DESC"))
cat("grain_size_fraction rows:", nrow(fraction),
    "| distinct subsamples:", n_distinct(fraction$subsample_id), "\n")
cat("non-(target/reference) left in measurement (should be 0):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category NOT IN ('target','reference')")$n, "\n")

dbDisconnect(con)
