# Response to the refined-generation review

Working response to
[multised-refined-summary-pages-and-review.md](multised-refined-summary-pages-and-review.md)
(external reviewer, August 2026, read of the published multised-refined site).

**Status: ordering steps 1-4 are done and shipped (multised-refined v0.7.6, v0.7.7, v0.8.0
and v0.9.0). Steps 5-7 remain.** Every claim below was re-checked against
`data/db/multised_refined.sqlite` and `data/analysis/background/`; where the
review and the data disagree, the data is quoted.

The reviewer saw the refined site only, with no knowledge of the earlier
generations. Several items are therefore about things settled upstream (outlier
flagging at merge step 4, LOQ handling at slim step 8); those are marked
**upstream** and answered with the rule that actually applies.

---

## 1. Decisions taken

| # | Decision | Consequence |
|---|----------|-------------|
| D1 | **EF gets a second reference.** Keep the offshore median as the headline, add the offshore P90 of metal/Al alongside it, and report both everywhere. **Superseded in part by step 3**, which showed the bulk reference is pooled over incompatible aluminium measurements, so a second percentile of the same pool inherits the same error. The bulk reference must be stratified or restricted first; see [ef-source-bias.md](ef-source-bias.md) §4 for the three options. The P90 reference is still wanted, computed within whatever stratification is chosen. | Touches `analysis_refined_background_ef()`, `analysis_refined_pristine()`, `export_refined_dataset()`, three site pages, the dataset download. New release. |
| D2 | **Fe is a reference only, never an enrichment normaliser.** Norwegian fish feed contains iron, so Fe near a farm is partly the pressure being measured. It stays in the grain-size comparison with an explicit callout. | Site text only. `background-gsnorm.qmd` gains a callout; no CSV or figure changes. |
| D3 | **The two summary pages wait** for D1 to land, so they are not written against numbers that are about to move. | Deferred, spec in §5. |

D2 is a standing project rule, not a one-off: it is recorded in `CLAUDE.md`
because the temptation to add "and metal/Fe" to an enrichment calculation will
recur.

---

## 2. Disposition of the eleven items

| # | Item | Disposition |
|---|------|-------------|
| 1 | EF threshold at war with its median denominator | **Adopted** as D1 (report both references) |
| 2 | Strict rule contradicts the page's own principle | **Adopted, presentation** — relabel, do not re-specify |
| 3 | The three criteria are not independent | **Adopted, wording** — "corroboration", not "independent confirmation" |
| 4 | Percentiles of a convenience sample; pseudo-replication | **Adopted in part** — per-site sensitivity, headline stays per-measurement |
| 5 | Outlier removal circular with the background | **Downgraded** — upstream rule, 0.36% of rows; state it, no change |
| 6 | Cross-source Al comparability unexamined | **Adopted, escalated** — the largest real problem found; see §3 |
| 7 | Ratio normalisation weaker than regression | **Deferred** — genuine, but a new method, not a fix |
| 8 | Claimed cutoff insensitivity contradicted by its table | **Adopted** — the text is wrong; correct it |
| 9 | Mixture technicalities (k fixed at 2) | **Adopted in part** — report BIC for k = 1,2,3 |
| 10 | Confounded validation, both directions | **Adopted, re-diagnosed** — the cause is not distance; see §3 |
| 11 | Non-detects, per-site map averaging, null guard | **Split** — LOQ is upstream; the null guard is a real bug |

### Item 1: the median denominator (adopted, D1)

The reviewer is right and the arithmetic is visible in our own output.
`refined_ef_meta.csv` records the reference as `offshore >10 km median of
metal/Al`, and `refined_ef_dist.csv` shows `ef_p50` sitting at 0.87-1.38 across
every reliable group, with `pct_lt1` between 36 and 64. Half the reference
population fails EF < 1 because it is the median of that population.

We are not choosing between the median and the P90, because that choice is
exactly what is in dispute. Both get computed and reported, and the spread
between them becomes the answer the summary page gives.

Implementation, in `analysis_refined_background_ef()`:

- `refined_ef_background.csv` gains `bg_ratio_al_p90` beside `bg_ratio_al`.
- `refined_ef_dist.csv` gains `ef_p50_p90ref`, `pct_lt1_p90ref` beside the
  existing median-referenced columns.
- `refined_ef_meta.csv` records both references and states which is headline.
- `analysis_refined_pristine()` gains `pct_ef_p90ref` alongside `pct_ef`.
- `export_refined_dataset()` gains `ef_p90ref` and `pristine_ef_p90ref`; the
  existing nine verdict columns keep their current definition so the published
  v0.7.5 dataset stays a strict subset of the next one.

