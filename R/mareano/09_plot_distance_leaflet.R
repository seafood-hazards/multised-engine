library(tidyverse)
library(ggpubr)
library(leaflet)
library(sf)
library(viridis)


# 1. Prepare Data
# Ensure we are using the SF object with WGS84 (Lat/Lon) coordinates
# Assuming 'points_sf' has columns: Distance, label, geometry

df_loc <- df_mariano_sediment |> distinct(cruise_id, core_id, dde, ddn, dist_to_coast) |>
  mutate(Distance = case_when(
    dist_to_coast <= 10 ~ "0 to 10km",
    dist_to_coast <= 30 ~ "10 to 30km",
    dist_to_coast <= 100 ~ "30 to 100km",
    .default = "≥100km"
  ) |>
    factor(levels=c("0 to 10km",
                              "10 to 30km",
                              "30 to 100km",
                              "≥100km")))

points_web <- st_as_sf(df_loc, coords = c("dde", "ddn"), remove = FALSE, crs = 4326)
saveRDS(points_web, "./data/points_web.Rds")

# 2. Create a Color Palette
# matches the 'Distance' factor levels
pal <- colorFactor(
  palette = "turbo",  # Or c("orange", "gold", "green", "blue")
  domain = points_web$Distance
)


# 3. Create the Map
leaflet(points_web) %>%
  # A. Add a nice base map (CartoDB is clean for scientific data)
  addProviderTiles(providers$CartoDB.Positron) %>%

  # B. Add the points
  addCircleMarkers(
    radius = 6,
    color = ~pal(Distance),    # Border color
    fillColor = ~pal(Distance),# Inner color
    fillOpacity = 0.7,
    weight = 1,                # Border width

    # INTERACTIVITY:
    # 'core_id' appears when you HOVER over the point
    label = ~paste0(
      "Cruise ID: ", cruise_id, ", ",
      "Core ID: ", core_id
    ),

    # 'popup' appears when you CLICK the point (supports HTML)
    popup = ~paste0(
      "<strong>Cruise ID:</strong> ", cruise_id, "<br>",
      "<strong>Core ID:</strong> ", core_id, "<br>",
      "<strong>Latitude:</strong> ", round(ddn, 2), "<br>",
      "<strong>Longitude:</strong> ", round(dde, 2), "<br>",
      "<strong>Distance:</strong> ", round(dist_to_coast, 1), " km<br>",
      "<strong>Category:</strong> ", Distance
    )
  ) %>%

  # C. Add a Legend
  addLegend(
    position = "bottomright",
    pal = pal,
    values = ~Distance,
    title = "Dist. to Coast",
    opacity = 1
  )
