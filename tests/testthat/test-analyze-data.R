test_that("the analysis registry resolves to real functions", {
  tbl <- analysis_module_table()
  expect_equal(nrow(tbl), 26L)
  expect_setequal(unique(tbl$generation), c("clean", "merged", "refined"))
  for (f in tbl$fun) {
    expect_true(exists(f, mode = "function"), info = f)
  }
})

test_that("each generation has the documented module count", {
  expect_equal(nrow(analysis_modules("clean")), 6L)
  expect_equal(nrow(analysis_modules("merged")), 13L)
  expect_equal(nrow(analysis_modules("refined")), 7L)
})

test_that("background is the only multi-step module, and is ordered", {
  tbl <- analysis_module_table()
  multi <- unique(tbl$module[duplicated(tbl$module) & tbl$generation == "refined"])
  expect_equal(multi, "background")
  bg <- tbl[tbl$module == "background", ]
  expect_equal(bg$step, 1:6)
})

test_that("a module name is validated against the generation", {
  # grainsize exists for clean and merged, but not for refined
  expect_error(analyze_data("refined", module = "grainsize"),
               "no module")
  expect_error(analyze_data("clean", module = "hotspots"), "no module")
  expect_error(analyze_data("merged", module = c("a", "b")),
               "single module name")
})

test_that("steps only make sense within one module", {
  expect_error(analyze_data("refined", steps = 2), "`module` is required")
  expect_error(analyze_data("refined", module = "background", steps = 9),
               "has steps")
})

test_that("an unknown generation is rejected by match.arg", {
  expect_error(analyze_data("pilot"), "'arg' should be one of")
  expect_error(analyze_data("slim"), "'arg' should be one of")
})
