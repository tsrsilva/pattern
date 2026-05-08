suppressPackageStartupMessages(library(vegan))
suppressPackageStartupMessages(library(proxy))
suppressPackageStartupMessages(library(dplyr))

compute_distance <- function(mat, type) {

  mat <- as.matrix(mat)
  type <- tolower(type)

  if (type %in% c("pos", "dep", "phrase")) {
    # Bray–Curtis for count data
    return(vegan::vegdist(mat, method = "bray"))
  }

  if (type == "lemma") {
    # Cosine distance for TF–IDF weighted lemma templates
    return(proxy::dist(mat, method = "cosine"))
  }

  stop("Unknown pattern type: ", type)
}

run_permanova <- function(
  dist_mat,
  meta,
  formula,
  strata_var = NULL,
  n_perm = 999
) {

  # Safety checks
  stopifnot(nrow(meta) == attr(dist_mat, "Size"))

  # Drop predictors that have fewer than 2 observed levels in the current
  # metadata subset; adonis2/model.matrix cannot build contrasts otherwise.
  rhs_terms <- attr(terms(formula), "term.labels")
  valid_terms <- rhs_terms[vapply(
    rhs_terms,
    function(v) {
      if (!(v %in% names(meta))) {
        return(FALSE)
      }
      vals <- meta[[v]]
      vals <- vals[!is.na(vals)]
      length(unique(vals)) >= 2
    },
    logical(1)
  )]

  if (length(valid_terms) == 0) {
    return(data.frame(
      term = "no_testable_terms",
      Df = NA_real_,
      SumOfSqs = NA_real_,
      R2 = NA_real_,
      p_value = NA_real_,
      stringsAsFactors = FALSE
    ))
  }

  safe_nperm <- function(requested_nperm, upper_bound) {
    # For tiny datasets, disable permutation testing to avoid unstable
    # complete-enumeration paths in the permutation engine.
    if (nrow(meta) < 6) {
      return(0L)
    }

    if (!is.finite(upper_bound) || is.na(upper_bound)) {
      return(max(1L, as.integer(requested_nperm)))
    }
    # Keep nperm strictly below full enumeration to avoid complete-set mode.
    if (upper_bound <= 2) {
      return(0L)
    }
    capped <- min(as.integer(requested_nperm), max(1L, as.integer(floor(upper_bound)) - 2L))
    max(1L, capped)
  }

  if (!is.null(strata_var)) {
    strata <- as.factor(meta[[strata_var]])
    block_sizes <- as.numeric(table(strata))
    # Upper bound for permutations under block-restricted shuffling.
    perm_upper <- exp(sum(lgamma(block_sizes + 1)))
    n_perm_eff <- safe_nperm(n_perm, perm_upper)

    # Use an explicit permutation design for small, stratified datasets to
    # avoid exhaustive-set generation and instability in some setups.
    perm_ctrl <- permute::how(
      nperm = n_perm_eff,
      blocks = strata,
      complete = FALSE,
      minperm = 0
    )
    strata_arg <- NULL
  } else {
    # Upper bound for unrestricted permutations across rows.
    perm_upper <- exp(lgamma(nrow(meta) + 1))
    n_perm_eff <- safe_nperm(n_perm, perm_upper)
    perm_ctrl <- n_perm_eff
    strata_arg <- NULL
  }

  # Rebuild the model formula locally so the LHS always resolves to the
  # distance matrix argument for this run.
  rhs <- paste(valid_terms, collapse = " + ")
  model_formula <- as.formula(
    paste("dist_mat ~", rhs),
    env = environment()
  )

  ad <- vegan::adonis2(
    model_formula,
    data = meta,
    permutations = perm_ctrl,
    strata = strata_arg,
    by = "margin"
  )

  # Convert to data frame
  res <- as.data.frame(ad)
  res$term <- rownames(res)
  rownames(res) <- NULL

  # Clean output
  res %>%
    dplyr::select(
      "term",
      "Df",
      "SumOfSqs",
      "R2",
      "Pr(>F)"
    ) %>%
    dplyr::rename(p_value = "Pr(>F)")
}

# Baseline taxonomy model
form_taxonomy <- as.formula(
  dist ~ taxonomy_order + taxonomy_family
)

# Sociolinguistic / editorial model
form_context <- as.formula(
  dist ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type +
    period_class
)

# Full model
form_full <- as.formula(
  dist ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type +
    period_class +
    taxonomy_order +
    taxonomy_family
)

format_results <- function(res, pattern_type, model_name) {
  res %>%
    dplyr::mutate(
      pattern_type = pattern_type,
      model = model_name,
      significance = dplyr::case_when(
        .data$p_value < 0.001 ~ "***",
        .data$p_value < 0.01  ~ "**",
        .data$p_value < 0.05  ~ "*",
        TRUE ~ ""
      )
    ) %>%
    dplyr::arrange(.data$p_value)
}

align_meta_to_matrix <- function(mat, meta) {
  if (is.null(rownames(mat))) {
    stop("Input matrix must have document IDs as row names.")
  }
  if (!("id" %in% names(meta))) {
    stop("Metadata must include an 'id' column.")
  }

  idx <- match(rownames(mat), meta$id)
  if (any(is.na(idx))) {
    missing_ids <- rownames(mat)[is.na(idx)]
    stop(
      "Missing metadata for document IDs: ",
      paste(missing_ids, collapse = ", ")
    )
  }

  meta[idx, , drop = FALSE]
}

run_all_models <- function(mat, meta, pattern_type) {

  message("Running analyses for: ", pattern_type)

  meta_aligned <- align_meta_to_matrix(mat, meta)

  if (nrow(mat) < 6) {
    message(
      "Skipping PERMANOVA for ", pattern_type,
      " (requires at least 6 specimens for stable permutation testing)."
    )
    return(data.frame(
      term = rep("no_testable_terms", 3),
      Df = NA_real_,
      SumOfSqs = NA_real_,
      R2 = NA_real_,
      p_value = NA_real_,
      pattern_type = pattern_type,
      model = c("taxonomy", "context", "full"),
      significance = "",
      stringsAsFactors = FALSE
    ))
  }

  dist <- compute_distance(mat, pattern_type)

  # TAXONOMY
  res_tax <- run_permanova(
    dist,
    meta_aligned,
    form_taxonomy
  )

  # CONTEXT (restricted by family)
  res_ctx <- run_permanova(
    dist,
    meta_aligned,
    form_context,
    strata_var = "taxonomy_family"
  )

  # FULL MODEL (restricted)
  res_full <- run_permanova(
    dist,
    meta_aligned,
    form_full,
    strata_var = "taxonomy_family"
  )

  bind_rows(
    format_results(res_tax,  pattern_type, "taxonomy"),
    format_results(res_ctx,  pattern_type, "context"),
    format_results(res_full, pattern_type, "full")
  )
}

results_all <- bind_rows(
  run_all_models(mat_pos,           meta, "POS"),
  run_all_models(mat_dep,           meta, "DEP"),
  run_all_models(mat_phrase,        meta, "PHRASE"),
  run_all_models(mat_lemma_tfidf,   meta, "LEMMA")
)

write.csv(
  results_all,
  "outputs/analyses/permanova_results.csv",
  row.names = FALSE
)
