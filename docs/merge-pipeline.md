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

| # | File                 | Purpose                                             |
|---|----------------------|-----------------------------------------------------|
| 1 | `01_union.R`         | prefix keys, add `source`, union the 8 tables       |
| 2 | `02_dedup.R`         | remove cross-source duplicates by the preference    |
| 3 | `03_finalise.R`      | renumber keys to integers, keep provenance          |
| 4 | `04_mark_outliers.R` | add `outlier_flag` (distributional outliers)        |
| 5 | `05_summary.R`       | retention / stage-total CSVs for the website        |

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
Two **rules** run, both flagging the lower-preference copy (never deleting; finalise
removes the flagged rows and cascades). Within any duplicate group the row from the
highest-preference source is kept and the rest dropped.

**Rule 1, value-cluster (general).** Two measurements are duplicates when they share:

- rounded **location** (latitude/longitude to 3 dp),
- **sampling year** (rows with no year are never deduped, kept as-is),
- **depth layer** (`depth_from`, `depth_to`),
- **element** (`symbol`) and **track** (`frac_class`, plus `sieve_um_std` for sieved),
- and a **near-equal standardised value** (`value_std` within **1%** relative).

Year (not exact sampling date) is the time key: a re-hosting source often rewrites
the date field, so exact date splits copies that are plainly the same reading. The
strict **1% value** gate is what keeps genuinely different samples apart, so
loosening the date to year is safe. In practice, at 1% this fires almost only on real
re-hosting overlaps: chiefly **ICES-DOME copies of MUDAB's German OSPAR monitoring**
(MUDAB, the national source, winning; ICES-DOME, the aggregator, dropped), verified by
the overlap concentrating in matching ICES-programme / MUDAB-lab dataset pairs
(`review_year_overlap.R`). It is inert across the rest of the data.

**Rule 2, provenance (Vannmiljø's re-hosted Mareano).** Vannmiljø carries a dataset
literally named *"Kartlegging av miljøgifter i sedimenter - MAREANO"*: re-hosted
Mareano data. Re-hosting nudged the value past 1%, so even the year-based rule 1
misses most of it. A Vannmiljø row from that dataset is a duplicate when native
Mareano has the same rounded location + year + element + track within **5%**; the
looser tolerance is justified because the provenance is known from the dataset name.
Vannmiljø-MAREANO rows with **no** native Mareano match are **kept** (native Mareano
spans ~2003-2021 while the re-hosted copy runs 1999-2024, so ~385 of 1,054 are the
only copy we hold); `review_mareano_dedup.R` justifies the split row by row.

Bulk vs sieved never collide because `frac_class` is in both keys. Both rules target
re-hosted copies, not reprocessed values. Counts on the current data: rule 1 flags
**20,174** (mostly ICES-DOME superseded by MUDAB); rule 2 identifies **656** Vannmiljø
rows superseded by Mareano, but because rule 1's year key already catches most of them
within 1%, rule 2 adds only **13** net; **20,187** distinct duplicates in total.

### 3. Finalise

Renumber every key to a clean contiguous integer, rebuild the foreign keys, and keep
`source` plus the original per-source id (`src_*_id`) as provenance columns. Drop rows
orphaned by the dedup. Write the final `multised_merged.sqlite`.

### 4. Mark outliers

Add a soft `outlier_flag` (`high` / `low` / NULL) to `measurement`: a data-driven
marker for values sitting implausibly far from their element's distribution, most of
which are registration errors (decimal shifts, unit swaps) rather than real chemistry.
It is a **review/removal candidate, not a deletion** (genuine extremes, e.g. a
contaminated fjord, survive for a human to judge), and complements the physical
`range_flag` carried up from slim (which, being deliberately generous, misses an
in-range 10x shift).

Computed on the pooled merged distribution, per **element x fraction** (`bulk` /
`sieved63` / `sieved20`; fraction must be split, sieved medians run 1.5-3x bulk), on
`log10(value_std)`, chemistry only (grain-size composition is bounded 0-100% and left
NULL). A **dual criterion** flags a value only when it is BOTH a statistical outlier
(`|z| > 4`, `z = (log - median)/MAD`) AND at least **one order of magnitude** from the
group median (`|log10(value/median)| > 1`). The order-of-magnitude floor targets
registration errors and spares narrow real tails (e.g. Se) that a MAD-only rule
over-flags; the effective boundary is `median +/- max(4 * MAD, 1 oom)`. Groups below
100 rows are left NULL (robust stats unreliable, e.g. Iodine) and rely on `range_flag`.
Region is not stratified (regional spread ~2x is trivial next to the 10-1000x errors
this targets). The rule was settled in `R/analysis/outlier_review/`; on the current
data it flags 653 rows (381 high, 272 low, 0.34%). Idempotent and re-runnable.

### 5. Summary

Reporting only (no DB change): compare the final DB against the five clean DBs and
write the per-source retention and stage-total CSVs the website reads. The final DB
holds **190,844** measurements from the 211,031-row union (20,187 cross-source
duplicates removed, **90.4%** retained); ICES-DOME, the aggregator, retains the least
(72%), the national sources nearly all of theirs.

## Open items

- Whether `element` rows ever conflict across sources (same symbol, different
  name/cas) and how to resolve; expected clean since clean-stage names are canonical.
- Whether near-duplicate **sites/events** (same location/date, kept because their
  measurements differed) should be collapsed to one site/event with multiple sources,
  or left as distinct prefixed rows. Currently left distinct.
- Site coordinates are rounded to 3 dp for matching (~110 m); revisit if it over- or
  under-merges.
