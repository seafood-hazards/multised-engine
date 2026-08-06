# ── Analysis, merged generation: hotspots ────────────────────────────────
# Converted from R/analysis/hotspots/01_merged_hotspots.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_hotspots <- function(db_dir = multised_db_dir(),
                                     out_dir = multised_analysis_dir(),
                                     verbose = TRUE) {
  # ── Analysis stage, spatial hotspots (MERGED database) ───────────────────────
  # The second Clustering page, and the geographic complement of Geochemical Facies
  # (which clusters in chemistry space). Here we cluster in GEOGRAPHIC space, per
  # element and per fraction, to answer: where are the regions of elevated
  # concentration, the hotspots?
  #
  # Method: take the ELEVATED readings only (top HIGH_Q quantile of the metric within
  # each element x fraction), project their locations to kilometres with a sinusoidal
  # (equal-area) projection, and run DBSCAN on those points. A dense cluster of
  # co-located high readings is a hotspot; an isolated high reading is DBSCAN "noise"
  # (a one-off, not a hotspot). The metric matches the facies page and the pipeline
  # rule: BULK on metal / Fe (enrichment, grain-size removed), SIEVED on raw value_std.
  #
  # DBSCAN is implemented inline (classic algorithm, Euclidean distance on the
  # projected km coordinates) to avoid adding a package to the renv-managed pipeline;
  # the elevated-point counts are small (a few hundred to ~2,200 per run) so an O(n^2)
  # distance matrix is trivial. Two parameters: EPS_KM (neighbourhood radius) and
  # MINPTS (min points, self included, for a dense core).
  #
  # Hotspots are labelled by the modal sea_name of their members, so the table reads
  # without a map. Distributional outliers are dropped. Bulk and sieved never pooled.
  #
  # Caveat carried on the page: DBSCAN uses one global eps, but marine sampling density
  # is very uneven (dense fjords, sparse open sea), so a single radius over- or
  # under-merges in places; and a bulk "hotspot" on metal/Fe is an enrichment hotspot,
  # not necessarily a high-total-concentration one.
  #
  # Outputs -> data/analysis/hotspots/ (gitignored):
  #   merged_hotspots_summary.csv  per element x fraction: n_high, n_hotspots, % clustered
  #   merged_hotspots_top.csv      the largest hotspots, named by sea area
  #   merged_hotspots_points.csv   elevated points + hotspot id (0 = isolated) for maps
  #   merged_hotspots_meta.csv     one-row config

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)
  ELEMS   <- c("CU", "ZN", "MN", "CO")   # dense enough for spatial density
  NORM    <- "FE"
  HIGH_Q  <- 0.80                        # "elevated" = top 20% of the metric
  EPS_KM  <- 20                          # DBSCAN neighbourhood radius (km)
  MINPTS  <- 5L                          # DBSCAN min core size (self included)
  R_EARTH <- 6371                        # km

  out_dir <- file.path(out_dir, "hotspots")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── DBSCAN (classic), coords = n x 2 matrix in km ────────────────────────────
  dbscan_km <- function(coords, eps, minPts) {
    n <- nrow(coords)
    if (n == 0) return(integer(0))
    D <- as.matrix(dist(coords))
    labels  <- integer(n)      # 0 = noise/unassigned
    visited <- logical(n)
    cid <- 0L
    for (i in seq_len(n)) {
      if (visited[i]) next
      visited[i] <- TRUE
      nb <- which(D[i, ] <= eps)                 # includes self
      if (length(nb) < minPts) next              # leave as noise (0)
      cid <- cid + 1L
      labels[i] <- cid
      seeds <- setdiff(nb, i)
      k <- 1L
      while (k <= length(seeds)) {
        j <- seeds[k]
        if (!visited[j]) {
          visited[j] <- TRUE
          nbj <- which(D[j, ] <= eps)
          if (length(nbj) >= minPts) seeds <- union(seeds, nbj)   # j is a core point
        }
        if (labels[j] == 0L) labels[j] <- cid    # assign border/core
        k <- k + 1L
      }
    }
    labels
  }

  # ── 1. Pull chemistry + location, one row per subsample ──────────────────────
  con <- dbConnect(SQLite(), db_path)
  raw <- dbGetQuery(con, sprintf("
    SELECT m.subsample_id, m.frac_class, m.symbol, m.value_std,
           si.latitude, si.longitude, si.sea_name
    FROM measurement m
    JOIN subsample s ON s.subsample_id = m.subsample_id
    JOIN event e     ON e.event_id     = s.event_id
    JOIN site  si    ON si.site_id     = e.site_id
    WHERE m.value_std > 0 AND m.outlier_flag IS NULL
      AND m.frac_class IN ('bulk','sieved')
      AND m.symbol IN (%s)
  ", paste(sprintf("'%s'", c(ELEMS, NORM)), collapse = ", "))) |> as_tibble()
  dbDisconnect(con)

  wide <- raw |>
    group_by(subsample_id, frac_class, latitude, longitude, sea_name, symbol) |>
    summarise(v = mean(value_std), .groups = "drop") |>
    pivot_wider(names_from = symbol, values_from = v)

  lon0 <- mean(wide$longitude, na.rm = TRUE)
  project_km <- function(lon, lat) {
    lat_r <- lat * pi / 180
    cbind(x = R_EARTH * (lon - lon0) * pi / 180 * cos(lat_r),
          y = R_EARTH * lat_r)
  }

  # ── 2. Run one element x fraction ────────────────────────────────────────────
  run_one <- function(sym, fraction) {
    d <- wide |> filter(frac_class == fraction, !is.na(.data[[sym]]), .data[[sym]] > 0)
    if (fraction == "bulk") {
      d <- d |> filter(!is.na(.data[[NORM]]), .data[[NORM]] > 0) |>
        mutate(metric = .data[[sym]] / .data[[NORM]], value = .data[[sym]])
    } else {
      d <- d |> mutate(metric = .data[[sym]], value = .data[[sym]])
    }
    if (nrow(d) < 50) return(NULL)

    thr  <- quantile(d$metric, HIGH_Q, names = FALSE)
    high <- d |> filter(metric >= thr) |> arrange(subsample_id)
    if (nrow(high) < MINPTS) return(NULL)

    xy  <- project_km(high$longitude, high$latitude)
    lab <- dbscan_km(xy, EPS_KM, MINPTS)

    pts <- high |>
      transmute(symbol = sym, frac_class = fraction, hotspot_id = lab,
                longitude = round(longitude, 4), latitude = round(latitude, 4),
                sea_name, value = signif(value, 4), metric = signif(metric, 5))
    pts
  }

  runs <- expand_grid(symbol = ELEMS, frac_class = c("bulk", "sieved"))
  points <- pmap(runs, function(symbol, frac_class) run_one(symbol, frac_class)) |>
    compact() |> bind_rows()

  # ── 3. Summaries ─────────────────────────────────────────────────────────────
  summary_tbl <- points |>
    group_by(symbol, frac_class) |>
    summarise(n_high      = n(),
              n_hotspots  = n_distinct(hotspot_id[hotspot_id > 0]),
              n_clustered = sum(hotspot_id > 0),
              n_isolated  = sum(hotspot_id == 0),
              pct_clustered = round(100 * mean(hotspot_id > 0)),
              .groups = "drop") |>
    arrange(frac_class, symbol)

  # per hotspot: size, modal sea area, centroid, median level
  modal <- function(x) { x <- x[!is.na(x)]; if (!length(x)) return(NA_character_)
                         names(sort(table(x), decreasing = TRUE))[1] }
  top_tbl <- points |>
    filter(hotspot_id > 0) |>
    group_by(symbol, frac_class, hotspot_id) |>
    summarise(n = n(), sea_area = modal(sea_name),
              lon = round(median(longitude), 2), lat = round(median(latitude), 2),
              median_value = signif(median(value), 4),
              median_metric = signif(median(metric), 4), .groups = "drop") |>
    group_by(symbol, frac_class) |>
    slice_max(n, n = 6, with_ties = FALSE) |>
    mutate(rank = row_number()) |>
    ungroup() |>
    arrange(frac_class, symbol, rank)

  meta <- tibble(elements = paste(ELEMS, collapse = ","),
                 bulk_metric = sprintf("metal/%s", NORM), sieved_metric = "raw value_std",
                 high_quantile = HIGH_Q, eps_km = EPS_KM, minpts = MINPTS,
                 n_runs = nrow(distinct(points, symbol, frac_class)))

  # ── 4. Write outputs ─────────────────────────────────────────────────────────
  write_csv(summary_tbl, file.path(out_dir, "merged_hotspots_summary.csv"))
  write_csv(top_tbl,     file.path(out_dir, "merged_hotspots_top.csv"))
  write_csv(points,      file.path(out_dir, "merged_hotspots_points.csv"))
  write_csv(meta,        file.path(out_dir, "merged_hotspots_meta.csv"))

  if (verbose) {
    # ── 5. Console summary ───────────────────────────────────────────────────────
    cat("merged hotspots written to", out_dir, "\n")
    cat(sprintf("elevated = top %d%% of metric; DBSCAN eps=%d km, minPts=%d\n\n",
                round(100 * (1 - HIGH_Q)), EPS_KM, MINPTS))
    cat("hotspots per element x fraction:\n")
    summary_tbl |> as.data.frame() |> print(row.names = FALSE)
    cat("\nlargest hotspots (by sea area):\n")
    top_tbl |> filter(rank <= 3) |>
      select(symbol, frac_class, n, sea_area, median_value) |>
      as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
