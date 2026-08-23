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
| `background` | `analysis_refined_pressure_controls()`   | controls on the near-cage pressure gradient (time alignment, municipality matching) |
| `background` | `analysis_refined_regression()`          | regression normalisation as a check on the ratio, and whether Al predicts each metal |
| `background` | `analysis_refined_method_changes()`      | pre/post comparison for the Method Revisions page |

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

Step 8 also decides **which groups get a verdict at all** (D4). It fits `metal ~ a + b * Al` on the same offshore
reference the EF uses, so the two are comparable, and answers two questions the EF
cannot ask about itself: whether the intercept the ratio assumes away is really
zero, and whether aluminium predicts the metal at all. The second turned out to
matter more: R2 is about 0.5 for Co, Cu and Zn in bulk and under 0.1 for
everything else, sieved fractions included. Those three groups are therefore the
only ones the EF and pristine steps classify. The rule itself is frozen in
`inst/extdata/normalisability/` and read through
`R/analysis-refined-shared-normalisability.R`, because steps 4 and 6 consume it
and run first; step 8 recomputes it and warns if the frozen table has gone stale.

Step 9 derives nothing of its own: it reads the frozen pre-revision baseline in
`inst/extdata/method-baseline/` alongside what the earlier steps have just
written, so the Method Revisions page shows generated numbers rather than typed
ones. It must run last.

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
`inst/scripts/pilot/<source>_07_create_data_frame.R` scripts are legacy
per-source review dumps for the retired pilot sites and are not part of the
interface.

**25 columns.** Sixteen describe the measurement (location, year, layer,
element, fraction, value, the Fe / Al / organic normalisers, the fines, the two
distances, `outlier_flag`). The other nine are the verdicts, added by
`add_background_flags()`:

| Column | Is |
|---|---|
| `ef` | the enrichment factor, `ratio_al / bg_ratio_al` |
| `classifiable` | whether an EF exists, so a pristine verdict is possible |
| `pristine_ef` | `EF < 1`, the permissive rule |
| `pristine_strict` | `EF < 1` and below the mixture threshold and below the offshore P90 |
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
