# ── Clean step 5: distance to the nearest aquaculture site ───────────────────
# Adds `dist_to_aquaculture` (km, great-circle) to the clean `site` table. The
# aquaculture reference is Norway-only, so the distance is computed only for
# sites in Norway (`country_code = 'NOR'`, which step 4 sets); every other site
# is left NULL.
#
# The nearest site is taken over ALL aquaculture sites, active or closed, since a
# past farm is a historical pressure on the sediment just as a current one is.
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

  # (re)create the column, cleared to NULL
  if (!"dist_to_aquaculture" %in% names(site)) {
    dbExecute(con, "ALTER TABLE site ADD COLUMN dist_to_aquaculture REAL")
  }
  dbExecute(con, "UPDATE site SET dist_to_aquaculture = NULL")

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
    idx <- sf::st_nearest_feature(nor_sf, aqua_sf)
    d_km <- as.numeric(sf::st_distance(nor_sf, aqua_sf[idx, ],
                                       by_element = TRUE)) / 1000

    upd <- tibble::tibble(site_id = nor$site_id, dist = round(d_km, 3))
    dbWriteTable(con, "tmp_aqua_dist", as.data.frame(upd), overwrite = TRUE)
    dbExecute(con, "UPDATE site SET dist_to_aquaculture =
                      (SELECT dist FROM tmp_aqua_dist t WHERE t.site_id = site.site_id)
                    WHERE site_id IN (SELECT site_id FROM tmp_aqua_dist)")
    dbExecute(con, "DROP TABLE tmp_aqua_dist")
  }

  n_set <- dbGetQuery(
    con, "SELECT COUNT(*) n FROM site WHERE dist_to_aquaculture IS NOT NULL")$n
  out <- data.frame(source = source, norway_sites = n_set, sites = nrow(site))
  if (verbose) {
    cat(sprintf("%-10s %5d Norway sites set (of %d)\n", source, n_set, nrow(site)))
  }
  invisible(out)
}
