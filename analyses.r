# analyses_final.R
# Full plotting pipeline that builds per-component matrices and produces:
# - global heatmaps (full + top-20)
# - phrase top-20 heatmaps (from per-file *_phrase.csv)
# - per-component top-20 matrices (pos/dep/lemma/phrase)
# - a 4-panel plate with POS / DEP / LEMMA / PHRASE top-20 heatmaps
#
# Requirements:
# install.packages(c(
#   "readr", "dplyr", "tidyr", "pheatmap", "ComplexHeatmap",
#   "circlize", "viridisLite", "ggplot2", "gridExtra", "stringr"
# ))
# or install tidyverse and the others.
#
# Adjust file paths if needed.

suppressPackageStartupMessages(library(readr))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tidyr))
suppressPackageStartupMessages(library(pheatmap))
suppressPackageStartupMessages(library(ComplexHeatmap))
suppressPackageStartupMessages(library(circlize))
suppressPackageStartupMessages(library(grid))
suppressPackageStartupMessages(library(gridExtra))
suppressPackageStartupMessages(library(viridisLite))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(stringr))

# ============================
# CONFIG
# ============================
pattern_comparison_csv <- "outputs/analyses/pattern_comparison.csv"
output_plots_dir <- "outputs/analyses/plots"
perfile_dir <- "outputs"   # where per-file *_pos/_dep/_lemma/_phrase.csv are
top_n <- 20

dir.create(output_plots_dir, recursive = TRUE, showWarnings = FALSE)

# ----------------------------
# Helper: safe numeric convert for whole data frame/matrix
# ----------------------------
safe_to_numeric_matrix <- function(df) {
  # df can be data.frame or matrix
  if (is.null(df)) return(NULL)
  if (is.data.frame(df)) {
    # try to coerce columns to numeric; preserve rownames if present
    rn <- rownames(df)
    mat <- suppressWarnings(as.matrix(df))
  } else {
    mat <- df
  }
  # if matrix is character or factor, coerce per-column
  if (!is.numeric(mat)) {
    # convert column-wise to numeric, return numeric matrix
    mat2 <- matrix(NA_real_, nrow = nrow(mat), ncol = ncol(mat))
    for (j in seq_len(ncol(mat))) {
      colj <- mat[, j]
      # convert factors or characters
      colj <- as.character(colj)
      colj[colj == ""] <- NA
      numj <- suppressWarnings(as.numeric(colj))
      mat2[, j] <- numj
    }
    rownames(mat2) <- rn
    colnames(mat2) <- colnames(mat)
    mat <- mat2
  }
  # Replace non-finite values with 0 (safe)
  mat[!is.finite(mat)] <- 0
  mat
}

# ----------------------------
# Load global pattern_comparison (if present)
# used for full matrix / top-20 global
# ----------------------------
if (!file.exists(pattern_comparison_csv)) {
  stop("pattern_comparison.csv not found at: ", pattern_comparison_csv)
}
message("Reading global comparison CSV: ", pattern_comparison_csv)
df_global <- read_csv(pattern_comparison_csv, show_col_types = FALSE)

message(
  "Loaded global CSV: ", nrow(df_global),
  " rows × ", ncol(df_global), " columns"
)

# Clean species column (first column)
species_raw <- df_global[[1]]
species <- species_raw %>%
  gsub("^\\s*['\"]+|['\"]+\\s*$", "", .) %>%
  trimws()
if (any(species == ""))
  stop("Empty species name detected in global CSV first column.")
if (any(duplicated(species)))
  stop("Duplicate species names detected in global CSV first column.")
message(
  "Species detected (first 6): ",
  paste(head(species, 6), collapse = ", ")
)

# numeric block (everything except first column)
numeric_block <- df_global[, -1, drop = FALSE]
# coerce to numeric matrix safely
mat <- safe_to_numeric_matrix(numeric_block)
rownames(mat) <- species
colnames(mat) <- colnames(numeric_block)
message("Global numeric matrix built: ", nrow(mat), " × ", ncol(mat))

