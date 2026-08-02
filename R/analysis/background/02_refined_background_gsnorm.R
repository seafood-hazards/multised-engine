library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, grain-size-normalised background (REFINED database) ───────
# The second background page. A raw background (page 1) mixes grain size in: muddy
# sediment carries more metal, and the coast tends to be muddier, so part of the
# coastal signal is grain size, not pressure. Normalising to a grain-size proxy strips
# that out. We do it THREE ways side by side, per element x fraction:
#
#   al    : metal / Al  (aluminium, the textbook lithogenic grain-size normaliser)
#   fe    : metal / Fe  (iron, the secondary carrier)
#   fines : metal per unit mud fraction, value_std / (fines_lt63 / 100), i.e. the
#           concentration scaled to 100% mud. Computed only where fines_lt63 >=
#           FINES_MIN%, since dividing a sandy sample by a tiny mud fraction is unstable.
#
# For each (element, fraction, basis) we take the global percentiles and the offshore
# (dist_to_coast > DIST_MAIN km) percentiles, as on page 1, so the offshore/global
# shift can be compared to the raw shift: if grain size drove the coastal signal, the
# normalised shift moves toward 1. Fractions bulk/sieved63/sieved20, outliers dropped.
#
# Outputs -> data/analysis/background/ (gitignored):
#   refined_gsnorm_percentiles.csv  element x fraction x basis x subset: percentiles
#   refined_gsnorm_compare.csv      global vs offshore P90 per basis, the shift
#   refined_gsnorm_meta.csv         one-row config

db_path <- "./data/db/multised_refined.sqlite"

CATS      <- c("bulk", "sieved63", "sieved20")
BASES     <- c("al", "fe", "fines")
DIST_MAIN <- 10
FINES_MIN <- 10        # % mud floor for the fines-normalised basis
MIN_N     <- 30L
elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

out_dir <- "data/analysis/background"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

PROBS <- c(p10 = .10, p25 = .25, p50 = .50, p75 = .75, p90 = .90)
pctl <- function(v) {
  q <- quantile(v, PROBS, names = FALSE, na.rm = TRUE)
  bind_cols(tibble(n = length(v)),
            as_tibble(as.list(setNames(signif(q, 4), names(PROBS)))))
}

# ── 1. Pull chemistry + normalisers + fines + distance ───────────────────────
con <- dbConnect(SQLite(), db_path)
m <- as_tibble(dbGetQuery(con, "
  SELECT me.symbol, me.frac_class, me.sieve_um_std, me.value_std,
         me.ratio_al, me.ratio_fe, s.fines_lt63, si.dist_to_coast
  FROM measurement me
  JOIN subsample s ON s.subsample_id = me.subsample_id
  JOIN event e     ON e.event_id     = s.event_id
  JOIN site  si    ON si.site_id     = e.site_id
  WHERE me.value_std > 0 AND me.outlier_flag IS NULL
")) |>
  mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                         sieve_um_std == 63 ~ "sieved63",
                         sieve_um_std == 20 ~ "sieved20",
                         TRUE ~ NA_character_)) |>
  filter(cat %in% CATS) |>
  mutate(al = ratio_al, fe = ratio_fe,
         fines = if_else(!is.na(fines_lt63) & fines_lt63 >= FINES_MIN,
                         value_std / (fines_lt63 / 100), NA_real_))
dbDisconnect(con)

# ── 2. Long over the three bases, then percentiles per subset ────────────────
long <- m |>
  select(symbol, cat, dist_to_coast, all_of(BASES)) |>
  pivot_longer(all_of(BASES), names_to = "basis", values_to = "v") |>
  filter(!is.na(v), v > 0)

subset_pctl <- function(df, label) {
  df |> group_by(symbol, cat, basis) |> reframe(pctl(v)) |> mutate(subset = label)
}
percentiles <- bind_rows(
  subset_pctl(long, "global"),
  subset_pctl(long |> filter(dist_to_coast > DIST_MAIN), sprintf("offshore>%dkm", DIST_MAIN))) |>
  mutate(symbol = factor(symbol, levels = elem_levels),
         cat = factor(cat, levels = CATS),
         basis = factor(basis, levels = BASES),
         reliable = n >= MIN_N) |>
  arrange(symbol, cat, basis, subset) |>
  select(symbol, cat, basis, subset, n, reliable, everything())

# ── 3. Compare: global vs offshore P90 per basis (the normalised shift) ───────
key <- percentiles |> mutate(across(c(symbol, cat, basis), as.character))
g <- key |> filter(subset == "global") |> select(symbol, cat, basis, n_global = n, p90_global = p90)
o <- key |> filter(subset == sprintf("offshore>%dkm", DIST_MAIN)) |>
  select(symbol, cat, basis, n_off = n, p90_off = p90)
compare <- g |> left_join(o, by = c("symbol", "cat", "basis")) |>
  mutate(shift_p90 = round(p90_off / p90_global, 3),
         symbol = factor(symbol, levels = elem_levels),
         cat = factor(cat, levels = CATS), basis = factor(basis, levels = BASES)) |>
  arrange(symbol, cat, basis)

meta <- tibble(bases = paste(BASES, collapse = ","), dist_main_km = DIST_MAIN,
               fines_min_pct = FINES_MIN, min_n = MIN_N)

# ── 4. Write ─────────────────────────────────────────────────────────────────
write_csv(percentiles, file.path(out_dir, "refined_gsnorm_percentiles.csv"))
write_csv(compare,     file.path(out_dir, "refined_gsnorm_compare.csv"))
write_csv(meta,        file.path(out_dir, "refined_gsnorm_meta.csv"))

# ── 5. Console summary ───────────────────────────────────────────────────────
cat("grain-size-normalised background written to", out_dir, "\n\n")
cat("offshore/global P90 shift by basis, bulk, well-covered elements:\n")
compare |> filter(cat == "bulk", n_off >= MIN_N, symbol %in% c("CO","CU","MN","MO","ZN")) |>
  select(symbol, basis, p90_global, p90_off, shift_p90) |>
  pivot_wider(names_from = basis, values_from = c(p90_global, p90_off, shift_p90)) |>
  select(symbol, starts_with("shift_p90")) |> as.data.frame() |> print(row.names = FALSE)
cat("\n(compare these shifts to the raw-value shifts on page 1: Cu 0.40, Zn 0.59)\n")
