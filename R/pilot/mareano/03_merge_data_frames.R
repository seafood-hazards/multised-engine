df_cruise <- df_inorganic_cruise |>
  left_join(df_cruise_info, by="cruise_id")

df_core <- df_inorganic_core |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id")

df_sample <- df_inorganic_sample |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
  inner_join(df_core |> distinct(core_id), by="core_id") %>%
  mutate(depth_from = as.integer(depth_from),
         depth_to = as.integer(depth_to))

df_parameter <- df_inorganic_unit |>
  left_join(df_element_info, by = "parameter")

df_sediment <- df_inorganic_sediment |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
  inner_join(df_core |> distinct(core_id), by="core_id") |>
  inner_join(df_sample |> distinct(sample_id), by="sample_id") |>
  inner_join(df_parameter |> distinct(parameter), by="parameter")

df_lld <- df_lld_info

df_missing_batch_ids <- df_sample %>%
  anti_join(df_lld %>% distinct(batch_id)) %>%
  distinct(batch_id) %>%
  drop_na() %>%
  inner_join(df_sample) %>%
  distinct( cruise_id, batch_id )

df_missing_batch_ids
