# Slim pipeline — schema reference & QC/marking plan

Companion to [../CLAUDE.md](../CLAUDE.md). Covers (1) the shared slim schema and
its per-source column differences, and (2) the behaviour of the
marking steps 3–12, plus the source-specific steps 13 (`src_flag`), 14 (grain-size
correction) and 15 (`fines_lt63`).

## Running it

```r
create_db("slim", source)                 # every step that applies
create_db("slim", "ices-dome", steps = 14:15)
```

`slim_steps(source)` returns the applicable steps. Steps 1-2 are one unit: the
parse feeds the write, so requesting either runs both. Package code is
`R/slim-*.R`.

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

Where a source provides a **QC-corrected value**, `value_std` is standardised from
that rather than the raw `value`: 4Demon's `corrected_value` (which the 4Demon
metadata recommends for analysis) carries scale-error fixes and below-detection
substitutions — e.g. Fe reported as 720,000 µg/g (72 %) corrected to 72,000 µg/g
(7.2 %). The raw `value` column is left untouched as provenance. The step reads
`corrected_value` where the column exists (`coalesce(corrected_value, value)`) and
falls back to `value` for every other source, so the body stays identical across
sources. Adopting the corrected values cleared all 49 of 4Demon's spurious
`above_max` range flags (step 10).

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

### 4Demon

4Demon's detection-limit flag (`limit_flag`) and `basis` are already handled
(steps 8 and 12). Unlike the other two sources it carries **several independent**
quality flags that can co-occur on one row, so its `src_flag` holds a comma-joined
set of tokens (meanings from the pilot metadata):

| Token              | Source condition          | Meaning                                    |
|--------------------|---------------------------|--------------------------------------------|
| `suspect`          | `vflag = 1`               | suspect value                               |
| `invalid`          | `vflag = 3`               | invalid value                               |
| `range_check`      | `range_check_flag = 1`    | outside 4Demon's expected range             |
| `outlier_moderate` | `outlier_extreme_flag = 1`| moderate per-parameter outlier              |
| `outlier_extreme`  | `outlier_extreme_flag = 2`| extreme per-parameter outlier               |
| `outlier_stdev`    | `outlier_stdev_flag = 1`  | outlier by a standard-deviation threshold   |

`vflag = 2` (below detection) is **not** folded: it duplicates `below_loq`
(step 8, from the detection-limit flag). `corrected_value`, `fraction_range` and
`matrix` are provenance/metadata, not quality flags. 1,621 of 6,739 rows carry at
least one token.

All `src_flag` values are review / removal candidates for the clean stage.

## 13. Step 14 — Correct grain-size (`14_correct_grainsize.R`)

A **grain-size correction** step (source-specific; ICES-DOME, MUDAB, Vannmiljø).
It adds two columns to `measurement`:

| column           | type | meaning                                                     |
|------------------|------|-------------------------------------------------------------|
| `value_std_corr` | REAL | corrected standardised value; equals `value_std` everywhere except renormalised grain-size fractions (a drop-in "best" `value_std` for any row, chemistry included) |
| `gs_corr`        | TEXT | `renorm` = rescaled by the per-curve factor; `invalid` = grain-size value reviewed and confirmed unreliable (removal candidate, `value_std_corr` nulled); `suspect` = auto-flagged implausible/uncorrectable curve (currently none); NULL = untouched |

Many grain-size curves (chiefly ICES-DOME and MUDAB) are internally consistent (a monotone
cumulative distribution) but scaled wrong: within one sample every code is inflated
by the same factor, so `value_std` runs to thousands of "percent" (e.g. every code
≈13,481 instead of ≈100).

