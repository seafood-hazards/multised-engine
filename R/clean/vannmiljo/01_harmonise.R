library(DBI)
library(RSQLite)
library(tidyverse)

# ── Clean stage, Step 1: Harmonise (Vannmiljø) ───────────────────────────────
# Reads the slim DB and writes ./data/db/vannmiljo_clean.sqlite in a uniform
# format. Vannmiljø-specific: units carry a 'dw' (and 'C' for carbon) suffix that
# is stripped; symbols TOC->CORG (TOC63 kept); date is derived from datetime;
# depths are cm but a corrupt tail is nulled; sampling_tool holds ISO standards
# that do not map to ICES gear (left as-is). No matrix / uncertainty.
#
# Harmonisations applied:
#   - symbol  -> ICES canonical (case-fold; TOC->CORG for other sources, none here)
#   - unit    -> ICES names (strip dw/ww suffix, micro sign -> u; identity here)
#   - depth   -> cm (ICES stores metres; x100. e.g. 0.02 m = 2 cm surface slice)
#   - event   -> keep date/year, derive date from datetime where needed, drop
#                datetime/time (ICES already has date, none to drop)
#   - method  -> keep LOD/LOQ, add limit_unit (the method's reporting unit)
# Already-folded raw columns (basis, qflag, vflag, dcflag) are dropped; the flags
# derived from them (weight_basis, below_loq, src_flag) and everything the later
# Clean / Annotate steps need (matrix, uncrt/metcu, value_std*, labels) are kept.

slim_path  <- "./data/db/vannmiljo_slim.sqlite"
clean_path <- "./data/db/vannmiljo_clean.sqlite"

DEPTH_TO_CM <- 1    # Vannmiljo depths are cm; a corrupt tail is nulled below
DEPTH_MAX_CM <- 300 # implausible above this (or inverted); set to NA

# ── 1. Read slim tables ──────────────────────────────────────────────────────
scon <- dbConnect(RSQLite::SQLite(), slim_path)
element     <- dbReadTable(scon, "element")     |> as_tibble()
dataset     <- dbReadTable(scon, "dataset")     |> as_tibble()
site        <- dbReadTable(scon, "site")        |> as_tibble()
event       <- dbReadTable(scon, "event")       |> as_tibble()
method      <- dbReadTable(scon, "method")      |> as_tibble()
subsample   <- dbReadTable(scon, "subsample")   |> as_tibble()
measurement <- dbReadTable(scon, "measurement") |> as_tibble()
dbDisconnect(scon)

# ── 2. Harmonisation maps (ICES is the reference: identity results here) ─────
harmonise_symbol <- function(sym) {
  s <- str_to_upper(str_trim(sym))
  # TOC / TOC63 -> CORG unification is a no-op for ICES (it has no TOC); other
  # sources map TOC -> CORG and keep TOC63. Chemistry symbols are already ICES.
  recode(s, "TOC" = "CORG")
}
harmonise_unit <- function(u) {
  u |>
    str_trim() |>
    str_replace_all("µ|μ", "u") |>                 # micro sign / greek mu -> u
    str_remove(regex("\\s*(c\\s+)?(dw|ww)\\b.*$", ignore_case = TRUE)) |>  # drop C / dw / ww suffix
    str_trim()
}

element     <- element     |> mutate(symbol = harmonise_symbol(symbol))
measurement <- measurement |> mutate(symbol = harmonise_symbol(symbol),
                                      unit   = harmonise_unit(unit))
method      <- method      |> mutate(symbol = harmonise_symbol(symbol))

# ── 3. Depth -> cm (+ clean the corrupt tail) ────────────────────────────────
# Vannmiljo depths are cm but a small tail is corrupt: point depths of thousands
# (up to 42,600) and inverted intervals (depth_from > depth_to). Values beyond a
# plausible core length, or inverted, are set to NA (row kept, depth unknown).
n_bad <- with(subsample,
  sum(depth_to > DEPTH_MAX_CM | depth_from > depth_to | depth_from < 0, na.rm = TRUE))
