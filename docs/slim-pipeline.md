# Slim pipeline — schema reference & QC/marking plan

Companion to [../CLAUDE.md](../CLAUDE.md). Covers (1) the shared slim schema and
its per-source column differences, and (2) the intended behaviour of the
not-yet-implemented steps 3–6.

## 1. Shared slim schema

Seven tables, built by `02_create_tables.R` for every source. Common columns:

- **element** — `symbol` (PK), `element`. (Some sources also carry `cas_no`.)
- **dataset** — `dataset_id` (PK), `source`, `dataset_name`, `country`,
  `institute`; several sources add `dataset_code`/`dataset_group`/`region`.
- **site** — `site_id` (PK), `latitude`, `longitude`, `country`,
  `country_code`, `dist_to_coast`, `municipality`, `sea_name`; mareano also has
  `depth`.
- **event** — `event_id` (PK), `dataset_id` (FK), `site_id` (FK),
  `sampling_tool`, `year`, `date`; some add `tool_description`, `time`,
  `datetime`.
- **method** — `method_id` (PK), `symbol` (FK), `method`, `lab`, plus source
  detection/quantification limits (`lld`, or `lod`/`loq`), and optional
  `lab_name`/`method_description`/`uncertainty`.
- **subsample** — `subsample_id` (PK), `event_id` (FK), `depth_from`,
  `depth_to`. One row per depth interval; `event` is one row per core.
- **measurement** — `measurement_id` (PK), `subsample_id` (FK), `symbol` (FK),
  `value`, `unit`, `method_id` (FK), plus source-specific columns below.

### `measurement` columns by source

| Source     | Extra columns beyond `value`, `unit`                                             |
|------------|----------------------------------------------------------------------------------|
| mareano    | `below_lld`                                                                       |
| vannmiljo  | `operator`, `filtered`                                                            |
| ices-dome  | `basis`, `matrix`, `qflag`, `vflag`, `uncrt`, `metcu`, `dcflag`                   |
| mudab      | `basis`, `matrix`, `qflag`                                                        |
| 4demon     | `corrected_value`, `basis`, `matrix`, `fraction_range`, `vflag`, `limit_flag`, `range_check_flag`, `outlier_extreme_flag`, `outlier_stdev_flag` |

When writing cross-source logic, do not assume a column exists — branch on the
source or guard with `if ("col" %in% names(df))`.

## 2. Step 3 — Quality control (`03_quality_control.R`)

Add `qc_flag` columns to the relevant tables.

- **Area QC** — restrict to European seas/oceans; flag samples whose location
  falls outside Europe. (Site-level; uses `site.latitude`/`longitude`, and
  `sea_name`/`country` already derived in the pilot stage.)
- **Invalid values** — flag measurements that are negative or exceed unit-based
  limits (e.g. `unit == "ug/g"` ⇒ max 1000). Applies to `measurement.value`.

## 3. Step 4 — Mark duplicates (`04_mark_duplicates.R`)

Add `dup_flag` columns to the relevant tables. Two observations share the same
date, location, and element:

- **Duplicate** — if the actual value is also identical, mark as duplicate.
- **Technical replicate** — same date/location/element but a *different* value,
  mark as technical replicate.

## 4. Step 5 — Mark additional data (`05_mark_additional_data.R`)

Adds three integer (0/1) existence flags to the **`subsample`** table (the
finest sampling unit = site + date + depth interval):

- `fe_exist` — a **FE** measurement is present in the subsample,
- `al_exist` — an **AL** measurement is present,
- `comp_exist` — any **sediment composition** (grain-size) measurement is present.

Classification is by symbol: the `element` table contains only the 7 targets,
the FE/AL normalisers, and composition params, so composition is defined as *any
element that is neither a target nor FE/AL* (no description parsing). Symbols are
upper-cased first since sources case them differently (`Fe` vs `FE`). Flags roll
up to event/site by taking the max over a group's subsamples.

Full list of grain-size codes lives in [sediment-composition-codes.md](sediment-composition-codes.md).
(Note: 4Demon carries no composition params, so its `comp_exist` is always 0.)

## 5. Step 6 — Mark multi (`06_mark_multi.R`)

Adds two integer columns to the **`event`** table:

- `n_layers` — number of `subsample` rows (depth layers / cores) under the event,
- `multi_flag` — 1 when `n_layers > 1` (a multi-layer/-core sampling such as a
  sliced core), 0 for a single grab.

Derived from the data rather than the `sampling_tool` code: the same gear code
yields both single- and multi-layer events (e.g. Mareano `MC` is ~60 % multi,
~40 % single; ICES-DOME `BC` is almost all single), so tool type is not a
reliable discriminator. Replicate-core events (several events at one
station/date/tool) are rare and inconsistent across sources (ICES-DOME: 0), so
they are not separately flagged; add that later if the clean stage needs it.
