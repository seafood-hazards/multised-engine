# multised-engine

R scripts that assemble a database of marine-sediment trace-element measurements
from five external data sources, harmonise them into a common schema, and
progressively quality-control the result.

## Data sources

| Key         | Source     | Notes                                  |
|-------------|------------|----------------------------------------|
| `mareano`   | Mareano    | Norway / IMR cruises                   |
| `vannmiljo` | Vannmiljø  | Norway                                 |
| `ices-dome` | ICES-DOME  | International; rich sediment-composition data |
| `mudab`     | MUDAB      | Germany (national)                     |
| `4demon`    | 4Demon     | Belgium (national; Baltic/North Sea)   |

## Pipeline generations

Five generations. The first three are one SQLite DB **per source**; the last two
are single cross-source DBs. Each has a spec doc under `docs/` — **read the
relevant one before changing that stage.**

| # | Gen       | Package files        | Output DB (`data/db/`)      | Spec                                             | Status |
|---|-----------|----------------------|-----------------------------|--------------------------------------------------|--------|
| 1 | pilot     | `R/pilot-*.R`        | `<source>_pilot.sqlite`     | (per source; table structure differs)            | done   |
| 2 | slim      | `R/slim-*.R`         | `<source>_slim.sqlite`      | [slim-pipeline.md](docs/slim-pipeline.md)        | done   |
| 3 | clean     | `R/clean-*.R`        | `<source>_clean.sqlite`     | [clean-pipeline.md](docs/clean-pipeline.md)      | done   |
| 4 | merged    | `R/merge-*.R`        | `multised_merged.sqlite`    | [merge-pipeline.md](docs/merge-pipeline.md)      | done   |
| 5 | refined   | `R/refine-*.R`       | `multised_refined.sqlite`   | [refined-pipeline.md](docs/refined-pipeline.md)  | phase 1 done |

Run any of them with `create_db(gen, source)`.

- **pilot → slim** parses raw source files, then reshapes into the shared 7-table
  schema and flags quality/duplicates/etc.
- **clean** applies the slim flags (01 harmonise, 02 clean, 03 annotate; shared
  helpers in `R/clean-shared-*.R`). Sites are geo-enriched by `R/clean-04-geo-enrich.R`
  (depth, country, dist_to_coast, municipality, sea_name) using the external
  `seastamp` CLI, then step 05 adds `dist_to_aquaculture` (Norway only; keys on
  the `NOR` country code step 04 assigns, so it must follow it).
- **merged** unions all five clean DBs and removes cross-source duplicates.
- **refined** is a mart cut from the merged DB for the pristine/background work.

Alongside the generations:

- **aquaculture** (`R/aquaculture-01-build.R`) — a standalone Norway-only
  reference DB (`aquaculture_no.sqlite`) of marine aquaculture sites from the
  Fiskeridirektoratet "Yggdrasil" exports (`data/raw/yggdrasil/`). Not a
  generation: build it with `create_db("aquaculture")` (no `source`, no `steps`),
  and clean step 05 measures against it. Needs `sf`. See
  [clean-pipeline.md](docs/clean-pipeline.md).
- **analysis** (`R/analysis-<generation>-<module>.R`) — read-only analyses on a
  finished DB, writing CSVs to `data/analysis/<module>/` for the websites. The
  generation token (`clean` / `merged` / `refined`) says which DB is read. Run
  with `analyze_data()`. See [analysis.md](docs/analysis.md).
- **websites** — nine Quarto sites, each in a **sibling repo**, not in this
  project: five per-source pilot sites (`../<source>-pilot`) plus one per later
  generation. A pilot site depends only on its `<source>_pilot.sqlite`, taken
  from that repo's *latest* release, so **every release there must carry the
  database as an asset**. See [websites.md](docs/websites.md).

## Public interface

Three entry points cover the whole project; everything else is internal.

```r
create_db(generation, source = NULL, steps = NULL,
          db_dir = multised_db_dir(), verbose = TRUE)

analyze_data(generation, module = NULL, steps = NULL,
             db_dir = multised_db_dir(),
             out_dir = multised_analysis_dir(), verbose = TRUE)

export_data(generation = "refined", source = NULL,
            db_dir = multised_db_dir(),
            out_dir = multised_analysis_dir(), verbose = TRUE)
```

- `create_db()` covers **all five generations**. `source` is required for the
  per-source generations (pilot/slim/clean) and must be `NULL` for
  merged/refined.
- `analyze_data()` covers **all 28 analyses** (6 clean, 13 merged, 9 refined);
  `generation` is `clean`, `merged` or `refined`. `module = NULL` runs every
  module for it. Most modules hold one analysis; `background` holds six.
