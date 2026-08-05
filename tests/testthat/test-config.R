test_that("the five source keys are stable", {
  expect_setequal(multised_sources(),
                  c("mareano", "vannmiljo", "ices-dome", "mudab", "4demon"))
})

test_that("source keys map onto database filename stems", {
  # the documented key keeps the hyphen; the database file uses an underscore
  expect_equal(source_stem("ices-dome"), "ices_dome")
  expect_equal(source_stem("mareano"), "mareano")
})

test_that("path helpers read their option and fall back to the project layout", {
  old <- options(multised.db_dir = NULL, multised.analysis_dir = NULL)
  on.exit(options(old), add = TRUE)

  expect_equal(multised_db_dir(), "data/db")
  expect_equal(multised_analysis_dir(), "data/analysis")

  options(multised.db_dir = file.path(tempdir(), "elsewhere"))
  expect_equal(multised_db_dir(), file.path(tempdir(), "elsewhere"))
})

test_that("database paths are built from the source and directory", {
  expect_equal(slim_db_path("ices-dome", "db"), file.path("db", "ices_dome_slim.sqlite"))
  expect_equal(pilot_db_path("4demon", "db"), file.path("db", "pilot_4demon.sqlite"))
})

test_that("an unknown source is rejected by name", {
  expect_error(check_source("atlantis"), "Unknown source")
  expect_error(check_source("atlantis"), "mareano")   # lists the valid ones
  expect_error(check_source(NULL), "single source key")
  expect_error(check_source(c("mareano", "mudab")), "single source key")
})

test_that("a missing database gives a directed error, not an empty one", {
  expect_error(multised_con(file.path(tempdir(), "nope.sqlite")),
               "Database not found")
})
