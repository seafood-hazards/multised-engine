# Refined pipeline — plan & spec (draft)

The fifth generation, **`multised-refined`**. One database,
`data/db/multised_refined.sqlite`, refactored **from** the merged database
(`multised_merged.sqlite`) plus the aquaculture reference (`aquaculture_no.sqlite`)
and the analysis outputs already produced on the merged DB. Built by a new `R/refine/`
script tree.

It is an **analysis-ready mart** for the later "pristine / background sediment" work
(identifying pristine sediments so aquaculture effects can be assessed). That work is
**not** designed yet and is deliberately out of scope here: this generation only
restructures the merged data and bakes in reusable results, so the later analyses do
not recompute them.

## Governing rule

> **Bake in facts and already-computed reusable values; defer every classification or
> threshold.**

- **Baked** (facts + reused computations): the normalisation results (metal/Fe,
  metal/Al, fines %, organic), the repeat-sampled-site grouping, the aquaculture link,
  and factual context already present on the data (sea area, distances, raw depth,
  provenance, detection limits).
- **Deferred** (decisions the later analyses own): depth banding, offshore / pressure
  flags, enrichment factors and background models, the pristine label itself, and the
  **unsupervised cluster labels** (facies / hotspots / regions). The DB carries the raw
  material for these (ratios, fines, distances, raw depth) but makes none of the calls.
  EFSA's specific recipe (e.g. a 90th-percentile per region) is **not** adopted; only
  the reusable inputs are provided.

  On clustering specifically: the merged-DB clustering was descriptive, its labels
  depend on choices made for description (k, location weight, eps, the CU/ZN/MN/CO
  feature set), and it re-runs cheaply on the ratios baked here. So we bake the
  clustering **inputs**, not its **outputs**; the later pristine analyses cluster for
  themselves. A descriptive facies/region tag could be added later if wanted, but never
  the hotspot labels (a threshold is baked into them).

## Principles

- **One `measurement` table with a `frac_class` column.** Bulk and sieved never pool,
  enforced by the column (as in the clean/merged generations). Splitting into two
  tables was tried and reverted: a target reading has identical attributes in both
  fractions, so the split earned only the two sieve columns (NULL for bulk) at the cost
  of a UNION on every cross-fraction query.
- **`measurement` holds only the 7 targets**, and drops three redundant columns:
  `unit_std` (constant mg/kg), `matrix` (raw grain-size fraction code, unused now grain
  size is gone) and `sieve_um` (superseded by the harmonised `sieve_um_std`). FE / AL /
  CORG stop being measurement rows; they become a compact normaliser carrier (below).
  `grain_size_fraction` is dropped (every analysis used the derived `fines_lt63`).
- **Normalisers live at (subsample, fraction) grain.** A normaliser is *not* unique per
  subsample (a subsample can hold both bulk and sieved chemistry), so a single
  subsample-level value would be ambiguous. See the `normaliser` table.
- **Provenance kept.** Every row keeps `source` and its original per-source id.
- **Derived, not recomputed.** Ratios, fines, repeat grouping and the aquaculture link
  are computed once here so the later analyses just filter and aggregate.

## Schema

Dimensions carried over largely unchanged: `element` (**trimmed to the 7 targets**;
the normalisers/organic are captured as `normaliser` columns, not element rows),
`dataset`, `method` (keeps `lod`/`loq`/`lab`), `event` (`year`, `date`, `n_layers`).

**`site`** — carried over, plus:
- `aqua_id` → `aquaculture.aqua_id` (nearest aquaculture site; Norway-only, NULL
  elsewhere, alongside the existing `dist_to_aquaculture`).
- `repeat_group` (the rounded-location cell key) + `n_years` (distinct sampling years
  at that cell) from the repeat-sampled-sites analysis. Raw `depth`, `dist_to_coast`,
  `sea_name`, `country`, `municipality` kept as facts; **no** offshore/pressure flag
  (deferred).

