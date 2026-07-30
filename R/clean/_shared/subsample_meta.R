# ── Clean stage: shared subsample metadata ───────────────────────────────────
# Common column set for the subsample table across all sources:
#   - the supporting-data flags (fe/al/org/comp_exist), with a fixed order (fixes
#     4Demon, whose slim table had org_exist / comp_exist swapped);
#   - a per-subsample sediment-fraction summary of the TARGET measurements only,
#     target_frac_class ('bulk' / 'sieved' / 'mixed') + target_sieve_um (see
#     _shared/fraction_meta.R). 'mixed' marks the ~4% of subsamples whose targets
#     span both bulk and sieved; the authoritative per-value fraction is on
#     `measurement` (frac_class / sieve_um). NULL where there is no target
#     chemistry. The names are distinct from the measurement columns so the two
#     tables can be joined / flattened without a clash;
#   - the grain-size fines: fines_lt63 (% <63 um, the mud content, from slim step
#     15) + fines_basis. Derived from grain-size, independent of the targets. The
#     one-to-many grain-size detail stays in grain_size_fraction.
#   - a depth_flag ('implausible' where the source's reported depth was out of
#     range or inverted and was removed, NULL otherwise). Only Vannmiljo nulls
#     corrupt depths, so it is the only source that sets it; elsewhere a NULL
#     depth means the source never recorded one, which depth_flag leaves NULL so
#     the two cases stay distinguishable. The row is kept either way; the flag
#     lets a user spot depth-less rows and drop them if their analysis needs depth.
# 01_harmonise calls standardise_subsample to lock the columns/order (the target
# summary NULL at that point); 03_annotate fills the summary and re-applies this.

SUBSAMPLE_COLS <- c("subsample_id", "event_id", "depth_from", "depth_to", "depth_flag",
                    "fe_exist", "al_exist", "org_exist", "comp_exist",
                    "target_frac_class", "target_sieve_um", "fines_lt63", "fines_basis")

standardise_subsample <- function(subsample) {
  s <- subsample
  for (col in c("depth_flag", "target_frac_class", "fines_basis")) if (!col %in% names(s)) s[[col]] <- NA_character_
  for (col in c("target_sieve_um", "fines_lt63"))    if (!col %in% names(s)) s[[col]] <- NA_real_
  dplyr::select(s, dplyr::all_of(SUBSAMPLE_COLS))
}
