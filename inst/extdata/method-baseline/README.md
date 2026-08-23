# Pre-revision baseline

The `background` module's outputs exactly as published in **multised-refined v0.8.0**,
frozen here so the method-revision comparison can be regenerated rather than typed into a
page by hand.

v0.8.0 is the last release before the enrichment-factor reference was restricted to a
single aluminium measurement basis (see [ef-source-bias.md](../../../docs/ef-source-bias.md)).
Every EF and every pristine verdict in it is computed against a reference pooled over
incompatible aluminium measurements, so **these numbers are superseded, not current**.
They are kept only as the "before" column of the comparison.

Do not run the pipeline into this directory. It is a snapshot, not an output path:
`analysis_refined_method_changes()` reads it and writes the comparison into the normal
analysis tree.
