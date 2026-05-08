compute_tfidf <- function(mat) {

  # Ensure matrix
  mat <- as.matrix(mat)
  storage.mode(mat) <- "numeric"

  # Remove empty documents (all-zero rows)
  keep_rows <- rowSums(mat) > 0
  if (!all(keep_rows)) {
    warning("Removing ", sum(!keep_rows), " empty documents before TF-IDF")
    mat <- mat[keep_rows, , drop = FALSE]
  }

  # --- Term Frequency (row-normalized) ---
  tf <- mat / rowSums(mat)

  # --- Inverse Document Frequency ---
  df <- colSums(mat > 0)
  idf <- log(nrow(mat) / df)

  # --- TF-IDF ---
  tfidf <- tf * matrix(
    idf,
    nrow = nrow(tf),
    ncol = length(idf),
    byrow = TRUE
  )

  tfidf[!is.finite(tfidf)] <- 0
  return(tfidf)
}

load_lemma_counts <- function(path) {
  raw_lines <- readLines(path, warn = FALSE)
  header_idx <- grep("^document_id,", raw_lines)[1]

  if (is.na(header_idx)) {
    stop("Could not find document_id header in ", path)
  }

  mat_lemma_raw <- read.csv(
    text = paste(raw_lines[header_idx:length(raw_lines)], collapse = "\n"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  row_ids <- mat_lemma_raw[[1]]
  if (anyDuplicated(row_ids)) {
    stop("Duplicate document IDs found in ", path)
  }

  rownames(mat_lemma_raw) <- row_ids
  mat_lemma_raw[[1]] <- NULL
  mat_lemma_raw
}

# Load raw lemma-template counts
mat_lemma_raw <- load_lemma_counts(
  "outputs/analyses/corpus_lemma_patterns.csv"
)

# Sanity checks
stopifnot(is.data.frame(mat_lemma_raw))
stopifnot(nrow(mat_lemma_raw) > 1)
stopifnot(ncol(mat_lemma_raw) > 1)

# Compute TF-IDF
mat_lemma_tfidf <- compute_tfidf(mat_lemma_raw)

write.csv(
  mat_lemma_tfidf,
  "outputs/analyses/corpus_lemma_templates_tfidf.csv",
  row.names = TRUE
)

