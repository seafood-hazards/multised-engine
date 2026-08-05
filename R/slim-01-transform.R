# ── Slim step 1: transform the pilot database into the slim tables ───────────
# Reads a source's pilot database and reshapes it into the shared 7-table slim
# schema. Each source has its own pilot structure, so the body is per-source.
#
# The scripts this replaces built the tables as loose `df_*` globals that step 2
# then picked up, which is why they had to be sourced together in one session.
# Here step 1 returns them, and step 2 takes them as an argument.

SLIM_TABLES <- c("element", "dataset", "site", "event",
                 "method", "subsample", "measurement")

# Fail early and clearly if a per-source transform forgets one of the 7 tables.
check_slim_tables <- function(tables, source) {
  missing <- setdiff(SLIM_TABLES, names(tables))
  if (length(missing)) {
    stop("The ", source, " transform did not produce: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  tables[SLIM_TABLES]
}

slim_transform <- function(source, db_dir = multised_db_dir(), verbose = TRUE) {
  check_source(source)
  transform <- switch(
    source,
    "mareano"   = slim_transform_mareano,
    "vannmiljo" = slim_transform_vannmiljo,
    "ices-dome" = slim_transform_ices_dome,
    "mudab"     = slim_transform_mudab,
    "4demon"    = slim_transform_4demon
  )

  pilot <- pilot_db_path(source, db_dir)
  con_src <- multised_con(pilot)
  on.exit(dbDisconnect(con_src), add = TRUE)

  tables <- check_slim_tables(transform(con_src), source)

  if (verbose) {
    cat("transformed from ", basename(pilot), ":\n", sep = "")
    for (nm in names(tables)) {
      cat(sprintf("  %-13s %d rows\n", nm, nrow(tables[[nm]])))
    }
  }
  invisible(tables)
}
