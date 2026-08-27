# multised.engine (development version)

## A summary layer over the refined results

A new analysis module, `analyze_data("refined", module = "summary")`, and a tenth
Quarto site (`../multised-summary`) that draws it: Home, Methods, one page per
element, Downloads. It is the plain-English answer for a reader who will not open
the refined site, and it links there for every working.

- **It is a module, not a sixth generation.** There is no `multised_summary.sqlite`
  and no `create_db("summary")`. A sixth database would restate the refined mart
  rather than derive anything, and every generation so far exists because it
  changes the data. See [summary-site.md](docs/summary-site.md).
- **It derives no verdict.** Every background, pristine share and enrichment number
  is read from what the `background` module wrote and only reshaped. What it
  computes itself is extent (counts, year ranges, per-source and per-stage totals)
  and the two map layers.
- **No page holds a number.** Four numbers were typed into pages during the build
  (the pipeline funnel, the classifiability-by-band chart, the four-controls table
  and the zinc comparison) and all four moved into the module before it shipped.
- **Withholding now propagates to the summary layer.** Two bugs found and fixed in
  the same build: `summary_background.csv` marked molybdenum and selenium
  `reliable`, so the site printed a molybdenum background two paragraphs above the
  sentence saying it has none; and the map layer carried an Igeo for both, built on
  a `B` cut from a distribution whose low end was deleted. Both are now `NA`, and
  the map hides its Igeo control where there is no Igeo.
- **Element-level counts are their own columns.** Summing the per-fraction site
  counts reported 25 347 copper sites where there are 24 908.
- **One counted population.** Everything outside the funnel counts the same
  115 231 rows; the funnel carries the difference from the database's 115 811 as a
  visible last rung rather than leaving two unexplained totals on one page.

No verdict changes. The module reads the refined database and writes CSVs; nothing
in the pipeline, the exports or the refined site moved.

A first pass of presentation fixes after publication, all on the site and none in
the module:

- The pipeline diagram on the home page runs top to bottom. Seven stages laid out
  sideways were scaled down to fit the page and the labels became unreadable.
- Thousands are separated with a non-breaking space, so a site count no longer
  wraps to two lines inside a narrow table column.
- The element maps open on the extent of the element they draw, held between zoom
  3 and 6, and carry a reset button. They also draw OpenStreetMap tiles: CARTO's
  free basemaps now stamp "API key required" across every tile.
- **Why the sieved fractions carry no verdict is now stated**, in "And in bulk
  sediment only" on the pristine methods page, and pointed at from the data page
  and every element page. A sieved sample is already grain-size corrected by the
  sieve, so aluminium has nothing left to track.
- The site is titled `multised (summary)`, so a reader with several of the sites
  open can tell the tabs apart.

Then a second pass, this one reaching the module:

- **D4's measures are published alongside its flag.** `summary_elements.csv` gains
  `al_tested`, `al_n`, `al_r2` and `al_rho` from the frozen normalisability table,
  and `summary_meta.csv` gains `al_r2_limit`. Saying only that aluminium fails on
  the sieved fractions invites the wrong conclusion, that there is not enough
  sieved data. There is plenty: copper sieved below 63 um has 4 502 measurements
  and 2 203 aluminium-paired samples, and aluminium explains 0.3% of the variation
  in them against 55.6% in bulk. The pristine methods page now prints that
  comparison instead of asserting the conclusion.
- The element map box is 700 px tall, so a fit to the full latitude range of the
  data lands at zoom 3. Shorter, and it dropped to zoom 2: North Africa filling the
  bottom of the frame while the Svalbard and Barents cells were cut off the top.

## A before/after control that needs no matching, and zinc stops being null

Every Igeo control so far matched one population against another and paid for it: texture
matching spends 97.3% of the near-cage rows, municipality pairing cannot be stacked on it,
and the adjacent contrast that survives both is blunted because 1-5 km is not farm-free.
All three approximate one thing, a farm-free reading of the *same* seabed, and
`fish_farm_aqua_id` supplies that directly. A site sampled before its farm opened and again
during operation is its own control (`refined_igeo_within_site.csv`,
`refined_igeo_within_reach.csv`).

* **It holds fixed what no matching reaches**: exact location, depth, regional background,
  sediment provenance and sampling programme, and it needs no grain-size measurement. The
  pre-farm rows are almost all MOM baseline surveys taken a median of **one year** before
  the farm opens, so this is a designed baseline rather than an accident of the archive.
