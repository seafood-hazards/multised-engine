# Analyses (`R/analysis/`)

Analyses run *on* a finished database and write tidy CSVs (and some plots) to
`data/analysis/<module>/` (gitignored). They never modify a pipeline DB. Each
output is consumed by a page on one of the Quarto sites (see
[websites.md](websites.md)), so **adding an analysis output means uploading it to
that site repo's release before pushing `main`**, or the CI pre-render download
fails. A local render hides this, because the local data symlink is
skip-if-exists.

## Filename convention

`R/analysis/<module>/<NN>_<generation>_<name>.R`

The `<generation>` token says which DB the script reads, and therefore which site
consumes its output:

| Token      | Reads                                   | Feeds site       |
|------------|-----------------------------------------|------------------|
| `clean`    | `data/db/<source>_clean.sqlite` (per source) | multised-clean   |
| `merged`   | `data/db/multised_merged.sqlite`        | multised-merged  |
| `refined`  | `data/db/multised_refined.sqlite`       | multised-refined |

A module can hold more than one generation of the same analysis (e.g.
`grainsize/01_clean_grainsize.R` and `grainsize/01_merged_grainsize.R`), which is
why the token exists rather than the module name alone.

## Modules

### Clean generation (per source, feeds multised-clean)

| Module          | Script                       | What it covers                     |
|-----------------|------------------------------|------------------------------------|
| `grainsize`     | `01_clean_grainsize.R`       | grain size / fines coverage        |
| `normalisation` | `01_clean_normalisation.R`   | Fe/Al normalisation                |
| `organic`       | `01_clean_organic.R`         | organic carbon                     |
| `spatial`       | `01_clean_spatial.R`         | depth / distance to coast          |
| `temporal`      | `01_clean_temporal.R`        | sampling year                      |
| `uncertainty`   | `01_clean_uncertainty.R`     | measurement uncertainty            |

### Merged generation (feeds multised-merged)

| Module           | Script                        | What it covers                                    |
|------------------|-------------------------------|---------------------------------------------------|
| `merged_summary` | `01_merged_data_summary.R`    | the **Data Categories** page: three count CSVs (`merged_coverage_fraction`, `merged_bulk_factors`, `merged_layering`) classifying every target/reference/organic measurement by fraction (bulk / sieved63 / sieved20), covariate availability (grain size / Fe / Al / organic carbon, from the subsample exist flags), and layering (single vs multi-layer/core, `event.n_layers`) |
| `grainsize`      | `01_merged_grainsize.R`       | grain size on the merged DB                       |
| `normalisation`  | `01_merged_normalisation.R`   | Fe/Al normalisation                               |
| `organic`        | `01_merged_organic.R`         | organic carbon                                    |
| `spatial`        | `01_merged_spatial.R`         | depth / distance to coast                         |
| `temporal`       | `01_merged_temporal.R`        | sampling year                                     |
| `depthprofile`   | `01_merged_depthprofile.R`    | down-core depth profiles                          |
| `enrichment`     | `01_merged_enrichment.R`      | enrichment                                        |
| `clustering`     | `01_merged_clustering.R`      | Facies (K-means chemistry), Hotspots (DBSCAN geography), Regions (both, weighted) |
| `hotspots`       | `01_merged_hotspots.R`        | geographic hotspots                               |
| `regions`        | `01_merged_regions.R`         | regional grouping                                 |
| `siteyears`      | `01_merged_siteyears.R`       | location-controlled temporal trend (2dp grid, within-cell) |
| `outlier_review` | `01_merged_outlier_review.R`  | **review prototype, not a site input.** Settled the distributional `outlier_flag` rule now applied by merge step `04_mark_outliers.R`; writes candidate/summary CSVs + distribution plots for eyeballing |

### Refined generation (feeds multised-refined)

| Module       | Script                                | What it covers                          |
|--------------|---------------------------------------|-----------------------------------------|
| `background` | `01_refined_background.R`              | background / pristine baseline          |
| `background` | `02_refined_background_gsnorm.R`       | grain-size-normalised background        |
| `background` | `03_refined_background_pressure.R`     | pressure-based background               |
| `background` | `04_refined_background_ef.R`           | enrichment factor                       |
| `background` | `05_refined_background_mixture.R`      | distribution-mixture background         |
| `background` | `06_refined_pristine.R`                | pristine-classification synthesis       |
| `download`   | `01_refined_dataset.R`                 | downloadable flat dataset export        |

The `background` module is a single ordered suite: each script builds on the
previous one, and the six map onto the six background pages of multised-refined.
