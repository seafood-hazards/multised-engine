# Explore Vannmiljø slim value distributions, separately for the target elements,
# the Fe/Al normalisers, and the grain-size parameters. Console-only checking
# ahead of a "Source specific" Quarto page. Run from the project root.
#
# Notes on Vannmiljø specifics:
#  - `operator` carries the relational sign: '=' quantified, '<'/'ND' below-limit,
#    '>' above-range. Distribution stats are computed on quantified, valid rows
#    only (operator '=' and invalid_flag IS NULL); the other operators are counted.
#  - `filtered` is present but almost always 0 (barely informative).
#  - Units are split into their own rows: MO is reported in both mg/kg and µg/kg,
#    so pooling would be meaningless.

library(DBI)
library(RSQLite)
library(tidyverse)

con <- dbConnect(RSQLite::SQLite(), "./data/db/vannmiljo_slim.sqlite")

targets <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
refs    <- c("FE", "AL")
organic <- c("TOC", "TOC63")

m <- dbReadTable(con, "measurement") |> as_tibble()
el <- dbReadTable(con, "element") |> as_tibble()
dbDisconnect(con)

d <- m |>
  mutate(sym = str_to_upper(symbol)) |>
  left_join(el |> transmute(symbol, element), by = "symbol") |>
  mutate(group = case_when(
    sym %in% targets ~ "1 target",
    sym %in% refs    ~ "2 reference (Fe/Al)",
    sym %in% organic ~ "organic",
    TRUE             ~ "3 grain-size"))

# One summary row per symbol + unit (units are not comparable across rows).
summarise_group <- function(df) {
  counts <- df |>
    group_by(sym, element, unit) |>
    summarise(
      n           = n(),
      n_eq        = sum(operator == "=",  na.rm = TRUE),
      n_lt        = sum(operator == "<",  na.rm = TRUE),
      n_nd        = sum(operator == "ND", na.rm = TRUE),
      n_gt        = sum(operator == ">",  na.rm = TRUE),
      n_below_loq = sum(below_loq == 1L,  na.rm = TRUE),
      n_over      = sum(invalid_flag == "over_range", na.rm = TRUE),
      n_filtered  = sum(filtered == 1L,   na.rm = TRUE),
      .groups = "drop")

  stats <- df |>
    filter(operator == "=", is.na(invalid_flag)) |>   # quantified & valid only
    group_by(sym, unit) |>
    summarise(
      min    = min(value),
      q25    = quantile(value, 0.25),
      median = median(value),
      mean   = mean(value),
      q75    = quantile(value, 0.75),
      max    = max(value),
      .groups = "drop")

  counts |>
    left_join(stats, by = c("sym", "unit")) |>
    arrange(desc(n))
}

opts <- options(pillar.sigfig = 4, width = 200)
for (g in sort(unique(d$group))) {
  if (g == "organic") next   # not part of this check
  cat("\n========== ", toupper(g), " ==========\n")
  print(summarise_group(filter(d, group == g)), n = Inf)
}
options(opts)
