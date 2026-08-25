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

**Option 1 was chosen.** How it was implemented, and what it cost, is §6.

The claim above that the sieved fractions need no stratification turned out to be wrong,
and §6 corrects it: they looked consistent only because they are already mostly one basis,
and their strata differ by 1.7 to 3.0x just as bulk's do.

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


## 6. Implementing option 1

### Placing each sample

There is no digestion field, so the basis is inferred per sample from **Fe/Al**. Both
elements are lithogenic and both track grain size, so their ratio is close to grain-size
free, while an acid extraction depresses aluminium far more than iron. Crustal Fe/Al is
about 0.5; the cut is at **1.0**, and above it aluminium is under-recovered.

| Source    | n (bulk) | Fe/Al < 0.5 | 0.5-1.0 | >= 1.0 |
|-----------|---------:|------------:|--------:|-------:|
| ICES-DOME | 3,688    | 1,476       | 1,790   | 422    |
| Mareano   | 3,251    | 0           | 4       | 3,247  |
| Vannmiljø | 322      | 6           | 5       | 311    |
| MUDAB     | 251      | 21          | 196     | 34     |

Mareano is 99.9% above the cut and Vannmiljø 97%, so both Norwegian programmes are on the
extraction basis; MUDAB is 86% below it. The reason to trust the cut is ICES-DOME, which
straddles it: splitting that one source at Fe/Al = 1 separates its metal/Al by 1.7 to 2.5x.
A single source does not split itself that way by geography, so the cut is finding a
protocol.

The three strata are `extraction`, `total`, and `unplaced` where no iron was reported.

### One basis per fraction

A single global basis is not possible: bulk is 53% extraction while the sieved fractions
are 42-48% total. Each fraction therefore adopts the basis that carries its data, and
everything else is left unclassified.

| Fraction | Adopted    | n on it | % of fraction | offshore rows | rows < 1 km from a farm |
|----------|------------|--------:|--------------:|--------------:|------------------------:|
| bulk     | extraction | 16,329  | 53%           | 13,325        | **164**                 |
| sieved63 | total      | 5,468   | 48%           | 2,152         | 0                       |
| sieved20 | total      | 7,551   | 42%           | 5,944         | 0                       |

Bulk had to be the extraction basis: the total-basis stratum has **no** near-cage samples
at all (against 164), no selenium reference and five molybdenum rows. The cost of that
choice is that bulk aluminium is acid-leachable, so **bulk EF is internally comparable but
not comparable with literature EF values**. That belongs on the page, and it is in the meta
file.

Cross-fraction comparison was never valid anyway, since the fractions are never pooled.

### What it fixed

The source spread, before and after, bulk. `bg_rel` is the source's own offshore reference
over the adopted one; `% adequate` is under the adopted reference.

| Element | Source    | bg_rel before | bg_rel after | % adequate before | % adequate after |
|---------|-----------|--------------:|-------------:|------------------:|-----------------:|
| CO      | Mareano   | 1.04          | **1.00**     | 41                | 47               |
| CO      | ICES-DOME | 0.30          | 0.52         | 97                | 74               |
| CU      | Mareano   | 1.15          | **1.02**     | 22                | 42               |
| CU      | ICES-DOME | 0.37          | 0.48         | 84                | 82               |
| MN      | Mareano   | 1.21          | **1.01**     | 32                | 48               |
| MN      | ICES-DOME | 0.61          | 0.83         | 78                | 46               |
| ZN      | Mareano   | 1.10          | **1.00**     | 20                | 45               |
| ZN      | ICES-DOME | 0.49          | 0.81         | 80                | 56               |

The bulk EF medians move to 1.01-1.23 and the adequate shares to 39-48%, which is what a
median reference over one coherent population has to give. A residual gap remains on
ICES-DOME's extraction-basis subsets, which are 40 to 244 rows and pan-European against
Mareano's Norwegian shelf, so some of it is the regional difference the region check could
never rule out.

### What it cost

Bulk classifiable share, before and after: CO 84 to 62%, CU 24 to **11%**, MN 89 to 46%,
MO 66 to 55%, SE 98 to 97%, ZN 26 to **11%**. Copper and zinc lose most, because their
bulk rows are heavily ICES-DOME and MUDAB on the total basis.

Near-cage bulk classifiable rows fall from about 400 to **164**, since 234 of them are
Vannmiljø samples with no iron reported and so cannot be placed. Reporting iron alongside
aluminium would recover those, which strengthens the recommendation already made about
Vannmiljø's aluminium.

### The unexpected dividend

Restricting to one basis made the aquaculture bands homogeneous enough to run the distance
validation **within a single source**, which the review response had listed as necessary
and undone (item 10). It holds:

