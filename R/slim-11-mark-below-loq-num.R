# ── Slim step 11: mark below limit, numeric ──────────────────────────────────
# Adds `measurement.below_loq_num` (0/1, NULL where the method has no numeric
# limit): a numeric cross-check of step 8's label-based `below_loq`, comparing
# `value_std` against the method's own detection/quantification limit.
#
# Identical for all five sources.

slim_mark_below_loq_num <- function(source, db_dir = multised_db_dir(),
                                    verbose = TRUE) {
  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Unit mass basis (mirror of step 9) ──────────────────────────────────
  # Needed to convert a method limit into the same standardised unit as value_std
  # (chemistry -> mg/kg), so value and limit are compared like for like.
  mass_basis <- tibble::tribble(
    ~unit_canon, ~denom,
    "%", 1e2, "vol.%", 1e2, "wt.%", 1e2,
    "g/kg", 1e3, "g/kg c", 1e3, "mg/g", 1e3,
    "mg/kg", 1e6, "ug/g", 1e6, "ppm", 1e6,
    "ug/kg", 1e9, "ng/g", 1e9, "ppb", 1e9
  )
  canon_unit <- function(u) {
    u |> str_to_lower() |> str_trim() |>
      str_remove("\\s*(dw|ww|dry weight|wet weight)$") |> str_trim() |>
      str_replace_all("µ|μ", "u")
  }

  # ── 2. Add below_loq_num column (idempotent) ───────────────────────────────
  # A numeric cross-check of the label-based `below_loq` (step 8), since a source's
  # detection label can be wrong. 1 = value below the method's numeric
  # detection/quantification limit; 0 = above it; NULL = not assessable (the method
  # carries no numeric limit, e.g. 4Demon, or the measurand is grain-size
  # composition, whose method 'limit' is a size-class boundary in µm, not a
  # detection limit). At the limit exactly, the source detection flag decides: some
  # sources substitute the value at the limit (Mareano reports value == LLD for
  # below-detection results), so a value == limit is below-limit only when
  # `below_loq` is set; a genuine reading equal to the limit (flag off) stays 0. The
  # clean stage can union `below_loq = 1 OR below_loq_num = 1`.
  add_column_if_missing(con, "measurement", "below_loq_num", "INTEGER")

  # ── 3. One numeric limit per method: LOQ, else LOD, else LLD ───────────────
  # Prefer the quantification limit (higher, more inclusive) where present. Sources
  # expose different columns; a source with none (4Demon) yields no limit at all.
  me <- dbReadTable(con, "method") |> as_tibble()
  me_lim <- me |> select(method_id, any_of(c("loq", "lod", "lld")))
  me_lim$limit <- NA_real_
  for (col in c("loq", "lod", "lld")) {
    if (col %in% names(me_lim)) me_lim$limit <- coalesce(me_lim$limit, me_lim[[col]])
  }

  # ── 4. Flag values at or below the (standardised) limit ────────────────────
  # The numeric check runs on chemistry only (element.category from step 3);
  # grain-size composition is left NULL because its method limit is a size-class
  # boundary in µm, not a detection limit.
  el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
  m  <- dbReadTable(con, "measurement") |> as_tibble()
  if (!"value_std" %in% names(m)) {
    stop("value_std is missing -- run step 9 (add_converted_value) first.",
         call. = FALSE)
  }
  if (!"below_loq" %in% names(m)) {
    stop("below_loq is missing -- run step 8 (mark_below_loq) first.",
         call. = FALSE)
  }

  d <- m |>
    left_join(me_lim |> select(method_id, limit), by = "method_id") |>
    left_join(el, by = "symbol") |>
    mutate(unit_canon = canon_unit(unit),
           is_chem = category %in% c("target", "reference", "organic")) |>
    left_join(mass_basis, by = "unit_canon") |>
    mutate(limit_std = limit / denom * if_else(is_chem, 1e6, 1e2),
           below_loq_num = case_when(
             !is_chem ~ NA_integer_,  # grain-size: method 'limit' is a size-class boundary (um), not a detection limit
             is.na(limit_std) | is.na(value_std) | limit_std <= 0 ~ NA_integer_,
             value_std <  limit_std  ~ 1L,
             value_std == limit_std  ~ as.integer(below_loq == 1L),  # at the limit, defer to the flag
             TRUE                    ~ 0L))

  # ── 5. Write back (idempotent) ─────────────────────────────────────────────
  # Assessable rows (0/1) go to the temp table; rows with no usable limit are left
  # NULL by the correlated update.
  dbWriteTable(con, "qc_bloqn",
               d |> filter(!is.na(below_loq_num)) |> select(measurement_id, below_loq_num),
               temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_bloqn ON qc_bloqn(measurement_id);")
  dbExecute(con, "
    UPDATE measurement
    SET below_loq_num = (SELECT below_loq_num FROM qc_bloqn q
                         WHERE q.measurement_id = measurement.measurement_id);")

  # ── 6. Verify ──────────────────────────────────────────────────────────────
  totals <- dbGetQuery(con, "SELECT COALESCE(CAST(below_loq_num AS TEXT),'(no limit)') below_loq_num,
                                    COUNT(*) n
                             FROM measurement GROUP BY below_loq_num ORDER BY n DESC")
  crosstab <- dbGetQuery(con, "SELECT below_loq, below_loq_num, COUNT(*) n
                               FROM measurement WHERE below_loq_num IS NOT NULL
                               GROUP BY below_loq, below_loq_num ORDER BY below_loq, below_loq_num")
  if (verbose) {
    cat("below_loq_num totals:\n")
    print(totals)
    cat("label (below_loq) vs numeric (below_loq_num), where assessable:\n")
    print(crosstab)
  }
  invisible(list(totals = totals, label_vs_numeric = crosstab))
}
