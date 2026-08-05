test_that("per-source generations require a source, combined ones refuse it", {
  expect_error(create_db("slim"), "single source key")
  expect_error(create_db("merged", source = "mareano"),
               "combines every source")
  expect_error(create_db("refined", source = "mudab"),
               "combines every source")
})

test_that("an unknown generation is rejected by match.arg", {
  expect_error(create_db("gold"), "'arg' should be one of")
})

test_that("generations that are not converted yet say so plainly", {
  # they must not silently do nothing
  expect_error(create_db("merged"), "not available through create_db")
  expect_error(create_db("clean", "mareano"), "not available through create_db")
})

test_that("the step registry matches the documented per-source coverage", {
  # steps 1-12 everywhere; 13 src_flag; 14 grain-size correction; 15 fines
  expect_equal(slim_steps("mareano")$step, c(1:12, 15L))
  expect_equal(slim_steps("4demon")$step, 1:13)
  expect_equal(slim_steps("vannmiljo")$step, 1:15)
  expect_equal(slim_steps("ices-dome")$step, 1:15)
  expect_equal(slim_steps("mudab")$step, c(1:12, 14L, 15L))
})

test_that("asking for a step a source does not have is an error", {
  # Mareano has no source-native flags and no grain-size correction
  expect_error(create_db("slim", "mareano", steps = 13),
               "do not apply to mareano")
  expect_error(create_db("slim", "4demon", steps = 15),
               "do not apply to 4demon")
})

test_that("every registered step function exists", {
  for (src in multised_sources()) {
    for (fun in slim_step_table()$fun) {
      expect_true(is.function(get(fun, envir = asNamespace("multised.engine"))),
                  info = fun)
    }
  }
})
