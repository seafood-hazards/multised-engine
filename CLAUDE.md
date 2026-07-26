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
   and derive a standardised value. **All twelve steps done** (see below).
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


| 3 | `03_categorize.R`           | add `element.category`         | done   |
| 4 | `04_quality_control.R`      | add `area_flag`/`invalid_flag` | done   |
| 5 | `05_mark_duplicates.R`      | add `dup_flag` columns         | done   |
| 6 | `06_mark_additional_data.R` | add `exist_flag` columns       | done   |
| 7 | `07_mark_multi.R`           | mark multi-layer/-core samples | done   |
| 8 | `08_mark_below_loq.R`       | add `below_loq` column         | done   |
| 9 | `09_add_converted_value.R`  | add `value_std`/`unit_std`     | done   |
| 10| `10_mark_range.R`           | add `range_flag` column        | done   |
| 11| `11_mark_below_loq_num.R`   | add `below_loq_num` column     | done   |
| 12| `12_mark_weight_basis.R`    | add `weight_basis` column      | done   |
| 13| `13_mark_source_specific.R` | add `src_flag` (source-native) | van, ices, dem |
| 14| `14_derive_fines.R`         | add `fines_lt63` (<63µm %)      | mar, van, ices, mud |

Steps 1–12 are common to every source; **step 13 onward is source-specific** and
present only where a source has something extra to fold in or derive. So far
Vannmiljø, ICES-DOME and 4Demon have a step 13 (`src_flag`), and every source with
grain-size (all but 4Demon) has a step 14 (`fines_lt63`); step numbers are fixed
per concern, so a source runs only the later steps that apply to it (Mareano has
no native flags, so no step 13; 4Demon has no grain-size, so no step 14).

