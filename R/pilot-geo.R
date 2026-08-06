# ── Pilot geo-enrichment ─────────────────────────────────────────────────────
# Adds dist_to_coast / est_country / country_code / municipality / sea_name to a
# source's station frame.
#
# Replaces the twenty `04_*` scripts (four per source), which reimplemented in R
# (sf + rnaturalearth + giscoR) the same job the clean stage already did with the
# seastamp CLI. Both now go through seastamp_enrich(), so the pipeline has one
# location-annotation path and one set of reference data.
#
# NOTE: this is a deliberate behaviour change, not a like-for-like conversion.
# The old sf implementation and seastamp use the same reference datasets but not
# the same code, so the values differ in detail. They are also transient: the
# clean stage recomputes all of them with seastamp anyway
# (clean_geo_enrich()), so routing pilot through the same tool makes the pilot
# values agree with the ones that survive instead of disagreeing with them.
#
# The pilot column names differ from the clean ones, and not uniformly: Mareano
# and Vannmiljo call the nearest country `country`, while ICES-DOME, MUDAB and
# 4Demon call it `est_country`. That is carried in the spec rather than assumed.

# Which frame carries the stations for each source, and its coordinate columns.
pilot_geo_spec <- function(source) {
  switch(
    source,
    "mareano"   = list(frame = "df_core",    lon = "dde", lat = "ddn",
                       country_col = "country"),
    "vannmiljo" = list(frame = "df_site",    lon = "lon", lat = "lat",
                       country_col = "country"),
    "ices-dome" = list(frame = "df_site",    lon = "longitude", lat = "latitude",
                       country_col = "est_country"),
    "mudab"     = list(frame = "df_survey",
                       lon = "station_longitude", lat = "station_latitude",
                       country_col = "est_country"),
    "4demon"    = list(frame = "df_station", lon = "longitude", lat = "latitude",
                       country_col = "est_country"),
    stop("No geo spec for source ", sQuote(source), call. = FALSE)
  )
}

# Annotate a pilot station frame in place, joining on its coordinate columns.
#
# `df` needs no id column: seastamp is run over the frame's DISTINCT coordinates
# (as the original scripts did) and the result is joined back on longitude /
# latitude, so repeated stations at one position share a single lookup.
pilot_geo_enrich <- function(df, lon_col, lat_col,
                             country_col = "est_country",
                             seastamp_dir = multised_seastamp_dir(),
                             seastamp_bin = multised_seastamp_bin(),
                             region = "auto", verbose = TRUE) {
  pts <- df |>
    distinct(.data[[lon_col]], .data[[lat_col]]) |>
    filter(!is.na(.data[[lon_col]]), !is.na(.data[[lat_col]])) |>
    mutate(.pt_id = row_number())

  enr <- seastamp_enrich(pts, id_col = ".pt_id",
                         lon_col = lon_col, lat_col = lat_col,
                         seastamp_dir = seastamp_dir, seastamp_bin = seastamp_bin,
                         region = region, verbose = verbose)

  # the nearest-country column is named per source; the rest match the clean names
  lookup <- pts |>
    left_join(enr, by = ".pt_id") |>
    select(all_of(c(lon_col, lat_col)),
           dist_to_coast, !!country_col := .data$country, country_code,
           municipality, sea_name)

  out <- df |>
    select(-any_of(c("dist_to_coast", "est_country", "country", "country_code",
                     "municipality", "sea_name"))) |>
    left_join(lookup, by = c(lon_col, lat_col))

  if (verbose) {
    cat(sprintf("  %d distinct positions -> %d station rows annotated\n",
                nrow(pts), sum(!is.na(out$dist_to_coast))))
  }
  out
}
