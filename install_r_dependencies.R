#!/usr/bin/env Rscript

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