subsample <- subsample |>
  mutate(depth_from = depth_from * DEPTH_TO_CM,
         depth_to   = depth_to   * DEPTH_TO_CM,
         bad_depth  = coalesce(depth_to > DEPTH_MAX_CM | depth_from > depth_to | depth_from < 0, FALSE),
         depth_from = if_else(bad_depth, NA_real_, depth_from),
         depth_to   = if_else(bad_depth, NA_real_, depth_to)) |>
  select(-bad_depth)
cat("Vannmiljo depths nulled as implausible:", n_bad, "\n")

# ── 4. Event: date from datetime, drop datetime/time ─────────────────────────
if (!"date" %in% names(event) && "datetime" %in% names(event)) {
  event$date <- substr(as.character(event$datetime), 1, 10)
} else if ("datetime" %in% names(event) && "date" %in% names(event)) {
  event$date <- coalesce(event$date, substr(as.character(event$datetime), 1, 10))
}
event <- event |> select(-any_of(c("datetime", "time")))

# ── 5. Method: LOD/LOQ reporting unit ────────────────────────────────────────
# lod/loq are in the reporting unit of the method's measurements. A few methods
# span two units (e.g. ug/g + ug/kg); limit_unit takes the modal one (documented
# approximation, mirrors how step 11 converted limits per measurement).
limit_unit <- measurement |>
  filter(!is.na(unit)) |>
  count(method_id, unit) |>
  group_by(method_id) |>
  slice_max(n, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(method_id, limit_unit = unit)
method <- method |> left_join(limit_unit, by = "method_id")

# ── 6. Column selection (drop already-folded raw columns) ────────────────────
element   <- element   |> select(any_of(c("symbol", "element", "category")))
measurement <- measurement |> select(any_of(c(
  "measurement_id", "subsample_id", "symbol", "value", "unit",
  "value_std", "unit_std", "value_std_corr", "gs_corr", "matrix", "fraction_range",
  "uncrt", "metcu", "method_id",
  "invalid_flag", "dup_flag", "below_loq", "below_loq_num",
  "range_flag", "weight_basis", "src_flag")))

# ── 7. Write clean DB ────────────────────────────────────────────────────────
if (file.exists(clean_path)) invisible(file.remove(clean_path))
ccon <- dbConnect(RSQLite::SQLite(), clean_path)
tbls <- list(element = element, dataset = dataset, site = site, event = event,
             method = method, subsample = subsample, measurement = measurement)
for (nm in names(tbls)) dbWriteTable(ccon, nm, tbls[[nm]], overwrite = TRUE)
for (ix in c("CREATE UNIQUE INDEX ix_element_pk ON element(symbol)",
             "CREATE UNIQUE INDEX ix_measurement_pk ON measurement(measurement_id)",
             "CREATE INDEX ix_measurement_ss ON measurement(subsample_id)",
             "CREATE INDEX ix_subsample_ev ON subsample(event_id)")) {
  dbExecute(ccon, ix)
}

# ── 8. Verify ────────────────────────────────────────────────────────────────
cat("Tables written to", clean_path, ":\n")
for (t in dbListTables(ccon))
  cat(sprintf("  %-12s %d rows\n", t, dbGetQuery(ccon, paste0("SELECT COUNT(*) FROM ", t))[[1]]))
cat("\ndepth range now (cm):\n")
print(dbGetQuery(ccon, "SELECT ROUND(MIN(depth_from),1) dmin, ROUND(MAX(depth_to),1) dmax FROM subsample"))
cat("\nchemistry symbols:\n")
print(dbGetQuery(ccon, "SELECT DISTINCT m.symbol FROM measurement m JOIN element e ON m.symbol=e.symbol WHERE e.category IN ('target','reference','organic') ORDER BY m.symbol"))
cat("\nlimit_unit coverage (methods):\n")
print(dbGetQuery(ccon, "SELECT COALESCE(limit_unit,'(none)') limit_unit, COUNT(*) n FROM method GROUP BY limit_unit ORDER BY n DESC"))

dbDisconnect(ccon)
