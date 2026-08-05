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
rather than computing, so it lives behind `export_data("refined")`. It still
writes to `<out_dir>/download/`, the path the multised-refined pre-render
expects. See [the export section](#export).

## Layout

Package code is flat (R collates only top-level `R/*.R`):

`R/analysis-<generation>-<name>.R`, one function `analysis_<generation>_<name>()`

The original script tree `R/analysis/<module>/<NN>_<generation>_<name>.R` is kept
until the outputs have been validated by hand, and is excluded from the tarball.

The `<generation>` token says which DB is read, and therefore which site
consumes the output:

| Token     | Reads                                        | Feeds site |
|-----------|----------------------------------------------|------------------|
| `clean`   | `data/db/<source>_clean.sqlite` (per source) | multised-clean |
| `merged`  | `data/db/multised_merged.sqlite`             | multised-merged |
| `refined` | `data/db/multised_refined.sqlite`            | multised-refined |

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

### Refined generation (feeds multised-refined)

| Module       | Function                                 | What it covers |
|--------------|------------------------------------------|-----------------------------------|
| `background` | `analysis_refined_background()`          | background / pristine baseline |
| `background` | `analysis_refined_background_gsnorm()`   | grain-size-normalised background |
| `background` | `analysis_refined_background_pressure()` | pressure-based background |
| `background` | `analysis_refined_background_ef()`       | enrichment factor |
| `background` | `analysis_refined_background_mixture()`  | distribution-mixture background |
| `background` | `analysis_refined_pristine()`            | pristine-classification synthesis |

The `background` module is a single ordered suite: each script builds on the
previous one, and the six map onto the six background pages of multised-refined.

## Export

```r
export_data(generation = "refined", source = NULL,
            db_dir = multised_db_dir(),
            out_dir = multised_analysis_dir(), verbose = TRUE)
```

| Generation | Function                   | Writes                                                          |
|------------|----------------------------|-----------------------------------------------------------------|
| `refined`  | `export_refined_dataset()` | `download/multised_refined_dataset.tsv.gz` + `refined_dataset_dictionary.csv` |

One flat row per target measurement, plus a column dictionary that drives the
Dataset Download page. Only the refined generation has an export; the five
`R/pilot/<source>/07_create_data_frame.R` scripts are legacy per-source review
dumps for the retired pilot sites and are not part of the interface.
