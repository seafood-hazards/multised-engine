# ── Pilot geo-enrichment ─────────────────────────────────────────────────────
# Adds dist_to_coast / est_country / country_code / municipality / sea_name to a
# source's station frame, from GSHHG shorelines, Natural Earth countries, GISCO
# LAU municipalities and the IHO Sea Areas.
#
# Replaces the twenty `04_*` scripts (four per source). They differed only in the
# frame they operated on and its coordinate column names, so the body is shared
# and those two things are arguments.
#
# The original scripts passed `ocean_points` between each other through the
# session: the country script built it and attached `nearest_country`, and the
# municipality script then read that object back. That coupling is why country
# and municipality are one function here rather than two.
#
# NOTE: the clean stage recomputes all of these columns with the `seastamp` CLI
# (R/clean/geo_enrich.R), so these values do not survive into the clean
# databases. They are computed here only because they are stored in the pilot
# tables, and reproducing a pilot database requires them.
#
# The spatial packages are Suggests, not Imports: a plain install can build every
# other part of the pipeline without them.

pilot_geo_require <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("The pilot geo-enrichment step needs: ", paste(missing, collapse = ", "),
         ".\nInstall them, or skip the step, e.g. ",
         "create_db(\"pilot\", source, steps = c(1, 5)).", call. = FALSE)
  }
  invisible(NULL)
}

# Unique coordinates of a station frame as an sf point layer, the starting point
# of all four enrichments.
pilot_geo_points <- function(df, lon_col, lat_col) {
  df |>
    distinct(.data[[lon_col]], .data[[lat_col]]) |>
    sf::st_as_sf(coords = c(lon_col, lat_col), crs = 4326, remove = FALSE)
}

# ── Distance to the nearest shoreline (GSHHG) ────────────────────────────────
# Distances are computed in EPSG:3035 (ETRS89-extended / LAEA Europe), which is
# accurate for Norway/Svalbard where a Web-Mercator distance would not be.
pilot_geo_coast <- function(df, lon_col, lat_col,
                            data_path = "./data/gshhg/gshhg-shp-2.3.7/GSHHS_shp/f",
                            verbose = TRUE) {
  pilot_geo_require(c("sf"))

  # A box slightly larger than the data extent, so the nearest coast is not cut
  # off by the crop.
  europe_bbox <- sf::st_bbox(c(xmin = -30, xmax = 45, ymin = 45, ymax = 80),
                             crs = 4326) |>
    sf::st_as_sfc()

  shapefile_paths <- list.files(data_path, pattern = "\\.shp$", full.names = TRUE)
  if (!length(shapefile_paths)) {
    stop("No GSHHG shapefiles under ", data_path, call. = FALSE)
  }

  coastline <- shapefile_paths |>
    lapply(sf::st_read, quiet = TRUE) |>
    lapply(function(x) sf::st_transform(x, 4326)) |>
    lapply(sf::st_make_valid) |>
    lapply(function(x) x[sf::st_is_valid(x), ]) |>
    lapply(function(x) sf::st_collection_extract(x, "POLYGON")) |>
    # st_filter rather than st_crop: slicing land polygons in half creates
    # artificial straight edges that then read as the "nearest" coast.
    lapply(function(x) sf::st_filter(x, europe_bbox)) |>
    bind_rows()

  # GSHHG geometry is often messy; union it with the spherical engine off.
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  coastline <- sf::st_union(coastline) |> sf::st_make_valid()
  sf::sf_use_s2(TRUE)

  target_crs <- 3035
  points_proj <- sf::st_transform(pilot_geo_points(df, lon_col, lat_col), target_crs)
  coastline_proj <- sf::st_transform(coastline, target_crs)

  dists <- as.numeric(apply(sf::st_distance(points_proj, coastline_proj), 1, min))
  results <- points_proj |>
    sf::st_drop_geometry() |>
    mutate(dist_to_coast = dists / 1000) |>   # metres -> km
    select(all_of(c(lat_col, lon_col)), dist_to_coast)

  out <- df |> left_join(results, by = c(lon_col, lat_col))
  if (verbose) cat("  dist_to_coast: ", sum(!is.na(out$dist_to_coast)),
                   " of ", nrow(out), " rows\n", sep = "")
  out
}