- `export_data()` denormalises a finished DB into a flat gzipped TSV plus a
  column dictionary. It derives nothing of its own, which is why it is not an
  analysis module; `refined` is the only generation with one. It does carry the
  pristine / background verdicts, joined from the `background` module's CSVs, so
  **`analyze_data("refined")` must have run first** or it errors.
- `steps` re-runs a subset. In `create_db("slim", …)` steps 1-2 are one unit; in
  `analyze_data()` `steps` selects within one module and so requires `module`
  (only `background` has more than one step).
- Listing helpers: `slim_steps(source)`, `analysis_modules(generation)`,
  `multised_sources()` — all executable versions of the tables below.
- Paths: the `db_dir` / `out_dir` / `seastamp_dir` arguments, or the
  `multised.db_dir`, `multised.analysis_dir`, `multised.raw_dir` and
  `multised.seastamp_dir` options. `seastamp_dir` (`data/seastamp`, called
  `data/geoenrich` before the tool was renamed) is the seastamp reference tree,
  read by pilot step 4 and clean step 4 only; skip those steps where seastamp is
  not installed (`create_db("pilot", src, steps = c(1, 5))`, `steps = 1:3` for
  clean).

Analyses never modify a pipeline DB, so re-running is always safe; each writes
to `out_dir/<module>/`.

**R collates only top-level `R/*.R`.** Package code therefore lives in flat files
whose names encode the old tree (`R/slim-03-categorize.R`,
`R/slim-01-transform-mudab.R`, `R/analysis-merged-hotspots.R`). Do not add
subdirectories under `R/`.

The original script trees were deleted at v0.3.0, once every generation and all
25 analyses had been validated by hand against the stored databases and outputs.
Each conversion was verified by rebuilding into a temp directory and diffing.
Thirteen review and export prototypes that were never part of the interface live
on in `inst/scripts/` (`pilot/`, `slim/`, `merge/`), to be `source()`d from the
project root when wanted.

## Slim schema (7 tables)

`element` → `dataset` → `site` → `event` → `subsample` → `measurement`, plus
`method`. Foreign keys:

- `event.dataset_id → dataset`, `event.site_id → site`
- `subsample.event_id → event`
- `measurement.subsample_id → subsample`, `measurement.symbol → element`,
  `measurement.method_id → method`; `method.symbol → element`

The core structure is identical across sources; **columns differ slightly** on
the wide tables (e.g. `measurement` carries `below_lld` for mareano,
`operator`/`filtered` for vannmiljo, `basis`/`matrix`/`qflag`/… for
ices-dome/mudab/4demon). Per-source column map in
[slim-pipeline.md](docs/slim-pipeline.md).

## Slim step scripts (run in order, per source)

| #  | File                        | Adds                              | Sources           |
|----|-----------------------------|-----------------------------------|-------------------|
| 1  | `01_transform_data.R`       | pilot DB → slim data frames       | all               |
| 2  | `02_create_tables.R`        | create schema + write slim DB     | all               |
| 3  | `03_categorize.R`           | `element.category`                | all               |
| 4  | `04_quality_control.R`      | `area_flag` / `invalid_flag`      | all               |
| 5  | `05_mark_duplicates.R`      | `dup_flag`                        | all               |
| 6  | `06_mark_additional_data.R` | `*_exist` flags on `subsample`    | all               |
| 7  | `07_mark_multi.R`           | `n_layers` / `multi_flag`         | all               |
| 8  | `08_mark_below_loq.R`       | `below_loq`                       | all               |
| 9  | `09_add_converted_value.R`  | `value_std` / `unit_std`          | all               |
| 10 | `10_mark_range.R`           | `range_flag`                      | all               |
| 11 | `11_mark_below_loq_num.R`   | `below_loq_num`                   | all               |
| 12 | `12_mark_weight_basis.R`    | `weight_basis`                    | all               |
| 13 | `13_mark_source_specific.R` | `src_flag` (source-native)        | van, ices, dem    |
| 14 | `14_correct_grainsize.R`    | `value_std_corr` / `gs_corr`      | ices, mud, van    |
| 15 | `15_derive_fines.R`         | `fines_lt63` / `fines_basis`      | mar, van, ices, mud |

Steps 1–12 are common to every source; **step 13 onward is source-specific** and
present only where a source has something extra to fold in or derive. Step numbers
are fixed per concern, so a source runs only the later steps that apply to it:
Mareano runs …12, 15 (no native flags, clean grain-size); 4Demon runs …13 only
(no grain-size). Steps 3–7 and 9–11 have identical bodies across sources bar the
DB path; steps 8 and 12 differ per source because the source signal differs.

