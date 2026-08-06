# ── Slim step 12: mark weight basis ──────────────────────────────────────────
# Adds `measurement.weight_basis` (dry / wet, NULL for grain-size composition),
# harmonising each source's stated sample weight basis.
#
# Source-specific in its derivation only: the write-back and verification are
# shared. Three shapes, from a `basis` column (ices-dome / mudab / 4demon), the
# unit suffix (vannmiljo), or a constant (mareano, all dry, confirmed).

# First letter of a `basis` value: d -> dry, w -> wet (covers 'D'/'W' and
# 'dw'/'ww'). Anything else stays NULL.
wb_from_basis <- function(b) {
  bl <- str_to_lower(str_trim(b))
  case_when(str_starts(bl, "d") ~ "dry",
            str_starts(bl, "w") ~ "wet",
            TRUE                 ~ NA_character_)
}

# Vannmiljo encodes the basis in the unit, e.g. 'mg/kg dw', 'g/kg C dw'.
# Chemistry with no recognisable suffix stays NULL.
wb_from_unit <- function(u) {
  ul <- str_to_lower(u)
  case_when(str_detect(ul, "\\bdw\\b|dry ?weight") ~ "dry",
            str_detect(ul, "\\bww\\b|wet ?weight") ~ "wet",
            TRUE                                    ~ NA_character_)
}

slim_mark_weight_basis <- function(source, db_dir = multised_db_dir(),
                                   verbose = TRUE) {
  con <- slim_con(source, db_dir)
  on.exit(dbDisconnect(con), add = TRUE)

  # ── 1. Add weight_basis column (idempotent) ────────────────────────────────
  # Harmonised sample weight basis of each chemistry measurement: 'dry' or 'wet'
  # weight. Grain-size composition is left NULL: the dry/wet-weight distinction is
  # a concentration concept and does not apply to a grain-size fraction (its
  # vol.%/wt.% basis is handled by the dedicated grain-size step). Dry weight is the
  # sediment standard; wet-weight rows are review / conversion candidates for the
  # clean stage. The derivation differs per source because the basis signal differs
  # (a `basis` column, a unit suffix, or none).
  add_column_if_missing(con, "measurement", "weight_basis", "TEXT")

  # ── 2. Derive the basis for chemistry rows ─────────────────────────────────
  el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
  m  <- dbReadTable(con, "measurement") |> as_tibble() |> left_join(el, by = "symbol")
  d  <- m |> mutate(is_chem = category %in% c("target", "reference", "organic"))

  d$weight_basis <- switch(
    source,
    # Mareano carries no per-row basis field or unit suffix; all of its data are
    # dry weight (confirmed), so every chemistry measurement is 'dry'.
    "mareano"   = if_else(d$is_chem, "dry", NA_character_),
    "vannmiljo" = if_else(d$is_chem, wb_from_unit(d$unit), NA_character_),
    if_else(d$is_chem, wb_from_basis(d$basis), NA_character_)
  )

  # ── 3. Write back (idempotent) ─────────────────────────────────────────────
  dbWriteTable(con, "qc_wb",
               d |> filter(!is.na(weight_basis)) |> select(measurement_id, weight_basis),
               temporary = TRUE, overwrite = TRUE)
  dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_wb ON qc_wb(measurement_id);")
  dbExecute(con, "
    UPDATE measurement
    SET weight_basis = (SELECT weight_basis FROM qc_wb q
                        WHERE q.measurement_id = measurement.measurement_id);")

  # ── 4. Verify ──────────────────────────────────────────────────────────────
  out <- dbGetQuery(con, "SELECT COALESCE(weight_basis,'(none)') weight_basis, COUNT(*) n
                          FROM measurement GROUP BY weight_basis ORDER BY n DESC")
  if (verbose) {
    cat("weight_basis:\n")
    print(out)
  }
  invisible(out)
}