# ── Nearest country and municipality (Natural Earth + GISCO LAU) ─────────────
# One function because the two are coupled: the municipality lookup reads the
# `nearest_country` the country lookup attached to the shared point layer.
pilot_geo_place <- function(df, lon_col, lat_col, verbose = TRUE) {
  pilot_geo_require(c("sf", "rnaturalearth", "giscoR"))

  ocean_points <- pilot_geo_points(df, lon_col, lat_col)

  # Nearest country. st_nearest_feature returns the row index of the nearest.
  world_map <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")
  nearest_indices <- sf::st_nearest_feature(ocean_points, world_map)
  ocean_points$nearest_country <- world_map$name[nearest_indices]
  ocean_points$nearest_iso3 <- world_map$iso_a3[nearest_indices]

  # ISO3 codes, not names, to avoid GISCO's ambiguous "GB".
  target_countries <- c("NOR", "PRT", "ESP", "FRA", "GBR", "IRL", "DNK", "DEU",
                        "NLD", "BEL", "ISL", "BIH", "HRV", "EST", "FIN", "GRC",
                        "ITA", "LVA", "LTU", "RUS", "SWE")
  if (verbose) message("Downloading Municipality Data...")
  municipalities <- giscoR::gisco_get_lau(year = "2020", country = target_countries)

  # Planar geometry, so the LAU polygons' "loop crosses edge" errors do not stop
  # the nearest-feature search; st_make_valid closes them first.
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  municipalities <- sf::st_make_valid(municipalities)
  if (verbose) message("Calculating nearest municipalities...")
  nearest_lau_indices <- sf::st_nearest_feature(ocean_points, municipalities)
  sf::sf_use_s2(TRUE)

  results_muni <- ocean_points |>
    mutate(
      est_municipality = municipalities$LAU_NAME[nearest_lau_indices],
      est_country_code = municipalities$CNTR_CODE[nearest_lau_indices]
    ) |>
    sf::st_drop_geometry() |>
    select(all_of(c(lat_col, lon_col)),
           est_country = "nearest_country",
           country_code = "est_country_code",
           municipality = "est_municipality")

  out <- df |> left_join(results_muni, by = c(lon_col, lat_col))
  if (verbose) cat("  country/municipality: ", sum(!is.na(out$municipality)),
                   " of ", nrow(out), " rows\n", sep = "")
  out
}

# ── Sea / ocean name (IHO Sea Areas) ─────────────────────────────────────────
# The IHO layer is read from a saved copy rather than re-downloaded, so a rebuild
# does not depend on the Marine Regions service being up.
pilot_geo_sea <- function(df, lon_col, lat_col,
                          data_path = "./data", verbose = TRUE) {
  pilot_geo_require(c("sf"))

  iho_file <- file.path(data_path, "iho_seas.Rds")
  if (!file.exists(iho_file)) {
    stop("IHO Sea Areas not found at ", iho_file, call. = FALSE)
  }
  iho_seas <- readRDS(iho_file)

  ocean_points <- pilot_geo_points(df, lon_col, lat_col)

  # Planar mode: the IHO polygons trip the spherical engine.
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  joined_data <- sf::st_join(ocean_points, iho_seas)

  # Points that did not fall strictly inside a polygon (slightly inland or
  # coastal) take the nearest sea instead.
  na_indices <- which(is.na(joined_data$name))
  if (length(na_indices) > 0) {
    if (verbose) {
      message("Fixing ", length(na_indices),
              " points located slightly inland/coastal...")
    }
    nearest_idx <- sf::st_nearest_feature(ocean_points[na_indices, ], iho_seas)
    joined_data$name[na_indices] <- iho_seas$name[nearest_idx]
  }
  sf::sf_use_s2(TRUE)

  # st_join suffixes the duplicated coordinate columns with .x
  sea_names_lookup <- joined_data |>
    sf::st_drop_geometry() |>
    select(all_of(setNames(paste0(c(lat_col, lon_col), ".x"), c(lat_col, lon_col))),
           sea_name = "name")

  out <- df |> left_join(sea_names_lookup, by = c(lon_col, lat_col))
  if (verbose) cat("  sea_name: ", sum(!is.na(out$sea_name)),
                   " of ", nrow(out), " rows\n", sep = "")
  out
}

# ── All four, in the order the scripts ran them ──────────────────────────────
pilot_geo_enrich <- function(df, lon_col, lat_col, verbose = TRUE) {
  df <- pilot_geo_coast(df, lon_col, lat_col, verbose = verbose)
  df <- pilot_geo_place(df, lon_col, lat_col, verbose = verbose)
  df <- pilot_geo_sea(df, lon_col, lat_col, verbose = verbose)
  df
}

# Which frame carries the stations for each source, and its coordinate columns.
pilot_geo_spec <- function(source) {
  switch(
    source,
    "mareano"   = list(frame = "df_core",    lon = "dde", lat = "ddn"),
    "vannmiljo" = list(frame = "df_site",    lon = "lon", lat = "lat"),
    "ices-dome" = list(frame = "df_site",    lon = "longitude", lat = "latitude"),
    "mudab"     = list(frame = "df_survey",
                       lon = "station_longitude", lat = "station_latitude"),
    "4demon"    = list(frame = "df_station", lon = "longitude", lat = "latitude"),
    stop("No geo spec for source ", sQuote(source), call. = FALSE)
  )
}
