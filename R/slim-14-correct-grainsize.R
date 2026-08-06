# ── Slim step 14: correct grain-size ─────────────────────────────────────────
# Adds `measurement.value_std_corr` + `measurement.gs_corr`. Raw value /
# value_std are left untouched as provenance; the later fines step (15) reads
# value_std_corr.
#
# Source-specific, and present only for ICES-DOME, MUDAB and Vannmiljo. Two real
# variants: a per-curve renormalisation (ICES-DOME / MUDAB, whose bodies are
# identical) and an invalid-value flag (Vannmiljo).

# Cumulative "<n" cutoff in µm from a GSMF<n> code, NA for anything else.
gs_cutoff <- function(sym) as.numeric(str_match(sym, "^GSMF([0-9]+)$")[, 2])

# Only mass-fraction codes are rescaled (GSMF*, GS>a<b); grain-size statistics
# (GSMEA / GSMED / GSSORT / ...) are not fractions and are never touched.
gs_is_fraction <- function(sym) str_detect(sym, "^GSMF|^GS>")

# ICES-DOME / MUDAB: a large share of the grain-size curves are internally
# consistent (a monotone cumulative distribution) but scaled wrong: within one
# sample every code is inflated by the same factor, so value_std runs to
# thousands of "percent". Renormalise each such curve so its coarsest cutoff (the
# total, ~ the <2 mm fraction) reads 100 %.
#
# A grain-size curve is one (subsample, matrix) group. Only the cumulative "<n"
# codes GSMF<n> (GSMF63, GSMF2000, ...) define it; the ">n" gravel codes (GSMF>2000,
# GSMF>8000) and "_n" variants are not cumulative "<n" values and are excluded,
# else an anomalously large gravel value breaks the monotonicity check and wrongly
# rejects an otherwise correctable curve. The anchor is the largest value_std in
# the curve (the coarsest cutoff, i.e. the total). A curve is corrected only when
# it is over-scaled (anchor > 100.5 %) AND monotone (a valid cumulative shape after
# renormalising); factor = 100 / anchor. Everything else keeps factor 1.
slim_gs_renorm <- function(m) {
  curves <- m |>
    filter(category == "composition", !is.na(value_std), !is.na(gs_cutoff(symbol))) |>
    mutate(cut = gs_cutoff(symbol)) |>
    group_by(subsample_id, matrix) |>
    summarise(anchor   = max(value_std),
              monotone = all(diff(value_std[order(cut)]) >= -0.005 * max(value_std)),
              .groups  = "drop") |>
    mutate(factor = if_else(anchor > 100.5 & monotone & anchor > 0, 100 / anchor, 1))

  m |>
    left_join(curves |> select(subsample_id, matrix, factor),
              by = c("subsample_id", "matrix")) |>
    mutate(
      factor = coalesce(factor, 1),
      frac   = category == "composition" & gs_is_fraction(symbol),
      value_std_corr = if_else(frac & factor != 1, value_std * factor, value_std),
      gs_corr = case_when(
        frac & factor != 1                       ~ "renorm",
        frac & !is.na(value_std_corr) & value_std_corr > 100.5 ~ "suspect",
        TRUE                                     ~ NA_character_))
}

# Vannmiljo: the noise is not a whole-curve scale error but a handful of isolated
# values with an implausible magnitude. There is also no matrix column and the
# GSMF_63 / GSMF_2000 codes mean ">n µm" rather than "<n", so the per-curve
# renormalisation does not apply. These rows were exported
# (inst/scripts/export_vannmiljo_suspect_grainsize.R) and manually reviewed against
# the raw data: the error magnitude varies per row (x1000, x10, borderline) and the
# values were found incorrect / unreliable, so they are flagged INVALID for removal
# in the clean stage rather than rescaled. value_std_corr passes value_std through
# except for the invalid rows, which get NULL.
slim_gs_invalid <- function(m) {
  m |>
    mutate(
      invalid_gs     = category == "composition" & !is.na(value_std) & value_std > 100.5,
      gs_corr        = if_else(invalid_gs, "invalid", NA_character_),
      value_std_corr = if_else(invalid_gs, NA_real_, value_std))
}

slim_correct_grainsize <- function(source, db_dir = multised_db_dir(),
                                   verbose = TRUE) {
  derive <- switch(
    source,
    "ices-dome" = slim_gs_renorm,
    "mudab"     = slim_gs_renorm,
    "vannmiljo" = slim_gs_invalid,
    stop("Step 14 (grain-size correction) applies to ices-dome, mudab and ",
         "vannmiljo only, not ", sQuote(source), ".", call. = FALSE)
  )

  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Add columns (idempotent) ────────────────────────────────────────────
  # value_std_corr : corrected standardised value. Equals value_std everywhere
  #                  except corrected grain-size fractions (so it is a drop-in
  #                  "best" value_std for any measurement, chemistry included).
  # gs_corr        : 'renorm'  = value was rescaled by the per-curve factor;
  #                  'invalid' = reviewed and confirmed unreliable (value_std_corr
  #                              nulled);
  #                  'suspect' = still implausible (>100 %) and not correctable
  #                              (e.g. a non-monotone curve);
  #                  NULL      = untouched.
  add_column_if_missing(con, "measurement", "value_std_corr", "REAL")
  add_column_if_missing(con, "measurement", "gs_corr", "TEXT")

  # ── 2. Derive ──────────────────────────────────────────────────────────────
  el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
  m  <- dbReadTable(con, "measurement") |> as_tibble() |> left_join(el, by = "symbol")
  d  <- derive(m)

  # ── 3. Write back (idempotent) ─────────────────────────────────────────────
  dbWriteTable(con, "qc_gscorr",
               d |> select(measurement_id, value_std_corr, gs_corr),
               temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_gscorr ON qc_gscorr(measurement_id);")
  dbExecute(con, "
    UPDATE measurement SET
      value_std_corr = (SELECT value_std_corr FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id),
      gs_corr        = (SELECT gs_corr        FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id);")

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  dist <- dbGetQuery(con, "SELECT COALESCE(gs_corr,'(none)') gs_corr, COUNT(*) n
                           FROM measurement m JOIN element e ON m.symbol=e.symbol
                           WHERE e.category='composition' GROUP BY gs_corr ORDER BY n DESC")
  over <- NULL
  if (!identical(source, "vannmiljo")) {
    over <- dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol
                             WHERE e.category='composition' AND value_std_corr > 100.5")
  }
  if (verbose) {
    cat("gs_corr distribution (composition rows):\n")
    print(dist)
    if (!is.null(over)) {
      cat("\ngrain-size value_std_corr still > 100 (should be only suspect):\n")
      print(over)
    }
  }
  invisible(if (is.null(over)) dist else list(gs_corr = dist, still_over_100 = over))
}
