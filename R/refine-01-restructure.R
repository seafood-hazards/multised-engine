# ── Refine step 1: restructure the merged DB into the refined skeleton ───────
# Fifth generation: an analysis-ready mart derived from the merged database for
# the pristine/background work (docs/refined-pipeline.md). This step lays down
# the skeleton:
#
#   - carry the dimensions over (element TRIMMED to the 7 targets; dataset; method
#     filtered to methods the kept target rows use; event; site; subsample),
#   - keep the 7 TARGET measurements as a single `measurement` table with a
#     frac_class column (bulk/sieved never pool, enforced by the column), and DROP
#     three redundant columns: unit_std (constant mg/kg), matrix (raw grain-size
#     fraction code, unused now grain size is gone) and sieve_um (superseded by the
#     harmonised sieve_um_std),
#   - DROP grain_size_fraction (every analysis used the derived fines_lt63).
#
# FE / AL / CORG are NOT carried into the fact table here; step 2 reshapes them
# into the slim `normaliser` table and step 3 writes the ratios. This step creates
# the refined database fresh.

refined_db_path <- function(db_dir = multised_db_dir()) {
  file.path(db_dir, "multised_refined.sqlite")
}

REFINE_TARGETS <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

refine_restructure <- function(db_dir = multised_db_dir(), verbose = TRUE) {
  src_db <- merged_db_path(db_dir)
  out_db <- refined_db_path(db_dir)
  TARGETS <- REFINE_TARGETS

  # ── 1. Read the merged tables ──────────────────────────────────────────────
  srccon <- multised_con(src_db)
  element    <- as_tibble(dbReadTable(srccon, "element"))
  dataset    <- as_tibble(dbReadTable(srccon, "dataset"))
  method     <- as_tibble(dbReadTable(srccon, "method"))
  event      <- as_tibble(dbReadTable(srccon, "event"))
  site       <- as_tibble(dbReadTable(srccon, "site"))
  subsample  <- as_tibble(dbReadTable(srccon, "subsample"))
  meas       <- as_tibble(dbReadTable(srccon, "measurement"))
  dbDisconnect(srccon)

  # ── 2. Dimensions ──────────────────────────────────────────────────────────
  # element -> the 7 targets only (normalisers/organic become normaliser columns)
  df_element <- element |> filter(category == "target")

  # split the target measurements up front so we can trim `method` to what they use
  target_meas <- meas |> filter(symbol %in% TARGETS)
  used_methods <- target_meas |> distinct(method_id) |> filter(!is.na(method_id)) |> pull()
  df_method  <- method |> filter(method_id %in% used_methods)

  df_dataset   <- dataset
  df_event     <- event
  df_site      <- site        # aqua_id / repeat_group / n_years added in steps 4-5
  df_subsample <- subsample   # physical properties; already carries fines_lt63

  # ── 3. Build the single target `measurement` table ─────────────────────────
  # frac_class kept as a column; unit_std / matrix / sieve_um dropped; sieve_um_std /
  # sieve_class kept (NULL for bulk). Ratios are added in step 3.
  keep_cols <- c("measurement_id", "subsample_id", "symbol",
                 "value", "unit", "value_std",
                 "value_sd", "n_rep", "value_uncrt",
                 "frac_class", "sieve_um_std", "sieve_class", "frac_basis",
                 "method_id", "source", "src_measurement_id", "outlier_flag")

  df_measurement <- target_meas |>
    filter(frac_class %in% c("bulk", "sieved")) |>
    select(all_of(keep_cols))

  dropped <- target_meas |> filter(!frac_class %in% c("bulk", "sieved"))

  # ── 4. Write the refined DB (fresh) ────────────────────────────────────────
  if (file.exists(out_db)) invisible(file.remove(out_db))
  outcon <- multised_con(out_db, must_exist = FALSE)
  on.exit(dbDisconnect(outcon), add = TRUE)
  writes <- list(element = df_element, dataset = df_dataset, method = df_method,
                 event = df_event, site = df_site, subsample = df_subsample,
                 measurement = df_measurement)
  for (nm in names(writes)) {
    dbWriteTable(outcon, nm, as.data.frame(writes[[nm]]), overwrite = TRUE)
  }

  # ── 5. Sanity summary ──────────────────────────────────────────────────────
  if (verbose) {
    cat("refined DB written to", out_db, "\n\n")
    cat("dimensions carried:\n")
    cat(sprintf("  element   %6d (was %d; targets only)\n", nrow(df_element), nrow(element)))
    cat(sprintf("  method    %6d (was %d; used by targets)\n", nrow(df_method), nrow(method)))
    cat(sprintf("  dataset   %6d   event %d   site %d   subsample %d\n",
                nrow(df_dataset), nrow(df_event), nrow(df_site), nrow(df_subsample)))
    cat("\nmeasurement (targets only, single table):\n")
    cat(sprintf("  total  %6d  (merged target rows: %d)\n", nrow(df_measurement), nrow(target_meas)))
    cat(sprintf("  bulk %d, sieved %d\n",
                sum(df_measurement$frac_class == "bulk"),
                sum(df_measurement$frac_class == "sieved")))
    cat(sprintf("  columns: %d (dropped unit_std, matrix, sieve_um)\n", ncol(df_measurement)))
    if (nrow(dropped) > 0) {
      cat(sprintf("  WARNING: %d target rows with frac_class not in bulk/sieved were dropped\n",
                  nrow(dropped)))
    }
    cat(sprintf("\ndropped: grain_size_fraction, and FE/AL/CORG measurement rows (%d, -> normaliser in step 2)\n",
                sum(meas$symbol %in% c("FE", "AL", "CORG"))))
  }
  invisible(list(n_element = nrow(df_element), n_method = nrow(df_method),
                 n_measurement = nrow(df_measurement), n_dropped = nrow(dropped)))
}
