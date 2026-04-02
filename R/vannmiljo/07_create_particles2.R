library(tidyverse)

# ── Constants ─────────────────────────────────────────────────────────────────
SAND_SUBCOLS  <- c("GSMF63_125", "GSMF125_250", "GSMF250_500",
                   "GSMF500_1000", "GSMF1000_2000")
ALL_MEAS_COLS <- c("GSMF2", "GSMF2_63", "FINS", "GSMF_63",
                   SAND_SUBCOLS, "GSMF_2000")

# ── STEP 0: Operator-adjusted values ─────────────────────────────────────────
#   ND  → 0          (not detected)
#   "<" → value / 2  (below limit; mid-point as point estimate)
#   ">" → value      (lower bound; kept as measured)
#   "=" → value      (exact)
df_p_adj <- df_p %>%
  mutate(
    value_adj = case_when(
      operator == "ND" ~ 0,
      operator == "<"  ~ value / 2,
      TRUE             ~ value
    )
  )

# ── Confidence penalty system ─────────────────────────────────────────────────
#
# Each QC issue adds penalty points; total → confidence level:
#
#   Source                              Penalty
#   ─────────────────────────────────── ───────
#   Total 100–101 % (rounding)            +1
#   Total 101–110 % (moderate conflict)   +2
#   Total 110–200 % (serious conflict)    +3
#   Total  > 200 % (likely multi-error)   +4
#   Decimal correction applied (0b)       +1
#   Overlap/aggregate removed (0c)        +1
#
#   Total penalty → confidence
#   0  → "high"
#   1  → "medium"
#   2  → "low"
#   3  → "very_low"
#   4+ → "unreliable"

CONF_LEVELS <- c("high", "medium", "low", "very_low", "unreliable")

penalty_to_confidence <- function(penalty) {
  factor(
    case_when(
      penalty == 0 ~ "high",
      penalty == 1 ~ "medium",
      penalty == 2 ~ "low",
      penalty == 3 ~ "very_low",
      TRUE         ~ "unreliable"
    ),
    levels = CONF_LEVELS
  )
}

SAND_SUBCOLS <- c("GSMF63_125", "GSMF125_250", "GSMF250_500",
                   "GSMF500_1000", "GSMF1000_2000")

# ── STEP 0b: Decimal-point correction ────────────────────────────────────────

param_bg_medians <- df_p_adj %>%
  filter(value_adj <= 100, value_adj >= 0) %>%
  group_by(param_id) %>%
  summarise(bg_median = median(value_adj, na.rm = TRUE), .groups = "drop")

fix_decimal <- function(value, bg_median) {
  if (is.na(value) || value <= 100) return(value)
  candidates <- value / 10^(1:6)
  valid_cand <- candidates[candidates <= 100 & candidates >= 0]
  if (length(valid_cand) == 0) return(NA_real_)
  valid_cand[which.min(abs(valid_cand - bg_median))]
}

df_p_adj <- df_p_adj %>%
  left_join(param_bg_medians, by = "param_id") %>%
  mutate(
    decimal_corrected     = value_adj > 100,
    value_adj             = map2_dbl(value_adj, bg_median, fix_decimal),
    decimal_unrecoverable = decimal_corrected & is.na(value_adj)
  ) %>%
  select(-bg_median)

# Per-sample 0b penalty: +1 if any decimal correction in this sample
penalty_0b <- df_p_adj %>%
  group_by(sample_id, sediment_no) %>%
  summarise(
    penalty_decimal      = as.integer(any(decimal_corrected,     na.rm = TRUE)),
    any_unrecoverable_0b = any(decimal_unrecoverable, na.rm = TRUE),
    .groups = "drop"
  )

# ── STEP 0c: Overlap removal + rescaling ─────────────────────────────────────

# Pass 1: remove redundant aggregates, track whether removal happened
df_p_dedup <- df_p_adj %>%
  group_by(sample_id, sediment_no) %>%
  mutate(
    .fins_redundant   = any(param_id == "FINS") &
                         (any(param_id == "GSMF2") | any(param_id == "GSMF2_63")),
    .coarse_redundant = any(param_id == "GSMF_63") &
                         (any(param_id %in% SAND_SUBCOLS) | any(param_id == "GSMF_2000"))
  ) %>%
  ungroup() %>%
  mutate(
    overlap_removed = (param_id == "FINS"    & .fins_redundant) |
                      (param_id == "GSMF_63" & .coarse_redundant)
  ) %>%
  filter(!overlap_removed) %>%
  select(-starts_with("."))

