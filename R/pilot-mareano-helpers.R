# ── Pilot helpers, Mareano ───────────────────────────────────────────────────
# Moved verbatim from R/pilot/mareano/sedimeter_helpers.R, which the Mareano
# parse scripts used to source(). These read blocks out of the Mareano workbook
# by Excel range, since the sheets carry several tables side by side under a
# two-row header rather than one rectangular table.
#
# Original function names are kept, including the `repalce_na` spelling, so the
# sliced bodies below need no edits.

# -------------------------------------------------------------------
# Simple helpers
# -------------------------------------------------------------------
# Keep original name to avoid refactors in your codebase
repalce_na <- function(x) ifelse(is.na(x), "", x)

to_numeric_safe <- function(x) {
  suppressWarnings(as.numeric(x))
}

# -------------------------------------------------------------------
# Excel range & sheet helpers
# -------------------------------------------------------------------
excel_col_to_index <- function(col_letters) {
  col_letters <- toupper(col_letters)
  vals <- utf8ToInt(col_letters) - utf8ToInt("A") + 1
  acc <- 0L
  i <- 1L
  while (i <= length(vals)) {
    acc <- acc * 26L + vals[i]
    i <- i + 1L
  }
  acc
}

parse_excel_range <- function(rng) {
  m <- stringr::str_match(rng, "^([A-Za-z]+)(\\d+):([A-Za-z]+)(\\d+)$")
  if (is.na(m[1, 1])) stop("Invalid range: ", rng)
  c1 <- excel_col_to_index(m[1, 2])
  r1 <- as.integer(m[1, 3])
  c2 <- excel_col_to_index(m[1, 4])
  r2 <- as.integer(m[1, 5])
  list(
    col1 = min(c1, c2), col2 = max(c1, c2),
    row1 = min(r1, r2), row2 = max(r1, r2)
  )
}

# Read a whole sheet with no column names (preserve raw positions)
read_sheet_raw <- function(excel_file, sheet) {
  readxl::read_excel(excel_file, sheet = sheet, col_names = FALSE, col_types = "text")
}

# -------------------------------------------------------------------
# Header/catalog builders and block extraction
# -------------------------------------------------------------------

# Build catalog from first two rows (two-row header) of a raw sheet.
# Returns tibble: col_index, Row1, Row2, Full, ColType.
# numeric_full_names = character vector to hint numeric columns.
build_two_row_header_catalog <- function(sheet_df,
                                         header_rows = 1:2,
                                         numeric_full_names = character(0)) {
  if (length(header_rows) < 2) stop("header_rows must contain at least two rows")
  if (nrow(sheet_df) < max(header_rows)) stop("Sheet has fewer rows than header_rows")

  n <- ncol(sheet_df)
  row1 <- as.character(unlist(sheet_df[header_rows[1], 1:n, drop = TRUE]))
  row2 <- as.character(unlist(sheet_df[header_rows[2], 1:n, drop = TRUE]))

  catalog <- tibble::tibble(
    col_index = seq_len(n),
    Row1 = row1,
    Row2 = row2
  )

  catalog <- tidyr::fill(catalog, .data$Row1, .direction = "down")

  catalog <- dplyr::mutate(
    catalog,
    Row1 = stringr::str_trim(.data$Row1),
    Row2 = ifelse(is.na(.data$Row2), "", stringr::str_trim(.data$Row2)),
    Full = stringr::str_trim(paste(.data$Row1, .data$Row2)),
    ColType = ifelse(.data$Full %in% numeric_full_names, "numeric", "text")
  )

  catalog
}

# Extract a block when the header is INSIDE the selected range.
# If col_names = NULL -> use first row of block as headers (then drop that row)
# If col_names is character vector -> force names
# trim and drop_empty_cols control light cleanup
extract_block_header_in_range <- function(sheet_df,
                                          range,
                                          col_names = NULL,
                                          trim = TRUE,
                                          drop_empty_cols = TRUE) {
  dims <- parse_excel_range(range)
  nrow_df <- nrow(sheet_df); ncol_df <- ncol(sheet_df)
  rows <- seq.int(max(1, dims$row1), min(nrow_df, dims$row2))
  cols <- seq.int(max(1, dims$col1), min(ncol_df, dims$col2))

  blk <- tibble::as_tibble(sheet_df[rows, cols, drop = FALSE], .name_repair = "minimal")

  if (is.null(col_names)) {
    header_row <- blk[1, , drop = FALSE]
    new_names <- vapply(header_row, function(x) if (is.na(x)) "" else as.character(x), character(1))
    names(blk) <- make.names(new_names, unique = TRUE)
    blk <- blk[-1, , drop = FALSE]
  } else {
    if (length(col_names) != ncol(blk)) stop("col_names length does not match block width")
    names(blk) <- col_names
  }

  if (trim) {
    blk <- dplyr::mutate(blk, dplyr::across(where(is.character), function(x) trimws(x)))
  }

  if (drop_empty_cols) {
    # Vectorized, environment-agnostic check:
    # keep columns that are NOT entirely NA or (for characters) empty-string.
    keep <- vapply(blk, function(x) {
      if (is.character(x)) {
        !all(is.na(x) | trimws(x) == "")
      } else {
        !all(is.na(x))
      }
    }, logical(1))
    blk <- blk[, keep, drop = FALSE]
  }

  blk
}

# Extract a block by range and assign column names from a catalog$Full
slice_block_with_catalog <- function(sheet_df, catalog, range) {
  dims <- parse_excel_range(range)
  nrow_df <- nrow(sheet_df); ncol_df <- ncol(sheet_df)
  rows <- seq.int(max(1, dims$row1), min(nrow_df, dims$row2))
  cols <- seq.int(max(1, dims$col1), min(ncol_df, dims$col2))

  blk <- tibble::as_tibble(sheet_df[rows, cols, drop = FALSE], .name_repair = "minimal")
  names(blk) <- catalog$Full[cols]
  blk
}

