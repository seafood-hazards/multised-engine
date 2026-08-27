# The summary generation

The sixth and outermost layer of the project: a short, diagram-led site that
states what the work found, for a reader who will not open the refined site.

Live at <https://seafood-hazards.github.io/multised-summary/>, built from
`../multised-summary`.

## What it is, and what it is not

It is **not a pipeline generation**. There is no `multised_summary.sqlite`, no
`R/summary-*.R` and no `create_db("summary")`. Adding one was considered and
rejected: a sixth database would restate the refined mart rather than derive
anything from it, and every generation so far exists because it changes the data.
This one changes only the presentation.

What it is instead:

| Piece | Where |
|-------|-------|
| One analysis module | `R/analysis-refined-summary.R`, reached by `analyze_data("refined", module = "summary")` |
| Its outputs | `data/analysis/summary/*.csv` (14 files) |
| The site | `../multised-summary`, a sibling Quarto repo like the other nine |

The generation token stays `refined`, because that is the database being read.
`summary` is the module, and the site takes its name from the module.

If the EFSA submission later needs a filtered database of its own, that is a
seventh thing and it should be a real generation with its own `create_db()`
branch. Do not grow this module into one.

## The rule the site is built on

**No page computes anything.** Every figure, table and number is read from a CSV
written by the module. The two refined summary pages already worked this way; here
it is the whole site.

The consequence is the thing to remember when editing: *a number the site needs
that no CSV holds belongs in `R/analysis-refined-summary.R`, not typed into a
page.* Four numbers were typed into pages during the first build (the pipeline
funnel, the classifiability-by-band chart, the four-controls table and the zinc
comparison) and all four were moved into the module before it shipped. A typed
number is a number that will be wrong after the next rebuild and will not announce
itself.

The one exception is prose descriptions of a file or a method, which are text
rather than results. The Downloads page describes each released CSV in prose, and
guards the list by checking it against `_scripts/release-assets.txt` at render, so
a release carrying an undescribed file fails the build instead of shipping.

## What the module derives itself

Everything about **extent**, which no background CSV holds:

- per element x fraction, and separately per element: measurements, sites,
  datasets, sources, year range;
- per source: what each of the five contributes, over the same filtered rows the
  rest of the site reports;
- per pipeline stage: the funnel, counted by opening each database rather than
  remembered;
- per site and per 0.1 degree cell: the map layers.

Everything about **verdicts** is read from the `background` module and only
reshaped. The module derives no background, no enrichment factor and no pristine
flag of its own, and it must not start to.

### One counted population

Every figure outside the funnel counts the same rows: `value_std > 0`, no
`outlier_flag`, and one of the three reported fractions. That is 115 231 of the
115 811 rows in the refined database. The funnel carries the difference as its
last rung ("analysed") rather than leaving two totals on the site with no
explanation, which is what happened on the first build: the home page showed
115 397 in one figure and 115 811 in the diagram beside it.

Element-level counts are carried as their own columns (`n_elem`, `n_sites_elem`,
`n_sources_elem`, `year_*_elem`). **Do not add up the per-fraction counts.** A
site measured in bulk and in two sieved fractions is one site, and summing the
rows reported 25 347 copper sites where there are 24 908.

### Withholding propagates here

The two withholding rules (D1 below-LOQ censoring, D4 normalisability) are read
from their frozen tables, never re-derived, so this site cannot disagree with the
pages it summarises. Both have bitten in this module already:

- `summary_background.csv` marked molybdenum and selenium `reliable`, so the
  Background Identification page printed a molybdenum background two paragraphs
  above the sentence saying it has none. `reliable` now includes `!withheld`.
- `summary_map_sites.csv` carried an Igeo for molybdenum, because the Igeo step
  still computes a `B` for it. That `B` is cut from a distribution whose low end
  was deleted, so the map would have offered a colour scale with no meaning. Igeo
  is now `NA` for a withheld element, and the map hides the control.

The general form: **a rule that withholds a verdict has to be applied everywhere
the verdict could surface**, including derived columns and map layers, not only in
the table where it was decided.

