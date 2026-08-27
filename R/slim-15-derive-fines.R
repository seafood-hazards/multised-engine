# ── Slim step 15: derive fines <63µm ─────────────────────────────────────────
# Adds `subsample.fines_lt63` (% finer than 63µm, the clay + silt "mud"
# fraction) + `subsample.fines_basis` (how it was derived).
#
# WHAT THE COLUMN MEANS. It describes the PARENT SEDIMENT as collected, never a
# sieved aliquot: a grain-size curve is measured on the whole sample, so the number
# belongs to that material and not to whatever cut was later analysed for metals.
# The data shows it plainly. A cut below 63µm would be 100% mud by definition, yet
# across subsamples whose targets are sieved to <63µm the median here is about 15%,
# LOWER than the ~50% for bulk, because sandy sediment is what gets sieved.
#
# So never divide a sieved measurement by it: that scales a concentration by the mud
# content of different material and inflates it by roughly the reciprocal of that
# content. The refined grain-size-normalised background did exactly this until
# 2026-08-27. See the bulk-normalised, sieved-raw rule in CLAUDE.md and step 15 in
# docs/slim-pipeline.md.
#
# Source-specific, and present for every source with grain-size (all but
# 4Demon). Three derivations, because each source encodes grain-size
# differently. Mareano reads `value_std` (it has no step 14); the others read the
# corrected `value_std_corr`.

