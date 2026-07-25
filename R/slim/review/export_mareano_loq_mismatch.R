# Export Mareano rows where the numeric limit check and the detection label
# disagree, for manual checking of the raw LLD/LOD/LOQ values.
#
# Step 7 sets `below_loq` from Mareano's own `below_lld` flag; step 10 sets
# `below_loq_num` by comparing `value_std` against the method's numeric limit
# (LLD here) converted to the standardised unit. This script exports the rows the
# numeric check flags as below-limit that the label did NOT
# (`below_loq_num = 1 AND below_loq = 0`) — the ~6,350 "missed by label" cases —
# so the reported value can be checked against the method LLD by hand.
#
# The Mareano caveat: `lld` in the method table is a single collapsed
# representative limit per method, so a value below that representative LLD may
# well come from a batch with a lower actual LLD. `limit_std` (the LLD in the
# standardised unit) and `ratio = value_std / limit_std` are included so a reader
# can see how far below the representative limit each value sits. Writes
# ./data/qc_review/mareano_loq_mismatch.csv. Run from the project root.

library(DBI)
library(RSQLite)
library(tidyverse)

db <- "./data/db/mareano_slim.sqlite"
out_path <- "./data/qc_review/mareano_loq_mismatch.csv"

# ── Unit mass basis (mirror of steps 8 & 10) ─────────────────────────────────
targets     <- c("CO", "CU", "I", "MN", "MO", "SE", "ZN")
normalisers <- c("FE", "AL")
organic     <- c("CORG", "TOC", "TOC63")

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

# ── Read the slim tables ─────────────────────────────────────────────────────
con <- dbConnect(RSQLite::SQLite(), db)
m  <- dbReadTable(con, "measurement") |> as_tibble()
ss <- dbReadTable(con, "subsample")   |> as_tibble()
ev <- dbReadTable(con, "event")       |> as_tibble()
st <- dbReadTable(con, "site")        |> as_tibble()
el <- dbReadTable(con, "element")     |> as_tibble()
ds <- dbReadTable(con, "dataset")     |> as_tibble()
mt <- dbReadTable(con, "method")      |> as_tibble()
dbDisconnect(con)

date_col <- intersect(c("date", "datetime", "year"), names(ev))[1]

# ── The mismatch set: numeric flags below-limit, label did not ───────────────
mm <- m |> filter(below_loq_num == 1L, below_loq == 0L)

out <- mm |>
  left_join(mt |> select(method_id, method, lab, lld), by = "method_id") |>
  mutate(sym = str_to_upper(symbol),
         unit_canon = canon_unit(unit),
         is_chem = sym %in% c(targets, normalisers, organic)) |>
  left_join(mass_basis, by = "unit_canon") |>
  mutate(limit_std = lld / denom * if_else(is_chem, 1e6, 1e2),
         ratio     = value_std / limit_std) |>
  left_join(ss |> select(subsample_id, event_id, depth_from, depth_to),
            by = "subsample_id") |>
  left_join(ev |> transmute(event_id, dataset_id, site_id,
                            date = as.character(.data[[date_col]])),
            by = "event_id") |>
  left_join(st |> select(site_id, latitude, longitude), by = "site_id") |>
  left_join(el |> select(symbol, element), by = "symbol") |>
  left_join(ds |> select(dataset_id, source, dataset_name), by = "dataset_id") |>
  arrange(symbol, method_id, ratio) |>
  select(measurement_id, source, dataset_name, site_id, latitude, longitude,
         date, depth_from, depth_to, symbol, element,
         value, unit, value_std, unit_std,
         below_lld, below_loq, below_loq_num,
         method_id, method, lab, lld, limit_std, ratio)

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(out, out_path)

cat("\n===== Mareano LOQ mismatch export =====\n")
cat("rows (below_loq_num = 1 & below_loq = 0):", nrow(out), "\n")
cat("distinct elements:", n_distinct(out$symbol), "\n")
cat("written to:", out_path, "\n\n")
cat("by element / method:\n")
print(out |> count(symbol, element, method_id, method, lld, name = "rows"),
      n = Inf)
