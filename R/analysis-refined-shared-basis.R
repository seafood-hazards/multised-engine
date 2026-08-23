# ── Refined analyses, shared: the aluminium measurement basis ─────────────────
# One rule, used by the enrichment-factor analysis, the pristine synthesis and the flat
# export, so the three cannot drift into disagreeing about which samples are classifiable.
# The finding behind it is in docs/ef-source-bias.md.
#
# The sources do not all measure aluminium the same way. Some report near-total Al, some
# report what an acid extraction leaches, which is 2-3x less. Al is the denominator of
# every enrichment factor, so a reference pooled over both bases means nothing and pushes
# the under-recovered samples toward falsely pristine.
#
# No source records its digestion (the refined `method` table carries no AL row at all),
# so the basis is inferred per sample from Fe/Al. Fe and Al are both lithogenic and both
# track grain size, so the ratio is close to grain-size free; an acid extraction depresses
# Al far more than Fe. Crustal Fe/Al is about 0.5, and Fe/Al at or above the cut marks Al
# under-recovery. The cut separates a real bimodality WITHIN a single source (ICES-DOME
# rows either side of it differ 1.7-2.5x in metal/Al), which is what says it is finding a
# protocol rather than geology.

# Fe/Al at or above this marks aluminium under-recovery.
refined_fe_al_cut <- function() 1.0

# The one basis each fraction's EF is computed on: the stratum carrying that fraction's
# data. Bulk on the extraction basis is the only bulk stratum with near-cage samples (164
# against none) and the only one with a molybdenum or selenium reference; the sieved
# fractions are the other way round. Samples on the other basis, or with no Fe to place
# them, are left UNCLASSIFIED rather than judged against a reference they do not belong
# to, which is the stance already taken for samples with no Al at all.
refined_ef_basis <- function() c(bulk = "extraction", sieved63 = "total", sieved20 = "total")

#' The aluminium basis of each measurement
#'
#' @param fe,al The subsample's normaliser concentrations, mg/kg.
#' @return `"extraction"`, `"total"`, or `"unplaced"` where Fe is missing.
refined_al_basis <- function(fe, al) {
  ifelse(is.na(fe) | fe <= 0 | is.na(al) | al <= 0, "unplaced",
         ifelse(fe / al >= refined_fe_al_cut(), "extraction", "total"))
}

#' Whether a measurement sits on the basis its fraction adopted
#'
#' @param al_basis From [refined_al_basis()].
#' @param cat The fraction, one of `bulk` / `sieved63` / `sieved20`.
refined_on_basis <- function(al_basis, cat) {
  !is.na(al_basis) & !is.na(cat) & al_basis == unname(refined_ef_basis()[cat])
}
