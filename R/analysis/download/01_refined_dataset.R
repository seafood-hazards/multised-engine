library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, downloadable flat dataset (REFINED database) ──────────────
# A single denormalised table for external users who want to try their own
# background / enrichment methods, without needing the full relational database.
# It keeps only the values those analyses actually need: location, sampling
# metadata (source, year, depth), the target concentration, the Fe/Al/organic
# normalisers and grain-size fines, and the two distances (coast, aquaculture).
# Everything else (surrogate keys, provenance, uncertainty, method detail) is
# dropped. One row per target measurement.
#
# Output -> data/analysis/download/ (gitignored):
#   multised_refined_dataset.tsv.gz   the flat dataset (tab-separated, gzip)
#   refined_dataset_dictionary.csv    column -> description (drives the site page)

db_path <- "./data/db/multised_refined.sqlite"
out_dir <- "data/analysis/download"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Pull and denormalise ──────────────────────────────────────────────────
con <- dbConnect(SQLite(), db_path)
df <- as_tibble(dbGetQuery(con, "
  SELECT m.source                    AS source,
         si.latitude                 AS latitude,
         si.longitude                AS longitude,
         e.year                      AS year,
         sub.depth_from              AS depth_from_cm,
         sub.depth_to                AS depth_to_cm,
         m.symbol                    AS element,
         m.frac_class                AS frac_class,
         m.sieve_um_std              AS sieve_um_std,
         m.value_std                 AS value_mgkg,
         nz.al                       AS al_mgkg,
         nz.fe                       AS fe_mgkg,
         nz.corg                     AS corg_mgkg,
         sub.fines_lt63              AS fines_pct,
         si.dist_to_coast            AS dist_to_coast_km,
         si.dist_to_aquaculture      AS dist_to_aquaculture_km,
         m.outlier_flag              AS outlier_flag
  FROM measurement m
    JOIN subsample sub ON sub.subsample_id = m.subsample_id
    JOIN event e       ON e.event_id       = sub.event_id
    JOIN site si       ON si.site_id       = e.site_id
    LEFT JOIN normaliser nz
           ON nz.subsample_id = m.subsample_id
          AND nz.frac_class   = m.frac_class")) |>
  # a single readable fraction token (bulk / sieved63 / sieved20 / ...)
  mutate(fraction = if_else(frac_class == "bulk", "bulk",
                            paste0("sieved", as.integer(sieve_um_std)))) |>
  select(source, latitude, longitude, year, depth_from_cm, depth_to_cm,
         element, fraction, value_mgkg, al_mgkg, fe_mgkg, corg_mgkg,
         fines_pct, dist_to_coast_km, dist_to_aquaculture_km, outlier_flag) |>
  arrange(element, fraction, source, latitude, longitude)
dbDisconnect(con)

# ── 2. Write the gzipped TSV ──────────────────────────────────────────────────
tsv_path <- file.path(out_dir, "multised_refined_dataset.tsv.gz")
write_tsv(df, tsv_path, na = "")

# ── 3. Column dictionary (drives the Dataset Download page) ───────────────────
dict <- tribble(
  ~column,                   ~unit,        ~description,
  "source",                  "",           "Original data source the measurement came from (Mareano, Vannmiljo, ICES-DOME, MUDAB, 4Demon).",
  "latitude",                "deg",        "Site latitude, decimal degrees (WGS84), rounded to 3 dp.",
  "longitude",               "deg",        "Site longitude, decimal degrees (WGS84), rounded to 3 dp.",
  "year",                    "",           "Sampling year.",
  "depth_from_cm",           "cm",         "Top of the sediment layer sampled (0 = surface).",
  "depth_to_cm",             "cm",         "Bottom of the sediment layer sampled.",
  "element",                 "",           "Target element symbol: CO, CU, I, MN, MO, SE, ZN.",
  "fraction",                "",           "Sediment fraction: bulk (whole sample) or sieved<n> (< n micrometre sieve cutoff, e.g. sieved63, sieved20).",
  "value_mgkg",              "mg/kg",      "Standardised element concentration (dry weight), the value all analyses use.",
  "al_mgkg",                 "mg/kg",      "Aluminium concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
  "fe_mgkg",                 "mg/kg",      "Iron concentration for the same subsample and fraction (grain-size normaliser); empty if not measured.",
  "corg_mgkg",               "mg/kg",      "Organic carbon concentration for the same subsample and fraction (organic normaliser); empty if not measured.",
  "fines_pct",               "%",          "Percentage of material finer than 63 micrometre (the mud fraction, clay + silt); empty if no grain size.",
  "dist_to_coast_km",        "km",         "Great-circle distance from the site to the nearest coastline.",
  "dist_to_aquaculture_km",  "km",         "Distance to the nearest marine aquaculture farm (Norway only; empty elsewhere).",
  "outlier_flag",            "",           "Distributional outlier marker (high / low); empty = kept. The analyses exclude flagged rows."
)
write_csv(dict, file.path(out_dir, "refined_dataset_dictionary.csv"))

# ── 4. Console summary ────────────────────────────────────────────────────────
cat("flat dataset written to", tsv_path, "\n")
cat("rows:", nrow(df), " columns:", ncol(df), "\n")
cat("size:", round(file.size(tsv_path) / 1024^2, 2), "MB\n\n")
df |> count(element, fraction) |> pivot_wider(names_from = fraction, values_from = n, values_fill = 0) |>
  as.data.frame() |> print(row.names = FALSE)
