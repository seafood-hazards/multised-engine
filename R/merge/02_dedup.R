library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge stage 2: flag cross-source duplicate measurements ──────────────────
# A cross-source duplicate is the same reading reported by more than one source.
# Two measurements are duplicates when they share rounded location (lat/lon 3 dp),
# exact sampling date, depth layer, element, track (frac_class + sieve_um_std for
# sieved) AND a near-equal standardised value (within 1% relative). Within such a
# cluster the highest-preference source is kept and the rest are flagged.
#
# Preference (highest first): Mareano > 4Demon > MUDAB > Vannmiljø > ICES-DOME.
# Undated rows (no exact date) are never deduped. This flags (does not delete);
# 03_finalise.R removes the flagged rows and cascades.
#
# Adds to `measurement`: dup_flag (1 = superseded duplicate, else NULL) and
# dup_superseded_by (the winning source). Reads/writes data/db/merged.sqlite.

db <- "data/db/merged.sqlite"
PREF <- c(Mareano = 1L, `4Demon` = 2L, MUDAB = 3L, `Vannmiljø` = 4L, `ICES-DOME` = 5L)
TOL  <- 0.01   # 1% relative value match

con <- dbConnect(SQLite(), db)
meas <- as_tibble(dbReadTable(con, "measurement"))
sub  <- as_tibble(dbReadTable(con, "subsample")) |> select(subsample_id, event_id, depth_from, depth_to)
ev   <- as_tibble(dbReadTable(con, "event"))     |> select(event_id, site_id, date)
site <- as_tibble(dbReadTable(con, "site"))      |> select(site_id, latitude, longitude)

# ── 1. Join the matching context onto each measurement ───────────────────────
ctx <- meas |>
  select(measurement_id, subsample_id, symbol, value_std, frac_class, sieve_um_std, source) |>
  left_join(sub,  by = "subsample_id") |>
  left_join(ev,   by = "event_id") |>
  left_join(site, by = "site_id") |>
  mutate(pref = unname(PREF[source]),
         lat3 = round(latitude, 3), lon3 = round(longitude, 3),
         dated = !is.na(date) & date != "")

# ── 2. Cluster dated rows by value within each sample key, flag losers ───────
# gkey isolates same location / date / depth / element / track; within it a value
# cluster is a single-linkage chain of values each within TOL of the previous.
dated <- ctx |>
  filter(dated) |>
  mutate(gkey = paste(lat3, lon3, date, depth_from, depth_to,
                      symbol, frac_class, sieve_um_std, sep = "|")) |>
  arrange(gkey, value_std) |>
  group_by(gkey) |>
  mutate(rel_gap = (value_std - lag(value_std)) / lag(value_std),
         cluster = cumsum(is.na(rel_gap) | rel_gap > TOL)) |>
  group_by(gkey, cluster) |>
  mutate(best_pref     = min(pref),
         winner_source = source[which.min(pref)],
         dup           = pref > best_pref) |>
  ungroup()

flagged <- dated |>
  filter(dup) |>
  transmute(measurement_id, dup_flag = 1L, dup_superseded_by = winner_source)

# ── 3. Write dup_flag / dup_superseded_by back onto measurement ──────────────
meas_out <- meas |>
  select(-any_of(c("dup_flag", "dup_superseded_by"))) |>
  left_join(flagged, by = "measurement_id")

dbExecute(con, "DROP TABLE IF EXISTS measurement")
dbWriteTable(con, "measurement", as.data.frame(meas_out), row.names = FALSE)
dbDisconnect(con)

# ── 4. Console summary ───────────────────────────────────────────────────────
n_dup <- nrow(flagged)
cat("cross-source duplicates flagged:", n_dup,
    sprintf("(%.1f%% of %d measurements)\n", 100 * n_dup / nrow(meas), nrow(meas)))
cat("\nsuperseded (loser) by source:\n")
dated |> filter(dup) |> count(loser = source, sort = TRUE) |>
  as.data.frame() |> print(row.names = FALSE)
cat("\nwinner -> loser pairs:\n")
dated |> filter(dup) |> count(winner_source, loser = source, sort = TRUE) |>
  as.data.frame() |> print(row.names = FALSE)
