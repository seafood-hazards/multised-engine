library(sf)
library(tidyverse)

# Define path
data_path <- "/scratch2/aiqc/GSHHG/gshhg/gshhg-shp-2.3.7/GSHHS_shp/f"

# --- Step 1: Define Bounding Box ---
# Note: When calculating distance, it is safer to make the box slightly larger
# than your data extent to ensure the nearest coast isn't cut off by the crop.
norway_bbox <- st_bbox(c(xmin = -10, xmax = 45, ymin = 55, ymax = 85), crs = 4326) %>%
  st_as_sfc()

# --- Step 2 & 3: Read and Clean Coastline ---
shapefile_paths <- list.files(data_path, pattern = "\\.shp$", full.names = TRUE)

coastline <- shapefile_paths %>%
  map(st_read, quiet = TRUE) %>%
  map(~ st_transform(.x, 4326)) %>%
  map(~ st_make_valid(.x)) %>%
  map(~ filter(.x, st_is_valid(.))) %>%
  map(~ st_collection_extract(.x, "POLYGON")) %>%
  # Use st_filter instead of st_crop to avoid slicing land polygons in half
  # (Slicing can create artificial straight lines that become "nearest" points)
  map(~ st_filter(.x, norway_bbox)) %>%
  bind_rows()

# Fix geometry errors (GSHHG is often messy)
sf_use_s2(FALSE)
coastline <- st_union(coastline) %>% st_make_valid()
sf_use_s2(TRUE)

# --- Step 4: Prepare Ocean Points ---
ocean_points <- df_core %>%
  distinct(dde, ddn) %>%
  st_as_sf(coords = c("dde", "ddn"), crs = 4326, remove = FALSE) %>%
  rename(longitude = dde, latitude = ddn)

# --- Step 5: Compute Distances (THE FIX) ---
# TARGET CRS: EPSG:3035 (ETRS89-extended / LAEA Europe)
# This projection is accurate for distances in Norway/Svalbard (unlike 3857)
target_crs <- 3035

coastline_proj <- st_transform(coastline, target_crs)
ocean_points_proj <- st_transform(ocean_points, target_crs)

# Calculate distance
# Result is in meters
ocean_points_proj <- ocean_points_proj %>%
  mutate(dist_to_coast = as.numeric(st_distance(geometry, coastline_proj) %>% apply(1, min)))

# --- Step 6 & 7: Clean up and Join ---
results <- ocean_points_proj %>%
  st_drop_geometry() %>%
  select(longitude, latitude, dist_to_coast)

df_core <- df_core %>%
  left_join(results, by = c("dde" = "longitude", "ddn" = "latitude"))

# Optional: Convert meters to km
df_core$dist_to_coast <- df_core$dist_to_coast / 1000

print(head(df_core))
