# Websites

Nine Quarto sites present the pipeline, each published to GitHub Pages. **All
nine live in sibling repositories, not inside this project** (one source of
truth; do not re-create a copy under `multised-engine/`). Each publishes on push
to `main` via a GitHub Action whose pre-render script downloads what it needs
from that repo's own release; nothing large is committed.

They split into two families that work differently enough to be worth keeping
apart.

## The five pilot sites

One per data source, documenting that provider's own schema and the corrections
applied to it. This is the only generation split per source, because it is the
stage where the five providers still look like five different databases.

| Site | Repo (`seafood-hazards/…`) | Sibling path | Database | Version |
|---|---|---|---|---|
| Mareano   | `mareano-pilot`   | `../mareano-pilot`   | `mareano_pilot.sqlite`   | v0.1.28 |
| Vannmiljø | `vannmiljo-pilot` | `../vannmiljo-pilot` | `vannmiljo_pilot.sqlite` | v0.1.23 |
| ICES-DOME | `ices-dome-pilot` | `../ices-dome-pilot` | `ices_dome_pilot.sqlite` | v0.1.19 |
| MUDAB     | `mudab-pilot`     | `../mudab-pilot`     | `mudab_pilot.sqlite`     | v0.1.11 |
| 4Demon    | `4demon-pilot`    | `../4demon-pilot`    | `4demon_pilot.sqlite`    | v0.1.7  |

Site versions are independent of each other and of this package; the table
records where each stood in August 2026.

### The contract, identical across all five

Since August 2026 every pilot site depends on **exactly one file**: its
`<source>_pilot.sqlite`, built here by `create_db("pilot", source)` and published
as an asset on that repo's own release. Nothing else is downloaded, and no page
reads a second data file.

Three rules follow, and they are what breaks a site when missed:

- **The database comes from `releases/latest/download/`**, not a pinned tag. That
  URL does not fall back, so **every release must carry the database as an
  asset** or the next CI render 404s.
- **Publish the release before pushing `main`.** Push the tag, `gh release
  create` with the file, then push `main`; the reverse order races the deploy
  against the upload.
- **Bump the `cacheKey` in `_db-setup.qmd` whenever the database content
  changes.** stratum-sqlite caches the file in the browser under that key, and a
  stale cache surfaces as "no such column".

Each repo keeps a slim `CLAUDE.md` naming those rules, with the detail in its own
`docs/database.md` (schema, row counts, how a page queries it) and
`docs/site.md` (stack, pages, gitflow, the release procedure). Read the relevant
one before changing a pilot site.

The home page of each carries `_generations.qmd`, a shared block listing the five
generations and linking to all nine sites. **It is duplicated across the five
repos** and differs only in which row reads "this site", so a change to it has to
be copied to the other four.

### What each site does not have

The pilot generation no longer exports a dataset file (`export_data()` is
refined-only, and the old per-source dumps are legacy prototypes in
`inst/scripts/pilot/`), so the Export to Tabular File pages were removed. The DB
Schema (Slim) pages and slim database downloads went with them: that schema
belongs to `multised-slim`. The remaining EFSA Format and EFSA Submission pages
are static documentation of the submission column mapping, not of a file this
project produces.

### Per-source quirks

| Site | Worth knowing |
|---|---|
| Mareano | 6 tables. The one source naming the nearest-country column `country`; the others use `est_country` |
| Vannmiljø | 10 tables. Raw positions are UTM33, reprojected with `sf`. `sediment-fractions.qmd` documents how overlapping raw grain-size parameters are resolved |
| ICES-DOME | 10 tables, the largest database. `code_lookup` resolves the ICES code vocabularies, and `sediment-fractions.qmd` is a *Grain Size Codes* page cut from it, not a fractions page |
| MUDAB | 10 tables. **The geo columns are on `survey`, not `station`** (only source where that holds), and raw field names are German: `data-preparation.qmd` has the translations |
| 4Demon | 6 tables, the smallest. The only pilot fact table with source-native quality flags (which slim step 13 folds into `src_flag`), and no grain size or organic carbon at all |

## The four generation sites

| Site             | Repo (`seafood-hazards/…`) | Sibling path        | Presents                                  |
|------------------|----------------------------|---------------------|-------------------------------------------|
| multised-slim    | `multised-slim`            | `../multised-slim`  | how the slim schema, QC flagging and clean DBs are built |
| multised-clean   | `multised-clean`           | `../multised-clean` | analyses on the clean DBs + aquaculture + merge build steps |
| multised-merged  | `multised-merged`          | `../multised-merged`| the merged DB: schema, interactive explorers, outlier flagging |
| multised-refined | `multised-refined`         | `../multised-refined`| the refined DB: schema, background/pristine analyses, downloads |

