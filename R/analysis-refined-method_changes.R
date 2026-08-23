# ── Analysis, refined generation: background ─────────────────────────────
# The method-revision comparison. Reads the frozen pre-revision baseline
# (inst/extdata/method-baseline/, the background outputs exactly as published in
# multised-refined v0.8.0) alongside the current outputs of this same module, and writes
# the difference. It derives nothing of its own: every number on both sides came out of the
# pipeline, which is what keeps the method-changes page from being a page of typed figures.
#
# It must run LAST in the module, since it reads what steps 1-6 have just written.

analysis_refined_method_changes <- function(db_dir = multised_db_dir(),
                                            out_dir = multised_analysis_dir(),
                                            verbose = TRUE) {
  # Outputs -> data/analysis/background/ (gitignored):
  #   refined_method_changes.csv       long: measure x element x fraction, before / after
  #   refined_method_changes_meta.csv  what the two sides are
  #   refined_censoring.csv            the below-LOQ share behind the withheld verdicts,
  #                                    copied out of inst/extdata so the site can show it

  adir <- file.path(out_dir, "background")
  dir.create(adir, recursive = TRUE, showWarnings = FALSE)

  base_dir <- system.file("extdata", "method-baseline", package = "multised")
  if (!nzchar(base_dir)) base_dir <- file.path("inst", "extdata", "method-baseline")
  if (!dir.exists(base_dir))
    stop("the pre-revision baseline is missing (looked at ", base_dir, "); see ",
         "inst/extdata/method-baseline/README.md", call. = FALSE)

  elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  CATS <- c("bulk", "sieved63", "sieved20")

  rd <- function(dir, f) {
    p <- file.path(dir, f)
    if (!file.exists(p)) return(NULL)
    read_csv(p, show_col_types = FALSE) |>
      mutate(symbol = as.character(symbol), cat = as.character(cat))
  }

  # one measure = one column of one file, taken from both sides and matched on element x
  # fraction. `higher_is` says nothing about better or worse, only which way the number ran.
  measures <- tribble(
    ~file,                             ~column,           ~measure,
    "refined_pristine_summary.csv",    "pct_classifiable", "% classifiable",
    "refined_pristine_summary.csv",    "pct_ef",           "% pristine (EF rule)",
    "refined_pristine_summary.csv",    "pct_strict",       "% pristine (strict rule)",
    "refined_ef_dist.csv",             "ef_p50",           "median EF",
    "refined_ef_dist.csv",             "pct_lt1",          "% adequate (EF < 1)",
    "refined_ef_background.csv",       "bg_ratio_al",      "EF background, metal/Al",
    "refined_mixture_components.csv",  "threshold",        "mixture threshold, mg/kg"
  )

  pull_one <- function(dir, file, column) {
    d <- rd(dir, file)
    if (is.null(d) || !column %in% names(d)) return(NULL)
    d |> select(symbol, cat, value = all_of(column))
  }

  changes <- pmap_dfr(measures, function(file, column, measure) {
    before <- pull_one(base_dir, file, column)
    after  <- pull_one(adir,     file, column)
    if (is.null(before) && is.null(after)) return(NULL)
    full_join(before |> rename(before = value),
              after  |> rename(after  = value), by = c("symbol", "cat")) |>
      mutate(measure = measure)
  })

  # what each element's verdicts are subject to now, so a reader can see WHY a number went
  # to NA rather than only that it did
  withheld <- refined_withheld_elements()
  cur_bg   <- rd(adir, "refined_ef_background.csv")

  changes <- changes |>
    # a row that was absent on both sides says nothing; a group too sparse to fit before
    # and still too sparse now is not a method change
    filter(cat %in% CATS, !(is.na(before) & is.na(after))) |>
    mutate(
      symbol = factor(symbol, levels = elem_levels),
      cat    = factor(cat, levels = CATS),
      before = signif(before, 4),
      after  = signif(after, 4),
      change = case_when(
        is.na(after)                 ~ "withdrawn",
        is.na(before)                ~ "new",
        before == after              ~ "unchanged",
        before == 0                  ~ "changed",
        TRUE ~ sprintf("%+.0f%%", 100 * (after - before) / abs(before))),
      reason = case_when(
        as.character(symbol) %in% withheld ~ "verdicts withheld: over half the measurements were below the LOQ and removed upstream",
        measure == "% classifiable"        ~ "aluminium-basis restriction: samples off their fraction's basis are no longer classified",
        measure == "% pristine (strict rule)" ~ "aluminium-basis restriction, and an unusable mixture threshold now drops out of the rule",
        grepl("^mixture", measure)         ~ "k selected by BIC; an unseparated threshold is now marked unusable",
        TRUE                               ~ "aluminium-basis restriction: the reference is computed within one measurement basis")) |>
    arrange(measure, symbol, cat) |>
    select(measure, symbol, cat, before, after, change, reason)

  meta <- tibble(
    before = "multised-refined v0.8.0, the last release before the aluminium-basis restriction",
    after  = "the current outputs of the background module",
    changes = paste("Al measurement basis restricted per fraction;",
                    "mixture k selected by BIC and unusable thresholds dropped from the strict rule;",
                    "Se and Mo verdicts withheld for below-LOQ censoring;",
                    "a second EF reference (offshore P90) reported beside the median"),
    source = "generated from inst/extdata/method-baseline/, not typed")

  censoring <- refined_censoring_table(source_filter = NULL) |>
    as_tibble() |>
    mutate(withheld = source == "ALL" & pct_censored > refined_censoring_limit())

  write_csv(changes,   file.path(adir, "refined_method_changes.csv"))
  write_csv(meta,      file.path(adir, "refined_method_changes_meta.csv"))
  write_csv(censoring, file.path(adir, "refined_censoring.csv"))

  if (verbose) {
    cat("method-change comparison written to", adir, "\n\n")
    cat("bulk, the verdict measures:\n")
    changes |> filter(cat == "bulk", grepl("pristine|classifiable", measure)) |>
      select(measure, symbol, before, after, change) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(adir)
}
