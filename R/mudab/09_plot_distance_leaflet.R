library(tidyverse)
library(ggpubr)
library(leaflet)
library(sf)
library(viridis)


# 1. Prepare Data
# Ensure we are using the SF object with WGS84 (Lat/Lon) coordinates
# Assuming 'points_sf' has columns: Distance, label, geometry

df_loc <- df_mudab_sediment |> dplyr::distinct(organisation, project_affiliation, responsible_institute, region, station_latitude, survey_id, station_longitude, dist_to_coast, est_country, country_code, municipality, sea_name) |>
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

points_web <- st_as_sf(df_loc, coords = c("station_longitude", "station_latitude"), remove = FALSE, crs = 4326)
#saveRDS(points_web, "./data/points_web_mudab.Rds")

# 2. Define Default View (So we can use it twice)
# Adjust these to your liking
home_lat <- 55
home_lng <- 5
home_zoom <- 5

# 3. Create Palette
pal <- colorFactor(palette = "turbo", domain = points_web$Distance)

# 4. Initialize Map
map <- leaflet(points_web) %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  setView(lng = home_lng, lat = home_lat, zoom = home_zoom)

# 5. Add Points (Group Loop)
dist_groups <- rev(levels(points_web$Distance))

for(group in dist_groups) {
  data_subset <- points_web[points_web$Distance == group, ]
  map <- map %>%
    addCircleMarkers(
      data = data_subset,
      group = group,
      radius = 6,
      color = ~pal(group),
      fillColor = ~pal(group),
      fillOpacity = 0.7,
      weight = 1,
      label = ~paste0("Survey ID: ", survey_id),
      popup = ~paste0(
        "<strong>Survey ID:</strong> ", survey_id, "<br>",
        "<strong>Organisation:</strong> ", organisation, "<br>",
        "<strong>Project affiliation:</strong> ", project_affiliation, "<br>",
        "<strong>Responsible institute:</strong> ", responsible_institute, "<br>",
        "<strong>Latitude:</strong> ", round(station_latitude, 2), "<br>",
        "<strong>Longitude:</strong> ", round(station_longitude, 2), "<br>",
        "<strong>Region:</strong> ", region, "<br>",
        "<strong>Distance:</strong> ", round(dist_to_coast, 1), " km", "<br>",
        "<strong>Country:</strong> ", est_country, "<br>",
        "<strong>Country Code:</strong> ", country_code, "<br>",
        "<strong>Municipality:</strong> ", municipality, "<br>",
        "<strong>Sea/Ocean Name:</strong> ", sea_name, "<br>"
      )
    )
}

# 6. Add Controls & The Home Button
map %>%
  addLayersControl(
    overlayGroups = dist_groups,
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  addLegend(
    position = "bottomright",
    pal = pal,
    values = ~Distance,
    title = "Distance to Coast",
    opacity = 1
  ) %>%
  # --- THE HOME BUTTON LOGIC ---
  # This adds a generic button to the toolbar
  addEasyButton(easyButton(
    icon = "fa-earth-europe",  # FontAwesome globe icon
    title = "Reset View",
    onClick = JS(paste0("function(btn, map){ map.setView([", home_lat, ",", home_lng, "], ", home_zoom, "); }"))
  ))
