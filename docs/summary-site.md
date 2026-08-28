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
| Its outputs | `data/analysis/summary/*.csv` (13 files) |
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
- The element map was still *coloured* by median concentration for molybdenum and
  selenium, the two withheld elements. Every other concentration statistic is
  suppressed on those two pages (they carry four sections: extent, why it is
  withheld, and where the samples are), so the colour scale would have been the
  only place on the site publishing a molybdenum concentration, and it would have
  published it as the median of the rows that cleared the detection limit: the
  upper tail the page above it warns against. Their maps now draw every cell in
  one colour, and the legend says why.

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
| `summary_map_grid.csv` | the same on a 0.1 degree grid: what the site draws, including the per-cell pristine class and the site counts behind it |
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

The map opens on what it is drawing, not on a fixed window: it fits the extent of
the cells of that element and fraction, capped at zoom 6 so iodine's eleven sites do
not open at street level and floored at zoom 3, which is what the refined site's
maps use. A reset button restores that view, and tiles come from OpenStreetMap:
CARTO's free basemaps now stamp "API key required" across every tile.

**The map box is 700 px tall for a reason.** Mercator stretches the far north, so
copper's 36 to 81 degrees needs about 630 px of map at zoom 3. In a shorter box the
fit drops to zoom 2, and the result is the worst of both: North Africa fills the
bottom of the frame while the Svalbard and Barents cells, which are real data, are
cut off the top. Do not shrink it without redoing that arithmetic.

### All three fractions, one at a time

The map used to draw bulk sediment only, which made it the one place on an element
page where the sieved fractions disappeared: every table above it reports the three
side by side. A **Fraction** radio now picks between them, offering only the
fractions that element actually has, so iodine gets bulk and sieved <63 um and no
empty third button.

What the old restriction was really protecting against was a **shared colour
scale**, and that is still forbidden. Each fraction is scaled on its own cells, so
the same colour means different things between fractions: copper bulk runs 2.83 to
48.4 mg/kg across the bar where sieved <20 um runs 16.4 to 62.0. The page says so
under the map, and the legend names the fraction it is describing. Compare a
fraction with itself across the map, never one fraction's colour with another's.

This is not the sieved-normaliser trap: Igeo is a concentration measured against a
regional background, with no aluminium in it, and the element pages already publish
the contamination class for all three fractions in a table. Drawing that same
quantity on a map adds no new judgement.

### The pristine layer

A third **Colour by** option, added August 2026, draws the verdict rather than a
level. It exists only where the group has one: the option follows the fraction on
show, so manganese offers it in the sieved fractions and not in bulk, and iodine
and the two withheld elements never offer it.

The classification is applied **per measurement, with the predicate of
`analysis_refined_background_pristine()` and none of its own** (same thresholds,
same gates, same treatment of an unusable mixture bound), then aggregated to a
site and then to a cell, each step by majority. This module still derives no
verdict; it carries one down to a point on a map. The per-measurement counts
reproduce `refined_pristine_summary.csv` exactly, group by group, which is the
check to re-run after touching any of it.

Two properties fall out of the predicate rather than out of a caption, which is
the point:

- `pristine_ef` is NA off the aluminium-controlled fraction, so the `ef` class
  cannot arise on a sieved map and the legend cannot name one. **A sieved map can
  never show an "EF < 1" swatch**, whatever anyone later writes in a label.
- The sieved fractions are fully classifiable (their criteria need only a
  concentration and a threshold), so they carry no grey at all. Grey appears only
  on the three bulk maps that have an EF, where it is the commonest cell by far:
  83% of copper's bulk cells and 82% of zinc's.

That last number is the reason the layer needed a fourth class rather than three.
Aluminium is almost never measured near a farm or near the coast (0% classifiable
under 1 km from a farm, 44% beyond 20 km), so a map without an explicit "cannot be
classified" colour would show the coast as unjudged-therefore-clean. The legend
says "Grey is a gap in the data, not a clean result", the page says it again in
bold under the map, and the popup gives the composition behind every cell so a
reader can see that a green cell over mostly-unclassifiable sites is a different
object from a green cell where everything was judged.

Also worth knowing: the `ef` class (EF < 1 but failing a concentration criterion)
is nearly empty, 1 to 7 cells per element. Most cells that clear the enrichment
factor clear the other two as well.

**A fraction with no verdict still gets the layer**, drawn entirely grey, with the
reason in the legend: manganese bulk says aluminium does not predict it, iodine
says there is no background to judge against. Hiding the option there made the
absence look like an oversight; showing it makes the same statement the grey cells
make elsewhere, over a whole fraction. The two withheld elements are the exception
and keep no colour control at all, because their concentrations are withheld too
and a verdict layer over them would be answering a question the page does not ask.