* **It carries a placebo**, because a before/after is a time series: the same contrast runs
  at 1-5 km and 5-20 km, split on the *same* farm's start year. The gap needs matching too,
  since near-cage pairs sit 4 years apart and 5-20 km pairs 10.
* **Copper rises +0.22** under the cages, at 69.4% of 72 sites, against **-1.05** in the
  5-20 km placebo. Per year over all pairs the gradient is monotone: +0.050, -0.017, -0.044.
* **The secular trend is downward**, so every cross-sectional figure on the page is measured
  against an improving background and understates the farm.
* **Zinc is not null here**: +0.23, rising at 70.8% of 65 sites, against -0.53 in the
  placebo, after four cross-sectional designs put it at zero. The readings reconcile: those
  compare different places, where zinc's between-place variance hides a modest effect; this
  compares one place with itself. Zinc is now **unresolved** rather than absent.
* **What it cannot separate**: a farm makes sediment organically enriched and therefore
  finer, so part of the rise may be texture rather than load. Mediation rather than
  confounding, but it belongs in the reading, and no site has grain size in both periods.

No verdict changes. Zinc keeps its withheld status and nothing touches the pristine
classification or the exports.

## Igeo gains a location control, and copper survives it

The farm-size work below found location to be the confounder that mattered most, and the
Igeo bands had never been checked against it: cleaning and texture matching both act on
*what* is in a band, neither on *where* the bands are.
`analysis_refined_background_igeo()` now pairs bands inside one municipality
(`refined_igeo_paired.csv`, `refined_igeo_pair_reach.csv`).

* **The controls do not stack.** Requiring both bands in one municipality on top of the
  50-100% mud window leaves a single municipality for copper, because the texture match
  has already spent 97.3% of the near-cage rows. The published 1.8x cannot be
  location-checked directly, and the step says so rather than implying otherwise.
* **Paired against the > 20 km band without the texture match, the answer just replays
  the texture confounder**: copper -0.41, positive in 31.8% of 22 municipalities, with the
  near side 57 percentage points sandier. Published deliberately, so the trap is visible.
* **The adjacent contrast is the one that works.** A near-cage site and a site a few
  kilometres away usually share a municipality, so < 1 km against 1-5 km pairs on **79**
  municipalities with a texture gap of 7.6 points rather than 57. Copper is **+0.25 of an
  Igeo unit under the cages, positive in 72.2%** of them, conservative twice over (1-5 km
  is not farm-free, and the near side is still the sandier of the two). Restricting to
  texture-balanced pairs gives **+0.46 at 82.1%** on 28 municipalities.
* **Zinc is -0.01 at 49.4%**, a coin flip, and the fourth design on the site to say so.

Copper's case now rests on two Igeo controls that are each blind to what the other fixes,
on populations that cannot be combined, agreeing anyway. No verdict changes.

## Farm size does not predict what is under the cages

`analysis_refined_background_pressure()` (refined background step 3) split the near band
by the licensed size of the farm and got an inverted response: copper enriching 2.91 /
3.15 / 2.13 for small / medium / large. It closed by saying the likely cause was siting,
because large farms are licensed into roughly twice the water depth, and that separating
the two needed a depth-matched comparison that was not built. It is built now, as a
ladder of controls, and the explanation did not survive it.

* **Depth was not the confounder.** Cutting all three size bands to one 50-150 m window
  (achieved medians 84 / 97 / 95 m against 66 / 123 / 110 m raw) leaves the ordering
  untouched: copper P90 65.1 / 96.4 / 50.7. Reading the same contrast inside five coarse
  depth strata finds it at every depth, so no choice of window created it.
* **Depth is still a strong covariate**, which is why matching it was worth doing: copper
  roughly doubles and zinc roughly triples from the shallowest stratum to the deepest.
* **Location was the confounder.** The size bands read out different coastlines: large
  farms are 84.8% Norwegian Sea and the only band with any Barents Sea sites, small farms
  28.3% North Sea. Pairing farms *within one municipality* removes the size response
  entirely: eighteen ratios spanning 0.83 to 1.28, the sign flipping between depth
  windows, and about half the paired municipalities falling each way. Copper reads large
  above small and below medium in the same table.
* **The small band was also charged unevenly.** Its near band is 13.8% Vannmiljø stated
  `pressure` monitoring against 1.3% for the large band, so every rung above `raw` drops
  those rows first.
