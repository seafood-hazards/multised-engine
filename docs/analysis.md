# Analyses

Analyses run *on* a finished database and write tidy CSVs (and some plots) to
`<out_dir>/<module>/` (gitignored, `data/analysis/<module>/` by default). They
never modify a pipeline DB, so re-running is always safe. Each output is consumed
by a page on one of the Quarto sites (see [websites.md](websites.md)), so
**adding an analysis output means uploading it to that site repo's release before
pushing `main`**, or the CI pre-render download fails. A local render hides this,
because the local data symlink is skip-if-exists.

## Running them

```r
analyze_data(generation, module = NULL, steps = NULL,
             db_dir = multised_db_dir(),
             out_dir = multised_analysis_dir(), verbose = TRUE)

analyze_data("merged")                                   # every merged module
analyze_data("clean", module = "grainsize")              # one module
analyze_data("refined", module = "background", steps = 4)  # one step of a suite
```

`analysis_modules(generation)` returns the modules in run order, executable.
`steps` selects within a single module and therefore requires `module`; only
`background` has more than one step. The return value is, invisibly, the files
written per module.

Two modules need a suggested package, and say so if it is missing:
`clustering` needs **cluster**, `outlier_review` needs **ggplot2**.

The flat downloadable dataset is **not** an analysis module: it denormalises
rather than deriving anything of its own, so it lives behind
`export_data("refined")`. It still writes to `<out_dir>/download/`, the path the
multised-refined pre-render expects. See [the export section](#export).

It does ship the pristine and background verdicts, but it reads the thresholds
behind them from the `background` module's outputs
(`refined_ef_background.csv`, `refined_background_compare.csv`,
`refined_mixture_components.csv`) rather than recomputing them. So the export
now **depends on the background module having run**, and stops with a message
naming the missing files if it has not. That coupling is deliberate: it is what
keeps the download and the site's Pristine Classification page from drifting
apart.

## Layout

Package code is flat (R collates only top-level `R/*.R`):

`R/analysis-<generation>-<name>.R`, one function `analysis_<generation>_<name>()`

The original script tree `R/analysis/<module>/<NN>_<generation>_<name>.R` was
removed at v0.3.0, once every module's output had been validated by hand.

The `<generation>` token says which DB is read, and therefore which site
consumes the output:

| Token     | Reads                                        | Feeds site |
|-----------|----------------------------------------------|------------------|
| `clean`   | `data/db/<source>_clean.sqlite` (per source) | multised-clean |
| `merged`  | `data/db/multised_merged.sqlite`             | multised-merged |
| `refined` | `data/db/multised_refined.sqlite`            | multised-refined, multised-summary |

A module can hold more than one generation of the same analysis (e.g.
`analysis_clean_grainsize()` and `analysis_merged_grainsize()`), which is
why the token exists rather than the module name alone.

## Modules

### Clean generation (per source, feeds multised-clean)

| Module          | Function                         | What it covers |
|-----------------|----------------------------------|-----------------------------|
| `grainsize`     | `analysis_clean_grainsize()`     | grain size / fines coverage |
| `normalisation` | `analysis_clean_normalisation()` | Fe/Al normalisation |
| `organic`       | `analysis_clean_organic()`       | organic carbon |
| `spatial`       | `analysis_clean_spatial()`       | depth / distance to coast |
| `temporal`      | `analysis_clean_temporal()`      | sampling year |
| `uncertainty`   | `analysis_clean_uncertainty()`   | measurement uncertainty |

### Merged generation (feeds multised-merged)

| Module           | Function                           | What it covers |
|------------------|------------------------------------|------------------------------------------|
| `merged_summary` | `analysis_merged_data_summary()`   | the **Data Categories** page: three count CSVs (`merged_coverage_fraction`, `merged_bulk_factors`, `merged_layering`) classifying every target/reference/organic measurement by fraction (bulk / sieved63 / sieved20), covariate availability (grain size / Fe / Al / organic carbon, from the subsample exist flags), and layering (single vs multi-layer/core, `event.n_layers`) |
| `grainsize`      | `analysis_merged_grainsize()`      | grain size on the merged DB |
| `normalisation`  | `analysis_merged_normalisation()`  | Fe/Al normalisation |
| `organic`        | `analysis_merged_organic()`        | organic carbon |
| `spatial`        | `analysis_merged_spatial()`        | depth / distance to coast |
| `temporal`       | `analysis_merged_temporal()`       | sampling year |
| `depthprofile`   | `analysis_merged_depthprofile()`   | down-core depth profiles |
| `enrichment`     | `analysis_merged_enrichment()`     | enrichment |
| `clustering`     | `analysis_merged_clustering()`     | Facies (K-means chemistry), Hotspots (DBSCAN geography), Regions (both, weighted) |
| `hotspots`       | `analysis_merged_hotspots()`       | geographic hotspots |
| `regions`        | `analysis_merged_regions()`        | regional grouping |
| `siteyears`      | `analysis_merged_siteyears()`      | location-controlled temporal trend (2dp grid, within-cell) |
| `outlier_review` | `analysis_merged_outlier_review()` | **review prototype, not a site input.** Settled the distributional `outlier_flag` rule now applied by merged step 4 (`merge_mark_outliers`); writes candidate/summary CSVs + distribution plots for eyeballing. Needs ggplot2. Its stored outputs in `data/analysis/outlier_review/` are **stale** (they predate the merge-stage outlier flagging); re-run it if you need current numbers |

### Refined generation (feeds multised-refined and multised-summary)

| Module       | Function                                 | What it covers |
|--------------|------------------------------------------|-----------------------------------|
| `background` | `analysis_refined_background()`          | background / pristine baseline |
| `background` | `analysis_refined_background_gsnorm()`   | grain-size-normalised background |
| `background` | `analysis_refined_background_pressure()` | pressure-based background: distance to the nearest **fish farm**, that farm's licensed size, and the provider's stated purpose |
| `background` | `analysis_refined_background_ef()`       | enrichment factor |
| `background` | `analysis_refined_background_mixture()`  | distribution-mixture background |
| `background` | `analysis_refined_pristine()`            | pristine-classification synthesis |
| `background` | `analysis_refined_pressure_controls()`   | controls on the near-cage pressure gradient (time alignment, municipality matching) |
| `background` | `analysis_refined_regression()`          | regression normalisation as a check on the ratio, and whether Al predicts each metal |
| `background` | `analysis_refined_method_changes()`      | pre/post comparison for the Method Revisions page |
| `background` | `analysis_refined_background_igeo()`     | geo-accumulation index: a background-ratio classifier that needs no normaliser |
| `summary`    | `analysis_refined_summary()`             | assembles the `background` outputs, plus extent counts and map layers, into the tables the multised-summary site draws |

`summary` is the only module in the project that depends on another. It derives
no background, no enrichment factor and no verdict: it reshapes what `background`
wrote, and adds only the things no background CSV holds (per-element and
per-source extent, the pipeline funnel, and the site and grid map layers). It
errors rather than reading a stale directory if `background` has not run, and a
full `analyze_data("refined")` reaches it in the right order because it is listed
after `background` in the registry. Full spec:
[summary-site.md](summary-site.md).

Two things it must keep doing, both learned by getting them wrong first:
**withholding propagates** (a `reliable` flag that ignores `withheld` published a
molybdenum background on a page that said molybdenum has none, and an Igeo built
on a withheld `B` reached the map layer), and **element-level counts are their
own columns** (summing the per-fraction site counts reported 25 347 copper sites
where there are 24 908).

The `background` module is a single ordered suite: each script builds on the
previous one, and steps 1-6 map onto the six background estimate and verdict
pages of multised-refined.

Step 7 qualifies step 3 rather than extending it. It re-reads the refined DB to
ask what is left of the near-cage enrichment once the near band is restricted to
samples taken while the farm was operating (`aquaculture.start_year` /
`end_year` / `active` against `event.year`) and the far band is matched within
municipality instead of being the national >20 km pool. It feeds no verdict; it
feeds the Pressure Controls page and the caveats on the pages that use the
gradient as a yardstick.

Step 3 was rebuilt in August 2026, and the change is worth knowing before reading
its numbers against anything older.

- **The axis is `dist_to_fish_farm`, not `dist_to_aquaculture`.** The latter is the
  nearest aquaculture site of any kind, and 84% of what it added to the near band sat
  next to a *land-based* facility (smolt plants, lobster and prawn holding) with the
  rest mostly blue mussel. Neither deposits feed or antifouling copper on the seabed at
  the licence coordinate. `refined_pressure_axis.csv` and
  `refined_pressure_axis_dropped.csv` hold the before/after so the change is auditable.
- **The far band is cleaned of stated pressure.** The raw > 20 km pool is not a
  background: 55.6% of its bulk copper and 54.3% of its bulk zinc is Vannmiljø
  `pressure_class = "pressure"`, the contaminated-seabed / industry / sewage
  programmes. Rows a provider has *stated* are pressure monitoring are removed; the four
  sources that record no programme keep every row, so this removes stated pressure and
  never inferred pressure. `enrich_near_clean` is the ratio to read; `enrich_near`
  (raw far band) is kept beside it.
- **Farm size enters** via `fish_farm_band` (`refined_pressure_size.csv`), with
  `refined_pressure_size_covariates.csv` recording the siting confounder that has to be
  read with it: large farms sit in roughly twice the water depth of small ones.
- **And farm size does not survive being controlled** (section 5b, five CSVs). The raw
  split is inverted: copper enriches 2.91 / 3.15 / 2.13 for small / medium / large, which
  is not a dose-response. `refined_pressure_size_depth.csv` runs that split up a ladder
  of controls (`raw` -> `clean`, stated-pressure rows out -> `depth`, one 50-150 m window
  for all three bands -> `depth+texture`, a 20-80% mud window on top), reporting the
  *achieved* median depth and mud per band so each match is checked rather than trusted;
  `refined_pressure_size_depth_cost.csv` says what each rung costs.

  **Depth was the named confounder and it is not the one that mattered.** Matched at a
  median of 84 / 97 / 95 m the ordering is unchanged (copper P90 65.1 / 96.4 / 50.7), and
  `refined_pressure_size_strata.csv` shows it holding in all five depth strata, so no
  choice of window created it. What the strata table does show is that depth itself is a
  strong covariate: copper roughly doubles and zinc roughly triples from the shallowest
  stratum to the deepest, the ordinary grain-size effect.

  **Location was the confounder.** The bands read out different coastlines
  (`refined_pressure_size_geography.csv`: large farms 84.8% Norwegian Sea and the only
  band with Barents Sea sites, small farms 28.3% North Sea). `refined_pressure_size_paired.csv`
  therefore takes one median per municipality x size band and ratios two bands *within
  one municipality*, over three depth windows. The response goes flat: eighteen ratios
  spanning 0.83 to 1.28, the sign flipping between windows, and `pct_above_1` near 50 in
  almost every row. Copper reads large > small and large < medium at once.

  So **licensed MTB is not a usable proxy for seabed load at the licence coordinate**, and
  size-weighted distance, the reason capacity was carried onto `site`, is not supported.
  This is a statement about the proxy: MTB is a licensed ceiling rather than the stock in
  the water at sampling, and a bigger farm's cages extend further from the licence point.
  **No near/far number changes** - that comparison is across distance bands, not size
  bands.
- **The small band was also being charged unevenly.** Its near band is 13.8% stated
  `pressure` monitoring against 1.3% for large, so every tier above `raw` drops those
  rows before comparing.
- **Stated purpose is the independent check** (`refined_pressure_stated.csv`): 80% of
  Vannmiljø's aquaculture-monitoring measurements fall within 1 km of a fish farm and
  0.3% beyond 20 km, and all 64 reference-condition measurements are beyond 20 km.

**Every refined step moved with it.** Steps 1, 4, 6, 8 and 10 used
`dist_to_aquaculture` only to *report* coverage against the pressure gradient, never to
define a background or a verdict (the background is `dist_to_coast`), so switching them
changed reported coverage and no verdict. The bin column is `dist_bin` everywhere and the
axis label is `"distance to fish farm"`.

**Step 7 needed the rebuild.** Its temporal control asks whether *that* farm was licensed
when the sediment was sampled, and until August 2026 the only farm id on `site` was
`aqua_id`, the nearest aquaculture site of any kind. `R/clean-05-aquaculture.R` now writes
`fish_farm_aqua_id`; the clean, merged and refined DBs were rebuilt to carry it, and step 7
bands on `dist_to_fish_farm` and reads the licence dates through it. It also cleans both far
bands of stated pressure, so its ratios and step 3's are on the same footing.

**One result reversed.** On the old link step 7 reported that near-cage sediment sampled
*before* the farm existed was dirtier than sediment sampled while it operated, and that was
read as evidence that farm distance is partly a marker of industrialised coastline. It was an
artefact of dating samples against the wrong facility. Keyed to the fish farm's own licence
the ordering is the expected one (copper P90 34 pre-farm, 68.3 operating, 74.6 post-closure),
and the time alignment barely bites at all: 88% of near-cage copper is contemporary with an
operating farm.

Step 8 also decides **which groups get a verdict at all** (D4). It fits `metal ~ a + b * Al` on the same offshore
reference the EF uses, so the two are comparable, and answers two questions the EF
cannot ask about itself: whether the intercept the ratio assumes away is really
zero, and whether aluminium predicts the metal at all. The second turned out to
matter more: R2 is about 0.5 for Co, Cu and Zn in bulk and under 0.1 for
everything else, sieved fractions included. Those three groups are therefore the
only ones the EF step computes an enrichment factor for.

**D4 governs bulk only.** The grain-size control is a property of the fraction, not
of the rule: aluminium in bulk, where the control has to be statistical, and the
sieve in the sieved fractions, where it was applied physically before the chemistry.
Aluminium scoring near zero on a sieved fraction is that control working, not
failing, so it withholds nothing; the sieved `r2` and `rho` stay in the frozen table
as a diagnostic and nothing reads them to decide. `refined_gs_control()` is the
split. Before 2026-08-27 the sieved rows were scored `normalisable = FALSE` and that
flag withheld a verdict from 27 971 sieved measurements. The rule itself is frozen in
`inst/extdata/normalisability/` and read through
`R/analysis-refined-shared-normalisability.R`, because steps 4 and 6 consume it
and run first; step 8 recomputes it and warns if the frozen table has gone stale,
over the groups the rule governs.

Step 10 adds the **geo-accumulation index**, `Igeo = log2(C / (1.5 * B))`, against the
same offshore (> 10 km) population the EF reference is cut from but using the median raw
concentration as `B` rather than the median metal/Al. The point is what it does not need:
EF divides by aluminium, Igeo divides by a background, so it classifies any row that has
a value. EFSA names it for exactly this case, "in absence of EF".

Coverage goes from **9.8% to 97.2%** of target measurements, and within 1 km of a fish
farm from 0.3% to 99.9% -- the data EFSA asked for by name, which the pipeline could not
speak to at all because Vannmiljø's aquaculture programme carries aluminium on 5 of
13,996 subsamples.

It is **not wired into the pristine verdict**, and step 10 sits after the synthesis
deliberately. That was decided on the numbers, 2026-08-25: **the verdicts stay on EF,
and Igeo is reported alongside them.** Igeo's reach is the argument for it and its lack
of grain-size control is the argument against, and the confounding measured below is
strong enough in bulk (cobalt rho 0.70 against the mud fraction) that a verdict built on
it would be partly a verdict about texture. Reporting the index without promoting it to
a verdict keeps the coverage visible to EFSA, who asked for Igeo in EF's absence,
without changing what "pristine" means in this database.

The step also tests the index against the fish-farm gradient, and that test was
**published once without controls and got the answer backwards** (corrected 2026-08-26).
The bands carry two confounders that have nothing to do with farms: the > 20 km band is
**55.6%** of its copper Vannmiljø stated pressure, so it was a harbour rather than a
remote band, and the < 1 km band is **38.1%** fines against **74.7%** beyond 20 km and a
`B` cut from **69.4%** mud, so near-cage sediment reads low on grain size alone. The step
now reports each band three ways: raw, cleaned of `pressure_class = "pressure"`, and
cleaned plus matched on `fines_lt63` in two windows.

Cleaning alone reverses the finding: copper's far-band class 0 share goes from 47.3% to
**71.7%**, above the 54.4% under the cages, so the far band becomes the cleaner band.
Matching texture as well produces a monotone copper gradient, median Igeo **+0.51** under
the cages against **-0.35** beyond 20 km, a factor of **1.8**, which lands beside the 2.6x
from step 3 and the 1.6x municipality-matched figure from step 8 without needing any
aluminium. Zinc moves by 1.4x and cobalt and manganese have no near-cage band that
survives the controls. `refined_igeo_band_cost.csv` records the price: grain size is
recorded on 43.9% of far-band rows and **2.7%** of near-cage rows, so the matched
comparison rests on 337 copper measurements out of more than 21,000.

**A third control was added 2026-08-26: location** (`refined_igeo_paired.csv`,
`refined_igeo_pair_reach.csv`). Cleaning and texture matching both act on *what* is in a
band; neither touches *where* the bands are, and the farm-size work in step 3 found
location to be the confounder that bit hardest there. Bands are therefore paired within a
municipality, one median per municipality x band.

Three things come out of it. **The controls do not stack**: requiring both bands in one
municipality on top of the mud window leaves a single municipality for copper, so the 1.8x
headline cannot be location-checked directly. **Paired against > 20 km without the texture
match, the result just replays the texture confounder** (copper -0.41, positive in 31.8% of
22 municipalities, with the near side 57 pp sandier); that row is published so the trap
stays visible. **The adjacent contrast is the informative one**: < 1 km against 1-5 km
pairs on **79** municipalities with a texture gap of 7.6 pp rather than 57, and copper is
**+0.25 of an Igeo unit, positive in 72.2%**. It is conservative twice over (1-5 km is not
farm-free, and the near side is still the sandier), and restricting to texture-balanced
pairs lifts it to **+0.46 at 82.1%** on 28 municipalities. Zinc is -0.01 at 49.4%, its
fourth null.

So copper's case now rests on two Igeo controls that are each blind to what the other
fixes: texture matching holds grain size and lets location vary (337 measurements),
municipality pairing holds location and lets grain size vary (79 municipalities), they
cannot be applied together, and they agree.

**A fourth control needs no matching at all** (`refined_igeo_within_site.csv`,
`refined_igeo_within_reach.csv`, added 2026-08-27). Every control above approximates one
thing: a farm-free reading of the *same* seabed. `fish_farm_aqua_id` supplies it directly,
because a site sampled before its farm opened and again during operation is its own
control, holding location, depth, regional background and sampling programme fixed and
needing no grain size. The pre-farm rows are almost all MOM baseline surveys taken a median
of **one year** before the farm opens.

It carries a placebo, because a before/after is a time series and this sediment is not
stationary: the same contrast runs in 1-5 km and 5-20 km rings split on the *same* farm's
start year. The gap must be matched too, since near-cage pairs sit 4 years apart and 5-20 km
pairs 10. Gap-matched to 2-7 years, copper rises **+0.22** under the cages (rising at 69.4%
of 72 sites) against **-1.05** in the 5-20 km placebo (22.2%). As a per-year rate over all
pairs the gradient is monotone: **+0.050**, -0.017, -0.044 Igeo units per year. **The
secular trend is downward**, so every cross-sectional figure on the page is measured against
an improving background and understates the farm.

**Zinc is not null in this design**, and that is a change: **+0.23** under the cages, rising
at **70.8%** of 65 sites, against -0.53 in the placebo, after four cross-sectional designs
put it near zero. The readings reconcile rather than conflict, because every other design
compares different places and zinc's between-place variance is large enough to hide a modest
effect, while this one compares one place with itself. Zinc is therefore **unresolved**
rather than absent; its withheld verdict stands, and no export or classification changes.

**The design cannot separate metal input from texture change**: a farm enriches sediment
with organic matter and organically enriched sediment is finer, so part of the rise may be
the seabed becoming muddier. That is mediation, not confounding, but it belongs in the
reading, and no site has grain size in both periods to check it.

`B` itself is left uncleaned, and `refined_igeo_background.csv` now carries the columns
that justify it: the offshore pool is 8.7% stated pressure against 55.6% in the far band,
and the cleaned median moves `B` by at most 8.3%. Cleaning it would also cut it from a
different population than the EF reference.

Those numbers include a caveat the step measures on itself. Igeo has no grain-size
control, so `refined_igeo_confound.csv` correlates it against the mud fraction, with
metal/Al alongside for scale. In bulk, Igeo tracks texture for every metal, worst for
cobalt (rho 0.70). In the sieved fractions it barely does, which is D4 from the other
side: a sieved sample is already grain-size controlled. And EF is **not uniformly
better** -- it beats Igeo for cobalt (0.24 against 0.70), loses for copper (0.55 against
0.36) and ties for zinc, so dividing by aluminium removes the texture signal for one
metal and not another. The case for Igeo is therefore strongest exactly where EF cannot
run: the sieved fractions and the near-farm data.

Selenium and molybdenum stay withheld. That withholding is about below-LOQ censoring
truncating the distribution, which a different index over the same rows inherits; D4
normalisability, by contrast, does not apply, since nothing here divides by aluminium.

Step 9 derives nothing of its own: it reads the frozen pre-revision baseline in
`inst/extdata/method-baseline/` alongside what the earlier steps have just
written, so the Method Revisions page shows generated numbers rather than typed
ones. It must run last.

## Export

```r
export_data(generation = "refined", format = c("dataset", "efsa"),
            source = NULL, db_dir = multised_db_dir(),
            out_dir = multised_analysis_dir(), verbose = TRUE)
```

| Format | Function | Writes |
|---|---|---|
| `dataset` | `export_refined_dataset()` | `download/multised_refined_dataset.tsv.gz` + `refined_dataset_dictionary.csv` |
| `efsa` | `export_efsa_submission()` | `download/multised_efsa_submission.tsv.gz` + `efsa_submission_dictionary.csv` |

Both are cut from `refined_export_base()`, one pull with the background verdicts
already joined, so they cannot disagree about scope, references or verdicts.

One flat row per target measurement, plus a column dictionary that drives the
Dataset Download page. Only the refined generation has an export; the five
`inst/scripts/pilot/<source>_07_create_data_frame.R` scripts are legacy
per-source review dumps for the retired pilot sites and are not part of the
interface.

**31 columns.** Eighteen describe the measurement (location, year, layer,
element, fraction, value, the Fe / Al / organic normalisers, the fines, the two
distances, `outlier_flag`, and `extraction` / `extraction_class`, the digestion
chemistry and EFSA's class for it). The other thirteen are the verdicts and the
references behind them, added by `add_background_flags()`:

| Column | Is |
|---|---|
| `ef` | the enrichment factor, `ratio_al / bg_ratio_al` |
| `classifiable` | whether a pristine verdict exists for the row: in bulk, that an EF could be computed; in the sieved fractions, that the element is not withheld and an offshore P90 exists |
| `pristine_ef` | `EF < 1`, the permissive rule. Bulk only, since no EF is defined off the aluminium-controlled fraction |
| `pristine_strict` | every criterion that applies to the fraction agrees. Bulk: `EF < 1` and below the mixture threshold and below the offshore P90. Sieved: below the mixture threshold and below the offshore P90, with the sieve as the grain-size control |
| `background_p90` | below the offshore P90 (raw concentration, not grain-size controlled) |
| `background_mixture` | below the mixture threshold (likewise) |
| `bg_ratio_al`, `p90_off`, `mixture_threshold` | the three references applied to that row |

Scope matches `analysis_refined_pristine()` exactly: fractions `bulk` /
`sieved63` / `sieved20`, outliers dropped, non-positive values dropped. Rows
outside it get empty verdicts, never verdicts computed on a different basis.
The match is checkable, and is worth rechecking after any change to the
background module: group the exported rows by element and fraction and compare
`pct_classifiable` / `pct_ef` / `pct_strict` against
`refined_pristine_summary.csv`. All 20 groups agree.

`ef` is written with `signif(, 6)` rather than rounded to a few decimals, and
`check_ef_consistent()` enforces the reason: at 3 decimals, 24 rows with an EF
just under 1 printed as `1.000` beside `pristine_ef = TRUE`, so the file
contradicted itself for anyone applying their own cutoff.

### The EFSA submission table

`format = "efsa"` writes the superset of the two things EFSA asked for, which are
not the same thing: the reporting workbook
(`data/raw/Mareano/EFSA form-reporting-tool-trace-elements-IMR.xlsx`) and the
data-extraction spec in [ReplyFHF_TypeDataForEFSA.md](ReplyFHF_TypeDataForEFSA.md).
See [efsa-submission.md](efsa-submission.md).

**58 columns.** The first 42 reproduce the workbook's `dataReported` sheet in its
own order, so the block can be pasted straight in; the remaining 16 are the fields
only the ReplyFHF spec asks for (extraction class, the ordinal depth band, sieve /
bulk, SD) plus the provenance a reviewer needs. Term codes come from the workbook's
own catalogue sheets (PARAM, UNIT, EXPRRES, MTX, YESNO, ANLYMD) and are frozen in
`R/export-efsa-submission.R` rather than read from the xlsx at run time, so a
replacement form cannot silently change the submission's shape.

What it cannot fill, and why:

| Field | Why |
|---|---|
| `accLab` | Only MUDAB records accreditation and it is not carried through the pipeline |
| `phSed`, `phWater` | No source holds porewater pH; the one sediment pH series is 22 ICES rows outside this scope |
| `TextureSedClay`, `TextureSedSilt` | Refined carries combined fines, not separate grain-size fractions. `TextureSedSand` is their complement |
| `hardWater`, `DOC` | Water-column measurands, not sediment |
| `publicData`, `refPublication`, `confidential` | The submitter's statements, not derived values |
| `specCode` for iodine | EFSA's own catalogue has no term; the workbook leaves it blank too |

`pristineLoc` is the one field where the answer is stronger than the ask: the spec
prefers a local-background enrichment factor and warns against Turekian and
Wedepohl values, which is exactly what `pristine_ef` is. It is subject to D4, so it
is present on 11,266 of 115,811 rows and empty elsewhere. **An empty verdict is not
a finding of non-pristine**, and the dictionary says so.
