# ── Public entry point: build a database generation ──────────────────────────

# The slim step registry. Step numbers are fixed per concern, so a source runs
# only the later steps that apply to it (see the slim step table in CLAUDE.md).
slim_step_table <- function() {
  all_sources <- multised_sources()
  tibble::tribble(
    ~step, ~name,                  ~fun,                       ~sources,
    1L,  "transform_data",       "slim_transform",             all_sources,
    2L,  "create_tables",        "slim_create_tables",         all_sources,
    3L,  "categorize",           "slim_categorize",            all_sources,
    4L,  "quality_control",      "slim_quality_control",       all_sources,
    5L,  "mark_duplicates",      "slim_mark_duplicates",       all_sources,
    6L,  "mark_additional_data", "slim_mark_additional_data",  all_sources,
    7L,  "mark_multi",           "slim_mark_multi",            all_sources,
    8L,  "mark_below_loq",       "slim_mark_below_loq",        all_sources,
    9L,  "add_converted_value",  "slim_add_converted_value",   all_sources,
    10L, "mark_range",           "slim_mark_range",            all_sources,
    11L, "mark_below_loq_num",   "slim_mark_below_loq_num",    all_sources,
    12L, "mark_weight_basis",    "slim_mark_weight_basis",     all_sources,
    13L, "mark_source_specific", "slim_mark_source_specific",
    c("vannmiljo", "ices-dome", "4demon"),
    14L, "correct_grainsize",    "slim_correct_grainsize",
    c("vannmiljo", "ices-dome", "mudab"),
    15L, "derive_fines",         "slim_derive_fines",
    c("mareano", "vannmiljo", "ices-dome", "mudab")
  )
}

#' Which slim steps apply to a source
#'
#' Steps 1-12 are common to every source; step 13 onward is source-specific and
#' present only where a source has something extra to fold in or derive. Mareano
#' runs 1-12 and 15 (no native flags, clean grain-size); 4Demon runs 1-13 only
#' (no grain-size).
#'
#' @param source One of [multised_sources()].
#'
#' @return A data frame of the applicable steps, with columns `step`, `name` and
#'   `fun`.
#' @export
#' @examples
#' slim_steps("mareano")
#' slim_steps("4demon")
slim_steps <- function(source) {
  check_source(source)
  tbl <- slim_step_table()
  keep <- vapply(tbl$sources, function(s) source %in% s, logical(1))
  tbl[keep, c("step", "name", "fun")]
}

#' Build a database generation
#'
#' Runs a pipeline generation end to end. The first three generations
#' (`"pilot"`, `"slim"`, `"clean"`) produce one database per source and require
#' `source`; the last two (`"merged"`, `"refined"`) combine all five and must not
#' be given one.
#'
#' Every step is idempotent, so re-running the whole generation, or a subset via
#' `steps`, is safe.
#'
#' @param generation The generation to build: `"pilot"`, `"slim"`, `"clean"`,
#'   `"merged"` or `"refined"`.
#' @param source For the per-source generations, one of [multised_sources()].
#'   Must be `NULL` for `"merged"` and `"refined"`.
#' @param steps Optional subset of step numbers, for example `steps = 3:12`.
#'   Steps 1 and 2 form one unit (the parse and the write), so requesting either
#'   runs both. Defaults to every step that applies to the source.
#' @param db_dir Directory holding the databases. Defaults to
#'   [multised_db_dir()].
#' @param seastamp_dir Directory holding the seastamp reference datasets, used by
#'   the two geo steps (pilot step 4 and clean step 4) and ignored by every
#'   other generation. Defaults to [multised_seastamp_dir()].
#' @param verbose Print each step's summary as it runs.
#'
#' @return Invisibly, a named list with one element per step run, holding that
#'   step's summary.
#' @export
#' @examples
#' \dontrun{
#' # the whole slim generation for one source
#' create_db("slim", "mareano")
#'
#' # re-run only the grain-size steps
#' create_db("slim", "ices-dome", steps = 14:15)
#'
#' # against databases held somewhere else
#' create_db("slim", "mudab", db_dir = "~/sediment/db")
#'
#' # geo-enrich from a reference tree outside the project
#' create_db("pilot", "mareano", seastamp_dir = "~/seastamp")
#'
#' # skip the geo step where seastamp is not installed
#' create_db("pilot", "mareano", steps = c(1, 5))
#' }
create_db <- function(generation = c("pilot", "slim", "clean",
                                     "merged", "refined"),
                      source = NULL,
                      steps = NULL,
                      db_dir = multised_db_dir(),
                      seastamp_dir = multised_seastamp_dir(),
                      verbose = TRUE) {
  generation <- match.arg(generation)
  per_source <- generation %in% c("pilot", "slim", "clean")

  if (per_source) {
    check_source(source)
  } else if (!is.null(source)) {
    stop("The ", generation, " generation combines every source, so `source` ",
         "must be NULL.", call. = FALSE)
  }

  switch(
    generation,
    pilot  = create_db_pilot(source, steps, db_dir, verbose, seastamp_dir = seastamp_dir),
    slim   = create_db_slim(source, steps, db_dir, verbose),
    clean  = create_db_clean(source, steps, db_dir, verbose, seastamp_dir = seastamp_dir),
    merged  = create_db_merged(steps, db_dir, verbose),
    refined = create_db_refined(steps, db_dir, verbose),
    stop("The ", generation, " generation is not available through create_db() ",
         "yet; \"slim\", \"clean\", \"merged\" and \"refined\" are. Run the ",
         "scripts under R/", generation, "/ from the project root in the ",
         "meantime.", call. = FALSE)
  )
}

