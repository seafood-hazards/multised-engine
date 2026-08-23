# The EF background is source-biased in the bulk fraction

Result of ordering step 3 of [refined-review-response.md](refined-review-response.md),
which was the reviewer's item 6 ("cross-source Al comparability unexamined"). It was
scoped as a read-only diagnostic. It found a real defect in the published enrichment
factors, and it changes what decision D1 should be, so it gets its own note.

Produced by `analysis_refined_background_ef()` (sections 6 and 7), which now writes
`refined_ef_source.csv` and `refined_ef_region.csv` alongside its existing four outputs.
Those four are byte-identical to the published ones: no verdict moved in this step.

## The short version

The EF background reference is one median of `metal/Al` over all sources pooled. In the
**bulk** fraction that pool is 54-99% Mareano, and **Mareano's aluminium is measured on a
different basis from everyone else's**: about 1.6% Al where the other sources report
5-6%. So the bulk reference is roughly 2-3x too high for every non-Mareano sample, and
those samples are handed an EF that is 2-3x too low, which is to say **too pristine**.

The **sieved** fractions are unaffected: Mareano contributes nothing to them, and the
remaining sources agree with each other to within about 15%.

## 1. Each source against the pooled reference

From `refined_ef_source.csv`, bulk, reliable groups. `bg_rel` is the source's own offshore
`metal/Al` median divided by the pooled reference. `% adequate` is the share with EF < 1
under the pooled reference; `own` is the same rows judged against that source's own
offshore reference.

| Element | Source    | share of reference | bg_rel | % adequate (pooled) | % adequate (own) |
|---------|-----------|-------------------:|-------:|--------------------:|-----------------:|
| CO      | ICES-DOME | 11%                | 0.30   | **97**              | 35               |
| CO      | MUDAB     | 2%                 | 0.44   | **90**              | 41               |
| CO      | Mareano   | 87%                | 1.04   | 41                  | 48               |
| CU      | ICES-DOME | 40%                | 0.36   | **85**              | 43               |
| CU      | MUDAB     | 3%                 | 0.64   | 64                  | 37               |
| CU      | Mareano   | 57%                | 1.15   | **22**              | 45               |
| MN      | ICES-DOME | 33%                | 0.61   | 78                  | 44               |
| MN      | MUDAB     | 3%                 | 0.75   | 49                  | 37               |
| MN      | Mareano   | 64%                | 1.21   | 32                  | 48               |
| ZN      | ICES-DOME | 43%                | 0.49   | **80**              | 38               |
| ZN      | MUDAB     | 2%                 | 0.44   | 52                  | 26               |
| ZN      | Mareano   | 54%                | 1.10   | **20**              | 46               |

Read the last two columns. Under the pooled reference the same seabed is 97% adequate for
cobalt if ICES-DOME measured it and 41% if Mareano did. Under each source's own reference
every group lands between 35% and 48%, which is what a median reference has to give.
**The spread between sources is the artefact; the convergence is the arithmetic.**

The published headline of "roughly half adequate" is therefore an average of two badly
wrong halves, not a measurement of the seabed.

Molybdenum and selenium are absent from the table because their bulk reference is 94% and
99% Mareano respectively, so `bg_rel` is 1.00 by construction and there is no second source
to compare against. That is not reassurance: it means their bulk reference is entirely on
Mareano's measurement basis, and the handful of non-Mareano Mo and Se samples are misjudged
in the same direction as everything else here.

Sieved63 and sieved20 show none of this: every reliable group has `bg_rel` between 0.88
and 1.16, and the pooled and own-reference shares differ by a few points at most.

## 2. It is not geology

Sources sample different seas, so the spread could have been regional. `refined_ef_region.csv`
holds the sea area fixed. `spread_sea` is the max/min of the offshore `metal/Al` medians
across the sources sampling **one** sea area; `spread_all` is the same across all sources
pooled over every sea.

| Element | Fraction | Sea area      | sources | spread_sea | spread_all |
|---------|----------|---------------|--------:|-----------:|-----------:|
| CO      | bulk     | Norwegian Sea | 2       | 2.53       | 3.47       |
| CU      | bulk     | Barentsz Sea  | 2       | 2.65       | 3.16       |
| CU      | bulk     | Norwegian Sea | 2       | 1.85       | 3.16       |
| MN      | bulk     | Barentsz Sea  | 2       | 2.76       | 2.00       |
| ZN      | bulk     | Barentsz Sea  | 2       | 3.02       | 2.49       |
| ZN      | bulk     | Norwegian Sea | 2       | 2.67       | 2.49       |
| CU      | sieved63 | North Sea     | 2       | 1.17       | 1.21       |
| CU      | sieved20 | North Sea     | 2       | 1.06       | 1.09       |
| MN      | sieved20 | North Sea     | 2       | 1.02       | 1.03       |
| ZN      | sieved20 | North Sea     | 2       | 1.48       | 1.36       |

