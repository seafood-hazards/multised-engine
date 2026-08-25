# ── Aquaculture reference database (Norway) ──────────────────────────────────
# A single table of Norwegian marine aquaculture sites, built from the two
# Fiskeridirektoratet ("Yggdrasil") exports. It is not a pipeline generation: it
# is a standalone reference that clean step 5 measures distances against.
#
# The active file carries decimal lat/lon AND projected x,y; the closed file
# carries only x,y. Both x,y are ETRS89 / UTM zone 33N (EPSG:25833), confirmed by
# round-tripping the active file's x,y against its own lat/lon (residual 56 m, the
# rounding of the file's 3-decimal lat/lon). lat/lon is therefore derived from x,y
# for BOTH files, uniformly and at full precision.
#
# The source is Norwegian; the categorical descriptors and species are translated
# to English (proper place / site names are kept as-is). Sites with a salt-water
# component are kept: salt, brackish and mixed fresh/salt; pure freshwater is
# dropped.
#
# Non-ASCII belongs in comments but not in code, so the Norwegian keys below are
# written as \uXXXX escapes.

aquaculture_build <- function(raw_dir = multised_raw_dir(),
                              db_dir = multised_db_dir(),
                              verbose = TRUE) {
  require_suggested("sf", "The aquaculture reference build")

  data_path <- file.path(raw_dir, "yggdrasil")
  files <- file.path(data_path, c("Lokaliteter.csv", "Slettete lokaliteter.csv"))
  for (f in files) {
    if (!file.exists(f)) stop("Yggdrasil export not found: ", f, call. = FALSE)
  }
  out_db <- aquaculture_db_path(db_dir)

  # ── 1. Translation lookups ───────────────────────────────────────────────────
  # Water environment -> English; kept sites are salt / brackish / fresh-salt.
  water_map <- c("SALTVANN" = "salt", "SALT" = "salt", "BRAKKVANN" = "brackish",
                 "FERSKVANN/SALTVANN" = "fresh/salt", "FERSKVANN" = "fresh")
  KEEP_WATER <- c("SALTVANN", "SALT", "BRAKKVANN", "FERSKVANN/SALTVANN")

  # Capacity unit codes -> standardised English tokens.
  unit_map <- c(TN = "tonnes", DA = "decare", STK = "count", KG = "kg",
                M2 = "m2", M3 = "m3", L = "litre", UNKNOWN = NA_character_)

  # Placement of the site.
  placement_map <- c("SJ\u00d8" = "sea", "LAND" = "land", "HAV" = "offshore",
                     "UKJENT" = "unknown")

  # Common commercial aquaculture species (marine). Rare / research-monitoring
  # species not listed here keep their Norwegian name (documented on the web page).
  species_map <- c(
    "Laks" = "Atlantic salmon", "\u00d8rret" = "Trout", "Regnbue\u00f8rret" = "Rainbow trout",
    "R\u00f8ye" = "Arctic char", "Torsk" = "Atlantic cod", "Kveite" = "Atlantic halibut",
    "Bl\u00e5kveite" = "Greenland halibut", "Sei" = "Saithe", "Lyr" = "Pollack",
    "Hyse" = "Haddock", "Brosme" = "Tusk", "Lysing" = "European hake",
    "Piggvar" = "Turbot", "R\u00f8dspette" = "European plaice", "Tunge" = "Common sole",
    "Breiflabb" = "Anglerfish", "Havabbor" = "European seabass",
    "Makrell" = "Atlantic mackerel", "Sild" = "Herring", "Brisling" = "Sprat",
    "\u00c5l" = "European eel", "Gr\u00e5steinbit" = "Atlantic wolffish",
    "Flekksteinbit" = "Spotted wolffish", "Bl\u00e5steinbit" = "Northern wolffish",
    "Rognkjeks" = "Lumpfish",
    # cleaner-fish wrasses
    "Berggylt" = "Ballan wrasse", "Bergnebb" = "Goldsinny wrasse",
    "Gr\u00f8nngylt" = "Corkwing wrasse", "Gressgylt" = "Rock cook",
    "Brungylt" = "Scale-rayed wrasse", "Bl\u00e5st\u00e5l/R\u00f8dnebb" = "Cuckoo wrasse",
    # shellfish / molluscs
    "Bl\u00e5skjell" = "Blue mussel", "O-skjell" = "Horse mussel",
    "Kamskjell" = "Great scallop", "Haneskjell" = "Icelandic scallop",
    "\u00d8sters" = "Flat oyster", "Stillehavs\u00f8sters" = "Pacific oyster",
    "Kongsnegl (Kongesnegl)" = "Common whelk", "Strandsnegl" = "Periwinkle",
    # crustaceans
    "Hummer" = "European lobster", "Sj\u00f8kreps" = "Norway lobster",
    "Taskekrabbe" = "Edible crab", "Kongekrabbe" = "Red king crab",
    "Sn\u00f8krabbe" = "Snow crab", "Dypvannsreke" = "Deep-water prawn",
    # echinoderms
    "Sj\u00f8piggsvin uspes." = "Sea urchin (unspecified)",
    "Dr\u00f8baksj\u00f8piggsvin" = "Green sea urchin",
    # macroalgae / kelp
    "Sukkertare (oppdrett)" = "Sugar kelp (farmed)", "Sukkertare" = "Sugar kelp",
    "Butare" = "Winged kelp", "Fingertare" = "Finger kelp", "Stortare" = "Cuvie",
    "Bladtare" = "Kelp (blade)", "Martaum" = "Sea lace", "Draugtare" = "Sea spaghetti",
    "S\u00f8l" = "Dulse", "Havsalat" = "Sea lettuce", "Krusflik" = "Carrageen moss",
    "Grisetang" = "Knotted wrack", "Bl\u00e6retang" = "Bladder wrack",
    "Fj\u00e6rehinne uspes" = "Laver (unspecified)", "Vanlig fj\u00e6rehinne" = "Common laver",
    "Gr\u00f8nnsekkdyr" = "Green sea squirt", "Sekkdyr" = "Sea squirt")

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
  A <- read_csv(file.path(data_path, "Lokaliteter.csv"),
                show_col_types = FALSE, name_repair = "minimal")
  C <- read_csv(file.path(data_path, "Slettete lokaliteter.csv"),
                show_col_types = FALSE, name_repair = "minimal")
  names(A) <- str_trim(names(A)); names(C) <- str_trim(names(C))
  # `vannmilj\u00f8` cannot be written as an escape inside backticks, so the
  # column is renamed before it is referred to.
  names(C)[names(C) == "vannmilj\u00f8"] <- "water_col"

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
    transmute(loknr = as.integer(loknr), name = loknavn, water = water_col, placement = plassering,
              capacity = `klarert kapasitet`, unit = `kapasitet enhet`,
              species = arter, county = fylkesnavn, municipality = kommunenavn,
              start_year = year_of(klareringsdato), end_year = year_of(`trukket dato`),
              active = 0L, x, y)

  both <- bind_rows(active, closed) |>
    filter(water %in% KEEP_WATER)   # salt / brackish / fresh-salt

  # ── 3. Derive lon/lat from x,y (EPSG:25833 -> WGS84) ─────────────────────────
  ll <- both |>
    sf::st_as_sf(coords = c("x", "y"), crs = 25833) |>
    sf::st_transform(4326) |>
    sf::st_coordinates()

  # capacity in the common unit (tonnes): mass units convert, others have no
  # tonnes equivalent (area / count / volume) and stay NA.
  to_tonnes <- function(cap, unit)
    case_when(unit == "TN" ~ cap, unit == "KG" ~ cap / 1000, TRUE ~ NA_real_)

  # ── Which sites are fish farms, and how big ────────────────────────────────
  # `fish_types` is the licence's species list, and it is long and noisy: 335
  # distinct entries across the register, most of them wild organisms recorded
  # against research and multi-species licences (herring, tuna, starfish). So the
  # test is a POSITIVE list of the finfish Norway actually grows in sea cages: a
  # site is called a fish farm only on evidence, never by failing to look like
  # something else.
  #
  # Cleaner fish (wrasse, lumpfish) are deliberately absent. They are farmed, but
  # a salmon licence lists salmon anyway, and including them would catch
  # wild-capture wrasse holding sites that are not a farm in the sediment sense.
  FARMED_FINFISH <- c(
    # salmonids, which are nearly all of it
    "Atlantic salmon", "Rainbow trout", "Trout", "Arctic char",
    # marine finfish
    "Atlantic cod", "Atlantic halibut", "Turbot", "European seabass", "Kingfish",
    "Spotted wolffish", "Atlantic wolffish", "Northern wolffish",
    "Saithe", "Pollack", "Haddock")

  names_finfish <- function(species) {
    vapply(strsplit(ifelse(is.na(species), "", species), ",", fixed = TRUE),
           function(p) any(trimws(p) %in% FARMED_FINFISH), logical(1))
  }

  # Norwegian finfish licences are issued in MTB (maksimalt tillatt biomasse), and
  # the standard concession is 780 t: the capacity distribution lands on exact
  # multiples of it (780, 1560, 2340, 3120, ...). Reporting size in concessions
  # rather than raw tonnes is the unit the licence is actually written in, reads
  # to a Norwegian regulator, and collapses the long tail sensibly.
  MTB_CONCESSION_T <- 780

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
    mutate(
      # a fish farm in the sediment sense: finfish, grown in the sea
      fish_farm = as.integer(names_finfish(fish_types) &
                             placement %in% c("sea", "offshore")),
      # size only where the licence is a biomass one; a sea cage licensed by
      # volume or head count is still a fish farm, just one of unknown size
      mtb_concessions = if_else(fish_farm == 1L,
                                round(capacity_tonnes / MTB_CONCESSION_T, 2),
                                NA_real_),
      size_band = case_when(
        is.na(mtb_concessions)   ~ NA_character_,
        mtb_concessions <= 2     ~ "small",     # up to 1560 t
        mtb_concessions <= 4     ~ "medium",    # up to 3120 t
        TRUE                     ~ "large")) |>
    transmute(aqua_id = row_number(), loknr, name, latitude, longitude,
              start_year, end_year, active, water_type,
              capacity, capacity_unit, capacity_tonnes,
              fish_farm, mtb_concessions, size_band,
              fish_types, placement, county, municipality)

  # ── Write the table ────────────────────────────────────────────────────────
  dir.create(dirname(out_db), showWarnings = FALSE, recursive = TRUE)
  con <- multised_con(out_db, must_exist = FALSE)
  on.exit(dbDisconnect(con), add = TRUE)
  dbExecute(con, "DROP TABLE IF EXISTS aquaculture")
  dbWriteTable(con, "aquaculture", as.data.frame(aqua), row.names = FALSE)
  dbExecute(con, "CREATE UNIQUE INDEX ix_aqua_pk ON aquaculture(aqua_id)")

  if (verbose) {
    cat("aquaculture_no.sqlite written:", nrow(aqua), "sites (salt / brackish)\n")
    cat("  active:", sum(aqua$active == 1), " closed:", sum(aqua$active == 0), "\n")
    cat("  water types:", paste(sort(unique(aqua$water_type)), collapse = ", "), "\n")
    cat("  year range:", min(aqua$start_year, na.rm = TRUE), "-",
        max(aqua$end_year, aqua$start_year, na.rm = TRUE), "\n")
    cat("  capacity units:",
        paste(sort(unique(na.omit(aqua$capacity_unit))), collapse = ", "), "\n")
    cat("  with capacity_tonnes:", sum(!is.na(aqua$capacity_tonnes)), "\n")
  }
  invisible(aqua)
}
