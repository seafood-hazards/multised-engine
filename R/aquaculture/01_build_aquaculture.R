library(DBI)
library(RSQLite)
library(tidyverse)
library(sf)

# ── Aquaculture reference table (Norway) ─────────────────────────────────────
# Build a single DB table of Norwegian marine (salt + brackish) aquaculture sites
# from the two Fiskeridirektoratet ("Yggdrasil") exports:
#   Lokaliteter.csv          active sites (status AKTIV)
#   Slettete lokaliteter.csv closed/withdrawn sites (status TRUKKET)
#
# The active file carries decimal lat/lon AND projected x,y; the closed file
# carries only x,y. Both x,y are ETRS89 / UTM zone 33N (EPSG:25833), confirmed by
# round-tripping the active file's x,y against its own lat/lon (residual 56 m, the
# rounding of the file's 3-decimal lat/lon). We therefore derive lat/lon from x,y
# for BOTH files, uniformly and at full precision.
#
# The source is Norwegian; the categorical descriptors and species are translated
# to English (proper place / site names are kept as-is). Sites with a salt-water
# component are kept: salt (SALTVANN/SALT), brackish (BRAKKVANN) and mixed
# fresh/salt (FERSKVANN/SALTVANN); pure freshwater (FERSKVANN) is dropped.
#
# Output -> data/db/aquaculture_no.sqlite (table `aquaculture`).

raw_dir <- "data/raw/yggdrasil"
out_db  <- "data/db/aquaculture_no.sqlite"

# ── 1. Translation lookups ───────────────────────────────────────────────────
# Water environment -> English; kept sites are salt / brackish / fresh-salt.
water_map <- c("SALTVANN" = "salt", "SALT" = "salt", "BRAKKVANN" = "brackish",
               "FERSKVANN/SALTVANN" = "fresh/salt", "FERSKVANN" = "fresh")
KEEP_WATER <- c("SALTVANN", "SALT", "BRAKKVANN", "FERSKVANN/SALTVANN")

# Capacity unit codes -> standardised English tokens.
unit_map <- c(TN = "tonnes", DA = "decare", STK = "count", KG = "kg",
              M2 = "m2", M3 = "m3", L = "litre", UNKNOWN = NA_character_)

# Placement of the site.
placement_map <- c("SJØ" = "sea", "LAND" = "land", "HAV" = "offshore",
                   "UKJENT" = "unknown")

# Common commercial aquaculture species (marine). Rare / research-monitoring
# species not listed here keep their Norwegian name (documented on the web page).
species_map <- c(
  "Laks" = "Atlantic salmon", "Ørret" = "Trout", "Regnbueørret" = "Rainbow trout",
  "Røye" = "Arctic char", "Torsk" = "Atlantic cod", "Kveite" = "Atlantic halibut",
  "Blåkveite" = "Greenland halibut", "Sei" = "Saithe", "Lyr" = "Pollack",
  "Hyse" = "Haddock", "Brosme" = "Tusk", "Lysing" = "European hake",
  "Piggvar" = "Turbot", "Rødspette" = "European plaice", "Tunge" = "Common sole",
  "Breiflabb" = "Anglerfish", "Havabbor" = "European seabass",
  "Makrell" = "Atlantic mackerel", "Sild" = "Herring", "Brisling" = "Sprat",
  "Ål" = "European eel", "Gråsteinbit" = "Atlantic wolffish",
  "Flekksteinbit" = "Spotted wolffish", "Blåsteinbit" = "Northern wolffish",
  "Rognkjeks" = "Lumpfish",
  # cleaner-fish wrasses
  "Berggylt" = "Ballan wrasse", "Bergnebb" = "Goldsinny wrasse",
  "Grønngylt" = "Corkwing wrasse", "Gressgylt" = "Rock cook",
  "Brungylt" = "Scale-rayed wrasse", "Blåstål/Rødnebb" = "Cuckoo wrasse",
  # shellfish / molluscs
  "Blåskjell" = "Blue mussel", "O-skjell" = "Horse mussel",
  "Kamskjell" = "Great scallop", "Haneskjell" = "Icelandic scallop",
  "Østers" = "Flat oyster", "Stillehavsøsters" = "Pacific oyster",
  "Kongsnegl (Kongesnegl)" = "Common whelk", "Strandsnegl" = "Periwinkle",
  # crustaceans
  "Hummer" = "European lobster", "Sjøkreps" = "Norway lobster",
  "Taskekrabbe" = "Edible crab", "Kongekrabbe" = "Red king crab",
  "Snøkrabbe" = "Snow crab", "Dypvannsreke" = "Deep-water prawn",
  # echinoderms
  "Sjøpiggsvin uspes." = "Sea urchin (unspecified)",
  "Drøbaksjøpiggsvin" = "Green sea urchin",
  # macroalgae / kelp
  "Sukkertare (oppdrett)" = "Sugar kelp (farmed)", "Sukkertare" = "Sugar kelp",
  "Butare" = "Winged kelp", "Fingertare" = "Finger kelp", "Stortare" = "Cuvie",
  "Bladtare" = "Kelp (blade)", "Martaum" = "Sea lace", "Draugtare" = "Sea spaghetti",
  "Søl" = "Dulse", "Havsalat" = "Sea lettuce", "Krusflik" = "Carrageen moss",
  "Grisetang" = "Knotted wrack", "Blæretang" = "Bladder wrack",
  "Fjærehinne uspes" = "Laver (unspecified)", "Vanlig fjærehinne" = "Common laver",
  "Grønnsekkdyr" = "Green sea squirt", "Sekkdyr" = "Sea squirt")