# ----------------------------
# Build per-component matrices from per-file CSVs (pos, dep, lemma, phrase)
# ----------------------------
get_pattern_matrix <- function(type, inputs_dir = perfile_dir) {
  files <- list.files(
    path = inputs_dir,
    pattern = paste0("_", type, "\\.csv$"),
    full.names = TRUE,
    recursive = FALSE
  )

  if (length(files) == 0) {
    message("No files found for type: ", type)
    return(NULL)
  }

  message(
    "Found ", length(files), " files for type ", type,
    " (example): ", paste(head(basename(files), 5), collapse = ", ")
  )

  lst <- list()
  for (f in files) {
    df <- suppressWarnings(read_csv(f, show_col_types = FALSE))
    if (!all(c("pattern", "count") %in% names(df))) {
      message("  Skipping invalid file (missing pattern/count): ", basename(f))
      next
    }
    sp <- gsub(paste0("_", type, "\\.csv$"), "", basename(f))
    # make sure counts are numeric
    df$count <- suppressWarnings(as.numeric(df$count))
    df$count[!is.finite(df$count)] <- 0
    df$species <- sp
    lst[[sp]] <- df %>% select(species, pattern, count)
  }

  if (length(lst) == 0) {
    message("No valid files after parsing for type: ", type)
    return(NULL)
  }

  all <- bind_rows(lst)

  wide <- all %>%
    pivot_wider(names_from = pattern, values_from = count, values_fill = 0)

  species_vec <- wide$species
  wide_df <- as.data.frame(wide[, -1, drop = FALSE])
  rownames(wide_df) <- species_vec

  # ensure column names are syntactic? we keep them raw (pattern strings)
  mat <- safe_to_numeric_matrix(wide_df)
  return(mat)
}

message("Building per-component matrices (pos, dep, lemma, phrase)...")
mat_pos <- get_pattern_matrix("pos")
mat_dep <- get_pattern_matrix("dep")
mat_lemma <- get_pattern_matrix("lemma")
mat_phrase <- get_pattern_matrix("phrase")  # optional, but helpful to have

# ----------------------------
# Helper: top-N columns selector
# ----------------------------
select_top_n <- function(mat, n = top_n) {
  if (is.null(mat)) return(NULL)
  if (ncol(mat) == 0) return(NULL)
  totals <- colSums(mat, na.rm = TRUE)
  keep_n <- min(n, length(totals))
  if (keep_n <= 0) return(NULL)
  top_cols <- names(sort(totals, decreasing = TRUE))[1:keep_n]
  return(mat[, top_cols, drop = FALSE])
}

mat_pos_top   <- select_top_n(mat_pos, top_n)
mat_dep_top   <- select_top_n(mat_dep, top_n)
mat_lemma_top <- select_top_n(mat_lemma, top_n)
# For phrases: prefer building phrase_top from per-file phrase matrices
# (we also create phrase_top below)
mat_phrase_top <- select_top_n(mat_phrase, top_n)

# Also compute global top-20 from the big 'mat' (pattern_comparison)
pattern_totals <- colSums(mat, na.rm = TRUE)
top_patterns_global <- names(
  sort(pattern_totals, decreasing = TRUE)
)[seq_len(min(top_n, length(pattern_totals)))]
mat_top_global <- mat[, top_patterns_global, drop = FALSE]

message(
  "Global top patterns (examples): ",
  paste(head(top_patterns_global, 6), collapse = ", ")
)

# ----------------------------
# PHRASE: if mat_phrase was NULL or too small, build phrase matrix
# from per-file phrase CSVs explicitly (robust)
# ----------------------------
if (is.null(mat_phrase) || ncol(mat_phrase) < 1) {
  # attempt again with recursion (maybe phrase files have different
  # naming), but we already tried
  message(
    "No per-file phrase matrix built earlier or empty; ",
    "attempting to collect phrase files explicitly..."
  )
  phrase_files <- list.files(
    path = perfile_dir,
    pattern = "_phrase\\.csv$",
    full.names = TRUE
  )
  if (length(phrase_files) > 0) {
    # Reuse get_pattern_matrix which returns processed matrix
    mat_phrase <- get_pattern_matrix("phrase")
    mat_phrase_top <- select_top_n(mat_phrase, top_n)
  } else {
    message("No phrase files found under ", perfile_dir)
    mat_phrase <- NULL
    mat_phrase_top <- NULL
  }
}

