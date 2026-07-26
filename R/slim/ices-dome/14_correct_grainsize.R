library(DBI)
library(RSQLite)
library(tidyverse)

# ── 0. Open slim db ──────────────────────────────────────────────────────────
# Grain-size correction step (source-specific; ICES-DOME / MUDAB share this body).
# A large share of the grain-size curves are internally consistent (a monotone
# cumulative distribution) but scaled wrong: within one sample every code is
# inflated by the same factor, so the standardised value_std runs to thousands of
# "percent". This step renormalises each such curve so its coarsest cutoff (the
# total, ~ the <2 mm fraction) reads 100 %, writing the result to value_std_corr
# and marking gs_corr. Raw value / value_std are left untouched as provenance.
# The later fines step (15) reads value_std_corr.
con <- dbConnect(RSQLite::SQLite(), "./data/db/ices_dome_slim.sqlite")
dbExecute(con, "PRAGMA foreign_keys = ON;")

# ── 1. Add columns (idempotent) ──────────────────────────────────────────────
# value_std_corr : corrected standardised value. Equals value_std everywhere
#                  except renormalised grain-size fractions (so it is a drop-in
#                  "best" value_std for any measurement, chemistry included).
# gs_corr        : 'renorm'  = value was rescaled by the per-curve factor;
#                  'suspect' = grain-size fraction still implausible (>100 %) and
#                              not correctable (e.g. a non-monotone curve);
#                  NULL      = untouched.
for (coldef in c("value_std_corr REAL", "gs_corr TEXT")) {
  col <- sub(" .*", "", coldef)
  if (!col %in% dbListFields(con, "measurement")) {
    dbExecute(con, sprintf("ALTER TABLE measurement ADD COLUMN %s;", coldef))
  }
}

# ── 2. Per-curve renormalisation factor ──────────────────────────────────────
# A grain-size curve is one (subsample, matrix) group. The cumulative GSMF codes
# (GSMF63, GSMF2000, ...) define it; the anchor is the largest value_std in the
# curve (the coarsest cutoff, i.e. the total). A curve is corrected only when it
# is over-scaled (anchor > 100.5 %) AND monotone (a valid cumulative shape after
# renormalising); factor = 100 / anchor. Everything else keeps factor 1.
cutoff <- function(sym) as.numeric(str_match(sym, "^GSMF>?_?([0-9]+)$")[, 2])

el <- dbReadTable(con, "element") |> as_tibble() |> select(symbol, category)
m  <- dbReadTable(con, "measurement") |> as_tibble() |> left_join(el, by = "symbol")

curves <- m |>
  filter(category == "composition", !is.na(value_std), !is.na(cutoff(symbol))) |>
  mutate(cut = cutoff(symbol)) |>
  group_by(subsample_id, matrix) |>
  summarise(anchor   = max(value_std),
            monotone = all(diff(value_std[order(cut)]) >= -0.005 * max(value_std)),
            .groups  = "drop") |>
  mutate(factor = if_else(anchor > 100.5 & monotone & anchor > 0, 100 / anchor, 1))

# ── 3. Apply: renorm fraction rows, flag the rest ────────────────────────────
# Only mass-fraction codes are rescaled (GSMF*, GS>a<b); grain-size statistics
# (GSMEA / GSMED / GSSORT / ...) are not fractions and are never touched.
is_fraction <- function(sym) str_detect(sym, "^GSMF|^GS>")

d <- m |>
  left_join(curves |> select(subsample_id, matrix, factor), by = c("subsample_id", "matrix")) |>
  mutate(
    factor = coalesce(factor, 1),
    frac   = category == "composition" & is_fraction(symbol),
    value_std_corr = if_else(frac & factor != 1, value_std * factor, value_std),
    gs_corr = case_when(
      frac & factor != 1                       ~ "renorm",
      frac & !is.na(value_std_corr) & value_std_corr > 100.5 ~ "suspect",
      TRUE                                     ~ NA_character_))

# ── 4. Write back (idempotent) ───────────────────────────────────────────────
dbWriteTable(con, "qc_gscorr",
             d |> select(measurement_id, value_std_corr, gs_corr),
             temporary = TRUE, overwrite = TRUE)
dbExecute(con, "CREATE INDEX IF NOT EXISTS ix_qc_gscorr ON qc_gscorr(measurement_id);")
dbExecute(con, "
  UPDATE measurement SET
    value_std_corr = (SELECT value_std_corr FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id),
    gs_corr        = (SELECT gs_corr        FROM qc_gscorr q WHERE q.measurement_id = measurement.measurement_id);")

# ── 5. Verify ─────────────────────────────────────────────────────────────────
cat("gs_corr distribution (composition rows):\n")
print(dbGetQuery(con, "SELECT COALESCE(gs_corr,'(none)') gs_corr, COUNT(*) n
                       FROM measurement m JOIN element e ON m.symbol=e.symbol
                       WHERE e.category='composition' GROUP BY gs_corr ORDER BY n DESC"))
cat("\ngrain-size value_std_corr still > 100 (should be only suspect):\n")
print(dbGetQuery(con, "SELECT COUNT(*) n FROM measurement m JOIN element e ON m.symbol=e.symbol
                       WHERE e.category='composition' AND value_std_corr > 100.5"))

dbDisconnect(con)
