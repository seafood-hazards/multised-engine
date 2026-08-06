# A minimal Mareano-shaped slim database, enough to exercise the marking steps
# without needing the real (multi-GB, gitignored) databases.
#
# Two elements from two categories, one site, one event with two layers, and a
# handful of measurements including a negative, an over-range and a duplicate
# pair, so each step has something to find.

make_fixture_db <- function(dir = tempfile()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(dir, "mareano_slim.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))

  ddl <- slim_schema_mareano()
  for (tbl in c("element", "dataset", "site", "event",
                "method", "subsample", "measurement")) {
    DBI::dbExecute(con, ddl[[tbl]])
  }

  DBI::dbWriteTable(con, "element", data.frame(
    symbol  = c("CU", "FE", "Clay", "Silt"),
    element = c("Copper", "Iron", "Clay", "Silt"),
    stringsAsFactors = FALSE), append = TRUE)

  DBI::dbWriteTable(con, "dataset", data.frame(
    dataset_id = 1L, source = "Mareano", country = "Norway",
    institute = "IMR", dataset_name = "test",
    stringsAsFactors = FALSE), append = TRUE)

  DBI::dbWriteTable(con, "site", data.frame(
    site_id = 1:2, latitude = c(60.0, 5.0), longitude = c(5.0, -60.0),
    depth = c(100, 200), country = "Norway", country_code = "NOR",
    dist_to_coast = 10L, municipality = NA_character_, sea_name = NA_character_,
    stringsAsFactors = FALSE), append = TRUE)

  DBI::dbWriteTable(con, "event", data.frame(
    event_id = 1:2, dataset_id = 1L, site_id = 1:2,
    sampling_tool = "grab", year = 2020L, date = "2020-01-01",
    stringsAsFactors = FALSE), append = TRUE)

  DBI::dbWriteTable(con, "method", data.frame(
    method_id = 1L, symbol = "CU", method = "ICP-MS", lab = "IMR",
    lld = 0.5, comment = NA_character_,
    stringsAsFactors = FALSE), append = TRUE)

  # event 1 has two layers (multi), event 2 a single grab
  DBI::dbWriteTable(con, "subsample", data.frame(
    subsample_id = 1:3, event_id = c(1L, 1L, 2L),
    depth_from = c(0L, 5L, 0L), depth_to = c(5L, 10L, 5L),
    stringsAsFactors = FALSE), append = TRUE)

  DBI::dbWriteTable(con, "measurement", data.frame(
    measurement_id = 1:6,
    subsample_id   = c(1L, 1L, 1L, 2L, 3L, 3L),
    symbol         = c("CU", "CU", "FE", "Clay", "CU", "Silt"),
    #                   dup pair ^^^^^^^^        negative  over-range
    value          = c(20, 20, 30000, 40, -5, 1e7),
    unit           = "mg/kg",
    below_lld      = c(0L, 0L, 0L, 0L, 0L, 0L),
    method_id      = 1L,
    stringsAsFactors = FALSE), append = TRUE)

  path
}
