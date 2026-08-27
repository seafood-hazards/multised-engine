# EFSA submission: recovering the optional fields

Plan for adding the EFSA-recommended optional fields that the pipeline does not
currently carry. Scope was set by three decisions taken 2026-08-24 (§7).

The headline: **extraction class is recoverable for just over half the target
measurements, and porewater pH is recoverable for none of them.**

## 1. The two EFSA artefacts

There are two, and they do not ask for the same things.

| Artefact | What it is | Where |
|---|---|---|
| ReplyFHF spec | EFSA's data-extraction spec for the systematic review. Defines **Extraction class** and **pH of porewater**. | [ReplyFHF_TypeDataForEFSA.md](ReplyFHF_TypeDataForEFSA.md) |
| Reporting tool | The submission workbook itself, 12 of 500 rows filled with IMR fjord data. Has **phSed** / **phWater**, and **no extraction field at all**. | `data/raw/Mareano/EFSA form-reporting-tool-trace-elements-IMR.xlsx` |

We target the **union** of the two, so whichever channel EFSA wants is served
without a second pass.

## 2. What Extraction class is

Not a sampling method: it is the **digestion chemistry**, how aggressively the
metal was liberated from the sediment before it reached the instrument. EFSA
defines three classes:

| Class | EFSA label | Chemistry |
|---|---|---|
| 1 | Strong | Aqua regia or strong acid digestion (HF, HNO3, HCl, HClO4 combinations), aimed at total recovery |
| 2 | Milder | HNO3 alone or with H2O2, targeting labile / exchangeable / organically-bound metal |
| 3 | Weak or none | No extraction, or poorly reported / undisclosed |

This is the *recorded* counterpart of the aluminium measurement basis that
`R/analysis-refined-shared-basis.R` currently **infers** from Fe/Al with a cut at
1.0 (see [ef-source-bias.md](ef-source-bias.md)). Carrying the recorded value
through lets us test that inference against a stated fact, which is why phase 3
below exists.

## 3. Where it lives, and where it dies

It is present in the pilot databases and is **dropped at slim step 1**.
`R/slim-01-transform-ices-dome.R:125` builds the method table from
`distinct(param, metoa, lod, loq, labo)`. `metoa` is the *determination* method
(ICP-MS, AAS); `metcx`, the extraction, is never selected. MUDAB does the same
with `measurement_method_code` in place of `chemical_treatment`. So slim, clean,
merged and refined all carry `method.method = "ICP-OES"` and the extraction is
lost at the pilot boundary.

Coverage over the 7 target elements, weighted by measurements, not by method rows:

| Source | Pilot field | Target rows | Classifiable |
|---|---|---|---|
| ICES-DOME | `analysis_method.metcx` | 58,164 | **100%** (79.1% strong, 19.3% milder, 1.6% weak-none) |
| MUDAB | `analysis_method.chemical_treatment` | 26,049 | **100%** (71.4% strong, 26.4% milder, 2.2% none) |
| Mareano | `parameter.method2` | all | **100%**, uniform "partial extraction by 7 M HNO3 in autoclave" |
| Vannmiljø | `analysis_method.analysis` | 62,017 | **none**, see below |
| 4Demon | `method.method_code` | 3,528 | **none**, 2 rows excepted |

MUDAB uses the ICES METCX vocabulary verbatim, so one mapping serves both. That
is the same arrangement `R/clean-shared-method-meta.R` already relies on for
method codes ("MUDAB already uses it").

**Vannmiljø is the gap, and it is the largest source.** Its `analysis` field
holds ISO *determination* standards (`NS-EN ISO 17294-2` = ICP-MS,
`NS-EN ISO 11885` = ICP-OES), which say nothing about digestion, and 27,243 of
62,017 target rows (44%) are literally "Unknown". Norwegian practice would
usually put these at class 2, but that is an assumption about an unrecorded
step, so they default to class 3 unless IMR can supply the lab SOP. Raising them
later is a one-line change to the frozen table.

**4Demon** encodes programme, instrument and sieve (`Monit3_OES/MS_63`), not
chemistry. Only Cu and Zn of the 7 targets are present at all.

### A contradiction the field exposes

