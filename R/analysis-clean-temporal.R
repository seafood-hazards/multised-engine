# ── Analysis, clean generation: temporal ─────────────────────────────────
# Converted from R/analysis/temporal/01_clean_temporal.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_clean_temporal <- function(db_dir = multised_db_dir(),
                                    out_dir = multised_analysis_dir(),
                                    verbose = TRUE) {
  # ── Analysis stage, temporal context of normalisation (per source) ───────────
  # Does sampling year affect the normalisation? The time analogue of the spatial
  # (depth / distance-to-coast) page. Two questions, bulk samples, per source:
  #
  #  (A) lead: does the ENRICHMENT (metal / Al, and metal / Fe) trend over the years?
  #      A ratio that falls with year is a real improvement signal (declining input
  #      relative to the lithogenic carrier); a flat ratio means normalisation
  #      removed any temporal drift.
  #  (B) check: do the normalisers / covariates themselves (Al, Fe, CORG, fines)
  #      trend with year? A drift here means the sampling / method mix changed over
  #      time, which would confound (A).
  #
  # Caveats: this is an unbalanced observational series, not a fixed monitoring
  # station, so year is confounded with WHERE and HOW each source sampled over time
  # (station mix, gear, lab); these are associations, not station trends. Mareano's
  # year is sparse (2003-2021, ~23% of events carry no year).
  #
  # Outputs -> data/analysis/temporal/ (gitignored):
  #   temporal_enrichment.csv  (A) rho of metal/normaliser vs year
  #   temporal_normaliser.csv  (B) rho of Al/Fe/CORG/fines vs year
  #   temporal_pairs.csv        per-measurement (bulk) for the figures

  # ── 0. Config ────────────────────────────────────────────────────────────────
  sources <- tibble(
    Source = c("Mareano", "Vannmilj\u00f8", "ICES-DOME", "MUDAB", "4Demon"),
    stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

  TARGETS     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  NORMALISERS <- c("AL", "FE")
  MIN_N       <- 30L

  out_dir <- file.path(out_dir, "temporal")
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

  # ── 1. Build per-subsample chemistry + event year, bulk ──────────────────────
  build <- function(stem, Source) {
    con <- dbConnect(SQLite(), file.path(db_dir, sprintf("%s_clean.sqlite", stem)))
    on.exit(dbDisconnect(con))
    meas <- as_tibble(dbReadTable(con, "measurement"))
    ss   <- as_tibble(dbReadTable(con, "subsample"))
    ev   <- as_tibble(dbReadTable(con, "event"))
    if (!"fines_lt63" %in% names(ss)) ss$fines_lt63 <- NA_real_

    ctx <- ss |> select(subsample_id, event_id, fines_lt63) |>
      left_join(ev |> select(event_id, year), by = "event_id")

    agg <- meas |>
      filter(symbol %in% c(TARGETS, NORMALISERS, "CORG"), !is.na(value_std), value_std > 0) |>
      group_by(subsample_id, frac_class, symbol) |>
      summarise(v = mean(value_std), .groups = "drop")
    wide <- agg |> pivot_wider(names_from = symbol, values_from = v)
    for (s in c(TARGETS, NORMALISERS, "CORG")) if (!s %in% names(wide)) wide[[s]] <- NA_real_

    wide |>
      left_join(ctx, by = "subsample_id") |>
      filter(frac_class == "bulk") |>
      mutate(Source = Source)
  }

  dat <- pmap_dfr(sources, function(Source, stem) build(stem, Source))

  # ── 2. (A) Enrichment (metal / normaliser) vs year ───────────────────────────
  pairs <- dat |>
    pivot_longer(all_of(TARGETS), names_to = "symbol", values_to = "value_std") |>
    filter(!is.na(value_std)) |>
    transmute(Source, symbol, value_std, AL, FE, year,
              ratio_AL = value_std / AL, ratio_FE = value_std / FE)

  enrichment <- bind_rows(
    rho_by_group(pairs |> rename(v = ratio_AL), "v", "year", c("Source","symbol")) |>
      mutate(normaliser = "Al"),
    rho_by_group(pairs |> rename(v = ratio_FE), "v", "year", c("Source","symbol")) |>
      mutate(normaliser = "Fe")) |>
    mutate(rho = round(rho, 3), variable = "year") |>
    select(Source, symbol, normaliser, variable, n, rho) |>
    arrange(Source, symbol, normaliser)

  # ── 3. (B) Normalisers / covariates vs year ──────────────────────────────────
  subs <- dat |> distinct(Source, subsample_id, AL, FE, CORG, fines_lt63, year) |>
    rename(Al = AL, Fe = FE, Fines = fines_lt63)

  normaliser <- bind_rows(lapply(c("Al", "Fe", "CORG", "Fines"), function(f)
    rho_by_group(subs |> rename(v = !!f), "v", "year", "Source") |>
      mutate(factor = f, variable = "year"))) |>
    mutate(rho = round(rho, 3)) |>
    select(Source, factor, variable, n, rho) |>
    arrange(Source, factor)

  # ── 4. Write outputs ─────────────────────────────────────────────────────────
  write_csv(enrichment, file.path(out_dir, "temporal_enrichment.csv"))
  write_csv(normaliser, file.path(out_dir, "temporal_normaliser.csv"))
  write_csv(pairs,      file.path(out_dir, "temporal_pairs.csv"))

  if (verbose) {
    # ── 5. Console summary ───────────────────────────────────────────────────────
    cat("temporal analysis written to", out_dir, "\n")
    cat("\n(A) metal/Al vs year (negative rho = enrichment declines over time):\n")
    enrichment |> filter(normaliser == "Al") |>
      select(Source, symbol, n, rho) |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
