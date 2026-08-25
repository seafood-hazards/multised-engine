# Refined pipeline — plan & spec (draft)

The fifth generation, **`multised-refined`**. One database,
`data/db/multised_refined.sqlite`, refactored **from** the merged database
(`multised_merged.sqlite`) plus the aquaculture reference (`aquaculture_no.sqlite`)
and the analysis outputs already produced on the merged DB.

Run with `create_db("refined")` — no `source`. Package code is `R/refine-*.R`.

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

> **Joining it: always match `frac_class` too.**
> ```sql
> LEFT JOIN normaliser n ON n.subsample_id = me.subsample_id
>                       AND n.frac_class   = me.frac_class
> ```
> 2,936 subsamples carry both a bulk and a sieved normaliser row, so a join on
> `subsample_id` alone fans those measurements out into two and can attach the wrong
> fraction's aluminium. Three analyses did exactly that between v0.9.0 and v0.9.5
> (`background_ef`, `pristine`, `regression`); the export always had it right, and the
> export-vs-analysis check in [analysis.md](analysis.md) is what caught it.

**`measurement`** — one row per (subsample, target element): `frac_class`
(`bulk`/`sieved`), `value_std`, `ratio_fe`, `ratio_al`, `ratio_corg` (target /
normaliser at the same subsample+fraction), `sieve_um_std` / `sieve_class` (NULL for
bulk), `method_id`, `outlier_flag`, raw `value`/`unit` + `src_measurement_id` for
provenance. **No `ratio_fines`**: grain size was used as a covariate/correction, not a
divide-by-fines normaliser, so the reusable primitive is `fines_lt63` on `subsample`
and the analysis normalises by whatever method it chooses.

**Dropped:** `grain_size_fraction`; FE/AL/CORG as measurement rows; and the redundant
`unit_std` / `matrix` / `sieve_um` columns.

## Steps (`R/refine-*.R`, run in order)

| # | File                    | Purpose                                                    |
|---|-------------------------|------------------------------------------------------------|
| 1 | `01_restructure.R`      | carry dimensions; keep targets as one `measurement` (frac_class); drop `unit_std`/`matrix`/`sieve_um` and `grain_size_fraction` |
| 2 | `02_normaliser.R`       | build `normaliser` (subsample×fraction, wide, mean-collapsed) from FE/AL/CORG rows |
| 3 | `03_ratios.R`           | compute `ratio_fe`/`ratio_al`/`ratio_corg` on the fact tables from `normaliser` |
| 4 | `04_aquaculture.R`      | import `aquaculture` table; add `site.aqua_id`             |
| 5 | `05_repeat_sites.R`     | add `site.repeat_group` + `n_years` from the sampling years |
| 6 | `06_summary.R`          | row-count / retention / sanity CSVs for the creation pages  |

Phase 1 is the structural refactor above.

**Phase 2, `extraction_class`: done** (2026-08-25). It is now carried on the `method`
table, all the way from pilot to the export. See
[efsa-submission.md](efsa-submission.md).

> The 2026-08-02 note here said extraction class was "blocked pending source-level
> data", on the grounds that **"no digestion/extraction column exists in any of the
> five pilot DBs"**. That was wrong. It held for the *refined* `method` table, which
> does record only the analytical technique, but not for the pilot databases: ICES-DOME
> carries `analysis_method.metcx` (the ICES METCX code for method of chemical
> extraction) and MUDAB carries `analysis_method.chemical_treatment` in the same
> vocabulary. The field was there all along and was dropped at **slim step 1**, which
> builds the method table from `distinct(param, metoa, ...)` and never selects `metcx`.
> The conclusion was drawn from the wrong end of the pipeline.

Recorded for **51.5%** of the 115,820 target measurements: ICES-DOME and MUDAB record
it per analysis, Mareano has one stated method for every target element, and Vannmiljø
and 4Demon record nothing, so they take the `UNK` code and EFSA class 3. The extraction
is part of method identity, so `method` grew from 949 rows to 983.

`accredited` remains a gap of the kind this one turned out not to be, but a real one:
only MUDAB records it (46.9% of its target rows, in a messy `true`/`ja`/`y`/`1`
vocabulary) and it is not carried through the pipeline. See
[efsa-submission.md](efsa-submission.md) section 9.

## Websites

- **DB-creation pages** (how the refined schema is built): on the existing
  **multised-merged** site.
- **Analyses** on the refined DB (the pristine/background work): the
  `multised-refined` site (created and published). See
  [websites.md](websites.md).

## Resolved decisions

- **`measurement` structure**: single table with `frac_class` (the split was reverted;
  it earned only the sieve columns). Dropped `unit_std` / `matrix` / `sieve_um`; kept
  raw `value` / `unit`. **Decided.**
- **`normaliser` storage**: slim (subsample×fraction) table. **Decided.**
- **`ratio_fines`**: not baked; `fines_lt63` primitive only. **Decided.**
- **`element` trimming**: reduced to the 7 targets. **Decided.**
- **Clustering results**: inputs baked, labels not. **Decided.**
- **Extraction class**: carried on `method` from the sources' own digestion fields,
  not curated lookups. **Done**, see above.
- **`accredited`**: carried on `method` the same way, from Mareano's `lld.comment` and
  MUDAB's `analysis_method.accreditation`, as `yes` / `partly` / `no` with NULL for not
  reported; `partly` maps to EFSA's `Y`. The other three sources do not record it.
  **Done**, see [generation-gaps.md](generation-gaps.md) §2.
- **Igeo and the pristine verdict**: Igeo is computed and reported (background step
  10) but **does not issue a verdict**; the verdicts stay on EF. It reaches 97.2% of
  target measurements against EF's 9.8%, and 99.4% within 1 km of a fish farm against
  0.4%, which is why it exists; but it has no grain-size control, and the confounding
  is strong enough in bulk (cobalt rho 0.70 against the mud fraction) that a verdict
  built on it would be partly a verdict about texture. **Decided 2026-08-25.**
- **Igeo for the withheld elements**: withheld, like every other background statement
  about selenium and molybdenum. D1 removes over half of both below the LOQ, and the
  offshore median that Igeo divides by is drawn from what survived, so the denominator
  is an upper tail and the quotient is not an enrichment. Needing no aluminium rescues
  Igeo from D4, not from D1. **Settled 2026-08-25** when re-cutting the exports: step
  10's coverage table had always applied this (`igeo_ok = has_ref & !withheld`) but its
  class tables had not, so the step published Mo and Se Igeo beside a 97.2% coverage
  figure computed as though it did not. The class tables now apply the same gate; the
  headline number is unchanged, because it was always the withheld-excluded one.
- **TOC as a normaliser**: rejected. It clears the D4 limits in one group of twenty,
  and that group is selenium sieved63 on 34 rows of a withheld element. **Decided.**
- **PLI**: not built. Same `C / B` inputs as Igeo so no coverage gain, and a PLI over
  three or more elements reaches 26% of subsamples where Igeo reaches ~100% per
  element. **Decided.**

## Still open

- Whether the later `multised-refined` analysis site reuses any merged-site machinery
  (decide when that site is designed; leaning no).
