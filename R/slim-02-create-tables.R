# ── Slim step 2: create the slim database and write the tables ───────────────
# Drops and recreates the 7-table schema, then inserts the frames built by step
# 1. The schema is per-source because the wide tables differ (e.g. `measurement`
# carries `below_lld` for mareano, `operator`/`filtered` for vannmiljo,
# `basis`/`matrix`/`qflag`/... for ices-dome/mudab/4demon).
#
# This step REPLACES the database: it drops every slim table first, so all the
# marking columns added by steps 3-15 are lost and those steps must be re-run.

slim_schema <- function(source) {
  switch(
    source,
    "mareano"   = slim_schema_mareano(),
    "vannmiljo" = slim_schema_vannmiljo(),
    "ices-dome" = slim_schema_ices_dome(),
    "mudab"     = slim_schema_mudab(),
    "4demon"    = slim_schema_4demon()
  )
}

slim_create_tables <- function(tables, source, db_dir = multised_db_dir(),
                               verbose = TRUE) {
  check_source(source)
  tables <- check_slim_tables(tables, source)
  ddl <- slim_schema(source)

  # must_exist = FALSE: this step is what creates the database in the first place.
  con <- slim_con(source, db_dir, must_exist = FALSE)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Create target database and schema ───────────────────────────────────
  # Dropped in reverse dependency order so the foreign keys never dangle.
  for (tbl in rev(SLIM_TABLES)) {
    dbExecute(con, paste0("DROP TABLE IF EXISTS ", tbl, ";"))
  }
  for (tbl in SLIM_TABLES) {
    dbExecute(con, ddl[[tbl]])
  }

  # ── 2. Insert data ─────────────────────────────────────────────────────────
  for (tbl in SLIM_TABLES) {
    dbWriteTable(con, tbl, as.data.frame(tables[[tbl]]), append = TRUE)
  }

  # ── 3. Verify ──────────────────────────────────────────────────────────────
  out <- data.frame(
    table = dbListTables(con),
    rows  = vapply(dbListTables(con),
                   function(t) dbGetQuery(con, paste0("SELECT COUNT(*) FROM ", t))[[1]],
                   numeric(1)),
    row.names = NULL)
  if (verbose) {
    cat("Tables:", paste(out$table, collapse = ", "), "\n")
    for (i in seq_len(nrow(out))) {
      cat(sprintf("  %-15s %d rows\n", out$table[i], out$rows[i]))
    }
  }
  invisible(out)
}
