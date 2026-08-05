# ── Analysis, merged generation: depthprofile ────────────────────────────
# Converted from R/analysis/depthprofile/01_merged_depthprofile.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_depthprofile <- function(db_dir = multised_db_dir(),
                                         out_dir = multised_analysis_dir(),
                                         verbose = TRUE) {
  # ── Analysis stage, downcore depth profiles (MERGED database) ────────────────
  # A merged-only analysis (no per-source clean counterpart): how the target metals
  # change with depth WITHIN a sediment core. Multi-layer events (event.n_layers > 1)
  # are cores sampled in several depth slices; a metal that concentrates in the top
  # slices and falls with depth is surface-enriched, the fingerprint of recent
  # (often anthropogenic) input over a lower natural background. A flat or rising
  # profile instead points to a stable or buried source.
  #
  # The absolute level differs hugely between sites, so profiles are compared in
  # RELATIVE terms: each measurement is divided by its own core's median for that
  # element, and the within-core trend is a rank correlation (Spearman) of value
  # against layer midpoint depth, both of which cancel the site's baseline level.
  #
  # Run once on multised_merged.sqlite. Bulk only (a downcore profile of the whole
  # sample); distributional outliers dropped; depth is the subsample interval
  # midpoint (cm). 4Demon has no multi-layer bulk targets to speak of.
  #
  # Outputs -> data/analysis/depthprofile/ (gitignored). The multised-merged site
  # renders tables + figures from these files:
  #   merged_depthprofile_trends.csv       per element: within-core trend summary
  #   merged_depthprofile_enrichment.csv   per element: surface/deep ratio summary
  #   merged_depthprofile_pooled.csv       element x depth bin: relative conc curve
  #   merged_depthprofile_cores.csv        relative points for the profile figure

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)

  TARGETS    <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
  MIN_LAYERS <- 3L     # layers needed for a within-core trend (rho)
  MIN_CORES  <- 20L    # cores needed to report an element
  elem_levels <- TARGETS

  out_dir <- file.path(out_dir, "depthprofile")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # relative-depth bins (cm), from the interval midpoint; a center for plotting.
  depth_bins <- c(0, 2, 5, 10, 20, 40, Inf)
  bin_labels <- c("0-2", "2-5", "5-10", "10-20", "20-40", ">40")
  bin_center <- c(1, 3.5, 7.5, 15, 30, 55)

  # ── 1. Pull bulk target measurements in multi-layer cores ────────────────────
  con <- dbConnect(SQLite(), db_path)

  dat <- dbGetQuery(con, sprintf("
    SELECT ev.event_id, m.symbol, m.value_std, m.source AS Source,
           s.subsample_id, s.depth_from, s.depth_to
    FROM measurement m
      JOIN subsample s  ON s.subsample_id = m.subsample_id
      JOIN event     ev ON ev.event_id    = s.event_id
    WHERE m.frac_class = 'bulk' AND m.value_std > 0 AND m.outlier_flag IS NULL
      AND ev.n_layers > 1
      AND s.depth_from IS NOT NULL AND s.depth_to IS NOT NULL
      AND m.symbol IN (%s)
  ", paste(sprintf("'%s'", TARGETS), collapse = ", "))) |>
    as_tibble() |>
    mutate(mid_depth = (depth_from + depth_to) / 2) |>
    # one value per core x layer x element (average any co-located repeats)
    group_by(event_id, Source, symbol, subsample_id, mid_depth) |>
    summarise(value_std = mean(value_std), .groups = "drop") |>
    mutate(symbol = factor(symbol, levels = elem_levels))

  dbDisconnect(con)

  # add the core's median level and relative concentration (value / core median)
  dat <- dat |>
    group_by(event_id, symbol) |>
    mutate(core_layers = n_distinct(mid_depth),
           core_median = median(value_std),
           rel = value_std / core_median) |>
    ungroup()

  # ── 2. Within-core trend: Spearman rho of value vs depth, per core ───────────
  # One rho per (core, element) with at least MIN_LAYERS distinct depths.
  core_trend <- dat |>
    filter(core_layers >= MIN_LAYERS) |>
    group_by(symbol, event_id) |>
    summarise(n_layers = n_distinct(mid_depth),
              rho = suppressWarnings(cor(mid_depth, value_std, method = "spearman")),
              .groups = "drop") |>
    filter(!is.na(rho))

  trends <- core_trend |>
    group_by(symbol) |>
    summarise(n_cores      = n(),
              median_rho   = round(median(rho), 3),
              pct_decrease = round(100 * mean(rho <= -0.5)),  # surface-enriched
              pct_increase = round(100 * mean(rho >=  0.5)),
              pct_flat     = round(100 * mean(abs(rho) < 0.5)),
              .groups = "drop") |>
    filter(n_cores >= MIN_CORES) |>
    arrange(symbol)

  # ── 3. Surface vs deep enrichment ratio, per core ────────────────────────────
  # Shallowest layer value / deepest layer value, per (core, element) with >= 2
  # layers. > 1 means surface-enriched.
  core_ratio <- dat |>
    group_by(symbol, event_id) |>
    filter(n_distinct(mid_depth) >= 2) |>
    summarise(surf = value_std[which.min(mid_depth)],
              deep = value_std[which.max(mid_depth)],
              .groups = "drop") |>
    mutate(ratio = surf / deep) |>
    filter(is.finite(ratio), ratio > 0)

  enrichment <- core_ratio |>
    group_by(symbol) |>
    summarise(n_cores        = n(),
              median_ratio   = round(median(ratio), 2),
              p25            = round(quantile(ratio, 0.25), 2),
              p75            = round(quantile(ratio, 0.75), 2),
              pct_surf_higher = round(100 * mean(ratio > 1)),
              .groups = "drop") |>
    filter(n_cores >= MIN_CORES) |>
    arrange(symbol)

  # ── 4. Pooled relative-depth profile ─────────────────────────────────────────
  # Each measurement's relative concentration (value / core median) binned by depth,
  # pooled across cores: the average downcore shape, baseline level cancelled.
  keep_elems <- trends$symbol   # elements with enough cores to report

  pooled <- dat |>
    filter(symbol %in% keep_elems) |>
    mutate(bin = cut(mid_depth, breaks = depth_bins, labels = bin_labels,
                     right = FALSE)) |>
    filter(!is.na(bin)) |>
    group_by(symbol, bin) |>
    summarise(n = n(),
              median_rel = round(median(rel), 3),
              p25 = round(quantile(rel, 0.25), 3),
              p75 = round(quantile(rel, 0.75), 3),
              .groups = "drop") |>
    mutate(bin_center = bin_center[match(bin, bin_labels)]) |>
    arrange(symbol, bin_center)

  # ── 5. Per-core trend values for the distribution figure ─────────────────────
  # The honest headline: how the within-core trend (rho) is distributed per element.
  # Pooling levels flattens the median profile, but the spread of rho shows which
  # metals are surface-enriched (rho < 0) versus enriched at depth (rho > 0).
  core_rho_out <- core_trend |>
    filter(symbol %in% keep_elems) |>
    transmute(symbol = as.character(symbol), event_id, n_layers, rho = round(rho, 3))

  # ── 6. Write outputs ─────────────────────────────────────────────────────────
  write_csv(trends,       file.path(out_dir, "merged_depthprofile_trends.csv"))
  write_csv(enrichment,   file.path(out_dir, "merged_depthprofile_enrichment.csv"))
  write_csv(pooled,       file.path(out_dir, "merged_depthprofile_pooled.csv"))
  write_csv(core_rho_out, file.path(out_dir, "merged_depthprofile_core_rho.csv"))

  if (verbose) {
    # ── 7. Console summary ───────────────────────────────────────────────────────
    cat("merged depth-profile analysis written to", out_dir, "\n\n")
    cat("within-core trend (rho of concentration vs depth), bulk multi-layer cores:\n")
    trends |> as.data.frame() |> print(row.names = FALSE)
    cat("\nsurface/deep enrichment ratio (>1 = surface-enriched):\n")
    enrichment |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
