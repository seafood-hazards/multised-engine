# ── Pilot step 1, ICES-DOME ──────────────────────────────────────────────────
# Parses the ICES-DOME sediment export plus its RECO code exports into the pilot
# tables: code_lookup, project, site, parameter, lld, analysis_method, reference,
# sample, sediment.
#
# ICES ships codes rather than values, so the eighteen RECO exports are combined
# into one lookup and joined back on. Several columns hold `~`-joined multi-codes,
# which are split before the lookup.

pilot_extract_ices_dome <- function(raw_dir = multised_raw_dir(), verbose = TRUE) {
  data_path <- file.path(raw_dir, "ICES DOME")
  data_file <- file.path(data_path, "DomeSediment_Data_0326015962.csv")
  code_path <- file.path(data_path, "code")
  if (!file.exists(data_file)) {
    stop("ICES-DOME export not found: ", data_file, call. = FALSE)
  }

  # ── Read the whole export ──────────────────────────────────────────────────
  # Fixes applied at read: PARAM upper-cased (and the literal "NA" sodium code
  # rescued from being read as missing), the SEDTOT/SEDtot casing split, and two
  # transposed lab codes.
  all_data <- read_csv(data_file, show_col_types = FALSE) |>
    mutate(PARAM = if_else(is.na(PARAM), "NA", toupper(PARAM)),
           MATRX = if_else(MATRX == "SEDTOT", "SEDtot", MATRX),
           RLABO = ifelse(RLABO == "LNUG", "LUNG", RLABO),
           ALABO = ifelse(ALABO == "LNUG", "LUNG", ALABO)) |>
    filter(Longitude >= -30 & Longitude <= 30) %>%
    filter(PARGROUP %in% c("B-BIO", "I-MAJ", "I-MET", "P-PHY", "O-MAJ"))

  # ── Read code data ─────────────────────────────────────────────────────────
  code_files <- file.path(code_path, c(
    "RECO_Export_13-08-2026-02-08-51.csv",
    "RECO_Export_13-09-2026-02-09-21.csv",
    "RECO_Export_13-08-2026-12-08-07.csv",
    "RECO_Export_13-08-2026-12-08-41.csv",
    "RECO_Export_13-10-2026-12-10-39.csv",
    "RECO_Export_13-16-2026-12-16-53.csv",
    "RECO_Export_13-20-2026-12-20-47.csv",
    "RECO_Export_13-23-2026-12-23-21.csv",
    "RECO_Export_13-32-2026-12-32-07.csv",
    "RECO_Export_13-32-2026-12-32-26.csv",
    "RECO_Export_13-36-2026-12-36-40.csv",
    "RECO_Export_13-37-2026-12-37-45.csv",
    "RECO_Export_13-40-2026-12-40-21.csv",
    "RECO_Export_13-41-2026-12-41-37.csv",
    "RECO_Export_13-46-2026-12-46-49.csv",
    "RECO_Export_13-57-2026-11-57-46.csv",
    "RECO_Export_13-57-2026-11-57-56.csv",
    "RECO_Export_13-58-2026-11-58-58.csv"
  ))

  combined_codes <- code_files |>
    map(function(f) read_csv(f, col_select = c(Code, Description, CodeType),
                             show_col_types = FALSE)) |>
    purrr::list_rbind() |>
    mutate(Code = ifelse(Description == "sodium", "NA", Code))

  # ── Create look-up table ───────────────────────────────────────────────────
  # Column -> CodeType mapping. RLABO/ALABO both map to "RLABO"; PARGROUP maps to
  # "Pargroup"; DCFLGs to "DCFLG".
  col_to_codetype <- tibble::tribble(
    ~data_col,  ~CodeType,
    "MPROG",    "MPROG",
    "PURPM",    "PURPM",
    "RLABO",    "RLABO",
    "MATRX",    "MATRX",
    "PARGROUP", "Pargroup",
    "PARAM",    "PARAM",
    "BASIS",    "BASIS",
    "QFLAG",    "QFLAG",
    "VFLAG",    "VFLAG",
    "METCU",    "METCU",
    "ALABO",    "RLABO",
    "REFSK",    "REFSK",
    "METST",    "METST",
    "METPT",    "METPT",
    "METPS",    "METPS",
    "METCX",    "METCX",
    "METOA",    "METOA",
    "SMTYP",    "SMTYP",
    "DCFLGs",   "DCFLG"
  )

  multi_code_cols <- c("MPROG", "PURPM", "QFLAG", "VFLAG", "DCFLGs", "METPT", "METCX")

  # Step 1: distinct raw codes, multi-codes expanded
  used_codes <- col_to_codetype |>
    mutate(
      raw_code = map(data_col, function(col) {
        all_data |>
          distinct(across(all_of(col))) |>
          pull(col) |>
          discard(is.na)
      })
    ) |>
    tidyr::unnest(raw_code) |>
    mutate(
      Code = purrr::map2(data_col, raw_code, function(col, val) {
        if (col %in% multi_code_cols) stringr::str_split_1(val, "~") else val
      })
    ) |>
    tidyr::unnest(Code) |>
    mutate(Code = ifelse(Code == "21-CONVR-1", "21-METPT-1", Code))

  # Step 2: filter the combined codes to those actually used
  used_combined_codes <- combined_codes |>
    semi_join(used_codes, by = c("CodeType", "Code"))

  # Step 3: build the lookup.
  # raw_code: the original value in all_data (e.g. "T~S")
  # Code:     the individual split code     (e.g. "T", "S")
  code_lookup <- used_codes |>
    left_join(
      combined_codes |> select(CodeType, Code, Description),
      by = c("CodeType", "Code")
    )

  # ── Update column names ────────────────────────────────────────────────────
  col_rename <- tibble::tribble(
    ~old,         ~new,
    "MPROG",      "project",
    "PURPM",      "purpose",
    "Country",    "country",
    "RLABO",      "institute",
    "STATN",      "station",
    "MYEAR",      "year",
    "DATE",       "date",
    "Latitude",   "latitude",
    "Longitude",  "longitude",
    "DEPHU",      "depth_from",
    "DEPHL",      "depth_to",
    "MATRX",      "matrix",
    "PARGROUP",   "group_code",
    "PARAM",      "param",
    "BASIS",      "basis",
    "QFLAG",      "qflag",
    "Value",      "value",
    "MUNIT",      "unit",
    "VFLAG",      "vflag",
    "DETLI",      "lod",
    "LMQNT",      "loq",
    "UNCRT",      "uncrt",
    "METCU",      "metcu",
    "ALABO",      "labo",
    "REFSK",      "ref",
    "METST",      "metst",
    "METPT",      "metpt",
    "METPS",      "metps",
    "METCX",      "metcx",
    "METOA",      "metoa",
    "SMTYP",      "sample_type",
    "SUBNO",      "sub_no",
    "DCFLGs",     "dcflag"
  )

  # select() accepts a named vector where names = new, values = old
  df_all <- all_data |>
    select(all_of(tibble::deframe(col_rename[, c("new", "old")])))

  code_lookup <- code_lookup |>
    left_join(col_rename, by = c("data_col" = "old")) |>
    mutate(data_col = coalesce(new, data_col)) |>
    distinct(data_col, code_type = CodeType, raw_code, code = Code,
             description = Description)

  # ── project ────────────────────────────────────────────────────────────────
  df_project <- df_all %>% distinct(project, purpose, country, institute) %>%
    arrange(country, institute, project, purpose) %>%
    mutate(project_id = row_number()) %>%
    dplyr::select(project_id, project, purpose, country, institute)

  # ── site ───────────────────────────────────────────────────────────────────
  df_site <- df_all %>% distinct(station, latitude, longitude) %>%
    arrange(station, latitude, longitude) %>%
    mutate(site_id = row_number()) %>%
    dplyr::select(site_id, station, latitude, longitude)

  # ── sample ─────────────────────────────────────────────────────────────────
  df_sample <- df_all %>% count(project, purpose, country, institute,
                                 station, latitude, longitude,
                                 year, date, sample_type) %>%
    inner_join(df_project, by = c("project", "purpose", "country", "institute")) %>%
    inner_join(df_site, by = c("station", "latitude", "longitude")) %>%
    mutate(sample_id = row_number()) %>%
    left_join(
      code_lookup %>% filter(data_col == "sample_type") %>% select(raw_code, sample_type_description = description),
      by = c("sample_type" = "raw_code")
    )  %>%
    dplyr::select(sample_id, project_id, site_id, year, date, sample_type, sample_type_description, row_count = n)

  # ── parameter ──────────────────────────────────────────────────────────────
  df_parameter <- df_all %>% count(group_code, param) %>%
    inner_join(
      code_lookup %>% filter(data_col == "group_code") %>% select(raw_code, group_description = description),
      by = c("group_code" = "raw_code")
    ) %>%
    inner_join(
      code_lookup %>% filter(data_col == "param") %>% select(raw_code, param_description = description),
      by = c("param" = "raw_code")
    ) %>%
    dplyr::select(param, param_description, group_code, group_description, row_count = n)

  # ── lld ────────────────────────────────────────────────────────────────────
  df_lld <- df_all %>% count(param, lod, loq)  %>%
    mutate(lld_id = row_number()) %>%
    dplyr::select(lld_id, param, lod, loq, row_count = n)

  # ── analysis method ────────────────────────────────────────────────────────
  df_analysis_method <- df_all %>% count(param, labo, metst, metpt, metps, metcx, metoa)  %>%
    mutate(analysis_id = row_number()) %>%
    dplyr::select(analysis_id, param, labo, metst, metpt, metps, metcx, metoa, row_count = n)

  # ── reference ──────────────────────────────────────────────────────────────
  df_referance <- df_all %>% count(ref) %>%
    left_join(
      code_lookup %>% filter(data_col == "ref") %>% select(raw_code, ref_description = description),
      by = c("ref" = "raw_code")
      ) %>%
    mutate(ref_id = row_number()) %>%
    dplyr::select(ref_id, ref, ref_description, row_count = n)

  # ── sediment ───────────────────────────────────────────────────────────────
  df_sediment <- df_all %>%
    inner_join(df_project, by = c("project", "purpose", "country", "institute")) %>%
    inner_join(df_site, by = c("station", "latitude", "longitude")) %>%
    inner_join(df_sample, by = c("project_id", "site_id", "year", "date", "sample_type")) %>%
    inner_join(df_parameter, by = c("param", "group_code")) %>%
    inner_join(df_lld, by = c("param", "lod", "loq")) %>%
    inner_join(df_analysis_method, by = c("param", "labo", "metst", "metpt", "metps", "metcx", "metoa")) %>%
    inner_join(df_referance, by = "ref") %>%
    dplyr::select(project_id, site_id, sample_id, year, date, sample_type,
                  depth_from, depth_to, matrix, param, value, unit,
                  basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                  sub_no, dcflag) %>%
    arrange(project_id, site_id, sample_id, param, depth_from, depth_to) %>%
    group_by(project_id, site_id, sample_id, param) %>%
    mutate(sediment_no = row_number()) %>%
    ungroup() %>%
    dplyr::select(project_id, site_id, sample_id, param,
                  sediment_no, depth_from, depth_to, matrix,
                  value, unit,
                  basis, qflag, vflag, uncrt, metcu, lld_id, analysis_id, ref_id,
                  sub_no, dcflag)

  if (verbose) {
    cat(sprintf("ices-dome parsed: project %d, site %d, sample %d, parameter %d, sediment %d\n",
                nrow(df_project), nrow(df_site), nrow(df_sample),
                nrow(df_parameter), nrow(df_sediment)))
  }

  list(code_lookup     = code_lookup,
       project         = df_project,
       site            = df_site,
       parameter       = df_parameter,
       lld             = df_lld,
       analysis_method = df_analysis_method,
       reference       = df_referance,
       sample          = df_sample,
       sediment        = df_sediment)
}
