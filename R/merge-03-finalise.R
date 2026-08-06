# ── Merge step 3: finalise the merged database ───────────────────────────────
# Removes the flagged cross-source duplicates, drops rows orphaned by that
# removal, then renumbers every source-prefixed key to a clean contiguous integer
# while keeping the source and the original prefixed id as provenance.
#
# `element` stays keyed on its shared `symbol`.

merge_finalise <- function(db_dir = multised_db_dir(), verbose = TRUE) {
  con <- multised_con(merged_db_path(db_dir))
  on.exit(dbDisconnect(con), add = TRUE)

  tbls <- c("element", "dataset", "site", "event", "subsample",
            "measurement", "method", "grain_size_fraction")
  d <- rlang::set_names(map(tbls, function(x) as_tibble(dbReadTable(con, x))), tbls)

  # ── 1. Drop flagged duplicates + cascade orphans ───────────────────────────
  d$measurement <- d$measurement |>
    filter(is.na(dup_flag)) |>
    select(-any_of(c("dup_flag", "dup_superseded_by")))

  keep_subsample <- union(d$measurement$subsample_id, d$grain_size_fraction$subsample_id)
  d$subsample <- d$subsample |> filter(subsample_id %in% keep_subsample)
  d$event     <- d$event     |> filter(event_id   %in% d$subsample$event_id)
  d$site      <- d$site      |> filter(site_id    %in% d$event$site_id)
  d$dataset   <- d$dataset   |> filter(dataset_id %in% d$event$dataset_id)
  d$method    <- d$method    |> filter(method_id  %in% d$measurement$method_id)

  # ── 2. Renumber keys to integers, keep the prefixed id as provenance ───────
  # old prefixed key -> new contiguous integer (deterministic order)
  key_map <- function(df, pk) df |> distinct(.data[[pk]]) |>
    arrange(.data[[pk]]) |> transmute(old = .data[[pk]], new = row_number())

  maps <- list(
    dataset     = key_map(d$dataset,     "dataset_id"),
    site        = key_map(d$site,        "site_id"),
    event       = key_map(d$event,       "event_id"),
    subsample   = key_map(d$subsample,   "subsample_id"),
    measurement = key_map(d$measurement, "measurement_id"),
    method      = key_map(d$method,      "method_id"))

  # remap a key column against a map (NA stays NA, e.g. missing method_id)
  remap <- function(x, m) m$new[match(x, m$old)]

  # primary keys: add src_<pk> provenance, then replace the key with the integer
  d$dataset <- d$dataset |> mutate(src_dataset_id = dataset_id,
                                   dataset_id = remap(dataset_id, maps$dataset))
  d$site    <- d$site    |> mutate(src_site_id = site_id,
                                   site_id = remap(site_id, maps$site))
  d$method  <- d$method  |> mutate(src_method_id = method_id,
                                   method_id = remap(method_id, maps$method))

  d$event <- d$event |>
    mutate(src_event_id = event_id,
           event_id   = remap(event_id, maps$event),
           dataset_id = remap(dataset_id, maps$dataset),   # foreign keys
           site_id    = remap(site_id, maps$site))

  d$subsample <- d$subsample |>
    mutate(src_subsample_id = subsample_id,
           subsample_id = remap(subsample_id, maps$subsample),
           event_id     = remap(event_id, maps$event))

  d$measurement <- d$measurement |>
    mutate(src_measurement_id = measurement_id,
           measurement_id = remap(measurement_id, maps$measurement),
           subsample_id   = remap(subsample_id, maps$subsample),
           method_id      = remap(method_id, maps$method))

  d$grain_size_fraction <- d$grain_size_fraction |>
    filter(subsample_id %in% maps$subsample$old)
  gsf_map <- key_map(d$grain_size_fraction, "gsf_id")
  d$grain_size_fraction <- d$grain_size_fraction |>
    mutate(src_gsf_id = gsf_id,
           gsf_id       = remap(gsf_id, gsf_map),
           subsample_id = remap(subsample_id, maps$subsample))

  # ── 3. Write final tables + PK indexes ─────────────────────────────────────
  pk_index <- c(dataset = "dataset_id", site = "site_id", event = "event_id",
                subsample = "subsample_id", measurement = "measurement_id",
                method = "method_id", grain_size_fraction = "gsf_id")
  for (tbl in tbls) {
    dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tbl))
    dbWriteTable(con, tbl, as.data.frame(d[[tbl]]), row.names = FALSE)
    if (tbl %in% names(pk_index)) {
      dbExecute(con, sprintf("CREATE UNIQUE INDEX ix_%s_pk ON %s(%s)",
                             tbl, tbl, pk_index[tbl]))
    }
  }

  # ── 4. Console summary ─────────────────────────────────────────────────────
  counts <- data.frame(table = tbls,
                       rows  = vapply(d[tbls], nrow, numeric(1)),
                       row.names = NULL)
  by_source <- d$measurement |> count(source)

  if (verbose) {
    cat("multised_merged.sqlite finalised\n")
    for (i in seq_len(nrow(counts)))
      cat(sprintf("  %-20s %7d rows\n", counts$table[i], counts$rows[i]))
    cat("measurement by source:\n"); print(as.data.frame(by_source), row.names = FALSE)
  }
  invisible(list(counts = counts, by_source = by_source))
}