Nothing here deletes rows: the flags are suspicious markers for the clean stage
and for manual review. **Full step specs, per-source signal maps and row counts
are in [slim-pipeline.md](docs/slim-pipeline.md)** — go there before touching a
step.

> **Rebuilding:** `02` reuses the `df_*` frames built by `01`, so the two must be
> `source()`d together in one R session per source. After a rebuild, sanity-check
> that the slim DB matches its pilot source (row counts, measurement columns) —
> `ices_dome_slim.sqlite` was once clobbered with 4Demon output and went unnoticed
> because the numbers looked plausible.

## Target elements

`element.category` (added by slim step 3) is the single source of truth for the
measurand class; later steps read it rather than each redefining its own symbol
lists.

| Category      | Symbols                                   |
|---------------|-------------------------------------------|
| `target`      | CO, CU, I, MN, MO, SE, ZN (the 7 targets) |
| `reference`   | FE, AL (normalisers)                      |
| `organic`     | CORG (ices-dome, mudab) / TOC, TOC63 (mareano, vannmiljo) |
| `composition` | grain-size mass-fraction parameters (ICES-DOME `GS…`/`GSMF…` codes) |

**Al is the only valid enrichment normaliser, and only where it predicts the
element**: EF and pristine verdicts exist for CO/CU/ZN in bulk alone (D4, see
[normalisability](inst/extdata/normalisability/README.md)). **Fe is a reference, never a
normaliser** — Norwegian fish feed contains iron, so Fe near a farm is partly the
pressure being measured. It may be shown for comparison; it must not enter an EF
or a pristine verdict.

Organic carbon is its own category, tracked by `org_exist`, and is **not** counted
as composition. Grain-size code naming is source-dependent (ICES `GSMF63` = below
63µm, Vannmiljø `GSMF_63` = above); never assume the number is a below-cutoff.

## Conventions

- **Stack:** `tidyverse` + `DBI`/`RSQLite`; magrittr `%>%` and native `|>`.
- **Run from the project root** — scripts use relative paths like
  `./data/db/…`. `data/` is a symlink to external storage; `data/db` is a
  symlink to the DB working area. Neither the DBs nor `data/` are in git.
- Environment is `renv`-managed (`renv.lock`); `.Rprofile` activates it.
- Data frames are prefixed `df_`; source rows are filtered into `df_base_*`
  (7 target elements) and `df_ref_*` (normalisers + sediment composition), then
  widened into a single `df_slim` join table from which each output table is
  cut with `distinct()` + `row_number()` surrogate keys.
- Scripts are organised with `# ── N. Title ─────` section headers.
- Sites are keyed on latitude/longitude **rounded to 3 decimal places**.
- The `multised-engine` DESCRIPTION/NAMESPACE make this a package skeleton, but the
  code is a script pipeline, not an exported-function package.
- **No em-dashes in the Quarto site pages** (`../multised-slim`,
  `../multised-clean`, `../multised-merged`, `../multised-refined`): use commas,
  colons, or parentheses instead.

## Docs map

| Doc | Covers |
|-----|--------|
| [slim-pipeline.md](docs/slim-pipeline.md) | slim schema + full specs for steps 3–15 |
| [clean-pipeline.md](docs/clean-pipeline.md) | clean schema, harmonise/clean/annotate, geo-enrichment, aquaculture |
| [merge-pipeline.md](docs/merge-pipeline.md) | union, dedup rules, finalise, outlier flagging, summary |
| [refined-pipeline.md](docs/refined-pipeline.md) | refined mart schema, steps, resolved/open decisions |
| [refined-review-response.md](docs/refined-review-response.md) | external review of the refined site: dispositions, decisions, ordering |
| [ef-source-bias.md](docs/ef-source-bias.md) | why the bulk EF background is not comparable across sources, and the options |
| [inst/extdata/loq-censoring/README.md](inst/extdata/loq-censoring/README.md) | below-LOQ rows are removed at clean step 2; why Se and Mo verdicts are withheld |
| [inst/extdata/normalisability/README.md](inst/extdata/normalisability/README.md) | D4: EF and pristine verdicts exist only where Al predicts the element (CO/CU/ZN bulk) |
| [analysis.md](docs/analysis.md) | the analysis modules and which site each feeds |
| [websites.md](docs/websites.md) | the nine sibling-repo Quarto sites (5 pilot + 4 generation), publishing, gotchas |
| [sediment-composition-codes.md](docs/sediment-composition-codes.md) | grain-size code reference |
| [plan.md](docs/plan.md) | overall project plan |