* Five new CSVs: `refined_pressure_size_depth.csv` (the ladder, with achieved depth and
  mud per band so each match is checked), `refined_pressure_size_depth_cost.csv`,
  `refined_pressure_size_strata.csv`, `refined_pressure_size_geography.csv` and
  `refined_pressure_size_paired.csv`.

The conclusion is about the proxy, not about fish farming: **licensed MTB is not a usable
stand-in for seabed load at the licence coordinate**, so modelling pressure as
size-weighted distance is not supported. MTB is a licensed ceiling rather than the stock
in the water at sampling, and a bigger farm's cages reach further from the licence point.
No verdict changes, and no near/far number changes: that comparison is across distance
bands, not size bands.

## The Igeo farm gradient was an artefact of its bands

`analysis_refined_background_igeo()` (refined background step 10) tests the index against
distance to a fish farm. It published the answer **backwards**: that copper and zinc peak
at 5 to 20 km rather than under the cages, that the band beyond 20 km is dirtier than the
band under them, and therefore that distance to a fish farm is a poor axis for Igeo. The
arithmetic was right and the conclusion was not. The step now reports every band three
ways, raw, cleaned and matched, so the correction is auditable rather than silent.

- **The bands are cleaned of stated pressure.** The > 20 km band is **55.6%** of its bulk
  copper and **54.3%** of its bulk zinc Vannmiljø `pressure_class = "pressure"`, against
  3.5% of both under the cages. It was an industrial band, not a remote one. Cleaning it
  alone reverses the published finding: copper's far-band class 0 share goes from 47.3%
  to **71.7%**, above the 54.4% under the cages. The earlier note argued the bands needed
  no cleaning because they describe where the index lands rather than estimate a
  background. True of the arithmetic, false of the conclusion drawn from it.
- **The bands are also matched on texture.** Igeo divides by a background cut from
  offshore mud (**69.4%** fines for copper) while the near-cage band is **38.1%** fines,
  so near-cage sediment reads low on grain size before any farm enters it. Matching every
  band to comparable muddiness gives copper a monotone gradient: median Igeo **+0.51**
  under the cages, +0.35 in both middle rings, **-0.35** beyond 20 km. That is a factor of
  **1.8**, beside 2.6x from step 3 and 1.6x municipality-matched from step 8, and it needs
  no aluminium. A tighter window gives +0.47 against -0.39, so it is not a cut artefact.
- **Zinc moves 1.4x and only under the texture control**, and it loses that to the
  location control on step 8 (1.04 on a coin flip). Two controls that disagree is the
  argument for reading its near-cage signal as sediment character rather than farm input.
  Cobalt and manganese have 14 and 29 clean near-cage measurements, below the reporting
  threshold, so the innermost band is two elements.
- **`B` is deliberately not cleaned**, and `refined_igeo_background.csv` now carries the
  evidence: the offshore pool is 8.7% stated pressure against 55.6% in the far band, and
  the cleaned median shifts `B` by at most **8.3%**, 0.11 of an Igeo unit. Cleaning it
  would cut it from a different population than the EF reference, which is the one thing
  the step is built not to do.
- New outputs `refined_igeo_pressure_matched.csv` (two fines windows) and
  `refined_igeo_band_cost.csv` (what each control costs each band).
  `refined_igeo_pressure.csv` gains `pct_stated`, `n_clean`, `igeo_p50_clean` and
  `pct_unpolluted_clean`; `refined_igeo_background.csv` gains `n_bg_stated`,
  `bg_median_clean`, `bg_fines_p50`, `pct_bg_stated` and `bg_shift`.
- The stale **0.4% to 99.4%** near-cage coverage figure in `docs/analysis.md` is corrected
  to **0.3% to 99.9%**, matching the axis change already made on the site.

No verdict changes. Igeo issues none, and nothing here touches EF, the pristine
classification or the exports.

## The pressure gradient measures the fish farm now

`analysis_refined_background_pressure()` (refined background step 3) was rebuilt.
It answers a question that had never been asked of it: *is the near band actually
near a fish farm, and is the far band actually a background?* Both answers were no.

