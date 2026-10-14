# Analysis Redesign Report

## Scope

This report evaluates the current pattern-analysis outputs and proposes a redesign for the next corpus. It is based on the 10-description pilot currently represented in `outputs/analyses/metadata.csv` and `outputs/analyses/permanova_results.csv`.

The current outputs are useful for exploration and quality control. They are not yet sufficient for confirmatory claims about the effects of taxonomy, historical period, publication context, or language-related metadata.

## Executive Summary

The main limitation is the design, not primarily the choice of distance measure.

The current corpus has:

- 10 descriptions total.
- Eight order labels are represented across the current metadata, with uneven representation. The proposed redesign uses six focal orders: Hymenoptera, Coleoptera, Stylommatophora, Littorinimorpha, Siphonostomatoida, and Monstrilloida.
- 3 period classes.
- 7 families, most represented by a single description.
- Strong confounding among taxonomy, period, and contextual variables.
- Thousands of sparse linguistic features for only 10 observations.
- A saturated full PERMANOVA model with `Residual Df = 0`.
- A context model with only `Residual Df = 1`.

The immediate recommendation is:

1. Treat the current PERMANOVA results as exploratory only.
2. Stop running the current full model.
3. Build a balanced corpus before adding more predictors.
4. Target at least 54 descriptions for a structured pilot extension.
5. Target approximately 90 to 108 descriptions for the main order-by-period analysis.
6. Prefer 120 to 144 descriptions if the study will retain several contextual covariates and family-level controls.
7. Use simulation-based power analysis once the planned design and feature filtering are fixed.

## What Is Wrong With the Current Analysis?

### 1. The full model is saturated

The full model includes:

```text
journal_type
_author_linguistic_background_
_depository_language_environment_
period_class
taxonomy_order
taxonomy_family
```

With 10 observations, the model consumes all available degrees of freedom. The output shows:

```text
Total Df = 9
Residual Df = 0
R2 = 1
```

This `R2 = 1` is a consequence of fitting a saturated model, not evidence that the predictors perfectly explain the linguistic distances. The full-model p-values cannot be interpreted.

### 2. The context model has almost no residual degrees of freedom

The context model leaves one residual degree of freedom. Its estimated effects and p-values will be highly unstable, and the restricted permutation distribution is very small.

The current analysis also restricts context permutations by `taxonomy_family`. That is difficult to justify with the present structure because most families have one observation. A family with one observation cannot provide within-family permutations.

### 3. Taxonomic predictors are partly redundant

`taxonomy_order` and `taxonomy_family` are not independently estimable in the current pilot. Most families occur in only one order, and several families occur only once. This is why `taxonomy_order` receives `Df = 0` in the taxonomy model.

For the current pilot, use one taxonomic control at a time. Do not interpret order and family as separate effects until the expanded corpus contains replication across both levels.

### 4. Some metadata cannot be tested

`description_type` is constant: every current document is marked `original`. It should not be included in an analytical model until the corpus contains multiple description types.

The same principle applies to any metadata variable with one observed level or with levels represented by only one or two documents.

### 5. The feature space is too large for the sample

The exported matrices contain hundreds or thousands of features for 10 descriptions. Many lexical and phrase features occur in only one document. This is expected in a specialized taxonomic corpus, but it means that raw high-dimensional distances can reflect document-specific vocabulary, document length, and authorial idiosyncrasy.

The analysis should therefore separate:

- Structural pattern composition: POS, dependency, and phrase features.
- Lexical content: lemma templates and lexical n-grams.
- Document-level confounds: length, token count, and parser quality.

## Recommended Study Design

### Primary design: crossed order by period

Use a balanced design with the following primary factors:

- `taxonomy_order`: 6 focal orders: Hymenoptera, Coleoptera, Stylommatophora, Littorinimorpha, Siphonostomatoida, and Monstrilloida.
- `period_class`: 3 periods: early descriptive, transitional, and modern integrative.

The core design should contain the same number of descriptions in every order-by-period cell.

This is a proposed sampling scope, not a relabeling of the existing data. In the current metadata, the gastropod entries include `Stylommatophora`, `Littorinimorpha`, and `Caenogastropoda incertae sedis`, while the crustacean entries include `Siphonostomatoida`, `Monstrilloida`, and `Harpacticoida`. The redesigned primary comparison deliberately selects six of these order-level groups and excludes `Caenogastropoda incertae sedis` and `Harpacticoida` unless they are added as further focal orders.

A description should be treated as the observational unit. Avoid treating individual tokens, phrases, or extracted features as independent observations.

### Minimum balanced extension: 54 descriptions

A useful minimum is:

