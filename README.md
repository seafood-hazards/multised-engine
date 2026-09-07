# multised.engine

<!-- badges: start -->
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

R code that assembles a database of marine-sediment trace-element measurements
from five external data sources, harmonises them into a common schema, and
progressively quality-controls the result.

The seven target measurands are the trace elements **Co, Cu, I, Mn, Mo, Se and
Zn**, supported by the normalisers **Fe** and **Al**, organic carbon, and
grain-size composition.

## Data sources

| Key         | Source     | Coverage                                      |
|-------------|------------|-----------------------------------------------|
| `mareano`   | Mareano    | Norway / IMR cruises                          |
| `vannmiljo` | Vannmiljø  | Norway                                        |
| `ices-dome` | ICES-DOME  | International; rich sediment-composition data |
| `mudab`     | MUDAB      | Germany (national)                            |
| `4demon`    | 4Demon     | Belgium (national; Baltic / North Sea)        |

## Pipeline generations

Data moves through five generations. The first three produce one SQLite database
**per source**; the last two are single cross-source databases.

| # | Generation | Output                      | What it does                                                  |
|---|------------|-----------------------------|---------------------------------------------------------------|
| 1 | pilot      | `<source>_pilot.sqlite`     | parse raw source files (table structure differs per source)   |
| 2 | slim       | `<source>_slim.sqlite`      | reshape into a shared 7-table schema, then flag quality, duplicates, detection limits and derive standardised values |
| 3 | clean      | `<source>_clean.sqlite`     | apply the slim flags; geo-enrich every site                   |
| 4 | merged     | `multised_merged.sqlite`    | union all five sources, remove cross-source duplicates        |
| 5 | refined    | `multised_refined.sqlite`   | a mart cut from the merged database for background / pristine work |

A sixth **summary** layer sits over the refined results, but it is not a
generation: it derives no data and has no database of its own. It is one analysis
module (`analyze_data("refined", module = "summary")`) plus the plain-English
site it feeds, `multised-summary`. See
[docs/summary-site.md](docs/summary-site.md).

## Installation

```r
# install.packages("remotes")
remotes::install_github("seafood-hazards/multised-engine")
```

The package installs the pipeline code only. The **databases are not
distributed with it**: they are built from the external sources, or downloaded
from the releases of the companion sites below.

Some steps need suggested packages: `readxl` and `sf` (the Mareano and Vannmiljø
parsers), `ggplot2`, `cowplot`, `ggpubr`, `viridis` and `cluster` (plotting and
clustering analyses). Each says so by name if it is missing, so you can install
only what you use — or take them all up front:

```r
remotes::install_github("seafood-hazards/multised-engine", dependencies = TRUE)
```

### System requirements

Two dependencies are not R packages.

**System libraries.** `sf` and its dependencies build against GDAL, GEOS, PROJ
and udunits; `s2` needs Abseil and `curl` needs libcurl. On Debian / Ubuntu:

```bash
sudo apt install -y libgdal-dev libgeos-dev libproj-dev libudunits2-dev \
                    libabsl-dev libcurl4-openssl-dev
```

```bash
brew install gdal geos proj udunits abseil curl      # macOS
```

`renv::restore()` reports which of these are missing before it starts, and
`renv::sysreqs()` lists them per package. A common failure is an `sf` that
installs but will not load: that means the libraries arrived after `sf` did, so
rebuild it with `renv::install("sf", rebuild = TRUE)`.

**The seastamp CLI**, for the two geo steps (pilot step 4, clean step 4), from
[AIQC-Hub/seastamp](https://github.com/AIQC-Hub/seastamp), plus its reference
datasets (see [docs/clean-pipeline.md](docs/clean-pipeline.md)). Put it on the
`PATH`, or point at it with `options(multised.seastamp_bin = "/path/to/seastamp")`
— the RStudio console does not inherit the login shell's `PATH`. Skip those two
steps where it is not installed: `create_db("pilot", src, steps = c(1, 5))`,
`create_db("clean", src, steps = 1:3)`.

## Status

Three public verbs cover the whole project:

```r
create_db(generation, source = NULL, steps = NULL)    # all five generations
analyze_data(generation, module = NULL, steps = NULL) # all 30 analyses
export_data("refined", format = "dataset")            # flat TSV + dictionary
```

The 30 analyses are 6 on the clean databases, 13 on the merged one and 11 on the
refined one; `analysis_modules(generation)` is the live list. The last refined
module, `summary`, assembles what the others wrote into the tables the
multised-summary site draws, so it runs after them.

The package is flat: R collates only top-level `R/*.R`. The original script
trees were removed at v0.3.0 after every generation and analysis had been
validated by hand; the review and export prototypes that were never part of the
interface are in `inst/scripts/`.

## Companion sites

Ten Quarto sites present the pipeline and its analyses, each built from its own
repository and published to GitHub Pages. Five document one data source each at
the pilot stage (`mareano-pilot`, `vannmiljo-pilot`, `ices-dome-pilot`,
`mudab-pilot`, `4demon-pilot`); the other five follow the data outwards:

| Site             | Presents                                                        |
|------------------|-----------------------------------------------------------------|
| multised-slim    | how the slim schema, the QC flagging and the clean databases are built |
| multised-clean   | analyses on the clean databases, aquaculture, and the merge build steps |
| multised-merged  | the merged database: schema, interactive explorers, outlier flagging |
| multised-refined | the refined database: background and pristine-classification analyses |
| multised-summary | the plain-English answer over the refined results: what was found, per element |

multised-summary is the outermost layer and the only one written for a reader who
will not open the analysis sites. It computes nothing: every number on it is read
from a CSV written by the `summary` module.

## Documentation

Specifications for each stage live under `docs/`: `slim-pipeline.md`,
`clean-pipeline.md`, `merge-pipeline.md`, `refined-pipeline.md`, plus
`analysis.md` (the analysis modules), `summary-site.md` (the summary layer) and
`websites.md` (the ten companion sites).

## Licence

MIT. See [LICENSE.md](LICENSE.md).