# ----------------------------
# SAFE CLEANING: ensure all top matrices exist and numeric
# ----------------------------
mat_top_global <- safe_to_numeric_matrix(mat_top_global)
mat_pos_top      <- safe_to_numeric_matrix(mat_pos_top)
mat_dep_top      <- safe_to_numeric_matrix(mat_dep_top)
mat_lemma_top    <- safe_to_numeric_matrix(mat_lemma_top)
mat_phrase_top   <- safe_to_numeric_matrix(mat_phrase_top)

# ----------------------------
# Small utility to check whether clustering is possible
# (need >=2 rows and >=2 cols)
# ----------------------------
can_cluster <- function(m) {
  if (is.null(m)) return(FALSE)
  if (!is.matrix(m)) m <- as.matrix(m)
  if (nrow(m) < 2 || ncol(m) < 2) return(FALSE)
  # also need some variance
  if (all(rowSums(m) == 0) && all(colSums(m) == 0)) return(FALSE)
  TRUE
}

# ----------------------------
# Function to draw and save a pheatmap to a file
# (handles small matrices gracefully)
# ----------------------------
save_pheatmap_file <- function(
  mat, filename, show_colnames = TRUE, main_title = NULL,
  fontsize_row = 6, fontsize_col = 6, width = 9, height = 7
) {
  if (is.null(mat) || nrow(mat) == 0 || ncol(mat) == 0) {
    message("Skipping heatmap (empty matrix): ", filename)
    return(NULL)
  }

  if (!can_cluster(mat)) {
    # fallback: simple tile ggplot
    message("Matrix too small to cluster; using tile plot for ", filename)
    df_long <- as.data.frame(mat)
    df_long$species <- rownames(mat)
    long <- pivot_longer(
      df_long, -species,
      names_to = "pattern", values_to = "count"
    )
    p <- ggplot(long, aes(x = pattern, y = species, fill = count)) +
      geom_tile() +
      scale_fill_viridis_c() +
      theme_minimal(base_size = 10) +
      theme(
        axis.text.x = element_text(
          angle = 45, hjust = 1, size = fontsize_col
        ),
        axis.text.y = element_text(size = fontsize_row)
      ) +
      labs(title = main_title, x = "", y = "")

    ggsave(filename, plot = p, width = width, height = height)
    return(invisible(NULL))
  }

  # normal pheatmap -> some pheatmap versions redirect to ComplexHeatmap;
  # silent=TRUE returns a list (including gtable)
  ph <- pheatmap::pheatmap(
    mat,
    clustering_distance_rows = "euclidean",
    clustering_distance_cols = "euclidean",
    clustering_method = "ward.D2",
    fontsize = 10,
    show_rownames = TRUE,
    show_colnames = show_colnames,
    fontsize_row = fontsize_row,
    fontsize_col = fontsize_col,
    border_color = NA,
    main = main_title,
    silent = TRUE
  )

  # pheatmap created an object; use grid.draw to save to file
  pdf(filename, width = width, height = height)
  grid.newpage()
  grid.draw(ph[[4]])  # element 4 is the gtable in many pheatmap versions
  dev.off()
  invisible(NULL)
}

# ----------------------------
# Save global heatmaps
# ----------------------------
message("Saving global full heatmap and top-20 global heatmap...")
save_pheatmap_file(
  mat,
  file.path(output_plots_dir, "pattern_similarity_heatmap_FULL.pdf"),
  show_colnames = FALSE,
  main_title = "Pattern similarity (full matrix)",
  fontsize_row = 6, fontsize_col = 1, width = 10, height = 8
)

