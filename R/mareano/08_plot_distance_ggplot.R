library(tidyverse)
library(ggpubr)

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

ggplot(df_loc, aes(x = dde, y = ddn, colour = Distance)) +
  annotation_borders("world", fill = "lightgray", color = "gray") +
  geom_point() +
  scale_color_viridis_d(option = "plasma") + # "turbo" or "plasma" are very distinct
  ggtitle("title") +
  xlab("Longitude") +
  ylab("Latitude") +
  coord_cartesian(xlim = c(0, 40), ylim = c(57, 82)) +
  theme_pubr(base_size = 12)


df_sf <- st_as_sf(df_loc, coords = c("dde", "ddn"), crs = 4326)

ggplot() +
  annotation_borders("world", fill = "lightgray", color = "gray") +
  geom_sf(data = df_sf, aes(color = Distance), size = 2) +
  # coord_sf handles the aspect ratio automatically
  # You can even use the projection from your distance calc (EPSG:3035) for a curved look
  coord_sf(xlim = c(0, 40), ylim = c(59, 80), crs = 4326) +
  theme_pubr()



library(tidyverse)
library(sf)
library(rnaturalearth) # For the background map
library(rnaturalearthdata)

# 1. Convert your dataframe to a spatial (sf) object
# We tell R the initial coordinates are WGS84 (crs = 4326)
points_sf <- df_loc %>%
  st_as_sf(coords = c("dde", "ddn"), crs = 4326)

# 2. Get a base map of the world (Europe context)
world_map <- ne_countries(scale = "medium", returnclass = "sf")

# 3. Define the Projection (EPSG:3035 - LAEA Europe)
target_crs <- 3035

# 4. Calculate the Zoom Limits (Bounding Box)
# We define the box in Lat/Lon, then transform it to the 3035 projection (meters).
# If we don't do this transformation, the zoom will be wrong.
bbox_wgs84 <- st_bbox(c(xmin = 0, xmax = 27, ymin = 56, ymax = 82), crs = 4326)
bbox_3035  <- st_as_sfc(bbox_wgs84) %>% st_transform(target_crs) %>% st_bbox()

# 5. Plot
p <- ggplot() +
  # A. Add the base map (World/Europe)
  geom_sf(data = world_map, fill = "lightgray", color = "darkgray") +

  # B. Add your data points
  geom_sf(data = points_sf, aes(color = Distance), size = 0.25, alpha = 0.8) +

  # C. Colors (using the Turbo palette suggested earlier)
  scale_color_viridis_d(option = "turbo") +

  # D. THE MAGIC STEP: Set the projection and zoom
  coord_sf(
    crs = target_crs,           # This curves the grid lines
    xlim = c(bbox_3035["xmin"], bbox_3035["xmax"]), # Limits in meters
    ylim = c(bbox_3035["ymin"], bbox_3035["ymax"]), # Limits in meters
    expand = FALSE              # Removes extra padding around the box
  ) +

  # E. Labels and Theme
  ggtitle("Sediment Cores (EPSG:3035 Projection)") +
  guides(color=guide_legend(title="Distance to Coastline")) +
  theme_bw(base_size = 10) +
  theme(
    panel.grid.major = element_line(color = gray(0.5), linetype = "dashed", linewidth = 0.5),
    panel.background = element_rect(fill = "aliceblue"),
    plot.title = element_text(size = 10),
    legend.title=element_text(size=9),
  )

library(cowplot)
ggsave2("/scratch/workspace/pilot-db-with-mareano/image/dist_to_coast.svg",
        p,  width = 100, height = 70, unit="mm", fix_text_size=FALSE)
