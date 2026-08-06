# ── Refine step 2: build the slim `normaliser` table ─────────────────────────
# FE / AL / CORG were kept out of the refined fact table in step 1. Here they are
# reshaped from the merged measurements into one compact carrier at the correct
# grain, (subsample_id, frac_class), wide: columns `fe`, `al`, `corg` in the
# standardised unit (mg/kg). This is the "remove FE/AL/CORG from measurement"
# step, done without loss.
#
# A normaliser is NOT unique per subsample (~3,939 subsamples carry both
# fractions), so the grain is (subsample, fraction). Where a (subsample, fraction)
# has more than one method row for a normaliser (FE ~4.6%, AL/CORG ~0.2%), the
# values are MEAN-COLLAPSED, as the merged-DB analyses did.

REFINE_NORMS <- c("FE", "AL", "CORG")

refine_normaliser <- function(db_dir = multised_db_dir(), verbose = TRUE) {
  src_db <- merged_db_path(db_dir)
  out_db <- refined_db_path(db_dir)
  NORMS  <- REFINE_NORMS

  # ── 1. Read the normaliser measurements from the merged DB ─────────────────
  srccon <- multised_con(src_db)
  meas <- as_tibble(dbGetQuery(srccon, sprintf("
    SELECT subsample_id, symbol, frac_class, value_std
    FROM measurement
    WHERE symbol IN (%s)
  ", paste(sprintf("'%s'", NORMS), collapse = ", "))))
  dbDisconnect(srccon)

  dropped_frac <- meas |> filter(!frac_class %in% c("bulk", "sieved"))

  # ── 2. Mean-collapse to one value per (subsample, fraction, normaliser) ────
  collapsed <- meas |>
    filter(frac_class %in% c("bulk", "sieved"), !is.na(value_std), value_std > 0) |>
    group_by(subsample_id, frac_class, symbol) |>
    summarise(value = mean(value_std), n_meth = n(), .groups = "drop")

  n_collapsed <- sum(collapsed$n_meth > 1)

  # ── 3. Widen to fe / al / corg ─────────────────────────────────────────────
  df_normaliser <- collapsed |>
    select(subsample_id, frac_class, symbol, value) |>
    pivot_wider(names_from = symbol, values_from = value) |>
    rename_with(tolower, any_of(NORMS))
  for (cc in c("fe", "al", "corg")) {
    if (!cc %in% names(df_normaliser)) df_normaliser[[cc]] <- NA_real_
  }
  df_normaliser <- df_normaliser |> select(subsample_id, frac_class, fe, al, corg)

  # ── 4. Write the normaliser table into the refined DB ──────────────────────
  outcon <- multised_con(out_db)
  on.exit(dbDisconnect(outcon), add = TRUE)
  dbWriteTable(outcon, "normaliser", as.data.frame(df_normaliser), overwrite = TRUE)

  # ── 5. Sanity summary ──────────────────────────────────────────────────────
  if (verbose) {
    cat("normaliser table written to", out_db, "\n\n")
    cat(sprintf("rows (subsample x fraction): %d\n", nrow(df_normaliser)))
    cat(sprintf("  by fraction: bulk %d, sieved %d\n",
                sum(df_normaliser$frac_class == "bulk"),
                sum(df_normaliser$frac_class == "sieved")))
    cat("coverage (non-NA):\n")
    cat(sprintf("  fe   %6d (%.0f%%)\n", sum(!is.na(df_normaliser$fe)),   100 * mean(!is.na(df_normaliser$fe))))
    cat(sprintf("  al   %6d (%.0f%%)\n", sum(!is.na(df_normaliser$al)),   100 * mean(!is.na(df_normaliser$al))))
    cat(sprintf("  corg %6d (%.0f%%)\n", sum(!is.na(df_normaliser$corg)), 100 * mean(!is.na(df_normaliser$corg))))
    cat(sprintf("\nmean-collapsed (subsample x fraction x normaliser) groups with >1 method: %d\n",
                n_collapsed))
    if (nrow(dropped_frac) > 0) {
      cat(sprintf("note: %d normaliser rows with frac_class not in bulk/sieved were excluded\n",
                  nrow(dropped_frac)))
    }
  }
  invisible(list(n_rows = nrow(df_normaliser), n_collapsed = n_collapsed,
                 n_dropped = nrow(dropped_frac)))
}