| Factor | Levels | Descriptions per cell | Total |
|---|---:|---:|---:|
| Order x period | 6 x 3 | 3 | 54 |

This design would provide three descriptions per order-period cell. It is suitable for exploratory ordination, effect-size estimation, and checking whether the broad temporal pattern is reproducible across orders.

It remains marginal for a model with several covariates. It should not be treated as a fully powered confirmatory design without simulation.

### Recommended main target: 90 to 108 descriptions

For the main analysis, target five or six descriptions per order-period cell:

| Factor | Levels | Descriptions per cell | Total |
|---|---:|---:|---:|
| Order x period | 6 x 3 | 5 | 90 |
| Order x period | 6 x 3 | 6 | 108 |

The recommended practical target is **108 descriptions**, because six observations per primary cell gives more stability than five while preserving a clear balanced design.

At this size, the primary model can reasonably focus on:

```r
dist ~ period_class + taxonomy_order
```

or, if the scientific question is taxonomic rather than historical:

```r
dist ~ taxonomy_order + period_class
```

Contextual variables should be added selectively, not all at once.

### Robust target: 120 to 144 descriptions

If the study must estimate several contextual variables, include description type, or compare families rather than only orders, target approximately 120 to 144 descriptions.

A possible structure is:

- 6 focal orders x 3 periods x 6 descriptions = 108 core observations.
- Additional descriptions distributed across families and description types.
- At least 3 descriptions per important order-period-family combination where a family-level analysis is planned.

This larger target is preferable when the corpus is intended for confirmatory inference rather than a pilot publication.

## How To Sample The Additional Descriptions

### Preserve the crossed design

Do not simply add whichever descriptions are easiest to obtain. Fill the order-period cells deliberately.

For every new description, record:

- Taxonomic order.
- Taxonomic family.
- Period class.
- Description type.
- Publication year.
- Journal type.
- Author linguistic background, with an explicit coding rule.
- Depository language environment, with an explicit coding rule.
- Token count and document length.
- Source and extraction quality notes.

### Balance families within orders where possible

Family should initially be treated as a blocking or descriptive variable, not automatically as a main predictor. If family-level controls are important, sample multiple families per order and multiple documents per family.

A practical rule is:

- At least 2 families per order.
- At least 3 descriptions per family for a family-level comparison.
- Similar family representation across periods when possible.

If that is not feasible, use order as the taxonomic control and report family composition descriptively.

### Avoid perfect confounding

The following combinations should not be identical by design:

- All early descriptions from anglophone authors.
- All modern descriptions from non-anglophone authors.
- All descriptions from one order published in one journal type.
- All descriptions in one period coming from a single family.

Some correlation is unavoidable in historical data. Perfect or near-perfect correlation prevents the model from separating effects.

### Use an explicit sampling table

Before collecting texts, create a sampling table with one row per target cell:

| Order | Early | Transitional | Modern | Target total |
|---|---:|---:|---:|---:|
| Hymenoptera | 6 | 6 | 6 | 18 |
| Coleoptera | 6 | 6 | 6 | 18 |
| Stylommatophora | 6 | 6 | 6 | 18 |
| Littorinimorpha | 6 | 6 | 6 | 18 |
| Siphonostomatoida | 6 | 6 | 6 | 18 |
| Monstrilloida | 6 | 6 | 6 | 18 |
| **Total** | **36** | **36** | **36** | **108** |

The numbers can be changed if the scientific scope changes, but the cell structure should be fixed before data collection.

## Recommended Statistical Workflow

### Stage 1: data and extraction quality

Before any hypothesis test:

1. Verify that every matrix row is a document ID.
2. Verify that metadata IDs match matrix row names exactly.
3. Record token count and extracted pattern count per document.
4. Check for parser failures, empty documents, and unusually short documents.
5. Check whether any feature has zero variance or occurs in only one document.
6. Inspect the effect of document length on distances.

The corpus matrices should be exported with an unambiguous row identifier and should be read back in a test step before statistical analysis.

### Stage 2: normalize count matrices

For POS, dependency, and phrase counts, compare raw counts with length-normalized representations. A reasonable primary approach is Hellinger-transformed relative abundance:

```r
mat_relative <- vegan::decostand(mat, method = "total")
mat_hellinger <- vegan::decostand(mat, method = "hellinger")
dist <- vegan::vegdist(mat_hellinger, method = "euclidean")
```

Bray-Curtis on relative frequencies is also defensible:

```r
mat_relative <- vegan::decostand(mat, method = "total")
dist <- vegan::vegdist(mat_relative, method = "bray")
```

Choose one primary transformation in advance and treat alternatives as sensitivity analyses.

