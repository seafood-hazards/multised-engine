# What each generation is missing

A gap audit across all five generations, written 2026-08-25 in the same spirit as
the pilot-site pass: find what the sources record and the pipeline throws away,
before deciding what to rebuild.

Scope was set by seven questions (§1-§7). Everything here is measured against the
databases in `data/db` as of this date, not estimated.

**Headline:** the pipeline can currently give a pristine verdict to **9.7%** of
target measurements, and to **0%** of the samples within 1 km of a fish farm,
which is the data EFSA asked for most explicitly. The single change that moves
that number is adding an index that does not need aluminium.

---

## 1. Extraction class: is our reading right?

Yes, with one judgement call worth naming.

[ReplyFHF_TypeDataForEFSA.md](ReplyFHF_TypeDataForEFSA.md) defines the field by
**digestion chemistry**, and our three-class mapping follows it. Two details of
the spec are easy to misread and we have them right:

- **HClO4 does not discriminate.** It appears in the examples for class 1
  (`HClO₄, HF, HNO₃`) *and* class 2 (`HClO₄, HNO₃`). The actual discriminator is
  the presence of **HF or aqua regia**, i.e. whether the silicate lattice is
  attacked. Our table keys on that.
- **Class 3 is two different things.** "No extraction" and "poorly reported" both
  land there. We keep them apart upstream as ICES `NON` and our own `UNK`, and
  only merge them at the EFSA boundary.

### The one ambiguity: Mareano

EFSA lists **"Ultra clave extraction with HNO₃ and water"** under **class 1**.
Mareano's method reads:

> `on samples from partial extraction by 7 M HNO3 in autoclave`

Both are nitric acid in a heated pressure vessel. We assign **class 2**, because
the source calls it a *partial* extraction, and class 2 is defined as "targeting
labile, exchangeable, or organically-bound metals" -- which is what a 7 M HNO3
autoclave leach does: it does not dissolve silicates, so it does not reach total
recovery whatever the vessel.

This is defensible but it is a judgement, and it governs **all 18,941 Mareano
target rows** -- the largest single call in the mapping. Actions:

1. Mark it `judgement = TRUE` in `extraction_class.csv` (it currently is not).
2. Carry the verbatim method string into the EFSA **Notes** field so EFSA can
   re-classify if they disagree.
3. Worth one question to the lab: is the UltraCLAVE instrument in use here? If
   the digestion is UltraCLAVE rather than a conventional autoclave, EFSA's own
   example puts it in class 1 and 18,941 rows move.

Everything else in `inst/extdata/extraction-class/` stands as written.

---

## 2. Accredited lab: two sources have it, not one

| Source | Field | Content | Usable |
|---|---|---|---|
| Mareano | `lld.comment` | `accredited` 640, `partly accredited` 161, `not accredited` 69, `not accredited method` 20, blank 35 | **yes**, clean three-state |
| MUDAB | `analysis_method.accreditation` | `y` 27, `true` 23, `ja` 20, `1` 5 / `n` 16, `false` 14; **237 of 342 blank** | **yes**, after normalising |
| ICES-DOME | -- | no accreditation field | no |
| Vannmiljø | -- | none | no |
| 4Demon | -- | none | no |

So MUDAB has it too, in three spellings of yes across two languages. Neither
source's field survives past slim.

Two things to decide rather than assume:

- **Mareano's `partly accredited` (161 rows) has no EFSA counterpart** -- the
  field is binary. Mapping it to "yes" is the natural reading (the lab holds
  accreditation, not every parameter is in scope) but it should be a stated
  choice, with the original string in Notes.
- **EFSA's definition is broader than formal accreditation.** It explicitly
  counts labs "following a quality control/quality assurance procedure,
  including reference samples". MUDAB carries `control_chart_type`,
  `proficiency_testing`, `reference_material_id` and `internal_qa_count` --
  which is direct evidence of exactly that, for rows where `accreditation` is
  blank. Those 237 blanks may be largely recoverable from the QA columns.

