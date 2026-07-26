library(DBI)
library(RSQLite)
library(tidyverse)

# ── Clean stage, Step 3: Annotate (Vannmiljø) ────────────────────────────────
# Vannmiljø variant of the grain-size split. Differences from the ICES template:
#   - grain-size codes are Vannmiljø's own: FINS (<63), GSMF<n> (<n),
#     GSMF_<n> (>n), GSMF<a>_<b> (a-b bin);
#   - there is no `matrix`; Vannmiljø is environmental sediment sampling with no
#     sieving metadata, so grain-size is taken as whole-sample (frac_class =
#     'bulk', an assumption -- see docs/clean-pipeline.md);
#   - fractions use the corrected value_std_corr, and gs_corr='invalid' rows
#     (reviewed unreliable) are excluded.
# Produces grain_size + grain_size_fraction, drops composition from measurement,
# moves fines off subsample. One-way; guarded.

clean_path     <- "./data/db/vannmiljo_clean.sqlite"
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

# ── 2. grain_size summary: all bulk (no matrix; assumed whole-sample) ────────
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
    "| unparsed bounds:", sum(is.na(fraction$lo_um) & is.na(fraction$hi_um)), "\n")
cat("composition left in measurement (should be 0):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category='composition'")$n, "\n")

dbDisconnect(con)
