# sedimenter

R scripts that assemble a database of marine-sediment trace-element measurements
from five external data sources, harmonise them into a common schema, and
progressively quality-control the result.

## Data sources

| Key         | Source     | Notes                                  |
|-------------|------------|----------------------------------------|
| `mareano`   | Mareano    | Norway / IMR cruises                   |
| `vannmiljo` | Vannmiljø  | Norway                                 |
| `ices-dome` | ICES-DOME  | International; rich sediment-composition data |
| `mudab`     | MUDAB      | International                          |
| `4demon`    | 4Demon     | International                          |

## Pipeline generations

The data moves through three generations. Each is one SQLite DB **per source**.

1. **pilot** (`R/pilot/<source>/`) — parse raw source files into a per-source
   pilot DB (`./data/db/pilot_<source>.sqlite`). Table structure differs by
   source. **Done.**
2. **slim** (`R/slim/<source>/`) — reshape each pilot DB into a shared 7-table
   schema (`./data/db/<source>_slim.sqlite`), then flag quality/duplicate/etc.
   **All six steps done** (see below).
3. **clean** — the final, QC-passed DB built by applying the slim flags. *Not started.*

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
ices-dome/mudab/4demon). See [docs/slim-pipeline.md](docs/slim-pipeline.md) for
the per-source column map and the plan for the QC/marking steps.

## Slim step scripts (run in order, per source)

| # | File                        | Purpose                        | Status |
|---|-----------------------------|--------------------------------|--------|
| 1 | `01_transform_data.R`       | pilot DB → slim data frames    | done   |
| 2 | `02_create_tables.R`        | create schema + write slim DB  | done   |

> **Rebuilding:** `02` reuses the `df_*` frames built by `01`, so the two must be
> `source()`d together in one R session per source. After a rebuild, sanity-check
> that the slim DB matches its pilot source (row counts, measurement columns) —
> `ices_dome_slim.sqlite` was once clobbered with 4Demon output and went unnoticed
> because the numbers looked plausible.


| 3 | `03_quality_control.R`      | add `qc_flag` columns          | done   |
| 4 | `04_mark_duplicates.R`      | add `dup_flag` columns         | done   |
| 5 | `05_mark_additional_data.R` | add `exist_flag` columns       | done   |
| 6 | `06_mark_multi.R`           | mark multi-layer/-core samples | done   |

Step 3 adds a `qc_flag` (NULL = passed) to `site` (`outside_europe`) and
`measurement` (`negative` / `over_range`). Step 4 adds a `dup_flag` to
`measurement` (`duplicate` / `technical_replicate`, NULL = neither), grouping on
location + date + depth + element + unit. Both are suspicious markers for manual
review, not deletions. Step 5 adds `fe_exist` / `al_exist` / `comp_exist`
(integer 0/1) to `subsample`, flagging whether the FE/AL normalisers and
grain-size composition are available for that sample (composition = any element
that is not a target and not FE/AL). Step 6 adds `n_layers` + `multi_flag` (0/1)
to `event`, marking multi-layer/-core samplings (events with >1 subsample) versus
single grabs; it is derived from the data, not the tool code, since the same gear
yields both. Each script body is identical across sources bar the DB path. Full
step specs are in [docs/slim-pipeline.md](docs/slim-pipeline.md).

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
- The `sedimenter` DESCRIPTION/NAMESPACE make this a package skeleton, but the
  code is a script pipeline, not an exported-function package.

## Target elements

- **7 targets:** CO, CU, I, MN, MO, SE, ZN.
- **2 normalisers:** FE, AL.
- **Sediment composition:** grain-size mass-fraction parameters (ICES-DOME
  `GS…`/`GSMF…` codes); used to flag whether composition data exist.
