# ── Slim step 7: mark multi-layer / multi-core samplings ─────────────────────
# Adds `event.n_layers` + `event.multi_flag`, marking events with more than one
# subsample (a sliced core) versus a single grab. Derived from the data, not the
# tool code, since the same gear yields both.
#
# Identical for all five sources.

slim_mark_multi <- function(source, db_dir = multised_db_dir(), verbose = TRUE) {
  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Count layers (subsamples) per event ─────────────────────────────────
  # Each depth layer / core of a sampling event is one `subsample` row. An event
  # with more than one is a multi-layer/-core sampling (a sliced core) as opposed
  # to a single grab. Tool type alone does not determine this — the same gear code
  # yields both single- and multi-layer events — so it is derived from the data.
  lpe <- dbReadTable(con, "subsample") |> as_tibble() |>
    count(event_id, name = "n_layers")

  # ── 2. Write n_layers + multi_flag to event (idempotent) ───────────────────
  for (col in c("n_layers", "multi_flag")) {
    add_column_if_missing(con, "event", col, "INTEGER")
  }
  dbWriteTable(con, "qc_multi", lpe, temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_multi ON qc_multi(event_id);")
  dbExecute(con, "
    UPDATE event SET
      n_layers   = COALESCE((SELECT n_layers FROM qc_multi q WHERE q.event_id = event.event_id), 0),
      multi_flag = (COALESCE((SELECT n_layers FROM qc_multi q WHERE q.event_id = event.event_id), 0) > 1);")

  # ── 3. Verify ──────────────────────────────────────────────────────────────
  out <- dbGetQuery(con, "SELECT multi_flag, COUNT(*) n_events, SUM(n_layers) layers
                          FROM event GROUP BY multi_flag ORDER BY multi_flag;")
  if (verbose) {
    cat("event multi_flag:\n")
    print(out)
  }
  invisible(out)
}
