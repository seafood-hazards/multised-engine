# ── seastamp: shared location annotation ─────────────────────────────────────
# One wrapper around the `seastamp` CLI (https://github.com/AIQC-Hub/seastamp,
# formerly `geoenrich`), used by every stage that needs location attributes:
# the pilot station frames and the clean `site` tables.
#
# Replaces two separate implementations: the clean stage already called this
# tool, while the pilot stage did the same work again in R with sf +
# rnaturalearth + giscoR. One tool, one set of reference data, one set of values.
#
# Columns produced:
#   dist_to_coast  km (GSHHG full resolution)
#   depth          = -bathymetry (GEBCO is negative below sea level; stored
#                    positive-down). Points GEBCO places on land (bathymetry > 0)
#                    get depth = NULL.
#   sea_name       IHO Sea Areas
#   country        Natural Earth (global)
#   country_code   Natural Earth ISO alpha-3 (NOR, DEU)
#   municipality   GISCO LAU (Europe only, so non-European sites may be NULL)

# The tool was renamed geoenrich -> seastamp at 0.9.0 (commands, flags and output
# columns unchanged). No fallback to the old `geoenrich` binary on purpose: it
# stops at 0.8.0, whose default region differs, so silently running it would give
# different distances rather than an error.
#' @rdname multised_db_dir
#' @export
multised_seastamp_bin <- function() {
  configured <- getOption("multised.seastamp_bin", Sys.getenv("SEASTAMP_BIN", ""))
  bin <- if (nzchar(configured)) configured else unname(Sys.which("seastamp"))
  if (!nzchar(bin) || !file.exists(bin)) {
    stop(if (nzchar(configured)) {
           paste0("seastamp not found at ", sQuote(configured), ".")
         } else {
           "seastamp not found on the PATH."
         },
         " Install it from https://github.com/AIQC-Hub/seastamp so the system ",
         "can find it. Within an RStudio session, whose console does not ",
         "inherit the login shell's PATH, point at the binary instead:\n",
         "  options(multised.seastamp_bin = \"/path/to/seastamp\")\n",
         "or set SEASTAMP_BIN in ~/.Renviron.",
         call. = FALSE)
  }
  bin
}

# Reference datasets, under data/seastamp on disk (external storage). The tree
# was called data/geoenrich until the tool was renamed; anything still pointing
# at the old name needs `options(multised.seastamp_dir = ...)`.
seastamp_data <- function(seastamp_dir = multised_seastamp_dir()) {
  list(
    coast     = file.path(seastamp_dir, "gshhg/gshhg-shp-2.3.7/GSHHS_shp/f"),
    depth     = file.path(seastamp_dir, "gebco/GEBCO_2024_sub_ice_topo.nc"),
    sea       = file.path(seastamp_dir, "iho/World_Seas_IHO_v3/World_Seas_IHO_v3.shp"),
    countries = file.path(seastamp_dir, "naturalearth/ne_10m_admin_0_countries.shp"),
    muni      = file.path(seastamp_dir, "gisco/LAU_RG_01M_2021_4326.shp"))
}