Making the extraction part of method identity surfaced something the pipeline had
been hiding. **MUDAB reports six target measurements twice**, once under `HF-CB`
(a total digestion) and once under `HNO` (a partial one), with identical values.
A total and a partial digestion cannot both yield the same number, and nothing in
the source says which applies.

Before, the two rows collapsed because `chemical_treatment` was not part of the
method key, so the measurement appeared once and the disagreement was invisible.
Once extraction joins the key they take different `method_id`s, survive the
`distinct()` that mints the measurement table, and the measurement is counted
twice.

`extraction_unambiguous()` withholds rather than guessing: where a measurement's
rows disagree about the digestion, all of them become `UNK`. That restores the
row count and matches how the project treats every other untrustworthy
reference. The same guard runs on ICES-DOME, where it is a no-op today, so a
later pilot refresh cannot reintroduce the duplication unnoticed.

### Expected result in the refined database

`measurement.method_id` is populated for **100%** of all 115,811 target
measurements in every source, so extraction attaches wherever it is recorded:

| Outcome | Rows | Share |
|---|---|---|
| From a source that records the digestion (ICES-DOME + MUDAB + Mareano) | 59,666 | **51.5%** |
| Class 3 by default (Vannmiljø + 4Demon) | 56,145 | 48.5% |

Two figures get quoted and they measure different things. **51.5%** is the share of
rows *from a source that records the digestion*. **51.3%** (59,372 rows) is the share
whose code is not `UNK`, which is the same set minus the 294 rows where a recording
source left the field blank or where `extraction_unambiguous()` withheld it. The site
quotes the second, because "recorded" there means a usable code.

## 4. The mapping

Frozen under `inst/extdata/extraction-class/`, following the pattern already used
by `normalisability/` and `loq-censoring/`, and read through a shared helper so
the pipeline and any analysis cannot drift apart.

| Class | ICES / MUDAB codes |
|---|---|
| 1 strong | `AQR`, `HF-C`, `HF-CB`, `HF-CM`, `HF-OV`, `HNO-HF-HCL`, `HNO-HF-PER`, `SAD`, `TOT`, `HF-CB~HF-CM`, `HNO-CM~LMF-A-L`, and (judgement) `LMF-A`, `LMF-A-L`, `ALK` |
| 2 milder | `HNO`, `HNO-CM`, `HNO-CM150`, `HNO-OV`, `HPX` |
| 3 weak / none | `NON`, empty, `HAC`, `PHO`, and (judgement) `HCL`, `HSA`, `SCE`, plus the organic solvents `ACE` `ACH` `ACD` `ACPE` `MHX` `PEN` `SOX` `SAP` |

Six codes are judgement calls and are marked as such in the frozen table, with
the reasoning recorded rather than buried:

- `LMF-A`, `LMF-A-L`, `ALK` (lithium metaborate and alkaline fusion) achieve
  total recovery but are not acid digestions, so EFSA's wording does not reach
  them. Assigned **1**, because the recovery is what the class is for.
- `HCL` and `HSA` (hydrochloric, sulfuric acid alone) are not in any EFSA list.
  Assigned **3**, since neither is a total digestion and neither is the HNO3
  chemistry that defines class 2.
- `SCE` (selective chemical extraction) is partial by design. Assigned **3**.

The organic solvent codes on a metal row are almost certainly mis-tagged: 86
ICES target rows (0.15%) carry them, and none in MUDAB. They are marked
`organic_solvent = TRUE` so the pipeline can flag them, and land in class 3
meanwhile rather than being silently binned. (A further 107 ICES rows carry
`HAC` or `SCE`, which are genuine weak leaches rather than mis-tags.)

Mareano's single method reads "partial extraction by 7 M HNO3 in autoclave".
"Partial" and "HNO3" both point the same way: **class 2**, for every target
element, from one constant.

## 5. pH: dropped

Checked at both pilot and raw level in all five sources. There is no porewater
pH anywhere, and rebuilding cannot produce any, because it was never in the
exports:

- The only pH in the project is **22 ICES rows**, and they are `matrix = SED63`,
  sediment below 63 µm. That is sediment pH, not porewater.
