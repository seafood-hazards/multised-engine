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