#' Annotate coordinates with location attributes
#'
#' Runs the external `seastamp` command-line tool over a table of points and
#' returns the location attributes for each: distance to coast, sea-floor depth,
#' sea name, country, country code and municipality.
#'
#' This is the single location-annotation path for the whole pipeline. It needs
#' the `seastamp` binary and its reference datasets (GSHHG, GEBCO, IHO, Natural
#' Earth, GISCO); neither ships with the package.
#'
#' @param points A data frame with an id column and longitude/latitude columns.
#' @param id_col,lon_col,lat_col Column names in `points`.
#' @param seastamp_dir Directory holding the reference datasets.
#' @param seastamp_bin Path to the seastamp executable. Defaults to
#'   [multised_seastamp_bin()].
#' @param work_dir Scratch directory for the intermediate TSVs.
#' @param partition Use seastamp's `--partition`, the project default (`TRUE`).
#'   The points are split into sub-regions, each measured in its own projection,
#'   halving until every distance is within 2% of true. It takes no region of its
#'   own, so `region` must be `NULL` when this is `TRUE`.
#'
#'   Requires **seastamp >= 0.16.2**, which is checked: `--partition` arrived at
#'   0.14.0, but 0.16.2 fixed it over-estimating distance near the poles and the
#'   antimeridian, and this project's sites reach 81.5 lat.
#' @param region seastamp's projection region, used only when `partition` is
#'   `FALSE`. `"auto"` derives one projection centre from the points; `"global"`
#'   reproduces the values stored by the pre-0.9.0 `geoenrich` builds.
#'
#'   Measured over the 26,849 refined sites, seastamp's own distortion bound is
#'   **25%** for `global`, **3%** for `auto` and **1.32%** for `partition`. The
#'   error is proportional, so it is invisible near shore and largest where the
#'   EF reference is drawn: beyond 10 km, `auto` and `partition` agree to within
#'   0.3%, while `global` runs -10% to +12% out. `depth` does not project, so it
#'   is unaffected by any of this. See `docs/clean-pipeline.md`.
#' @param verbose Print progress.
#'
#' @return A data frame with the id column plus `depth`, `country`,
#'   `country_code`, `dist_to_coast`, `municipality` and `sea_name`.
#' @export
#' @examples
#' \dontrun{
#' pts <- data.frame(site_id = 1:2,
#'                   longitude = c(5.32, 10.75),
#'                   latitude  = c(60.39, 59.91))
#' seastamp_enrich(pts)
#'
#' # reproduce the pre-0.9.0 stored values
#' seastamp_enrich(pts, partition = FALSE, region = "global")
#' }
seastamp_enrich <- function(points,
                            id_col   = "site_id",
                            lon_col  = "longitude",
                            lat_col  = "latitude",
                            seastamp_dir  = multised_seastamp_dir(),
                            seastamp_bin  = multised_seastamp_bin(),
                            work_dir = file.path(tempdir(), "seastamp"),
                            partition = TRUE,
                            region   = if (partition) NULL else "auto",
                            verbose  = TRUE) {
  stopifnot(is.data.frame(points))
  if (partition && !is.null(region)) {
    stop("`partition = TRUE` derives its own projections, so `region` must be ",
         "NULL. Pass `partition = FALSE` to choose a region by hand.",
         call. = FALSE)
  }
  if (!partition && is.null(region)) {
    stop("`partition = FALSE` needs a `region`; seastamp's own default centres ",
         "the projection on (0, 0), which is 25% out for this data.",
         call. = FALSE)
  }
  missing <- setdiff(c(id_col, lon_col, lat_col), names(points))
  if (length(missing)) {
    stop("`points` has no column(s): ", paste(missing, collapse = ", "),
         call. = FALSE)
  }

  BIN  <- seastamp_bin
  # --partition arrived at 0.14.0, but 0.16.2 fixed it over-estimating distance
  # near the poles and the antimeridian: a point at (-179, 86) read 1595.58 km
  # against a true 958.68 km. This project's sites reach 81.5 lat, so an older
  # binary would answer rather than fail, and answer wrongly.
  if (partition) seastamp_require_version(BIN, "0.16.2")

  data <- seastamp_data(seastamp_dir)
  absent <- names(data)[!file.exists(unlist(data))]
  if (length(absent)) {
    stop("seastamp reference data not found for: ", paste(absent, collapse = ", "),
         "\nLooked under ", seastamp_dir, ". Fetch them with the tool's ",
         "scripts/download_data.sh.", call. = FALSE)
  }

  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  run <- function(args) {
    status <- system2(BIN, args, stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(status, "status")) && attr(status, "status") != 0) {
      stop(basename(BIN), " failed:\n", paste(status, collapse = "\n"),
           call. = FALSE)
    }
    invisible(status)
  }

  tsv_opts <- c("--in-format", "tsv", "--out-format", "tsv")
  # The projection applies to the projecting commands only (coast, sea, place);
  # depth and nearest do not project. --partition and --region are mutually
  # exclusive: seastamp rejects the pair.
  proj_opts <- if (partition) "--partition" else c("--region", region)

  tag <- paste0("pts_", as.integer(stats::runif(1, 1, 1e9)))
  in_tsv <- file.path(work_dir, paste0(tag, "_0in.tsv"))
  f1 <- file.path(work_dir, paste0(tag, "_1coast.tsv"))
  f2 <- file.path(work_dir, paste0(tag, "_2depth.tsv"))
  f3 <- file.path(work_dir, paste0(tag, "_3sea.tsv"))
  f4 <- file.path(work_dir, paste0(tag, "_4place.tsv"))
  on.exit(unlink(c(in_tsv, f1, f2, f3, f4)), add = TRUE)

  # seastamp expects its coordinate columns to be named; rename on the way in.
  std <- points[, c(id_col, lon_col, lat_col)]
  names(std) <- c(id_col, "longitude", "latitude")
  write_tsv(std, in_tsv)

  run(c("coast", in_tsv, "--data", data$coast, "--unit", "km",
        proj_opts, tsv_opts, "-o", f1))
  # depth reads GEBCO via HDF5. seastamp 0.9.1 serialises the grid lookup itself
  # after a thread-safety segfault; -t 1 is belt-and-braces.
  run(c("depth", f1, "--data", data$depth, "-t", "1", tsv_opts, "-o", f2))
  run(c("sea",   f2, "--data", data$sea, proj_opts, tsv_opts, "-o", f3))
  run(c("place", f3, "--countries", data$countries,
        "--municipalities", data$muni, proj_opts, tsv_opts, "-o", f4))

  enr <- read_tsv(f4, show_col_types = FALSE)
  out <- enr |>
    transmute(
      !!id_col := .data[[id_col]],
      # positive-down depth; GEBCO land points (bathymetry > 0) -> NULL
      depth         = if_else(bathymetry <= 0, round(-bathymetry, 1), NA_real_),
      country,
      country_code,
      dist_to_coast = round(dist_to_coast, 3),
      municipality,
      sea_name)

  if (verbose) {
    cat(sprintf("seastamp: %d points annotated (%s)\n", nrow(out),
                if (partition) "partitioned" else paste("region", region)))
  }
  out
}

