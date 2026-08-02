library(DBI)
library(RSQLite)
library(tidyverse)

# ── Refine stage 3: bake the normalisation ratios onto the measurement table ──
# Add ratio_fe / ratio_al / ratio_corg to `measurement`: the target value_std divided
# by the co-located normaliser (same subsample, same fraction) from the step-02
# `normaliser` table. These are the reusable enrichment inputs (metal / Fe, metal / Al,
# metal / organic-carbon) the later pristine analyses consume without recomputing. A
# ratio is NULL where the target value or the matching normaliser is missing /
# non-positive.
#
# measurement carries frac_class, so it is joined to the normaliser on both
# subsample_id and frac_class. All values are mg/kg, so the ratios are dimensionless.
# Reads/writes data/db/multised_refined.sqlite in place.

db <- "./data/db/multised_refined.sqlite"

con <- dbConnect(SQLite(), db)
norm <- as_tibble(dbReadTable(con, "normaliser"))
meas <- as_tibble(dbReadTable(con, "measurement"))

out <- meas |>
  left_join(norm, by = c("subsample_id", "frac_class")) |>
  mutate(
    ratio_fe   = if_else(!is.na(value_std) & !is.na(fe)   & fe   > 0, value_std / fe,   NA_real_),
    ratio_al   = if_else(!is.na(value_std) & !is.na(al)   & al   > 0, value_std / al,   NA_real_),
    ratio_corg = if_else(!is.na(value_std) & !is.na(corg) & corg > 0, value_std / corg, NA_real_)) |>
  select(-fe, -al, -corg)

dbWriteTable(con, "measurement", as.data.frame(out), overwrite = TRUE)
dbDisconnect(con)

# ── Sanity summary ───────────────────────────────────────────────────────────
cov <- function(x) sprintf("%d (%.0f%%)", sum(!is.na(x)), 100 * mean(!is.na(x)))
cat("ratios written to measurement in", db, "\n\n")
for (fr in c("bulk", "sieved")) {
  d <- out |> filter(frac_class == fr)
  cat(sprintf("%s (%d target rows):\n", fr, nrow(d)))
  cat(sprintf("  ratio_fe   %s\n", cov(d$ratio_fe)))
  cat(sprintf("  ratio_al   %s\n", cov(d$ratio_al)))
  cat(sprintf("  ratio_corg %s\n", cov(d$ratio_corg)))
}
