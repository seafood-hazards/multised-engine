# ── Analysis, clean generation: spatial ──────────────────────────────────
# Converted from R/analysis/spatial/01_clean_spatial.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_clean_spatial <- function(db_dir = multised_db_dir(),
                                   out_dir = multised_analysis_dir(),
                                   verbose = TRUE) {
  # ── Analysis stage, spatial context of normalisation (per source) ────────────
  # Do the geo attributes depth and distance-to-coast affect the normalisation?
  # Two questions, bulk samples, per source:
  #
  #  (B) lead: does the ENRICHMENT (metal / Al, and metal / Fe) vary with depth and
  #      distance-to-coast? A ratio that falls offshore / with depth (negative rho)
  #      is the coastal-pollution gradient the EFSA background rests on; a flat ratio
  #      means normalisation removed the spatial structure.
  #  (A) check: do the normalisers / covariates themselves (Al, Fe, CORG, fines)
  #      vary with depth and distance-to-coast? (Expected, via grain size.)
  #
  # Caveats: depth and distance-to-coast are strongly collinear and both co-vary
  # with grain size, so these are associations, not isolated effects. depth is
  # modelled (GEBCO) and NULL on land-rounded sites; distance-to-coast is solid.
  #
  # Outputs -> data/analysis/spatial/ (gitignored):
  #   spatial_enrichment.csv  (B) rho of metal/normaliser vs depth & coast
  #   spatial_normaliser.csv  (A) rho of Al/Fe/CORG/fines vs depth & coast
  #   spatial_pairs.csv        per-measurement (bulk) for the figures

  # ── 0. Config ────────────────────────────────────────────────────────────────
  sources <- tibble(
    Source = c("Mareano", "Vannmilj\u00f8", "ICES-DOME", "MUDAB", "4Demon"),
    stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

  TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  MIN_N       <- 30L

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

  # ── 1. Build per-subsample chemistry + site geo, bulk ────────────────────────
  build <- function(stem, Source) {
    con <- dbConnect(SQLite(), file.path(db_dir, sprintf("%s_clean.sqlite", stem)))
    on.exit(dbDisconnect(con))
    meas <- as_tibble(dbReadTable(con, "measurement"))
    ss   <- as_tibble(dbReadTable(con, "subsample"))
    ev   <- as_tibble(dbReadTable(con, "event"))
    st   <- as_tibble(dbReadTable(con, "site"))
    if (!"fines_lt63" %in% names(ss)) ss$fines_lt63 <- NA_real_

    coords <- ss |> select(subsample_id, event_id, fines_lt63) |>
      left_join(ev |> select(event_id, site_id), by = "event_id") |>
      left_join(st |> select(site_id, depth, dist_to_coast), by = "site_id")

    agg <- meas |>
      filter(symbol %in% c(TARGETS, NORMALISERS, "CORG"), !is.na(value_std), value_std > 0) |>
      group_by(subsample_id, frac_class, symbol) |>
      summarise(v = mean(value_std), .groups = "drop")
    wide <- agg |> pivot_wider(names_from = symbol, values_from = v)
    for (s in c(TARGETS, NORMALISERS, "CORG")) if (!s %in% names(wide)) wide[[s]] <- NA_real_

    wide |>
      left_join(coords, by = "subsample_id") |>
      filter(frac_class == "bulk") |>
      mutate(Source = Source)
  }

  dat <- pmap_dfr(sources, function(Source, stem) build(stem, Source))

  # ── 2. (B) Enrichment (metal / normaliser) vs depth & distance-to-coast ──────
  pairs <- dat |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std)) |>
    transmute(Source, symbol, value_std, AL, FE, depth, dist_to_coast,
              ratio_AL = value_std / AL, ratio_FE = value_std / FE)

  enrichment <- bind_rows(
    rho_by_group(pairs |> rename(v = ratio_AL), "v", "depth",         c("Source","symbol")) |>
      mutate(normaliser = "Al", variable = "depth"),
    rho_by_group(pairs |> rename(v = ratio_AL), "v", "dist_to_coast", c("Source","symbol")) |>
      mutate(normaliser = "Al", variable = "dist_to_coast"),
    rho_by_group(pairs |> rename(v = ratio_FE), "v", "depth",         c("Source","symbol")) |>
      mutate(normaliser = "Fe", variable = "depth"),
    rho_by_group(pairs |> rename(v = ratio_FE), "v", "dist_to_coast", c("Source","symbol")) |>
      mutate(normaliser = "Fe", variable = "dist_to_coast")) |>
    mutate(rho = round(rho, 3)) |>
    select(Source, symbol, normaliser, variable, n, rho) |>
    arrange(Source, symbol, normaliser, variable)

  # ── 3. (A) Normalisers / covariates vs depth & distance-to-coast ─────────────
  subs <- dat |> distinct(Source, subsample_id, AL, FE, CORG, fines_lt63, depth, dist_to_coast) |>
    rename(Al = AL, Fe = FE, Fines = fines_lt63)

  normaliser <- bind_rows(lapply(c("Al", "Fe", "CORG", "Fines"), function(f)
    bind_rows(
      rho_by_group(subs |> rename(v = !!f), "v", "depth",         "Source") |> mutate(factor = f, variable = "depth"),
      rho_by_group(subs |> rename(v = !!f), "v", "dist_to_coast", "Source") |> mutate(factor = f, variable = "dist_to_coast")))) |>
    mutate(rho = round(rho, 3)) |>
    select(Source, factor, variable, n, rho) |>
    arrange(Source, factor, variable)

  # ── 4. Write outputs ─────────────────────────────────────────────────────────
  write_csv(enrichment, file.path(out_dir, "spatial_enrichment.csv"))
  write_csv(normaliser, file.path(out_dir, "spatial_normaliser.csv"))
  write_csv(pairs,      file.path(out_dir, "spatial_pairs.csv"))

  if (verbose) {
    # ── 5. Console summary ───────────────────────────────────────────────────────
    cat("spatial analysis written to", out_dir, "\n")
    cat("\n(B) metal/Al vs distance-to-coast (negative rho = offshore is cleaner):\n")
    enrichment |> filter(normaliser == "Al", variable == "dist_to_coast") |>
      select(Source, symbol, n, rho) |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
