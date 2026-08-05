# ── Refine step 5: repeat-sampled-location grouping on `site` ────────────────
# Adds two columns to `site`, carrying the repeat-sampled-sites idea as a
# reusable fact:
#
#   repeat_group : a location cell key, latitude/longitude rounded to GRID_DP dp
#                  (2 dp ~= 1.1 km, the analysis grid). Nearby 3 dp sites that are
#                  really the same station share a cell.
#   n_years      : the number of DISTINCT sampling years at that cell, counted over
#                  ALL events in the cell (fraction-agnostic: this is about WHEN the
#                  location was sampled, not the chemistry).
#
# A location sampled in several years is what later analyses use for temporal /
# downcore work; the THRESHOLD ("repeat if n_years >= k") is a decision left to
# those analyses, so only the count is stored here.

refine_repeat_sites <- function(db_dir = multised_db_dir(), verbose = TRUE) {
  GRID_DP <- 2L
  db <- refined_db_path(db_dir)

  con <- multised_con(db)
  on.exit(dbDisconnect(con), add = TRUE)
  site  <- as_tibble(dbReadTable(con, "site"))
  event <- as_tibble(dbGetQuery(con, "SELECT event_id, site_id, year FROM event"))

  # ── 1. Assign each site to its cell ────────────────────────────────────────
  site <- site |>
    mutate(repeat_group = sprintf(paste0("%.", GRID_DP, "f_%.", GRID_DP, "f"),
                                  round(latitude, GRID_DP), round(longitude, GRID_DP)))

  # ── 2. Distinct sampling years per cell (over all dated events) ────────────
  cell_years <- event |>
    filter(!is.na(year)) |>
    left_join(site |> select(site_id, repeat_group), by = "site_id") |>
    group_by(repeat_group) |>
    summarise(n_years = n_distinct(year), .groups = "drop")

  site_out <- site |>
    left_join(cell_years, by = "repeat_group") |>
    mutate(n_years = coalesce(n_years, 0L)) |>
    relocate(repeat_group, n_years, .after = last_col())

  dbWriteTable(con, "site", as.data.frame(site_out), overwrite = TRUE)

  # ── 3. Sanity summary ──────────────────────────────────────────────────────
  cells <- site_out |> distinct(repeat_group, n_years)
  if (verbose) {
    cat("repeat_group / n_years written to site in", db, "\n\n")
    cat(sprintf("sites: %d in %d distinct cells\n", nrow(site_out), nrow(cells)))
    cat(sprintf("cells with >=3 sampling years: %d | sites in them: %d\n",
                sum(cells$n_years >= 3),
                sum(site_out$n_years >= 3)))
    cat("n_years distribution across cells:\n")
    print(cells |> count(n_years) |> arrange(n_years) |> head(8) |> as.data.frame(),
          row.names = FALSE)
    cat("... max n_years:", max(cells$n_years), "\n")
  }
  invisible(list(n_sites = nrow(site_out), n_cells = nrow(cells),
                 max_n_years = max(cells$n_years)))
}
