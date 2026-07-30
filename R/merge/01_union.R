library(DBI)
library(RSQLite)
library(tidyverse)

# ── Merge stage 1: union the five clean DBs (prefixed keys) ──────────────────
# Combine the per-source clean DBs into one, with every key prefixed by a source
# code so keys from different sources cannot mix. Adds a `source` column and the
# harmonised sieve-cutoff columns. No deduplication yet (that is 02_dedup.R).
#
# Output -> data/db/multised_merged.sqlite (prefixed keys; pre-dedup).

# code = key prefix, stem = clean DB file, pref = source preference (1 = highest).
SOURCES <- tribble(
  ~Source,      ~stem,        ~code,  ~pref,
  "Mareano",    "mareano",    "mar",  1L,
  "4Demon",     "4demon",     "dem",  2L,
  "MUDAB",      "mudab",      "mud",  3L,
  "Vannmiljø",  "vannmiljo",  "van",  4L,
  "ICES-DOME",  "ices_dome",  "ice",  5L)

out_db <- "data/db/multised_merged.sqlite"

# every table and which of its columns are keys to prefix (element is the shared
# vocabulary: no keys prefixed, no source column).
KEY_COLS <- list(
  element             = character(0),
  dataset             = "dataset_id",
  site                = "site_id",
  event               = c("event_id", "dataset_id", "site_id"),
  subsample           = c("subsample_id", "event_id"),
  measurement         = c("measurement_id", "subsample_id", "method_id"),
  method              = "method_id",
  grain_size_fraction = c("gsf_id", "subsample_id"))

# ── 1. Read + prefix each source ─────────────────────────────────────────────
prefix_keys <- function(df, cols, code) {
  for (c in intersect(cols, names(df)))
    df[[c]] <- paste0(code, "_", df[[c]])
  df
}

read_source <- function(stem, code, Source) {
  con <- dbConnect(SQLite(), sprintf("data/db/%s_clean.sqlite", stem))
  on.exit(dbDisconnect(con))
  have <- dbListTables(con)
  imap(KEY_COLS, function(cols, tbl) {
    if (!tbl %in% have) return(NULL)                       # 4Demon: no grain_size
    df <- as_tibble(dbReadTable(con, tbl)) |> prefix_keys(cols, code)
    if (tbl != "element") df$source <- Source             # element is sourceless
    df
  })
}

per_source <- pmap(SOURCES, function(Source, stem, code, pref)
  read_source(stem, code, Source))
names(per_source) <- SOURCES$Source

# ── 2. Union table by table ──────────────────────────────────────────────────
union_table <- function(tbl) {
  parts <- map(per_source, tbl) |> compact()
  bind_rows(parts)
}

merged <- set_names(map(names(KEY_COLS), union_table), names(KEY_COLS))

# element: collapse the shared vocabulary to distinct rows
merged$element <- distinct(merged$element)
dup_sym <- merged$element |> count(symbol) |> filter(n > 1)
if (nrow(dup_sym) > 0)
  warning("element symbols with conflicting rows: ",
          paste(dup_sym$symbol, collapse = ", "))

# ── 3. Harmonised sieve cutoff on measurement ────────────────────────────────
# canonical numeric cutoff (62 -> 63; others unchanged) + label; NULL for bulk.
merged$measurement <- merged$measurement |>
  mutate(sieve_um_std = if_else(frac_class == "sieved",
                                if_else(sieve_um == 62, 63, sieve_um), NA_real_),
         sieve_class  = if_else(!is.na(sieve_um_std),
                                paste0("<", sieve_um_std, "um"), NA_character_))

# ── 4. Write the merged DB ───────────────────────────────────────────────────
dir.create(dirname(out_db), showWarnings = FALSE, recursive = TRUE)
con <- dbConnect(SQLite(), out_db)
for (tbl in names(merged)) {
  dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tbl))
  dbWriteTable(con, tbl, as.data.frame(merged[[tbl]]), row.names = FALSE)
}
dbDisconnect(con)

# ── 5. Console summary ───────────────────────────────────────────────────────
cat("multised_merged.sqlite (pre-dedup) written\n")
for (tbl in names(merged))
  cat(sprintf("  %-20s %7d rows\n", tbl, nrow(merged[[tbl]])))
cat("measurement by source:\n")
merged$measurement |> count(source) |> as.data.frame() |> print(row.names = FALSE)
cat("sieved sieve_class:\n")
merged$measurement |> filter(frac_class == "sieved") |> count(sieve_class) |>
  as.data.frame() |> print(row.names = FALSE)
