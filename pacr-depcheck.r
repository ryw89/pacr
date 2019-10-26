#!/usr/bin/env Rscript
# Use R's tools::package_dependencies() function to get all of a
# package's dependencies. (Recursively by default.)

args <- commandArgs(trailingOnly = TRUE)

# CRAN package name
pkg <- args[1]

if (length(args) > 1) {
    recursive <- as.logical(args[2])
} else {
    recursive <- TRUE
    cran_mirror <- 1  # R 0-cloud
}

# Passed from pacr.rb from pacr config
if (length(args) > 2) {
    cran_mirror <- as.numeric(args[3])
} else {
    cran_mirror <- 1
}

chooseCRANmirror(graphics = FALSE, ind = cran_mirror)
pkg_deps <- tools::package_dependencies(pkg, recursive = recursive)

# Print all dependencies to stdout
for (pkg_dep in pkg_deps[[pkg]]) {
    cat(paste0(pkg_dep, "\n"))
}
