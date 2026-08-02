library(DBI)
library(RSQLite)
library(tidyverse)
library(cluster)

# ── Analysis stage, geochemical facies clustering (MERGED database) ───────────
# The first of a new Clustering family. Unsupervised structure in the multi-source
# merged data: are there distinct multi-element compositional signatures ("facies")
# in the sediment chemistry, and where do they fall geographically?
#
# Approach: K-means in CHEMISTRY space (not geographic space), per fraction. The
# feature vector is the four best-covered targets, CU / ZN / MN / CO:
#   - BULK   -> each as a ratio to iron (metal / Fe), the grain-size normaliser, so
#              a cluster reflects an ENRICHMENT signature rather than how muddy the
#              grab happened to be (raw metals would just split mud from sand).
#   - SIEVED -> raw value_std (the <63/<20um cut already controls grain size, so no
#              iron normalisation), per the pipeline's bulk-normalised/sieved-raw rule.
# Features are log10-transformed (metals are log-normal) then z-scored (so no single
# element dominates the Euclidean distance). Location is NOT a clustering feature; it
# is kept only to MAP the resulting labels (clustering in chemistry, shown in space),
# which sidesteps the degree-anisotropy and chemistry-vs-distance weighting traps.
#
# Bulk and sieved are clustered separately (never pooled) and k is chosen per
# fraction. Complete cases only (a subsample must carry all four targets, plus Fe for
# the bulk ratios); the wider 7-target set has no complete cases, so MO/SE/I are out.
# Distributional outliers (outlier_flag) are dropped.
#
# k is DATA-DRIVEN: sweep k = 2..8, refit with many restarts, and score each k by
# mean silhouette width (separation) with total within-cluster SS for the elbow. The
# chosen k maximises mean silhouette; the sweep is written out so the page shows the
# diagnostic behind the choice.
#
# Outputs -> data/analysis/clustering/ (gitignored):
#   merged_clustering_kselect.csv     k sweep: fraction x k -> wss, mean silhouette
#   merged_clustering_centroids.csv   chosen-k facies signatures (per-cluster medians)
#   merged_clustering_assignments.csv per-subsample cluster + location + features
#   merged_clustering_meta.csv        one-row config / cohort description

set.seed(42)

# ── 0. Config ────────────────────────────────────────────────────────────────
db_path <- "./data/db/multised_merged.sqlite"
CORE    <- c("CU", "ZN", "MN", "CO")   # facies features (best-covered targets)
NORM    <- "FE"                        # bulk normaliser (metal / Fe)
K_RANGE <- 2:8
SIL_MAX <- 2500L                       # subsample size for the O(n^2) silhouette