- **The axis is `dist_to_fish_farm`, not `dist_to_aquaculture`.** The old column is
  the nearest aquaculture site of any kind. **84%** of what it added to the near
  band sat next to a *land-based* facility (smolt plants, lobster and prawn
  holding) and most of the rest next to blue mussel. Neither puts feed or
  antifouling copper on the seabed at the licence coordinate.
  `refined_pressure_axis.csv` and `refined_pressure_axis_dropped.csv` hold the
  before and after, so the change is auditable rather than silent.
- **The far band is cleaned of stated pressure.** The raw > 20 km pool was never a
  background: **55.6%** of its bulk copper and **54.3%** of its bulk zinc is
  Vannmiljø `pressure_class = "pressure"`, the contaminated-seabed, industry and
  sewage programmes. Cleaning it takes the copper background from 102 to
  **25.7 mg/kg** and zinc from 273 to **126.5**, which puts both within a few
  percent of the mixture crossover and the offshore P90 for the first time. Only
  *stated* pressure is removed; sources that record no programme keep every row.
- **Two headline figures are withdrawn.** Molybdenum was reported at about 13x and
  selenium at about 5x, the largest ratios on the site. On the corrected axis there
  are **21** bulk molybdenum and **1** bulk selenium measurements within 1 km of a
  sea cage, against a threshold of 30. They are withdrawn, not restated. Copper
  reads **2.6x** on 11,475 measurements and is the one strong near-cage signal.

## Farm size is in the analysis

`fish_farm_mtb_t` and `fish_farm_band` had been on `site` since the aquaculture
work and no analysis had ever read them. The near band is now split by the
licensed size of the farm it is near (`refined_pressure_size.csv`).

**It is not a dose-response.** Copper goes 2.91 / 3.15 / 2.13 across small, medium
and large, and zinc 1.11 / 1.26 / 0.95: large is the *lowest* of the three for both.
`refined_pressure_size_covariates.csv` measures the reason rather than asserting
it. Large and medium farms sit at 107 m and 121 m median depth against 66 m for
small, and further from shore, because Norway licenses the big farms into deep,
well-flushed water precisely so it disperses the load. A flat or inverted size
response is therefore not evidence that the pressure is absent, and separating the
two needs a depth-matched comparison this analysis does not do.

## The provider's stated purpose enters an analysis

`dataset.pressure_class` reached the export and the dictionary and no analysis had
used it. It now cross-checks the geometry (`refined_pressure_stated.csv`), and the
two agree: **80%** of Vannmiljø's aquaculture-monitoring measurements fall within
1 km of a fish farm and **0.3%** beyond 20 km, and all **64** reference-condition
measurements are beyond 20 km. A Norwegian programme code and a great-circle
distance to a licence coordinate are independent, and they pick out the same rows.

## Every refined analysis is on the fish-farm axis

All ten refined analyses now bin on `dist_to_fish_farm`. In eight of them the axis
was only ever used to *report* coverage against the pressure gradient, never to
define a background or a verdict (the background is `dist_to_coast`), so **no
verdict changed**: the refined DB still holds 115,811 target measurements and
11,266 carry a pristine verdict, unchanged from `v0.3.2`. What changed is what the
coverage tables are coverage *of*. The bin column is `dist_bin` throughout and the
axis label is `"distance to fish farm"`.

`analysis_refined_pressure_controls()` needed the databases rebuilt, and got them.

## A reversed result, corrected

Pressure Controls used to report that near-cage sediment sampled **before** the
farm existed was *dirtier* than sediment sampled while it operated, and read that
as evidence that distance to a farm is partly a marker of industrialised coastline
rather than of farm input. It was an artefact.

The licence dates came from `aqua_id`, the nearest aquaculture site of any kind, so
a sample could be dated against a mussel raft or a land-based smolt plant while its
chemistry was attributed to a cage that was not there. `clean_aquaculture()` now
writes **`fish_farm_aqua_id`**, the nearest fish farm's own id, and the clean,
merged and refined DBs were rebuilt to carry it.

On the corrected link the ordering is the one the pressure hypothesis predicts:
copper P90 **34** mg/kg pre-farm, **68.3** while operating, **74.6** after closure,
and the same ordering for zinc. The time alignment barely bites at all now, because
**88%** of near-cage copper is contemporary with an operating farm rather than the
five in six the old link implied.

The controls that remain are geographic, and they separate the two elements:
matched within a municipality copper goes 2.62 to **1.60** and exceeds local far
sediment in **70%** of the 40 testable municipalities, while zinc goes 1.09 to
**1.04** at 51% of 37. **Copper is the one near-cage signal that survives every
control on this site.**