# Mareano stores grain-size as four named bins (element.category = 'composition'):
#   Clay   < 2 um
#   Silt   2 - 63 um
#   Sand   63 - 2000 um
#   Gravel > 2000 um
# The <63 um ("mud") fraction is Clay + Silt. Both are volume-% and share the
# same basis, so they sum cleanly; the standardised value_std (grain-size -> %,
# from step 9) is summed so the derivation is unit-safe. Sand/Gravel are the
# coarse remainder and are not part of <63 um. A subsample with neither Clay nor
# Silt gets no fines value (stays NULL).
slim_fines_mareano <- function(con) {
  sub63 <- c("Clay", "Silt")
  m <- dbGetQuery(con, "
    SELECT s.subsample_id, m.symbol, m.value_std
    FROM subsample s
    JOIN measurement m ON m.subsample_id = s.subsample_id
    JOIN element e     ON e.symbol = m.symbol
    WHERE e.category = 'composition'") |> as_tibble()

  m |>
    filter(symbol %in% sub63, !is.na(value_std)) |>
    group_by(subsample_id) |>
    summarise(fines_lt63  = sum(value_std),
              fines_basis = "sum_bins",
              .groups = "drop")
}

# ICES-DOME / MUDAB report the cumulative code GSMF63 ("Grain Size Mass Fraction
# <63 micron, silt/clay"): the <63 um fraction directly. But it is <63 um *of the
# matrix it was measured on*, so the matrix must be combined in:
#   SEDtot            -> <63 um of the whole sample (what we want)
#   SED2000 / SED1000 -> <63 um of the <2 mm / <1 mm material; used as the
#                        whole-sample fines when SEDtot is absent. NOTE: these
#                        samples carry grain-size ONLY on the sieved <2 mm base,
#                        so the gravel (>2 mm) removed beforehand is unmeasured and
#                        cannot be reconciled. They are taken as whole-sample fines
#                        under the assumption that gravel is negligible (true for
#                        open marine sediment, not for gravelly/coastal). The
#                        fines_basis 'gsmf63_sed2000' marks them for downstream use.
#   finer matrices (SED63, SED20, ...) -> trivially ~100 %, excluded
# Priority SEDtot > SED2000 > SED1000. The corrected value_std_corr (step 14) is
# read, so the per-curve renormalisation is already applied and previously
# over-scaled samples are recovered here. Values still outside 0-100 (the step-14
# 'suspect' rows) are excluded (left NULL).
slim_fines_gsmf63 <- function(con) {
  bulk_prio <- c(SEDtot = 1L, SED2000 = 2L, SED1000 = 3L)

  g <- dbGetQuery(con, "
    SELECT subsample_id, matrix, value_std_corr AS value_std
    FROM measurement WHERE symbol = 'GSMF63'") |>
    as_tibble() |>
    filter(!is.na(value_std), value_std >= 0, value_std <= 100,
           matrix %in% names(bulk_prio))

  g |>
    mutate(prio = bulk_prio[matrix]) |>
    group_by(subsample_id, matrix, prio) |>
    summarise(v = mean(value_std), .groups = "drop") |>
    group_by(subsample_id) |>
    slice_min(prio, n = 1, with_ties = FALSE) |>
    ungroup() |>
    transmute(subsample_id,
              fines_lt63  = v,
              fines_basis = paste0("gsmf63_", str_to_lower(matrix)))
}

# Vannmiljo reports several grain-size codes. fines_lt63 is taken from the first
# available, in this order:
#   1. FINS      "Fines < 63 um"            -> the <63 um fraction directly.
#   2. GSMF_63   "Particle fraction >63 um" -> the COMPLEMENT (sand+); note the
#                naming is the OPPOSITE of the ICES GSMF63 (<63), so 100 - GSMF_63.
#                FINS + GSMF_63 ~ 100 (verified).
#   3. GSMF2 + GSMF2_63  "<2 um" (clay) + "2-63 um" (silt) -> the same clay+silt
#                sum used for Mareano, an exact <63 um for samples that carry the
#                fraction bins but neither of the direct codes above.
# All via the standardised value (grain-size -> %, step 9). value_std_corr
# (step 14) is read; for Vannmiljo that is a pass-through of value_std (its noise
# is flagged, not rescaled), so the implausible values are excluded here.
slim_fines_vannmiljo <- function(con) {
  comps <- c("FINS", "GSMF_63", "GSMF2", "GSMF2_63")
  g <- dbGetQuery(con, sprintf("
    SELECT subsample_id, symbol, value_std_corr AS value_std FROM measurement
    WHERE symbol IN (%s)", paste0("'", comps, "'", collapse = ","))) |>
    as_tibble() |>
    filter(!is.na(value_std), value_std >= 0, value_std <= 100)

  per <- g |>
    group_by(subsample_id, symbol) |>
    summarise(v = mean(value_std), .groups = "drop") |>
    pivot_wider(names_from = symbol, values_from = v)
  for (cc in comps) if (!cc %in% names(per)) per[[cc]] <- NA_real_

  per |>
    mutate(clay_silt = GSMF2 + GSMF2_63) |>   # NA unless both bins present
    transmute(
      subsample_id,
      fines_lt63  = case_when(!is.na(FINS)      ~ FINS,
                              !is.na(GSMF_63)   ~ 100 - GSMF_63,
                              !is.na(clay_silt) ~ clay_silt),
      fines_basis = case_when(!is.na(FINS)      ~ "fins",
                              !is.na(GSMF_63)   ~ "gsmf_63_complement",
                              !is.na(clay_silt) ~ "clay_silt_sum")) |>
    filter(!is.na(fines_lt63), fines_lt63 >= 0, fines_lt63 <= 100)
}

slim_derive_fines <- function(source, db_dir = multised_db_dir(),
                              verbose = TRUE) {
  derive <- switch(
    source,
    "mareano"   = slim_fines_mareano,
    "ices-dome" = slim_fines_gsmf63,
    "mudab"     = slim_fines_gsmf63,
    "vannmiljo" = slim_fines_vannmiljo,
    stop("Step 15 (derive fines) applies to every source with grain-size, ",
         "i.e. all but 4demon; not ", sQuote(source), ".", call. = FALSE)
  )

  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Add fines columns (idempotent) ──────────────────────────────────────
  # fines_lt63  : percentage finer than 63 um (REAL, %). NULL where the subsample
  #               has no usable grain-size data.
  # fines_basis : how it was derived, for provenance and cross-source comparison.
  add_column_if_missing(con, "subsample", "fines_lt63", "REAL")
  add_column_if_missing(con, "subsample", "fines_basis", "TEXT")

  # ── 2. Derive ──────────────────────────────────────────────────────────────
  fines <- derive(con)

  # ── 3. Write back (idempotent) ─────────────────────────────────────────────
  dbWriteTable(con, "qc_fines", fines, temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_fines ON qc_fines(subsample_id);")
  dbExecute(con, "
    UPDATE subsample SET
      fines_lt63  = (SELECT fines_lt63  FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id),
      fines_basis = (SELECT fines_basis FROM qc_fines q WHERE q.subsample_id = subsample.subsample_id);")

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  basis <- dbGetQuery(con, "SELECT COALESCE(fines_basis,'(none)') fines_basis, COUNT(*) n
                            FROM subsample GROUP BY fines_basis ORDER BY n DESC")
  range <- dbGetQuery(con, "SELECT ROUND(MIN(fines_lt63),2) vmin, ROUND(MAX(fines_lt63),2) vmax,
                                   ROUND(AVG(fines_lt63),2) vavg,
                                   SUM(CASE WHEN fines_lt63 > 100 THEN 1 ELSE 0 END) over_100
                            FROM subsample WHERE fines_lt63 IS NOT NULL")
  if (verbose) {
    cat("fines_basis distribution:\n")
    print(basis)
    cat("\nfines_lt63 (%) range where present:\n")
    print(range)
  }
  invisible(list(fines_basis = basis, fines_range = range))
}
