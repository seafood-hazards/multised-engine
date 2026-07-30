library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/site_meta.R")  # consume_area_flag()

# ── Clean stage, Step 2: Clean (Mareano) ───────────────────────────────────
# Operates on mareano_clean.sqlite (built by 01_harmonise.R). Removes chemistry
# measurements that failed QC, then collapses duplicates and averages technical
# replicates. Grain-size (composition) rows pass through untouched; their cleaning
# is the Annotate step (grain_size table build). Rewrites the measurement table.
#
# Order: standardise uncertainty -> remove flagged rows -> collapse per occasion.
# Removal (chemistry only): range_flag, invalid_flag, below_loq / below_loq_num,
# weight_basis = 'wet', any src_flag (all source-specific QC failures).
# Collapse key = sampling occasion + element + method: site + date + depth +
# symbol + unit + method + lab (mirrors slim step 5). Within a group the distinct
# value_std values are the technical replicates (identical values are duplicates,
# counted once); one row is emitted with value_std = mean, value_sd = SD,
# n_rep = number of distinct values, value_uncrt = mean standardised uncertainty.

clean_path <- "./data/db/mareano_clean.sqlite"
chem_cats  <- c("target", "reference", "organic")

con <- dbConnect(RSQLite::SQLite(), clean_path)
element   <- dbReadTable(con, "element")     |> as_tibble()
method    <- dbReadTable(con, "method")      |> as_tibble()
event     <- dbReadTable(con, "event")       |> as_tibble()
subsample <- dbReadTable(con, "subsample")   |> as_tibble()
m         <- dbReadTable(con, "measurement") |> as_tibble()
site      <- dbReadTable(con, "site")        |> as_tibble()

# This step consumes the QC flag columns and collapses rows (one-way). The clean
# steps run in sequence on a fresh DB: 01_harmonise -> 02_clean -> 03_annotate.
# Guard against an accidental second run, which would reset n_rep / value_sd.
if (!"range_flag" %in% names(m)) {
  dbDisconnect(con)
  stop("measurement carries no QC flags -- it looks already cleaned. ",
       "Re-run 01_harmonise.R to rebuild the clean DB before 02_clean.R.")
}

# ── 0. Remove out-of-scope sites (area_flag = 'outside_europe') and cascade ──
# Consume the slim area_flag: drop sites outside Europe (e.g. a corrupt Vannmiljø
# coordinate in the Gulf of Guinea) and their linked event / subsample /
# measurement rows, then drop the area_flag column. No-op where nothing is flagged.
pr <- consume_area_flag(site, event, subsample, m)
site <- pr$site; event <- pr$event; subsample <- pr$subsample; m <- pr$measurement
if (pr$n_sites)
  cat(sprintf("removed %d outside_europe site(s): %d events, %d subsamples, %d measurements\n",
              pr$n_sites, pr$n_events, pr$n_subsamples, pr$n_measurements))

# ── 1. Standardise analytical uncertainty to mg/kg (value_uncrt) ─────────────
# ICES uncrt + metcu: '%' = percent (relative), 'SD' = 1 sigma (absolute),
# 'U2' = expanded uncertainty, coverage factor 2 (so 1 sigma = U2 / 2). Reduce to
# a 1-sigma value in the measurement's unit, then convert to mg/kg like value_std.
mass_basis <- tibble::tribble(
  ~unit_canon, ~denom,
  "%", 1e2, "vol.%", 1e2, "wt.%", 1e2,
  "g/kg", 1e3, "g/kg c", 1e3, "mg/g", 1e3,
  "mg/kg", 1e6, "ug/g", 1e6, "ppm", 1e6,
  "ug/kg", 1e9, "ng/g", 1e9, "ppb", 1e9)
canon_unit <- function(u) u |> str_to_lower() |> str_trim() |>
  str_remove("\\s*(dw|ww)$") |> str_replace_all("µ|μ", "u")

has_uncrt <- all(c("uncrt", "metcu") %in% names(m))
m <- m |> left_join(element |> select(symbol, category), by = "symbol")
m$unit_canon <- canon_unit(m$unit)
m <- m |> left_join(mass_basis, by = "unit_canon")
m$value_uncrt <- NA_real_
if (has_uncrt) {
  sigma <- with(m, case_when(
    is.na(uncrt)   ~ NA_real_,
    metcu == "%"   ~ uncrt / 100 * value,   # relative -> absolute in the unit
    metcu == "U2"  ~ uncrt / 2,             # expanded (k=2) -> 1 sigma
    metcu == "SD"  ~ uncrt,
    TRUE           ~ NA_real_))
  m$value_uncrt <- if_else(m$category %in% chem_cats & !is.na(m$denom),
                           sigma / m$denom * 1e6, NA_real_)
}

