library(DBI)
library(RSQLite)
library(tidyverse)
library(sf)

# ── Distance from each clean site to the nearest aquaculture site ────────────
# Adds `dist_to_aquaculture` (km, great-circle) to the `site` table of every clean
# database. The aquaculture reference (data/db/aquaculture_no.sqlite) is Norway-only,
# so the distance is computed only for sites in Norway (country_code = 'NOR', from
# the geo-enrichment step); every other site is left NULL. The nearest site is
# taken over ALL aquaculture sites, active or closed, since a past farm is a
# historical pressure on the sediment just as a current one is.
#
# Idempotent: re-running resets the column and recomputes.

aqua_db <- "data/db/aquaculture_no.sqlite"
stems   <- c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon")

# aquaculture points (WGS84)
con_a <- dbConnect(SQLite(), aqua_db)
aqua  <- dbReadTable(con_a, "aquaculture") |> as_tibble()
dbDisconnect(con_a)
aqua_sf <- st_as_sf(aqua, coords = c("longitude", "latitude"), crs = 4326)

for (stem in stems) {
  db  <- sprintf("data/db/%s_clean.sqlite", stem)
  con <- dbConnect(SQLite(), db)

  site <- dbReadTable(con, "site") |> as_tibble()

  # (re)create the column, cleared to NULL
  if (!"dist_to_aquaculture" %in% names(site))
    dbExecute(con, "ALTER TABLE site ADD COLUMN dist_to_aquaculture REAL")
  dbExecute(con, "UPDATE site SET dist_to_aquaculture = NULL")

  nor <- site |> filter(country_code == "NOR", !is.na(latitude), !is.na(longitude))

  if (nrow(nor) > 0) {
    nor_sf <- st_as_sf(nor, coords = c("longitude", "latitude"), crs = 4326)
    idx    <- st_nearest_feature(nor_sf, aqua_sf)
    d_km   <- as.numeric(st_distance(nor_sf, aqua_sf[idx, ], by_element = TRUE)) / 1000

    upd <- tibble(site_id = nor$site_id, dist = round(d_km, 3))
    dbWriteTable(con, "tmp_aqua_dist", as.data.frame(upd), overwrite = TRUE)
    dbExecute(con, "UPDATE site SET dist_to_aquaculture =
                      (SELECT dist FROM tmp_aqua_dist t WHERE t.site_id = site.site_id)
                    WHERE site_id IN (SELECT site_id FROM tmp_aqua_dist)")
    dbExecute(con, "DROP TABLE tmp_aqua_dist")
  }

  n_set <- dbGetQuery(con, "SELECT COUNT(*) n FROM site WHERE dist_to_aquaculture IS NOT NULL")$n
  cat(sprintf("%-10s %5d Norway sites set (of %d)\n", stem, n_set, nrow(site)))
  dbDisconnect(con)
}
