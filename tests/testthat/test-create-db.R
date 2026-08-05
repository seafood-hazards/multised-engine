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
  expect_error(create_db("refined"), "not available through create_db")
  expect_error(create_db("pilot", "mareano"), "not available through create_db")
})

test_that("the clean generation runs three steps in sequence", {
  expect_equal(clean_step_table()$step, 1:3)
  expect_equal(clean_step_table()$name, c("harmonise", "clean", "annotate"))
  # clean has no step 4; asking for one is an error, not a silent no-op
  expect_error(create_db("clean", "mareano", steps = 4), "steps 1-3")
})

test_that("every clean step function exists", {
  for (fun in clean_step_table()$fun) {
    expect_true(is.function(get(fun, envir = asNamespace("multised.engine"))),
                info = fun)
  }
})

test_that("each source has a clean spec for every step", {
  for (src in multised_sources()) {
    expect_type(clean_harmonise_spec(src), "list")
    expect_type(clean_annotate_spec(src), "list")
    expect_true(!is.null(clean_harmonise_spec(src)$depth_to_cm), info = src)
  }
  # 4Demon has no grain-size, so no grain-size-fraction builder
  expect_null(clean_annotate_spec("4demon")$gsf)
  expect_true(is.function(clean_annotate_spec("mareano")$gsf))
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
