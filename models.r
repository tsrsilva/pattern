# Canonical models
# Model A — Core hypothesis: taxonomy vs grammar
## Do grammatical patterns cluster by taxonomic classification?

adonis2(
  dist_mat ~ taxonomy_order + taxonomy_family,
  data = meta,
  permutations = 999
)

# Model B — Editorial and institutional effects (Tier 1)
## Do editorial and sociolinguistic contexts explain grammatical similarity better than taxonomy?

adonis2(
  dist_mat ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type +
    period_class,
  data = meta,
  permutations = 999
)

# Model C — Full model including taxonomy (critical comparison)
## Do order/family remain non-significant? Do Tier 1 variables remain significant?

adonis2(
  dist_mat ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type +
    period_class +
    taxonomy_order +
    taxonomy_family,
  data = meta,
  permutations = 999
)

# Model 1 — Genre and temporal effects (baseline model)
## Control for these, otherwise everything else is uninterpretable.

adonis2(
  dist_mat ~ description_type + period_class,
  data = meta,
  permutations = 999
)

# Model 2 — Variance partitioning (optional but powerful)
## How much variation is explained by editorial context vs taxonomy?

varpart(
  dist_mat,
  ~ journal_type + author_linguistic_background + depository_language_environment,
  ~ taxonomy_order + taxonomy_family,
  ~ description_type + period_class,
  data = meta
)

# POS, DEP, PHRASE patterns
## Bray–Curtis

library(vegan)
dist_pos    <- vegdist(mat_pos, method = "bray")
dist_dep    <- vegdist(mat_dep, method = "bray")
dist_phrase <- vegdist(mat_phrase, method = "bray")

# Lemma patterns
## TF–IDF + cosine

library(proxy)
dist_lemma <- dist(mat_lemma_tfidf, method = "cosine")

# Restricted permutation design
## Restrict permutations by taxonomic family

adonis2(
  dist_mat ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type +
    period_class,
  data = meta,
  permutations = how(strata = meta$taxonomy_family)
)

## Add temporal blocking

ctrl <- how(
  strata = meta$taxonomy_family,
  blocks = meta$period_class
)

adonis2(
  dist_mat ~ journal_type +
    author_linguistic_background +
    depository_language_environment +
    description_type,
  data = meta,
  permutations = ctrl
)

## Small-corpus adjustment
### current N (~20–40)

permutations = min(999, factorial(nlevels(meta$taxonomy_family)))
