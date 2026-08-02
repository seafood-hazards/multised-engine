library(DBI)
library(RSQLite)
library(tidyverse)

# ── Refine stage 2: build the slim `normaliser` table ────────────────────────
# FE / AL / CORG were kept out of the refined fact tables in step 01. Here they are
# reshaped from the merged measurements into one compact carrier at the correct grain,
# (subsample_id, frac_class), wide: columns `fe`, `al`, `corg` in the standardised unit
# (mg/kg). This is the "remove FE/AL/CORG from measurement" step, done without loss.
#
# A normaliser is NOT unique per subsample (~3,939 subsamples carry both fractions),
# so the grain is (subsample, fraction). Where a (subsample, fraction) has more than
# one method row for a normaliser (FE ~4.6%, AL/CORG ~0.2%), the values are
# MEAN-COLLAPSED, as the merged-DB analyses did. Reads FE/AL/CORG from the merged DB;
# writes the `normaliser` table into data/db/multised_refined.sqlite.

src_db <- "./data/db/multised_merged.sqlite"
out_db <- "./data/db/multised_refined.sqlite"

NORMS <- c("FE", "AL", "CORG")

# ── 1. Read the normaliser measurements from the merged DB ────────────────────
srccon <- dbConnect(SQLite(), src_db)
meas <- as_tibble(dbGetQuery(srccon, sprintf("
  SELECT subsample_id, symbol, frac_class, value_std
  FROM measurement
  WHERE symbol IN (%s)
", paste(sprintf("'%s'", NORMS), collapse = ", "))))
dbDisconnect(srccon)

dropped_frac <- meas |> filter(!frac_class %in% c("bulk", "sieved"))

# ── 2. Mean-collapse to one value per (subsample, fraction, normaliser) ───────
collapsed <- meas |>
  filter(frac_class %in% c("bulk", "sieved"), !is.na(value_std), value_std > 0) |>
  group_by(subsample_id, frac_class, symbol) |>
  summarise(value = mean(value_std), n_meth = n(), .groups = "drop")

n_collapsed <- sum(collapsed$n_meth > 1)

# ── 3. Widen to fe / al / corg ───────────────────────────────────────────────
df_normaliser <- collapsed |>
  select(subsample_id, frac_class, symbol, value) |>
  pivot_wider(names_from = symbol, values_from = value) |>
  rename_with(tolower, any_of(NORMS))
for (c in c("fe", "al", "corg")) if (!c %in% names(df_normaliser)) df_normaliser[[c]] <- NA_real_
df_normaliser <- df_normaliser |> select(subsample_id, frac_class, fe, al, corg)

# ── 4. Write the normaliser table into the refined DB ────────────────────────
outcon <- dbConnect(SQLite(), out_db)
dbWriteTable(outcon, "normaliser", as.data.frame(df_normaliser), overwrite = TRUE)
dbDisconnect(outcon)

# ── 5. Sanity summary ────────────────────────────────────────────────────────
cat("normaliser table written to", out_db, "\n\n")
cat(sprintf("rows (subsample x fraction): %d\n", nrow(df_normaliser)))
cat(sprintf("  by fraction: bulk %d, sieved %d\n",
            sum(df_normaliser$frac_class == "bulk"),
            sum(df_normaliser$frac_class == "sieved")))
cat("coverage (non-NA):\n")
cat(sprintf("  fe   %6d (%.0f%%)\n", sum(!is.na(df_normaliser$fe)),   100 * mean(!is.na(df_normaliser$fe))))
cat(sprintf("  al   %6d (%.0f%%)\n", sum(!is.na(df_normaliser$al)),   100 * mean(!is.na(df_normaliser$al))))
cat(sprintf("  corg %6d (%.0f%%)\n", sum(!is.na(df_normaliser$corg)), 100 * mean(!is.na(df_normaliser$corg))))
cat(sprintf("\nmean-collapsed (subsample x fraction x normaliser) groups with >1 method: %d\n",
            n_collapsed))
if (nrow(dropped_frac) > 0)
  cat(sprintf("note: %d normaliser rows with frac_class not in bulk/sieved were excluded\n",
              nrow(dropped_frac)))
