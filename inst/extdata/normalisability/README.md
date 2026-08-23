# Is aluminium a working normaliser? (decision D4)

`refined_al_normalisability.csv` is the frozen answer to one question, asked per
element and fraction: **does aluminium predict this metal at all?**

An enrichment factor divides metal by aluminium and calls the result grain-size
controlled. That only holds where aluminium carries the metal. Measured on this
database it does so for **cobalt, copper and zinc in bulk** and for nothing else.

## The rule

A group is normalisable when **both** of these clear their limit:

| Measure | Limit | What it is |
|---------|-------|------------|
| `r2`  | >= 0.30 | OLS R-squared of `value_std ~ al` over the offshore (> 10 km) reference, on the fraction's adopted aluminium basis: the same rows the EF reference is built from |
| `rho` | >= 0.50 | Spearman's rho of `value_std` against `al` over **every** on-basis row |

`rho` is there to answer the obvious objection to `r2` alone. An R-squared computed
on the offshore reference is attenuated by that reference's restricted range, so a
low value could mean a narrow reference rather than a failed normaliser. Spearman
over the full set uses the whole range of aluminium and is rank based, so neither
the restricted range nor the skew of these distributions can flatten it.

**The two measures agree completely.** No group passes one and fails the other, and
copper sieved63 is the only group where they disagree in spirit (`r2` 0.003 on the
reference against 0.102 on the full range), which is exactly the attenuation `rho`
was added to catch: its `rho` of 0.462 still falls short. The limits could be moved
anywhere in **0.10-0.46** for `r2` or **0.47-0.65** for `rho` without changing which
groups qualify, so the partition is not an artefact of where the line was drawn.

## The table

| Element | Fraction | r2 | rho | normalisable |
|---------|----------|-----:|------:|---|
| CO | bulk | 0.584 | 0.812 | **yes** |
| CO | sieved20 | 0.0131 | 0.336 | no |
| CU | bulk | 0.556 | 0.652 | **yes** |
| CU | sieved63 | 0.00322 | 0.462 | no |
| CU | sieved20 | 0.0822 | -0.228 | no |
| MN | bulk | 0.0369 | 0.368 | no |
| MN | sieved63 | 0.00574 | 0.336 | no |
| MN | sieved20 | 0.00495 | 0.107 | no |
| MO | bulk | 0.0966 | -2e-4 | no |
| SE | bulk | 0.012 | 0.154 | no |
| ZN | bulk | 0.464 | 0.714 | **yes** |
| ZN | sieved63 | 7.56e-4 | 0.221 | no |
| ZN | sieved20 | 4.43e-5 | -0.00992 | no |

Copper sieved20, zinc sieved20 and molybdenum bulk have rho at or below zero: more
aluminium goes with *less* metal, or with nothing at all.

Two patterns are worth naming. The sieved fractions fail across the board because a
sieved sample is **already** grain-size controlled: cut to below 63 or 20 um, most of
the texture variation is gone before the chemistry starts, leaving aluminium little
to track. And manganese, molybdenum and selenium fail in bulk too, because they are
redox-mobile or organic-associated rather than clay-borne, so they never rode on
aluminium in the first place.

## Why frozen

Same reason as `inst/extdata/loq-censoring/`. This is a **rule**, so it should not
move silently under a rebuild, and the EF (background step 4) and pristine (step 6)
analyses that consume it run before the regression analysis (step 8) that measures
it.

`check_normalisability()` closes the drift risk: step 8 recomputes both measures and
warns if the frozen table no longer matches what the data says.

## Regenerating

Re-cut this file only when the underlying data changes, and then re-run the whole
background suite so the verdicts follow it:

```r
analyze_data("refined", module = "background", steps = 8)   # reports the current values
```

`refined_regression_fits.csv` carries `r2`, `rho`, `r2_all`, `r2_log` and
`normalisable` for every group, so the new table can be cut from it directly.

## What it changes

`refined_normalisable()` in `R/analysis-refined-shared-normalisability.R` is read by
the EF analysis, the pristine synthesis and the flat export, so the three cannot
disagree about which groups carry a verdict. Concentrations, EF references and the
distributions themselves are still published for every group; only the **verdicts**
are withheld.
