# ── Clean stage: shared site column set ──────────────────────────────────────
# Enforces a common `site` column set and order across sources. The site tables
# are already near-identical; this guarantees `depth` (station / water depth, m)
# exists for every source (only Mareano carries it natively) and a stable order.
# Values are produced upstream (the geocoding / bathymetry tools) and are not set
# here; a source that lacks `depth` gets NULL until those tools populate it.
#
# Note: `site.depth` is the water depth at the station, distinct from the sediment
# core depth in `subsample.depth_from` / `depth_to`.

SITE_COLS <- c(
  "site_id", "latitude", "longitude", "depth", "country", "country_code",
  "dist_to_coast", "municipality", "sea_name", "area_flag")

standardise_site <- function(site) {
  s <- site
  if (!"depth" %in% names(s)) s$depth <- NA_real_
  for (col in SITE_COLS) if (!col %in% names(s)) s[[col]] <- NA
  dplyr::select(s, dplyr::all_of(SITE_COLS))
}
