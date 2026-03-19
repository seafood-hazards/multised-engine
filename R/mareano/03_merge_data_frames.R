df_cruise <- df_inorganic_cruise |>
  left_join(df_info_cruise, by="cruise_id")

df_core <- df_inorganic_core |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id")

df_sample <- df_inorganic_sample |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
  inner_join(df_core |> distinct(core_id), by="core_id")

df_parameter <- df_inorganic_unit |>
  left_join(df_info_element, by = "parameter")

df_sediment <- df_inorganic_sediment |>
  inner_join(df_cruise |> distinct(cruise_id), by="cruise_id") |>
  inner_join(df_core |> distinct(core_id), by="core_id") |>
  inner_join(df_sample |> distinct(sample_id), by="sample_id")

