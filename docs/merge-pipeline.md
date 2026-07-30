# Merge pipeline — plan & spec (draft)

The fourth generation. The five per-source clean DBs (`<source>_clean.sqlite`) are
combined into **one** cross-source database, `data/db/multised_merged.sqlite`, with
cross-source duplicates removed. Built by a new `R/merge/` script tree.

## Principles

- **Bulk and sieved stay separate tracks.** `frac_class` (`bulk`/`sieved`) is part of
  every dedup key and every downstream split; the two are never pooled, deduped, or
  normalised against each other. They live in the same tables, told apart by the
  column (as in the clean stage), not in separate tables.
- **Source preference** (highest wins on a duplicate):
  **Mareano > 4Demon > MUDAB > Vannmiljø > ICES-DOME.** ICES-DOME is the
  international aggregator that re-hosts national data, so it ranks last; the national
  sources are preferred over their re-hosted copies. (Overlap is real: 1,371 shared
  rounded-coordinate locations, chiefly ICES+MUDAB 1,035, Mareano+Vannmiljø 247.)
- **Prefixed keys while merging.** During the union every primary/foreign key is
  prefixed with a 3-letter source code (`mar`/`van`/`ice`/`mud`/`dem`, e.g.
  `mar_123`) so keys from different sources can never be silently mixed. The shared
  `element.symbol` vocabulary (ICES symbols, identical across sources) is **not**
  prefixed. Keys are renumbered to clean integers only at the end.
- **Provenance kept.** Every row carries `source`; the final renumber keeps the
  source and the original per-source id for back-tracing.

## Steps (`R/merge/`, run in order)

| # | File            | Purpose                                             |
|---|-----------------|-----------------------------------------------------|
| 1 | `01_union.R`    | prefix keys, add `source`, union the 8 tables       |
| 2 | `02_dedup.R`    | remove cross-source duplicates by the preference    |
| 3 | `03_finalise.R` | renumber keys to integers, keep provenance          |

### 1. Union

Read all five clean DBs; prefix every `*_id` column (PK and FK) with the source
code; add a `source` column. Bind each table across sources into
`data/db/multised_merged.sqlite`. `element` is a shared dimension: collapsed to the distinct
`(symbol, name, category, cas)` set (no source, no prefix). `grain_size_fraction` is
unioned from the four sources that have it (4Demon has none).

Also derive the **harmonised sieve cutoff** on `measurement` (sieved rows only):
`sieve_um_std` (canonical numeric cutoff, `62 → 63`, others unchanged) and
`sieve_class` (the label, e.g. `<63um` / `<20um`), NULL for bulk. Values are **not**
converted between cutoffs (impossible without the grain-size curve); the columns only
let like-cutoff sieved data be compared and keep different cutoffs apart.

### 2. Deduplicate

A cross-source duplicate is the **same reading reported by more than one source**.
Two measurements are duplicates when they share:

- rounded **location** (latitude/longitude to 3 dp),
- **exact sampling date** (rows with no date are never deduped, kept as-is),
- **depth layer** (`depth_from`, `depth_to`),
- **element** (`symbol`) and **track** (`frac_class`, plus `sieve_um_std` for sieved),
- and a **near-equal standardised value** (`value_std` within **1%** relative).

Within each such group the row from the highest-preference source is kept and the
rest are dropped (cascading to any now-orphaned subsample/event/site is handled in
finalise). Bulk vs sieved never collide because `frac_class` is in the key. The
near-exact (1%) value match keeps genuinely different samples apart; it targets
re-hosted copies, not reprocessed values.

### 3. Finalise

Renumber every key to a clean contiguous integer, rebuild the foreign keys, and keep
`source` plus the original per-source id (`src_*_id`) as provenance columns. Drop rows
orphaned by the dedup. Write the final `multised_merged.sqlite`.

## Open items

- Whether `element` rows ever conflict across sources (same symbol, different
  name/cas) and how to resolve; expected clean since clean-stage names are canonical.
- Whether near-duplicate **sites/events** (same location/date, kept because their
  measurements differed) should be collapsed to one site/event with multiple sources,
  or left as distinct prefixed rows. Currently left distinct.
- Site coordinates are rounded to 3 dp for matching (~110 m); revisit if it over- or
  under-merges.