# ── 2. Remove failed-QC chemistry rows ───────────────────────────────────────
chem <- m |> filter(category %in% chem_cats)
comp <- m |> filter(!category %in% chem_cats)

# Removal flags, guarded for columns a source may not have (MUDAB has no src_flag).
col_or_false <- function(df, col, pred)
  if (col %in% names(df)) pred(df[[col]]) else rep(FALSE, nrow(df))
drop <-
  col_or_false(chem, "range_flag",    function(x) !is.na(x)) |
  col_or_false(chem, "invalid_flag",  function(x) !is.na(x)) |
  col_or_false(chem, "below_loq",     function(x) coalesce(x == 1L, FALSE)) |
  col_or_false(chem, "below_loq_num", function(x) coalesce(x == 1L, FALSE)) |
  col_or_false(chem, "weight_basis",  function(x) coalesce(x == "wet", FALSE)) |
  col_or_false(chem, "src_flag",      function(x) !is.na(x))
n_before <- nrow(chem)
chem <- chem[!drop, ]
cat(sprintf("chemistry rows: %d -> %d (removed %d failed-QC)\n",
            n_before, nrow(chem), sum(drop)))

# ── 3. Collapse duplicates + average technical replicates ────────────────────
mkey <- method |> select(method_id, method, lab)
grp <- chem |>
  left_join(subsample |> select(subsample_id, event_id, depth_from, depth_to),
            by = "subsample_id") |>
  left_join(event |> select(event_id, site_id, date), by = "event_id") |>
  left_join(mkey, by = "method_id")
if (!"matrix" %in% names(grp)) grp$matrix <- NA_character_  # Mareano has no matrix

collapsed <- grp |>
  group_by(site_id, date, depth_from, depth_to, symbol, unit, method, lab) |>
  summarise(
    measurement_id = first(measurement_id),
    subsample_id   = first(subsample_id),
    method_id      = first(method_id),
    matrix         = first(matrix),
    unit_std       = first(unit_std),
    # value_sd / n_rep MUST be computed before value_std is overwritten below,
    # else they would see the scalar mean instead of the original column.
    n_rep          = n_distinct(value_std),
    value_sd       = if (n_distinct(value_std) > 1) sd(unique(value_std)) else NA_real_,
    value          = mean(unique(value)),
    value_std      = mean(unique(value_std)),
    value_uncrt    = if (all(is.na(value_uncrt))) NA_real_ else mean(value_uncrt, na.rm = TRUE),
    .groups = "drop") |>
  select(measurement_id, subsample_id, symbol, value, unit, value_std, unit_std,
         value_sd, n_rep, value_uncrt, matrix, method_id)

cat(sprintf("chemistry after collapse: %d rows (%d technical-replicate groups averaged)\n",
            nrow(collapsed), sum(collapsed$n_rep > 1)))

# ── 4. Rebuild measurement: cleaned chemistry + untouched composition ────────
comp <- comp |>
  select(any_of(c("measurement_id", "subsample_id", "symbol", "value", "unit",
                  "value_std", "unit_std", "value_std_corr", "gs_corr",
                  "matrix", "fraction_range", "method_id")))
measurement <- bind_rows(collapsed, comp)  # bind_rows fills absent columns with NA

dbWriteTable(con, "measurement", measurement, overwrite = TRUE)
dbWriteTable(con, "site", site, overwrite = TRUE)          # area_flag consumed + dropped
if (pr$n_sites) {                                          # cascade: rewrite the pruned subtree
  dbWriteTable(con, "event", event, overwrite = TRUE)
  dbWriteTable(con, "subsample", subsample, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_subsample_ev ON subsample(event_id)")
}
invisible(dbExecute(con, "CREATE UNIQUE INDEX IF NOT EXISTS ix_measurement_pk ON measurement(measurement_id)"))
invisible(dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_measurement_ss ON measurement(subsample_id)"))

# ── 5. Verify ────────────────────────────────────────────────────────────────
cat("\nmeasurement columns:\n"); print(dbListFields(con, "measurement"))
cat("\nrow counts:\n")
print(dbGetQuery(con, "SELECT
    SUM(CASE WHEN e.category IN ('target','reference','organic') THEN 1 ELSE 0 END) chemistry,
    SUM(CASE WHEN e.category='composition' THEN 1 ELSE 0 END) grain_size,
    COUNT(*) total
  FROM measurement m JOIN element e ON m.symbol=e.symbol"))
cat("\naveraged replicates (n_rep>1):\n")
print(dbGetQuery(con, "SELECT n_rep, COUNT(*) groups FROM measurement WHERE n_rep>1 GROUP BY n_rep ORDER BY n_rep LIMIT 8"))
cat("\nvalue_uncrt present (chemistry):",
    dbGetQuery(con, "SELECT COUNT(*) n FROM measurement WHERE value_uncrt IS NOT NULL")$n, "\n")

dbDisconnect(con)