---

## 3. Turekian & Wedepohl: the check supports EFSA's warning

EFSA says using T&W (and Whitehead) as background "may be a distorted picture of
the real background concentrations in marine sediment". Measured against our own
offshore (>10 km) background, that is an understatement.

T&W deep-sea **clay** ÷ our bulk offshore median:

| Element | T&W clay | Our bulk p50 | Ratio | Effect on EF |
|---|---:|---:|---:|---|
| MN | 6,700 | 275.9 | **24.3x** | everything looks pristine |
| CU | 250 | 13.3 | **18.8x** | everything looks pristine |
| MO | 27 | 1.19 | **22.7x** | everything looks pristine |
| CO | 74 | 8.32 | **8.9x** | everything looks pristine |
| ZN | 165 | 57.3 | 2.9x | mild |
| SE | 0.17 | 1.30 | **0.13x** | everything looks polluted |
| I | 0.05 | 380.7 | **0.0001x** | everything looks polluted |

Both directions of distortion, in the same table. Using T&W clay would suppress
EF by up to 24x for the clay-borne metals and inflate it by four orders of
magnitude for iodine. This is quantitative support for EFSA's position and worth
reporting to them as such.

Three caveats on the extracted table itself:

- **These are the deep-sea columns.** The values EF papers normally cite from
  T&W are the **average shale** column (commonly given as Co 19, Cu 45, Zn 95,
  Mn 850, Mo 2.6, Al 8.0%, Fe 4.72%), which is much closer to shelf sediment.
  Worth extracting that column too before drawing the comparison publicly, so we
  are arguing against the reference people actually use.
- **Se and I are identical in both columns** (0.17 and 0.05). Identical values
  across two very different sediment types is a signature of a dash, a footnote
  or a single spanning cell in the original. Worth one look at the paper.
- **Whitehead et al. (1985) is not needed.** We adopt neither reference: our
  background is local and cut from the data. Not finding it blocks nothing.

**Decision: do not adopt T&W as background anywhere.** Use it only as a
comparison exhibit demonstrating why local background is required.

---

## 4. Sieved vs bulk: three separate problems

### 4a. A real bug in 4Demon (fix this)

