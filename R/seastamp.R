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
seastamp_bin <- function() {
  bin <- Sys.which("seastamp")
  if (bin == "") bin <- "/home/takaya/programs/seastamp/seastamp"
  if (!file.exists(bin)) {
    stop("seastamp not found. Install it from ",
         "https://github.com/AIQC-Hub/seastamp, or put it on the PATH.",
         call. = FALSE)
  }
  unname(bin)
}

# Reference datasets. Still under data/geoenrich on disk (external storage, not
# renamed with the tool).
seastamp_data <- function(geo_dir = "data/geoenrich") {
  list(
    coast     = file.path(geo_dir, "gshhg/gshhg-shp-2.3.7/GSHHS_shp/f"),
    depth     = file.path(geo_dir, "gebco/GEBCO_2024_sub_ice_topo.nc"),
    sea       = file.path(geo_dir, "iho/World_Seas_IHO_v3/World_Seas_IHO_v3.shp"),
    countries = file.path(geo_dir, "naturalearth/ne_10m_admin_0_countries.shp"),
    muni      = file.path(geo_dir, "gisco/LAU_RG_01M_2021_4326.shp"))
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
#' @param geo_dir Directory holding the reference datasets.
#' @param work_dir Scratch directory for the intermediate TSVs.
#' @param region seastamp's projection region. **`"global"` is the default here
#'   deliberately**: it reproduces the values already stored in the databases.
#'   seastamp 0.12.0 changed its own default to `"auto"`, which derives the
#'   projection from the points and is more accurate (the old whole-globe default
#'   was around 8% out on a Norwegian survey), but switching changes every
#'   `dist_to_coast` in the pipeline, so it is an explicit choice rather than a
#'   silent one.
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
#' # adopt seastamp's own, more accurate default instead
#' seastamp_enrich(pts, region = "auto")
#' }
seastamp_enrich <- function(points,
                            id_col   = "site_id",
                            lon_col  = "longitude",
                            lat_col  = "latitude",
                            geo_dir  = "data/geoenrich",
                            work_dir = file.path(tempdir(), "seastamp"),
                            region   = "global",
                            verbose  = TRUE) {
  stopifnot(is.data.frame(points))
  missing <- setdiff(c(id_col, lon_col, lat_col), names(points))
  if (length(missing)) {
    stop("`points` has no column(s): ", paste(missing, collapse = ", "),
         call. = FALSE)
  }

  BIN  <- seastamp_bin()
  data <- seastamp_data(geo_dir)
  absent <- names(data)[!file.exists(unlist(data))]
  if (length(absent)) {
    stop("seastamp reference data not found for: ", paste(absent, collapse = ", "),
         "\nLooked under ", geo_dir, ". Fetch them with the tool's ",
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
  # region applies to the projecting commands only (coast, sea, place); depth
  # and nearest do not project.
  reg_opts <- if (is.null(region)) character(0) else c("--region", region)

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
        reg_opts, tsv_opts, "-o", f1))
  # depth reads GEBCO via HDF5. seastamp 0.9.1 serialises the grid lookup itself
  # after a thread-safety segfault; -t 1 is belt-and-braces.
  run(c("depth", f1, "--data", data$depth, "-t", "1", tsv_opts, "-o", f2))
  run(c("sea",   f2, "--data", data$sea, reg_opts, tsv_opts, "-o", f3))
  run(c("place", f3, "--countries", data$countries,
        "--municipalities", data$muni, reg_opts, tsv_opts, "-o", f4))

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
    cat(sprintf("seastamp: %d points annotated (region %s)\n",
                nrow(out), if (is.null(region)) "tool default" else region))
  }
  out
}

# The six columns seastamp owns, in the order the pipeline stores them.
SEASTAMP_COLS <- c("depth", "country", "country_code",
                   "dist_to_coast", "municipality", "sea_name")