## Fixes

- Both far bands in `analysis_refined_pressure_controls()` are cleaned of stated
  pressure, so its ratios and the pressure step's are on the same footing.
- `analysis_refined_pristine()` writes **`refined_pristine_coverage_source.csv`**,
  the aluminium-coverage-by-band-and-source split that was previously typed into
  the Pristine Classification page as a static table and therefore unverifiable.
  Recomputed on the corrected axis it changes: the > 20 km band is 44% Mareano,
  not the 85% the page claimed.
- The Vannmiljø pristine share no longer rises monotonically with farm distance:
  it falls back beyond 20 km, because roughly two thirds of that source's
  classifiable far-band rows are its own contaminated-seabed, industry and sewage
  programmes. The page says so instead of claiming a clean trend.
- `refined_pressure_percentiles.csv` renames `aq_bin` to `dist_bin`, since it is
  no longer an aquaculture distance.
- `background-summary` and `enrichment-summary` on multised-refined were moved
  onto the cleaned far band, and the hardcoded manganese spread figures on
  `background-summary` are computed from the CSV rather than typed.

# multised.engine 0.3.2

The source-fidelity release. Five things the sources record and the pipeline was
discarding now survive to the export, one new analysis reaches almost every
measurement, and every generation was rebuilt on the corrected geo-enrichment.

**Every database and both exports were rebuilt.** The refined generation now holds
**115,811** target measurements, nine fewer than `v0.3.1`, and the nine are
explained below rather than absorbed.

## Source fidelity

Five fields the sources state and the pipeline dropped, each carried from slim
through to the export:

* **Extraction class**, the EFSA digestion class, mapped from a frozen table under
  `inst/extdata/extraction-class/`. Recorded for **51.3%** of target measurements
  (59,372 rows); the rest default to class 3. This is the *recorded* counterpart of
  the aluminium basis the enrichment work **infers** from Fe/Al, and phase 3 tested
  one against the other.
* **Laboratory accreditation**, from the two sources that state it.
* **Fraction provenance** (`frac_basis`), distinguishing a stated sieve or stated
  no-sieve from bulk merely *inferred* from a source's silence. Most "bulk" is the
  latter, and a submitter should be able to tell.
* **Vannmiljø programme codes** as a stated pressure label, frozen under
  `inst/extdata/vannmiljo-programmes/` and read only through `R/vannmiljo-pressure.R`.
* **Fish-farm size**, the nearest farm's licensed biomass and a small/medium/large
  band, carried onto `site`.

**4Demon's sieve is now read from `fraction_range`**, not its matrix code. This is a
correctness fix that made a hidden duplicate visible: the dedup key includes
`frac_class`, so rows mislabelled `sieved63` were compared against the wrong stratum
and their ICES-DOME re-hosts went unrecognised. Merged loses **17** measurements to
this, all on the Belgian shelf in 2007 with byte-identical values; refined loses the
**9** among them that are target elements. Nothing was lost that was not a duplicate.

## Geo-enrichment

* Locations are stamped with **`--partition`**, requiring **seastamp >= 0.16.2**
  (the polar fix is load-bearing at 81.5 lat). Measured over 26,849 refined sites,
  seastamp's error bound is 25% for `--region global`, 3% for `--region auto` and
  **1.32%** for `--partition`. Global is the outlier beyond 10 km, which is exactly
  where the enrichment reference is drawn.

## New analysis

* **Geo-accumulation index (Igeo)**, background step 10. Coverage goes from 9.8% to
  **97.2%** of target measurements, and from 0.4% to **99.4%** within 1 km of a fish
  farm, because Igeo needs no aluminium. The background is the **local** offshore
  median, not a crustal reference: EFSA warns against Turekian and Wedepohl, and
  section 3 of `docs/generation-gaps.md` measured why for this data.
* Igeo is deliberately **not wired into the pristine verdict**. The verdicts stay on
  EF, because the texture confounding Igeo is strong enough in bulk (cobalt rho 0.70)
  that a verdict built on it would be partly a verdict about grain size.
* Igeo is **withheld for selenium and molybdenum**, on the same grounds as their EF:
  over half of each was deleted below the LOQ, so both ends of the ratio are
  truncated and the quotient is not an enrichment.
* TOC normalisation was tested and **rejected**; PLI was measured and **not built**,
  adding no coverage over Igeo.

