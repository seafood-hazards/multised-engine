# Clean pipeline — plan & spec (draft)

The third generation. Each source's `<source>_slim.sqlite` is turned into a
`<source>_clean.sqlite` by applying the slim flags and harmonising to a uniform
format. Still **one DB per source**; merging into a single cross-source DB is a
later generation (see [plan.md](plan.md)). A single website summarises the clean
results (replacing the per-source pilot sites).

Built by a new `R/clean/<source>/` script tree, run in order, reading the slim DB.
Three ordered steps (rename freely; the parenthesised names are the originals):

1. **Harmonise** (data conversion) — uniform names, units, depths, tools.
2. **Clean** (data cleaning) — remove flagged rows, collapse replicates.
3. **Annotate** (labelling) — carry labels; split grain-size to its own table.

Decisions locked so far: organic carbon `TOC → CORG`, `TOC63` kept separate;
Clean removes **all** `src_flag` rows; grain-size becomes a **separate table** and
is dropped from `measurement`; the `<63 µm` label is kept as **both** numeric
`fines_lt63` and a boolean `is_fine`.

---

## Target clean schema

Seven tables carried over (`element`, `dataset`, `site`, `event`, `subsample`,
`measurement`, `method`) plus a new **`grain_size`**. Key changes vs slim:

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
  (`R/clean/_shared/dataset_meta.R`) supplies `url` + `accessed`.
- **site** — a common column set: `site_id`, `latitude`, `longitude`, `depth`,
  `country`, `country_code`, `dist_to_coast`, `municipality`, `sea_name`,
  `area_flag`. `depth` is the station / water depth (m; distinct from the sediment
  core depth in `subsample.depth_from`/`depth_to`) and is present for every source
  (Mareano native; the others populated by the upstream geocoding / bathymetry
  tools). `site_id` and the coordinates are stable; the other attributes are
  regenerated upstream. `standardise_site()` (`R/clean/_shared/site_meta.R`)
  guarantees the column set and order.
- **measurement** — chemistry only (`target` / `reference` / `organic`); no
  `composition` rows. Columns: `symbol` (ICES), `value` + `unit` (original value,
  ICES-named unit), `value_std` + `unit_std` (mg/kg), and for collapsed technical
  replicates `value_sd` + `n_rep`; measurement uncertainty `value_uncrt` (mg/kg,
  from ICES `uncrt`/`metcu` and MUDAB `method.uncertainty`). The slim marking
  columns are consumed by Clean and not carried forward (except where a label is
  wanted). `method_id` retained.
- **method** — `symbol`, `method` (ICES code), `lab`, `lod`, `loq`, and their
  unit. Mareano keeps its single `lld` as `lod`; 4Demon has none (null).
- **event** — `date` (derived from `datetime` where needed), `year`,
  `sampling_tool` (ICES), `site_id`, `dataset_id`. `datetime` / `time` dropped.
- **subsample** — `depth_from` / `depth_to` in **cm**; supporting-data flags
  (`fe_exist`, `al_exist`, `org_exist`, `comp_exist`).
- **grain_size** (new, one row per subsample with usable grain-size, summary):
  `frac_class` (`sieved` / `bulk`; `unknown` dropped), `fines_lt63` (%),
  `is_fine` (0/1 at a threshold), `fines_basis`.
- **grain_size_fraction** (new, one row per grain-size mass-fraction measurement,
  detail): `symbol`, `matrix`, size bounds `lo_um`/`hi_um`, `value_pct` (the
  corrected %); grain-size statistics (GSMEA/GSMED/...) and `gs_corr='invalid'`
  rows excluded. The multi-valued fractions are normalised out of the per-subsample
  summary rather than crammed into one table.

---

## 1. Harmonise (data conversion)

Value-preserving relabel/reshape; leans on slim's `value_std` / `unit_std` /
`category`.

- **Symbols → ICES canonical.** Targets (`CO CU I MN MO SE ZN`) and normalisers
  (`FE AL`) are identity after case-folding (`Fe`→`FE`). Organic carbon:
  `TOC → CORG`, `TOC63` kept as-is. A small per-source symbol map does this.
- **Element names + CAS.** The `element` name column becomes `name`; each chemistry
  symbol gets one canonical Title-Case name and CAS number from a shared lookup
  (`R/clean/_shared/element_meta.R`), so all sources read identical values. CAS is
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

## 2. Clean (removal + replicate aggregation)

Order: harmonise → **remove** flagged rows → **aggregate** replicates.

