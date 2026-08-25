# multised.engine (development version)

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