# Per-sample 0c penalty: +1 if any row was removed by deduplication
penalty_0c_dedup <- df_p_adj %>%
  group_by(sample_id, sediment_no) %>%
  summarise(n_before = n(), .groups = "drop") %>%
  left_join(
    df_p_dedup %>%
      group_by(sample_id, sediment_no) %>%
      summarise(n_after = n(), .groups = "drop"),
    by = c("sample_id", "sediment_no")
  ) %>%
  mutate(penalty_dedup = as.integer(n_before != n_after)) %>%
  select(sample_id, sediment_no, penalty_dedup)

# Pass 2: totals after dedup and associated penalty
df_totals <- df_p_dedup %>%
  filter(value_adj >= 0, value_adj <= 100) %>%
  group_by(sample_id, sediment_no) %>%
  summarise(
    total_pct_before_rescale = sum(value_adj, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    penalty_total = case_when(
      total_pct_before_rescale <= 100 ~ 0L,
      total_pct_before_rescale <= 101 ~ 1L,
      total_pct_before_rescale <= 110 ~ 2L,
      total_pct_before_rescale <= 200 ~ 3L,
      TRUE                             ~ 4L
    )
  )

# Pass 3: combine all penalties → single confidence flag
df_qc_flags <- df_totals %>%
  left_join(penalty_0b,      by = c("sample_id", "sediment_no")) %>%
  left_join(penalty_0c_dedup, by = c("sample_id", "sediment_no")) %>%
  mutate(
    across(starts_with("penalty_"), ~ replace_na(.x, 0L)),
    penalty_total_combined = penalty_decimal + penalty_dedup + penalty_total,
    qc_confidence = penalty_to_confidence(penalty_total_combined)
  )

# Pass 4: rescale all to 100 %
df_p_clean <- df_p_dedup %>%
  left_join(
    df_qc_flags %>% select(sample_id, sediment_no,
                            total_pct_before_rescale, qc_confidence,
                            penalty_decimal, penalty_dedup, penalty_total),
    by = c("sample_id", "sediment_no")
  ) %>%
  mutate(
    value_adj = case_when(
      is.na(total_pct_before_rescale) | total_pct_before_rescale <= 0 ~ value_adj,
      TRUE ~ value_adj * 100 / total_pct_before_rescale
    )
  )

# ── Diagnostics ───────────────────────────────────────────────────────────────

message("\n── Penalty breakdown (unique samples) ──")
df_qc_flags %>%
  count(penalty_decimal, penalty_dedup, penalty_total,
        penalty_total_combined, qc_confidence,
        sort = TRUE) %>%
  print(n = 30)

message("\n── Final confidence distribution ──")
df_qc_flags %>%
  count(qc_confidence) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()

message("\n── Total % before rescale, by confidence band ──")
df_qc_flags %>%
  group_by(qc_confidence) %>%
  summarise(
    n       = n(),
    min_tot = min(total_pct_before_rescale),
    med_tot = median(total_pct_before_rescale),
    max_tot = max(total_pct_before_rescale),
    .groups = "drop"
  ) %>%
  print()

# ── STEP 1: Wide formats ──────────────────────────────────────────────────────
df_val <- df_p_clean %>%
  distinct(sample_id, sediment_no, param_id, value_adj) %>%
  pivot_wider(names_from = param_id, values_from = value_adj)

df_ops <- df_p_clean %>%
  distinct(sample_id, sediment_no, param_id, operator) %>%
  pivot_wider(names_from  = param_id,
              values_from = operator,
              names_glue  = "{param_id}_op")

for (col in ALL_MEAS_COLS) {
  if (!col %in% names(df_val)) df_val[[col]] <- NA_real_
}

df_wide <- left_join(df_val, df_ops, by = c("sample_id", "sediment_no")) %>%
  arrange(sample_id, sediment_no)

# ── STEP 2: Multi-pass arithmetic derivation (no background ratios yet) ───────
#
# Hierarchy:
#   Group level : fines (<63 µm) + coarse (>63 µm) = 100 %
#   Components  : clay + silt = fines;  sand + gravel = coarse
#
# Pass 1  – direct measurements
# Pass 2a – group total = sum of both components
# Pass 2b – one component = group total − the other component
# Pass 3  – 100 % constraint: one group = 100 − the other
# Pass 4  – repeat Pass 2b with group totals derived in Pass 3
#            (e.g. GSMF2_63 + sand_sub + GSMF_2000 → clay via 100 % path)

df_derived <- df_wide %>%
  mutate(
    sand_sub = if_else(
      if_any(all_of(SAND_SUBCOLS), ~ !is.na(.)),
      rowSums(across(all_of(SAND_SUBCOLS)), na.rm = TRUE),
      NA_real_
    )
  ) %>%
  # Pass 1: direct
  mutate(
    clay_v   = GSMF2,
    silt_v   = GSMF2_63,
    sand_v   = sand_sub,
    gravel_v = GSMF_2000,
    fines_v  = FINS,
    coarse_v = GSMF_63
  ) %>%
  # Pass 2a: group total from both components
  mutate(
    fines_v  = coalesce(fines_v,
                        if_else(!is.na(clay_v) & !is.na(silt_v),
                                clay_v + silt_v, NA_real_)),
    coarse_v = coalesce(coarse_v,
                        if_else(!is.na(sand_v) & !is.na(gravel_v),
                                sand_v + gravel_v, NA_real_))
  ) %>%
  # Pass 2b: one component = group total − the other
  mutate(
    clay_v   = coalesce(clay_v,
                        if_else(!is.na(fines_v)  & !is.na(silt_v),
                                pmax(0, fines_v  - silt_v),   NA_real_)),
    silt_v   = coalesce(silt_v,
                        if_else(!is.na(fines_v)  & !is.na(clay_v),
                                pmax(0, fines_v  - clay_v),   NA_real_)),
    sand_v   = coalesce(sand_v,
                        if_else(!is.na(coarse_v) & !is.na(gravel_v),
                                pmax(0, coarse_v - gravel_v), NA_real_)),
    gravel_v = coalesce(gravel_v,
                        if_else(!is.na(coarse_v) & !is.na(sand_v),
                                pmax(0, coarse_v - sand_v),   NA_real_))
  ) %>%
  # Pass 3: 100 % constraint
  mutate(
    fines_v  = coalesce(fines_v,
                        if_else(!is.na(coarse_v), 100 - coarse_v, NA_real_)),
    coarse_v = coalesce(coarse_v,
                        if_else(!is.na(fines_v),  100 - fines_v,  NA_real_))
  ) %>%
  # Pass 4: repeat component derivation now that cross-derived group totals exist
  mutate(
    clay_v   = coalesce(clay_v,
                        if_else(!is.na(fines_v)  & !is.na(silt_v),
                                pmax(0, fines_v  - silt_v),   NA_real_)),
    silt_v   = coalesce(silt_v,
                        if_else(!is.na(fines_v)  & !is.na(clay_v),
                                pmax(0, fines_v  - clay_v),   NA_real_)),
    sand_v   = coalesce(sand_v,
                        if_else(!is.na(coarse_v) & !is.na(gravel_v),
                                pmax(0, coarse_v - gravel_v), NA_real_)),
    gravel_v = coalesce(gravel_v,
                        if_else(!is.na(coarse_v) & !is.na(sand_v),
                                pmax(0, coarse_v - sand_v),   NA_real_))
  )

# Snapshot: what was arithmetic-derivable WITHOUT any background ratio
df_pre_bg <- df_derived %>%
  transmute(
    sample_id, sediment_no,
    clay_no_bg   = !is.na(clay_v),
    silt_no_bg   = !is.na(silt_v),
    sand_no_bg   = !is.na(sand_v),
    gravel_no_bg = !is.na(gravel_v)
  )

# ── STEP 3: Background ratios (computed from arithmetic-derived data) ─────────

# clay / (clay + silt): rows where both fines components are known
p_clay_fines <- df_derived %>%
  filter(!is.na(clay_v), !is.na(silt_v), (clay_v + silt_v) > 0) %>%
  summarise(r = median(clay_v / (clay_v + silt_v), na.rm = TRUE)) %>%
  pull(r)

# gravel / (sand + gravel): rows where both coarse components are known
p_gravel_coarse <- df_derived %>%
  filter(!is.na(sand_v), !is.na(gravel_v), (sand_v + gravel_v) > 0) %>%
  summarise(r = median(gravel_v / (sand_v + gravel_v), na.rm = TRUE)) %>%
  pull(r)

# Overall proportions for the general imputation fallback
# (rows where all 4 are known without background)
bg_raw <- df_derived %>%
  filter(!is.na(clay_v), !is.na(silt_v), !is.na(sand_v), !is.na(gravel_v)) %>%
  mutate(tot = clay_v + silt_v + sand_v + gravel_v) %>%
  filter(tot > 0) %>%
  summarise(
    p_clay   = median(clay_v   / tot, na.rm = TRUE),
    p_silt   = median(silt_v   / tot, na.rm = TRUE),
    p_sand   = median(sand_v   / tot, na.rm = TRUE),
    p_gravel = median(gravel_v / tot, na.rm = TRUE)
  )

bg_norm     <- bg_raw$p_clay + bg_raw$p_silt + bg_raw$p_sand + bg_raw$p_gravel
p_clay_bg   <- bg_raw$p_clay   / bg_norm
p_silt_bg   <- bg_raw$p_silt   / bg_norm
p_sand_bg   <- bg_raw$p_sand   / bg_norm
p_gravel_bg <- bg_raw$p_gravel / bg_norm

message(sprintf("Background clay/fines ratio    (median): %.4f", p_clay_fines))
message(sprintf("Background gravel/coarse ratio (median): %.4f", p_gravel_coarse))
message(sprintf("Overall background proportions: clay=%.4f  silt=%.4f  sand=%.4f  gravel=%.4f",
                p_clay_bg, p_silt_bg, p_sand_bg, p_gravel_bg))

# ── STEP 4: Within-group background splits ────────────────────────────────────
# Applies when a group total is known but BOTH its components are still unknown.
# The original-state flags (.cs_unk, .sg_unk) are captured before any mutation
# so later assignments in the same mutate() do not corrupt the conditions.

df_step4 <- df_derived %>%
  mutate(
    .cs_unk = is.na(clay_v)   & is.na(silt_v),   # both fines components unknown
    .sg_unk = is.na(sand_v)   & is.na(gravel_v),  # both coarse components unknown

    clay_v   = if_else(.cs_unk & !is.na(fines_v),
                       fines_v * p_clay_fines,           clay_v),
    silt_v   = if_else(.cs_unk & !is.na(fines_v),
                       fines_v * (1 - p_clay_fines),     silt_v),

    sand_v   = if_else(.sg_unk & !is.na(coarse_v),
                       coarse_v * (1 - p_gravel_coarse), sand_v),
    gravel_v = if_else(.sg_unk & !is.na(coarse_v),
                       coarse_v * p_gravel_coarse,        gravel_v),

    .cs_unk = NULL,
    .sg_unk = NULL
  )

# ── STEP 5: General background imputation for any remaining NAs ───────────────
# Known fractions are NEVER changed.
# Unknown fractions receive the remaining budget (100 − sum_known),
# distributed in proportion to their background weights.

df_imputed <- df_step4 %>%
  mutate(
    # Background weight is non-zero only for still-unknown fractions
    .bg_c = if_else(is.na(clay_v),   p_clay_bg,   0),
    .bg_s = if_else(is.na(silt_v),   p_silt_bg,   0),
    .bg_n = if_else(is.na(sand_v),   p_sand_bg,   0),
    .bg_g = if_else(is.na(gravel_v), p_gravel_bg, 0),
    .bg_denom = .bg_c + .bg_s + .bg_n + .bg_g,

    .sum_known = coalesce(clay_v,   0) + coalesce(silt_v,   0) +
                 coalesce(sand_v,   0) + coalesce(gravel_v, 0),
    .remaining = pmax(0, 100 - .sum_known),

    clay_v   = if_else(is.na(clay_v),
                       .remaining * .bg_c / pmax(.bg_denom, 1e-10), clay_v),
    silt_v   = if_else(is.na(silt_v),
                       .remaining * .bg_s / pmax(.bg_denom, 1e-10), silt_v),
    sand_v   = if_else(is.na(sand_v),
                       .remaining * .bg_n / pmax(.bg_denom, 1e-10), sand_v),
    gravel_v = if_else(is.na(gravel_v),
                       .remaining * .bg_g / pmax(.bg_denom, 1e-10), gravel_v)
  ) %>%
  select(-starts_with("."))

# ── STEP 6: Method labels and final output ────────────────────────────────────
#   "direct"     – fraction came from a direct measurement
#   "arithmetic" – derived from other measurements without any background ratio
#   "background" – at least one background ratio was needed

df_sediment_fractions <- df_imputed %>%
  left_join(df_pre_bg, by = c("sample_id", "sediment_no")) %>%
  mutate(
    clay_method = case_when(
      !is.na(GSMF2)    ~ "direct",
      clay_no_bg       ~ "arithmetic",
      TRUE             ~ "background"
    ),
    silt_method = case_when(
      !is.na(GSMF2_63) ~ "direct",
      silt_no_bg       ~ "arithmetic",
      TRUE             ~ "background"
    ),
    sand_method = case_when(
      !is.na(sand_sub) ~ "direct",
      sand_no_bg       ~ "arithmetic",
      TRUE             ~ "background"
    ),
    gravel_method = case_when(
      !is.na(GSMF_2000) ~ "direct",
      gravel_no_bg      ~ "arithmetic",
      TRUE              ~ "background"
    ),
    any_op_adjusted = if_any(ends_with("_op"), ~ !is.na(.) & . != "="),
    # total_pct ≈ 100 for imputed rows; may differ slightly for fully direct rows
    total_pct = clay_v + silt_v + sand_v + gravel_v
  ) %>%
  left_join(
    df_qc_flags %>% select(sample_id, sediment_no, qc_confidence,
                            total_pct_before_rescale,
                            penalty_decimal, penalty_dedup, penalty_total),
    by = c("sample_id", "sediment_no")
  ) %>%
  mutate(
    # Samples that passed through with no total (single-param, always ≤ 100)
    # get "high" by default, but degrade by 0b penalty if applicable
    qc_confidence = case_when(
      !is.na(qc_confidence) ~ qc_confidence,
      TRUE ~ left_join(
        tibble(sample_id, sediment_no),
        penalty_0b %>% mutate(qc_confidence = penalty_to_confidence(penalty_decimal)),
        by = c("sample_id", "sediment_no")
      )$qc_confidence
    )
  ) %>%
  rename(
    clay_pct   = clay_v,
    silt_pct   = silt_v,
    sand_pct   = sand_v,
    gravel_pct = gravel_v
  ) %>%
  dplyr::select(sample_id, sediment_no,
                clay_pct, silt_pct, sand_pct, gravel_pct, total_pct,
                clay_method, silt_method, sand_method, gravel_method,
                any_op_adjusted, qc_confidence)

print(df_sediment_fractions)

# ── STEP 7: Diagnostics ───────────────────────────────────────────────────────

message("\n── Fraction summary (%) ──")
df_sediment_fractions %>%
  summarise(across(
    ends_with("_pct"),
    list(mean = \(x) mean(x, na.rm = TRUE),
         sd   = \(x) sd(x,   na.rm = TRUE),
         min  = \(x) min(x,  na.rm = TRUE),
         max  = \(x) max(x,  na.rm = TRUE)),
    .names = "{.col}_{.fn}"
  )) %>%
  pivot_longer(everything(),
               names_to  = c("fraction", ".value"),
               names_sep = "_pct_") %>%
  print()

message("\n── Total % deviation from 100 ──")
df_sediment_fractions %>%
  filter(!is.na(total_pct)) %>%
  summarise(
    n_rows    = n(),
    exact_100 = sum(abs(total_pct - 100) < 0.01),
    within_1  = sum(abs(total_pct - 100) <  1),
    max_dev   = max(abs(total_pct - 100))
  ) %>%
  print()

message("\n── Derivation method breakdown ──")
df_sediment_fractions %>%
  count(clay_method, silt_method, sand_method, gravel_method, sort = TRUE) %>%
  print(n = 30)

message("\n── Operator-adjusted rows ──")
cat(sprintf("%d of %d rows had at least one non-'=' operator input\n",
            sum(df_sediment_fractions$any_op_adjusted, na.rm = TRUE),
            nrow(df_sediment_fractions)))

#
# Write data
#
write_tsv(df_sediment_fractions, "./data/pilot_vannmiljo_particles.tsv.gz")
