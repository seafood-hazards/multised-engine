#' @keywords internal
"_PACKAGE"

## Package-level imports.
##
## The pipeline was written as scripts under `library(DBI)` / `library(RSQLite)`
## / `library(tidyverse)`, so it calls those functions unqualified throughout.
## Importing them by name here lets the step bodies move across unchanged, which
## keeps the conversion mechanical and reviewable.

#' @import dplyr
#' @importFrom DBI dbConnect dbDisconnect dbExecute dbGetQuery dbReadTable
#'   dbWriteTable dbListFields dbListTables dbExistsTable dbAppendTable
#'   dbRemoveTable dbBegin dbCommit dbRollback
#' @importFrom RSQLite SQLite
#' @importFrom tibble tibble tribble as_tibble
#' @importFrom tidyr pivot_longer pivot_wider replace_na separate separate_rows
#'   unite fill unnest drop_na expand_grid
#' @importFrom lubridate year
#' @importFrom stringr str_to_upper str_to_lower str_trim str_remove
#'   str_remove_all str_replace str_replace_all str_detect str_extract
#'   str_match str_starts str_split str_sub str_pad fixed regex
#' @importFrom readr read_tsv write_tsv read_csv write_csv
#' @importFrom purrr map map_chr map_dbl map_lgl map_int keep discard
#'   map_dfr pmap pmap_dfr walk compact
#' @importFrom rlang .data :=
#' @importFrom stats median quantile sd setNames binom.test coef cor dist
#'   dnorm kmeans lm mad
#' @importFrom utils head tail
NULL