**The unjudged cells are drawn small (2.5 px against 4) and faint (0.3 against
0.85), and drawn first so the judged ones sit on top.** They outnumber everything
else four to one on the bulk maps, and at full weight they buried the result the
map exists to show. Being quiet is not the same as being hidden: the legend swatch
is faded to match, the note still says grey is a gap in the data rather than a
clean result, and the page repeats it in bold. If that balance is ever revisited,
the thing to protect is that a reader cannot mistake a faint cell for an absent
one.

### The legend

Colour is the only thing on the map carrying a value, so it needs a key, and the
two scales need different ones: concentration is sequential and Igeo is diverging
about a zero that means "at background". The legend is a gradient bar **sampled
from the same ramp the markers are drawn with**, not a restatement of the palette,
so a change to the scale cannot leave the legend describing the previous one. The
Igeo bar carries a tick at its true zero, which is not the middle of the bar: the
domain is `[min(-2, p05), max(2, p95)]`, so zero sits between 50% and 66% across
the fourteen element and fraction combinations that have an Igeo.

Its numbers are the ends of the ramp, which the page already computed in order to
draw the map, so this does not breach the no-typed-numbers rule: nothing is stated
that was not already being drawn. The end labels say the scale is clipped, because
it is: everything past the 5th and 95th percentile takes the end colour.

A withheld element gets the single-swatch form instead: one colour, "Cells with
data", and a line pointing at the section that explains the withholding.

### The placeholder that has to carry a value

The "Colour by" radio only exists where there is an Igeo, and the else branch used
to be a bare `html\`<span></span>\``. That silently removed the map from the
molybdenum and selenium pages for as long as the map existed. Observable derives
the value of a `viewof` through `Generators.input`, which yields nothing at all
when the element has no `value` property, so `chosen` never resolved, `layer`
never resolved, and the map cell sat pending for ever. Nothing throws, so the
console is clean and the page just quietly ends after the heading.

The placeholder is now `Object.assign(html\`<span></span>\`, { value: "value_p50" })`
and `layer` reads it directly rather than branching around it. **Any OJS
placeholder standing in for an input has to carry a value**, or every cell
downstream of it disappears without saying so.

## The site

Five sections: Home, Methods (four pages), Results (a coverage matrix plus one page
per element), Open Questions, Downloads. The brief asked for the first three and the
last; Open Questions was added afterwards (see below).

Shared machinery, so the seven element pages stay in step:

- `_setup.qmd` loads every CSV and defines the display helpers
  (`capability_note()`, `chip()`, `keyfig()`, `sym_display`).
- `_element-body.qmd` is the whole element page. Each `element-<sym>.qmd` sets
  `SYM` and includes it. **Edit the body, never one element page**, or they drift.
- Sections appear and disappear from flags, not from per-page edits: a withheld
  element gets a "Why this element is withheld" section and no distance chart, an
  element below the reporting threshold gets "Why there is no result", and the map
  hides its Igeo control where there is no Igeo.

### Why the sieved fractions carry no verdict, and where that is said

The three fractions are reported side by side everywhere but only bulk gets a
pristine verdict, and the asymmetry looks arbitrary until it is explained. It is
explained once, in "And in bulk sediment only" on the pristine methods page, and
pointed at from the two places a reader meets it: the bulk-versus-sieved callout on
the data page and the verdict table on each element page.

That section was rewritten twice, and the second rewrite is the one worth keeping
in mind, because the first two attempts each answered a question nobody was asking.

**Attempt one gave the mechanism and let the reader infer the conclusion.** It said
aluminium does not predict the metal in a sieved sample, and a reader concludes
from that that there must not be enough sieved data. There is plenty: copper sieved
below 63 um has 4 502 measurements and 2 203 of them carry a paired aluminium.

**Attempt two proved that with numbers and then over-explained the mechanism.**
Aluminium explains 55.6% of the variation in bulk copper and 0.3% in sieved copper,
which settles it; the three paragraphs after it on why sieving is itself a
grain-size correction were telling a sediment chemist something they already knew.
D4's own measures now travel with the flag it produced so the numbers can be shown
instead of described: `summary_elements.csv` carries `al_tested`, `al_n`, `al_r2`
and `al_rho`, and `summary_meta.csv` carries `al_r2_limit`.

