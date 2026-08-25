# Extraction class: the frozen code table

`extraction_class.csv` maps a canonical extraction code to EFSA's **Extraction
class**, one of the optional fields EFSA recommends for the trace-element
submission. Read it through `R/extraction-class.R`, never directly.

Full context, coverage figures and the propagation plan:
[docs/efsa-submission.md](../../../docs/efsa-submission.md).

## What the field is

The **digestion chemistry**, not the sampling method: how aggressively the metal
was liberated from the sediment before it reached the instrument.
[docs/ReplyFHF_TypeDataForEFSA.md](../../../docs/ReplyFHF_TypeDataForEFSA.md)
defines three classes:

| Class | Label | Chemistry |
|---|---|---|
| 1 | strong | Aqua regia or strong acid digestion (HF, HNO3, HCl, HClO4 combinations), aimed at total recovery |
| 2 | milder | HNO3 alone or with H2O2, targeting labile, exchangeable or organically-bound metal |
| 3 | weak-none | No extraction, or poorly reported / undisclosed |

It is the **recorded** counterpart of the aluminium measurement basis that
`R/analysis-refined-shared-basis.R` infers from Fe/Al with a cut at 1.0. ICES-DOME
and MUDAB carry both, so the inference can be tested against a stated fact.

## The vocabulary

Canonical vocabulary is **ICES METCX**, which MUDAB already uses verbatim in
`chemical_treatment`. That is the same arrangement `clean-shared-method-meta.R`
relies on for method codes.

One code is ours: **`UNK`, "not reported"**. It is deliberately distinct from the
ICES code `NON`, "None". `NON` is a positive statement that no extraction was
performed; `UNK` is an absence of information. Both land in EFSA class 3, which
covers each of them, but conflating them at the source would throw the
difference away.

34 codes: the 33 that occur anywhere in ICES-DOME or MUDAB, plus `UNK`.

## Source mapping

| Source | Native field | Mapping |
|---|---|---|
| ICES-DOME | `analysis_method.metcx` | identity, blank to `UNK` |
| MUDAB | `analysis_method.chemical_treatment` | identity, blank to `UNK` |
| Mareano | `parameter.method2` | contains "HNO3" to `HNO`; one method covers every target element |
| 4Demon | `method.method_code` | exactly "HNO3" to `HNO`, else `UNK` |
| Vannmiljø | (none) | always `UNK` |

**Vannmiljø is mapped to `UNK`, not to class 2.** Its `analysis` field holds ISO
*determination* standards (`NS-EN ISO 17294-2` is ICP-MS), which say nothing
about digestion, and 27,243 of 62,017 target rows are literally "Unknown".
Norwegian practice would usually put these at class 2, but that is an assumption
about an unrecorded step, and adopting it would manufacture 62,017 rows of false
precision. If IMR can state the digestion standard behind those submissions,
raising them is a one-line change here.

## The six judgement calls

Marked `judgement = TRUE` in the table. EFSA's class definitions are written
around acids and do not reach every code in the ICES list.

| Code(s) | Class | Why |
|---|---|---|
| `LMF-A`, `LMF-A-L`, `ALK` | 1 | Lithium metaborate and alkaline fusion achieve total recovery but are not acid digestions, so EFSA's wording does not reach them. Total recovery is what the class is for. |
| `HNO-CM~LMF-A-L` | 1 | Composite. The fusion component reaches total recovery, so the stronger part governs. |
| `HCL` | 3 | Hydrochloric acid alone appears in no EFSA list. Neither a total digestion nor the HNO3 chemistry that defines class 2. |
| `HSA` | 3 | H2SO4 appears in class 1 only inside strong mixtures (`SAD`). Alone it is a partial leach. |
| `SCE` | 3 | Selective chemical extraction is partial by design. |

## Organic solvents

Eight codes (`ACE`, `ACH`, `ACD`, `ACPE`, `MHX`, `PEN`, `SOX`, `SAP`) are organic
preparations for organic contaminants. On a trace-element row they are almost
certainly mis-tagged. They carry `organic_solvent = TRUE` so the pipeline can
flag them rather than trust them, and land in class 3 meanwhile. They affect
**86 ICES target rows (0.15%)** and none in MUDAB.

## Why it is frozen

Same reason as [normalisability](../normalisability/README.md) and
[loq-censoring](../loq-censoring/README.md): it encodes judgement, so it must not
move silently under a rebuild. `check_extraction_codes()` closes the drift risk
by warning when a source emits a code the table does not know. An unrecognised
code returns `NA` from `extraction_efsa_class()` rather than being quietly binned
into class 3, because an unmapped code means the source vocabulary has changed,
which is a thing to fix rather than to average over.

## Measured result

Target elements only (CO, CU, I, MN, MO, SE, ZN), weighted by measurements:

| Source | Rows | 1 strong | 2 milder | 3 weak-none |
|---|---|---|---|---|
| ICES-DOME | 58,164 | 79.1% | 19.3% | 1.6% |
| MUDAB | 26,049 | 71.4% | 26.4% | 2.2% |
| Mareano | 18,941 | 0% | 100% | 0% |
| Vannmiljø | 62,017 | 0% | 0% | 100% |
| 4Demon | 3,528 | 0% | ~0% | ~100% |

## Regenerating

The table is hand-maintained, not cut from the data. To check it still covers
the sources:

```r
source("R/extraction-class.R")
# every observed code must be present, and every mapping must return a class
check_extraction_codes(extraction_canon(x, "ICES-DOME"), "ICES-DOME")
```

Adding a code means adding a row here, with `judgement` and `note` filled in if
the class is not obvious from EFSA's definitions.
