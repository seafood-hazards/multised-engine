# Clean pipeline — plan & spec (draft)

The third generation. Each source's `<source>_slim.sqlite` is turned into a
`<source>_clean.sqlite` by applying the slim flags and harmonising to a uniform
format. Still **one DB per source**; merging into a single cross-source DB is a
later generation (see [plan.md](plan.md)). A single website summarises the clean
results (replacing the per-source pilot sites).

Run with `create_db("clean", source)`; package code is `R/clean-*.R`, with the
shared helpers in `R/clean-shared-*.R`. Reads the slim DB. Three ordered steps
(the parenthesised names are the originals):

1. **Harmonise** (data conversion) — uniform names, units, depths, tools.
2. **Clean** (data cleaning) — remove flagged rows, collapse replicates.
3. **Annotate** (labelling) — carry labels; split grain-size to its own table.

Decisions locked so far: organic carbon `TOC → CORG`, `TOC63` kept separate (all
chemistry stays in one `measurement` table, distinguished by `element.category`);
Clean removes **all** `src_flag` rows; grain-size composition becomes a **separate
table** (`grain_size_fraction`) and is dropped from `measurement`; sediment fraction
is `frac_class` (`bulk`/`sieved`) + `sieve_um` per row on `measurement` (with the
raw `matrix` kept), summarised over the **targets** (`bulk`/`sieved`/`mixed`) onto
`subsample` as `target_frac_class` / `target_sieve_um`; the `<63 µm` mud content is
kept as numeric `fines_lt63` on `subsample`.

---

## Target clean schema

Seven tables carried over (`element`, `dataset`, `site`, `event`, `subsample`,
`measurement`, `method`) plus one new: **`grain_size_fraction`** (the grain-size
detail; its summary is folded onto `subsample`). 4Demon has no grain-size, so it
lacks that table. Key changes vs slim:

