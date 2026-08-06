# ── Clean step 4: geo-enrich the site table ──────────────────────────────────
# Recomputes the location attributes of every site with seastamp and writes them
# back into the clean `site` table, replacing depth / country / country_code /
# dist_to_coast / municipality / sea_name with consistent, tool-derived values.
#
# This is what makes the five sources comparable: a site off the Norwegian coast
# gets the same depth, sea and distance-to-coast whether it came from Mareano or
# ICES-DOME, rather than each source's own reported figure.
#
# Re-run after any clean rebuild (step 1), since a rebuild regenerates the site
# table from slim and restores the source's own values.

clean_geo_enrich <- function(source, db_dir = multised_db_dir(),
                             seastamp_dir = multised_seastamp_dir(),
                             region = "auto", verbose = TRUE) {
  check_source(source)

  con <- multised_con(clean_db_path(source, db_dir))
  on.exit(dbDisconnect(con), add = TRUE)
  site <- as_tibble(dbReadTable(con, "site"))

  enr <- seastamp_enrich(site, id_col = "site_id",
                         seastamp_dir = seastamp_dir, region = region, verbose = verbose)

  dbWriteTable(con, "_enr", as.data.frame(enr), overwrite = TRUE)
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

  if (verbose) {
    cat(sprintf("%-10s updated %5d sites | NULLs: depth %d, country %d, code %d, coast %d, muni %d, sea %d\n",
                source, nrow(enr), nulls$depth, nulls$country, nulls$country_code,
                nulls$dist_to_coast, nulls$municipality, nulls$sea_name))
  }
  invisible(list(n_sites = nrow(enr), nulls = nulls))
}
