# ── Pilot location columns ───────────────────────────────────────────────────
# The pilot stage DECLARES the five location columns (dist_to_coast, the nearest
# country and its code, municipality, sea_name) and leaves them empty. It does not
# derive them.
#
# It used to. Until 2026-08-25 pilot step 4 ran the seastamp CLI over every station,
# exactly as clean step 4 does. The values never survived: clean_geo_enrich() UPDATEs
# all five columns unconditionally, so every pilot value was overwritten. Computing
# them twice bought nothing and cost two things, a second seastamp dependency in the
# pilot stage and a second set of numbers that could disagree with the ones that
# survive. (`pilot_geo_enrich()`, the seastamp implementation, is in git history at
# the commit that removed it, if the pilot values are ever wanted back.)
#
# The columns stay because the pilot schema declares them and the slim transforms
# select them; only the values go. Nothing computes from them in between: slim step
# 4's `area_flag` is a lat/lon bounding box, not a location lookup.

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

#' Declare the location columns a source's station frame must carry, all empty
#'
#' @param df The station frame named by [pilot_geo_spec()].
#' @param country_col The frame's own name for the nearest-country column, which is
#'   `country` for Mareano and Vannmiljo and `est_country` for the other three.
#' @return `df` with the five location columns present and NA. Any that the source
#'   already carries under those names are overwritten, so the result does not depend
#'   on what the raw export happened to include.
#' @noRd
pilot_geo_blank <- function(df, country_col = "est_country") {
  df |>
    select(-any_of(c("dist_to_coast", "est_country", "country", "country_code",
                     "municipality", "sea_name"))) |>
    mutate(dist_to_coast = NA_integer_,
           !!country_col := NA_character_,
           country_code  = NA_character_,
           municipality  = NA_character_,
           sea_name      = NA_character_)
}
