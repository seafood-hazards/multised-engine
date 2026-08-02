library(DBI)
library(RSQLite)
library(tidyverse)

# ── Analysis stage, distribution-mixture background (REFINED database) ────────
# The fifth background page. It uses the SHAPE of the concentration distribution alone,
# with no spatial or pressure information: a concentration distribution is often a
# mixture of a natural (background) population and an enriched one. Fitting a two-
# component Gaussian mixture to log10(value_std) separates them, and the crossover
# between the two components is a data-driven background threshold (upper bound of the
# natural population). No external reference, no offshore/aquaculture filter.
#
# The two-component 1-D EM is implemented inline (no mixture package in the renv). It is
# run per element x fraction on the RAW value (mg/kg, EFSA's unit); because raw values
# carry grain size, a muddy/sandy split can masquerade as background/enriched, so this is
# the distribution-only view to be read against the grain-size-normalised, offshore and
# EF pages. Fractions bulk/sieved63/sieved20; outliers dropped; groups with < MIN_N or
# with no clear two-population separation are flagged.
#
# Outputs -> data/analysis/background/ (gitignored):
#   refined_mixture_components.csv  per element x fraction: the fitted components + threshold
#   refined_mixture_hist.csv        log10 histogram bins (bulk) for the figure
#   refined_mixture_meta.csv        one-row config

db_path <- "./data/db/multised_refined.sqlite"
CATS  <- c("bulk", "sieved63", "sieved20")
MIN_N <- 100L
elem_levels <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")

out_dir <- "data/analysis/background"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ── Two-component 1-D Gaussian mixture via EM ────────────────────────────────
# returns background/enriched means (log10), sds, weights, the crossover threshold
# (log10) and whether the two populations are meaningfully separated.
em2 <- function(x, iters = 300, tol = 1e-7) {
  x <- x[is.finite(x)]
  fit_from <- function(mu) {
    sigma <- rep(sd(x) / 2, 2); lambda <- c(.5, .5); ll_old <- -Inf
    for (i in seq_len(iters)) {
      d1 <- lambda[1] * dnorm(x, mu[1], sigma[1])
      d2 <- lambda[2] * dnorm(x, mu[2], sigma[2])
      tot <- d1 + d2; tot[tot < .Machine$double.xmin] <- .Machine$double.xmin
      r1 <- d1 / tot; r2 <- 1 - r1
      s1 <- sum(r1); s2 <- sum(r2)
      lambda <- c(s1, s2) / length(x)
      mu <- c(sum(r1 * x) / s1, sum(r2 * x) / s2)
      sigma <- sqrt(c(sum(r1 * (x - mu[1])^2) / s1, sum(r2 * (x - mu[2])^2) / s2))
      sigma[sigma < 1e-3] <- 1e-3
      ll <- sum(log(tot))
      if (is.finite(ll) && abs(ll - ll_old) < tol) break
      ll_old <- ll
    }
    list(mu = mu, sigma = sigma, lambda = lambda, ll = ll_old)
  }
  # two deterministic inits (quartile split, decile split); keep the better fit
  cand <- list(fit_from(quantile(x, c(.25, .75), names = FALSE)),
               fit_from(quantile(x, c(.10, .90), names = FALSE)))
  f <- cand[[which.max(vapply(cand, function(z) z$ll, numeric(1)))]]
  o <- order(f$mu)                      # component 1 = background (lower mean)
  mu <- f$mu[o]; sigma <- f$sigma[o]; lambda <- f$lambda[o]

  # crossover in (mu_bg, mu_en): where P(enriched | x) crosses 0.5
  grid <- seq(mu[1], mu[2], length.out = 2000)
  d1 <- lambda[1] * dnorm(grid, mu[1], sigma[1])
  d2 <- lambda[2] * dnorm(grid, mu[2], sigma[2])
  thr <- grid[which.min(abs(d2 / (d1 + d2) - 0.5))]

  # separated: both weights non-trivial and means apart by >= a pooled sd
  separated <- min(lambda) >= 0.05 && (mu[2] - mu[1]) >= mean(sigma)
  list(mu = mu, sigma = sigma, lambda = lambda, threshold = thr, separated = separated)
}

# ── 1. Pull chemistry, categorise by fraction ────────────────────────────────
con <- dbConnect(SQLite(), db_path)
m <- as_tibble(dbGetQuery(con, "
  SELECT symbol, frac_class, sieve_um_std, value_std
  FROM measurement WHERE value_std > 0 AND outlier_flag IS NULL")) |>
  mutate(cat = case_when(frac_class == "bulk" ~ "bulk",
                         sieve_um_std == 63 ~ "sieved63",
                         sieve_um_std == 20 ~ "sieved20",
                         TRUE ~ NA_character_)) |>
  filter(cat %in% CATS)
dbDisconnect(con)

# ── 2. Fit the mixture per element x fraction ────────────────────────────────
groups <- m |> group_by(symbol, cat) |> filter(n() >= MIN_N) |> group_split()

components <- map_dfr(groups, function(g) {
  f <- em2(log10(g$value_std))
  tibble(symbol = g$symbol[1], cat = g$cat[1], n = nrow(g),
         lambda_bg = round(f$lambda[1], 3),
         gm_bg = signif(10^f$mu[1], 4),           # background geometric mean (mg/kg)
         sd_bg_log = round(f$sigma[1], 3),
         gm_en = signif(10^f$mu[2], 4),           # enriched geometric mean (mg/kg)
         sd_en_log = round(f$sigma[2], 3),
         threshold = signif(10^f$threshold, 4),   # background upper bound (mg/kg)
         pct_bg = round(100 * mean(log10(g$value_std) < f$threshold)),
         separated = f$separated)
}) |>
  mutate(symbol = factor(symbol, levels = elem_levels), cat = factor(cat, levels = CATS)) |>
  arrange(symbol, cat)

# ── 3. Histograms (bulk) for the figure ──────────────────────────────────────
hist_tbl <- m |>
  filter(cat == "bulk", symbol %in% c("CO", "CU", "MN", "MO", "SE", "ZN")) |>
  mutate(lv = log10(value_std)) |>
  group_by(symbol) |>
  group_modify(~{
    br <- seq(min(.x$lv), max(.x$lv), length.out = 31)
    mid <- (head(br, -1) + tail(br, -1)) / 2
    cnt <- hist(.x$lv, breaks = br, plot = FALSE)$counts
    tibble(bin_mid = round(mid, 3), count = cnt)
  }) |>
  ungroup() |>
  mutate(symbol = factor(symbol, levels = elem_levels))

meta <- tibble(model = "2-component Gaussian mixture (EM) on log10(value_std)",
               min_n = MIN_N, basis = "raw value_std (mg/kg)",
               threshold = "crossover between the two components (background upper bound)")

# ── 4. Write ─────────────────────────────────────────────────────────────────
write_csv(components, file.path(out_dir, "refined_mixture_components.csv"))
write_csv(hist_tbl,   file.path(out_dir, "refined_mixture_hist.csv"))
write_csv(meta,       file.path(out_dir, "refined_mixture_meta.csv"))

# ── 5. Console summary ───────────────────────────────────────────────────────
cat("distribution-mixture background written to", out_dir, "\n\n")
cat("bulk: background geom-mean, threshold (mg/kg), % background, separated:\n")
components |> filter(cat == "bulk") |>
  select(symbol, n, gm_bg, threshold, pct_bg, separated) |> as.data.frame() |> print(row.names = FALSE)