**The question actually being asked was the next one.** If a sieved sample needs no
grain-size correction, why can it not be judged pristine without one? Nothing in
the data prevents it. What prevents it is that the verdict *is* an enrichment
factor, so a sample with no aluminium falls outside the rule rather than failing
it. The concentration-against-background judgement that does work on a sieved
sample is already computed and published under another name, the contamination
class, and the strict rule's two non-EF criteria survive as well: an offshore P90
for all six sieved groups of CO/CU/ZN, a mixture bound for three.

The page now says that, and stops at the boundary of the decision:

> A concentration-based pristine verdict for the sieved fractions could be built
> from what is already computed. It has not been, because it would be a different
> test wearing the same word.

**That is an open decision and it belongs to the project, not to the page.** If it
is ever taken, the reference is the thing to argue about: the contamination class
measures against the offshore median, and offshore is not the same as clean.

### The fines-normalised background is bulk only

Found while checking the above, and the same species of error as the two
withholding bugs: a correction applied to material that has already been corrected.

The `fines` basis divides a concentration by the sample's mud fraction to scale it
to 100% mud. `fines_lt63` sits on `subsample` and describes the **parent sediment**,
not the aliquot that was measured, which is provable from the data: an aliquot cut
to below 20 um is by definition entirely below 63 um, yet the median `fines_lt63`
across sieved <20 um measurements is 52%, and 78% across the subset the fines basis
would actually use (those clearing the 10% mud floor). Applied to a sieved measurement the correction
therefore inflates a value that is already all fines, by the reciprocal of the
parent's mud content. Copper sieved63's grain-size-normalised offshore median came
out at 65.1 against a raw offshore median of 19.7.

`summary_background.csv` now takes the fines basis for bulk only. Done correctly,
sieved63 normalised to 100% mud is the identity, so the column would only duplicate
the offshore median, and for sieved20 the quantity is not defined at all.

**This was fixed at source in August 2026.** `analysis_refined_background_gsnorm()`
now computes the fines basis for bulk only, so `refined_gsnorm_percentiles.csv`
carries no sieved fines rows and the refined site's Grain-Size-Normalised page no
longer draws them. The `cat == "bulk"` filter here stays as an assertion: if a
sieved fines row ever reappears upstream, it must not reach a summary page.

### The Open Questions page

`open-questions.qmd` lists eleven questions the project knows are open, two or three
sentences each. It exists because the rest of the site reads as settled, and a reader
who finds a gap should meet it as a known one rather than as an oversight.

It states plainly that nothing on it changes what the site reports and that none of
it is a commitment. Keep it that way: the moment an item becomes work in progress
it belongs in the plan, and the moment it is answered it belongs in the methods
pages. **The page carries no numbers**, only links to the pages that hold them,
which is what keeps it from going stale between rebuilds.

The eleven sit in four groups, numbered straight through so an item can be cited by
its number alone:

| Group | Items | What the group has in common |
|-------|-------|------------------------------|
| Is the answer right? | 1-3 | Could change what is already published |
| What the database already holds and does not use | 4-6 | Needs no new sampling; the measurements exist |
| Judging more of the seabed, and judging it more fairly | 7-10 | Four routes at the same wall, and only one has to work |
| Working with the data | 11 | Tooling, not method |

The grouping carries one point the list alone did not: **the first group is not like
the other three.** Those three would extend what the site says; the first could
overturn it. The intro states that asymmetry outright rather than leaving it to be
inferred from the order.

Two things about the structure are load-bearing. The groups are **contiguous blocks
of the existing order**, so grouping cost the reading order nothing; if a new item
does not fall into a block without reordering the rest, it wants a new group rather
than a resequencing. And the third group's title ends "and judging it more fairly"
because item 10 is not a reach problem: the sieved fractions are already fully
classifiable, and the question there is whether the reference they are judged
against resembles them. Filing it under reach alone would mislabel it.

Its navbar entry sits **before Downloads**, fourth of five. The page's first group
is the one that could change what is published and Downloads is where a reader
leaves with the files, so the caveats belong on the near side of the exit.

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

Published and live at <https://seafood-hazards.github.io/multised-summary/>, from
release `v0.1.0` and its 13 assets.

One trap worth recording for the next site: Pages was created by API while
`develop` was still the default branch, so the `github-pages` environment's
deployment branch policy allowed only `develop` and the deploy job silently ran
with no steps while the build succeeded. Set the default branch first, or fix the
policy afterwards.

The site says on its home page and its Downloads page that it is not the final
submission. That stays true until the pristine-filtered submission subset exists;
see [efsa-submission.md](efsa-submission.md).