| Band    | Mareano n | Mareano % pristine | Vannmiljø n | Vannmiljø % pristine |
|---------|----------:|-------------------:|------------:|---------------------:|
| < 1 km  | 41        | 12                 | 101         | 16                   |
| 1-5 km  | 812       | 13                 | 458         | 18                   |
| 5-20 km | 559       | 27                 | 129         | 29                   |
| > 20 km | 11,537    | 49                 | (none)      |                      |

(As written by `refined_pristine_validation_source.csv`, which scopes rows the same way the
rest of the pristine synthesis does; the sharper figures quoted while this was still an
ad-hoc query did not apply the `value_std > 0` filter.)

Both programmes show the same monotone rise. **The distance gradient is not a source
artefact**, and the site's step 2 caveat that it could only be read as consistency can be
lifted. It is written out as `refined_pristine_validation_source.csv`.

## 7. Tested against the recorded digestion

The basis above is **inferred** from Fe/Al because, when it was written, no source recorded
its digestion. That is no longer true: `extraction_class` now carries each measurement's
digestion chemistry from the source through to the export (see
[efsa-submission.md](efsa-submission.md)). ICES-DOME and MUDAB record it, Mareano has one
known method, so the inference can be checked against a stated fact for the first time.

Method: one Al and one Fe per subsample and fraction (subsamples carrying more than one Al
method are dropped as ambiguous), restricted to rows where **Al and Fe share the same
digestion**, so the ratio is not comparing two different chemistries. 12,190 pairs, of
which 7,179 are ICES-DOME or MUDAB.

### Where the chemistry is unambiguous, the inference is right

| Source | Code | Class | n | median Fe/Al | % inferred "extraction" |
|---|---|---|---:|---:|---:|
| ICES-DOME | HF-CB | 1 | 2,987 | 0.626 | 16 |
| ICES-DOME | HF-OV | 1 | 1,456 | 0.562 | 6 |
| MUDAB | HF-CB | 1 | 1,090 | 0.764 | 22 |
| MUDAB | HF-C | 1 | 553 | 0.659 | 9 |
| ICES-DOME | HF-C | 1 | 253 | 0.534 | 6 |
| **Mareano** | **HNO** | **2** | **3,251** | **1.347** | **100** |
| MUDAB | HNO | 2 | 63 | 1.154 | 81 |

Every HF or aqua-regia digestion sits between 0.44 and 0.85, comfortably below the 1.0 cut,
and is read as "total". Mareano's 7 M HNO3 autoclave, a partial extraction that the source
states in prose, sits at 1.347 and is read as "extraction" for **3,247 of 3,251 samples**.
An independently known partial digestion agreeing with the inference on 99.9% of samples is
the strongest evidence the cut has had.

### One systematic disagreement

ICES-DOME's own `HNO` rows go the other way: median Fe/Al **0.619**, only 15% read as
"extraction", where Mareano's and MUDAB's nitric rows read 100% and 81%. Same nominal code,
opposite verdict.

Restricting to rows where Al and Fe share the digestion does not change it (85.1% "total"
either way), so it is not an artefact of mismatched chemistries. In bulk, ICES `HNO` median
Al is **15,708 mg/kg** against **29,800-35,130** for the ICES HF codes: about half, which is
what a partial digestion looks like. The ratio does not flag it because Fe is depressed in
those samples too (15,092 against 18,290).

**The cut detects Al under-recovery *relative to Fe*, not absolute digestion strength.**
Where a digestion depresses both roughly together, the ratio survives and the sample reads
"total". That is a real limitation, and it took the recorded code to expose it.

The caveat on the size of it: comparing medians across codes compares different samples from
different labs and areas, not one sample digested two ways, which does not exist in this
data. The effect is a strong hint, not a controlled measurement. It concerns 375 ICES Al
rows, 44 of them bulk.

### The two sources that record nothing behave oppositely

| Source | Code | n | median Fe/Al | % inferred "extraction" |
|---|---|---:|---:|---:|
| Vannmiljø | UNK | 320 | 1.636 | 97 |
| 4Demon | UNK | 814 | 0.634 | 1 |

Vannmiljø's unrecorded digestion behaves like a partial extraction, which is consistent with
standard Norwegian nitric practice and is evidence bearing on the class 3 default that
[the extraction-class README](../inst/extdata/extraction-class/README.md) applies to its
62,017 rows. 4Demon's behaves like a total one. **Defaulting both to class 3 was right not
to assume a single class for the unrecorded sources**, because they are not the same.

### What this changes

Nothing, for now. The inference stays the operative rule:

- it is corroborated wherever the chemistry is unambiguous, including one near-perfect case;
- the recorded class does not exist for 48.5% of measurements, so it cannot replace it;
- and where the two disagree, the disagreement is small (375 Al rows) and one-directional.

What the recorded class adds is a **check** the pipeline did not have, and one open lead:
whether ICES's nitric rows should be excluded from the "total" stratum. That is a change to
`refined_ef_basis()` and would move background values, so it is not made here.
