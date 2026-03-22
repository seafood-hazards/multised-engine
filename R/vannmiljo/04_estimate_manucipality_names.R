library(sf)
library(giscoR)
library(tidyverse)

# 1. Use ISO3 codes (3 letters) to avoid the "Ambiguous GB" error
# NOR=Norway, PRT=Portugal, ESP=Spain, FRA=France, GBR=UK, IRL=Ireland,
# DNK=Denmark, DEU=Germany, NLD=Netherlands, BEL=Belgium
target_countries <- c("NOR", "PRT", "ESP", "FRA", "GBR", "IRL", "DNK", "DEU", "NLD", "BEL")

message("Downloading Municipality Data...")
municipalities <- gisco_get_lau(
  year = "2020",
  country = target_countries
)

# --- THE FIX STARTS HERE ---

# 2. Disable S2 Engine
# This switches to planar geometry, which ignores the "Loop crosses edge" errors
sf_use_s2(FALSE)

# 3. Fix invalid geometries
# Even with S2 off, we want to ensure polygons are mathematically closed
municipalities <- st_make_valid(municipalities)

# 4. Find Nearest Municipality
# Now this will run without error
message("Calculating nearest municipalities...")
nearest_lau_indices <- st_nearest_feature(ocean_points, municipalities)

# 5. Re-enable S2 (Good practice for future steps)
sf_use_s2(TRUE)

# --- THE FIX ENDS HERE ---

# 6. Extract estimates and bind to your data
results_muni <- ocean_points %>%
  mutate(
    est_municipality = municipalities$LAU_NAME[nearest_lau_indices],
    est_country_code = municipalities$CNTR_CODE[nearest_lau_indices]
  ) %>%
  st_drop_geometry() %>%
  select(lon, lat, country = nearest_country, country_code = est_country_code,  municipality = est_municipality)

# 7. Merge back to your main dataframe
df_site <- df_site %>%
  left_join(results_muni, by = c("lon", "lat"))

print(head(df_site))