## Outputs

Written to `data/analysis/summary/`, all listed in the site's
`_scripts/release-assets.txt`.

| File | Holds |
|------|-------|
| `summary_elements.csv` | per element x fraction: extent, the two withholding flags, and a plain-English note |
| `summary_background.csv` | long: every background estimate from every method, with `reliable` |
| `summary_verdicts.csv` | classifiable share, pristine share (both rules), Igeo class 0 share |
| `summary_coverage.csv` | the classifiability gap by distance band, on both axes |
| `summary_censoring.csv` | below-LOQ shares per element and source |
| `summary_pressure.csv` | long: the distance-band gradient, as concentration and as texture-matched Igeo |
| `summary_gradient.csv` | near-vs-far enrichment, raw and with stated pressure removed |
| `summary_controls.csv` | the four independent controls side by side |
| `summary_sources.csv` | what each of the five sources contributes |
| `summary_flow.csv` | the pilot-to-reported funnel |
| `summary_map_sites.csv` | per site x element x fraction: the full-resolution layer |
| `summary_map_grid.csv` | the same on a 0.1 degree grid: what the site draws |
| `summary_meta.csv` | provenance: which database, built when, under which rules |

### Why the map is gridded

Copper has 21 726 bulk sites. Twenty thousand overlapping markers is not a summary,
and the page is claiming a regional picture, so it should draw one. The grid is
0.1 degree (roughly 11 km), which takes copper to 3 664 cells: small enough to
embed in the page with `ojs_define()` and read at a glance. The site-level file
stays published for anyone who wants the finer layer.

Cells are summaries, and the page says so: a cell holding both clean and enriched
sites shows the middle of them, so the per-measurement counts on the refined
analysis pages remain the authoritative ones.

## The site

Four sections, as the brief asked: Home, Methods (four pages), Results (a coverage
matrix plus one page per element), Downloads.

Shared machinery, so the seven element pages stay in step:

- `_setup.qmd` loads every CSV and defines the display helpers
  (`capability_note()`, `chip()`, `keyfig()`, `sym_display`).
- `_element-body.qmd` is the whole element page. Each `element-<sym>.qmd` sets
  `SYM` and includes it. **Edit the body, never one element page**, or they drift.
- Sections appear and disappear from flags, not from per-page edits: a withheld
  element gets a "Why this element is withheld" section and no distance chart, an
  element below the reporting threshold gets "Why there is no result", and the map
  hides its Igeo control where there is no Igeo.

### Element pages are deliberately unequal

Three elements carry a full page, one carries background only, and three are close
to empty. That is the finding, so the thin pages say plainly what cannot be said
and why, and are not padded out to match. Filling them with source coverage and
censoring detail until they looked as substantial as copper's was considered and
rejected: it would imply more is known about selenium than is.

### House style

- No em-dashes, as on the other four generation sites.
- Plain English, short paragraphs, and a diagram or table wherever one will carry
  the point instead of a paragraph.
- Every page ends with links to the refined site for the workings. This site is
  the answer; that one is the evidence.

## Publishing

The same pattern as the other sites, with the same trap. CI renders from
`releases/latest/download/`, which does not fall back, so **upload the release
assets before pushing `main`**:

```bash
_scripts/publish-release.sh vX.Y.Z     # uploads everything in the manifest
git push origin main                   # then let CI render
```

`_scripts/release-assets.txt` is the single source of truth: `publish-release.sh`
uploads what it lists and `download_resources.R` fetches the same list from it.
They are never allowed to become two lists. That is not a style preference, it is
the fix for a render failure on the refined site, where the downloader kept its own
copy of the file list and 404'd on files that were sitting on the release.

## Status

Built and rendering. Not yet published: the repository does not exist on GitHub
yet, so there is no release and no Pages deployment.

The site says on its home page and its Downloads page that it is not the final
submission. That stays true until the pristine-filtered submission subset exists;
see [efsa-submission.md](efsa-submission.md).