The headline stays the median reference with EF < 1, because that is the EFSA
convention the pages cite. What changes is that a reader can see, per element
and fraction, how much of the "roughly half is enriched" picture is arithmetic.

### Item 2: the strict rule (adopted as presentation)

The contradiction is real. `refined_pristine_meta.csv` records the strict rule as
`EF<1 AND below mixture threshold AND below offshore P90`, and two of those three
are raw-concentration criteria on a page that rejected a raw-concentration
fallback for validating backwards.

The rule itself is not wrong, though: ANDing raw screens onto EF < 1 cannot make
a sample falsely pristine, only falsely non-pristine. It is conservative in the
direction a conservative rule should be conservative. What is wrong is
presenting the three as peers.

So: relabel, do not re-specify. The strict rule becomes "EF < 1 plus two raw
screens", with one sentence saying muddy-but-clean samples can fail the screens
on grain size alone. Cobalt's 56% → 20% drop gets named as an example rather
than left to look like evidence of cobalt enrichment.

### Item 3: not independent (adopted as wording)

Correct, and cheap to fix. The offshore subset is a large share of the global
sample, so the mixture threshold and the offshore P90 are two statistics of
overlapping data. "Corroboration" replaces "independent confirmation" on the
mixture page and in the summary spec.

### Item 4: convenience sample and pseudo-replication (adopted in part)

Two claims, and they need separating.

The convenience-sample point is right and unfixable: five monitoring programmes
with regulation-driven sampling do not give percentiles of the seabed. It goes
in the caveat box, phrased as the reviewer put it.

The pseudo-replication point is right about the mechanism and unverified about
the size. `site.repeat_group` and `site.n_years` exist and the percentile tables
are computed per measurement, so re-sampled sites are over-weighted. The
reviewer's inference that these are "typically the monitored, i.e. pressured
ones" is plausible and untested.

Disposition: compute the offshore P90 per site-aggregate as a **sensitivity
column** next to the per-measurement one, and let the size of the difference
decide whether the headline weighting should change. Do not switch the headline
blind. The reviewer is also right that the maps average per site while the tables
do not, and that this is nowhere stated; say it.

### Item 5: circular outlier removal (downgraded, with evidence)

Sound in principle, immaterial here, and the reviewer could not have known
because the rule lives upstream in `merge-04-mark-outliers.R`, not on any refined
page.

The flag requires **both** criteria: robust z on log10 above 4 MADs **and** at
least one full order of magnitude from the group median. It is a registration-
error catcher, not a tail trimmer. In the refined database it marks 414 of
115,820 rows: 366 high, 48 low, **0.36%**.

A filter that removes a third of a percent, and only values 10× off the median,
cannot meaningfully condition the P90 or the mixture's enriched component. The
concern is real for aggressive outlier rules and does not apply to this one.

Action: state the criterion and the 0.36% on the background pages, so the next
reader does not have to ask. No change to the rule.

### Item 6: cross-source Al comparability (adopted, escalated, now measured)

**Resolved as a diagnostic in step 3. Full write-up in
[ef-source-bias.md](ef-source-bias.md); the summary below is what the review response
originally said, and it understated the problem.**

What step 3 established, beyond the estimate below: the spread is not geology (it does not
shrink when the sea area is held fixed), it is confined to the **bulk** fraction, and it is
in the aluminium rather than the metal. Mareano's bulk Al runs about 1.6% against 5-6% for
the other sources, with iron barely differing, which is the signature of a partial acid
extraction rather than a total digestion. Under the pooled reference the same seabed comes
out 97% adequate for cobalt if ICES-DOME measured it and 41% if Mareano did; under
per-source references every group lands at 35-48%. The sieved fractions are clean.



**This is the most serious item in the review, and it is worse than the review
suggests.** The reviewer flagged it as a theoretical risk from digestion
chemistry. It is measurable in our data now.

Mean metal/Al, offshore bulk (>10 km), outliers dropped, groups of 30 or more:

| Element | Mareano | ICES-DOME | MUDAB | Mareano / ICES |
|---------|---------|-----------|-------|----------------|
| CO | 5.15e-4 | 1.68e-4 | 2.24e-4 | **3.1×** |
| CU | 8.42e-4 | 4.25e-4 | 5.58e-4 | **2.0×** |
| MN | 3.10e-2 | 1.10e-2 | 1.64e-2 | **2.8×** |
| ZN | 3.45e-3 | 2.47e-3 | 2.07e-3 | **1.4×** |

