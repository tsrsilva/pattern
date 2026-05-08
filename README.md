# Pattern Pipeline

This project extracts linguistic patterns from specimen descriptions and generates:

- per-specimen CSV/PDF outputs
- corpus-level matrices
- TF-IDF lemma matrix
- plots and PERMANOVA summary outputs

## Setup

### 1. Create and activate a Python environment

```bash
python -m venv .venv
source .venv/bin/activate
```

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Download spaCy model

```bash
python -m spacy download en_core_web_sm
```

### 4. Install R dependencies

R packages are not installed automatically by the pipeline.
You should install them once before running the full workflow.

Option A (recommended): run the helper script:

```bash
Rscript install_r_dependencies.R
```

Option B: install manually in R:

```r
install.packages(c(
	"readr", "dplyr", "tidyr", "pheatmap", "circlize",
	"gridExtra", "viridisLite", "ggplot2", "stringr",
	"vegan", "proxy", "permute"
))

if (!requireNamespace("BiocManager", quietly = TRUE)) {
	install.packages("BiocManager")
}
BiocManager::install("ComplexHeatmap", ask = FALSE, update = FALSE)
```

## 5. Run the Full Pipeline

From the project root:

```bash
python run_pipeline.py
```

## Main Outputs

Generated files are written under `outputs/` and `outputs/analyses/`, including:

- `outputs/analyses/pattern_comparison.csv`
- `outputs/analyses/corpus_lemma_templates_tfidf.csv`
- `outputs/analyses/permanova_results.csv`
- `outputs/analyses/plots/`

## Notes

- Input descriptions and metadata are configured in `config.yaml`.
- If your corpus is very small, PERMANOVA may be skipped and placeholder rows will be written to `permanova_results.csv`.
