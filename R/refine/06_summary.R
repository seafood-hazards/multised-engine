library(DBI)
library(RSQLite)
library(tidyverse)

# ── Refine stage 6: retention / reconciliation summary ───────────────────────
# Reporting only (no DB change). Compares the refined DB against the merged DB and
# writes the CSVs the multised-merged creation pages read: the per-table
# transformation, the measurement reconciliation (every merged measurement row
# accounted for), and the coverage of the baked derived fields. Reads both DBs.

merged_db  <- "./data/db/multised_merged.sqlite"
refined_db <- "./data/db/multised_refined.sqlite"
out_dir    <- "data/analysis/refine"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

TARGETS <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
NORMS   <- c("FE", "AL", "CORG")

nrows <- function(con, t) if (t %in% dbListTables(con)) dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM %s", t))$n else NA_integer_

mcon <- dbConnect(SQLite(), merged_db)
rcon <- dbConnect(SQLite(), refined_db)

# ── 1. Per-table transformation ──────────────────────────────────────────────
tables <- tribble(
  ~table,                ~disposition,
  "element",             "trimmed to 7 targets",
  "dataset",             "carried",
  "method",              "trimmed to methods used by targets",
  "event",               "carried",
  "site",                "carried + aqua_id, repeat_group, n_years",
  "subsample",           "carried (physical; fines_lt63 kept)",
  "measurement",         "targets only; +frac_class +ratios; FE/AL/CORG to normaliser; dropped unit_std/matrix/sieve_um",
  "normaliser",          "new: FE/AL/CORG wide, (subsample x fraction)",
  "aquaculture",         "new: imported reference",
  "grain_size_fraction", "dropped (derived fines_lt63 kept on subsample)")
# merged_rows is the source-table count (NA for tables new in refined, e.g. the split
# fact tables and normaliser: the measurement split is owned by the reconciliation CSV)
tables <- tables |>
  mutate(merged_rows  = map_int(table, ~ as.integer(nrows(mcon, .x))),
         refined_rows = map_int(table, ~ as.integer(nrows(rcon, .x))),
         refined_rows = if_else(table == "grain_size_fraction", 0L, refined_rows))

# ── 2. Measurement reconciliation (every merged row accounted for) ───────────
msym <- as_tibble(dbGetQuery(mcon, "SELECT symbol FROM measurement"))
recon <- msym |>
  mutate(group = case_when(symbol %in% TARGETS ~ "targets",
                           symbol %in% NORMS   ~ "FE/AL/CORG",
                           TRUE                ~ symbol)) |>
  count(group, name = "rows") |>
  mutate(destination = case_when(
    group == "targets"    ~ "measurement (bulk + sieved)",
    group == "FE/AL/CORG" ~ "normaliser (reshaped)",
    group == "TOC63"      ~ "dropped (fines-normalised organic, not whole-sample CORG)",
    TRUE                  ~ "dropped")) |>
  arrange(desc(rows))

# ── 3. Coverage of the baked derived fields ──────────────────────────────────
norm <- as_tibble(dbReadTable(rcon, "normaliser"))
meas_r <- as_tibble(dbReadTable(rcon, "measurement"))
bulk <- meas_r |> filter(frac_class == "bulk")
siev <- meas_r |> filter(frac_class == "sieved")
site <- as_tibble(dbReadTable(rcon, "site"))

cov_row <- function(scope, field, present, total)
  tibble(scope, field, n_present = present, n_total = total,
         pct = round(100 * present / total))

coverage <- bind_rows(
  cov_row("normaliser bulk",   "fe",   sum(norm$frac_class=="bulk" & !is.na(norm$fe)),   sum(norm$frac_class=="bulk")),
  cov_row("normaliser bulk",   "al",   sum(norm$frac_class=="bulk" & !is.na(norm$al)),   sum(norm$frac_class=="bulk")),
  cov_row("normaliser bulk",   "corg", sum(norm$frac_class=="bulk" & !is.na(norm$corg)), sum(norm$frac_class=="bulk")),
  cov_row("normaliser sieved", "fe",   sum(norm$frac_class=="sieved" & !is.na(norm$fe)),   sum(norm$frac_class=="sieved")),
  cov_row("normaliser sieved", "al",   sum(norm$frac_class=="sieved" & !is.na(norm$al)),   sum(norm$frac_class=="sieved")),
  cov_row("normaliser sieved", "corg", sum(norm$frac_class=="sieved" & !is.na(norm$corg)), sum(norm$frac_class=="sieved")),
  cov_row("measurement bulk",   "ratio_fe",   sum(!is.na(bulk$ratio_fe)),   nrow(bulk)),
  cov_row("measurement bulk",   "ratio_al",   sum(!is.na(bulk$ratio_al)),   nrow(bulk)),
  cov_row("measurement bulk",   "ratio_corg", sum(!is.na(bulk$ratio_corg)), nrow(bulk)),
  cov_row("measurement sieved", "ratio_fe",   sum(!is.na(siev$ratio_fe)),   nrow(siev)),
  cov_row("measurement sieved", "ratio_al",   sum(!is.na(siev$ratio_al)),   nrow(siev)),
  cov_row("measurement sieved", "ratio_corg", sum(!is.na(siev$ratio_corg)), nrow(siev)),
  cov_row("site", "aqua_id",           sum(!is.na(site$aqua_id)),  nrow(site)),
  cov_row("site", "repeat n_years>=3", sum(site$n_years >= 3),     nrow(site)))

dbDisconnect(mcon); dbDisconnect(rcon)

# ── 4. Write + console ───────────────────────────────────────────────────────
write_csv(tables,   file.path(out_dir, "refined_tables.csv"))
write_csv(recon,    file.path(out_dir, "refined_reconciliation.csv"))
write_csv(coverage, file.path(out_dir, "refined_coverage.csv"))

cat("refine summary written to", out_dir, "\n\n")
cat("per-table transformation:\n")
tables |> select(table, merged_rows, refined_rows, disposition) |> as.data.frame() |> print(row.names = FALSE)
cat("\nmeasurement reconciliation (merged rows all accounted for):\n")
recon |> as.data.frame() |> print(row.names = FALSE)
cat(sprintf("  total merged measurement rows: %d\n", sum(recon$rows)))
cat("\nderived-field coverage:\n")
coverage |> as.data.frame() |> print(row.names = FALSE)