out_dir <- "data/analysis/clustering"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── 1. Pull the covered chemistry + location, per subsample ──────────────────
con <- dbConnect(SQLite(), db_path)
raw <- dbGetQuery(con, sprintf("
  SELECT m.subsample_id, m.frac_class, m.symbol, m.value_std,
         si.latitude, si.longitude
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
  group_by(subsample_id, frac_class, latitude, longitude, symbol) |>
  summarise(v = mean(value_std), .groups = "drop") |>
  pivot_wider(names_from = symbol, values_from = v)

# ── 2. Build the per-fraction feature matrix ─────────────────────────────────
# bulk: log10(metal / Fe); sieved: log10(metal). Returns the interpretable feature
# frame (feat_*) alongside ids/location, complete cases only.
build_features <- function(df, fraction) {
  d <- df |> filter(frac_class == fraction)
  if (fraction == "bulk") {
    d <- d |> filter(if_all(all_of(c(CORE, NORM)), ~ !is.na(.) & . > 0))
    for (m in CORE) d[[paste0("feat_", m)]] <- d[[m]] / d[[NORM]]
  } else {
    d <- d |> filter(if_all(all_of(CORE), ~ !is.na(.) & . > 0))
    for (m in CORE) d[[paste0("feat_", m)]] <- d[[m]]
  }
  d |> select(subsample_id, frac_class, latitude, longitude,
              all_of(paste0("feat_", CORE)))
}

# ── 3. k sweep + final fit for one fraction ──────────────────────────────────
cluster_fraction <- function(feats, fraction) {
  fcols <- paste0("feat_", CORE)
  X <- log10(as.matrix(feats[, fcols]))
  Z <- scale(X)                                   # z-score each feature
  n <- nrow(Z)

  # silhouette on a capped subsample (full distance matrix is O(n^2))
  idx <- if (n > SIL_MAX) sort(sample.int(n, SIL_MAX)) else seq_len(n)
  Dsub <- dist(Z[idx, , drop = FALSE])

  sweep <- map_dfr(K_RANGE, function(k) {
    km <- kmeans(Z, centers = k, nstart = 25, iter.max = 50)
    sil <- silhouette(km$cluster[idx], Dsub)
    tibble(fraction = fraction, k = k,
           wss = km$tot.withinss,
           mean_sil = mean(sil[, "sil_width"]))
  })

  k_best <- sweep$k[which.max(sweep$mean_sil)]
  km <- kmeans(Z, centers = k_best, nstart = 50, iter.max = 100)

  # order clusters by overall enrichment (mean z across features) for stable labels
  ord <- order(tapply(rowMeans(Z), km$cluster, mean))
  relabel <- setNames(seq_along(ord), ord)
  cl <- relabel[as.character(km$cluster)]

  assign <- feats |>
    mutate(k_chosen = k_best, cluster = as.integer(cl)) |>
    mutate(across(all_of(fcols), ~ round(.x, 4)))

  list(sweep = sweep, k_best = k_best, assign = assign)
}

# ── 4. Run both fractions ────────────────────────────────────────────────────
results <- map(c("bulk", "sieved"), function(fr) {
  feats <- build_features(wide, fr)
  cluster_fraction(feats, fr)
})
names(results) <- c("bulk", "sieved")

kselect <- bind_rows(lapply(results, `[[`, "sweep")) |>
  mutate(wss = round(wss, 1), mean_sil = round(mean_sil, 4))

assignments <- bind_rows(lapply(results, `[[`, "assign"))

# facies signatures: per-cluster median of each interpretable feature (metal/Fe for
# bulk, raw mg/kg for sieved) + size
centroids <- assignments |>
  pivot_longer(starts_with("feat_"), names_to = "feature", values_to = "val") |>
  mutate(feature = str_remove(feature, "^feat_")) |>
  group_by(frac_class, k_chosen, cluster, feature) |>
  summarise(median = median(val), .groups = "drop") |>
  mutate(median = signif(median, 4),
         feature = factor(feature, levels = CORE)) |>
  arrange(frac_class, cluster, feature)

sizes <- assignments |> count(frac_class, cluster, name = "n")

meta <- tibble(
  features   = paste(CORE, collapse = ","),
  bulk_basis = sprintf("metal/%s (log10, z-scored)", NORM),
  sieved_basis = "raw value_std (log10, z-scored)",
  k_bulk     = results$bulk$k_best,
  k_sieved   = results$sieved$k_best,
  n_bulk     = sum(assignments$frac_class == "bulk"),
  n_sieved   = sum(assignments$frac_class == "sieved"))

# ── 5. Write outputs ─────────────────────────────────────────────────────────
write_csv(kselect,     file.path(out_dir, "merged_clustering_kselect.csv"))
write_csv(left_join(centroids, sizes, by = c("frac_class", "cluster")),
          file.path(out_dir, "merged_clustering_centroids.csv"))
write_csv(assignments, file.path(out_dir, "merged_clustering_assignments.csv"))
write_csv(meta,        file.path(out_dir, "merged_clustering_meta.csv"))

# ── 6. Console summary ───────────────────────────────────────────────────────
cat("merged clustering written to", out_dir, "\n\n")
cat("cohort:", meta$n_bulk, "bulk /", meta$n_sieved, "sieved complete cases\n")
cat("chosen k: bulk =", meta$k_bulk, " sieved =", meta$k_sieved, "\n\n")
cat("k sweep (mean silhouette, higher = better separated):\n")
kselect |> select(fraction, k, mean_sil) |>
  pivot_wider(names_from = fraction, values_from = mean_sil) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\nfacies signatures (per-cluster medians):\n")
left_join(centroids, sizes, by = c("frac_class", "cluster")) |>
  pivot_wider(names_from = feature, values_from = median) |>
  as.data.frame() |> print(row.names = FALSE)
