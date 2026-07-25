# Slim pipeline — schema reference & QC/marking plan

Companion to [../CLAUDE.md](../CLAUDE.md). Covers (1) the shared slim schema and
its per-source column differences, and (2) the behaviour of the
marking steps 3–12, plus the source-specific step 13 (Vannmiljø, ICES-DOME).

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

## 2. Step 3 — Categorize (`03_categorize.R`)

Adds one column to the **`element`** table:

- `category` — the measurand class of each element symbol: `target` (the 7
  targets Co/Cu/I/Mn/Mo/Se/Zn), `reference` (the Fe/Al normalisers), `organic`
  (organic carbon: CORG/TOC/TOC63), or `composition` (grain-size, the remainder).

This is the single source of truth for the measurand class. The later steps that
used to redefine their own `targets`/`normalisers`/`organic` symbol vectors read
this column instead (step 6 supporting-data availability, step 9 unit conversion,
step 11 numeric below-limit), so the classification lives in one place. It is a
pure function of the upper-cased symbol (`Fe` vs `FE`), so the step is fully
idempotent; the stored `symbol` keeps its original case.

## 3. Step 4 — Quality control (`04_quality_control.R`)

Add a flag column per check (NULL = passed): `area_flag` on `site` and
`invalid_flag` on `measurement`.

- **Area QC** (`site.area_flag`) — restrict to European seas/oceans; flag sites
  whose location falls outside Europe (`outside_europe`). Uses
  `site.latitude`/`longitude`, and `sea_name`/`country` already derived in the
  pilot stage.
- **Invalid values** (`measurement.invalid_flag`) — flag measurements that are
  negative (`negative`) or exceed unit-based limits (`over_range`, e.g.
  `unit == "ug/g"` ⇒ max 1000). Applies to `measurement.value`.

## 4. Step 5 — Mark duplicates (`05_mark_duplicates.R`)

Add `dup_flag` columns to the relevant tables. Two observations share the same
date, location, depth, element, unit, **and method** (`method` plus `lab` where
the source records it — Vannmiljø and 4Demon carry no `lab`). Including the
method means two readings of one element on the same occasion but from different
analytical methods/labs are kept as distinct analyses, not replicates (e.g.
Mareano measures Se by both AAS and ICP-AES). Per-result LOD/LOQ/uncertainty are
metadata, not part of the method identity.

- **Duplicate** — if the actual value is also identical, mark as duplicate.
- **Technical replicate** — same occasion + method but a *different* value,
  mark as technical replicate.

## 5. Step 6 — Mark additional data (`06_mark_additional_data.R`)

Adds four integer (0/1) existence flags to the **`subsample`** table (the
finest sampling unit = site + date + depth interval):

- `fe_exist` — a **FE** measurement is present in the subsample,
- `al_exist` — an **AL** measurement is present,
- `org_exist` — an **organic-carbon** measurement is present (CORG / TOC / TOC63),
- `comp_exist` — any **sediment composition** (grain-size) measurement is present.

`org_exist` and `comp_exist` read `element.category` from step 3 (`organic` and
`composition`); `fe_exist`/`al_exist` still test the specific FE/AL symbol, which
the shared `reference` category does not distinguish. Symbols are upper-cased
first since sources case them differently (`Fe` vs `FE`). Flags roll up to
event/site by taking the max over a group's subsamples.

Full list of grain-size codes lives in [sediment-composition-codes.md](sediment-composition-codes.md).
(Note: 4Demon carries no composition or organic-carbon params, so its
`comp_exist` and `org_exist` are always 0.)

## 6. Step 7 — Mark multi (`07_mark_multi.R`)

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

## 7. Step 8 — Mark below LOQ (`08_mark_below_loq.R`)

Adds one integer column to the **`measurement`** table:

- `below_loq` — 1 when the value is below the detection/quantification limit (an
  uncertain "less-than" reading), 0 for a quantified value.

It folds LOD and LOQ together into a single below-limit marker, taken from each
source's own detection flag (not a numeric `value < loq` comparison — the flags
are the authoritative source-provided signal). These rows are candidates for
removal in the clean stage (`WHERE below_loq = 1`). Unlike the other marking
steps the body is **not** identical across sources, because the source flag
differs:

