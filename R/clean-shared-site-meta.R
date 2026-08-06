# ── Clean stage shared helper: site_meta ─────────────────────────────────────────
# Moved verbatim from R/clean/_shared/site_meta.R, which the per-source clean scripts
# source()d. These are pure definitions, so nothing needed changing.

# ── Clean stage: shared site helpers ─────────────────────────────────────────
# Enforces a common `site` column set/order across sources and consumes the slim
# `area_flag`.
#
# `standardise_site()` (Harmonise, step 01) guarantees `depth` (station / water
# depth, m; only Mareano carries it natively) and a stable order, keeping
# `area_flag` so the Clean step can act on it. Values for the non-key columns are
# produced upstream (geocoding / bathymetry tools); a source lacking `depth` gets
# NULL until those tools populate it.
#
# `consume_area_flag()` (Clean, step 02) drops sites flagged "outside_europe" and
# their linked event / subsample / measurement rows (cascade, no orphans) and
# removes the `area_flag` column, so the final clean `site` table has no flag.
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

consume_area_flag <- function(site, event, subsample, measurement) {
  out_ids <- if ("area_flag" %in% names(site))
    site$site_id[dplyr::coalesce(site$area_flag == "outside_europe", FALSE)] else integer(0)
  bad_ev <- event$event_id[event$site_id %in% out_ids]
  bad_ss <- subsample$subsample_id[subsample$event_id %in% bad_ev]
  keep_m <- !measurement$subsample_id %in% bad_ss
  list(
    site        = dplyr::select(site[!site$site_id %in% out_ids, , drop = FALSE],
                                -dplyr::any_of("area_flag")),
    event       = event[!event$event_id %in% bad_ev, , drop = FALSE],
    subsample   = subsample[!subsample$subsample_id %in% bad_ss, , drop = FALSE],
    measurement = measurement[keep_m, , drop = FALSE],
    n_sites        = length(out_ids),
    n_events       = length(bad_ev),
    n_subsamples   = length(bad_ss),
    n_measurements = sum(!keep_m))
}
