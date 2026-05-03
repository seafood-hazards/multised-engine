library(sf)
library(tidyverse)
library(rnaturalearth)

# 1. Create ocean points
ocean_points <- df_survey %>%
  distinct(station_longitude, station_latitude) %>%
  st_as_sf(coords = c("station_longitude", "station_latitude"), crs = 4326, remove = FALSE)

# 2. Get Country Data (High definition)
# limiting to Europe/North America to speed up search, or use world
world_map <- ne_countries(scale = "medium", returnclass = "sf")

# 3. Find the Nearest Country
# st_nearest_feature returns the ROW INDEX of the nearest country
nearest_indices <- st_nearest_feature(ocean_points, world_map)

# 4. Extract the names using the indices
ocean_points$nearest_country <- world_map$name[nearest_indices]
ocean_points$nearest_iso3 <- world_map$iso_a3[nearest_indices]

print(ocean_points)