Holding the sea area constant does not shrink the bulk spread; for MN and ZN in the
Barents Sea it is larger within one sea than across all of them. Meanwhile the North Sea
sieved rows, where MUDAB, ICES-DOME and 4Demon sample the same water and Mareano is
absent, agree to within 2-17%, zinc in the 20 um fraction being the one looser case at
48%. **The spread tracks the source, not the region.**

## 3. What differs is the aluminium, not the metal

Offshore bulk, same two sea areas, Mareano against MUDAB:

| Sea area      | Source  | n    | Cu   | Zn   | Mn    | **Al**     | Fe     | Fe/Al |
|---------------|---------|-----:|-----:|-----:|------:|-----------:|-------:|------:|
| Norwegian Sea | Mareano | 2046 | 13.7 | 51.5 | 608   | **15,585** | 21,160 | 1.36  |
| Norwegian Sea | MUDAB   | 40   | 32.3 | 71.8 | 1,094 | **56,030** | 41,453 | 0.74  |
| Barentsz Sea  | Mareano | 827  | 15.5 | 68.7 | 255   | **19,151** | 26,750 | 1.40  |
| Barentsz Sea  | MUDAB   | 32   | 21.8 | 77.5 | 319   | **66,031** | 36,734 | 0.56  |

All values mg/kg. The trace metals differ by 1.4-2.4x, which is unremarkable between two
sampling programmes. Aluminium differs by **3.4-3.6x**, and iron by only 1.4-1.7x, so the
Fe/Al ratio itself is twice as high in Mareano. The normaliser is the outlier, not the
sediment.

Mareano's bulk Al runs 2,200 to **30,400** mg/kg. A ceiling of 3.0% Al is not physically
compatible with a total digestion of aluminosilicate marine sediment, where 6-8% is
ordinary; MUDAB's 8.2% and ICES-DOME's 11.6% maxima are. Iron behaving so differently from
aluminium is the classic signature of an **acid extraction**: iron oxides dissolve readily
in nitric acid or aqua regia, lattice-bound aluminosilicate aluminium does not.

The inference is therefore that Mareano reports **partial-extraction** aluminium while the
other sources report near-total aluminium. It is an inference, not a field we can read: the
refined `method` table carries no AL or FE rows at all, and where the clean databases do
carry them (`mareano_clean` has one, ICES-DOME 125) the `method` value is the instrument
(ICP-OES, ICP-MS, and in one ICES case XRF), never the digestion. The Mareano row does name
its lab, NGU-Laboratory.

## 4. What this changes

**D1 as written does not fix this.** D1 was to report the offshore P90 of `metal/Al`
beside the median. A second percentile of the same pool inherits the same 3x offset in
bulk, so it would move the threshold without making the comparison valid.

The bulk EF background has to be stratified or restricted before a second reference is
worth adding. Three options, in the order I would defend them:

1. **Restrict the bulk reference to one measurement basis** and mark samples on the other
   basis unclassifiable, exactly as samples without any Al are already marked. Honest, and
   consistent with the site's existing stance. Costs the most rows.
2. **Compute the bulk reference per source.** Cheapest, and it uses every row, but a
   per-source median reference forces every source to about half adequate by construction
   (column `own` above proves it), which destroys cross-source comparison of contamination
   level. It answers "is this sample enriched for its programme", not "is this sample
   enriched".
3. **Calibrate the offset** and rescale, which is the only option that keeps every row and
   a common scale. It needs a conversion factor between the two bases that we do not have
   and cannot derive from these data alone.

Whichever is chosen, the sieved fractions need no stratification and should keep the
pooled reference: splitting them would lose rows for no gain.

Two upstream gaps to close either way:

- Carry AL and FE rows into the refined `method` table. They exist in the clean databases
  and are dropped at `refine-01-restructure.R`.
- Establish whether any source reports a digestion or extraction step at all. If none
  does, source stays the only available proxy for measurement basis, and that limitation
  belongs on the page.

## 5. What is not affected

- **The sieved fractions.** MUDAB, ICES-DOME and 4Demon agree closely within the North Sea.
- **The grain-size-normalised page**, which reports `metal/Al` distributions rather than
  dividing by a pooled reference, though the same source spread is present in its numbers
  and should be noted there.
- **The near-cage enrichment finding.** It is computed within the aquaculture bands, which
  are overwhelmingly Vannmiljø and Mareano rather than a source mixture, so it does not
  ride on the cross-source reference. It stands.
- **The aluminium coverage finding** of step 2, which is about missing Al, not mismeasured
  Al.
