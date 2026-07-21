library(sf)
library(tidyverse)

# --- Step 1: Prepare your data ---
ocean_points <- df_site %>%
  distinct(lon, lat) %>%
  st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE)

# --- Step 2: Download IHO Sea Areas ---
# The IHO dataset often has topology errors, so we download it and immediately fix it
#iho_url <- "https://geo.vliz.be/geoserver/MarineRegions/wfs?service=WFS&version=1.0.0&request=GetFeature&typeName=MarineRegions:goas&outputFormat=json"

message("Downloading IHO Sea Areas...")
# Use quiet = TRUE to suppress the download progress bar if needed
#iho_seas <- st_read(iho_url, quiet = TRUE)

# --- Step 3: THE FIX (Disable s2) ---
# We turn off spherical geometry to bypass the "Loop crosses edge" error
sf_use_s2(FALSE)

# Ensure the downloaded polygons are valid in planar geometry
#iho_seas <- st_make_valid(iho_seas)
data_path <- "./data"

#saveRDS(iho_seas, file.path(data_path, "iho_seas.Rds"))
iho_seas <- readRDS(file.path(data_path, "iho_seas.Rds"))

# Perform the spatial join (Planar mode)
joined_data <- st_join(ocean_points, iho_seas)

# --- Step 4: Handle NA values (Nearest Neighbor) ---
# Identify points that didn't fall strictly inside a polygon
na_indices <- which(is.na(joined_data$name))

if(length(na_indices) > 0) {
  message(paste("Fixing", length(na_indices), "points located slightly inland/coastal..."))

  # Calculate nearest feature using planar distance (acceptable for labeling)
  nearest_idx <- st_nearest_feature(ocean_points[na_indices, ], iho_seas)

  # Assign the name
  joined_data$name[na_indices] <- iho_seas$name[nearest_idx]
}

# --- Step 5: Re-enable s2 for future operations ---
sf_use_s2(TRUE)

# --- Step 6: Clean and Merge ---
sea_names_lookup <- joined_data %>%
  st_drop_geometry() %>%
  select(lat, lon, sea_name = name)

# Merge back into your main dataframe
df_site <- df_site %>%
  left_join(sea_names_lookup, by = c("lat", "lon"))

# Check the results
print(head(df_site %>% select(site_code, sea_name)))
