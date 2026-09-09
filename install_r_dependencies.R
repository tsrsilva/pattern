#!/usr/bin/env Rscript

# Fall back to a writable personal library if the default one isn't writable (common on Linux system R installs).
default_lib <- .libPaths()[1]
if (file.access(default_lib, mode = 2) != 0) {
  user_lib <- Sys.getenv("R_LIBS_USER", unset = file.path(Sys.getenv("HOME"), "R", "library"))
  dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(user_lib, .libPaths()))
}

cran_packages <- c(
  "readr", "dplyr", "tidyr", "pheatmap", "circlize",
  "gridExtra", "viridisLite", "ggplot2", "stringr",
  "vegan", "proxy", "permute"
)

missing_cran <- cran_packages[!vapply(cran_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_cran) > 0) {
  install.packages(missing_cran)
}

if (!requireNamespace("BiocManager", quietly = TRUE)) {
  install.packages("BiocManager")
}

if (!requireNamespace("ComplexHeatmap", quietly = TRUE)) {
  BiocManager::install("ComplexHeatmap", ask = FALSE, update = FALSE)
}

cat("R dependencies are installed.\n")
