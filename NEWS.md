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