- `data/raw/Vannmiljo/Vannmilio_pH_Carbon_Sulfur_all.xlsx`, despite its name,
  contains **no pH**: 42,149 rows of TOC / TOC63 / S / TC / TIC, every one of
  them medium "Sediment saltvann".
- MUDAB's codelist defines medium `P = Porenwasser` and parameter `PH`, but the
  export contains no PH rows, only PHENOL.
- Mareano and 4Demon have none.

**Decision: dropped.** No effort is spent on it. The `phSed` / `phWater` columns
still appear in the superset output (§6) so the reporting tool's schema is
matched, but they stay empty. Recovering porewater pH would mean fresh Vannmiljø
and MUDAB downloads filtered on a different medium, which is a separate piece of
work and is not in this plan.

## 6. The superset output

One table covering the union of both artefacts. Nearly everything is already in
the refined database or derivable from it:

| Group | Fields | Status |
|---|---|---|
| Identity | sampleId, recId, RefId | from refined keys |
| Location | sampleLocGC, sampleLocCM, envComp, place | site lat/lon, municipality, country, sea_name |
| Time | sampleDate | `event.year` / date |
| Measurand | traceEl, spec, conc, unit, weight, converted mg/kg dw | `measurement.value_std` / `unit_std` |
| Method | methAn, **extraction class**, LOD, LOQ, accLab | `method`, extraction **new**, accreditation partial |
| Sediment | Sieve <63µm, Bulk analysis, fracBasis, ocSed / TOC%, texture clay/silt/sand | `frac_class`, `sieve_um_std`, `frac_basis`, organic, grain size |
| Verdict | pristineLoc, igeo, igeo_class | `pristine_ef` and Igeo from the background module |
| Pressure | dist_to_fish_farm_km, fish_farm_band, pressure_class | site distances, Vannmiljø programme |
| Admin | publicData, refPublication, comments, confidentiality | constants / notes |
| **Empty** | phSed, phWater, hardWater, DOC, SD | not available, see §5 |

Three of those groups were filled in after the source-fidelity rebuild of
2026-08-25 and are worth calling out, because each answers something the spec
asks for that the table previously could not.

**`fracBasis`** says whether "Sieve <63µm = N, Bulk analysis = Y" was read off the
source or inferred from its silence. Around three fifths of the bulk rows are the
latter. Both answers were already being given; only the difference between them
was missing, and a submitter should be able to see it.

**`pressure_class`** is the provider's own statement of why the sample was taken.
The spec asks by name for *"monitoring data of sediment quality over time ... under
the sea cages"*, and 25,789 Vannmiljø measurements are filed under exactly that
programme. Until now nothing in the submission table said so; the reader had to
infer it from a distance. `dist_to_fish_farm_km` and `fish_farm_band` are the
geometric half of the same question, and narrow `dist_to_aquaculture_km` from
"any marine aquaculture site" to the finfish farms the spec is about.

**`igeo`** is reported beside `pristineLoc`, not instead of it. `pristineLoc`
carries a verdict on 9.7% of rows, because it needs aluminium on the right basis
in a group where aluminium predicts the metal; Igeo needs no aluminium and covers
97.2%. It is deliberately not a verdict: in bulk it is confounded with grain size
strongly enough (cobalt ρ 0.70) that a verdict built on it would be partly a
verdict about texture. See [generation-gaps.md](generation-gaps.md) §6.

### One correction the re-cut made

`sieve63` was `Y` for **any** sieved fraction. That is right for the <20µm rows,
which the spec explicitly counts as <63µm, and wrong for the 31 rows sieved at 90
or 500µm: those are coarser than 63µm, so answering `Y` told EFSA the sample was
finer than it was. They are now `N` to both `sieve63` and `bulkAnalysis`, which is
the honest pair of answers for a sample that was sieved but not below 63µm, with
the actual cutoff in `fraction`.

`pristineLoc` is the one field where our answer is stronger than EFSA's ask: the
ReplyFHF spec explicitly prefers a local-background EF and warns against
Turekian and Wedepohl values, which is what the refined pipeline already
computes. It is an enrichment factor, so it exists for CO, CU and ZN in bulk only
(see [normalisability](../inst/extdata/normalisability/README.md)).

## 7. Decisions taken