The EF denominator is a median over this mixture, and the mixture is not even:
Mareano contributes 2,887 of the 3,337 offshore CO bulk rows behind
`bg_ratio_al`. So the reference is close to "the Mareano value", and an
ICES-DOME cobalt sample is divided by a denominator drawn from a population
whose metal/Al runs 3× higher. That pushes non-Mareano samples toward EF < 1,
which is to say **toward falsely pristine**.

One honest caveat: source is confounded with region here. Mareano is the
Norwegian shelf and Barents Sea; ICES-DOME is pan-European. Part of a 3× spread
could be genuine geology. That is precisely why it has to be measured rather
than assumed either way.

Action, before the EF backgrounds are presented as trustworthy:

1. Add a source-stratified EF table (`refined_ef_source.csv`): metal/Al
   distribution and EF class shares per source, per element and fraction.
2. Test region against source on the overlap, where two sources sample the same
   sea area, to see whether the spread survives geography.
3. If it survives, either compute the EF background per source or restrict it to
   one source and state the restriction.

Until 1-3 are done, cross-source EF comparisons carry a warning. Note the `method`
table holds no AL or FE rows at all, so digestion cannot currently be read from
the database; that is a gap to close upstream, not something to infer.

### Item 7: ratio versus regression normalisation (deferred)

Legitimate and well-founded: ratio normalisation assumes proportionality through
the origin, sediment geochemistry generally has a non-zero intercept, and the
consequence is over-correcting sandy samples. A regression normalisation, with
the background as a residual band, is the stronger standard.

But this is a different method, not a correction to this one, and it would
replace the EF framework the EFSA submission pages are built on. It belongs in a
scoped piece of work with its own validation, after D1 and item 6 are settled.

The sub-point about Al-normalising *within* sieved fractions double-controlling
grain size is separable and cheaper; it plausibly explains Mo sieved metal/Al
sitting far below bulk (2.55e-5 sieved63 against 6.71e-5 bulk). Worth a note on
the EF page now.

### Item 8: the cutoff sensitivity claim (adopted, the text is wrong)

The reviewer read the table correctly and the page's text does not survive it.
From `refined_background_compare.csv`, bulk P90 at 10 / 20 / 50 km:

| Element | >10 km | >20 km | >50 km | Change |
|---------|--------|--------|--------|--------|
| CU | 34 | 23 | 22.4 | **−34%** |
| ZN | 130 | 86.8 | 77.4 | **−40%** |
| MO | 2.91 | 2.6 | 2.6 | −11% |
| CO | 11.9 | 11.8 | 12.1 | +2% |

Calling a 34-40% move in the headline background "small for the strong signals"
is not defensible. Cobalt and manganese are insensitive; copper and zinc, the two
elements the site says show the clearest coastal signal, are the two that move
most, which is the opposite of the claim.

Action: rewrite the sensitivity paragraph on `background.qmd` to say 10 km is
evidently not far enough out for Cu and Zn, and carry the >20 km column into the
summary table so the reader sees the range rather than a point. This interacts
with D1: the EF background also uses the >10 km subset, so every Cu and Zn EF is
anchored to the least clean of the three cutoffs. Worth a sensitivity row there
too.

### Item 9: mixture technicalities (adopted in part)

`refined_mixture_meta.csv` confirms k is fixed: `2-component Gaussian mixture
(EM) on log10(value_std)`, never tested against k = 1 or 3.

The cobalt diagnosis is sharp and worth taking seriously: a threshold of 6.45
sitting almost on the background geometric mean of 6.22, with only 31% assigned
to "background", is a minority background component, which inverts the method's
own premise that enrichment is the minority.

Action: report BIC for k = 1, 2, 3 per element and fraction in
`refined_mixture_components.csv`, and where k = 1 wins, mark the threshold
**not usable** rather than printing it. Anything marked not usable drops out of
the strict rule for that element, which is a real change to `pristine_strict`
and needs to land with D1, not separately.

Per-region fitting is deferred with item 7.

### Item 10: confounded validation (adopted, and re-diagnosed)

The reviewer identified the right problem and the wrong cause. This is worth
correcting carefully, because the site's headline conclusion depends on it.

The site reports that Al coverage collapses toward the cages, and reads it as a
property of near-cage sampling. Al coverage by distance band and by source:

