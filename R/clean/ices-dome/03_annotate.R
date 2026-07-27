library(DBI)
library(RSQLite)
library(tidyverse)

# ── Clean stage, Step 3: Annotate (ICES-DOME) ────────────────────────────────
# Operates on ices_dome_clean.sqlite (after 01_harmonise, 02_clean). Splits
# grain-size out of `measurement` into two new tables and finalises the labels:
#
#   grain_size          one row per subsample with usable grain-size:
#                         frac_class  'bulk' / 'sieved' (unknown is dropped)
#                         fines_lt63  % <63 um (from slim step 15)
#                         is_fine     1 if fines_lt63 >= FINE_THRESHOLD, else 0
#                         fines_basis how fines_lt63 was derived
#   grain_size_fraction one row per grain-size mass-fraction measurement:
#                         the corrected % (value_std_corr), with parsed size
#                         bounds; gs_corr='invalid' rows and grain-size
#                         *statistics* (GSMEA/GSMED/...) are excluded.
#
# `measurement` then keeps chemistry only (target/reference/organic). Labels kept
# elsewhere: element.category, subsample supporting-data flags, event.n_layers.
# Fines columns move off `subsample` into `grain_size`. One-way; guarded.

clean_path    <- "./data/db/ices_dome_clean.sqlite"
chem_cats     <- c("target", "reference", "organic")
FINE_THRESHOLD <- 50   # % mud (>=63 um) for is_fine; provisional

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

# ── 2. grain_size summary: sieved/bulk + fines per subsample ─────────────────
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

grain_size <- class_ss |>
  left_join(subsample |> select(subsample_id, fines_lt63, fines_basis),
            by = "subsample_id") |>
  mutate(is_fine = if_else(is.na(fines_lt63), NA_real_,
                           as.numeric(fines_lt63 >= FINE_THRESHOLD))) |>
  transmute(subsample_id, frac_class, fines_lt63, is_fine = as.integer(is_fine),
            fines_basis)

# keep only fractions of subsamples that survived (known frac_class)
fraction <- fraction |> semi_join(grain_size, by = "subsample_id")

# ── 3. Rebuild measurement: chemistry only, grain-size columns dropped ───────
measurement <- m |>
  left_join(element |> select(symbol, category), by = "symbol") |>
  filter(category %in% chem_cats) |>
  select(measurement_id, subsample_id, symbol, value, unit, value_std, unit_std,
         value_sd, n_rep, value_uncrt, matrix, method_id)

# fines columns move off subsample into grain_size
subsample <- subsample |> select(-any_of(c("fines_lt63", "fines_basis")))

# ── 4. Write back ────────────────────────────────────────────────────────────
dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
dbWriteTable(con, "subsample",   subsample,   overwrite = TRUE)
dbWriteTable(con, "grain_size",          grain_size, overwrite = TRUE)
dbWriteTable(con, "grain_size_fraction", fraction,   overwrite = TRUE)
for (ix in c("CREATE UNIQUE INDEX IF NOT EXISTS ix_meas_pk ON measurement(measurement_id)",
             "CREATE UNIQUE INDEX IF NOT EXISTS ix_gs_pk ON grain_size(subsample_id)",
             "CREATE INDEX IF NOT EXISTS ix_gsf_ss ON grain_size_fraction(subsample_id)"))
  invisible(dbExecute(con, ix))

# ── 5. Verify ────────────────────────────────────────────────────────────────
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
cat("\nany composition left in measurement (should be 0):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category='composition'")$n, "\n")

dbDisconnect(con)
