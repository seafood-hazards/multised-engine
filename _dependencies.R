# Dependencies renv cannot infer.
#
# renv discovers packages by scanning code, so anything that is only ever run as
# a tool - never called from a script here - is invisible to it and gets pruned
# on the next renv::snapshot(). Declaring it here keeps it in renv.lock.
#
# This file is never sourced. It exists to be read by renv::dependencies(), and
# is kept out of the package tarball by .Rbuildignore.

# Generates man/. DESCRIPTION pins the generator with
# Config/roxygen2/version, and this holds the lockfile to the same version.
library(roxygen2)

# pkgdown is NOT listed: renv already finds it in _pkgdown.yml.