- **element** — the name column is renamed `element → name`; chemistry rows carry a
  uniform canonical Title-Case `name` and a `cas` number, identical across sources;
  grain-size composition names follow ICES-DOME where the symbol is shared (Mareano's
  named bins and Vannmiljø's `_`-forms keep their own label), all with `cas` NULL.
  Columns: `symbol`, `name`, `category`, `cas`.
- **dataset** — a common column set across sources: `dataset_id`, `dataset_name`,
  `dataset_code`, `dataset_group`, `source`, `source_type` (currently "database"),
  `url` (source website), `doi` (NULL for now), `country`, `region`, `institute`,
  `institute_code`, `accessed` (retrieval date). Columns a source lacks are NULL;
  ICES-DOME's multi-nation `country`/`institute` lists are de-duplicated and sorted
  (kept for back-tracing); MUDAB `country` is set to Germany. A shared lookup
  (`R/clean-shared-dataset-meta.R`) supplies `url` + `accessed`.
- **site** — a common column set: `site_id`, `latitude`, `longitude`, `depth`,
  `country`, `country_code`, `dist_to_coast`, `municipality`, `sea_name`,
  `dist_to_aquaculture`. `depth`
  is the station / water depth (m; distinct from the sediment core depth in
  `subsample.depth_from`/`depth_to`) and is present for every source (Mareano
  native; the others populated by the upstream geocoding / bathymetry tools).
  `dist_to_aquaculture` (km to the nearest Norwegian farm) is added by the
  aquaculture step (see below), populated only for sites in Norway
  (`country_code = 'NOR'`) and NULL elsewhere.
  `site_id` and the coordinates are stable; the other attributes are regenerated
  upstream. `standardise_site()` (Harmonise) guarantees the column set/order and
  keeps the slim `area_flag`; the Clean step then consumes it via
  `consume_area_flag()` (`R/clean-shared-site-meta.R`): sites flagged
  `outside_europe` and their linked event/subsample/measurement rows are removed
  (cascade), and the `area_flag` column is dropped, so the final `site` has no flag.
- **measurement** — all chemistry (`target` / `reference` / `organic`); grain-size
  composition splits to `grain_size_fraction`. Columns: `symbol` (ICES), `value` +
  `unit` (original value, ICES-named unit), `value_std` + `unit_std` (mg/kg), and
  for collapsed technical replicates `value_sd` + `n_rep`; measurement uncertainty
  `value_uncrt` (mg/kg, from ICES `uncrt`/`metcu` and MUDAB `method.uncertainty`);
  the sediment fraction as the raw `matrix` (kept as provenance) plus its
  user-facing **`frac_class`** (`bulk` / `sieved`) + **`sieve_um`** (fine cutoff in
  µm, e.g. 63/20; NULL for bulk), derived via `_shared/fraction_meta.R`; `method_id`
  retained. bulk/sieved is per-measurement because it varies within a subsample (a
  subsample's metals and its organic carbon, and even different target metals, are
  often on different fractions). The slim marking columns are consumed by Clean.
  Organic carbon (CORG / TOC\*) stays here too, told apart by `element.category`;
  it is not split into a separate table since the columns would be identical.
- **method** — columns `method_id`, `symbol`, `method`, `method_description`,
  `lab`, `lab_name`, `lod`, `loq`, `limit_unit`. Grain-size (composition-symbol)
  methods are dropped (`grain_size_fraction` has no `method_id`, so nothing is
  orphaned). `method` is mapped to the ICES-DOME vocabulary (MUDAB already uses it;
  Mareano `ICP-AES`→`ICP-OES`, `LECO-analyser`→`CNA`; Vannmiljø ISO/NS standard
  references → the technique, e.g. `ISO 17294-2`→`ICP-MS`, `ISO 11885`→`ICP-OES`;
  4Demon `campaign_technique_fraction` codes → the technique; unlisted / NULL →
  `unknown`), with `method_description` kept where present (ICES/MUDAB) or filled
  from the ICES wording. `lod` / `loq` are converted to mg/kg (`limit_unit` =
  `mg/kg`). `comment` (Mareano) and `uncertainty` (MUDAB, unused by Clean) are
  dropped. Via `R/clean-shared-method-meta.R`.
  - The 4Demon sieve fraction, previously encoded in the method code, moves to the
    `fraction_range` column and joins the replicate-collapse key (so `<63µm` and
    `<2000µm` values of the same element are not averaged together).
- **event** — columns `event_id`, `dataset_id`, `site_id`, `year`, `date`,
  `sampling_tool`, `n_layers`. `date` is derived from `datetime` where needed
  (`datetime` / `time` dropped). `sampling_tool` is remapped from the raw gear codes
  to short descriptive names via a shared lookup (`R/clean-shared-event-meta.R`;
  e.g. `VV`/`19B` -> van Veen grab, `BC` -> box corer, unlisted / missing ->
  unknown). `multi_flag` is dropped (equals `n_layers > 1`) and ICES-DOME's
  `tool_description` is folded into the name.
- **subsample** — a common 13-column layout across all sources
  (`_shared/subsample_meta.R`): `depth_from` / `depth_to` in **cm** plus a
  `depth_flag` (`implausible` where the source's reported depth was out of range
  or inverted and was removed, else NULL — only Vannmiljø sets it, so a NULL
  `depth_from`/`depth_to` elsewhere means the source never recorded one; the row is
  kept either way so a user can spot depth-less rows and drop them if they need
  depth); supporting-data
  flags (`fe_exist`, `al_exist`, `org_exist`, `comp_exist`); a per-subsample
  **fraction summary** `target_frac_class` (`bulk` / `sieved` / **`mixed`**) +
  `target_sieve_um`, derived from the subsample's **target** measurements only
  (`mixed` = its targets span both bulk and sieved, ~4% of grain-bearing sources;
  NULL where no target chemistry; named apart from the measurement columns so the
  tables can be joined without a clash); and the grain-size mud content `fines_lt63`
  (% <63µm) + `fines_basis`
  (from slim step 15). This fixes 4Demon's `org_exist`/`comp_exist` order.
- **grain_size_fraction** (new, one row per grain-size mass-fraction measurement,
  detail): surrogate PK `gsf_id` (row number, unique index `ix_gsf_pk`, since the
  natural `subsample_id`+`symbol`+`matrix` is not unique), `subsample_id`, `symbol`,
  `matrix`, size bounds `lo_um`/`hi_um`, `value_pct` (the
  corrected %); grain-size statistics (GSMEA/GSMED/...) and `gs_corr='invalid'`
  rows excluded. The multi-valued fractions are normalised into their own table
  rather than crammed onto the subsample.

---

## 1. Harmonise (data conversion)

Value-preserving relabel/reshape; leans on slim's `value_std` / `unit_std` /
`category`.

- **Symbols → ICES canonical.** Targets (`CO CU I MN MO SE ZN`) and normalisers
  (`FE AL`) are identity after case-folding (`Fe`→`FE`). Organic carbon:
  `TOC → CORG`, `TOC63` kept as-is. A small per-source symbol map does this.
- **Element names + CAS.** The `element` name column becomes `name`; each chemistry
  symbol gets one canonical Title-Case name and CAS number from a shared lookup
  (`R/clean-shared-element-meta.R`), so all sources read identical values. CAS is
  taken from Vannmiljø's `cas_no` where available (AL FE CO CU MN MO SE ZN), iodine
  added from the registry; organic carbon (CORG/TOC63) has no CAS (NULL). Grain-size
  composition names follow ICES-DOME for shared symbols via the same lookup (so e.g.
  Vannmiljø `GSMF2` matches ICES); symbols ICES does not use keep their source label.
  Composition CAS is NULL.
- **Units → ICES names**, original value kept. e.g. `µg/g`→`ug/g`, strip the
  Vannmiljø `dw` / `C` suffixes (`mg/kg dw`→`mg/kg`, `g/kg C`→`g/kg`). `value_std`
  is already mg/kg; add `unit_std` even though constant.
- **Depth → cm.** Units differ by source and must be confirmed from pilot
  metadata (working assumption: Mareano/MUDAB/4Demon already cm; ICES `[0,2]`
  likely metres → ×100; **Vannmiljø `[0,42600]` is corrupt/mixed and needs a
  cleaning pass**). OPEN ITEM.
- **event date.** Derive `date` from `datetime` (Vannmiljø); drop `time` (MUDAB);
  keep `year`.
- **sampling_tool / method → ICES codes** where mappable. Mareano/ICES/MUDAB/
  4Demon already use ICES-style gear codes; **Vannmiljø records ISO sampling
  standards (`NS-EN ISO 5667-19*`) that do not map to ICES gear** → residual
  `unknown`. Mapping tables built incrementally. OPEN ITEM.
- **LOD / LOQ** kept with units on `method` (Mareano `lld`→`lod`; 4Demon null).
- **`measurement.matrix` → ICES `SED<µm>` vocabulary** (the sediment fraction the
  chemistry was measured on). ICES-DOME and MUDAB already use it (`SEDtot`,
  `SED2000`, `SED1000`, `SED500`, `SED90`, `SED63`, `SED62`, `SED20`); **4Demon**
  is remapped (`FS` fine <63 µm → `SED63`, `US` unsieved/bulk → `SEDtot`) and
  **MUDAB**'s stray `PK_default` sentinel (matrix unrecorded, 6 rows) → NULL.
  Mareano / Vannmiljø have no matrix. Shared helper `_shared/matrix_meta.R`
  (`matrix_canon` + `standardise_matrix()`).

## 2. Clean (removal + replicate aggregation)

Order: harmonise → **remove** flagged rows → **aggregate** replicates.

- **Remove** measurements carrying any of:
  - `range_flag` (outside plausible range)
  - `invalid_flag` (negative / over_range)
  - `below_loq = 1` OR `below_loq_num = 1` (below detection/quantification)
  - `weight_basis = 'wet'`
  - `src_flag IS NOT NULL` (all source-specific QC failures)
  - (grain-size `gs_corr = 'invalid'` is handled in the Annotate step)
- **Remove out-of-scope sites** — sites flagged `area_flag = 'outside_europe'` and
  their linked event/subsample/measurement rows (cascade); the `area_flag` column
  is then dropped (`consume_area_flag()`).
- **Duplicates** (`dup_flag = 'duplicate'`) — keep one row.
- **Technical replicates** (`dup_flag = 'technical_replicate'`) — collapse each
  group to one row: `value_std` = mean, `value_sd` = SD, `n_rep` = count.
- **Uncertainty** (`uncrt` / `metcu`, ICES; MUDAB `method.uncertainty`) —
  standardise to mg/kg (percent `metcu` → `uncrt/100 * value`; `SD`/`U2` →
  absolute, unit-converted) as `value_uncrt`, and propagate through replicate
  averaging. Exact combination rule is an OPEN ITEM (e.g. pooled SD vs mean uncrt).

## 3. Annotate (labelling)

- **Labels kept**: measurement class (`category`), supporting-data availability
  (`fe/al/org/comp_exist`), multi-layer (`multi_flag`).
- **Sediment fraction** (`_shared/fraction_meta.R`) — the ICES `matrix` gains
  `frac_class` (`bulk` / `sieved`) + `sieve_um` (fine cutoff µm; NULL for bulk) on
  each measurement (bulk = `SEDtot` or a `>= 1000 µm` cutoff; no matrix, i.e.
  Mareano/Vannmiljø, taken as bulk); `matrix` is kept as provenance. Because
  bulk/sieved varies between the measurements of one subsample (metals vs organic
  carbon, and even target-vs-target), it is authoritative per-row on `measurement`,
  and summarised onto `subsample` as `target_frac_class` `bulk`/`sieved`/**`mixed`**
  (+ `target_sieve_um`) from the **target** rows only — `mixed` where a subsample's
  targets span both (584 ICES, 88 MUDAB, 10 4Demon), NULL where it has no target
  chemistry. Summarising over targets only means the reference/organic rows sharing
  `measurement` do not affect it.
- **grain-size fines on `subsample`**: `fines_lt63` (% <63µm mud content) +
  `fines_basis`, kept from slim step 15 (no separate grain-size summary table).
- **grain_size_fraction** detail table (the genuine one-to-many, kept separate):
  the individual grain-size fractions moved out of `measurement` (corrected
  `value_pct`, parsed `lo_um`/`hi_um`; statistics and `invalid` rows excluded).
- **`comp_exist`** on `subsample` flags grain-size availability; grain-size
  composition no longer sits in `measurement`.

**Status:** built and verified for **all five sources**. Every
source now runs steps 01-03 (4Demon's 03 does the fraction annotation only — no
grain-size). Chemistry counts are unchanged by the annotation: `measurement` holds
all chemistry (e.g. ICES 69,719; MUDAB 30,744).

Per-source specifics settled during the rollout:

| source    | depth unit | sediment fraction | notes |
|-----------|------------|-------------------|-------|
| ICES-DOME | metres (×100) | from `matrix` (SED\* → bulk/sieved + sieve_um) | reference vocabulary |
| MUDAB     | cm (×1)    | from `matrix` (`PK_default` → NULL → bulk) | `time` dropped; no `src_flag` |
| Mareano   | cm (×1)    | all `bulk` (confirmed; no `matrix`) | named bins Clay/Silt/Sand/Gravel; `lld`->`lod`; TOC->CORG |
| Vannmiljø | cm (×1)    | all `bulk` (assumed; no `matrix`) | `date` from `datetime`; `dw`/`C` unit suffix stripped; 221 corrupt depths (>300 cm or inverted) nulled; own GSMF code vocabulary; `gs_corr='invalid'` fractions excluded |
| 4Demon    | cm (×1)    | from `matrix` (FS/US → sieved/bulk) | no grain-size / organic; no `lab`/`lod`/`loq`; ISO-free gear codes |

Cross-source portability handled in code: `col_or_false` removal predicate (absent
`src_flag`), `matrix` NA-guard, and `intersect(c("method","lab"))` grouping (absent
`lab` in Vannmiljø / 4Demon).

---

## 4. Geo-enrich — `seastamp` and its reference data

Clean step 4 (`clean_geo_enrich()`) and pilot step 4 (`pilot_geo_enrich()`) both
go through `seastamp_enrich()`, which shells out to the external
[seastamp](https://github.com/AIQC-Hub/seastamp) CLI. Neither the binary nor its
reference datasets ship with the package, so these are the two steps that can
fail for environmental rather than data reasons. Skip them with
`create_db("clean", src, steps = 1:3)` or `create_db("pilot", src, steps = c(1, 5))`.

The wrapper runs four seastamp commands as one chain and validates every path up
front, so all five datasets are needed even if only one column is wanted:

| Dataset | Command | Column(s) | Size | Path under `seastamp_dir` |
|---------|---------|-----------|-----:|----------------------|
| GSHHG (full res) | `coast` | `dist_to_coast` (km) | 217 MB | `gshhg/gshhg-shp-2.3.7/GSHHS_shp/f` |
| GEBCO sub-ice topo | `depth` | `depth` (positive-down; land → NULL) | 7.0 GB | `gebco/GEBCO_2024_sub_ice_topo.nc` |
| IHO Sea Areas v3 | `sea` | `sea_name` | 143 MB | `iho/World_Seas_IHO_v3/World_Seas_IHO_v3.shp` |
| Natural Earth 10m | `place` | `country`, `country_code` | 14 MB | `naturalearth/ne_10m_admin_0_countries.shp` |
| GISCO LAU 2021 | `place` | `municipality` (Europe only) | 273 MB | `gisco/LAU_RG_01M_2021_4326.shp` |

Fetch them with the tool's own `scripts/download_data.sh -d <seastamp_dir>`. IHO sits
behind the Marine Regions licence form, so it needs `--mr-name`, `--mr-org`,
`--mr-email` and `--mr-country`; running it accepts CC BY-NC-SA 4.0.

`seastamp_dir` defaults to `multised_seastamp_dir()` (`data/seastamp`, or the
`multised.seastamp_dir` option) and is an argument of `create_db()`.

**Finding the binary.** `seastamp_bin()` looks at `options(multised.seastamp_bin)`,
then `Sys.getenv("SEASTAMP_BIN")`, then the `PATH`. Prefer one of the first two in
RStudio: its console does not inherit the login shell's `PATH`, so a seastamp the
Terminal tab finds is often invisible to the console, and the run fails with
"seastamp not found" despite a working install.

**Pilot vs clean.** The pilot keeps five of the six columns (it drops `depth`),
and they are transient: clean step 4 recomputes all six from the site table, so
the clean values are the ones that survive. The stored **pilot** databases were
rebuilt with seastamp on 2026-08-07 and published to the five pilot sites, so
they now agree with a fresh build; before that they held values from the old
sf + rnaturalearth + giscoR implementation that `pilot_geo_enrich()` replaced.

**Region.** `region = "auto"` in code (seastamp's own default and the accurate
choice), and what the stored pilot databases now hold, but the stored clean and
merged databases still hold `"global"` values. `dist_to_coast` moves
on every row between the two (median 4.8-11.3% by source, largest shift 93 km),
`municipality` for 1,884 sites and `country` for 283; `depth` does not project
and is unchanged. Adopting `auto` therefore needs a deliberate refresh, and will
change the published multised-clean and multised-merged pages.

---

## Aquaculture (Norway reference) — `create_db("aquaculture")`

A standalone reference DB of Norwegian marine aquaculture sites, and a distance
column it adds to every clean `site` table. Norway-only for now (no international
aquaculture data yet).

- **`01_build_aquaculture.R`** — parses the two Fiskeridirektoratet ("Yggdrasil")
  exports under `data/raw/yggdrasil/` (`Lokaliteter.csv` active, `Slettete
  lokaliteter.csv` closed), and writes `data/db/aquaculture_no.sqlite` (table
  `aquaculture`, one row per site, `aqua_id` PK). Both files' `x,y` are ETRS89 /
  UTM 33N (**EPSG:25833**) — the active file also carries lat/lon, which validates
  the CRS (round-trip residual 56 m = its 3-dp rounding), so lat/lon is derived from
  `x,y` for both files uniformly. Norwegian descriptors + species are translated to
  English (proper names kept; common commercial species via a fixed dictionary, rare
  ones pass through). Kept water types: salt (`SALTVANN`/`SALT`), brackish
  (`BRAKKVANN`), mixed (`FERSKVANN/SALTVANN`); pure freshwater dropped. Columns:
  `loknr`, `name`, `latitude`, `longitude`, `start_year`, `end_year`, `active`
  (1/0), `water_type`, `capacity` + `capacity_unit` (cleared/permitted, the field in
  both files), `capacity_tonnes` (mass units only: TN as-is, KG/1000; else NULL),
  `fish_types`, `placement` (sea/land), `county`, `municipality`. Result: 3,743 sites
  (1,554 active, 2,189 closed).
- **`02_site_distance.R`** — adds `dist_to_aquaculture` (km, great-circle, `sf`) to
  each clean `site`, the nearest farm over **all** aquaculture rows (active or
  closed). Computed only for `country_code = 'NOR'` sites (from the geo-enrich step);
  others NULL. Idempotent (resets + recomputes).

---

## Open items (still provisional, easily changed)

- **bulk/sieved threshold** = `< 1000 µm` cutoff is sieved (so `<2mm`/`<1mm` are
  bulk); the middle cutoffs (`SED500`/`SED90`) are rare. Mareano/Vannmiljø no-matrix
  → bulk (assumed; Vannmiljø whole-sample treatment, Mareano confirmed grabs).
- Vannmiljø **depth-null threshold** (`> 300 cm` or inverted -> NA, 221 rows).
- **Uncertainty**: only ICES-DOME populates `value_uncrt` (per-measurement
  `uncrt`/`metcu`); MUDAB `method.uncertainty` and any cross-replicate propagation
  rule beyond mean-of-1sigma are not yet used.
- `sampling_tool` / `method` are carried as-is; a proper **ICES mapping** is
  best-effort and not built (Vannmiljø tool is ISO standards, unmapped).
- Whether `comp_exist` stays on `subsample` or is inferred from a
  `grain_size_fraction` row existing for the subsample.
- Next generation (per [plan.md](plan.md)): the single clean-results website, then
  the cross-source **merge**.
