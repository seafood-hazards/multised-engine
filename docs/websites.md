# Websites

Four Quarto sites present the pipeline, each published to GitHub Pages. **All
four live in sibling repositories, not inside this project** (one source of
truth; do not re-create a copy under `multised-engine/`). Each publishes on push
to `main` via a GitHub Action whose pre-render script downloads the databases and
analysis CSVs from that repo's own release (`v0.1.0`); nothing large is
committed.

| Site             | Repo (`seafood-hazards/…`) | Sibling path        | Presents                                  |
|------------------|----------------------------|---------------------|-------------------------------------------|
| multised-slim    | `multised-slim`            | `../multised-slim`  | how the slim schema, QC flagging and clean DBs are built |
| multised-clean   | `multised-clean`           | `../multised-clean` | analyses on the clean DBs + aquaculture + merge build steps |
| multised-merged  | `multised-merged`          | `../multised-merged`| the merged DB: schema, interactive explorers, outlier flagging |
| multised-refined | `multised-refined`         | `../multised-refined`| the refined DB: schema, background/pristine analyses, downloads |

`multised-clean`, `multised-merged` and `multised-refined` use gitflow
(`main`/`develop`).

**No em-dashes in any of these sites' pages.** Use commas, colons, or
parentheses instead.

## Local rendering

Render against live pipeline output by symlinking the data area into the sibling
repo first (both symlinks are gitignored, and the CI download is skip-if-exists,
so a working local render can hide a missing release asset):

```bash
ln -s "$(pwd)/data/db" ../multised-slim/data/db
ln -s "$(pwd)/data"    ../multised-clean/data
```

`multised-merged` and `multised-refined` need no symlink; they download their
DBs at pre-render.

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
`_db-setup.qmd`. Pages: DB Design (`db-schema-refined`, `refined-tables`), the
six Background analyses (`background`, `-gsnorm`, `-mixture`, `-pressure`,
`-map`, `-ef`, `-pristine`), `enrichment-map`, and Downloads
(`download-database`, `download-dataset`).
