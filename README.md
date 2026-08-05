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
| 1 | pilot      | `pilot_<source>.sqlite`     | parse raw source files (table structure differs per source)   |
| 2 | slim       | `<source>_slim.sqlite`      | reshape into a shared 7-table schema, then flag quality, duplicates, detection limits and derive standardised values |
| 3 | clean      | `<source>_clean.sqlite`     | apply the slim flags; geo-enrich every site                   |
| 4 | merged     | `multised_merged.sqlite`    | union all five sources, remove cross-source duplicates        |
| 5 | refined    | `multised_refined.sqlite`   | a mart cut from the merged database for background / pristine work |

## Installation

```r
# install.packages("remotes")
remotes::install_github("seafood-hazards/multised-engine")
```

The package installs the pipeline code only. The **databases are not
distributed with it**: they are built from the external sources, or downloaded
from the releases of the companion sites below.

Some analysis modules need optional spatial packages (`sf`, `leaflet`,
`rnaturalearth`, `giscoR`). Install them alongside if you intend to run those:

```r
remotes::install_github("seafood-hazards/multised-engine", dependencies = TRUE)
```

## Status

The programmatic interface (`create_db()` and `analyze_data()`, selecting a
pipeline generation plus its arguments) is **in development**. Until it lands,
the pipeline runs as ordered scripts under `R/`, `source()`d from the project
root in the documented order, since they use relative paths such as
`./data/db/…`.

## Companion sites

Four Quarto sites present the pipeline and its analyses, each built from its own
repository and published to GitHub Pages:

| Site             | Presents                                                        |
|------------------|-----------------------------------------------------------------|
| multised-slim    | how the slim schema, the QC flagging and the clean databases are built |
| multised-clean   | analyses on the clean databases, aquaculture, and the merge build steps |
| multised-merged  | the merged database: schema, interactive explorers, outlier flagging |
| multised-refined | the refined database: background and pristine-classification analyses |

## Documentation

Specifications for each stage live under `docs/`: `slim-pipeline.md`,
`clean-pipeline.md`, `merge-pipeline.md`, `refined-pipeline.md`, plus
`analysis.md` (the analysis modules) and `websites.md` (the companion sites).

## Licence

MIT. See [LICENSE.md](LICENSE.md).