- **Remove** measurements carrying any of:
  - `range_flag` (outside plausible range)
  - `invalid_flag` (negative / over_range)
  - `below_loq = 1` OR `below_loq_num = 1` (below detection/quantification)
  - `weight_basis = 'wet'`
  - `src_flag IS NOT NULL` (all source-specific QC failures)
  - (grain-size `gs_corr = 'invalid'` is handled in the grain_size table build)
- **Duplicates** (`dup_flag = 'duplicate'`) — keep one row.
- **Technical replicates** (`dup_flag = 'technical_replicate'`) — collapse each
  group to one row: `value_std` = mean, `value_sd` = SD, `n_rep` = count.
- **Uncertainty** (`uncrt` / `metcu`, ICES; MUDAB `method.uncertainty`) —
  standardise to mg/kg (percent `metcu` → `uncrt/100 * value`; `SD`/`U2` →
  absolute, unit-converted) as `value_uncrt`, and propagate through replicate
  averaging. Exact combination rule is an OPEN ITEM (e.g. pooled SD vs mean uncrt).

## 3. Annotate (labelling)

- **Labels kept**: measurement class (`category`, now only target/reference/
  organic since grain-size moved out), supporting-data availability
  (`fe/al/org/comp_exist`), multi-layer (`multi_flag`).
- **grain_size** summary table (per subsample, from slim `fines_lt63` /
  `fines_basis` and the `matrix` sample-fraction work):
  - `frac_class` = `sieved` / `bulk` (bulk = whole `SEDtot` or a `>= 1000 µm`
    coarse sieve); **drop the row if unknown**.
  - `fines_lt63` (%) numeric, plus `is_fine` (0/1) at a threshold (provisional
    `>= 50 %` mud).
- **grain_size_fraction** detail table: the individual grain-size fractions moved
  out of `measurement` (corrected `value_pct`, parsed `lo_um`/`hi_um`; statistics
  and `invalid` rows excluded), restricted to the subsamples the summary kept.
- **Drop `composition` rows from `measurement`**; `comp_exist` then means "has a
  `grain_size` row". Fines columns move off `subsample` into `grain_size`.

**Status:** built and verified for **all five sources** (`R/clean/<source>/`).
ICES-DOME / MUDAB / Mareano / Vannmiljø run steps 01-03; 4Demon runs 01-02 (no
grain-size). `is_fine` threshold = 50 % everywhere.

Per-source specifics settled during the rollout:

| source    | depth unit | grain-size sieved/bulk | notes |
|-----------|------------|------------------------|-------|
| ICES-DOME | metres (×100) | from `matrix` | reference vocabulary |
| MUDAB     | cm (×1)    | from `matrix` (`PK_default` -> unknown, dropped) | `time` dropped; no `src_flag` |
| Mareano   | cm (×1)    | all `bulk` (confirmed) | named bins Clay/Silt/Sand/Gravel; `lld`->`lod`; TOC->CORG |
| Vannmiljø | cm (×1)    | all `bulk` (assumed; no `matrix`) | `date` from `datetime`; `dw`/`C` unit suffix stripped; 221 corrupt depths (>300 cm or inverted) nulled; own GSMF code vocabulary; `gs_corr='invalid'` fractions excluded |
| 4Demon    | cm (×1)    | none | no grain-size / organic; no `lab`/`lod`/`loq`; ISO-free gear codes |

Cross-source portability handled in code: `col_or_false` removal predicate (absent
`src_flag`), `matrix` NA-guard, and `intersect(c("method","lab"))` grouping (absent
`lab` in Vannmiljø / 4Demon).

---

## Open items (still provisional, easily changed)

- `is_fine` **threshold** = `50 %` mud, provisional (one constant per Step-3 script).
- Vannmiljø **bulk assumption** (no `matrix`, so grain-size taken as whole-sample)
  and its **depth-null threshold** (`> 300 cm` or inverted -> NA, 221 rows).
- **Uncertainty**: only ICES-DOME populates `value_uncrt` (per-measurement
  `uncrt`/`metcu`); MUDAB `method.uncertainty` and any cross-replicate propagation
  rule beyond mean-of-1sigma are not yet used.
- `sampling_tool` / `method` are carried as-is; a proper **ICES mapping** is
  best-effort and not built (Vannmiljø tool is ISO standards, unmapped).
- Whether `comp_exist` stays on `subsample` or is inferred from `grain_size`.
- Next generation (per [plan.md](plan.md)): the single clean-results website, then
  the cross-source **merge**.