**ICES-DOME / MUDAB** renormalise each curve. A curve is one `(subsample, matrix)`
group, defined by its cumulative `GSMF<n>` codes; the anchor is the largest
`value_std` in the curve (the coarsest cutoff, i.e. the total). A curve is
corrected only when it is over-scaled (`anchor > 100.5`) **and** monotone (a valid
cumulative shape); then every mass-fraction code in the curve is multiplied by
`100 / anchor` (`gs_corr = 'renorm'`). The curve is built only from the cumulative
"<n" `GSMF<n>` codes; the ">n" gravel codes (`GSMF>2000` / `GSMF>8000`) are
excluded, else an anomalously large gravel value breaks the monotonicity check and
wrongly rejects an otherwise correctable curve. Grain-size statistics (`GSMEA` /
`GSMED` / `GSSORT` / …) are not fractions and are never rescaled. Rows still
`> 100` after this (a non-monotone / uncorrectable curve) are marked `suspect`.
Results: ICES-DOME 1,147 `renorm`, MUDAB 1,068 `renorm`, both 0 `suspect`.

**Vannmiljø** has no matrix, and its `GSMF_63` / `GSMF_2000` codes mean ">n µm"
(not "<n"), so the per-curve renormalisation does not apply. Its noise is instead a
handful of isolated values (22 rows). These were exported
(`R/slim/review/export_vannmiljo_suspect_grainsize.R`) and manually reviewed
against the raw data: the error magnitude varies per row (×1000, ×10, borderline)
and the values were found incorrect, so they are flagged `gs_corr = 'invalid'`
(with `value_std_corr` nulled) for removal in the clean stage rather than rescaled.

Assumption: renormalising the coarsest cutoff to 100 % treats the `<2 mm` total as
the whole sample (gravel negligible), consistent with the bulk-equivalent decision
in the sample-fraction work. Raw `value` / `value_std` are untouched as provenance.
The later fines step (15) reads `value_std_corr`.

## 14. Step 15 — Derive fines <63µm (`15_derive_fines.R`)

A **grain-size derivation** step (source-specific; every source with grain-size,
i.e. all but 4Demon). It reads the corrected `value_std_corr` from step 14 (Mareano
uses `value_std`; it has no correction step). It adds two columns to `subsample`:

| column        | type | meaning                                                        |
|---------------|------|----------------------------------------------------------------|
| `fines_lt63`  | REAL | percentage of material finer than 63µm (the clay + silt "mud" fraction), NULL where the subsample has no usable grain-size |
| `fines_basis` | TEXT | how it was derived, for provenance / cross-source comparison   |

`fines_lt63` is taken from the corrected `value_std_corr` (step 14; Mareano uses
`value_std`, which for its clean vol.%/wt.% data are the same) so units (`%`,
`g/kg`, ...) are handled uniformly and the renormalised curves are used. The
derivation differs per source because each encodes grain-size differently and the
raw signal is noisy, so the per-source parameter definitions below were verified
against the pilot `parameter` / `code_lookup` tables. Values whose `value_std_corr`
is still outside 0–100% or nulled after correction (the step-14 `invalid` /
`suspect` rows) are **excluded** (the subsample is left NULL). Coverage is therefore
partial. A summary of what each source
contributes:

| source    | code used            | `fines_basis`                          | subsamples |
|-----------|----------------------|----------------------------------------|-----------:|
| Mareano   | Clay + Silt bins     | `sum_bins`                             | 3,265      |
| Vannmiljø | `FINS`, else complement, else clay+silt | `fins` / `gsmf_63_complement` / `clay_silt_sum` | 7,113 |
| ICES-DOME | `GSMF63` on bulk matrix | `gsmf63_sedtot` / `gsmf63_sed2000`   | 8,957      |
| MUDAB     | `GSMF63` on bulk matrix | `gsmf63_sedtot` / `gsmf63_sed2000`   | 4,162      |

**Mareano** stores grain-size as four named bins (`element.category =
'composition'`):

| bin      | size        |
|----------|-------------|
| `Clay`   | < 2µm       |
| `Silt`   | 2 – 63µm    |
| `Sand`   | 63 – 2000µm |
| `Gravel` | > 2000µm    |

So `fines_lt63 = Clay + Silt`, summed from the standardised `value_std` (grain-size
→ %, step 9) so the sum is unit-safe; `fines_basis = 'sum_bins'`. All Mareano
samples are bulk grabs, so this is the <63µm fraction of the **whole sample**.
Result: 3,265 subsamples, range 0–99.5% (mean 72.8%), none over 100%. Sand and
Gravel are the coarse remainder and play no part; Gravel is reported wt.% against
the others' vol.%, so the four never sum cleanly, but Clay + Silt share a basis
and do.

