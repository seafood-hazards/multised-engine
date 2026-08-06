# ── Analysis, clean generation: uncertainty ──────────────────────────────
# Converted from R/analysis/uncertainty/01_clean_uncertainty.R. The body is unchanged; only the
# hardcoded paths and the console output are parameterised.

analysis_clean_uncertainty <- function(db_dir = multised_db_dir(),
                                       out_dir = multised_analysis_dir(),
                                       verbose = TRUE) {
  # ── Analysis stage, measurement uncertainty (value_uncrt) ────────────────────
  # The clean `measurement` table carries value_uncrt (measurement uncertainty,
  # mg/kg), populated only for ICES-DOME (from its ICES uncrt/metcu fields). This is
  # an exploratory pass: how much of the data carries it, and how it behaves, so we
  # can decide whether and how to use it.
  #
  # Key question: is value_uncrt an ABSOLUTE spread, or effectively a RELATIVE
  # uncertainty (roughly constant uncrt / value per element)? The relative form is
  # what would let it be reused as an error bar or a weight.
  #
  # Outputs -> data/analysis/uncertainty/ (gitignored):
  #   uncertainty_coverage.csv    per-source coverage of value_uncrt
  #   uncertainty_by_element.csv  per-element value / uncertainty / relative %
  #   uncertainty_pairs.csv       per-measurement value_std vs value_uncrt (ICES)
  #   uncertainty_rel_values.csv  most common relative-% values (method vs measured)
  #   uncertainty_by_method.csv   per (element, method, lab): is the relative % constant?

  sources <- tibble(
    Source = c("Mareano", "Vannmilj\u00f8", "ICES-DOME", "MUDAB", "4Demon"),
    stem   = c("mareano", "vannmiljo", "ices_dome", "mudab", "4demon"))

  CHEM <- c("target", "reference", "organic")

  out_dir <- file.path(out_dir, "uncertainty")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  # ── 1. Coverage per source ───────────────────────────────────────────────────
  coverage <- pmap_dfr(sources, function(Source, stem) {
    con <- dbConnect(SQLite(), file.path(db_dir, sprintf("%s_clean.sqlite", stem)))
    on.exit(dbDisconnect(con))
    cols <- dbGetQuery(con, "PRAGMA table_info(measurement)")$name
    if (!"value_uncrt" %in% cols)
      return(tibble(Source = Source, total = dbGetQuery(con,
        "SELECT COUNT(*) n FROM measurement")$n, has_uncrt = 0L))
    q <- dbGetQuery(con, "SELECT COUNT(*) total, SUM(value_uncrt IS NOT NULL) has_uncrt
                          FROM measurement")
    tibble(Source = Source, total = q$total, has_uncrt = as.integer(q$has_uncrt))
  }) |>
    mutate(pct = round(100 * has_uncrt / total, 1))

  # ── 2. ICES-DOME chemistry rows that carry uncertainty ───────────────────────
  con <- dbConnect(SQLite(), file.path(db_dir, "ices_dome_clean.sqlite"))
  m <- dbGetQuery(con,
    "SELECT ms.symbol, e.category, ms.value_std, ms.value_uncrt, ms.frac_class,
            ms.method_id, mt.method, mt.lab
     FROM measurement ms JOIN element e ON ms.symbol = e.symbol
     LEFT JOIN method mt ON ms.method_id = mt.method_id
     WHERE ms.value_uncrt IS NOT NULL AND ms.value_std > 0 AND ms.value_uncrt > 0") |>
    as_tibble() |>
    filter(category %in% CHEM) |>
    mutate(rel = value_uncrt / value_std, rel_pct = round(100 * rel, 2))
  dbDisconnect(con)

  # ── 3. Per-element summary ───────────────────────────────────────────────────
  by_element <- m |>
    group_by(category, symbol) |>
    summarise(n = n(),
              med_value = round(median(value_std), 3),
              med_uncrt = round(median(value_uncrt), 3),
              med_rel_pct = round(100 * median(rel), 1),
              p25_rel_pct = round(100 * quantile(rel, 0.25), 1),
              p75_rel_pct = round(100 * quantile(rel, 0.75), 1),
              .groups = "drop") |>
    arrange(factor(category, levels = CHEM), desc(n))

  # ── 3b. Is the relative uncertainty a per-method constant? ───────────────────
  # Most common relative-% values: genuine per-sample estimates would not pile up on
  # round numbers; method/lab-declared uncertainties do.
  rel_values <- m |>
    count(rel_pct, sort = TRUE) |>
    mutate(share_pct = round(100 * n / sum(n), 2)) |>
    slice_head(n = 15)

  # Within each analytical method record (element, method_id, lab): how many distinct
  # relative-% values? One value = a fixed nominal figure applied to every measurement;
  # many = measured per sample.
  by_method <- m |>
    group_by(symbol, method_id, lab) |>
    summarise(method = first(method), n = n(), n_distinct_rel = n_distinct(rel_pct),
              rel_median_pct = round(median(rel_pct), 1),
              constant = n_distinct_rel == 1L, few = n_distinct_rel <= 3L,
              .groups = "drop") |>
    filter(n >= 20) |>
    select(symbol, method, lab, n, n_distinct_rel, rel_median_pct, constant, few) |>
    arrange(desc(n))

  # ── 4. Pairs for the figures (sampled if very large) ─────────────────────────
  set.seed(1)
  pairs <- m |>
    transmute(category, symbol, value_std, value_uncrt, rel) |>
    group_by(symbol) |>
    slice_sample(n = 3000) |>   # caps per element (returns all rows if fewer)
    ungroup()

  # ── 5. Write outputs ─────────────────────────────────────────────────────────
  write_csv(coverage,   file.path(out_dir, "uncertainty_coverage.csv"))
  write_csv(by_element, file.path(out_dir, "uncertainty_by_element.csv"))
  write_csv(pairs,      file.path(out_dir, "uncertainty_pairs.csv"))
  write_csv(rel_values, file.path(out_dir, "uncertainty_rel_values.csv"))
  write_csv(by_method,  file.path(out_dir, "uncertainty_by_method.csv"))

  if (verbose) {
    # ── 6. Console summary ───────────────────────────────────────────────────────
    cat("uncertainty analysis written to", out_dir, "\n")
    cat("\ncoverage:\n"); print(as.data.frame(coverage), row.names = FALSE)
    cat("\nper element (relative uncertainty, %):\n")
    by_element |> select(symbol, n, med_value, med_rel_pct, p25_rel_pct, p75_rel_pct) |>
      as.data.frame() |> print(row.names = FALSE)
    cat("\nper-method constancy (", nrow(by_method), " method/lab groups, n>=20): ",
        sum(by_method$constant), " single-valued (", round(100 * mean(by_method$constant)),
        "%), ", sum(by_method$few), " with <=3 values (", round(100 * mean(by_method$few)),
        "%)\n", sep = "")
  }

  invisible(out_dir)
}
