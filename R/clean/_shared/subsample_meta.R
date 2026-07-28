# ── Clean stage: shared subsample metadata ───────────────────────────────────
# Common column set for the subsample table across all sources:
#   - the supporting-data flags (fe/al/org/comp_exist), with a fixed order (fixes
#     4Demon, whose slim table had org_exist / comp_exist swapped);
#   - a per-subsample sediment-fraction summary, frac_class ('bulk' / 'sieved' /
#     'mixed') + sieve_um, derived from the subsample's TARGET measurements in
#     03_annotate (see _shared/fraction_meta.R). 'mixed' marks the ~4% of
#     subsamples whose targets span both bulk and sieved; the authoritative
#     per-value fraction is on `measurement`. NULL where there is no target
#     chemistry to classify;
#   - the grain-size fines: fines_lt63 (% <63 um, the mud content, from slim step
#     15) + fines_basis. The one-to-many grain-size detail stays in
#     grain_size_fraction.
# 01_harmonise calls standardise_subsample to lock the columns/order (frac_class /
# sieve_um NULL at that point); 03_annotate fills the fraction summary and
# re-applies this to reorder.

SUBSAMPLE_COLS <- c("subsample_id", "event_id", "depth_from", "depth_to",
                    "fe_exist", "al_exist", "org_exist", "comp_exist",
                    "frac_class", "sieve_um", "fines_lt63", "fines_basis")

standardise_subsample <- function(subsample) {
  s <- subsample
  for (col in c("frac_class", "fines_basis")) if (!col %in% names(s)) s[[col]] <- NA_character_
  for (col in c("sieve_um", "fines_lt63"))    if (!col %in% names(s)) s[[col]] <- NA_real_
  dplyr::select(s, dplyr::all_of(SUBSAMPLE_COLS))
}
