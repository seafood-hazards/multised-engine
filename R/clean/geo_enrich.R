library(DBI)
library(RSQLite)
library(readr)
library(dplyr)

# ── Clean stage, geo-enrichment of the site table ────────────────────────────
# Recompute the location attributes of every site with the `seastamp` CLI
# (https://github.com/AIQC-Hub/seastamp, formerly `geoenrich`) and write them
# back into each <source>_clean.sqlite `site`
# table, replacing depth / country / country_code / dist_to_coast / municipality /
# sea_name with consistent, tool-derived values.
#
# Per source: export the site coordinates to TSV, chain the seastamp modules
# (coast -> depth -> sea -> place), read the enriched TSV back, and UPDATE the
# six columns keyed on site_id. Re-run this after any clean rebuild (03), since a
# rebuild regenerates the site table from slim.
#
# Notes on the tool output:
#   dist_to_coast  km (GSHHG full resolution)
#   depth          = -bathymetry (GEBCO is negative below sea level; stored
#                    positive-down). Points GEBCO places on land (bathymetry > 0,
#                    e.g. a coordinate that rounds onto shore) get depth = NULL.
#   sea_name       IHO Sea Areas
#   country        Natural Earth (global)
#   country_code   Natural Earth ISO alpha-3 (NOR, DEU; was alpha-2 before)
#   municipality   GISCO LAU (Europe only, so non-European sites may be NULL)

# ── 0. Config ────────────────────────────────────────────────────────────────
# The tool was renamed geoenrich -> seastamp at 0.9.0 (commands, flags and output
# columns unchanged). No fallback to the old `geoenrich` binary on purpose: it
# stops at 0.8.0, whose default region differs, so silently running it would give
# different distances rather than an error.
BIN <- Sys.which("seastamp")
if (BIN == "") BIN <- "/home/takaya/programs/seastamp/seastamp"
if (!file.exists(BIN)) stop("seastamp not found; install it or set BIN")

# Reference-data dir (external storage). Renamed geoenrich -> seastamp on disk.
GEO       <- "data/seastamp"
COAST     <- file.path(GEO, "gshhg/gshhg-shp-2.3.7/GSHHS_shp/f")
DEPTH     <- file.path(GEO, "gebco/GEBCO_2024_sub_ice_topo.nc")
SEA       <- file.path(GEO, "iho/World_Seas_IHO_v3/World_Seas_IHO_v3.shp")
COUNTRIES <- file.path(GEO, "naturalearth/ne_10m_admin_0_countries.shp")
MUNI      <- file.path(GEO, "gisco/LAU_RG_01M_2021_4326.shp")

work <- "data/geo"
dir.create(work, recursive = TRUE, showWarnings = FALSE)

sources <- c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon")

run <- function(args) {
  status <- system2(BIN, args, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(status, "status")) && attr(status, "status") != 0)
    stop(basename(BIN), " failed:\n", paste(status, collapse = "\n"))
  invisible(status)
}

tsv_opts <- c("--in-format", "tsv", "--out-format", "tsv")

# ── 1. Enrich + update each source ───────────────────────────────────────────
for (stem in sources) {
  con  <- dbConnect(SQLite(), sprintf("data/db/%s_clean.sqlite", stem))
  site <- as_tibble(dbReadTable(con, "site"))

  in_tsv <- file.path(work, sprintf("%s_site.tsv", stem))
  write_tsv(site |> select(site_id, longitude, latitude), in_tsv)

  f1 <- file.path(work, sprintf("%s_1coast.tsv", stem))
  f2 <- file.path(work, sprintf("%s_2depth.tsv", stem))
  f3 <- file.path(work, sprintf("%s_3sea.tsv",   stem))
  f4 <- file.path(work, sprintf("%s_4place.tsv", stem))

  run(c("coast", in_tsv, "--data", COAST, "--unit", "km", tsv_opts, "-o", f1))
  # depth reads GEBCO via HDF5, which is not thread-safe: force one worker or it
  # segfaults on more than a handful of points.
  run(c("depth", f1,     "--data", DEPTH, "-t", "1",      tsv_opts, "-o", f2))
  run(c("sea",   f2,     "--data", SEA,                   tsv_opts, "-o", f3))
  run(c("place", f3, "--countries", COUNTRIES, "--municipalities", MUNI, tsv_opts, "-o", f4))

  enr <- read_tsv(f4, show_col_types = FALSE) |>
    transmute(site_id,
              # positive-down depth; GEBCO land points (bathymetry > 0) -> NULL
              depth         = if_else(bathymetry <= 0, round(-bathymetry, 1), NA_real_),
              country,
              country_code,
              dist_to_coast = round(dist_to_coast, 3),
              municipality,
              sea_name)

  dbWriteTable(con, "_enr", enr, overwrite = TRUE)
  dbExecute(con, "
    UPDATE site SET
      depth         = (SELECT depth         FROM _enr WHERE _enr.site_id = site.site_id),
      country       = (SELECT country       FROM _enr WHERE _enr.site_id = site.site_id),
      country_code  = (SELECT country_code  FROM _enr WHERE _enr.site_id = site.site_id),
      dist_to_coast = (SELECT dist_to_coast FROM _enr WHERE _enr.site_id = site.site_id),
      municipality  = (SELECT municipality  FROM _enr WHERE _enr.site_id = site.site_id),
      sea_name      = (SELECT sea_name      FROM _enr WHERE _enr.site_id = site.site_id)
    WHERE site_id IN (SELECT site_id FROM _enr)")
  dbExecute(con, "DROP TABLE _enr")

  # report coverage (how many NULLs remain per replaced column)
  nulls <- dbGetQuery(con, "
    SELECT SUM(depth IS NULL) depth, SUM(country IS NULL) country,
           SUM(country_code IS NULL) country_code, SUM(dist_to_coast IS NULL) dist_to_coast,
           SUM(municipality IS NULL) municipality, SUM(sea_name IS NULL) sea_name
    FROM site")
  dbDisconnect(con)

  cat(sprintf("%-10s updated %5d sites | NULLs: depth %d, country %d, code %d, coast %d, muni %d, sea %d\n",
              stem, nrow(enr), nulls$depth, nulls$country, nulls$country_code,
              nulls$dist_to_coast, nulls$municipality, nulls$sea_name))
}
