# ── Merge step 1: union the five clean databases ─────────────────────────────
# Combines the per-source clean DBs into one, with every key prefixed by a source
# code so keys from different sources cannot mix. Adds a `source` column and the
# harmonised sieve-cutoff columns. No deduplication yet (that is step 2).
#
# Unlike pilot/slim/clean there is nothing per-source here: the merge operates on
# all five at once, so `create_db("merged")` takes no `source`.

# code = key prefix, stem = clean DB file, pref = source preference (1 = highest).
merge_sources <- function() {
  tibble::tribble(
    ~Source,      ~stem,        ~code,  ~pref,
    "Mareano",    "mareano",    "mar",  1L,
    "4Demon",     "4demon",     "dem",  2L,
    "MUDAB",      "mudab",      "mud",  3L,
    "Vannmilj\u00f8",  "vannmiljo",  "van",  4L,
    "ICES-DOME",  "ices_dome",  "ice",  5L)
}

# Every table and which of its columns are keys to prefix. `element` is the shared
# vocabulary: no keys prefixed, no source column.
merge_key_cols <- function() {
  list(
    element             = character(0),
    dataset             = "dataset_id",
    site                = "site_id",
    event               = c("event_id", "dataset_id", "site_id"),
    subsample           = c("subsample_id", "event_id"),
    measurement         = c("measurement_id", "subsample_id", "method_id"),
    method              = "method_id",
    grain_size_fraction = c("gsf_id", "subsample_id"))
}

merged_db_path <- function(db_dir = multised_db_dir()) {
  file.path(db_dir, "multised_merged.sqlite")
}

merge_union <- function(db_dir = multised_db_dir(), verbose = TRUE) {
  SOURCES  <- merge_sources()
  KEY_COLS <- merge_key_cols()
  out_db   <- merged_db_path(db_dir)

  # ── 1. Read + prefix each source ───────────────────────────────────────────
  prefix_keys <- function(df, cols, code) {
    for (c in intersect(cols, names(df)))
      df[[c]] <- paste0(code, "_", df[[c]])
    df
  }

  read_source <- function(stem, code, Source) {
    path <- file.path(db_dir, paste0(stem, "_clean.sqlite"))
    con <- multised_con(path)
    on.exit(dbDisconnect(con))
    have <- dbListTables(con)
    purrr::imap(KEY_COLS, function(cols, tbl) {
      if (!tbl %in% have) return(NULL)             # 4Demon: no grain_size_fraction
      df <- as_tibble(dbReadTable(con, tbl)) |> prefix_keys(cols, code)
      if (tbl != "element") df$source <- Source    # element is sourceless
      df
    })
  }

  per_source <- purrr::pmap(SOURCES, function(Source, stem, code, pref)
    read_source(stem, code, Source))
  names(per_source) <- SOURCES$Source

  # ── 2. Union table by table ────────────────────────────────────────────────
  union_table <- function(tbl) {
    parts <- map(per_source, tbl) |> purrr::compact()
    bind_rows(parts)
  }

  merged <- rlang::set_names(map(names(KEY_COLS), union_table), names(KEY_COLS))

  # element: collapse the shared vocabulary to distinct rows
  merged$element <- distinct(merged$element)
  dup_sym <- merged$element |> count(symbol) |> filter(n > 1)
  if (nrow(dup_sym) > 0) {
    warning("element symbols with conflicting rows: ",
            paste(dup_sym$symbol, collapse = ", "))
  }

  # ── 3. Harmonised sieve cutoff on measurement ──────────────────────────────
  # canonical numeric cutoff (62 -> 63; others unchanged) + label; NULL for bulk.
  merged$measurement <- merged$measurement |>
    mutate(sieve_um_std = if_else(frac_class == "sieved",
                                  if_else(sieve_um == 62, 63, sieve_um), NA_real_),
           sieve_class  = if_else(!is.na(sieve_um_std),
                                  paste0("<", sieve_um_std, "um"), NA_character_))

  # ── 4. Write the merged DB ─────────────────────────────────────────────────
  dir.create(dirname(out_db), showWarnings = FALSE, recursive = TRUE)
  con <- multised_con(out_db, must_exist = FALSE)
  on.exit(dbDisconnect(con), add = TRUE)
  for (tbl in names(merged)) {
    dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tbl))
    dbWriteTable(con, tbl, as.data.frame(merged[[tbl]]), row.names = FALSE)
  }

  # ── 5. Console summary ─────────────────────────────────────────────────────
  counts <- data.frame(table = names(merged),
                       rows  = vapply(merged, nrow, numeric(1)),
                       row.names = NULL)
  by_source <- merged$measurement |> count(source)
  by_sieve  <- merged$measurement |> filter(frac_class == "sieved") |> count(sieve_class)

  if (verbose) {
    cat("multised_merged.sqlite (pre-dedup) written\n")
    for (i in seq_len(nrow(counts)))
      cat(sprintf("  %-20s %7d rows\n", counts$table[i], counts$rows[i]))
    cat("measurement by source:\n"); print(as.data.frame(by_source), row.names = FALSE)
    cat("sieved sieve_class:\n");    print(as.data.frame(by_sieve), row.names = FALSE)
  }
  invisible(list(counts = counts, by_source = by_source, by_sieve = by_sieve))
}