save_pheatmap_file(
  mat_top_global,
  file.path(output_plots_dir, "pattern_similarity_heatmap_TOP20.pdf"),
  show_colnames = TRUE,
  main_title = paste("Pattern similarity - Top", top_n),
  fontsize_row = 6, fontsize_col = 6, width = 10, height = 8
)

# Also save ComplexHeatmap variants for publication (if matrix large enough)
safe_draw_complexheatmap <- function(
  mat, filename, show_colnames = TRUE,
  title = NULL, width = 9, height = 7
) {
  if (is.null(mat) || nrow(mat) == 0 || ncol(mat) == 0) {
    message("Skipping ComplexHeatmap (empty): ", filename)
    return(NULL)
  }
  if (!can_cluster(mat)) {
    message(
      "Skipping ComplexHeatmap clustering for: ", filename,
      " (too small). Falling back to pheatmap/ggplot."
    )
    save_pheatmap_file(
      mat, filename,
      show_colnames = show_colnames,
      main_title = title,
      fontsize_row = 7, fontsize_col = 6,
      width = width, height = height
    )
    return(NULL)
  }

  pdf(filename, width = width, height = height)
  ht <- Heatmap(
    mat,
    name = "Frequency",
    show_column_names = show_colnames,
    col = circlize::colorRamp2(
      seq(min(mat), max(mat), length.out = 5), viridis(5)
    ),
    row_names_gp = grid::gpar(fontsize = 6),
    column_names_gp = grid::gpar(fontsize = 7),
    cluster_rows = TRUE,
    cluster_columns = TRUE,
    clustering_method_rows = "ward.D2",
    clustering_method_columns = "ward.D2",
    column_names_rot = 45
  )
  draw(ht)
  dev.off()
}

safe_draw_complexheatmap(
  mat_top_global,
  file.path(output_plots_dir, "pattern_heatmap_complex_TOP20.pdf"),
  show_colnames = TRUE,
  title = paste("Top", top_n),
  width = 9, height = 7
)

# ----------------------------
# Phrase top-20 heatmaps (built earlier)
# ----------------------------
message(
  "Saving phrase top-20 heatmaps ",
  "(per-file phrase matrix if available)..."
)
if (!is.null(mat_phrase_top) && ncol(mat_phrase_top) > 0) {
  save_pheatmap_file(
    mat_phrase_top,
    file.path(output_plots_dir, "phrase_patterns_heatmap_TOP20.pdf"),
    show_colnames = TRUE,
    main_title = paste("Phrase patterns Top", top_n),
    fontsize_row = 7, fontsize_col = 6, width = 10, height = 7
  )
  safe_draw_complexheatmap(
    mat_phrase_top,
    file.path(
      output_plots_dir, "phrase_patterns_complex_TOP20.pdf"
    ),
    show_colnames = TRUE,
    title = paste("Phrase Top", top_n)
  )
} else {
  message("No phrase_top available to plot.")
}

# ----------------------------
# Per-file top-N barplots (unchanged): loads individual
# *_pos/_dep/_lemma/_phrase CSVs and saves Top-N barplots
# ----------------------------
message(
  "Generating per-file Top-", top_n,
  " barplots for each *_pos/_dep/_lemma/_phrase.csv ..."
)
plot_top_patterns <- function(csv_file, output_dir, n_top = top_n) {

  fname <- basename(csv_file)
  file_id <- str_replace(fname, "\\.csv$", "")

  df <- suppressWarnings(read_csv(csv_file, show_col_types = FALSE))

  if (!all(c("pattern", "count") %in% names(df))) {
    message("Skipping (no pattern/count columns): ", csv_file)
    return(NULL)
  }

  df$count <- suppressWarnings(as.numeric(df$count))
  df <- df %>% filter(!is.na(count))

  df_top <- df %>%
    arrange(desc(count)) %>%
    slice_head(n = n_top)

  if (nrow(df_top) == 0) {
    message("Skipping empty pattern file: ", csv_file)
    return(NULL)
  }

  pdf_file <- file.path(output_dir, paste0(file_id, "_top", n_top, ".pdf"))

  p <- ggplot(df_top, aes(x = reorder(pattern, count), y = count)) +
    geom_col(fill = viridis(nrow(df_top))) +
    coord_flip() +
    labs(
      title = paste("Top", n_top, "Patterns -", file_id),
      x = "Pattern", y = "Frequency"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      axis.text.y = element_text(size = 8),
      axis.text.x = element_text(size = 8)
    )

  ggsave(pdf_file, plot = p, width = 8, height = 6)
  message("Saved: ", pdf_file)
}