# The six columns seastamp owns, in the order the pipeline stores them.
SEASTAMP_COLS <- c("depth", "country", "country_code",
                   "dist_to_coast", "municipality", "sea_name")

# ── Version guard ────────────────────────────────────────────────────────────
# `seastamp --version` prints "seastamp X.Y.Z". Compared numerically, not as a
# string, so 0.16.2 does not sort below 0.9.1.
seastamp_version <- function(bin) {
  out <- tryCatch(system2(bin, "--version", stdout = TRUE, stderr = TRUE),
                  error = function(e) character(0))
  v <- regmatches(out, regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", out))
  if (!length(v)) return(NA_character_)
  v[[1]]
}

seastamp_require_version <- function(bin, minimum) {
  have <- seastamp_version(bin)
  if (is.na(have)) {
    stop("could not read a version from ", sQuote(bin),
         "; seastamp >= ", minimum, " is required for `partition = TRUE`.",
         call. = FALSE)
  }
  if (utils::compareVersion(have, minimum) < 0) {
    stop("seastamp ", have, " is too old for `partition = TRUE`; ", minimum,
         " or newer is required.\n",
         "0.16.2 fixed --partition over-estimating distance near the poles, and ",
         "this project's sites reach 81.5 lat.\n",
         "Upgrade, or pass `partition = FALSE, region = \"auto\"`.",
         call. = FALSE)
  }
  invisible(have)
}
