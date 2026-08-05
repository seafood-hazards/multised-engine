# ── Analysis, merged generation: regions ─────────────────────────────────
# Converted from R/analysis/regions/01_merged_regions.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_merged_regions <- function(db_dir = multised_db_dir(),
                                    out_dir = multised_analysis_dir(),
                                    verbose = TRUE) {
  # ── Analysis stage, spatial-geochemical regions (MERGED database) ─────────────
  # The third Clustering page, combining the two views the first two separate:
  #   - Geochemical Facies clusters on CHEMISTRY only (a facies can be scattered).
  #   - Spatial Hotspots clusters on LOCATION + a single elevated element.
  # Here we cluster on LOCATION AND the full multi-element composition TOGETHER, so a
  # cluster is a spatially-contiguous region that shares a geochemical signature: a
  # regionalisation of the sea floor by chemistry.
  #
  # The catch is weighting: in one Euclidean space, how much should geography count
  # against chemistry? We make that explicit. Each feature is standardised, then each
  # BLOCK (2 location dims, 4 chemistry dims) is scaled to unit total variance so the
  # dimension count does not decide the balance, and a single LOC_WEIGHT multiplies the
  # location block. LOC_WEIGHT = 0 is pure chemistry (= the facies page); large weight
  # is pure geography (a plain spatial partition); LOC_WEIGHT = 1 balances them.
  #
  # To keep the comparison to the facies page clean, k is FIXED to the facies k per
  # fraction (bulk 4, sieved 2) and the LOCATION WEIGHT is the swept axis. The sweep is
  # reported as a tradeoff curve (geographic vs chemical dispersion) so the balance is
  # transparent; the primary output (map, signatures) is at the balanced weight.
  #
  # Features/rule as the facies page: CU/ZN/MN/CO, BULK on metal/Fe, SIEVED on raw,
  # log10 + z-scored. Bulk and sieved never pooled; complete cases only; outliers
  # dropped. Location projected to km with a sinusoidal (equal-area) projection.
  #
  # Outputs -> data/analysis/regions/ (gitignored):
  #   merged_regions_weightsweep.csv  fraction x loc_weight -> geo/chem dispersion
  #   merged_regions_assignments.csv  per-subsample region + location + features (w=1)
  #   merged_regions_signature.csv    per-region size, sea area, centroid, chem medians
  #   merged_regions_meta.csv         one-row config

  set.seed(42)

  # ── 0. Config ────────────────────────────────────────────────────────────────
  db_path <- merged_db_path(db_dir)
  CORE    <- c("CU", "ZN", "MN", "CO")
  NORM    <- "FE"
  K_FRAC  <- c(bulk = 4L, sieved = 2L)   # fixed to the facies-page k per fraction
  WEIGHTS <- c(0, 0.25, 0.5, 1, 2, 4)    # location-weight sweep
  W_MAIN  <- 1                           # balanced weight for the primary output
  R_EARTH <- 6371

  out_dir <- file.path(out_dir, "regions")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  modal <- function(x) { x <- x[!is.na(x)]; if (!length(x)) return(NA_character_)
                         names(sort(table(x), decreasing = TRUE))[1] }

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
  ", paste(sprintf("'%s'", c(CORE, NORM)), collapse = ", "))) |> as_tibble()
  dbDisconnect(con)

  wide <- raw |>
    group_by(subsample_id, frac_class, latitude, longitude, sea_name, symbol) |>
    summarise(v = mean(value_std), .groups = "drop") |>
    pivot_wider(names_from = symbol, values_from = v)

  lon0 <- mean(wide$longitude, na.rm = TRUE)
  project_km <- function(lon, lat) {
    lat_r <- lat * pi / 180
    cbind(x = R_EARTH * (lon - lon0) * pi / 180 * cos(lat_r), y = R_EARTH * lat_r)
  }

  # interpretable feature frame per fraction (bulk metal/Fe, sieved raw), complete cases
  build <- function(fraction) {
    d <- wide |> filter(frac_class == fraction)
    if (fraction == "bulk") {
      d <- d |> filter(if_all(all_of(c(CORE, NORM)), ~ !is.na(.) & . > 0))
      for (m in CORE) d[[paste0("feat_", m)]] <- d[[m]] / d[[NORM]]
    } else {
      d <- d |> filter(if_all(all_of(CORE), ~ !is.na(.) & . > 0))
      for (m in CORE) d[[paste0("feat_", m)]] <- d[[m]]
    }
    d |> select(subsample_id, frac_class, latitude, longitude, sea_name,
                all_of(paste0("feat_", CORE)))
  }

  # ── 2. Combined clustering for one fraction ──────────────────────────────────
  # returns the weight sweep (dispersions) and the assignment at W_MAIN
  cluster_fraction <- function(feats, fraction) {
    fcols <- paste0("feat_", CORE)
    Zchem <- scale(log10(as.matrix(feats[, fcols])))     # n x 4, unit-variance cols
    km_xy <- project_km(feats$longitude, feats$latitude) # raw km, for dispersion
    Zgeo  <- scale(km_xy)                                 # n x 2, unit-variance cols
    # block-normalise so each block has unit TOTAL variance regardless of dim count
    Cb <- Zchem / sqrt(ncol(Zchem))
    Gb <- Zgeo  / sqrt(ncol(Zgeo))
    k  <- K_FRAC[[fraction]]

    # geographic (km) / chemical (z) within-cluster dispersion for an assignment
    disp <- function(cl) {
      geo <- mean(tapply(seq_along(cl), cl, function(ix)
        mean(sqrt(rowSums((km_xy[ix, , drop = FALSE] -
                           rep(colMeans(km_xy[ix, , drop = FALSE]),
                               each = length(ix)))^2)))))
      chem <- mean(tapply(seq_along(cl), cl, function(ix)
        mean(sqrt(rowSums((Zchem[ix, , drop = FALSE] -
                           rep(colMeans(Zchem[ix, , drop = FALSE]),
                               each = length(ix)))^2)))))
      c(geo_km = geo, chem = chem)
    }

    sweep <- map_dfr(WEIGHTS, function(w) {
      X <- cbind(Cb, w * Gb)
      cl <- kmeans(X, centers = k, nstart = 25, iter.max = 100)$cluster
      d <- disp(cl)
      tibble(fraction = fraction, loc_weight = w,
             geo_km = d[["geo_km"]], chem = d[["chem"]])
    })

    # primary assignment at the balanced weight
    Xm <- cbind(Cb, W_MAIN * Gb)
    km <- kmeans(Xm, centers = k, nstart = 50, iter.max = 100)
    ord <- order(tapply(rowMeans(Zchem), km$cluster, mean))
    relab <- setNames(seq_along(ord), ord)
    region <- as.integer(relab[as.character(km$cluster)])

    assign <- feats |>
      mutate(region = region) |>
      mutate(across(all_of(fcols), ~ round(.x, 4)))
    list(sweep = sweep, assign = assign)
  }

  # ── 3. Run both fractions ────────────────────────────────────────────────────
  res <- map(c("bulk", "sieved"), function(fr) cluster_fraction(build(fr), fr))
  names(res) <- c("bulk", "sieved")

  weightsweep <- bind_rows(lapply(res, `[[`, "sweep")) |>
    mutate(geo_km = round(geo_km, 1), chem = round(chem, 4))

  assignments <- bind_rows(lapply(res, `[[`, "assign"))

  # per-region signature: size, sea area, centroid, chem medians
  signature <- assignments |>
    pivot_longer(starts_with("feat_"), names_to = "feature", values_to = "val") |>
    mutate(feature = factor(sub("^feat_", "", feature), levels = CORE)) |>
    group_by(frac_class, region, feature) |>
    summarise(median = signif(median(val), 4), .groups = "drop")
  region_geo <- assignments |>
    group_by(frac_class, region) |>
    summarise(n = n(), sea_area = modal(sea_name),
              lon = round(median(longitude), 2), lat = round(median(latitude), 2),
              .groups = "drop")
  signature <- left_join(signature, region_geo, by = c("frac_class", "region")) |>
    arrange(frac_class, region, feature)

  meta <- tibble(features = paste(CORE, collapse = ","),
                 bulk_metric = sprintf("metal/%s", NORM), sieved_metric = "raw value_std",
                 loc_weight_main = W_MAIN, k_bulk = K_FRAC[["bulk"]],
                 k_sieved = K_FRAC[["sieved"]],
                 n_bulk = sum(assignments$frac_class == "bulk"),
                 n_sieved = sum(assignments$frac_class == "sieved"))

  # ── 4. Write outputs ─────────────────────────────────────────────────────────
  write_csv(weightsweep, file.path(out_dir, "merged_regions_weightsweep.csv"))
  write_csv(assignments, file.path(out_dir, "merged_regions_assignments.csv"))
  write_csv(signature,   file.path(out_dir, "merged_regions_signature.csv"))
  write_csv(meta,        file.path(out_dir, "merged_regions_meta.csv"))

  if (verbose) {
    # ── 5. Console summary ───────────────────────────────────────────────────────
    cat("merged regions written to", out_dir, "\n\n")
    cat("cohort:", meta$n_bulk, "bulk /", meta$n_sieved, "sieved; k bulk/sieved =",
        meta$k_bulk, "/", meta$k_sieved, "; primary loc_weight =", W_MAIN, "\n\n")
    cat("weight sweep (geo dispersion km falls, chem dispersion rises as location weighs more):\n")
    weightsweep |> as.data.frame() |> print(row.names = FALSE)
    cat("\nregions at balanced weight (size, sea area):\n")
    region_geo |> as.data.frame() |> print(row.names = FALSE)
  }

  invisible(out_dir)
}
