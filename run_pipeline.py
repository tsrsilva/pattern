#!/usr/bin/env python3
"""Run the pattern analysis pipeline end-to-end."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent

R_ANALYSIS_SCRIPT = r'''
source("analyses.r", local = .GlobalEnv)

meta <- read.csv(
  "outputs/analyses/metadata.csv",
  stringsAsFactors = FALSE,
  check.names = FALSE
)

mat_lemma_tfidf <- as.matrix(
  read.csv(
    "outputs/analyses/corpus_lemma_templates_tfidf.csv",
    row.names = 1,
    check.names = FALSE
  )
)
storage.mode(mat_lemma_tfidf) <- "numeric"

source("statistics.r", local = .GlobalEnv)
'''


def run_step(command: list[str], description: str) -> None:
    print(f"\n==> {description}")
    print(" ".join(command))
    subprocess.run(command, cwd=PROJECT_DIR, check=True)


def check_python_environment() -> int | None:
    if importlib.util.find_spec("spacy") is None:
        print(
            "Missing Python dependency: spacy\n"
            "Install the Python requirements in this environment, then run:\n"
            f"  {sys.executable} -m pip install spacy reportlab pandas pyyaml\n"
            f"  {sys.executable} -m spacy download en_core_web_sm",
            file=sys.stderr,
        )
        return 1

    return None


def check_r_environment() -> int | None:
    required_packages = [
        "readr",
        "dplyr",
        "tidyr",
        "pheatmap",
        "ComplexHeatmap",
        "circlize",
        "gridExtra",
        "viridisLite",
        "ggplot2",
        "stringr",
        "vegan",
        "proxy",
    ]
    check_expr = (
        "required <- c(%s); "
        "missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]; "
        "if (length(missing)) { cat(paste(missing, collapse = '\\n')); quit(status = 1) }"
    ) % ", ".join(f'\"{package}\"' for package in required_packages)

    result = subprocess.run(
        ["Rscript", "-e", check_expr],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return None

    missing_packages = [
        line.strip() for line in result.stdout.splitlines() if line.strip()
    ]
    if not missing_packages:
        missing_packages = [
            line.strip() for line in result.stderr.splitlines() if line.strip()
        ]

    print(
        "Missing R packages: " + ", ".join(missing_packages) + "\n"
        "Install them in your R environment, for example:\n"
        "  Rscript -e 'install.packages(c(\"vegan\", \"proxy\"))'",
        file=sys.stderr,
    )
    return 1


def main() -> int:
    env_error = check_python_environment()
    if env_error is not None:
        return env_error

    r_env_error = check_r_environment()
    if r_env_error is not None:
        return r_env_error

    try:
        run_step([sys.executable, "main.py"], "Extracting pattern data")
        run_step(["Rscript", "tfidf.r"], "Computing TF-IDF matrix")
        run_step(
            ["Rscript", "-e", R_ANALYSIS_SCRIPT],
            "Generating plots and PERMANOVA outputs",
        )
    except FileNotFoundError as error:
        missing = error.filename or "required executable"
        print(f"Missing dependency: {missing}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(
            f"Pipeline failed during step with exit code {error.returncode}.",
            file=sys.stderr,
        )
        return error.returncode or 1

    print("\nPipeline completed successfully.")
    print("Outputs available under outputs/ and outputs/analyses/.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())