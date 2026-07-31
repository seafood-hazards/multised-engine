library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, data-shape summary of the MERGED database ────────────────
# Before running the clean-style analyses on the merged database, take stock of
# what is actually there: how many measurements each element carries, split by
# the factors that decide which analyses are possible. The factors are:
#
#   (1) fraction        bulk (whole sample) / sieved <63 um / sieved <20 um
#                       (measurement.frac_class + sieve_um_std)
#   (2) grain size      whether the subsample carries grain-size composition
#                       (subsample.comp_exist)          -- bulk only, see note
#   (3) normalisers     whether Fe and/or Al are available in the subsample
#                       (subsample.fe_exist / al_exist) -- bulk only, see note
#   (4) organic carbon  whether CORG/TOC is available   (subsample.org_exist)
#   (5) layering        single-layer grab/core vs multi-layer/multi-core event
#                       (event.n_layers == 1 vs > 1)
#
# Grain-size correction and Fe/Al normalisation are only meaningful on BULK
# samples, so factors (2)-(4) are tabulated for bulk only; sieved fractions are
# split by layering alone.
#
# Availability (factors 2-4) is read from the pipeline's subsample-level exist
# flags (slim step 6). They mark that the measurand exists somewhere in that
# subsample; they are fraction-agnostic, so a bulk row with fe_exist = 1 has Fe
# in the subsample but not necessarily in the bulk fraction. Good enough for
# planning which analyses are worth attempting; the analysis scripts themselves
# match fraction exactly.
#
# Outputs -> data/analysis/merged_summary/ (gitignored), uploaded to the
# multised-merged release and read by the "Data Categories" page:
#   merged_coverage_fraction.csv   element x fraction, measurement counts
#   merged_bulk_factors.csv        bulk element x (grain/Fe/Al/org) availability
#   merged_layering.csv            element x fraction x single/multi layering

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"

# element display order: the 7 targets, then the 2 normalisers, then organic C.
ELEM_ORDER <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN",  # target
                "FE", "AL",                                # reference
                "CORG", "TOC", "TOC63")                    # organic

out_dir <- "data/analysis/merged_summary"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

con <- dbConnect(SQLite(), db_path)

# ── 1. One row per measurement with its factors attached ─────────────────────
# join measurement -> subsample (exist flags) -> event (layering) -> element.
df <- dbGetQuery(con, "
  SELECT m.measurement_id,
         m.symbol,
         e.name        AS element_name,
         e.category    AS category,
         m.frac_class,
         m.sieve_um_std,
         s.comp_exist, s.fe_exist, s.al_exist, s.org_exist,
         ev.n_layers
  FROM measurement m
    JOIN element   e  ON e.symbol       = m.symbol
    JOIN subsample s  ON s.subsample_id = m.subsample_id
    JOIN event     ev ON ev.event_id    = s.event_id
  WHERE e.category IN ('target', 'reference', 'organic')
") |>
  as_tibble() |>
  mutate(
    fraction = case_when(
      frac_class == "bulk"                              ~ "bulk",
      frac_class == "sieved" & sieve_um_std == 63       ~ "sieved63",
      frac_class == "sieved" & sieve_um_std == 20       ~ "sieved20",
      frac_class == "sieved"                            ~ "other",
      TRUE                                              ~ "other"),
    layering = case_when(
      n_layers == 1 ~ "single",
      n_layers >  1 ~ "multi",
      TRUE          ~ NA_character_))

dbDisconnect(con)

# keep a stable element ordering / labelling helper
elem_levels <- ELEM_ORDER[ELEM_ORDER %in% unique(df$symbol)]
order_elems <- function(x) {
  x |>
    mutate(symbol = factor(symbol, levels = elem_levels),
           category = factor(category,
                             levels = c("target", "reference", "organic"))) |>
    arrange(category, symbol) |>
    mutate(symbol = as.character(symbol))
}

# ── 2. Coverage by fraction (measurements per element x fraction) ────────────
coverage <- df |>
  count(category, symbol, element_name, fraction) |>
  pivot_wider(names_from = fraction, values_from = n, values_fill = 0) |>
  # guarantee every fraction column exists even if empty
  { \(d) { for (f in c("bulk", "sieved63", "sieved20", "other"))
             if (!f %in% names(d)) d[[f]] <- 0L
           d } }() |>
  mutate(total = bulk + sieved63 + sieved20 + other) |>
  select(category, symbol, element_name,
         bulk, sieved63, sieved20, other, total) |>
  order_elems()

write_csv(coverage, file.path(out_dir, "merged_coverage_fraction.csv"))

# ── 3. Bulk sub-categories: availability of grain size / Fe / Al / organic C ──
# counts are of BULK measurements whose subsample carries each measurand.
bulk_factors <- df |>
  filter(fraction == "bulk") |>
  group_by(category, symbol, element_name) |>
  summarise(
    bulk      = n(),
    grain     = sum(comp_exist == 1, na.rm = TRUE),
    fe        = sum(fe_exist   == 1, na.rm = TRUE),
    al        = sum(al_exist   == 1, na.rm = TRUE),
    fe_or_al  = sum(fe_exist == 1 | al_exist == 1, na.rm = TRUE),
    org       = sum(org_exist  == 1, na.rm = TRUE),
    .groups   = "drop") |>
  order_elems()

write_csv(bulk_factors, file.path(out_dir, "merged_bulk_factors.csv"))

# ── 4. Layering: single vs multi-layer/core, by fraction ─────────────────────
layering <- df |>
  filter(fraction %in% c("bulk", "sieved63", "sieved20"),
         !is.na(layering)) |>
  count(category, symbol, element_name, fraction, layering) |>
  mutate(col = paste(fraction, layering, sep = "_")) |>
  select(-fraction, -layering) |>
  pivot_wider(names_from = col, values_from = n, values_fill = 0) |>
  { \(d) { for (c in c("bulk_single", "bulk_multi",
                       "sieved63_single", "sieved63_multi",
                       "sieved20_single", "sieved20_multi"))
             if (!c %in% names(d)) d[[c]] <- 0L
           d } }() |>
  select(category, symbol, element_name,
         bulk_single, bulk_multi,
         sieved63_single, sieved63_multi,
         sieved20_single, sieved20_multi) |>
  order_elems()

write_csv(layering, file.path(out_dir, "merged_layering.csv"))

# ── 5. Console recap ─────────────────────────────────────────────────────────
message("merged data summary written to ", out_dir, ":")
message("  merged_coverage_fraction.csv  ", nrow(coverage), " elements")
message("  merged_bulk_factors.csv       ", nrow(bulk_factors), " elements")
message("  merged_layering.csv           ", nrow(layering), " elements")
message("  total measurements summarised: ", nrow(df))
