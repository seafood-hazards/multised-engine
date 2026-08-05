# ── Merge step 2: flag cross-source duplicates ───────────────────────────────
# A cross-source duplicate is the same reading reported by more than one source.
# Two rules run, both flagging the lower-preference copy (never deleting; step 3
# removes the flagged rows and cascades).
#
#   Rule 1, value-cluster: same rounded location + sampling YEAR + depth layer +
#      element + track, and a value within 1%. Year rather than exact date,
#      because a re-hosting source often rewrites the date field; the strict 1%
#      value gate is what keeps genuinely different samples apart.
#   Rule 2, provenance: Vannmiljo's re-hosted Mareano dataset ("... - MAREANO"),
#      where re-hosting nudged the value past 1%. A row is a duplicate when native
#      Mareano matches on location + year + element + track within 5%. Rows with
#      NO native Mareano match are KEPT, they are the only copy we hold.
#
# Preference (highest first): Mareano > 4Demon > MUDAB > Vannmiljo > ICES-DOME.
#
# Adds to `measurement`: dup_flag (1 = superseded duplicate, else NULL) and
# dup_superseded_by (the winning source). Also writes the dedup detail CSV, which
# is lost once step 3 removes the flagged rows.

merge_dedup <- function(db_dir = multised_db_dir(),
                        analysis_dir = multised_analysis_dir(),
                        verbose = TRUE) {
  # setNames rather than backtick names: R does not allow \u escapes inside
  # backticks, and the source labels must stay byte-identical to the merged data.
  PREF <- stats::setNames(1:5,
    c("Mareano", "4Demon", "MUDAB", "Vannmilj\u00f8", "ICES-DOME"))
  TOL        <- 0.01        # 1% relative value match (rule 1)
  TOL_REHOST <- 0.05        # 5% relative value match (rule 2, provenance)
  REHOST_DS  <- "MAREANO"   # Vannmiljo dataset_name marker for re-hosted Mareano

  con <- multised_con(merged_db_path(db_dir))
  on.exit(dbDisconnect(con), add = TRUE)

  meas <- as_tibble(dbReadTable(con, "measurement"))
  sub  <- as_tibble(dbReadTable(con, "subsample")) |> select(subsample_id, event_id, depth_from, depth_to)
  ev   <- as_tibble(dbReadTable(con, "event"))     |> select(event_id, site_id, dataset_id, date, year)
  site <- as_tibble(dbReadTable(con, "site"))      |> select(site_id, latitude, longitude)
  dset <- as_tibble(dbReadTable(con, "dataset"))   |> select(dataset_id, dataset_name)

  # ── 1. Join the matching context onto each measurement ─────────────────────
  ctx <- meas |>
    select(measurement_id, subsample_id, symbol, value_std, frac_class, sieve_um_std, source) |>
    left_join(sub,  by = "subsample_id") |>
    left_join(ev,   by = "event_id") |>
    left_join(site, by = "site_id") |>
    left_join(dset, by = "dataset_id") |>
    mutate(pref = unname(PREF[source]),
           lat3 = round(latitude, 3), lon3 = round(longitude, 3),
           sieve_key = coalesce(sieve_um_std, -1),
           has_year = !is.na(year))

  # ── 2. Rule 1: cluster same-year rows by value within each sample key ───────
  # gkey isolates same location / year / depth / element / track; within it a value
  # cluster is a single-linkage chain of values each within TOL of the previous.
  clustered <- ctx |>
    filter(has_year) |>
    mutate(gkey = paste(lat3, lon3, year, depth_from, depth_to,
                        symbol, frac_class, sieve_um_std, sep = "|")) |>
    arrange(gkey, value_std) |>
    group_by(gkey) |>
    mutate(rel_gap = (value_std - lag(value_std)) / lag(value_std),
           cluster = cumsum(is.na(rel_gap) | rel_gap > TOL)) |>
    group_by(gkey, cluster) |>
    mutate(best_pref     = min(pref),
           winner_source = source[which.min(pref)],
           dup           = pref > best_pref) |>
    ungroup()

  flagged_value <- clustered |>
    filter(dup) |>
    transmute(measurement_id, dup_flag = 1L, dup_superseded_by = winner_source)

  # ── 2b. Rule 2: Vannmiljo's re-hosted Mareano dataset ───────────────────────
  # native Mareano key set (loc3 + year + element + track) with its value(s) ...
  mar_keys <- ctx |>
    filter(source == "Mareano") |>
    transmute(lat3, lon3, year, symbol, frac_class, sieve_key, mar_value = value_std)

  # ... versus the Vannmiljo rows from the re-hosted MAREANO dataset. A row is a
  # duplicate only when a native Mareano value on the same key is within 5%.
  van_mareano <- ctx |>
    filter(source == "Vannmilj\u00f8",
           !is.na(dataset_name), str_detect(dataset_name, REHOST_DS))

  flagged_rehost <- van_mareano |>
    inner_join(mar_keys,
               by = c("lat3", "lon3", "year", "symbol", "frac_class", "sieve_key"),
               relationship = "many-to-many") |>
    mutate(rel_diff = abs(mar_value - value_std) / value_std) |>
    group_by(measurement_id) |>
    summarise(min_rel = min(rel_diff), .groups = "drop") |>
    filter(min_rel <= TOL_REHOST) |>
    transmute(measurement_id, dup_flag = 1L, dup_superseded_by = "Mareano")

  # ── 2c. Combine the two flag sets (one row per measurement) ────────────────
  flagged <- bind_rows(flagged_value, flagged_rehost) |>
    distinct(measurement_id, .keep_all = TRUE)

  # dedup detail for the website (lost once step 3 removes the flagged rows)
  out_dir <- file.path(analysis_dir, "merge")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  flagged |>
    left_join(ctx |> select(measurement_id, loser_source = source, symbol, frac_class),
              by = "measurement_id") |>
    count(winner_source = dup_superseded_by, loser_source, symbol, frac_class, name = "n") |>
    arrange(desc(n)) |>
    write_csv(file.path(out_dir, "merge_dedup.csv"))

  # ── 3. Write dup_flag / dup_superseded_by back onto measurement ────────────
  meas_out <- meas |>
    select(-any_of(c("dup_flag", "dup_superseded_by"))) |>
    left_join(flagged, by = "measurement_id")

  dbExecute(con, "DROP TABLE IF EXISTS measurement")
  dbWriteTable(con, "measurement", as.data.frame(meas_out), row.names = FALSE)

  # ── 4. Console summary ─────────────────────────────────────────────────────
  n_dup <- nrow(flagged)
  by_loser <- flagged |>
    left_join(ctx |> select(measurement_id, source), by = "measurement_id") |>
    count(loser = source, sort = TRUE)
  pairs <- flagged |>
    left_join(ctx |> select(measurement_id, source), by = "measurement_id") |>
    count(winner = dup_superseded_by, loser = source, sort = TRUE)

  if (verbose) {
    cat("cross-source duplicates flagged:", n_dup,
        sprintf("(%.1f%% of %d measurements)\n", 100 * n_dup / nrow(meas), nrow(meas)))
    cat("  rule 1 (value-cluster, same year):         ", nrow(flagged_value), "\n")
    cat("  rule 2 (Vannmiljo re-hosted Mareano):      ", nrow(flagged_rehost),
        "  (", nrow(van_mareano), "candidates in the dataset)\n")
    cat("\nsuperseded (loser) by source:\n"); print(as.data.frame(by_loser), row.names = FALSE)
    cat("\nwinner -> loser pairs:\n");        print(as.data.frame(pairs), row.names = FALSE)
  }
  invisible(list(n_flagged = n_dup, n_rule1 = nrow(flagged_value),
                 n_rule2 = nrow(flagged_rehost), by_loser = by_loser, pairs = pairs))
}
