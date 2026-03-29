library(tidyverse)

# ── Constants ──────────────────────────────────────────────────────────────────

SAND_SUBCOLS  <- c("GSMF63_125", "GSMF125_250", "GSMF250_500",
                   "GSMF500_1000", "GSMF1000_2000")
ALL_MEAS_COLS <- c("GSMF2", "GSMF2_63", "FINS", "GSMF_63", SAND_SUBCOLS, "GSMF_2000")

# ── STEP 0: Adjust values for operators ────────────────────────────────────────
#   ND  → 0           (not detected = effectively zero)
#   "<" → value / 2   (below detection/quantification limit; half as point estimate)
#   ">" → value        (lower bound; treated as measured, flagged in output)
#   "=" → value        (exact)

df_p_adj <- df_p %>%
  mutate(
    value_adj = case_when(
      operator == "ND" ~ 0,
      operator == "<"  ~ value / 2,
      TRUE             ~ value
    )
  )

# ── STEP 1: Wide format (operator-adjusted values + operator strings) ──────────

df_val <- df_p_adj %>%
  distinct(sample_id, sediment_no, param_id, value_adj) %>%
  pivot_wider(names_from = param_id, values_from = value_adj)

df_ops <- df_p_adj %>%
  distinct(sample_id, sediment_no, param_id, operator) %>%
  pivot_wider(names_from  = param_id,
              values_from = operator,
              names_glue  = "{param_id}_op")

# Guarantee all measurement columns exist (fill absent ones with NA)
for (col in ALL_MEAS_COLS) {
  if (!col %in% names(df_val)) df_val[[col]] <- NA_real_
}

df_wide <- df_val %>%
  left_join(df_ops, by = c("sample_id", "sediment_no")) %>%
  arrange(sample_id, sediment_no)

# ── STEP 2: Derive group-level totals ─────────────────────────────────────────

df_raw <- df_wide %>%
  mutate(
    # Sum available sand sub-fractions (NA if none measured)
    sand_sub = if_else(
      if_any(all_of(SAND_SUBCOLS), ~ !is.na(.)),
      rowSums(across(all_of(SAND_SUBCOLS)), na.rm = TRUE),
      NA_real_
    ),

    # Fines group total (<63 µm = Clay + Silt)
    # Priority: direct FINS > sum of GSMF2 + GSMF2_63
    fines_grp = case_when(
      !is.na(FINS)                        ~ FINS,
      !is.na(GSMF2) & !is.na(GSMF2_63)  ~ GSMF2 + GSMF2_63,
      TRUE                                 ~ NA_real_
    ),

    # Coarse group total (>63 µm = Sand + Gravel)
    # Priority: direct GSMF_63 > sum of components
    coarse_grp = case_when(
      !is.na(GSMF_63)                          ~ GSMF_63,
      !is.na(sand_sub) & !is.na(GSMF_2000)    ~ sand_sub + GSMF_2000,
      TRUE                                       ~ NA_real_
    )
  )

# ── STEP 3: Background ratios (computed from directly measured pairs) ──────────

# Clay / FINS  (only rows where both GSMF2 and FINS are directly available)
clay_fines_ratio <- df_raw %>%
  filter(!is.na(GSMF2), !is.na(FINS), FINS > 0) %>%
  summarise(r = median(GSMF2 / FINS, na.rm = TRUE)) %>%
  pull(r)

# GSMF_2000 / GSMF_63  (only rows where both are directly available)
gravel_coarse_ratio <- df_raw %>%
  filter(!is.na(GSMF_2000), !is.na(GSMF_63), GSMF_63 > 0) %>%
  summarise(r = median(GSMF_2000 / GSMF_63, na.rm = TRUE)) %>%
  pull(r)

message(sprintf("Background clay/(clay+silt) ratio  [median]: %.4f", clay_fines_ratio))
message(sprintf("Background gravel/(sand+gravel) ratio [median]: %.4f", gravel_coarse_ratio))

# ── STEP 4: Resolve group totals via 100 % constraint ─────────────────────────

df_grp <- df_raw %>%
  mutate(
    fines_use = case_when(
      !is.na(fines_grp)   ~ fines_grp,
      !is.na(coarse_grp)  ~ 100 - coarse_grp,
      TRUE                 ~ NA_real_
    ),
    coarse_use = case_when(
      !is.na(coarse_grp)  ~ coarse_grp,
      !is.na(fines_grp)   ~ 100 - fines_grp,
      TRUE                 ~ NA_real_
    )
  )

# ── STEP 5: Derive the four fractions with derivation-method tracking ──────────

