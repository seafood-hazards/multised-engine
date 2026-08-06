# ── Slim step 6: mark additional data ────────────────────────────────────────
# Adds `fe_exist` / `al_exist` / `org_exist` / `comp_exist` (0/1) to `subsample`,
# flagging whether the Fe/Al normalisers, organic carbon and grain-size
# composition are available for that sample.
#
# Identical for all five sources.

slim_mark_additional_data <- function(source, db_dir = multised_db_dir(),
                                      verbose = TRUE) {
  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Classify each measurement via the element category (step 3) ─────────
  # org_exist / comp_exist read element.category directly (organic carbon and
  # grain-size composition). fe_exist / al_exist still need the specific Fe vs Al
  # symbol, which the shared 'reference' category does not distinguish. Symbols are
  # cased differently per source (Fe vs FE), so match on the upper-cased symbol.
  el <- dbReadTable(con, "element") |> as_tibble() |>
    transmute(sym = str_to_upper(symbol), category)
  m <- dbReadTable(con, "measurement") |> as_tibble() |>
    transmute(subsample_id, sym = str_to_upper(symbol)) |>
    left_join(el, by = "sym")

  # ── 2. Per-subsample existence of normalisers / organic C / composition ────
  ex <- m |> group_by(subsample_id) |>
    summarise(fe_exist   = as.integer(any(sym == "FE")),
              al_exist   = as.integer(any(sym == "AL")),
              org_exist  = as.integer(any(category == "organic")),
              comp_exist = as.integer(any(category == "composition")),
              .groups = "drop")

  # ── 3. Write exist flags back to subsample (idempotent) ────────────────────
  for (col in c("fe_exist", "al_exist", "org_exist", "comp_exist")) {
    add_column_if_missing(con, "subsample", col, "INTEGER")
  }
  dbWriteTable(con, "qc_exist", ex, temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_exist ON qc_exist(subsample_id);")
  dbExecute(con, "
    UPDATE subsample SET
      fe_exist   = (SELECT fe_exist   FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
      al_exist   = (SELECT al_exist   FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
      org_exist  = (SELECT org_exist  FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id),
      comp_exist = (SELECT comp_exist FROM qc_exist q WHERE q.subsample_id = subsample.subsample_id);")

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  out <- dbGetQuery(con, "SELECT SUM(fe_exist) fe, SUM(al_exist) al,
                                 SUM(org_exist) org, SUM(comp_exist) comp,
                                 COUNT(*) total FROM subsample")
  if (verbose) {
    cat("subsample existence flags (count with each present / total):\n")
    print(out)
  }
  invisible(out)
}