| Band | n | classifiable | % | Vannmiljø share of band | Vannmiljø % Al | Mareano % Al |
|------|---|--------------|---|-------------------------|----------------|--------------|
| <1 km | 25,446 | 403 | **1.6%** | 99.8% | 1.4% | 100% |
| 1-5 km | 16,916 | 1,597 | 9.4% | 93.4% | 3.7% | 99.9% |
| 5-20 km | 12,135 | 961 | 7.9% | 92.8% | 1.5% | 100% |
| >20 km | 14,924 | 13,387 | **89.7%** | 8.3% | 3.1% | 99.6% |

Read the last two columns across the rows. **Within Vannmiljø, Al coverage is
1.4-3.7% at every distance including beyond 20 km. Within Mareano it is
99.6-100% at every distance including under 1 km.** Coverage does not vary with
distance to a farm at all. What varies is which programme sampled there: the
<1 km band is 99.8% Vannmiljø, the >20 km band is 84.6% Mareano.

So the finding is not "near-cage sediment cannot be assessed". It is
**"Vannmiljø does not report aluminium, and Vannmiljø is the programme that
samples around the farms."** Same number, different cause, and a much more
actionable recommendation: the ask goes to one named data provider about one
named parameter, instead of a general plea about aquaculture sites.

It also makes the reviewer's confounding point stronger than they put it. The
pristine validation compares classifiable samples across distance bands, but at
<1 km those are 354 Vannmiljø and 49 Mareano rows, while at >20 km they are
12,581 Mareano and 38 Vannmiljø. The distance trend is a source trend wearing a
distance label. Any validation of pristine against distance must be run
**within source** or it is not a test.

**Resolved by step 4's basis restriction.** Once each fraction is restricted to one
aluminium basis, the aquaculture bands are homogeneous enough to run the test within a
single source, and it holds: Mareano goes 12 / 13 / 27 / 49% pristine across the four
bands and Vannmiljo 16 / 18 / 29% across the three it spans. Both rise monotonically, so
the gradient is not a source artefact after all. Written out as
`refined_pristine_validation_source.csv`; the site caveat added in step 2 can be lifted
when that ships.

The reviewer's two further points stand and are adopted as limitations: Norwegian
farms sit in sheltered, organic-rich, periodically anoxic fjords, so part of the
≈13× Mo near-cage ratio may be fjord redox geochemistry co-located with farms
rather than farm input, and a matched-fjord comparison would separate them.
Temporal alignment is likewise unstated and the aquaculture table includes closed
sites, so distance-to-farm is not necessarily the pressure the sediment
experienced. Both go in the limitations note; neither is a quick fix.

### Item 11: smaller reporting issues (split three ways)

**Non-detects. The paragraph that stood here was wrong**, and the correction is
worse than the original claim. It said the censoring flag existed one generation
up and only needed carrying into refined. It does not exist one generation up:
`clean-02-clean.R` **removes** below-LOQ rows outright, as a documented rule
alongside the range and validity failures, so merged and refined never had them.

That rule is right for contamination screening and wrong for background
estimation, because a background is the low end of the distribution and
non-detects are evidence about exactly that end. Measured from the slim
databases, which still carry the flags: **SE 68.6%** and **MO 52.2%** of
measurements removed, then nothing else above 4.3%. For Mareano, which supplies
94-99% of the bulk Mo and Se reference, 86% of Mo and 70% of Se went, so the
published "90th-percentile background" sat at about the **98th percentile** of
the real distribution.

Resolved by **withholding** Se and Mo background and pristine verdicts, on the
principle already adopted for the aluminium basis: where the reference is not
trustworthy, issue none. Their concentrations are still published. The gate is a
measured share against a 20% limit, frozen in `inst/extdata/loq-censoring/`. It
does not touch the near-cage Mo and Se enrichment, which removing low offshore
values suppresses rather than inflates.

**Per-site map averaging (adopted as wording).** Correct. The maps average across
years and depths, so the strict-rule map applies thresholds to averages and is a
different classifier from the per-measurement one. The pages say tables are
authoritative; they do not say the map classifier differs. Say it.

**The null guard (real bug, fix it).** `enrichment-map.qmd` compares `avg_value`
without the null guard the sibling criteria use. Harmless while `avg_value` is
never null, and it should not be left to stay harmless by luck.

---

## 3. What the verification added

Two findings that came out of checking the review rather than from the review
itself, both material:

1. **The EF denominator is source-biased by a factor of up to 3** (item 6). It
   affects every EF and therefore every pristine verdict, including the ones now
   shipped in the dataset download.
