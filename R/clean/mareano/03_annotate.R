library(DBI)
library(RSQLite)
library(tidyverse)

# ── Clean stage, Step 3: Annotate (Mareano) ──────────────────────────────────
# Mareano variant of the grain-size split. Differences from the ICES template:
#   - grain-size is four named bins (CLAY <2, SILT 2-63, SAND 63-2000, GRAVEL
#     >2000 um), not GSMF/GS codes;
#   - there is no `matrix`, and all Mareano samples are bulk grabs, so every
#     grain-size subsample is frac_class = 'bulk';
#   - there is no `value_std_corr` (grain-size is clean), so fractions use
#     value_std.
# Produces grain_size + grain_size_fraction, drops composition from measurement,
# moves fines off subsample. One-way; guarded.

clean_path     <- "./data/db/mareano_clean.sqlite"
chem_cats      <- c("target", "reference", "organic")
FINE_THRESHOLD <- 50   # % mud (<63 um) for is_fine; provisional

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

# ── 2. grain_size summary: all bulk (no matrix; Mareano samples are bulk) ────
grain_size <- comp |>
  distinct(subsample_id) |>
  mutate(frac_class = "bulk") |>
  left_join(subsample |> select(subsample_id, fines_lt63, fines_basis),
            by = "subsample_id") |>
  mutate(is_fine = if_else(is.na(fines_lt63), NA_integer_,
                           as.integer(fines_lt63 >= FINE_THRESHOLD))) |>
  select(subsample_id, frac_class, fines_lt63, is_fine, fines_basis)

fraction <- fraction |> semi_join(grain_size, by = "subsample_id")

# ── 3. Rebuild measurement (chemistry only) + finalise labels ────────────────
measurement <- m |>
  filter(category %in% chem_cats) |>
  select(any_of(c("measurement_id", "subsample_id", "symbol", "value", "unit",
                  "value_std", "unit_std", "value_sd", "n_rep", "value_uncrt",
                  "matrix", "method_id")))
subsample <- subsample |> select(-any_of(c("fines_lt63", "fines_basis")))

dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
dbWriteTable(con, "subsample",   subsample,   overwrite = TRUE)
dbWriteTable(con, "grain_size",          grain_size, overwrite = TRUE)
dbWriteTable(con, "grain_size_fraction", fraction,   overwrite = TRUE)
for (ix in c("CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)",
             "CREATE UNIQUE INDEX IF NOT EXISTS ix_gs_pk ON grain_size(subsample_id)",
             "CREATE INDEX IF NOT EXISTS ix_gsf_ss ON grain_size_fraction(subsample_id)"))
  invisible(dbExecute(con, ix))

# ── 4. Verify ────────────────────────────────────────────────────────────────
cat("measurement (chemistry only):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement")$n, "rows\n")
cat("grain_size rows:", nrow(grain_size),
    "| frac_class:", paste(names(table(grain_size$frac_class)),
                           table(grain_size$frac_class), sep = "=", collapse = ", "), "\n")
cat("is_fine:", paste(c("0", "1", "NA"),
      c(sum(grain_size$is_fine == 0, na.rm = TRUE),
        sum(grain_size$is_fine == 1, na.rm = TRUE),
        sum(is.na(grain_size$is_fine))), sep = "=", collapse = ", "), "\n")
cat("grain_size_fraction rows:", nrow(fraction),
    "| distinct subsamples:", n_distinct(fraction$subsample_id), "\n")
cat("composition left in measurement (should be 0):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category='composition'")$n, "\n")

dbDisconnect(con)
