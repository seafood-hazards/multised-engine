library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge stage 2: flag cross-source duplicate measurements ──────────────────
# A cross-source duplicate is the same reading reported by more than one source.
# Two rules run here, both FLAGGING the lower-preference copy (never deleting;
# 03_finalise.R removes the flagged rows and cascades):
#
#  (1) Value-cluster (general). Same rounded location (lat/lon 3 dp), sampling
#      YEAR, depth layer, element, track (frac_class + sieve_um_std) AND a
#      near-equal standardised value (within 1% relative). Year (not exact date)
#      is used because a re-hosting source often rewrites the date field, so exact
#      date splits copies that are plainly the same reading; the strict 1% value
#      gate is what keeps genuinely different samples apart. At 1% this fires
#      almost only on real re-hosting overlaps (chiefly ICES-DOME copies of
#      MUDAB's German OSPAR monitoring, MUDAB the national source winning), and is
#      inert across the rest of the data. Rows with no year are never matched.
#
#  (2) Provenance (Vannmiljo's re-hosted Mareano). Vannmiljo carries a dataset
#      named "Kartlegging av miljogifter i sedimenter - MAREANO": re-hosted
#      Mareano data. Re-hosting here nudged the value past 1%, so even the
#      year-based rule (1) misses most of it. Here a Vannmiljo row from that
#      dataset is a
#      duplicate when native Mareano has the same rounded location + YEAR +
#      element + track with a value within 5%; the looser key/tolerance is safe
#      because the provenance is known. Vannmiljo-MAREANO rows with NO native
#      Mareano match (native Mareano is ~2003-2021; the copy runs 1999-2024) are
#      KEPT, they are the only copy we hold. See review_mareano_dedup.R for the
#      row-by-row justification of the split.
#
# Preference (highest first): Mareano > 4Demon > MUDAB > Vannmiljø > ICES-DOME.
#
# Adds to `measurement`: dup_flag (1 = superseded duplicate, else NULL) and
# dup_superseded_by (the winning source). Reads/writes data/db/multised_merged.sqlite.

db <- "data/db/multised_merged.sqlite"
PREF <- c(Mareano = 1L, `4Demon` = 2L, MUDAB = 3L, `Vannmiljø` = 4L, `ICES-DOME` = 5L)
TOL        <- 0.01        # 1% relative value match (rule 1)
TOL_REHOST <- 0.05        # 5% relative value match (rule 2, provenance)
REHOST_DS  <- "MAREANO"   # Vannmiljo dataset_name marker for re-hosted Mareano

con <- dbConnect(SQLite(), db)
meas <- as_tibble(dbReadTable(con, "measurement"))
sub  <- as_tibble(dbReadTable(con, "subsample")) |> select(subsample_id, event_id, depth_from, depth_to)
ev   <- as_tibble(dbReadTable(con, "event"))     |> select(event_id, site_id, dataset_id, date, year)
site <- as_tibble(dbReadTable(con, "site"))      |> select(site_id, latitude, longitude)
dset <- as_tibble(dbReadTable(con, "dataset"))   |> select(dataset_id, dataset_name)

# ── 1. Join the matching context onto each measurement ───────────────────────
ctx <- meas |>
  select(measurement_id, subsample_id, symbol, value_std, frac_class, sieve_um_std, source) |>
  left_join(sub,  by = "subsample_id") |>
  left_join(ev,   by = "event_id") |>
  left_join(site, by = "site_id") |>
  left_join(dset, by = "dataset_id") |>
  mutate(pref = unname(PREF[source]),
         lat3 = round(latitude, 3), lon3 = round(longitude, 3),
         sieve_key = coalesce(sieve_um_std, -1),
         has_year = !is.na(year))

# ── 2. Rule 1: cluster same-year rows by value within each sample key ─────────
# gkey isolates same location / year / depth / element / track; within it a value
# cluster is a single-linkage chain of values each within TOL of the previous.
clustered <- ctx |>
  filter(has_year) |>
  mutate(gkey = paste(lat3, lon3, year, depth_from, depth_to,
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

flagged_value <- clustered |>
  filter(dup) |>
  transmute(measurement_id, dup_flag = 1L, dup_superseded_by = winner_source)

# ── 2b. Rule 2: Vannmiljo's re-hosted Mareano dataset ────────────────────────
# native Mareano key set (loc3 + year + element + track) with its value(s) ...
mar_keys <- ctx |>
  filter(source == "Mareano") |>
  transmute(lat3, lon3, year, symbol, frac_class, sieve_key, mar_value = value_std)

# ... versus the Vannmiljo rows from the re-hosted MAREANO dataset. A row is a
# duplicate only when a native Mareano value on the same key is within 5%.
van_mareano <- ctx |>
  filter(source == "Vannmiljø",
         !is.na(dataset_name), str_detect(dataset_name, REHOST_DS))

flagged_rehost <- van_mareano |>
  inner_join(mar_keys,
             by = c("lat3", "lon3", "year", "symbol", "frac_class", "sieve_key"),
             relationship = "many-to-many") |>
  mutate(rel_diff = abs(mar_value - value_std) / value_std) |>
  group_by(measurement_id) |>
  summarise(min_rel = min(rel_diff), .groups = "drop") |>
  filter(min_rel <= TOL_REHOST) |>
  transmute(measurement_id, dup_flag = 1L, dup_superseded_by = "Mareano")

# ── 2c. Combine the two flag sets (one row per measurement) ──────────────────
flagged <- bind_rows(flagged_value, flagged_rehost) |>
  distinct(measurement_id, .keep_all = TRUE)

# dedup detail for the website (lost once 03_finalise removes the flagged rows)
dir.create("data/analysis/merge", recursive = TRUE, showWarnings = FALSE)
flagged |>
  left_join(ctx |> select(measurement_id, loser_source = source, symbol, frac_class),
            by = "measurement_id") |>
  count(winner_source = dup_superseded_by, loser_source, symbol, frac_class, name = "n") |>
  arrange(desc(n)) |>
  write_csv("data/analysis/merge/merge_dedup.csv")

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
cat("  rule 1 (value-cluster, same year):         ", nrow(flagged_value), "\n")
cat("  rule 2 (Vannmiljo re-hosted Mareano):      ", nrow(flagged_rehost),
    "  (", nrow(van_mareano), "candidates in the dataset)\n")
cat("\nsuperseded (loser) by source:\n")
flagged |> left_join(ctx |> select(measurement_id, source), by = "measurement_id") |>
  count(loser = source, sort = TRUE) |> as.data.frame() |> print(row.names = FALSE)
cat("\nwinner -> loser pairs:\n")
flagged |> left_join(ctx |> select(measurement_id, source), by = "measurement_id") |>
  count(winner = dup_superseded_by, loser = source, sort = TRUE) |>
  as.data.frame() |> print(row.names = FALSE)
