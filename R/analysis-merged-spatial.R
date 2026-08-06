# ── Analysis, merged generation: spatial ─────────────────────────────────
# Converted from R/analysis/spatial/01_merged_spatial.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_spatial <- function(db_dir = multised_db_dir(),
                                    out_dir = multised_analysis_dir(),
                                    verbose = TRUE) {
  # ── Analysis stage, spatial context (MERGED database) ────────────────────────
  # The merged-database counterpart of 01_clean_spatial.R. Do the geo attributes
  # depth and distance-to-coast leave a residual gradient after normalisation? Two
  # questions, bulk samples, pooled across the merged database (outliers dropped):
  #
  #  (B) enrichment: does the ratio metal / normaliser (Fe primary, Al secondary)
  #      vary with depth and distance-to-coast? A ratio that FALLS offshore / with
  #      depth (negative rho) is the coastal-pollution gradient the EFSA background
  #      rests on; a flat ratio means normalisation already removed the spatial
  #      structure (the metal was just grain-size / lithogenic, not enriched).
  #  (A) covariate check: do the normalisers / covariates themselves (Al, Fe, CORG,
  #      fines) vary with depth and distance-to-coast? Expected, via grain size, and
  #      the reason the raw metal does; confirms why (B) uses the ratio.
  #
  # Caveats: depth and distance-to-coast are strongly collinear and both co-vary
  # with grain size, so these are associations, not isolated effects. depth is
  # modelled (GEBCO) and NULL on a few land-rounded sites; distance-to-coast is on
  # every site. Fe is the primary normaliser (it carried the grain-size signal best
  # in the Fe/Al analysis).
  #
  # Outputs -> data/analysis/spatial/ (gitignored). The multised-merged site
  # renders tables + figures from these files:
  #   merged_spatial_enrichment.csv  (B) rho of metal/normaliser vs depth & coast
  #   merged_spatial_covariate.csv   (A) rho of Al/Fe/CORG/fines vs depth & coast
  #   merged_spatial_pairs.csv        per-measurement (bulk) for the figures

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)

  TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  MIN_N       <- 50L
  elem_levels <- TARGETS

  out_dir <- file.path(out_dir, "spatial")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # Spearman rho of x vs y within each group, dropping groups below MIN_N.
  rho_by_group <- function(df, x, y, groups) {
    df |>
      filter(!is.na(.data[[x]]), !is.na(.data[[y]]), .data[[y]] > 0) |>
      group_by(across(all_of(groups))) |>
      filter(n() >= MIN_N) |>
      summarise(rho = cor(.data[[x]], .data[[y]], method = "spearman"),
                n = n(), .groups = "drop")
  }

  # ── 1. Build per-subsample chemistry + site geo, bulk, outliers dropped ──────
  con <- dbConnect(SQLite(), db_path)

  meas <- dbGetQuery(con, sprintf("
    SELECT m.subsample_id, m.source AS Source, m.symbol, m.value_std
    FROM measurement m
    WHERE m.frac_class = 'bulk' AND m.value_std > 0 AND m.outlier_flag IS NULL
      AND m.symbol IN (%s)
  ", paste(sprintf("'%s'", c(TARGETS, NORMALISERS, "CORG")), collapse = ", "))) |>
    as_tibble()

  geo <- dbGetQuery(con, "
    SELECT s.subsample_id, s.fines_lt63, si.depth, si.dist_to_coast, si.sea_name
    FROM subsample s
      JOIN event e  ON e.event_id = s.event_id
      JOIN site  si ON si.site_id = e.site_id
  ") |> as_tibble()
  dbDisconnect(con)

  agg <- meas |>
    group_by(subsample_id, Source, symbol) |>
    summarise(v = mean(value_std), .groups = "drop") |>
    pivot_wider(names_from = symbol, values_from = v)
  for (s in c(TARGETS, NORMALISERS, "CORG")) if (!s %in% names(agg)) agg[[s]] <- NA_real_

  dat <- agg |> left_join(geo, by = "subsample_id")

  # ── 2. (B) Enrichment (metal / normaliser) vs depth & distance-to-coast ──────
  pairs <- dat |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std)) |>
    transmute(Source, symbol = factor(symbol, levels = elem_levels),
              value_std, AL, FE, depth, dist_to_coast, sea_name,
              ratio_AL = value_std / AL, ratio_FE = value_std / FE)

  # pooled (symbol only) + per-source, for each normaliser x variable.
  enrich_one <- function(ratio_col, norm_lab) {
    bind_rows(
      rho_by_group(pairs |> rename(v = !!ratio_col), "v", "depth",         "symbol") |>
        mutate(Source = "All (pooled)", variable = "depth"),
      rho_by_group(pairs |> rename(v = !!ratio_col), "v", "dist_to_coast", "symbol") |>
        mutate(Source = "All (pooled)", variable = "dist_to_coast"),
      rho_by_group(pairs |> rename(v = !!ratio_col), "v", "depth",         c("Source","symbol")) |>
        mutate(variable = "depth"),
      rho_by_group(pairs |> rename(v = !!ratio_col), "v", "dist_to_coast", c("Source","symbol")) |>
        mutate(variable = "dist_to_coast")) |>
      mutate(normaliser = norm_lab)
  }

  enrichment <- bind_rows(enrich_one("ratio_FE", "Fe"),
                          enrich_one("ratio_AL", "Al")) |>
    mutate(rho = round(rho, 3),
           symbol = as.character(symbol)) |>
    select(Source, symbol, normaliser, variable, n, rho) |>
    arrange(Source, symbol, normaliser, variable)

  # ── 3. (A) Normalisers / covariates vs depth & distance-to-coast (pooled) ────
  subs <- dat |>
    distinct(subsample_id, AL, FE, CORG, fines_lt63, depth, dist_to_coast) |>
    rename(Al = AL, Fe = FE, Fines = fines_lt63)

  covariate <- bind_rows(lapply(c("Al", "Fe", "CORG", "Fines"), function(f)
    bind_rows(
      rho_by_group(subs |> rename(v = !!f), "v", "depth",         character(0)) |>
        mutate(factor = f, variable = "depth"),
      rho_by_group(subs |> rename(v = !!f), "v", "dist_to_coast", character(0)) |>
        mutate(factor = f, variable = "dist_to_coast")))) |>
    mutate(rho = round(rho, 3)) |>
    select(factor, variable, n, rho) |>
    arrange(factor, variable)

  # ── 4. Row-level pairs for the figures (Fe enrichment vs coast) ──────────────
  pairs_out <- pairs |>
    filter(!is.na(ratio_FE), is.finite(ratio_FE), ratio_FE > 0,
           !is.na(dist_to_coast)) |>
    transmute(symbol = as.character(symbol), value_std, FE, ratio_FE,
              depth, dist_to_coast)

  # ── 5. Write outputs ─────────────────────────────────────────────────────────
  write_csv(enrichment, file.path(out_dir, "merged_spatial_enrichment.csv"))
  write_csv(covariate,  file.path(out_dir, "merged_spatial_covariate.csv"))
  write_csv(pairs_out,  file.path(out_dir, "merged_spatial_pairs.csv"))

  if (verbose) {
    # ── 6. Console summary ───────────────────────────────────────────────────────
    cat("merged spatial analysis written to", out_dir, "\n\n")
    cat("(A) covariate vs depth & distance-to-coast (pooled rho):\n")
    covariate |> as.data.frame() |> print(row.names = FALSE)
    cat("\n(B) metal/Fe enrichment vs distance-to-coast (pooled; negative = offshore cleaner):\n")
    enrichment |>
      filter(Source == "All (pooled)", normaliser == "Fe", variable == "dist_to_coast") |>
      select(symbol, n, rho) |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
