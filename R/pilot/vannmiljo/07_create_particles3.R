library(tidyverse)

df_vannmiljo_sediment <- read_tsv("./data/pilot_vannmiljo_all.tsv.gz")
df_sediment_fractions <- read_tsv("./data/pilot_vannmiljo_particles.tsv.gz")

df_vannmiljo_sediment_particles <- df_vannmiljo_sediment %>%
  filter(category != "p") %>%
  left_join(df_sediment_fractions %>%
              dplyr::select(sample_id, sediment_no, clay_pct, silt_pct, sand_pct, gravel_pct, total_pct, particle_qc_confidence = qc_confidence),
            by = c("sample_id", "sediment_no"))

write_tsv(df_vannmiljo_sediment_particles, "./data/pilot_vannmiljo_pivoted_particles.tsv.gz")