Step 3 adds `category` to `element` (`target` / `reference` / `organic` /
`composition`), the single source of truth for the measurand class that later
steps read instead of each redefining its own symbol lists (target = the 7
targets, reference = FE/AL, organic = CORG/TOC/TOC63, composition = grain-size
remainder). Step 4 adds two flags (NULL = passed): `area_flag` on `site`
(`outside_europe`) and `invalid_flag` on `measurement` (`negative` /
`over_range`). Step 5 adds a `dup_flag` to
`measurement` (`duplicate` / `technical_replicate`, NULL = neither), grouping on
location + date + depth + element + unit + method (`method` plus `lab` where the
source records it), so readings of the same element from different methods/labs
are not treated as replicates of each other. Both are suspicious markers for manual
review, not deletions. Step 6 adds `fe_exist` / `al_exist` / `org_exist` /
`comp_exist` (integer 0/1) to `subsample`, flagging whether the FE/AL normalisers,
organic carbon (CORG/TOC), and grain-size composition are available for that
sample (org/comp read `element.category`; FE/AL still keyed on the specific
symbol). Step 7 adds `n_layers` + `multi_flag` (0/1)
to `event`, marking multi-layer/-core samplings (events with >1 subsample) versus
single grabs; it is derived from the data, not the tool code, since the same gear
yields both. Step 8 adds `below_loq` (integer 0/1) to `measurement`, folding each
source's detection/quantification flag (mareano `below_lld`, vannmiljo `operator`
`<`/`ND`, ices-dome/mudab ICES `qflag` `<`/`Q`/`D`/`<~Q`, 4demon `limit_flag`)
into one common below-limit marker for removal in the clean stage. Step 9 adds
`value_std` + `unit_std` to `measurement`: a standardised value keyed on the
measurand (`element.category`) — chemistry (target + reference + organic) →
**mg/kg**, grain-size composition → **%** — converted from each source's unit via
the step-4 mass basis. It standardises the source's QC-corrected value where one
is provided (4Demon's `corrected_value`: scale-error fixes, below-detection
substitutions; raw `value` kept as provenance), else the raw `value`. It is a
reusable derived value (range
check, Fe/Al normalisation, cross-source merge), not a flag. Step 10 adds
`range_flag` (`below_min` / `above_max`, NULL = in range/unbounded/below-LOQ) to
`measurement`, comparing `value_std` against a per-element plausible range (draft,
generous bounds for the 7 targets + FE/AL + organic carbon; grain-size unbounded)
to catch implausibly high and low values. Step 11 adds `below_loq_num` (integer
0/1, NULL where the method has no numeric limit) to `measurement`: a numeric
cross-check of step 8's label-based `below_loq`, comparing `value_std` against the
method's own detection/quantification limit (LOQ, else LOD/LLD) converted to the
standardised unit. `value < limit` → 1, `value > limit` → 0, and at `value ==
limit` it defers to the detection flag `below_loq` (some sources substitute the
reported value at the limit — Mareano reports value == LLD for below-detection
results — so a value equal to the limit is below only when the flag is set). It
catches below-limit values the source labels missed; the clean stage can take the
union `below_loq = 1 OR below_loq_num = 1`. It runs on chemistry only (via
`element.category`); grain-size is left NULL, since a grain-size method's limit
column holds the size-class boundary in µm, not a detection limit. Coverage is
partial — 4Demon has no numeric limits and only ~13% of Vannmiljø does, so those
rows stay NULL; Mareano's `lld` is a collapsed representative limit, so its extra
flags should be read with that caveat. Step 12 adds `weight_basis` (`dry` / `wet`,
NULL for grain-size composition) to `measurement`, harmonising each source's
stated sample weight basis: from a `basis` column (ices-dome/mudab/4demon) or the
unit suffix (vannmiljo `dw`), with Mareano all dry (confirmed). Only chemistry is
classified; dry weight is the sediment standard, so the few wet rows (only
ices-dome, 363) are review candidates. Steps
3–7 and 9–11 have identical bodies across sources bar the DB path; steps 8 and 12
differ per source because the source signal differs. Step 13 is **source-specific**
and adds `src_flag` (TEXT, NULL = pass) to `measurement`, folding each source's
native leftovers the common flags miss. Vannmiljø: `above_range` (operator `>`, a
right-censored greater-than reading, distinct from the `<`/`ND` below-detection
already in `below_loq`) and `filtered` (`filtered = 1`, a filtered-water sample),
15 and 2 rows. ICES-DOME: `suspect` (`vflag` `S`, originator-flagged suspect) and
`calculated` (`vflag` `C`, a derived rather than measured value), 68 and 16 rows;
its `dcflag`/`metcu`/`uncrt`/`matrix` stay unfolded (provenance/metadata, not
quality flags). 4Demon carries several independent native flags that can co-occur,
so its `src_flag` holds a comma-joined token set: `suspect`/`invalid` (`vflag`
1/3), `range_check` (`range_check_flag`), `outlier_moderate`/`outlier_extreme`
(`outlier_extreme_flag` 1/2), `outlier_stdev` (`outlier_stdev_flag`); 1,621 rows
flagged. `vflag = 2` (below detection) is not folded — it duplicates `below_loq`.
Step 14 is a **grain-size derivation** (source-specific; every source with
grain-size, i.e. all but 4Demon): it adds `fines_lt63` + `fines_basis` to
`subsample`, the percentage of material finer than 63µm (the clay + silt "mud"
fraction), always via the standardised `value_std` (%) so units are safe, and
`fines_basis` records how it was derived. The derivation differs per source
because each encodes grain-size differently, and the source signal is noisy, so
per-source parameter definitions were verified against the pilot lookups:
**Mareano** stores four named bins (Clay <2µm, Silt 2–63µm, Sand 63–2000µm,
Gravel >2000µm), so `fines_lt63` = Clay + Silt (`fines_basis = 'sum_bins'`; all
Mareano samples are bulk, 3,265 subsamples, 0–99.5%). **Vannmiljø** takes the first available of: `FINS`
("Fines <63µm") directly (`fines_basis = 'fins'`); else its complement `GSMF_63`
("Particle fraction **>63µm**", the opposite of the ICES `GSMF63`, so NOT the
fines) as `100 − GSMF_63` (`'gsmf_63_complement'`); else the clay+silt sum `GSMF2`
(<2µm) + `GSMF2_63` (2–63µm) (`'clay_silt_sum'`, the Mareano approach); 7,113
subsamples. **ICES-DOME** / **MUDAB** report the cumulative `GSMF63` ("<63µm
silt/clay"), which is <63µm *of the matrix it sits on*, so the matrix is combined
in: preferred on `SEDtot` (whole sample), else the bulk-equivalent `SED2000`/
`SED1000` (coarse sieving removes gravel), while finer matrices are trivially
~100% and excluded (`fines_basis = 'gsmf63_<matrix>'`; 8,811 and 4,033
subsamples). Implausible values (`value_std` outside 0–100%) are excluded (left
NULL) rather than corrected here. Note `GSMF63`/`GSMF_63` naming is source-
dependent (ICES = below, Vannmiljø = above); do not assume the number is a
below-cutoff. The dedicated noisy-grain-size correction pass is still separate.
Full step specs are in [docs/slim-pipeline.md](docs/slim-pipeline.md).

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
- **No em-dashes in the Quarto site pages** (`multised-*/*.qmd`): use commas,
  colons, or parentheses instead.
- Sites are keyed on latitude/longitude **rounded to 3 decimal places**.
- The `sedimenter` DESCRIPTION/NAMESPACE make this a package skeleton, but the
  code is a script pipeline, not an exported-function package.

## Target elements

- **7 targets:** CO, CU, I, MN, MO, SE, ZN.
- **2 normalisers:** FE, AL.
- **Organic carbon:** CORG (ices-dome, mudab) / TOC, TOC63 (mareano, vannmiljo);
  its own category, tracked by `org_exist` — not counted as composition.
- **Sediment composition:** grain-size mass-fraction parameters (ICES-DOME
  `GS…`/`GSMF…` codes); used to flag whether composition data exist.