# Translate a comma-joined Norwegian species string; unknown tokens pass through.
translate_species <- function(x) {
  map_chr(x, function(s) {
    if (is.na(s) || !nzchar(str_trim(s))) return(NA_character_)
    toks <- str_trim(str_split(s, ",")[[1]])
    toks <- toks[nzchar(toks)]
    out  <- ifelse(toks %in% names(species_map), species_map[toks], toks)
    paste(unique(out), collapse = ", ")
  })
}

year_of <- function(d) as.integer(str_extract(d, "\\d{4}"))

# ── 2. Read + normalise each file to a common shape ──────────────────────────
A <- read_csv(file.path(raw_dir, "Lokaliteter.csv"),
              show_col_types = FALSE, name_repair = "minimal")
C <- read_csv(file.path(raw_dir, "Slettete lokaliteter.csv"),
              show_col_types = FALSE, name_repair = "minimal")
names(A) <- str_trim(names(A)); names(C) <- str_trim(names(C))

# first token of a hyphen-joined multilingual place name ("Troms - Romsa" -> "Troms")
first_name <- function(x) str_to_title(str_trim(str_split_fixed(x, " - ", 2)[, 1]))

# tidy a site name: drop stray quotes, blank the "shall be deleted" placeholder
clean_name <- function(x) {
  x <- str_trim(str_remove_all(x, '"'))
  x <- if_else(str_detect(x, regex("^skal slettes", ignore_case = TRUE)) | x == "",
               NA_character_, x)
  x
}

active <- A |>
  transmute(loknr = as.integer(loknr), name = navn, water = vannmiljo, placement = plassering,
            capacity = `klarert kapasitet`, unit = `kapasitet enhet`,
            species = arter, county = fylke, municipality = kommune,
            start_year = year_of(klareringsdato), end_year = NA_integer_,
            active = 1L, x, y)

closed <- C |>
  transmute(loknr = as.integer(loknr), name = loknavn, water = `vannmiljø`, placement = plassering,
            capacity = `klarert kapasitet`, unit = `kapasitet enhet`,
            species = arter, county = fylkesnavn, municipality = kommunenavn,
            start_year = year_of(klareringsdato), end_year = year_of(`trukket dato`),
            active = 0L, x, y)

both <- bind_rows(active, closed) |>
  filter(water %in% KEEP_WATER)   # salt / brackish / fresh-salt

# ── 3. Derive lon/lat from x,y (EPSG:25833 -> WGS84) ─────────────────────────
ll <- both |>
  st_as_sf(coords = c("x", "y"), crs = 25833) |>
  st_transform(4326) |>
  st_coordinates()

# capacity in the common unit (tonnes): mass units convert, others have no
# tonnes equivalent (area / count / volume) and stay NA.
to_tonnes <- function(cap, unit)
  case_when(unit == "TN" ~ cap, unit == "KG" ~ cap / 1000, TRUE ~ NA_real_)

aqua <- both |>
  mutate(capacity = suppressWarnings(as.numeric(capacity)),
         longitude = round(ll[, 1], 5), latitude = round(ll[, 2], 5),
         water_type = unname(water_map[water]),
         capacity_unit = unname(unit_map[unit]),
         capacity_tonnes = round(to_tonnes(capacity, unit), 2),
         placement = unname(placement_map[placement]),
         fish_types = translate_species(species),
         county = first_name(county), municipality = first_name(municipality)) |>
  mutate(name = clean_name(name)) |>
  arrange(desc(active), loknr) |>
  transmute(aqua_id = row_number(), loknr, name, latitude, longitude,
            start_year, end_year, active, water_type,
            capacity, capacity_unit, capacity_tonnes,
            fish_types, placement, county, municipality)

# ── 4. Write the table ───────────────────────────────────────────────────────
dir.create(dirname(out_db), showWarnings = FALSE, recursive = TRUE)
con <- dbConnect(SQLite(), out_db)
dbExecute(con, "DROP TABLE IF EXISTS aquaculture")
dbWriteTable(con, "aquaculture", as.data.frame(aqua), row.names = FALSE)
dbExecute(con, "CREATE UNIQUE INDEX ix_aqua_pk ON aquaculture(aqua_id)")
dbDisconnect(con)

# ── 5. Console summary ───────────────────────────────────────────────────────
cat("aquaculture_no.sqlite written:", nrow(aqua), "sites (salt / brackish)\n")
cat("  active:", sum(aqua$active == 1), " closed:", sum(aqua$active == 0), "\n")
cat("  water types:", paste(sort(unique(aqua$water_type)), collapse = ", "), "\n")
cat("  year range:", min(aqua$start_year, na.rm = TRUE), "-",
    max(aqua$end_year, aqua$start_year, na.rm = TRUE), "\n")
cat("  capacity units:", paste(sort(unique(na.omit(aqua$capacity_unit))), collapse = ", "), "\n")
cat("  with capacity_tonnes:", sum(!is.na(aqua$capacity_tonnes)), "\n")
