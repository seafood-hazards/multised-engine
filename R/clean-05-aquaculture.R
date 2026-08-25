# ── Clean step 5: distance to the nearest aquaculture site ───────────────────
# Adds `dist_to_aquaculture` (km, great-circle) to the clean `site` table, and
# alongside it the nearest FISH FARM specifically: `dist_to_fish_farm`,
# `fish_farm_mtb_t` and `fish_farm_band`. The
# aquaculture reference is Norway-only, so the distance is computed only for
# sites in Norway (`country_code = 'NOR'`, which step 4 sets); every other site
# is left NULL.
#
# The nearest site is taken over ALL aquaculture sites, active or closed, since a
# past farm is a historical pressure on the sediment just as a current one is.
#
# `dist_to_aquaculture` keeps its meaning, the nearest aquaculture site of any
# kind: a mussel raft is aquaculture. The fish-farm columns are additive, because
# a fish farm is the pressure the trace-element work is about (feed, and the
# copper in net antifouling) and a 780 t farm and a 19,000 t farm at the same
# distance are not the same pressure. `fish_farm` and `size_band` are set in the
# aquaculture build; MTB is in tonnes, and one standard concession is 780 t.
#
# Runs after step 4 because it keys on the country code that step assigns, and
# after step 1 because a rebuild regenerates `site` from slim and drops the
# column. Idempotent: re-running resets the column and recomputes.
#
# The original looped over all five sources at once. Per-source fits the step
# registry, and means a single source can be redone without touching the others.

clean_aquaculture <- function(source, db_dir = multised_db_dir(),
                              verbose = TRUE) {
  check_source(source)
  require_suggested("sf", "The aquaculture distance step")

  aqua_db <- aquaculture_db_path(db_dir)
  if (!file.exists(aqua_db)) {
    stop("The aquaculture reference database is not in ", db_dir,
         ".\nBuild it first with create_db(\"aquaculture\").", call. = FALSE)
  }

  con_a <- multised_con(aqua_db)
  aqua <- as_tibble(dbReadTable(con_a, "aquaculture"))
  dbDisconnect(con_a)
  aqua_sf <- sf::st_as_sf(aqua, coords = c("longitude", "latitude"), crs = 4326)

  con <- multised_con(clean_db_path(source, db_dir))
  on.exit(dbDisconnect(con), add = TRUE)
  site <- as_tibble(dbReadTable(con, "site"))

  if (!"country_code" %in% names(site)) {
    stop("`site` has no country_code, so Norwegian sites cannot be selected. ",
         "Run clean step 4 (geo_enrich) first.", call. = FALSE)
  }

  # (re)create the columns, cleared to NULL
  new_cols <- c(dist_to_aquaculture = "REAL", dist_to_fish_farm = "REAL",
                fish_farm_mtb_t = "REAL", fish_farm_band = "TEXT")
  for (col in names(new_cols)) {
    if (!col %in% names(site)) {
      dbExecute(con, sprintf("ALTER TABLE site ADD COLUMN %s %s", col, new_cols[[col]]))
    }
    dbExecute(con, sprintf("UPDATE site SET %s = NULL", col))
  }

  # `NOR` is seastamp's ISO alpha-3; a site table that still carries the source's
  # own two-letter codes has not been geo-enriched, and would silently score zero
  # Norwegian sites rather than fail.
  if (!any(site$country_code == "NOR", na.rm = TRUE) &&
      any(nchar(site$country_code) == 2L, na.rm = TRUE)) {
    stop("`site.country_code` holds two-letter codes, so clean step 4 ",
         "(geo_enrich) has not run for ", source, ". Distances would be ",
         "computed for no sites at all.", call. = FALSE)
  }

  nor <- site |>
    filter(country_code == "NOR", !is.na(latitude), !is.na(longitude))

  if (nrow(nor) > 0) {
    nor_sf <- sf::st_as_sf(nor, coords = c("longitude", "latitude"), crs = 4326)

    nearest_km <- function(target_sf) {
      idx <- sf::st_nearest_feature(nor_sf, target_sf)
      list(idx = idx,
           km = round(as.numeric(sf::st_distance(nor_sf, target_sf[idx, ],
                                                 by_element = TRUE)) / 1000, 3))
    }

    all_n <- nearest_km(aqua_sf)
    upd <- tibble::tibble(site_id = nor$site_id, dist = all_n$km,
                          ff_dist = NA_real_, ff_mtb = NA_real_,
                          ff_band = NA_character_)

    # the fish-farm subset can be empty in a cut-down reference, so guard it
    farm_sf <- aqua_sf[!is.na(aqua_sf$fish_farm) & aqua_sf$fish_farm == 1L, ]
    if (nrow(farm_sf) > 0) {
      ff <- nearest_km(farm_sf)
      upd$ff_dist <- ff$km
      upd$ff_mtb  <- farm_sf$capacity_tonnes[ff$idx]
      upd$ff_band <- farm_sf$size_band[ff$idx]
    }

    dbWriteTable(con, "tmp_aqua_dist", as.data.frame(upd), overwrite = TRUE)
    dbExecute(con, "UPDATE site SET
        dist_to_aquaculture = (SELECT dist    FROM tmp_aqua_dist t WHERE t.site_id = site.site_id),
        dist_to_fish_farm   = (SELECT ff_dist FROM tmp_aqua_dist t WHERE t.site_id = site.site_id),
        fish_farm_mtb_t     = (SELECT ff_mtb  FROM tmp_aqua_dist t WHERE t.site_id = site.site_id),
        fish_farm_band      = (SELECT ff_band FROM tmp_aqua_dist t WHERE t.site_id = site.site_id)
      WHERE site_id IN (SELECT site_id FROM tmp_aqua_dist)")
    dbExecute(con, "DROP TABLE tmp_aqua_dist")
  }

  n_set <- dbGetQuery(
    con, "SELECT COUNT(*) n FROM site WHERE dist_to_aquaculture IS NOT NULL")$n
  n_ff <- dbGetQuery(
    con, "SELECT COUNT(*) n FROM site WHERE fish_farm_band IS NOT NULL")$n
  out <- data.frame(source = source, norway_sites = n_set, sites = nrow(site),
                    fish_farm_banded = n_ff)
  if (verbose) {
    cat(sprintf("%-10s %5d Norway sites set (of %d), %d with a fish-farm band\n",
                source, n_set, nrow(site), n_ff))
  }
  invisible(out)
}
