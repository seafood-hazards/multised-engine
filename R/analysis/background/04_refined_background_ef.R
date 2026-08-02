library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, enrichment factor (REFINED database) ─────────────────────
# The fourth background page, turning the background into a per-sample classifier. The
# enrichment factor is
#
#     EF = (metal / Al)_sample  /  (metal / Al)_background
#
# relative to a LOCAL, data-driven background: the offshore (dist_to_coast > DIST_BG km)
# MEDIAN of metal / Al, per element and fraction. This follows EFSA's steer to use a
# local background and to AVOID literature crustal values (Turekian & Wedepohl). Al is
# the normaliser (the grain-size carrier), so EF already controls for grain size.
#
# EF < 1 is read as adequate / at-or-below background (an EFSA convention); classes
# 1-2 / 2-5 / >5 mark rising enrichment RELATIVE TO THE LOCAL OFFSHORE BACKGROUND (not
# the crust, so the numbers are not the usual Sutherland scale). We report, per element
# x fraction: the background reference value, the EF distribution and class shares, and
# EF across the distance-to-aquaculture bands (does the near-cage enrichment survive
# grain-size normalisation). Fractions bulk/sieved63/sieved20; outliers dropped.
#
# Outputs -> data/analysis/background/ (gitignored):
#   refined_ef_background.csv  per element x fraction: the (metal/Al) background reference
#   refined_ef_dist.csv        EF distribution + class shares (incl. % EF<1, pristine)
#   refined_ef_pressure.csv    median EF by distance-to-aquaculture band (Norway)
#   refined_ef_meta.csv        one-row config

db_path <- "./data/db/multised_refined.sqlite"

CATS      <- c("bulk", "sieved63", "sieved20")
DIST_BG   <- 10          # km: offshore subset defining the background (metal/Al) median
AQ_BREAKS <- c(-Inf, 1, 5, 20, Inf)
AQ_LABELS <- c("<1km", "1-5km", "5-20km", ">20km")
MIN_N     <- 30L
elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

out_dir <- "data/analysis/background"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Pull metal/Al + distances ─────────────────────────────────────────────
con <- dbConnect(SQLite(), db_path)
m <- as_tibble(dbGetQuery(con, "
  SELECT me.symbol, me.frac_class, me.sieve_um_std, me.ratio_al,
         si.dist_to_coast, si.dist_to_aquaculture
  FROM measurement me
  JOIN subsample s ON s.subsample_id = me.subsample_id
  JOIN event e     ON e.event_id     = s.event_id
  JOIN site  si    ON si.site_id     = e.site_id
  WHERE me.outlier_flag IS NULL AND me.ratio_al IS NOT NULL AND me.ratio_al > 0
")) |>
  mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                         sieve_um_std == 63 ~ "sieved63",
                         sieve_um_std == 20 ~ "sieved20",
                         TRUE ~ NA_character_)) |>
  filter(cat %in% CATS)
dbDisconnect(con)

# ── 2. Local background reference: offshore median of metal/Al ───────────────
background <- m |>
  filter(dist_to_coast > DIST_BG) |>
  group_by(symbol, cat) |>
  summarise(n_bg = n(), bg_ratio_al = median(ratio_al), .groups = "drop") |>
  filter(n_bg >= MIN_N)

# ── 3. EF per row ────────────────────────────────────────────────────────────
ef <- m |>
  inner_join(background |> select(symbol, cat, bg_ratio_al), by = c("symbol", "cat")) |>
  mutate(EF = ratio_al / bg_ratio_al,
         ef_class = cut(EF, c(-Inf, 1, 2, 5, Inf),
                        labels = c("<1", "1-2", "2-5", ">5")))

# ── 4. EF distribution + class shares per element x fraction ─────────────────
ef_dist <- ef |>
  group_by(symbol, cat) |>
  summarise(n = n(),
            ef_p50 = signif(median(EF), 3),
            ef_p90 = signif(quantile(EF, .9, names = FALSE), 3),
            pct_lt1 = round(100 * mean(EF < 1)),
            pct_1_2 = round(100 * mean(EF >= 1 & EF < 2)),
            pct_2_5 = round(100 * mean(EF >= 2 & EF < 5)),
            pct_gt5 = round(100 * mean(EF >= 5)),
            .groups = "drop") |>
  mutate(symbol = factor(symbol, levels = elem_levels),
         cat = factor(cat, levels = CATS), reliable = n >= MIN_N) |>
  arrange(symbol, cat)

# ── 5. EF vs distance to aquaculture (Norway) ────────────────────────────────
ef_pressure <- ef |>
  filter(!is.na(dist_to_aquaculture)) |>
  mutate(aq_bin = cut(dist_to_aquaculture, AQ_BREAKS, labels = AQ_LABELS)) |>
  group_by(symbol, cat, aq_bin) |>
  summarise(n = n(), ef_p50 = signif(median(EF), 3), .groups = "drop") |>
  filter(n >= MIN_N) |>
  mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
  arrange(symbol, cat, aq_bin)

bg_out <- background |>
  mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS),
         bg_ratio_al = signif(bg_ratio_al, 4)) |>
  arrange(symbol, cat)

meta <- tibble(normaliser = "Al", background = sprintf("offshore >%d km median of metal/Al", DIST_BG),
               ef_lt1 = "adequate / at-or-below local background", min_n = MIN_N,
               note = "EF relative to LOCAL offshore background, not crustal (Turekian/Wedepohl avoided)")

# ── 6. Write ─────────────────────────────────────────────────────────────────
write_csv(bg_out,      file.path(out_dir, "refined_ef_background.csv"))
write_csv(ef_dist,     file.path(out_dir, "refined_ef_dist.csv"))
write_csv(ef_pressure, file.path(out_dir, "refined_ef_pressure.csv"))
write_csv(meta,        file.path(out_dir, "refined_ef_meta.csv"))

# ── 7. Console summary ───────────────────────────────────────────────────────
cat("enrichment-factor analysis written to", out_dir, "\n\n")
cat("EF distribution (bulk): median, P90, and % of samples adequate (EF<1):\n")
ef_dist |> filter(cat == "bulk", reliable) |>
  select(symbol, n, ef_p50, ef_p90, pct_lt1, pct_gt5) |> as.data.frame() |> print(row.names = FALSE)
cat("\nmedian EF by distance to aquaculture (bulk; does near-cage enrichment survive Al-normalisation?):\n")
ef_pressure |> filter(cat == "bulk") |>
  select(symbol, aq_bin, ef_p50) |> pivot_wider(names_from = aq_bin, values_from = ef_p50) |>
  as.data.frame() |> print(row.names = FALSE)