**`aquaculture`** — new; imported from `aquaculture_no.sqlite` (`aqua_id`, `loknr`,
`name`, lat/lon, `start_year`/`end_year`/`active`, `capacity_tonnes`, `fish_types`,
`placement`, `county`, `municipality`).

**`subsample`** — physical properties only: `depth_from`/`depth_to`/`depth_flag`
(raw, **not** banded), `fines_lt63` + `fines_basis` (physical grain-size fact),
the exist flags, provenance.

**`normaliser`** (new) — grain = **(subsample_id, frac_class)**; the FE/AL/CORG
measurements reshaped long→wide at the correct grain: `fe`, `al`, `corg` (values in
the standardised unit). Where a (subsample, fraction) has >1 method row for a
normaliser (FE 4.6%, AL/CORG 0.2%), the values are **mean-collapsed** (as the analyses
did). This *is* the "remove FE/AL/CORG from measurement" step, done without loss.

**`measurement`** — one row per (subsample, target element): `frac_class`
(`bulk`/`sieved`), `value_std`, `ratio_fe`, `ratio_al`, `ratio_corg` (target /
normaliser at the same subsample+fraction), `sieve_um_std` / `sieve_class` (NULL for
bulk), `method_id`, `outlier_flag`, raw `value`/`unit` + `src_measurement_id` for
provenance. **No `ratio_fines`**: grain size was used as a covariate/correction, not a
divide-by-fines normaliser, so the reusable primitive is `fines_lt63` on `subsample`
and the analysis normalises by whatever method it chooses.

**Dropped:** `grain_size_fraction`; FE/AL/CORG as measurement rows; and the redundant
`unit_std` / `matrix` / `sieve_um` columns.

## Steps (`R/refine/`, run in order)

| # | File                    | Purpose                                                    |
|---|-------------------------|------------------------------------------------------------|
| 1 | `01_restructure.R`      | carry dimensions; keep targets as one `measurement` (frac_class); drop `unit_std`/`matrix`/`sieve_um` and `grain_size_fraction` |
| 2 | `02_normaliser.R`       | build `normaliser` (subsample×fraction, wide, mean-collapsed) from FE/AL/CORG rows |
| 3 | `03_ratios.R`           | compute `ratio_fe`/`ratio_al`/`ratio_corg` on the fact tables from `normaliser` |
| 4 | `04_aquaculture.R`      | import `aquaculture` table; add `site.aqua_id`             |
| 5 | `05_repeat_sites.R`     | add `site.repeat_group` + `n_years` from the sampling years |
| 6 | `06_summary.R`          | row-count / retention / sanity CSVs for the creation pages  |

Phase 1 is the structural refactor above. **Deferred to a later phase** (facts that
need a curated lookup, easy to add once the pristine analyses need them):
`extraction_class` (strong/mild/weak, from `method` text) and an `accredited` flag
(from `lab`/source). Left out of the first cut so it ships clean.

## Websites

- **DB-creation pages** (how the refined schema is built): on the existing
  **multised-merged** site.
- **Analyses** on the refined DB (the pristine/background work): a **new** site,
  `multised-refined`, to be created when those analyses are designed.

## Resolved decisions

- **`measurement` structure**: single table with `frac_class` (the split was reverted;
  it earned only the sieve columns). Dropped `unit_std` / `matrix` / `sieve_um`; kept
  raw `value` / `unit`. **Decided.**
- **`normaliser` storage**: slim (subsample×fraction) table. **Decided.**
- **`ratio_fines`**: not baked; `fines_lt63` primitive only. **Decided.**
- **`element` trimming**: reduced to the 7 targets. **Decided.**
- **Clustering results**: inputs baked, labels not. **Decided.**
- **Extraction class / accredited**: phase 2 (curated `method` lookups). **Decided.**

## Still open

- Whether the later `multised-refined` analysis site reuses any merged-site machinery
  (decide when that site is designed; leaning no).
