library(tidyverse)

df_vannmiljo_sediment <- read_tsv("./data/pilot_vannmiljo.tsv.gz")

df_p <- df_vannmiljo_sediment %>%
  filter(category == "p") %>%
  dplyr::select(sample_id, param_id, sediment_no, param_name, value, unit, operator) %>%
  mutate(param_id = factor(param_id,
                           levels=c("GSMF2",
                                    "GSMF2_63",
                                    "FINS",
                                    "GSMF_63",
                                    "GSMF63_125",
                                    "GSMF125_250",
                                    "GSMF250_500",
                                    "GSMF500_1000",
                                    "GSMF1000_2000",
                                    "GSMF_2000")),
         param_name = factor(param_name,
                             levels=c("Particle fraction < 2 µm",
                                      "Particle fraction 2 - 63 µm",
                                      "Fines < 63 µm",
                                      "Particle fraction > 63 µm",
                                      "Particle fraction 63 - 125 µm",
                                      "Particle fraction 125 - 250 µm",
                                      "Particle fraction 250 - 500 µm",
                                      "Particle fraction 500 - 1000 µm",
                                      "Particle fraction 1000 - 2000 µm",
                                      "Particle fraction > 2000 µm")))

print(df_p)

df_p_val_wide <- df_p %>%
  distinct(sample_id, param_id, sediment_no, value) %>%
  arrange(param_id) %>%
  pivot_wider(names_from = param_id, values_from = value) %>%
  arrange(sample_id, sediment_no)

print(df_p_val_wide)

df_p_val_combinations <- df_p %>%
  arrange(param_id) %>%
  group_by(sample_id, sediment_no) %>%
  mutate(combination  = paste0(param_id, collapse=",")) %>%
  ungroup() %>%
  count(combination) %>%
  arrange(desc(n))

print(df_p_val_combinations)

df_p_op_wide <- df_p %>%
  distinct(sample_id, param_id, sediment_no, operator) %>%
  arrange(param_id) %>%
  mutate(param_id_op = paste0(as.character(param_id), "_op")) %>%
  dplyr::select(-c(param_id)) %>%
  pivot_wider(names_from = param_id_op, values_from = operator) %>%
  arrange(sample_id, sediment_no)

print(df_p_op_wide)

df_p_op_patterns <- df_p %>%
  count(param_id, operator)

print(df_p_op_patterns)