| # | Question | Decision |
|---|---|---|
| D1 | Porewater pH | **Dropped entirely.** Absent from every export; columns present but empty. |
| D2 | How far to carry extraction | **Full pipeline propagation**, slim through export. |
| D3 | Which EFSA artefact | **Both, as a superset.** |

(These three are local to this doc. The project-wide D1 and D4 are different
decisions: LOQ censoring and normalisability.)

### What actually gets submitted

**A representative subset, cut later. Not the whole export.** EFSA wants
representative records, not the corpus, so the submission will be a filtered
selection of **pristine** rows, chosen when the submission itself is prepared.

This is why `export_data("refined", format = "efsa")` is not a submission file and
is not carried on any release. Its job is to be the *pool* that selection is made
from, which is why it is a superset and why every row keeps its verdict columns.
Anyone reading the 115,811-row TSV as "the submission" has it backwards.

## 8. Phases

Status: phases 1-4 done. Phase 5 (docs and site) outstanding.

**Phase 1, freeze the mapping. Done.** `inst/extdata/extraction-class/` holding the
code table and a README recording the judgement calls of §4, plus
`R/analysis-refined-shared-extraction.R` to read it. No pipeline change yet.

**Phase 2, propagate. Done.** Adds `extraction` (canonical code) and
`extraction_class` (1/2/3) to the method table and carries them down. Merge and
refine needed no change: both move the method table generically, so the columns
ride the existing path.

| File | Change |
|---|---|
| `R/slim-01-transform-ices-dome.R` | add `metcx` to the `distinct()` and the select |
| `R/slim-01-transform-mudab.R` | add `chemical_treatment` |
| `R/slim-01-transform-mareano.R` | add `method2` |
| `R/slim-01-transform-vannmiljo.R` | constant "not reported" |
| `R/slim-01-transform-4demon.R` | parse `method_code`, constant otherwise |
| `R/slim-02-schema-*.R` (5) | two new columns on `method` |
| `R/clean-shared-method-meta.R` | extend `METHOD_COLS`, map source codes to the frozen vocabulary |
| `R/merge-03-finalise.R` | passes columns through generically, expected to need nothing |
| `R/refine-01-restructure.R` | `dbReadTable` + filter, expected to need nothing |
| `R/export-refined-dataset.R` | two new columns plus dictionary rows |

Then rebuild all five generations and re-run `analyze_data("refined")`.

**Phase 3, validate the Al basis. Done.** The inference is corroborated wherever
the chemistry is unambiguous, and Mareano's stated 7 M HNO3 partial extraction
agrees with it on 3,247 of 3,251 samples. It is kept as the operative rule.
The check also found its blind spot: the cut measures Al under-recovery
*relative to Fe*, so a digestion that depresses both together still reads
"total". Full numbers, the one disagreement (375 ICES-DOME nitric rows) and the
new evidence on Vannmiljø's unrecorded digestion are in
[ef-source-bias.md](ef-source-bias.md) section 7. No change to
`refined_ef_basis()` is made here.

**Phase 4, the superset export. Done.** `export_data("refined", format = "efsa")`
writes `multised_efsa_submission.tsv.gz` and its dictionary: 58 columns, of which
the first 42 reproduce the workbook's `dataReported` sheet in its own order so the
block can be pasted straight in. Both exports are cut from `refined_export_base()`,
one pull with the verdicts already joined, so they cannot disagree. Term codes are
frozen in the export rather than read from the workbook at run time.

**Phase 5, docs and site.** `CLAUDE.md` docs map, `slim-pipeline.md` step 1
column map, `refined-pipeline.md`, and a page on multised-refined.

## 9. Open, not in scope

- **Accreditation.** MUDAB's `analysis_method.accreditation` is in the very table
  phase 2 already opens, and covers 12,204 of 26,049 target rows (46.9%) with a
  yes/no, though the vocabulary is messy (`true` / `ja` / `y` / `1` / `false` /
  `n`). It fills EFSA's `accLab`. Cheap to add while we are there, but it is a
  widening of scope and is not started without a decision.
- **Vannmiljø extraction.** Recoverable only if IMR can state the digestion
  standard behind the Vannmiljø submissions. Would move 62,017 rows off the
  class 3 default.
- **Porewater pH re-download.** See §5.
