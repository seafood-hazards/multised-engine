# ── Database helpers ─────────────────────────────────────────────────────────
# Small shims replacing the connection boilerplate that opened every pipeline
# script. Nothing here changes what the steps do; it only removes the hardcoded
# path and makes the connection close on error as well as on success.

# Path to a generation's database for a given source.
slim_db_path <- function(source, db_dir = multised_db_dir()) {
  file.path(db_dir, paste0(source_stem(source), "_slim.sqlite"))
}

pilot_db_path <- function(source, db_dir = multised_db_dir()) {
  file.path(db_dir, paste0("pilot_", source_stem(source), ".sqlite"))
}

# Open a SQLite database with foreign keys on, as every script did.
#
# `must_exist = TRUE` gives a clear error rather than SQLite silently creating an
# empty database, which is the failure mode when `db_dir` is wrong.
multised_con <- function(path, must_exist = TRUE) {
  if (must_exist && !file.exists(path)) {
    stop("Database not found: ", path,
         "\nSet `db_dir` or options(multised.db_dir = ) to the directory ",
         "holding the databases.", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON;")
  con
}

slim_con <- function(source, db_dir = multised_db_dir(), must_exist = TRUE) {
  multised_con(slim_db_path(source, db_dir), must_exist = must_exist)
}

# The idempotent "add the column if this step has not run before" idiom used by
# every marking step.
add_column_if_missing <- function(con, table, column, type) {
  if (!column %in% DBI::dbListFields(con, table)) {
    DBI::dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN %s %s;",
                                table, column, type))
  }
  invisible(NULL)
}

# Progress reporting, gated on `verbose`.
msg <- function(verbose, ...) {
  if (isTRUE(verbose)) cat(..., sep = "")
  invisible(NULL)
}
