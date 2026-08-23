# Below-LOQ censoring, measured from the slim databases

`clean-02-clean.R` **removes** every measurement flagged `below_loq` or `below_loq_num`,
alongside the range and validity failures ([clean-pipeline.md](../../../docs/clean-pipeline.md),
step 02). That is a deliberate rule and the right one for most purposes: a non-detect has
no trustworthy value, and feeding a substituted number into a percentile corrupts it.

It is the wrong rule for **estimating a background**, because a background is the low end
of the distribution and non-detects are evidence about exactly that end. Deleting them
asserts no information where the truth is "measured, and below L".

By the clean stage the rows are gone, and merged and refined never had them, so the share
is measured here from the **slim** databases, which still carry the flags:

```sql
SELECT UPPER(m.symbol), COUNT(*), SUM(COALESCE(below_loq,0)=1 OR COALESCE(below_loq_num,0)=1)
FROM measurement m JOIN element e ON e.symbol = m.symbol
WHERE e.category = 'target' GROUP BY 1
```

run over each `<source>_slim.sqlite` and pooled. Regenerate it that way if the slim
databases are ever rebuilt.

| Element | censored | note |
|---------|---------:|------|
| SE      | 68.6%    | verdicts withheld |
| MO      | 52.2%    | verdicts withheld |
| I       | 4.3%     | already too sparse for any background |
| CU      | 1.6%     | |
| CO      | 0.3%     | |
| ZN      | 0.2%     | |
| MN      | 0.0%     | |

The split is clean: two elements above 50%, nothing else above 5%. Selenium and molybdenum
therefore have their background and pristine verdicts **withheld** rather than published
with a caveat, on the same principle applied to the aluminium basis: where the reference is
not trustworthy, issue no verdict. For Mareano, which supplies 94-99% of the bulk Mo and Se
reference, 86% of Mo and 70% of Se were removed, so the published "90th-percentile
background" sat at roughly the 98th percentile of the real distribution.

This does **not** affect the near-cage Mo and Se enrichment finding. Removing low offshore
values raises the offshore reference, which suppresses near-cage EF, so that signal is
conservative and survives.

Kept as a frozen file rather than computed at run time so the refined analyses do not
acquire a dependency on the slim databases, which would break the rule that an analysis
reads one generation's database only.