| Source     | Flag column          | Values meaning below-limit | rows |
|------------|----------------------|----------------------------|-----:|
| mareano    | `below_lld` (0/1)    | `1` (LOD only; no LOQ)     | 4,583 |
| vannmiljo  | `operator`           | `<`, `ND`                  | 1,987 |
| ices-dome  | `qflag` (ICES)       | `<`, `Q`, `D`, `<~Q`       | 2,043 |
| mudab      | `qflag` (ICES)       | `<`, `Q`, `D`              | 1,299 |
| 4demon     | `limit_flag` (0/1)   | `1`                        | 53 |

`Q` = below limit of quantification, `D` = below detection limit, `<` = less-than,
`ND` = not detected. Vannmiljø's `operator` also carries `>` (above-range) which
is kept as 0 — it is not a detection-limit case. The two `qflag` scripts warn if a
rebuild introduces a non-NULL flag code outside the mapped set, so the crosstab in
each script's verify block stays auditable.

## 8. Step 9 — Add converted value (`09_add_converted_value.R`)

Adds two columns to the **`measurement`** table — a source-agnostic standardised
value and its unit — reused by the range check (step 10), the numeric below-limit
check (step 11), Fe/Al normalisation, and the cross-source merge:

- `value_std` (REAL) — the value in a common unit,
- `unit_std` (TEXT) — that unit.

Standardisation is by **measurand** (`element.category` from step 3), not raw
unit:

- **Chemistry** (`target` / `reference` / `organic`) — the 7 targets, the Fe/Al
  normalisers, and organic carbon (CORG/TOC/TOC63) → **mg/kg** dry weight.
- **Grain-size composition** → **%** (mass/volume fraction). There is no
  length/µm grain-size in the data, so every grain-size value is a fraction; `%`
  is the only standardised grain-size unit. `vol.%` is treated as `%` here — the
  mass-vs-volume distinction is left to the dedicated grain-size step.

The conversion goes through the mass fraction `value / denom`, where `denom` is
"100 % of sample mass" in the original unit (the same canonical-unit map as
step 4). The fraction is then scaled to the target unit's full scale (`1e6` for
mg/kg, `1e2` for %). Units without a mass basis leave `value_std`/`unit_std` NULL
and warn. This is a derived value, not a flag.

## 9. Step 10 — Mark implausible range (`10_mark_range.R`)

Adds one column to the **`measurement`** table:

- `range_flag` — `below_min` / `above_max` when `value_std` falls outside a
  per-element plausible range; NULL when in range, when the element has no bound,
  or when the row is a below-LOQ reading (a limit, not a value).

It reads the standardised `value_std` (mg/kg) from step 9 and compares it to a
per-element min/max table. The bounds are **draft, deliberately generous** — they
target clearly implausible values (both impossibly high *and* impossibly low,
e.g. Vannmiljø's Al at ~60 mg/kg or Fe at ~0.0002 mg/kg) rather than strict
geochemical limits, and should be reviewed with domain input. They cover the 7
targets, the Fe/Al normalisers, and organic carbon (as carbon mass); grain-size
composition is unbounded (noisy, deferred to its own step). Draft bounds
(mg/kg dry weight):

| Element | min | max | | Element | min | max |
|---------|----:|----:|-|---------|----:|----:|
| Co | 0.1  | 300    | | Zn             | 1   | 20,000  |
| Cu | 0.5  | 10,000 | | Fe             | 500 | 250,000 |
| I  | 0.1  | 1,000  | | Al             | 500 | 200,000 |
| Mn | 1    | 50,000 | | CORG/TOC/TOC63 | 100 | 300,000 |
| Mo | 0.05 | 500    | | | | |
| Se | 0.01 | 100    | | | | |

Steps 9 and 10 have identical bodies across sources bar the DB path.

## 10. Step 11 — Mark below limit, numeric (`11_mark_below_loq_num.R`)

Adds one column to the **`measurement`** table:

- `below_loq_num` — `1` when the value is at or below the method's numeric
  detection/quantification limit, `0` when above it, NULL when the method carries
  no numeric limit (not assessable).

This is a **numeric cross-check** of step 8's label-based `below_loq`: a source's
detection *label* can be wrong, so the value is also compared directly against the
`method` table's own limit. The limit taken is **LOQ, else LOD, else LLD** (the
most inclusive), converted into the same standardised unit as `value_std` (via the
step-9 mass basis) so value and limit are compared like for like. It runs on
**chemistry only** (`element.category` in `target` / `reference` / `organic`); grain-size
composition is left NULL, because a grain-size method's limit column holds the
particle-size class boundary in µm (e.g. Gravel 2000, Sand 63), not a
concentration detection limit — comparing that against a mass-% value would flag
almost every grain-size row spuriously. `value_std <
limit_std` → `1`, `value_std > limit_std` → `0`, and **at the limit exactly**
(`value_std == limit_std`) it defers to the source detection flag `below_loq`:
some sources substitute the reported value *at* the limit (Mareano reports
value == LLD for below-detection results), so a value equal to the limit is
below-detection only when the flag is set, and a genuine reading equal to the
limit (flag off) stays `0`.

