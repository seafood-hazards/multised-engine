library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/subsample_meta.R")  # standardise_subsample()
source("R/clean/_shared/fraction_meta.R")   # apply_fraction() + attach_subsample_fraction()

# ── Clean stage, Step 3: Annotate (ICES-DOME) ────────────────────────────────
# Operates on ices_dome_clean.sqlite (after 01_harmonise, 02_clean). Splits the
# grain-size composition out of `measurement`, annotates the sediment fraction, and
# separates organic carbon:
#
#   measurement          the 7 target elements + Fe/Al normalisers only. The raw
#                        `matrix` becomes user-facing frac_class ('bulk'/'sieved')
#                        + sieve_um (fraction_meta.R); `matrix` is then dropped.
#   organic_carbon       CORG / TOC* moved out of measurement (supplementary, not a
#                        main analyte; same column set as measurement).
#   subsample            a per-target fraction summary frac_class ('bulk' /
#                        'sieved' / 'mixed') + sieve_um; plus fines_lt63 /
#                        fines_basis (% <63 um mud content, from slim step 15).
#                        NULL frac_class where a subsample has no target chemistry.
#   grain_size_fraction  one row per grain-size mass-fraction measurement (the
#                        one-to-many detail, kept separate): corrected %
#                        (value_std_corr) with parsed size bounds; gs_corr='invalid'
#                        rows and grain-size *statistics* (GSMEA/GSMED/...) excluded.
#
# Labels kept elsewhere: element.category, subsample supporting-data flags,
# event.n_layers. One-way; guarded.

clean_path    <- "./data/db/ices_dome_clean.sqlite"
chem_cats     <- c("target", "reference", "organic")

con <- dbConnect(RSQLite::SQLite(), clean_path)
element   <- dbReadTable(con, "element")     |> as_tibble()
subsample <- dbReadTable(con, "subsample")   |> as_tibble()
m         <- dbReadTable(con, "measurement") |> as_tibble()

if (!"value_std_corr" %in% names(m)) {
  dbDisconnect(con)
  stop("measurement has no value_std_corr -- it looks already annotated. ",
       "Re-run 01_harmonise.R -> 02_clean.R -> 03_annotate.R on a fresh clean DB.")
}

comp <- m |>
  left_join(element |> select(symbol, category), by = "symbol") |>
  filter(category == "composition")

# ── 1. grain_size_fraction: moved, corrected fraction distribution ───────────
# Keep mass-fraction codes only (GSMF<n>, GSMF>n, GS>a<b); drop grain-size
# statistics (GSMEA/GSMED/GSSORT/...). Value is the corrected % (value_std_corr);
# drop invalid rows. Parse size bounds (um): GSMF<n> = 0..n, GSMF>n = n..inf,
# GS>a<b = a..b.
lo_um <- function(s) case_when(
  str_detect(s, "^GSMF[0-9]+$")     ~ 0,
  !is.na(str_match(s, "^GSMF>([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GSMF>([0-9]+)$")[, 2]),
  !is.na(str_match(s, "^GS>([0-9]+)<[0-9]+$")[, 2]) ~ as.numeric(str_match(s, "^GS>([0-9]+)<[0-9]+$")[, 2]),
  TRUE ~ NA_real_)
hi_um <- function(s) case_when(
  !is.na(str_match(s, "^GSMF([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GSMF([0-9]+)$")[, 2]),
  str_detect(s, "^GSMF>[0-9]+$")    ~ NA_real_,
  !is.na(str_match(s, "^GS>[0-9]+<([0-9]+)$")[, 2]) ~ as.numeric(str_match(s, "^GS>[0-9]+<([0-9]+)$")[, 2]),
  TRUE ~ NA_real_)

fraction <- comp |>
  filter(str_detect(symbol, "^GSMF|^GS>"),
         is.na(gs_corr) | gs_corr != "invalid",
         !is.na(value_std_corr)) |>
  transmute(subsample_id, symbol, matrix,
            lo_um = lo_um(symbol), hi_um = hi_um(symbol),
            value_pct = value_std_corr)

# ── 2. Filter grain-size curves to a classifiable (bulk/sieved) matrix ──────────────────
# frac_class from the subsample's grain-size matrices: bulk if any whole/coarse
# matrix (SEDtot, or a cutoff >= 1000 um), sieved if only fine matrices, unknown
# otherwise (dropped, per the agreed handling).
mcut <- function(mx) suppressWarnings(as.numeric(sub("^SED", "", mx)))  # SEDtot -> NA
class_ss <- comp |>
  mutate(cut = mcut(matrix),
         is_bulk   = matrix == "SEDtot" | (!is.na(cut) & cut >= 1000),
         is_sieved = !is.na(cut) & cut < 1000) |>
  group_by(subsample_id) |>
  summarise(frac_class = case_when(any(is_bulk, na.rm = TRUE)   ~ "bulk",
                                    any(is_sieved, na.rm = TRUE) ~ "sieved",
                                    TRUE                         ~ "unknown"),
            .groups = "drop") |>
  filter(frac_class != "unknown")

# keep only fractions of subsamples with a classifiable grain-size curve
fraction <- fraction |> semi_join(class_ss, by = "subsample_id")

# ── 3. Rebuild measurement + split organic carbon ────────────────────────────
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

# ── 4. Write back ────────────────────────────────────────────────────────────
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

# ── 5. Verify ────────────────────────────────────────────────────────────────
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