`R/clean-shared-matrix-meta.R` maps 4Demon's matrix code `FS` to `SED63`
unconditionally. But `FS` is not the sieve field -- `fraction_range` is, and
`R/pilot-01-extract-4demon.R` documents it correctly ("0-63 = fine fraction
<63 um, 0-2000 = bulk sediment <2 mm"). `FS` spans four different fractions:

| matrix | fraction_range | target rows | currently labelled | should be |
|---|---|---:|---|---|
| FS | 0-63 | 2,578 | sieved <63µm | correct |
| FS | 0-2000 | **640** | sieved <63µm | **bulk** |
| FS | 0-37 | **222** | sieved <63µm | **sieved <37µm** |
| FS | 0-500 | **24** | sieved <63µm | **sieved <500µm** |
| US | 0-10000 | 64 | bulk | correct |

**886 of 3,528 4Demon target rows (25%) carry the wrong fraction**, and 640 of
them are bulk samples being reported as sieved. This propagates into merged and
refined, into `sieve_class`, and into the EFSA "Sieve <63 µm" field. Fix:
classify from `fraction_range`, keep `matrix` as provenance.

### 4b. Vannmiljø and Mareano: not "bulk", but "unknown"

Neither source has a matrix field. `classify_fraction()` maps absent to `bulk`,
so **53,754 Vannmiljø and 14,325 Mareano target measurements are positively
labelled bulk on no evidence**.

To the direct question -- could some Vannmiljø be sieved? -- the honest answer
is **the data we hold cannot tell us**. There is no sieving signal anywhere in
the Vannmiljø pilot: `sample.filtered` is a water-sample concept (45,851 zeros,
one 1), `analysis` holds ISO determination standards, and the `GSMF*` codes are
grain-size *measurements*, not preparation flags.

Two things follow, and they point in opposite directions:

- **For the EFSA export, our default is already correct.** The spec says of Bulk
  analysis: *"If not reported, there is also this option in the drop-down menu."*
  EFSA folds unreported into bulk deliberately. We are compliant today.
- **For our own science it is not.** Assumed-bulk and reported-bulk should not
  be indistinguishable in an EF or a background cut. Add a `frac_basis` column
  (`reported` / `assumed`) beside `frac_class`. Cheap, and it makes every
  downstream filter honest.

There is a route to upgrading the assumption rather than living with it: the
Norwegian programmes prescribe preparation at the standard level (NS 9410 for
aquaculture monitoring, M-608 for classification). If IMR or Miljødirektoratet
will state the practice, 25,789 MOMC rows move from assumed to reported without
touching a number.

### 4c. MUDAB: a consistency check worth running once

MUDAB has both `matrix` and `physical_treatment`, and they broadly agree
(`_SED20` with SED20, `_US` with SED2000). But 10,545 SED20 target rows list
`DFRZ` alone -- deep-frozen, with no sieving step recorded. Probably incomplete
reporting rather than contradiction. Low priority, but it is the largest single
sieved block in the database and deserves one look.

---

## 5. Is Al normalisation critical for sieved samples? No -- and that is the opening

Already answered by D4 ([normalisability](../inst/extdata/normalisability/README.md)),
and the answer is stronger than "no":

> The sieved fractions fail across the board because a sieved sample is
> **already** grain-size controlled: cut to below 63 or 20 um, most of the
> texture variation is gone before the chemistry starts, leaving aluminium
> little to track.

Every sieved group fails both tests, several with rho at or below zero. So Al
normalisation of sieved samples is not merely unnecessary -- fitting it is
fitting noise.

The consequence has not been drawn yet. **The reason EF fails on sieved samples
is the same reason raw sieved concentrations are already comparable.** Sieving
does the job EF was invented to do. Today D4 correctly withholds an EF verdict
for **29,802 sieved target measurements (26% of the database)**; that is right
for EF, and wrong as a final answer, because those are the rows least in need of
normalisation in the first place.

What they need is an index built on a background rather than a normaliser --
which is exactly §6.

---

## 6. Igeo and PLI: recommended, and they unlock the priority data

EFSA: *"The Geo-accumulation Index (Igeo) and the Pollution Load Index (PLI) can
be considered as well in absence of EF."*

Neither needs aluminium:

- **Igeo** = `log2(C / (1.5 * B))`, per measurement. The 1.5 absorbs lithological
  variability. Bands are conventional (<0 unpolluted, 0-1 unpolluted to
  moderate, ... >5 extreme).
- **PLI** = `(CF_1 * ... * CF_n)^(1/n)` where `CF = C / B`, per **site** across
  elements. PLI > 1 indicates deterioration.

### Why this is the highest-value change on the list

Current pristine coverage, from `refined_pristine_coverage.csv`:

| Distance to aquaculture | measurements | classifiable |
|---|---:|---:|
| <1 km | 25,071 | **0%** |
| 1-5 km | 16,216 | 6% |
| 5-20 km | 11,357 | 5% |
| >20 km | 10,281 | 84% |

The pipeline can say nothing about any sample near a fish farm. The cause is
measured and blunt: for Vannmiljø's aquaculture-monitoring programme, **Al is
present on 5 of 13,996 subsamples (0.04%)**. Meanwhile TOC is present on
**12,557 (90%)**.

EFSA explicitly asked for aquaculture data -- *"Samples taken during / for
Environmental / Ecological Impact Assessment for marine aquaculture facilities
... monitoring data of sediment quality over time under the sea cages"*. It is
the one request we currently answer with silence, and the fix is an index that
does not need the element we do not have.

### Design constraints

- **Background must stay local.** EFSA: *"The best index ... would be the
  calculation of EF based on local background concentrations."* Use our own
  offshore percentiles, never T&W (§3). Which percentile becomes B is a
  decision: the median of the offshore reference is the conventional choice; the
  p90 is what EFSA themselves extract for background. Pick one and state it.
- **Igeo first, PLI second.** Igeo is per-measurement and needs one element;
  PLI is per-site and multiplies across elements, so with only CO/CU/ZN reliably
  covered it is thin, and it silently mixes elements of different
  normalisability. Report PLI at site level with an explicit element list, or
  not at all.
- **Do not let Igeo quietly re-open the withheld elements.** Se and Mo verdicts
  are withheld for LOQ-censoring reasons ([loq-censoring](../inst/extdata/loq-censoring/README.md))
  that Igeo does not fix. The withholding is orthogonal and must survive.
- **TOC normalisation is the third option** where Al is absent and the sample is
  bulk: 90% coverage in exactly the programmes that lack Al. Worth evaluating on
  the same footing as Igeo, using the D4 method (does TOC predict the metal?).

---

## 7. Aquaculture: labelling farms by size

The reference DB already harmonises more than expected: `capacity`,
`capacity_unit` and a derived `capacity_tonnes`. 3,743 sites, 1,554 active,
2,668 with tonnes.

The units problem largely dissolves once the population is defined properly:

| Group | tonnes/kg | decare | count | m3 | m2 |
|---|---:|---:|---:|---:|---:|
| finfish | **2,508** | 3 | 63 | 62 | 1 |
| other (mussel, oyster, scallop, urchin, lobster) | 160 | 902 | 19 | 6 | 18 |

`decare` is area, and it is almost entirely shellfish and kelp. `count` and `m3`
on finfish sites are hatchery/smolt units -- number of fish and tank volume --
and `placement` confirms it: of finfish sites, **2,355 are sea + salt + tonnes**,
while nearly all the `count` and `m3` sites are `land`.

So the recipe is a filter, not a unit conversion:

1. Keep `placement IN ('sea','offshore')` and finfish species.
2. Keep `capacity_unit IN ('tonnes','kg')` -- this retains ~97% of that
   population. Land-based and tank-volume sites are excluded on their own merits:
   they do not deposit on the seabed at that coordinate.

### The size bands write themselves

The capacity distribution lands on the Norwegian concession ladder:

| MTB (t) | sites | multiple of 780 |
|---:|---:|---|
| 780 | 415 | 1x |
| 1,560 | 337 | 2x |
| 3,120 | 315 | 4x |
| 2,340 | 264 | 3x |
| 4,680 | 86 | 6x |
| 3,900 | 59 | 5x |
| 5,460 | 55 | 7x |
| 6,240 | 40 | 8x |

Over sea-sited salmon and trout farms (n = 1,857): median 2,340 t, p25 1,560,
p75 3,600, p90 5,460, max 19,000.

**Label farms in standard concessions (MTB / 780), not in raw tonnes.** It is
the unit the licences are actually issued in, it makes the bands interpretable
to a Norwegian regulator, and it collapses the long tail sensibly. A three-band
cut (1-2 / 3-4 / 5+ concessions) splits the population roughly into thirds.

Carry `capacity_tonnes`, the band, and `fish_types` onto `site` next to the
existing `dist_to_aquaculture` / `aqua_id`, so pressure can be modelled as
size-weighted distance rather than distance alone. A 780 t farm and a 19,000 t
farm at the same distance are not the same pressure.

---

## 8. Also found: Vannmiljø states the pressure and we ignore it

Vannmiljø's `activity` table is a programme classification, and it maps almost
one-to-one onto EFSA's own pristine / non-pristine lists. It already survives
into refined as `dataset_code` / `dataset_name`. `dataset_group` is empty.

| Code | Programme | Target measurements | EFSA reading |
|---|---|---:|---|
| MOMC | Miljøovervåking akvakulturanlegg | **25,789** | aquaculture EIA -- explicitly requested |
| FOSJ | Overvåking av forurenset sjøbunn | **13,881** | contaminated seabed -- non-pristine by definition |
| TILT | Tiltaksorientert overvåking | 3,030 | pressure-driven |
| INDU | Påvirkning fra industri | 2,582 | industrial -- non-pristine |
| PROB | Problemkartlegging | 1,655 | pressure-driven |
| EMUD | Mudring, utfylling og dumping | 419 | dredging/dumping -- non-pristine |
| KOMM | Påvirkning fra avløp | 365 | sewage -- non-pristine |
| MARE | MAREANO | 267 | offshore mapping |
| BAPO | Basisovervåking - påvirka områder | 198 | impacted baseline |
| BARE | Basisovervåking - referanseforhold | 64 | **reference conditions** |

`BARE` is literally a reference-condition programme, though at 64 measurements
it is a validation set rather than a data source. `KAVE` (92), `DEPO` (72),
`MIUR` (40), `JRBN` (40) and `FLYP` (25) name road, landfill, urban-fjord,
railway and airport pressures respectively -- small, but unambiguous positives
for a pressure axis that currently has none.

This is **stated evidence of pressure**, independent of the geometric proxies
(`dist_to_coast`, `dist_to_aquaculture`) and of the chemical one (EF). It should
populate `dataset_group` as a pressure class, and it gives the pristine work a
third, independent axis to validate against -- which is worth more than the
coverage, because right now EF is validated only against distance.

---

## 9. Gap table by generation

| Gen | Missing / wrong | Severity |
|---|---|---|
| **pilot** | Nothing new. It holds every field discussed here. Porewater pH is absent from all five raw sources and no rebuild recovers it. | -- |
| **slim** | Drops extraction (fixed on `feature/efsa-extraction-class`); drops Mareano `lld.comment` and MUDAB `accreditation`; passes 4Demon `fraction_range` through but nothing consumes it; keeps Vannmiljø `activity` as a code with no meaning attached. | high |
| **clean** | `matrix_canon` FS->SED63 mislabels 886 4Demon rows (§4a); `classify_fraction` records no provenance for absent matrix (§4b); `METHOD_COLS` has no accreditation column. | high |
| **merged** | Inherits all of the above. Dedup keys do not include extraction or fraction, so a rebuild that changes either can change dedup outcomes -- check row counts, as with the MUDAB double-report. | medium |
| **refined** | No Igeo, no PLI, no TOC-normalisation option; verdicts exist only via EF, so 26% sieved + all near-farm rows are unclassified; `dataset_group` unused; no farm size on `site`. | high |
| **export / EFSA** | `accLab` unfilled (recoverable for 2 sources); extraction class pending the branch merge; the "Sieve <63 µm" field inherits §4a's error. | medium |

---

## 10. Sequencing

Everything above needs a rebuild, and the rebuild is already gated on the
seastamp `region = "auto"` vs `"global"` decision. **Do not rebuild five times.**

1. **Decide the seastamp region question.** It gates clean onward and nothing
   else can land until it is settled.
2. **Batch the source-fidelity fixes into one branch**, since they all touch
   slim/clean and all change the same tables: extraction class (already built),
   4Demon fraction (§4a), `frac_basis` provenance (§4b), accreditation carry-through
   (§2), Vannmiljø pressure class (§8), farm size on `site` (§7).
3. **One rebuild**, pilot -> refined, with row-count verification at each
   boundary. §4a and §2 change method identity, which is exactly the class of
   change that silently altered MUDAB's row count last time.
4. **Then the refined analyses**: Igeo, then TOC-normalisation evaluation, then
   PLI if the element coverage justifies it (§6).
5. **Then re-cut the exports and the four generation sites**, and re-release.

Steps 1-3 are one unit of work. Step 4 is where the coverage number moves.