# The refine step registry. Step 6 is reporting only and also writes CSVs.
refine_step_table <- function() {
  tibble::tribble(
    ~step, ~name,           ~fun,                    ~writes_csv,
    1L,  "restructure",   "refine_restructure",     FALSE,
    2L,  "normaliser",    "refine_normaliser",      FALSE,
    3L,  "ratios",        "refine_ratios",          FALSE,
    4L,  "aquaculture",   "refine_aquaculture",     FALSE,
    5L,  "repeat_sites",  "refine_repeat_sites",    FALSE,
    6L,  "summary",       "refine_summary",         TRUE
  )
}

create_db_refined <- function(steps, db_dir, verbose,
                              analysis_dir = multised_analysis_dir()) {
  applicable <- refine_step_table()

  if (!is.null(steps)) {
    steps <- as.integer(steps)
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("The refined generation has steps 1-6; got ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }

  out <- list()
  for (i in seq_len(nrow(applicable))) {
    step <- applicable$step[i]
    name <- applicable$name[i]
    fun  <- get(applicable$fun[i], mode = "function")
    msg(verbose, "\n== refined step ", step, ": ", name, " ==\n")
    out[[name]] <- if (applicable$writes_csv[i]) {
      fun(db_dir = db_dir, analysis_dir = analysis_dir, verbose = verbose)
    } else {
      fun(db_dir = db_dir, verbose = verbose)
    }
  }
  invisible(out)
}

# The merge step registry. Steps 2 and 4 also write analysis CSVs, so they take
# `analysis_dir` as well; the others ignore it.
merge_step_table <- function() {
  tibble::tribble(
    ~step, ~name,            ~fun,                  ~writes_csv,
    1L,  "union",          "merge_union",          FALSE,
    2L,  "dedup",          "merge_dedup",          TRUE,
    3L,  "finalise",       "merge_finalise",       FALSE,
    4L,  "mark_outliers",  "merge_mark_outliers",  TRUE,
    5L,  "summary",        "merge_summary",        TRUE
  )
}

create_db_merged <- function(steps, db_dir, verbose,
                             analysis_dir = multised_analysis_dir()) {
  applicable <- merge_step_table()

  if (!is.null(steps)) {
    steps <- as.integer(steps)
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("The merged generation has steps 1-5; got ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }

  out <- list()
  for (i in seq_len(nrow(applicable))) {
    step <- applicable$step[i]
    name <- applicable$name[i]
    fun  <- get(applicable$fun[i], mode = "function")
    msg(verbose, "\n== merged step ", step, ": ", name, " ==\n")
    out[[name]] <- if (applicable$writes_csv[i]) {
      fun(db_dir = db_dir, analysis_dir = analysis_dir, verbose = verbose)
    } else {
      fun(db_dir = db_dir, verbose = verbose)
    }
  }
  invisible(out)
}

# The clean step registry. Unlike slim's marking steps, these run in strict
# sequence on a database step 1 rebuilds from scratch, so a subset only makes
# sense when the earlier steps have already run.
clean_step_table <- function() {
  tibble::tribble(
    ~step, ~name,        ~fun,
    1L,  "harmonise",  "clean_harmonise",
    2L,  "clean",      "clean_clean",
    3L,  "annotate",   "clean_annotate",
    # Step 4 shells out to the external seastamp CLI and needs its reference
    # datasets, so it is the one clean step that can fail for environmental
    # reasons; skip it with steps = 1:3 if the tool is not installed.
    4L,  "geo_enrich", "clean_geo_enrich"
  )
}

create_db_clean <- function(source, steps, db_dir, verbose,
                            seastamp_dir = multised_seastamp_dir()) {
  applicable <- clean_step_table()

  if (!is.null(steps)) {
    steps <- as.integer(steps)
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("The clean generation has steps 1-4; got ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }

  out <- list()
  for (i in seq_len(nrow(applicable))) {
    step <- applicable$step[i]
    name <- applicable$name[i]
    fun  <- get(applicable$fun[i], mode = "function")
    msg(verbose, "\n== ", source, " clean step ", step, ": ", name, " ==\n")
    # Only the geo step reads the seastamp reference tree.
    out[[name]] <- if (name == "geo_enrich") {
      fun(source, db_dir = db_dir, seastamp_dir = seastamp_dir, verbose = verbose)
    } else {
      fun(source, db_dir = db_dir, verbose = verbose)
    }
  }
  invisible(out)
}

create_db_slim <- function(source, steps, db_dir, verbose) {
  applicable <- slim_steps(source)

  if (is.null(steps)) {
    steps <- applicable$step
  } else {
    steps <- as.integer(steps)
    # 1 parses the pilot database into frames, 2 writes them; neither is useful
    # without the other.
    if (any(steps %in% 1:2)) steps <- sort(union(steps, 1:2))
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("Step(s) ", paste(unknown, collapse = ", "), " do not apply to ",
           source, ". Applicable steps: ",
           paste(applicable$step, collapse = ", "), call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }

  out <- list()

  if (all(1:2 %in% applicable$step)) {
    msg(verbose, "\n== ", source, " step 1-2: transform + create tables ==\n")
    tables <- slim_transform(source, db_dir = db_dir, verbose = verbose)
    out[["create_tables"]] <- slim_create_tables(tables, source,
                                                 db_dir = db_dir,
                                                 verbose = verbose)
    applicable <- applicable[!applicable$step %in% 1:2, ]
  }

  for (i in seq_len(nrow(applicable))) {
    step <- applicable$step[i]
    name <- applicable$name[i]
    fun  <- get(applicable$fun[i], mode = "function")
    msg(verbose, "\n== ", source, " step ", step, ": ", name, " ==\n")
    out[[name]] <- fun(source, db_dir = db_dir, verbose = verbose)
  }

  invisible(out)
}

# ── Pilot ────────────────────────────────────────────────────────────────────
# Only 4Demon is converted so far; the other four still run as scripts. The step
# numbers keep the original script numbering (1 parse, 4 geo, 5 write) so the
# registry lines up with the files it replaces.
PILOT_CONVERTED <- c("4demon", "ices-dome", "vannmiljo", "mudab", "mareano")

pilot_step_table <- function() {
  tibble::tribble(
    ~step, ~name,      ~fun,
    1L,  "extract",  "pilot_extract",
    4L,  "geo",      "pilot_geo",
    5L,  "write",    "pilot_create_tables"
  )
}

pilot_extract <- function(source, raw_dir = multised_raw_dir(), verbose = TRUE) {
  switch(
    source,
    "4demon"    = pilot_extract_4demon(raw_dir = raw_dir, verbose = verbose),
    "ices-dome" = pilot_extract_ices_dome(raw_dir = raw_dir, verbose = verbose),
    "vannmiljo" = pilot_extract_vannmiljo(raw_dir = raw_dir, verbose = verbose),
    "mudab"     = pilot_extract_mudab(raw_dir = raw_dir, verbose = verbose),
    "mareano"   = pilot_extract_mareano(raw_dir = raw_dir, verbose = verbose),
    stop("The pilot parser for ", sQuote(source), " is not converted yet.",
         call. = FALSE)
  )
}

create_db_pilot <- function(source, steps, db_dir, verbose,
                            raw_dir = multised_raw_dir(),
                            seastamp_dir = multised_seastamp_dir()) {
  if (!source %in% PILOT_CONVERTED) {
    stop("The pilot generation is not available through create_db() for ",
         sQuote(source), " yet; only ", paste(sQuote(PILOT_CONVERTED), collapse = ", "),
         " is. Run the scripts under R/pilot/", source,
         "/ from the project root in the meantime.", call. = FALSE)
  }

  applicable <- pilot_step_table()
  if (!is.null(steps)) {
    steps <- as.integer(steps)
    unknown <- setdiff(steps, applicable$step)
    if (length(unknown)) {
      stop("The pilot generation has steps ",
           paste(applicable$step, collapse = ", "), "; got ",
           paste(unknown, collapse = ", "), ".", call. = FALSE)
    }
    applicable <- applicable[applicable$step %in% steps, ]
  }
  # The parse feeds the geo step and the write, so it cannot be skipped when
  # either of those runs.
  if (nrow(applicable) && !1L %in% applicable$step) {
    stop("Pilot steps 4 and 5 consume the frames step 1 builds, so step 1 ",
         "cannot be skipped.", call. = FALSE)
  }

  msg(verbose, "\n== ", source, " pilot step 1: extract ==\n")
  tables <- pilot_extract(source, raw_dir = raw_dir, verbose = verbose)

  if (4L %in% applicable$step) {
    spec <- pilot_geo_spec(source)
    frame <- sub("^df_", "", spec$frame)
    msg(verbose, "\n== ", source, " pilot step 4: geo (seastamp) ==\n")
    tables[[frame]] <- pilot_geo_enrich(tables[[frame]], spec$lon, spec$lat,
                                        country_col = spec$country_col,
                                        seastamp_dir = seastamp_dir, verbose = verbose)
  }

  out <- list(extract = vapply(tables, nrow, numeric(1)))
  if (5L %in% applicable$step) {
    msg(verbose, "\n== ", source, " pilot step 5: write ==\n")
    out$write <- pilot_create_tables(tables, source, db_dir = db_dir,
                                     verbose = verbose)
  }
  invisible(out)
}