df_frac <- df_grp %>%
  mutate(

    # ── Clay (<2 µm) ─────────────────────────────────────────────────────────
    clay = case_when(
      !is.na(GSMF2)                             ~ GSMF2,
      !is.na(fines_use) & !is.na(GSMF2_63)     ~ pmax(0, fines_use - GSMF2_63),
      !is.na(fines_use)                          ~ fines_use * clay_fines_ratio,
      TRUE                                        ~ NA_real_
    ),
    clay_method = case_when(
      !is.na(GSMF2)                             ~ "direct",
      !is.na(fines_use) & !is.na(GSMF2_63)     ~ "fines - silt",
      !is.na(fines_use)                          ~ "background_ratio",
      TRUE                                        ~ NA_character_
    ),

    # ── Silt (2–63 µm) ──────────────────────────────────────────────────────
    silt = case_when(
      !is.na(GSMF2_63)                          ~ GSMF2_63,
      !is.na(fines_use) & !is.na(GSMF2)        ~ pmax(0, fines_use - GSMF2),
      !is.na(fines_use)                          ~ fines_use * (1 - clay_fines_ratio),
      TRUE                                        ~ NA_real_
    ),
    silt_method = case_when(
      !is.na(GSMF2_63)                          ~ "direct",
      !is.na(fines_use) & !is.na(GSMF2)        ~ "fines - clay",
      !is.na(fines_use)                          ~ "background_ratio",
      TRUE                                        ~ NA_character_
    ),

    # ── Gravel (>2000 µm) ───────────────────────────────────────────────────
    gravel = case_when(
      !is.na(GSMF_2000)                         ~ GSMF_2000,
      !is.na(coarse_use) & !is.na(sand_sub)     ~ pmax(0, coarse_use - sand_sub),
      !is.na(coarse_use)                         ~ coarse_use * gravel_coarse_ratio,
      TRUE                                        ~ NA_real_
    ),
    gravel_method = case_when(
      !is.na(GSMF_2000)                         ~ "direct",
      !is.na(coarse_use) & !is.na(sand_sub)     ~ "coarse - sand",
      !is.na(coarse_use)                         ~ "background_ratio",
      TRUE                                        ~ NA_character_
    ),

    # ── Sand (63–2000 µm) ───────────────────────────────────────────────────
    sand = case_when(
      !is.na(sand_sub)                          ~ sand_sub,
      !is.na(coarse_use) & !is.na(GSMF_2000)   ~ pmax(0, coarse_use - GSMF_2000),
      !is.na(coarse_use)                         ~ coarse_use * (1 - gravel_coarse_ratio),
      TRUE                                        ~ NA_real_
    ),
    sand_method = case_when(
      !is.na(sand_sub)                          ~ "direct",
      !is.na(coarse_use) & !is.na(GSMF_2000)   ~ "coarse - gravel",
      !is.na(coarse_use)                         ~ "background_ratio",
      TRUE                                        ~ NA_character_
    ),

    # ── Operator-adjustment flag (any input was non-exact?) ─────────────────
    any_op_adjusted = if_any(ends_with("_op"), ~ !is.na(.) & . != "=")
  )

# ── STEP 6: Normalise to 100 % ────────────────────────────────────────────────

df_sediment_fractions <- df_frac %>%
  mutate(
    total      = clay + silt + sand + gravel,
    clay_pct   = 100 * clay   / total,
    silt_pct   = 100 * silt   / total,
    sand_pct   = 100 * sand   / total,
    gravel_pct = 100 * gravel / total
  ) %>%
  select(sample_id, sediment_no,
         clay_pct, silt_pct, sand_pct, gravel_pct,
         clay_method, silt_method, sand_method, gravel_method,
         any_op_adjusted)

print(df_sediment_fractions)

# ── STEP 7: Diagnostics ───────────────────────────────────────────────────────

message("\n── Fraction summary (%) ──")
df_sediment_fractions %>%
  summarise(across(ends_with("_pct"),
                   list(mean = \(x) mean(x, na.rm = TRUE),
                        sd   = \(x) sd(x,   na.rm = TRUE),
                        min  = \(x) min(x,  na.rm = TRUE),
                        max  = \(x) max(x,  na.rm = TRUE)),
                   .names = "{.col}_{.fn}")) %>%
  pivot_longer(everything(),
               names_to  = c("fraction", ".value"),
               names_sep = "_pct_") %>%
  print()

message("\n── Derivation method combinations (top 20) ──")
df_sediment_fractions %>%
  count(clay_method, silt_method, sand_method, gravel_method, sort = TRUE) %>%
  print(n = 20)

message("\n── Rows with operator-adjusted inputs ──")
cat(sum(df_sediment_fractions$any_op_adjusted, na.rm = TRUE),
    "of", nrow(df_sediment_fractions), "rows\n")

message("\n── Rows where total was not exactly 100 before normalisation ──")
df_frac %>%
  mutate(total = clay + silt + sand + gravel) %>%
  filter(!is.na(total), abs(total - 100) > 0.5) %>%
  count() %>%
  paste("n =", ., "\n") %>% cat()