# -------------------------------------------------------------------
# Column name helpers & row operations
# -------------------------------------------------------------------
rename_first_match_base <- function(df, candidates, new_name) {
  overlap <- intersect(names(df), candidates)
  if (length(overlap) == 0) {
    stop(sprintf("None of the candidate columns found for '%s'. Available: [%s]",
                 new_name, paste(names(df), collapse = ", ")))
  }
  old <- overlap[1]
  nm <- names(df)
  nm[nm == old] <- new_name
  names(df) <- nm
  df
}

# Generic row operations (avoid ~ lambdas; pass function(df) {...})
drop_where <- function(df, predicate) {
  idx <- predicate(df)
  df[!idx, , drop = FALSE]
}

update_where <- function(df, predicate, updates) {
  idx <- predicate(df)
  if (!any(idx)) return(df)
  nms <- names(updates)
  i <- 1L
  while (i <= length(nms)) {
    nm <- nms[i]
    df[[nm]][idx] <- updates[[i]]
    i <- i + 1L
  }
  df
}

# -------------------------------------------------------------------
# ID builders
# -------------------------------------------------------------------
build_cruise_id <- function(year, number) {
  paste("MA", year, number, sep = "-")
}

build_core_id <- function(station_no, sampling_tool, tool_serial_id, core_id) {
  serial <- repalce_na(tool_serial_id)
  serial <- ifelse(serial == "", "", stringr::str_pad(serial, width = 3, side = "left", pad = "0"))
  core   <- ifelse(is.na(core_id) | core_id == "", "00", as.character(core_id))
  paste(station_no, sampling_tool, serial, core, sep = "-")
}

build_sample_id <- function(core_id, from_cm, to_cm) {
  fromp <- stringr::str_pad(as.character(from_cm), width = 2, side = "left", pad = "0")
  top   <- stringr::str_pad(as.character(to_cm),   width = 2, side = "left", pad = "0")
  paste0(core_id, "_", fromp, "-", top)
}

# -------------------------------------------------------------------
# Corrections (table-driven) for Full-ID + depth ranges
# -------------------------------------------------------------------
# corrections_tbl must have: full_id, drop (logical), new_from, new_to
apply_fullid_corrections <- function(df, fullid_col,
                                     from_col, to_col,
                                     corrections_tbl) {
  # Drop rows
  drops <- corrections_tbl[which(corrections_tbl$drop %in% TRUE), , drop = FALSE]
  if (nrow(drops) > 0) {
    df <- df[!(df[[fullid_col]] %in% drops$full_id), , drop = FALSE]
  }

  # Fix from/to ranges using base match (no joins)
  fixes <- corrections_tbl[which(!corrections_tbl$drop %in% TRUE), , drop = FALSE]
  if (nrow(fixes) > 0) {
    m <- match(df[[fullid_col]], fixes$full_id)
    # new_from
    new_from <- fixes$new_from[m]
    cond_from <- !is.na(new_from)
    df[[from_col]][cond_from] <- new_from[cond_from]
    # new_to
    new_to <- fixes$new_to[m]
    cond_to <- !is.na(new_to)
    df[[to_col]][cond_to] <- new_to[cond_to]
  }

  df
}

# -------------------------------------------------------------------
# Value cleaning + long pivot for measurement columns (by catalog)
# -------------------------------------------------------------------
# Detect "<" or &lt; as LOD flag
mark_lod_flag <- function(x) {
  stringr::str_detect(x, "<|&lt;")
}

# Remove "<" / "&lt;" and "± ..." then coerce to numeric
strip_lod_and_plusminus_to_numeric <- function(x) {
  cleaned <- stringr::str_remove_all(x, "<|&lt;|\u00b1.*")
  suppressWarnings(as.numeric(cleaned))
}

# Pivot to long for measurement columns defined by non-empty Row2 in catalog
# id_cols: character vector of id columns to keep (e.g., c("cruise_id","core_id","sample_id"))
pivot_measurements_long <- function(df, catalog, id_cols) {
  meas_cols <- catalog %>%
    dplyr::filter(!is.na(.data$Row2) & .data$Row2 != "") %>%
    dplyr::pull(.data$Full)

  meas_cols <- intersect(meas_cols, names(df))
  # Bind ids + measurements, then pivot the measurement columns
  keep_cols <- c(id_cols, meas_cols)
  base <- df[, keep_cols, drop = FALSE]

  long_df <- tidyr::pivot_longer(
    base,
    cols = all_of(meas_cols),
    names_to = "Full",
    values_to = "value"
  )

  # Clean and map parameter
  long_df <- long_df[!(is.na(long_df$value) | long_df$value == "n.a."), , drop = FALSE]
  long_df$is_lld <- mark_lod_flag(long_df$value)
  long_df$new_value <- strip_lod_and_plusminus_to_numeric(long_df$value)

  cat_map <- catalog[, c("Full", "Row1")]
  out <- dplyr::inner_join(long_df, cat_map, by = "Full")

  # Build final tibble without tidy-eval
  cols_to_keep <- c(id_cols, "Row1", "new_value", "is_lld")
  out <- out[, cols_to_keep, drop = FALSE]
  names(out)[which(names(out) == "Row1")] <- "parameter"
  names(out)[which(names(out) == "new_value")] <- "value"
  out
}

# -------------------------------------------------------------------
# Rightward-fill function for NA
# -------------------------------------------------------------------
fill_from_right <- function(df) {
  n <- ncol(df)
  for (i in (n - 1):1) {
    df[[i]] <- coalesce(df[[i]], df[[i + 1]])
  }
  df
}
