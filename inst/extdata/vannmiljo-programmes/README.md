# Vannmiljø programme pressure class: the frozen table

`pressure_class.csv` maps a Vannmiljø `activity` code to why the sample was
taken. Read it through `R/vannmiljo-pressure.R`, never directly.

## What it is for

Vannmiljø files every record under a monitoring programme, and the programme name
usually states the pressure. This is **evidence the source gives us**, independent
of the geometric proxies (`dist_to_coast`, `dist_to_aquaculture`) and of the
chemical one (EF).

That independence is the point. The pristine work currently validates EF against
distance, and distance alone; a categorical label from the data provider is a
third axis, and one that does not share EF's assumptions about aluminium.

The codes already reached refined as `dataset.dataset_code`. Only the meaning was
missing.

## The five classes

Counts are target measurements in `multised_refined.sqlite`, 53,754 in total.
Four of the 31 programmes carry no target chemistry, all of them `survey`.

| Class | Meaning | Programmes | With data | Target measurements |
|---|---|---:|---:|---:|
| `aquaculture` | Monitoring at marine fish farms | 1 | 1 | **25,789** |
| `pressure` | A named or presumed pressure at the site | 16 | 16 | 23,937 |
| `unknown` | The source's own residual category (`ANNE`) | 1 | 1 | 2,415 |
| `survey` | Status, trend or mapping work with no site-specific pressure premise | 12 | 8 | 1,549 |
| `reference` | Reference conditions, deliberately unpressured | 1 | 1 | 64 |

`MOMC` alone is 25,789 target measurements, the largest Vannmiljø programme and
exactly the data EFSA asked for by name: *"Samples taken during / for
Environmental / Ecological Impact Assessment for marine aquaculture facilities …
monitoring data of sediment quality over time … under the sea cages"*.

`BARE` is the only positive pristine signal in the vocabulary, and at 64
measurements it is a validation set rather than a data source.

## Why `NA` and `unknown` are different

A code the table does not hold returns `NA`, not `"unknown"`. `ANNE` ("Annet",
other) **is** `"unknown"`: the source looked at the record and declined to
classify it. An unrecognised code means the source vocabulary has changed, which
is a thing to fix. `check_vannmiljo_programmes()` warns when one appears.

Same distinction as `UNK` against `NON` in
[extraction-class](../extraction-class/README.md).

## The eight judgement calls

Marked `judgement = TRUE`. The programme names are clear about the subject and
silent about how much it presses on the sampling point.

| Code | Class | Why it is a call |
|---|---|---|
| `TILT` | pressure | Monitoring tied to a remedial measure: a known problem at the site, but the source is not named. |
| `PROB` | pressure | Investigating a *suspected* problem. The suspicion is the evidence, and some surveys will find nothing. |
| `SOFP` | pressure | "Several pressures" in the name, none identified. |
| `AREA` | pressure | Baseline for a planned development, so the pressure may post-date the sample. |
| `MONS` | pressure | Offshore petroleum field monitoring. Offshore, which EFSA leans pristine, but sited on an installation. |
| `YOFJ` | survey | Regional status programme in a populated fjord. Regional rather than site-specific, so not filed as a pressure. |
| `TILF` | survey | Quantifies riverine loads to the sea rather than impact at the sampling point. |
| `SPFO` | survey | A funding envelope rather than a subject; it covered both status and pressure work. |

The five judgement calls filed as `pressure` (`TILT` 3,030, `PROB` 1,655,
`SOFP` 152, `AREA` 94, `MONS` 36) total 4,967 measurements, a fifth of that
class. A reviewer who disagrees moves them *out* of `pressure`; the three filed
as `survey` (`YOFJ`, `TILF`, `SPFO`) would move *in*. Neither direction touches
`aquaculture` or `reference`, which are the two classes the pristine work leans
on.

## Why it is frozen

Same reason as [extraction-class](../extraction-class/README.md) and
[normalisability](../normalisability/README.md): it encodes judgement, so it must
not move silently under a rebuild.

## Regenerating

Hand-maintained, not cut from the data. To check it still covers the source:

```r
src <- DBI::dbGetQuery(con, "SELECT activity_id FROM activity")$activity_id
check_vannmiljo_programmes(src)   # silent when the table covers every code
```

Adding a programme means adding a row, with `judgement` and `note` filled in
where the class is not obvious from the name.
