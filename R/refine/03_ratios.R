library(DBI)
library(RSQLite)
library(tidyverse)

# ── Refine stage 3: bake the normalisation ratios onto the fact tables ────────
# Add ratio_fe / ratio_al / ratio_corg to bulk_measurement and sieved_measurement:
# the target value_std divided by the co-located normaliser (same subsample, same
# fraction) from the step-02 `normaliser` table. These are the reusable enrichment
# inputs (metal / Fe, metal / Al, metal / organic-carbon) the later pristine analyses
# consume without recomputing. A ratio is NULL where the target value or the matching
# normaliser is missing / non-positive.
#
# The fact tables carry no frac_class column (the table name encodes it), so each is
# joined to the normaliser rows of its own fraction. All values are mg/kg, so the
# ratios are dimensionless. Reads/writes data/db/multised_refined.sqlite in place.

db <- "./data/db/multised_refined.sqlite"

con <- dbConnect(SQLite(), db)
norm <- as_tibble(dbReadTable(con, "normaliser"))

add_ratios <- function(tbl, fraction) {
  fact <- as_tibble(dbReadTable(con, tbl))
  nf <- norm |> filter(frac_class == fraction) |> select(subsample_id, fe, al, corg)
  out <- fact |>
    left_join(nf, by = "subsample_id") |>
    mutate(
      ratio_fe   = if_else(!is.na(value_std) & !is.na(fe)   & fe   > 0, value_std / fe,   NA_real_),
      ratio_al   = if_else(!is.na(value_std) & !is.na(al)   & al   > 0, value_std / al,   NA_real_),
      ratio_corg = if_else(!is.na(value_std) & !is.na(corg) & corg > 0, value_std / corg, NA_real_)) |>
    select(-fe, -al, -corg)
  dbWriteTable(con, tbl, as.data.frame(out), overwrite = TRUE)
  out
}

bulk   <- add_ratios("bulk_measurement", "bulk")
sieved <- add_ratios("sieved_measurement", "sieved")
dbDisconnect(con)

# ── Sanity summary ───────────────────────────────────────────────────────────
cov <- function(x) sprintf("%d (%.0f%%)", sum(!is.na(x)), 100 * mean(!is.na(x)))
cat("ratios written to bulk_measurement / sieved_measurement in", db, "\n\n")
for (nm in c("bulk", "sieved")) {
  d <- get(nm)
  cat(sprintf("%s (%d target rows):\n", nm, nrow(d)))
  cat(sprintf("  ratio_fe   %s\n", cov(d$ratio_fe)))
  cat(sprintf("  ratio_al   %s\n", cov(d$ratio_al)))
  cat(sprintf("  ratio_corg %s\n", cov(d$ratio_corg)))
}