## Exports

* The flat dataset goes from **31 to 40 columns** and the EFSA table from **58 to
  64**, gaining `fraction_basis`, `dist_to_fish_farm_km`, `fish_farm_mtb_t`,
  `fish_farm_band`, `pressure_class`, `igeo`, `igeo_class` and `igeo_background`.
  Every column an earlier download carried keeps its name and meaning, so an
  existing consumer is unaffected.
* The EFSA `sieve63` field answered `Y` for **31 rows sieved at 90 or 500 µm**,
  which are coarser than 63 µm, not finer. Both `sieve63` and `bulkAnalysis` now
  answer `N` there, and `fraction` carries the actual cutoff.
* A new assertion fails the export if the column dictionary and the written frame
  disagree in either direction. Adding nine columns is precisely how a dictionary
  goes stale, and it drives the site's Download page.
* `export_data(format = "efsa")` is **the pool, not the submission**. EFSA wants
  representative records, so the submission will be a filtered selection of pristine
  rows cut later; the export is a superset, which is why every row keeps its verdict
  columns.

## Decisions recorded

* **D4, normalisability.** An enrichment factor and a pristine verdict exist only
  where aluminium predicts the element, which holds for **CO, CU and ZN in bulk
  alone**. An empty verdict is not a finding of non-pristine, and the dictionary
  now says so.
* **Porewater pH is dropped entirely.** Absent from all five sources, checked at
  raw-file level: the only pH anywhere is 22 ICES rows of *sediment* pH.

## Fixes

* The Igeo step returns its output directory, as `analyze_data()` requires.
* Igeo rounding is now part of the index rather than a display choice, in the shared
  `R/analysis-refined-shared-igeo.R`. Cutting the unrounded value into classes while
  publishing the rounded one had put six molybdenum rows in a class their own printed
  number does not fall in.
* The step's coverage table and its class shares now apply one rule. The table had
  always excluded the withheld elements; the class shares had not, so the step
  published molybdenum and selenium beside a 97.2% figure computed as though they
  were absent.
* The package name is corrected in the three frozen-table lookups.
* `CLAUDE.md` advertised 28 analyses and six background steps; there are **29**
  (6 clean, 13 merged, 10 refined) and **ten**. It now points at
  `analysis_modules()` as the executable answer.
* **The pkgdown site builds again.** Four internal helpers added by the censoring
  and normalisability work (`refined_al_basis`, `refined_on_basis`,
  `refined_censoring_table`, `refined_withheld_elements`) carried roxygen blocks
  without `@noRd`, so they generated `.Rd` files that were absent from the
  reference index, and `build_reference_index()` aborted. They are internal like
  the eight other shared helpers, and are now marked as such.

# multised.engine 0.3.1

Documentation and publishing only: no pipeline code changed, so a rebuild from
this version reproduces exactly what `v0.3.0` did.

## Publishing

* The **pkgdown site is live** at
  <https://seafood-hazards.github.io/multised-engine/>, built and deployed from
  `main` by GitHub Actions. It installs hard dependencies only, since every
  article chunk is `eval = FALSE` and nothing runnable touches `sf` - which would
  otherwise mean building GDAL, GEOS and PROJ to render prose.

## Documentation

* The single Analyses article is **split into one per generation**
  (`analyses-clean`, `analyses-merged`, `analyses-refined`), each shaped like the
  generation articles: what it reads, what it writes, how to check a rebuild, and
  which site it feeds.
* The **five pilot websites** are documented. `docs/websites.md` now covers all
  nine sites, and `vignette("pilot")` gains the publishing procedure: each pilot
  site depends on exactly one `<source>_pilot.sqlite`, taken from its own
  repository's *latest* release, which does not fall back - so every release
  there must carry the database.
* **Pilot geo columns now reproduce.** The stored pilot databases were rebuilt
  with seastamp on 2026-08-07, so a fresh `create_db("pilot", src)` matches them
  including the six location columns. `vignette("pilot")` records what the
  earlier `sf` implementation produced instead, per source; the change that
  mattered was `sea_name` resolving IHO sea areas rather than ocean basins.
  The stored clean and merged databases still hold `region = "global"` values.

# multised.engine 0.3.0

The package gains a public interface. Everything the project does is now behind
three verbs, and the 187 original scripts that implemented it are gone: each was
converted, and each conversion was verified by rebuilding into a temporary
directory and diffing against the stored output before the original was removed.

