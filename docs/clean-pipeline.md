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
- **grain_size** (new, one row per subsample that has usable grain-size):
  `frac_class` (`sieved` / `bulk`), `fines_lt63` (%), `is_fine` (0/1),
  `fines_basis`, and the individual size fractions.

---

## 1. Harmonise (data conversion)

Value-preserving relabel/reshape; leans on slim's `value_std` / `unit_std` /
`category`.

- **Symbols → ICES canonical.** Targets (`CO CU I MN MO SE ZN`) and normalisers
  (`FE AL`) are identity after case-folding (`Fe`→`FE`). Organic carbon:
  `TOC → CORG`, `TOC63` kept as-is. A small per-source symbol map does this.
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
- **grain_size table** (per subsample, from slim `fines_lt63` / `fines_basis`,
  the `matrix` sample-fraction work, and the fraction codes):
  - `frac_class` = `sieved` / `bulk`; **drop the row if unknown**.
  - `fines_lt63` (%) numeric, plus `is_fine` (0/1) at a threshold (provisional
    `>= 50 %` mud; OPEN ITEM).
  - the individual grain-size fractions.
- **Drop `composition` rows from `measurement`**; `comp_exist` then means "has a
  `grain_size` row".

---

## Open items to resolve during the build

- Per-source **depth units** (confirm from pilot metadata) and the Vannmiljø
  out-of-range depth cleaning.
- `is_fine` **threshold** (provisional `>= 50 %`).
- **Replicate / uncertainty** aggregation maths (pooled SD, uncrt propagation).
- `sampling_tool` / `method` **ICES mapping tables** (best-effort; Vannmiljø tool
  largely `unknown`).
- Whether `comp_exist` stays on `subsample` or is inferred from `grain_size`.