2. **The aluminium coverage gap is a Vannmiljø reporting gap, not a near-cage
   effect** (item 10). This reframes the project's own headline conclusion and
   makes the recommendation concrete.

Neither changes the two findings the reviewer identified as robust, and item 1
does not either: the near-cage enrichment of Mo, Se, Cu and Zn survives
grain-size control, and near-cage sediment is largely unassessable. Both hold.

---

## 4. Ordering

Items 1, 9 and 11 all change `pristine_strict`, so they land together or the
dataset is rebuilt three times.

1. **D2**, the Fe callout. Site text only, no dependencies, can go immediately.
   **Done, v0.7.6.** `background-gsnorm.qmd` carries the callout; no number moved,
   because the EF and pristine analyses already used `ratio_al` only.
2. **Item 8** text correction and **items 2, 3, 10, 11** wording. Site text only.
   **Done, v0.7.7**, and it absorbed two neighbouring text-only actions that had no
   reason to wait for their own release: item 5's outlier criterion and share, and
   item 4's convenience-sample and repeat-site caveats. Seven pages changed
   (`background`, `background-pristine`, `background-mixture`, `background-map`,
   `enrichment-map`, `download-dataset`, `index`), plus the item 11 null guard on
   `enrichment-map.qmd`. Item 4's *sensitivity columns* remain at step 5, and item
   11's *censoring* remains at step 4; only the wording moved here.
3. **Item 6**, the source-stratified EF table. Read-only, no verdict changes,
   but its result may change what D1 should do. **Done.** It did change it:
   `refined_ef_source.csv` and `refined_ef_region.csv` are added to
   `analysis_refined_background_ef()`, the four existing outputs are byte-identical,
   and the finding is in [ef-source-bias.md](ef-source-bias.md). The bulk EF
   reference pools incompatible aluminium measurements and is 2-3x too high for
   every non-Mareano sample.
4. **D1 + item 9 + item 11 censoring**, together: one rebuild of the background
   suite, one re-export, one release. **Option 1 chosen and built** (see
   [ef-source-bias.md](ef-source-bias.md) §6): each fraction's EF reference is
   restricted to one aluminium basis, inferred per sample from Fe/Al, and samples
   off it are left unclassified. It lives in
   `R/analysis-refined-shared-basis.R` so the EF analysis, the pristine synthesis
   and the flat export cannot disagree about it. **Not yet released**: the site
   pages, the re-export and the release are still to do, and items 9 and 11
   should land in the same pass so the dataset is rebuilt once.

   **Done, v0.9.0**, all four in one release with one re-export, as intended.
   The basis restriction needed no database rebuild after all, because
   `normaliser` already carries Fe and Al. Item 11 needed none either, for a
   worse reason: the below-LOQ rows are deleted at clean step 2, so there was no
   flag to carry and Se and Mo verdicts are withheld instead.

   Carrying the AL/FE method rows into refined is still undone, and is the one
   piece of step 4 that does need a rebuild. It is not blocking anything: the
   aluminium basis is inferred from Fe/Al rather than read from a method field,
   which is what made the rest of this possible.

   The release also carries the Method Revisions page, which was not in the
   original ordering. It reconciles the four changes against what the site said
   before, generated from the v0.8.0 outputs frozen in
   `inst/extdata/method-baseline/`.
5. **Item 4** sensitivity columns. **Next.**
6. **D3**, the two summary pages, written once against final numbers. Now that
   the Method Revisions page exists, these are the last pages outstanding.
7. Deferred to separate work: item 7 (regression normalisation), item 10's
   matched-fjord and temporal-alignment analyses.

---

## 5. The two summary pages (deferred, spec retained)

Part 2 of the review specifies `background-summary.qmd` and
`enrichment-summary.qmd`, each as the last item of its navbar menu, assembled
only from `data/refined_summary/*.csv` with no recomputation. That instruction is
accepted as written and the spec is not restated here.

Three amendments follow from the dispositions above:

- The convergence indicator (Part 2, page 1, step 3) must span the >10 and
  >20 km P90s, not just the >10 km one, given item 8.
- The verdict table (page 2, step 2) carries both EF references from D1, and the
  spread between them is the headline, not either column alone.
- Both caveat boxes carry the source-composition finding from item 10, because a
  reader who takes the distance gradient at face value will draw the wrong
  conclusion about where the data gap is.

The reviewer's rule that a number missing from a summary CSV must be added to the
pipeline rather than typed into the page is adopted without exception.