## Public interface

* **`create_db(generation, source, steps, db_dir, seastamp_dir, seastamp_bin,
  out_dir)`** builds any of the five generations, plus `"aquaculture"` for the
  Norway-only reference database. `source` is required for pilot / slim / clean
  and must be `NULL` for the rest.
* **`analyze_data(generation, module, steps, db_dir, out_dir)`** runs all 25
  analyses: 6 clean, 13 merged, 6 refined. `module = NULL` runs every module for
  the generation.
* **`export_data("refined")`** writes the flat downloadable dataset. It moved out
  of the analysis registry, since it denormalises rather than computing, and
  there is now exactly one public path to it.
* Listing helpers `multised_sources()`, `slim_steps(source)` and
  `analysis_modules(generation)` are executable versions of the documented
  tables.
* Paths are arguments or options: `multised_db_dir()`, `multised_analysis_dir()`,
  `multised_raw_dir()`, `multised_seastamp_dir()`, `multised_seastamp_bin()`.

## Structure

* `R/` is flat. R collates only top-level `R/*.R`, so the previous layout shipped
  197 files that were never loaded, and would have executed at install time if
  they had been.
* The **aquaculture** scripts are converted: `create_db("aquaculture")` builds the
  reference database, and clean gains **step 5** for `dist_to_aquaculture`. This
  was the last thing the original scripts could do that the package could not.
* Thirteen review and export prototypes that were never part of the interface
  moved to `inst/scripts/`.
* Pilot databases are renamed `<source>_pilot.sqlite`, so all three per-source
  generations follow one pattern.
* The seastamp reference tree moved from `data/geoenrich` to `data/seastamp`,
  following the tool's own rename, and the binary can be given explicitly rather
  than found on the `PATH` - which the RStudio console does not inherit.

## Documentation

* A **pkgdown site** with an article per generation, each carrying the expected
  row counts from the stored databases and what a rebuild should and should not
  reproduce.
* README gains the system requirements: the GDAL / GEOS / PROJ / Abseil / libcurl
  packages behind `sf`, and the seastamp CLI.

# multised.engine 0.2.0

First release since `v0.1.3` (2026-05-07), covering two new pipeline
generations and the move to an installable package.

## Pipeline

* **New `merged` generation** (`R/merge/`): unions all five clean databases into
  `multised_merged.sqlite` and removes cross-source duplicates under two rules,
  a value-cluster rule (location, sampling year, depth, element, track, value
  within 1%) and a provenance rule for Vannmiljø's re-hosted Mareano dataset.
  Adds a distributional `outlier_flag` complementing the physical `range_flag`.
* **New `refined` generation** (`R/refine/`): a mart cut from the merged
  database for the pristine and background work, with a single `measurement`
  table, a slim normaliser table, baked ratios, and aquaculture and
  repeat-site links.
* Slim steps 13-15 across the sources that need them: source-native flags
  (`src_flag`), grain-size correction (`value_std_corr` / `gs_corr`), and the
  derived fines fraction (`fines_lt63` / `fines_basis`).

## Analyses

* Background and pristine-classification suite on the refined database: plain,
  grain-size-normalised, pressure-based, enrichment-factor and
  distribution-mixture backgrounds, plus the pristine synthesis.
* Merged-database analyses: clustering (facies, hotspots, regions), site-years,
  depth profiles, enrichment, data-category summaries and outlier review.
* Downloadable flat dataset export.

## Packaging

* The package is now installable from GitHub. Real `DESCRIPTION` metadata, an
  MIT licence, a `README`, and a build manifest that keeps the external data
  symlink and the `renv` profile out of the tarball.
* Renamed the project from `sedimenter` to `multised.engine`.
* Geo-enrichment now calls the `seastamp` CLI, renamed upstream from
  `geoenrich`.

## Documentation

* `CLAUDE.md` cut roughly in half, with the detail moved into `docs/`; new
  `docs/analysis.md` and `docs/websites.md`.

## Known limitations

* The installed package exports no functions yet. All pipeline code lives in
  subdirectories of `R/`, which R does not collate, so the scripts ship in the
  tarball but are not loaded. The `create_db()` / `analyze_data()` interface
  that will address this is in development.


# multised.engine 0.1.3 and earlier

Released as plain git tags without notes. See the commit history.