For lemma templates, TF-IDF with cosine distance is reasonable, but rare-feature filtering should be considered. For example, retain features present in at least 3 documents, or compare results with and without that filter.

### Stage 3: exploratory analysis

Use:

- PCoA or dbRDA ordination.
- Document-length overlays.
- Group centroids and confidence regions where appropriate.
- Feature prevalence summaries.
- PERMANOVA effect sizes with confidence or stability assessment.
- PERMDISP to check whether apparent group differences reflect dispersion rather than centroid separation.

The exploratory phase should be used to identify a small number of primary hypotheses, not to select the most favorable p-value among many representations.

### Stage 4: confirmatory models

Pre-specify one primary pattern representation and one primary distance method for the main claim.

Start with a small model:

```r
dist ~ period_class + taxonomy_order
```

Add an interaction only if it is scientifically necessary and the cell sizes support it:

```r
dist ~ period_class * taxonomy_order
```

Do not include `taxonomy_order` and `taxonomy_family` together unless the design has enough replicated families across orders and periods.

Add contextual variables one at a time or in a small, pre-specified set. A model containing every available metadata column is not a substitute for replication.

### Stage 5: multiple representations and multiple tests

Because the pipeline produces POS, dependency, phrase, and lemma representations, decide which one is primary. Treat the remaining representations as secondary or sensitivity analyses.

If many terms and representations are tested, adjust for multiple comparisons or clearly label the analysis exploratory. Do not mark individual p-values with significance symbols without accounting for the number of tests.

## Suggested Model Set For The Expanded Corpus

### Primary model

```r
adonis2(
  dist ~ period_class + taxonomy_order,
  data = meta,
  permutations = 9999,
  by = "margin"
)
```

Use unrestricted permutations only if the design and sampling unit justify them. If there are blocks, repeated sources, or matched sampling units, define the restriction explicitly and ensure each block contains enough observations to permute.

### Secondary model

```r
adonis2(
  dist ~ period_class * taxonomy_order,
  data = meta,
  permutations = 9999,
  by = "margin"
)
```

Use this only after checking that every order-period cell has adequate replication.

### Dispersion check

```r
bd <- betadisper(dist, meta$period_class)
anova(bd)
permutest(bd, permutations = 9999)
```

A significant PERMANOVA result can arise from different within-group dispersion rather than different group centroids. Dispersion should therefore be reported alongside PERMANOVA.

## Corpus-Size Recommendation In One Sentence

Collect **at least 54 descriptions for a balanced exploratory extension, preferably 108 descriptions for the main order-by-period analysis, and 120 to 144 descriptions if you need several contextual covariates or family-level inference**. Starting from the current 10-description pilot, reaching 108 requires 98 additional descriptions, subject to the final inclusion and exclusion decisions for the focal orders.

## Power Analysis Recommendation

The numbers above are design targets, not guarantees of statistical power. Once the corpus reaches approximately 24 to 36 balanced descriptions, use the observed distance structure to simulate additional datasets.

A simulation should vary:

- Descriptions per order-period cell.
- Between-group effect size.
- Within-cell dispersion.
- Feature filtering threshold.
- Distance transformation.
- Number of covariates.
- Permutation restrictions.

The final sample size should be chosen based on the probability of detecting the smallest effect that matters scientifically, not only the effect observed in the pilot.

## Reporting Language For The Current Pilot

Until the corpus is expanded, use wording similar to:

> We conducted exploratory distance-based analyses of linguistic pattern matrices. The pilot contained 10 taxonomic descriptions and was not sufficiently replicated for stable multivariable inference. Apparent effects associated with taxonomy and contextual metadata should therefore be interpreted as preliminary effect-size estimates rather than confirmatory evidence.

Avoid statements such as:

- "The full model explained 100% of the variation."
- "Taxonomy had no effect because the p-value was not significant."
- "The contextual variables independently explained the pattern differences."

Those conclusions are not supported by the current degrees of freedom and confounding structure.

## Implementation Checklist

- [ ] Remove `description_type` from models until multiple levels are represented.
- [ ] Stop reporting the saturated full model.
- [ ] Choose either order or family as the initial taxonomic control.
- [ ] Build a 6 x 3 order-period sampling table.
- [ ] Expand to 54 descriptions for the next exploratory checkpoint.
- [ ] Continue to 90 or 108 descriptions for the primary analysis.
- [ ] Record document length and extraction-quality diagnostics.
- [ ] Normalize raw count matrices and pre-specify the primary representation.
- [ ] Filter extremely rare lexical features as a sensitivity analysis.
- [ ] Check PERMDISP alongside PERMANOVA.
- [ ] Run simulation-based power analysis before final data collection.
- [ ] Report exploratory and confirmatory analyses separately.