**Vannmiljø** has no `matrix` (all taken as whole-sample) and reports two direct
codes whose naming is a trap: `FINS` = "Fines <63µm" (the fraction we want) but
`GSMF_63` = "Particle fraction **>63µm**", the *complement* (the opposite sense of
the ICES `GSMF63`). Since `FINS + GSMF_63 ≈ 100` (verified), `fines_lt63` = `FINS`
where present (`fines_basis = 'fins'`), else `100 − GSMF_63`
(`'gsmf_63_complement'`), else the clay+silt sum `GSMF2` ("<2µm", clay) +
`GSMF2_63` ("2–63µm", silt) (`'clay_silt_sum'`, the same construction as Mareano,
for samples that carry the fraction bins but neither direct code). 7,113
subsamples (3,628 `fins` + 3,094 `gsmf_63_complement` + 391 `clay_silt_sum`).

**ICES-DOME** and **MUDAB** report the cumulative `GSMF63` ("Grain Size Mass
Fraction <63 micron, silt/clay"): the <63µm fraction, but *of the matrix it was
measured on*, so the matrix (the sample-fraction work) is combined in:

| matrix                | `GSMF63` means                          | used as fines? |
|-----------------------|-----------------------------------------|----------------|
| `SEDtot`              | <63µm of the whole sample               | yes (1st choice) |
| `SED2000` / `SED1000` | <63µm of the <2 mm / <1 mm material     | yes, as whole-sample under the no-gravel assumption below (2nd choice) |
| `SED63`, `SED20`, ... | <63µm of an already-fine fraction (~100%) | no, excluded |

Priority `SEDtot` > `SED2000` > `SED1000`; the highest-priority clean value per
subsample wins, and `fines_basis = 'gsmf63_<matrix>'` records which. Reading the
corrected `value_std_corr` recovers the samples renormalised in step 14: ICES-DOME
8,957 subsamples (6,611 `sedtot` + 2,346 `sed2000`), MUDAB 4,162 (4,152 + 10).

**Gravel reconciliation (`gsmf63_sed2000`).** A `<2 mm`-based fines value is the
`<63 µm` share of the `<2 mm` material, not of the whole sample; converting it
would need the sample's gravel (`>2 mm`) proportion. That proportion is
**unmeasured**: every one of these ~2,356 subsamples (2,346 ICES-DOME, 10 MUDAB)
carries grain-size *only* on the `SED2000` matrix, with no `SEDtot` row at all, so
there is nothing to reconcile against. They are therefore taken as whole-sample
fines under the assumption that **gravel is negligible** (true for open-marine
sediment, not for gravelly / coastal), and `fines_basis = 'gsmf63_sed2000'` marks
them so a downstream user can down-weight or drop them. `SEDtot`-based fines
(`gsmf63_sedtot`) are genuine whole-sample values and need no such caveat.

The idempotent write pattern is the usual one, keyed on `subsample_id`: a
temporary `qc_fines` table plus an unconditional correlated-subquery `UPDATE`
(subsamples absent from `qc_fines` reset to NULL on re-run).

Bin-summing was assessed for the remaining uncovered samples. It pays off only
for Vannmiljø (the clean clay+silt sum above); the ICES-DOME / MUDAB `GS>a<b` bins are
too sparse and incomplete to help (median partition total ~72 %, no `<20µm` clay
bin, and a 60µm rather than 63µm boundary). The one bin-based route for
ICES-DOME / MUDAB, `GSMF20` (<20) + `GS>20<60`, reaches only `<60µm` (~138
samples) and was deliberately **not** added, since those sources are already
~60–67 % covered by `GSMF63` and the proxy would mix a different cutoff into the
column.

The step-14 `suspect` rows have all been resolved: the MUDAB false-positive was
fixed (the gravel-code parser bug above) and Vannmiljø's 22 were reviewed and
flagged `invalid`. (The `SED2000` gravel reconciliation was investigated and found
to be impossible from the data, since these samples have no whole-sample
grain-size; it is instead handled by the documented negligible-gravel assumption
above.)