csv_files <- list.files(
  perfile_dir,
  pattern = ".*_(pos|dep|lemma|phrase)\\.csv$",
  full.names = TRUE
)
perfile_out <- file.path(output_plots_dir, "feature_plots")
dir.create(perfile_out, recursive = TRUE, showWarnings = FALSE)

if (length(csv_files) == 0) {
  warning("No per-file pattern CSVs found in ", perfile_dir)
} else {
  for (csv in csv_files) {
    plot_top_patterns(csv, perfile_out)
  }
}

# ----------------------------
# 4-PANEL PLATE: POS / DEP / LEMMA / PHRASE top-20
# ----------------------------
message("Assembling 4-panel plate (POS/DEP/LEMMA/PHRASE Top-20)...")

# list of mats for panel (use available mats;
# if missing make small empty placeholder)
panel_mats <- list(
  POS = mat_pos_top,
  DEP = mat_dep_top,
  LEMMA = mat_lemma_top,
  PHRASE = mat_phrase_top
)

# convert NULL to small placeholder that will render as "no data"
make_placeholder <- function(
  title,
  species = rownames(mat)[1:max(1, min(3, nrow(mat)))]
) {
  if (is.null(species) || length(species) == 0) species <- "no_species"
  dfph <- matrix(0, nrow = length(species), ncol = 1)
  rownames(dfph) <- species
  colnames(dfph) <- paste0(title, "_empty")
  return(dfph)
}

# helper: get gtable for a matrix (pheatmap or ggplot fallback)
get_panel_grob <- function(m, title) {
  if (is.null(m) || nrow(m) == 0 || ncol(m) == 0) {
    m <- make_placeholder(title)
  }
  if (!can_cluster(m)) {
    # fallback ggplot tile
    df_long <- as.data.frame(m)
    df_long$species <- rownames(m)
    long <- pivot_longer(
      df_long, -species,
      names_to = "pattern", values_to = "count"
    )
    p <- ggplot(long, aes(x = pattern, y = species, fill = count)) +
      geom_tile() +
      scale_fill_viridis_c() +
      theme_minimal(base_size = 9) +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1, size = 7),
        axis.text.y = element_text(size = 7)
      ) +
      labs(title = title)
    return(ggplotGrob(p))
  }
  ph <- pheatmap::pheatmap(
    m,
    clustering_distance_rows = "euclidean",
    clustering_distance_cols = "euclidean",
    clustering_method = "ward.D2",
    fontsize = 9,
    show_rownames = TRUE,
    show_colnames = TRUE,
    fontsize_row = 6,
    fontsize_col = 6,
    angle_col = 45,
    border_color = NA,
    main = title,
    silent = TRUE
  )
  ph[[4]]
}

grobs <- lapply(names(panel_mats), function(k) {
  get_panel_grob(panel_mats[[k]], paste0(k, " Top-", top_n))
})

# Save 4-panel plate
plate_file <- file.path(
  output_plots_dir, "plate_POS_DEP_LEMMA_PHRASE_TOP20.pdf"
)
pdf(plate_file, width = 14, height = 12)
grid.arrange(
  grobs[[1]], grobs[[2]], grobs[[3]], grobs[[4]],
  ncol = 2,
  top = textGrob(
    paste(
      "Pattern-Structure Comparison Across Species",
      "(Top-20 per Component)"
    ),
    gp = gpar(fontsize = 14, fontface = "bold")
  )
)
dev.off()
message("Four-panel plate saved to: ", plate_file)

message("All done. Plots in: ", output_plots_dir)