These still pin their release tag (`v0.1.0`) rather than resolving `latest`, and
several read analysis CSVs as well as databases, so they are not interchangeable
with the pilot contract above.

`multised-clean`, `multised-merged` and `multised-refined` use gitflow
(`main`/`develop`); so do all five pilot repos.

**No em-dashes in these four sites' pages.** Use commas, colons, or parentheses
instead. Some older pilot pages predate the rule and still contain them; new
pilot text follows it.

## Local rendering

Render against live pipeline output by symlinking the data area into the sibling
repo first (both symlinks are gitignored, and the CI download is skip-if-exists,
so a working local render can hide a missing release asset):

```bash
ln -s "$(pwd)/data/db" ../multised-slim/data/db
ln -s "$(pwd)/data"    ../multised-clean/data
```

`multised-merged` and `multised-refined` need no symlink; they download their
DBs at pre-render. Neither do the pilot sites, but their pre-render skips the
download if the file is already there, so **after rebuilding a pilot database,
delete the local copy in the site repo** or the render keeps using the old one.

> These symlinks point at the absolute path of this project, so **moving or
> renaming the project directory breaks them silently** (they are gitignored, so
> `git status` says nothing). Re-point them after any move.

## Per-site notes

### multised-slim

Documents the slim schema, the QC/marking steps, and the clean build. Reads the
flagged slim and clean databases. That repo's `README.md` has the full build /
publish / reproduce details (CI workflow, DB download, release-tag bump).

### multised-clean

Analyses performed *on* the clean databases (grain size, Fe/Al normalisation,
organic carbon, depth/coast, sampling year, a summary, the Aquaculture pages),
plus site-locations and aquaculture documentation. Also carries the merge
**build** pages (union / dedup / finalise / retention).

Reads the per-source analysis outputs written by `analyze_data("clean")` to
`data/analysis/` plus the clean and `aquaculture_no.sqlite` databases.
`_scripts/download-data.R` lists the release manifest. **Adding a page that reads
a new output means uploading that asset to the release before pushing `main`, or
the CI download fails.**

### multised-merged

Static **DB Design** (schema) pages plus an **Explore** menu of interactive
viewers and maps (Merged / Aquaculture Tables, and the Element / Location /
Grain Size / Aquaculture maps), and an **Analyses → Outlier Flagging** page
reading the `merge_outlier_*` CSVs from the release. It also carries the
DB-creation pages for the refined schema.

Unlike the slim/clean sites the Explore pages run **client-side**: the SQLite
databases load in the browser via WebAssembly (sql.js + stratum-sqlite,
committed under `libs/sqljs/`) and are queried with Observable JS, **not** R at
render. `download_resources.R` (pre-render) downloads the two DBs and the libs;
`header.html` sets the in-browser DB paths; a page includes `_db-setup.qmd`
(opens the merged DB as `db`) or `_db-setup-aqua.qmd` (aquaculture as `db_aqua`).
The five pilot sites use the same mechanism with a single database.

Gotchas:

- **One DB per page.** Opening both on one page fails, which is why the
  aquaculture map is its own page.
- **stratum-sqlite caches the DB in the browser** keyed by the `cacheKey` in
  `_db-setup*.qmd`. Whenever a DB's *content* changes (e.g. a new column,
  re-uploaded to the same `v0.1.0` asset), **bump that `cacheKey`** (e.g. to the
  new site version) or returning browsers keep serving the stale cached copy and
  queries hit "no such column".
- OJS: object literals assigned to a name need parens (`X = ({...})`), and
  non-ASCII (µ) in OJS string literals can break the parser (use `um`).

### multised-refined

The refined DB and its pristine/background work. One database
(`multised_refined.sqlite`, with aquaculture folded in), so pages share a single
`_db-setup.qmd`. Pages: DB Design (`db-schema-refined`, `refined-tables`);
**Background** (`background`, `-gsnorm`, `-mixture`, `-pressure`, `-map`,
`-summary`); **Enrichment** (`background-ef`, `background-pristine`,
`enrichment-map`, `enrichment-summary`); `method-revisions`; EFSA Submission
(`efsa-format`, `efsa-submission`, and their `-v2` pair); and Downloads
(`download-database`, `download-dataset`).

The two `-summary` pages are synthesis, not analysis: they recompute nothing and
read only the CSVs the analysis pages write, so they cannot disagree with their
sources. Keep it that way. A number a summary needs that no CSV holds belongs in
the pipeline, not typed into the page.
