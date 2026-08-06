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

test_that("every source is converted for the pilot generation", {
  expect_setequal(PILOT_CONVERTED, multised_sources())
})

test_that("an unconverted pilot source would say so plainly", {
  # All five sources are converted, so this guards the dispatch itself: a source
  # reaching the parser or schema without an entry must fail loudly rather than
  # silently build nothing.
  expect_error(pilot_extract("gold"), "not converted yet")
  expect_error(pilot_schema("gold"), "not converted yet")
  expect_error(create_db_pilot("gold", NULL, tempdir(), FALSE),
               "not available through create_db")
})

test_that("the pilot registry keeps the original step numbering", {
  # 1 parse, 4 geo, 5 write -- matching the scripts it replaces
  expect_equal(pilot_step_table()$step, c(1L, 4L, 5L))
  expect_equal(pilot_step_table()$name, c("extract", "geo", "write"))
  # steps 4 and 5 consume what step 1 builds, so step 1 cannot be skipped
  expect_error(create_db("pilot", "4demon", steps = 5),
               "step 1 cannot be skipped")
})

test_that("seastamp_dir is configurable and reaches both geo steps", {
  expect_equal(multised_seastamp_dir(), "data/seastamp")
  old <- options(multised.seastamp_dir = "/somewhere/ref")
  on.exit(options(old), add = TRUE)
  expect_equal(multised_seastamp_dir(), "/somewhere/ref")
  expect_equal(seastamp_data()$depth,
               "/somewhere/ref/gebco/GEBCO_2024_sub_ice_topo.nc")
  options(old)
  # the argument must be accepted by the public verb, not just the internals
  expect_true("seastamp_dir" %in% names(formals(create_db)))
  for (f in c(create_db_pilot, create_db_clean, pilot_geo_enrich,
              clean_geo_enrich, seastamp_enrich)) {
    expect_true("seastamp_dir" %in% names(formals(f)))
  }
})

test_that("each source has a pilot geo spec", {
  for (src in multised_sources()) {
    spec <- pilot_geo_spec(src)
    expect_true(all(c("frame", "lon", "lat") %in% names(spec)), info = src)
  }
})

test_that("the refined generation runs six steps and takes no source", {
  expect_equal(refine_step_table()$step, 1:6)
  expect_equal(refine_step_table()$name,
               c("restructure", "normaliser", "ratios", "aquaculture",
                 "repeat_sites", "summary"))
  expect_error(create_db("refined", source = "mareano"), "combines every source")
  expect_error(create_db("refined", steps = 7), "steps 1-6")
})

test_that("every refined step function exists", {
  for (fun in refine_step_table()$fun) {
    expect_true(is.function(get(fun, envir = asNamespace("multised.engine"))),
                info = fun)
  }
})

test_that("the refined mart keeps the 7 targets and the 3 normalisers", {
  expect_setequal(REFINE_TARGETS, c("CO", "CU", "I", "MN", "MO", "SE", "ZN"))
  expect_setequal(REFINE_NORMS, c("FE", "AL", "CORG"))
  # the normalisers are deliberately NOT targets: they become normaliser columns
  expect_length(intersect(REFINE_TARGETS, REFINE_NORMS), 0)
})

test_that("the merged generation runs five steps and takes no source", {
  expect_equal(merge_step_table()$step, 1:5)
  expect_equal(merge_step_table()$name,
               c("union", "dedup", "finalise", "mark_outliers", "summary"))
  expect_error(create_db("merged", source = "mareano"), "combines every source")
  expect_error(create_db("merged", steps = 6), "steps 1-5")
})

test_that("every merged step function exists", {
  for (fun in merge_step_table()$fun) {
    expect_true(is.function(get(fun, envir = asNamespace("multised.engine"))),
                info = fun)
  }
})

test_that("the merge source preference order is the documented one", {
  # Mareano > 4Demon > MUDAB > Vannmiljo > ICES-DOME
  expect_equal(merge_sources()$Source[order(merge_sources()$pref)],
               c("Mareano", "4Demon", "MUDAB", "Vannmiljø", "ICES-DOME"))
  # element is the shared vocabulary: no keys prefixed
  expect_length(merge_key_cols()$element, 0)
})

test_that("the clean generation runs three steps in sequence", {
  expect_equal(clean_step_table()$step, 1:4)
  expect_equal(clean_step_table()$name, c("harmonise", "clean", "annotate", "geo_enrich"))
  # clean has no step 5; asking for one is an error, not a silent no-op
  expect_error(create_db("clean", "mareano", steps = 5), "steps 1-4")
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
