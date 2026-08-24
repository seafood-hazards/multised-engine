# ── Slim step 1, 4Demon ──────────────────────────────────────────────────────
# Pilot tables: project, station, parameter, method, sample, sediment.
#
# 4Demon has no grain-size composition, so there is no "SED" pass; it does carry
# the widest set of native quality flags, which step 13 folds into `src_flag`.
#
# The natural (unkeyed) joins are kept exactly as the original script had them.

slim_transform_4demon <- function(con_src) {
  # ── 0. Read source data ────────────────────────────────────────────────────
  df_project <- dbReadTable(con_src, "project")     |> as_tibble()
  df_station <- dbReadTable(con_src, "station")     |> as_tibble()
  df_parameter <- dbReadTable(con_src, "parameter") |> as_tibble()
  df_method <- dbReadTable(con_src, "method")       |> as_tibble()
  df_sample <- dbReadTable(con_src, "sample")       |> as_tibble()
  df_sediment <- dbReadTable(con_src, "sediment")   |> as_tibble()

  # ── 1. Filter to 7 target elements ─────────────────────────────────────────
  df_base_parameter <- df_parameter %>%
    filter(parameter %in% c("CO", "CU", "I", "MN", "MO", "SE", "ZN"))

  df_base_sediment <- df_sediment %>%
    inner_join(df_base_parameter %>% distinct(parameter), by = "parameter")

  df_base_sample <- df_sample %>%
    inner_join(df_base_sediment %>% distinct(sample_id))

  df_base_method <- df_method %>%
    inner_join(df_sediment %>% distinct(method_id))

  df_base_project <- df_project %>%
    inner_join(df_base_sample %>% distinct(project_id))

  df_base_station <- df_station %>%
    inner_join(df_base_sample %>% distinct(station_id))

  # ── 2. Reference elements ──────────────────────────────────────────────────
  df_ref_parameter <- df_parameter %>%
    filter(parameter %in% c("FE", "AL"))

  df_ref_sediment <- df_sediment %>%
    inner_join(df_ref_parameter %>% distinct(parameter)) %>%
    inner_join(df_base_sample %>% distinct(sample_id))

  # ── 3. Build dataset table ─────────────────────────────────────────────────
  df_dataset <- df_base_project %>%
    group_by(project)  %>%
    summarise(project_id = paste0(project_id, collapse = ", "), .groups = "drop") %>%
    mutate(source       = "4Demon",
           country      = "Belgium",
           dataset_id   = row_number()) %>%
    select(dataset_id, source,
           dataset_name = project, country, project_id)

  df_project_to_dataset <- df_dataset %>%
    select(dataset_id, project_id) %>%
    tidyr::separate_rows(project_id, sep = ",\\s*") %>%
    mutate(
      dataset_id = as.integer(dataset_id),
      project_id = as.integer(project_id)
    )

  df_dataset <- df_dataset %>% dplyr::select(-project_id)

  # ── 4. Build site table (keyed on lat/lon rounded to 3 d.p.) ───────────────
  df_site <- df_base_station %>%
    mutate(lat_r = round(latitude, 3),
           lon_r = round(longitude, 3)) %>%
    group_by(lat_r, lon_r, dist_to_coast, est_country, country_code, municipality, sea_name) %>%
    summarise(station_id = paste0(station_id, collapse = ", "), .groups = "drop") %>%
    group_by(lat_r, lon_r) %>%
    summarise(dist_to_coast = min(dist_to_coast),
              country = first(est_country),
              country_code = first(country_code),
              municipality = first(municipality),
              sea_name = first(sea_name),
              station_id = paste0(station_id, collapse = ", "),
              .groups = "drop") %>%
    mutate(site_id = row_number()) %>%
    select(site_id, latitude = lat_r, longitude = lon_r,
           country, country_code, dist_to_coast, municipality, sea_name, station_id)

  df_station_to_site <- df_site %>%
    select(site_id, station_id) %>%
    tidyr::separate_rows(station_id, sep = ",\\s*") %>%
    mutate(
      site_id = as.integer(site_id),
      station_id = as.integer(station_id)
    )

  df_site <- df_site %>% dplyr::select(-station_id)

  # ── 5. Build intermediate slim dataset ─────────────────────────────────────
  df_slim <- bind_rows(df_base_sediment, df_ref_sediment) %>%
    inner_join(df_base_sample, by = "sample_id") %>%
    inner_join(df_project_to_dataset, by = "project_id") %>%
    inner_join(df_station_to_site, by = "station_id") %>%
    inner_join(df_base_method, by = "method_id") %>%
    inner_join(df_parameter, by = "parameter") %>%
    tidyr::separate(depth_range, sep = "-", remove = FALSE, into = c("depth_from", "depth_to")) %>%
    tidyr::separate(unit, sep = " ", remove = FALSE, into = c("unit2", "basis")) %>%
    mutate(date_orig = as.Date(sample_timestamp, format = "%d/%m/%Y %H:%M"),
           year = lubridate::year(date_orig) %>% as.integer(),
           date = as.character(date_orig))

  # ── 6. Build event table (one row per core, not per depth interval) ────────
  df_event_keys <- df_slim %>%
    distinct(dataset_id, site_id, sampling_tool = gear_code, year, date)  %>%
    mutate(event_id = row_number())

  df_slim <- df_slim %>%
    inner_join(df_event_keys %>% distinct(dataset_id, site_id, gear_code = sampling_tool,
                                          event_id, year, date),
               by = c("dataset_id", "site_id", "gear_code", "year", "date"))

  df_event <- df_event_keys %>%
    select(event_id, dataset_id, site_id, sampling_tool, year, date)

  # ── 7. Build method table ──────────────────────────────────────────────────
  df_method <- df_slim %>%
    distinct(parameter, method_code) %>%
    mutate(method_id = row_number())

  df_slim <- df_slim %>%
    rename(method_id_old = method_id) %>%
    inner_join(df_method, by = c("parameter", "method_code"))

  # `method_code` is programme_instrument_sieve (e.g. Monit3_OES/MS_63) and encodes no
  # chemistry, so the extraction is UNK for all but the one code that names an acid
  # outright. It is already part of the distinct() above, so the class follows from it.
  # See R/extraction-class.R.
  df_method <- df_method %>%
    mutate(extraction = extraction_canon(method_code, "4Demon"),
           extraction_class = extraction_efsa_class(extraction)) %>%
    select(method_id, symbol = parameter, method = method_code,
           extraction, extraction_class)

  # ── 8. Build subsample table ───────────────────────────────────────────────
  df_subsample <- df_slim %>%
    distinct(event_id, depth_from, depth_to) %>%
    mutate(subsample_id = row_number()) %>%
    select(subsample_id, event_id, depth_from, depth_to)

  df_slim <- df_slim %>%
    inner_join(df_subsample, by = c("event_id", "depth_from", "depth_to"))

  # ── 9. Build measurement table ─────────────────────────────────────────────
  df_measurement <- df_slim %>%
    distinct(survey_seq_no, subsample_id, parameter, value, corrected_value,
             unit = unit2, basis, matrix_code, fraction_range_um, vflag = value_flag,
             limit_flag = det_limit_flag, range_check_flag, outlier_extreme_flag, outlier_stdev_flag,
             method_id) %>%
    mutate(measurement_id = row_number()) %>%
    select(measurement_id, subsample_id, symbol = parameter, value, corrected_value,
           unit, basis, matrix = matrix_code, fraction_range = fraction_range_um,
           vflag, limit_flag,
           range_check_flag, outlier_extreme_flag, outlier_stdev_flag, method_id)

  # ── 10. Build element table ────────────────────────────────────────────────
  df_element <- bind_rows(df_base_parameter, df_ref_parameter) %>%
    distinct(symbol = parameter, element = parameter_name)

  list(element     = df_element,
       dataset     = df_dataset,
       site        = df_site,
       event       = df_event,
       method      = df_method,
       subsample   = df_subsample,
       measurement = df_measurement)
}
