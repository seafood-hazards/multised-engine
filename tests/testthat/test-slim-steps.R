# The marking steps run against a small fixture database (helper-fixture.R), so
# these tests do not need the real, gitignored databases.

test_that("step 3 categorises every element by its symbol", {
  db <- make_fixture_db()
  out <- slim_categorize("mareano", db_dir = dirname(db), verbose = FALSE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  cat_of <- function(sym) {
    DBI::dbGetQuery(con, sprintf("SELECT category FROM element WHERE symbol='%s'", sym))[[1]]
  }
  expect_equal(cat_of("CU"), "target")
  expect_equal(cat_of("FE"), "reference")
  expect_equal(cat_of("Clay"), "composition")
  expect_s3_class(out, "data.frame")
})

test_that("step 4 flags out-of-area sites and impossible values", {
  db <- make_fixture_db()
  slim_categorize("mareano", db_dir = dirname(db), verbose = FALSE)
  suppressWarnings(
    slim_quality_control("mareano", db_dir = dirname(db), verbose = FALSE))

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))

  # site 2 is at lat 5, outside the European box
  area <- DBI::dbGetQuery(con, "SELECT site_id, area_flag FROM site ORDER BY site_id")
  expect_true(is.na(area$area_flag[1]))
  expect_equal(area$area_flag[2], "outside_europe")

  inv <- DBI::dbGetQuery(con,
    "SELECT measurement_id, invalid_flag FROM measurement ORDER BY measurement_id")
  expect_equal(inv$invalid_flag[5], "negative")     # value -5
  expect_equal(inv$invalid_flag[6], "over_range")   # 1e7 mg/kg > 100 %
  expect_true(is.na(inv$invalid_flag[1]))
})

test_that("step 5 separates repeated values from technical replicates", {
  db <- make_fixture_db()
  slim_mark_duplicates("mareano", db_dir = dirname(db), verbose = FALSE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  dup <- DBI::dbGetQuery(con,
    "SELECT measurement_id, dup_flag FROM measurement ORDER BY measurement_id")

  # measurements 1 and 2 are the same element/value on one occasion
  expect_equal(dup$dup_flag[1], "duplicate")
  expect_equal(dup$dup_flag[2], "duplicate")
  expect_true(is.na(dup$dup_flag[3]))   # a singleton stays unflagged
})

test_that("step 7 marks a sliced core but not a single grab", {
  db <- make_fixture_db()
  slim_mark_multi("mareano", db_dir = dirname(db), verbose = FALSE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  ev <- DBI::dbGetQuery(con,
    "SELECT event_id, n_layers, multi_flag FROM event ORDER BY event_id")

  expect_equal(ev$n_layers, c(2L, 1L))
  expect_equal(ev$multi_flag, c(1L, 0L))
})

test_that("step 9 standardises chemistry to mg/kg and composition to %", {
  db <- make_fixture_db()
  slim_categorize("mareano", db_dir = dirname(db), verbose = FALSE)
  slim_add_converted_value("mareano", db_dir = dirname(db), verbose = FALSE)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  m <- DBI::dbGetQuery(con,
    "SELECT measurement_id, symbol, value, value_std, unit_std
     FROM measurement ORDER BY measurement_id")

  # mg/kg chemistry passes through unchanged
  expect_equal(m$value_std[1], 20)
  expect_equal(m$unit_std[1], "mg/kg")
  # composition converts mg/kg -> % (40 / 1e6 * 100)
  expect_equal(m$unit_std[4], "%")
  expect_equal(m$value_std[4], 40 / 1e6 * 1e2)
})

test_that("the steps are idempotent", {
  db <- make_fixture_db()
  run <- function() {
    slim_categorize("mareano", db_dir = dirname(db), verbose = FALSE)
    slim_mark_multi("mareano", db_dir = dirname(db), verbose = FALSE)
  }
  run()
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  first <- DBI::dbReadTable(con, "event")
  DBI::dbDisconnect(con)

  run()   # again
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  expect_equal(DBI::dbReadTable(con, "event"), first)
})

test_that("a step that needs an earlier one says which is missing", {
  db <- make_fixture_db()
  expect_error(slim_mark_range("mareano", db_dir = dirname(db), verbose = FALSE),
               "value_std is missing")
})

test_that("step 14 rejects sources that have no grain-size correction", {
  expect_error(slim_correct_grainsize("mareano"), "applies to ices-dome")
  expect_error(slim_derive_fines("4demon"), "all but 4demon")
  expect_error(slim_mark_source_specific("mareano"), "no source-specific flags")
})
