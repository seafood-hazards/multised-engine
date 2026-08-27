# Is aluminium a working normaliser? (decision D4)

`refined_al_normalisability.csv` is the frozen answer to one question, asked per
element and fraction: **does aluminium predict this metal at all?**

An enrichment factor divides metal by aluminium and calls the result grain-size
controlled. That only holds where aluminium carries the metal. Measured on this
database it does so for **cobalt, copper and zinc in bulk** and for nothing else.

## Scope: the question is only asked in bulk

**D4 governs the bulk fraction and nothing else** (the `gs_control` column says which
rows it governs). Aluminium is the grain-size control only where the control has to be
statistical. A sieved sample was cut to size before the chemistry started, so the sieve
already did the correcting and aluminium is a spare measurement rather than the
normaliser. Asking whether it predicts the metal there and then withholding a verdict
when it does not reads **"no correction needed" as "the correction failed"**, and
penalises the fraction that had the better control all along.

That is not a hypothetical: the sieved fractions carry `normalisable = NA` here now,
but they were `FALSE` until 2026-08-27, and that `FALSE` was what withheld a verdict
from 27 971 sieved measurements of cobalt, copper, zinc and manganese.

The sieved `r2` and `rho` stay in the table because they remain a **diagnostic**, and a
useful one: they are the direct evidence that the sieve has already removed the texture
signal aluminium would otherwise track. Nothing reads them to decide anything.
`refined_gs_control()` is the split, and `analysis_refined_pristine()` branches on it.

The sieve is also the **stronger** of the two controls where both could be compared.
Taking the offshore background of each fraction and asking how far it moves between
seas (largest sea median over smallest, seas with n >= 50):

| Element | Fraction | raw concentration | after / Al |
|---------|----------|------------------:|-----------:|
| CU | bulk | 9.5x | 4.4x |
| ZN | bulk | 10.7x | 4.9x |
| CO | bulk | 3.1x | 5.5x |
| CU | sieved63 | 2.5x | 2.5x |
| ZN | sieved63 | 1.7x | 1.5x |

Aluminium roughly halves the spread for bulk copper and zinc and makes cobalt worse,
and bulk **after** normalisation is still about twice as variable between seas as
sieved63 is **before** it. Within ICES-DOME alone, which removes the aluminium-basis
artefact of [ef-source-bias.md](../../../docs/ef-source-bias.md), zinc goes 8.0x -> 2.7x
on aluminium in bulk against 1.7x untouched in sieved63.

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

| Element | Fraction | control | r2 | rho | normalisable |
|---------|----------|---------|-----:|------:|---|
| CO | bulk | aluminium | 0.584 | 0.812 | **yes** |
| CO | sieved20 | sieve | 0.0131 | 0.336 | not asked |
| CU | bulk | aluminium | 0.556 | 0.652 | **yes** |
| CU | sieved63 | sieve | 0.00322 | 0.462 | not asked |
| CU | sieved20 | sieve | 0.0822 | -0.228 | not asked |
| MN | bulk | aluminium | 0.0369 | 0.368 | no |
| MN | sieved63 | sieve | 0.00574 | 0.336 | not asked |
| MN | sieved20 | sieve | 0.00495 | 0.107 | not asked |
| MO | bulk | aluminium | 0.0966 | -2e-4 | no |
| SE | bulk | aluminium | 0.012 | 0.154 | no |
| ZN | bulk | aluminium | 0.464 | 0.714 | **yes** |
| ZN | sieved63 | sieve | 7.56e-4 | 0.221 | not asked |
| ZN | sieved20 | sieve | 4.43e-5 | -0.00992 | not asked |

Copper sieved20, zinc sieved20 and molybdenum bulk have rho at or below zero: more
aluminium goes with *less* metal, or with nothing at all.

Two patterns are worth naming. The sieved fractions score near zero across the board
because a sieved sample is **already** grain-size controlled: cut to below 63 or 20 um,
most of the texture variation is gone before the chemistry starts, leaving aluminium
little to track. That is the diagnostic reading, and it is why those rows are scored but
not judged (see Scope above). And manganese, molybdenum and selenium fail in bulk too,
because they are redox-mobile or organic-associated rather than clay-borne, so they
never rode on aluminium in the first place. That failure is real and does withhold their
bulk verdict: unlike the sieved case, nothing else corrected the grain size.

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
