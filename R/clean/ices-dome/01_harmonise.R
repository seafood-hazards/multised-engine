library(DBI)
library(RSQLite)
library(tidyverse)
source("R/clean/_shared/element_meta.R")  # element_meta + apply_element_meta()
source("R/clean/_shared/dataset_meta.R")  # dataset_meta + standardise_dataset()
source("R/clean/_shared/site_meta.R")     # SITE_COLS + standardise_site()
source("R/clean/_shared/event_meta.R")    # tool_names + standardise_event()
source("R/clean/_shared/method_meta.R")   # standardise_method()
source("R/clean/_shared/matrix_meta.R")   # standardise_matrix()

# ── Clean stage, Step 1: Harmonise (ICES-DOME) ───────────────────────────────
# Reads the slim DB and writes ./data/db/ices_dome_clean.sqlite in a uniform
# format. ICES-DOME is the naming reference, so most maps here are identity; the
# real transformation for this source is depth -> cm. The script establishes the
# clean-DB build pattern the other sources' 01_harmonise.R will reuse (with fuller
# symbol / unit / tool maps). Value-preserving: no rows removed, originals kept.
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

slim_path  <- "./data/db/ices_dome_slim.sqlite"
clean_path <- "./data/db/ices_dome_clean.sqlite"

DEPTH_TO_CM <- 100  # ICES-DOME depths are in metres (confirmed: 0.01-2 m slices)

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
    str_remove(regex("\\s*(dw|ww)\\b.*$", ignore_case = TRUE)) |>  # drop dw/ww (Vannmiljo)
    str_trim()
}

element     <- element     |> mutate(symbol = harmonise_symbol(symbol))
measurement <- measurement |> mutate(symbol = harmonise_symbol(symbol),
                                      unit   = harmonise_unit(unit))
method      <- method      |> mutate(symbol = harmonise_symbol(symbol))

# ── 3. Depth -> cm ───────────────────────────────────────────────────────────
subsample <- subsample |>
  mutate(depth_from = depth_from * DEPTH_TO_CM,
         depth_to   = depth_to   * DEPTH_TO_CM)

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
element   <- apply_element_meta(element)  # rename element->name, add canonical name + cas
dataset   <- standardise_dataset(dataset) # uniform columns + url / accessed / source_type
site      <- standardise_site(site)       # uniform columns (adds depth where absent)
event     <- standardise_event(event)     # short tool names + drop multi_flag / tool_description
method    <- standardise_method(method, element) # ICES vocab, drop grain-size methods, lod/loq -> mg/kg
measurement <- measurement |> select(any_of(c(
  "measurement_id", "subsample_id", "symbol", "value", "unit",
  "value_std", "unit_std", "value_std_corr", "gs_corr", "matrix", "fraction_range",
  "uncrt", "metcu", "method_id",
  "invalid_flag", "dup_flag", "below_loq", "below_loq_num",
  "range_flag", "weight_basis", "src_flag")))
measurement <- standardise_matrix(measurement)  # matrix -> ICES SED* vocab (identity; already ICES)

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
