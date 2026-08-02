library(DBI)
library(RSQLite)
library(tidyverse)
library(sf)

# ── Refine stage 4: aquaculture table + site.aqua_id link ────────────────────
# Import the Norway aquaculture reference (aquaculture_no.sqlite) into the refined DB
# as the `aquaculture` table, and add `aqua_id` to `site`: the id of the NEAREST
# aquaculture site, so the existing `dist_to_aquaculture` (km) now has an explicit
# link to which farm it refers to. Norway-only (country_code = 'NOR'); NULL elsewhere.
#
# Reproduces exactly the distance step that set dist_to_aquaculture
# (R/aquaculture/02_site_distance.R): nearest over ALL aquaculture (active or closed,
# a past farm is a historical pressure), WGS84, great-circle km. The nearest-feature
# index gives the aqua_id; the recomputed distance is cross-checked against the stored
# dist_to_aquaculture to confirm it is the same site. Reads/writes multised_refined.sqlite.

refined_db <- "./data/db/multised_refined.sqlite"
aqua_db    <- "./data/db/aquaculture_no.sqlite"

# ── 1. Aquaculture reference -> refined DB ───────────────────────────────────
acon <- dbConnect(SQLite(), aqua_db)
aqua <- as_tibble(dbReadTable(acon, "aquaculture"))
dbDisconnect(acon)

con <- dbConnect(SQLite(), refined_db)
dbWriteTable(con, "aquaculture", as.data.frame(aqua), overwrite = TRUE)
site <- as_tibble(dbReadTable(con, "site"))

# ── 2. Nearest aquaculture aqua_id for each Norway site ──────────────────────
aqua_sf <- st_as_sf(aqua, coords = c("longitude", "latitude"), crs = 4326)
nor <- site |> filter(country_code == "NOR", !is.na(latitude), !is.na(longitude))

nor_sf <- st_as_sf(nor, coords = c("longitude", "latitude"), crs = 4326)
idx    <- st_nearest_feature(nor_sf, aqua_sf)
d_km   <- as.numeric(st_distance(nor_sf, aqua_sf[idx, ], by_element = TRUE)) / 1000

link <- tibble(site_id = nor$site_id,
               aqua_id = aqua$aqua_id[idx],
               dist_chk = round(d_km, 3))

# ── 3. Add aqua_id to site (NULL where not computed) ─────────────────────────
site_out <- site |>
  left_join(link |> select(site_id, aqua_id), by = "site_id") |>
  relocate(aqua_id, .after = dist_to_aquaculture)
dbWriteTable(con, "site", as.data.frame(site_out), overwrite = TRUE)
dbDisconnect(con)

# ── 4. Cross-check: recomputed distance == stored dist_to_aquaculture ─────────
chk <- link |> left_join(site |> select(site_id, dist_to_aquaculture), by = "site_id") |>
  mutate(diff = abs(dist_chk - dist_to_aquaculture))
max_diff  <- max(chk$diff, na.rm = TRUE)
pct_exact <- 100 * mean(chk$diff < 1e-6, na.rm = TRUE)

# ── 5. Sanity summary ────────────────────────────────────────────────────────
cat("aquaculture imported (", nrow(aqua), "rows ) and site.aqua_id set in", refined_db, "\n\n")
cat(sprintf("site rows: %d | aqua_id set: %d | Norway sites: %d\n",
            nrow(site_out), sum(!is.na(site_out$aqua_id)), nrow(nor)))
cat(sprintf("cross-check vs stored dist_to_aquaculture: max diff %.4f km, %.1f%% exact\n",
            max_diff, pct_exact))
cat("sample links (site -> aqua_id, km):\n")
chk |> select(site_id, aqua_id, dist_chk, dist_to_aquaculture) |> head(5) |>
  as.data.frame() |> print(row.names = FALSE)
