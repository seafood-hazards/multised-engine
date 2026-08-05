# ── Pilot step 5: create the pilot database and write the tables ─────────────
# Drops and recreates the source's pilot schema, then inserts the frames built by
# step 1 (and enriched by the geo step). Table sets and columns differ per source
# far more than in the later generations, since each vendor export has its own
# shape, so the schema is entirely per-source.

pilot_schema <- function(source) {
  switch(
    source,
    "4demon"    = pilot_schema_4demon(),
    "ices-dome" = pilot_schema_ices_dome(),
    "vannmiljo" = pilot_schema_vannmiljo(),
    "mudab"     = pilot_schema_mudab(),
    "mareano"   = pilot_schema_mareano(),
    stop("The pilot schema for ", sQuote(source), " is not converted yet.",
         call. = FALSE)
  )
}

pilot_create_tables <- function(tables, source, db_dir = multised_db_dir(),
                                verbose = TRUE) {
  check_source(source)
  schema <- pilot_schema(source)
  out_db <- pilot_db_path(source, db_dir)

  missing <- setdiff(schema$order, names(tables))
  if (length(missing)) {
    stop("The ", source, " pilot extract did not produce: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  con <- multised_con(out_db, must_exist = FALSE)
  on.exit(dbDisconnect(con), add = TRUE)
  dbExecute(con, "PRAGMA foreign_keys = ON;")

  # Drop in reverse dependency order so the foreign keys never dangle.
  for (tbl in rev(schema$order)) {
    dbExecute(con, sprintf("DROP TABLE IF EXISTS %s;", tbl))
  }
  for (tbl in schema$order) {
    dbExecute(con, schema$ddl[[tbl]])
  }
  # Write in dependency order. Some extracts carry build-only columns (e.g. the
  # ICES `row_count`) that the schema does not declare; drop them here.
  for (tbl in schema$order) {
    df <- tables[[tbl]]
    drop <- schema$drop_cols[[tbl]]
    if (!is.null(drop)) df <- df |> select(-any_of(drop))
    dbWriteTable(con, tbl, as.data.frame(df), append = TRUE)
  }

  counts <- data.frame(
    table = dbListTables(con),
    rows  = vapply(dbListTables(con),
                   function(t) dbGetQuery(con, paste0("SELECT COUNT(*) FROM ", t))[[1]],
                   numeric(1)),
    row.names = NULL)
  if (verbose) {
    for (i in seq_len(nrow(counts))) {
      cat(sprintf("  %-12s %d rows\n", counts$table[i], counts$rows[i]))
    }
  }
  invisible(counts)
}