It is kept **separate** from `below_loq` so the two stay auditable; the clean stage
can take the union `below_loq = 1 OR below_loq_num = 1` for aggressive removal.
Caveats: coverage is partial — 4Demon has no numeric limits, and only ~13 % of
Vannmiljø does, so those rows are NULL; and Mareano's `lld` is a single collapsed
representative limit per method, so its extra flags (values below the
representative LLD but likely from lower-LLD batches) should be read with that in
mind. Like steps 3–7 and 9–10, the body is identical across sources bar the DB
path (the limit column is picked by whichever of `loq`/`lod`/`lld` the source has).

## 11. Step 12 — Mark weight basis (`12_mark_weight_basis.R`)

Adds one column to the **`measurement`** table:

- `weight_basis` — `dry` / `wet` for a chemistry measurement, NULL for grain-size
  composition (the dry/wet-weight distinction is a concentration concept; a
  grain-size fraction's vol.%/wt.% basis is left to the dedicated grain-size
  step).

It harmonises each source's stated sample weight basis into one common marker.
Like step 8, the body is **not** identical across sources, because the signal
differs:

| Source     | Signal                       | Values                     |
|------------|------------------------------|----------------------------|
| mareano    | none (all dry, confirmed)    | every chemistry row `dry`  |
| vannmiljo  | unit suffix                  | `… dw` ⇒ dry, `… ww` ⇒ wet |
| ices-dome  | `basis` column               | `D` ⇒ dry, `W` ⇒ wet       |
| mudab      | `basis` column               | `D` ⇒ dry                  |
| 4demon     | `basis` column               | `dw` ⇒ dry                 |

Classification is scoped to chemistry via `element.category` (step 3); grain-size
composition stays NULL. Dry weight is the sediment standard, so the only
wet-weight rows in the data are ICES-DOME's 363 chemistry measurements; those are
review / conversion candidates for the clean stage.

## 12. Step 13 — Mark source-specific (`13_mark_source_specific.R`)

Steps 1–12 are common to every source. From step 13 the pipeline becomes
**source-specific**: a source gets one only if it carries native flags the common
steps do not already cover. Each such source adds its own `src_flag` (TEXT, NULL =
pass) to `measurement`, with its own value vocabulary, folding those leftovers into
one review marker for the clean stage. So far Vannmiljø and ICES-DOME have one.

### Vannmiljø

Vannmiljø carries `operator` (a relational sign) and `filtered`. The
below-detection meaning of `operator` (`<` / `ND`) is already in `below_loq`
(step 8); what remains is:

| `src_flag`    | Source condition | Meaning                                             | rows |
|---------------|------------------|-----------------------------------------------------|-----:|
| `above_range` | `operator = '>'` | right-censored "greater-than" reading (lower bound)  | 15 |
| `filtered`    | `filtered = 1`   | filtered-water sample rather than bulk sediment      | 2 |

The two are disjoint in the data (a combined `above_range,filtered` label is kept
only as a guard). Unlike `weight_basis`, `above_range` is not scoped to chemistry:
a `>` grain-size fraction is right-censored too (11 of the 15 are grain size).

### ICES-DOME

ICES's `qflag` (detection/quantification) and `basis` are already folded (steps 8
and 12). Its `vflag` (the originator value-quality flag) is folded here; meanings
are from the pilot `code_lookup` table:

| `src_flag`   | Source condition | Meaning                                              | rows |
|--------------|------------------|------------------------------------------------------|-----:|
| `suspect`    | `vflag = 'S'`    | suspect value (originator QC / instrument performance) | 68 |
| `calculated` | `vflag = 'C'`    | a calculated (derived) value, not a direct measurement | 16 |

`vflag = 'A'` ("Acceptable value") and NULL pass. ICES's other native columns are
left unfolded on purpose: `dcflag` holds DATSU screening/conversion codes (mostly
benign unit conversions), and `metcu`/`uncrt`/`matrix` are uncertainty and
sample-fraction metadata, not clean quality flags.

All `src_flag` values are review / removal candidates for the clean stage.
