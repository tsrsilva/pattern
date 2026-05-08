#!/usr/bin/env python3
"""
pattern_pipeline_clean.py

Full pipeline (ENHANCED PHRASE PATTERNS):
 - Loads descriptions listed in config.yaml
 - Extracts POS / dependency / lemma / phrase patterns per file
   * Phrase extraction now includes:
     - dependency subtree patterns
     - coordinating-conjunction detection
     - multi-headed NP detection
     - chunk expansion capturing PP modifiers
 - Exports per-file CSVs and PDFs
 - Produces corpus-level outputs
 - Produces cross-file analyses:
    - outputs/analyses/pattern_comparison.csv
    - outputs/analyses/distinctive_patterns.csv
"""

import os
import yaml
import spacy
from spacy.tokens import Token, Span, Doc
from collections import Counter
from typing import List, Dict, Any, Iterable
import pandas as pd

from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet

# ------------------------
# Configuration
# ------------------------
DEFAULT_CONFIG = "config.yaml"
OUTPUT_DIR = "outputs"
SPACY_MODEL = "en_core_web_sm"
PER_FILE_TOP_N = 50
CORPUS_TOP_N = 100

# ------------------------
# Load spaCy model
# ------------------------
try:
    nlp = spacy.load(SPACY_MODEL, disable=[])  # keep default pipeline
except Exception as e:
    raise RuntimeError(f"spaCy model '{SPACY_MODEL}' not found. Install and download it: {e}")

# ------------------------
# Loader: config -> list of entries
# ------------------------
def load_corpus_from_config(config_file: str = DEFAULT_CONFIG) -> List[Dict[str, Any]]:
    if not os.path.exists(config_file):
        raise FileNotFoundError(f"Config file '{config_file}' not found.")

    with open(config_file, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    entries = []
    for entry in config.get("corpus", []):
        file_path = entry.get("file")
        if not file_path:
            print("Warning: entry without 'file'. Skipping.")
            continue
        if not os.path.exists(file_path):
            print(f"Warning: file '{file_path}' not found. Skipping.")
            continue

        with open(file_path, "r", encoding="utf-8") as fh:
            text = fh.read()

        pub = entry.get("publication") or {}
        dep = entry.get("depository") or {}
        tax = entry.get("taxonomy") or {}

        entries.append({
            "id": entry.get("id") or os.path.splitext(os.path.basename(file_path))[0],
            "file": file_path,
            "species": entry.get("species"),
            "authors": "; ".join(entry.get("authors") or []),
            "description_type": entry.get("description_type"),
            "period_class": entry.get("period_class"),
            "author_linguistic_background": entry.get("author_linguistic_background"),
            "publication_year": pub.get("year"),
            "publication_journal": pub.get("journal"),
            "journal_type": pub.get("journal_type"),
            "publication_country": pub.get("country"),
            "depository_code": dep.get("code"),
            "depository_country": dep.get("country"),
            "depository_language_environment": dep.get("language_environment"),
            "taxonomy_order": tax.get("order"),
            "taxonomy_family": tax.get("family"),
            "notes": entry.get("notes"),
            "text": text,
        })
    return entries

# ------------------------
# Utilities for phrase extraction enhancements
# ------------------------
def tok_seq_to_pos_tuple(tokens: Iterable[Token]):
    """Return tuple of POS tags in surface order for given tokens"""
    toks = sorted([t for t in tokens if not (t.is_punct or t.is_space)], key=lambda x: x.i)
    return tuple(t.pos_ for t in toks)

def tok_seq_to_lemma_tuple(tokens: Iterable[Token]):
    toks = sorted([t for t in tokens if not (t.is_punct or t.is_space)], key=lambda x: x.i)
    return tuple(t.lemma_.lower() for t in toks)

def subtree_tokens_sorted(token: Token):
    """Return tokens in the subtree of token, sorted by position"""
    toks = [t for t in token.subtree if not (t.is_punct or t.is_space)]
    return sorted(toks, key=lambda x: x.i)

def find_pp_modifiers(head: Token):
    """Return list of prepositional modifier tokens (prepositions) attached to head"""
    pps = []
    for ch in head.children:
        # spaCy uses dep_ == 'prep' for prepositional modifiers (English model)
        if ch.dep_ == "prep":
            pps.append(ch)
    return pps

def has_coordination(chunk: Span):
    """Return True if chunk contains coordination (cc/conj)"""
    for t in chunk:
        if t.dep_ in ("cc", "conj") or t.pos_ == "CCONJ":
            return True
    return False

def count_nounlike_heads(chunk: Span):
    """Return number of noun-like tokens inside chunk (NOUN, PROPN)"""
    return sum(1 for t in chunk if t.pos_ in ("NOUN", "PROPN"))

# ------------------------
# Pattern extraction utilities
# ------------------------
def extract_pos_patterns(doc, window_size=3):
    tokens = [t for t in doc if not t.is_punct and not t.is_space]
    patterns = []
    for i in range(len(tokens)):
        for n in range(2, window_size + 1):
            if i + n <= len(tokens):
                seq = tokens[i:i+n]
                patterns.append(tuple(tok.pos_ for tok in seq))
    return patterns

def extract_dependency_patterns(doc):
    patterns = []
    for token in doc:
        for child in token.children:
            patterns.append((token.pos_, token.dep_, child.pos_))
    return patterns

def extract_lemma_templates(doc, window_size=3):
    tokens = [t for t in doc if not t.is_punct and not t.is_space]
    templates = []
    for i in range(len(tokens)):
        for n in range(2, window_size + 1):
            if i + n <= len(tokens):
                seq = tokens[i:i+n]
                templates.append(tuple(tok.lemma_.lower() for tok in seq))
    return templates

def extract_phrase_patterns(doc: Doc):
    """
    Enhanced phrase extractor. For each noun chunk, we produce multiple, labelled pattern types:
      - ("NP_INTERNAL", POS_TUPLE) : POS sequence inside the noun-chunk (Option B baseline)
      - ("NP_SUBTREE", POS_TUPLE)  : POS sequence of the dependency subtree rooted at the chunk head
      - ("NP_PP", POS_TUPLE)       : NP internal sequence *extended* with any immediate PP subtree tokens
      - ("NP_COORD", POS_TUPLE)    : if coordination present, POS sequence that includes coordinator/conj tokens
      - ("NP_MULTIHEAD", POS_TUPLE): if multiple noun-like tokens found in chunk (multi-headed compounds)
    Each pattern is included only if it meets minimal length criteria (>=2 tokens).
    """
    patterns = []

    for chunk in doc.noun_chunks:
        # collect tokens in the chunk (surface order)
        chunk_toks = [t for t in chunk if not t.is_punct and not t.is_space]
        if len(chunk_toks) < 2:
            # skip single-token chunks for internal NP patterns (unless subtree yields more)
            pass
        else:
            pos_seq = tuple(t.pos_ for t in chunk_toks)
            if len(pos_seq) >= 2:
                patterns.append(("NP_INTERNAL", pos_seq))

        head = chunk.root

        # 1) dependency subtree rooted at head (captures modifiers, complements)
        subtree_toks = subtree_tokens_sorted(head)
        if len(subtree_toks) >= 2:
            subtree_pos = tuple(t.pos_ for t in subtree_toks)
            patterns.append(("NP_SUBTREE", subtree_pos))

            # Also add lemma-based subtree pattern (useful for lexical signals)
            subtree_lemmas = tuple(t.lemma_.lower() for t in subtree_toks)
            patterns.append(("NP_SUBTREE_LEMMA", subtree_lemmas))

        # 2) expand with immediate PP modifiers (head -> prep children)
        pp_heads = find_pp_modifiers(head)
        if pp_heads:
            # include head subtree + pp subtree tokens (preserve order)
            extended_tokens = subtree_toks.copy()
            for pp in pp_heads:
                extended_tokens += subtree_tokens_sorted(pp)
            # deduplicate and sort by position
            extended_tokens = sorted({t.i: t for t in extended_tokens}.values(), key=lambda x: x.i)
            if len(extended_tokens) >= 2:
                patterns.append(("NP_PP", tuple(t.pos_ for t in extended_tokens)))
                patterns.append(("NP_PP_LEMMA", tuple(t.lemma_.lower() for t in extended_tokens)))

        # 3) coordination detection inside the chunk
        if has_coordination(chunk):
            # include the chunk tokens but preserve cc/conj tokens too
            coord_tokens = [t for t in chunk if not (t.is_punct or t.is_space)]
            if len(coord_tokens) >= 2:
                patterns.append(("NP_COORD", tuple(t.pos_ for t in coord_tokens)))
                patterns.append(("NP_COORD_LEMMA", tuple(t.lemma_.lower() for t in coord_tokens)))

        # 4) multi-headed NP: if more than one noun/proper noun inside chunk
        nounlike_count = count_nounlike_heads(chunk)
        if nounlike_count >= 2:
            # capture the sequence of noun-like tokens (and immediate modifiers)
            noun_tokens = [t for t in chunk if t.pos_ in ("NOUN", "PROPN") or t.dep_ in ("compound", "nmod")]
            if len(noun_tokens) >= 2:
                patterns.append(("NP_MULTIHEAD", tuple(t.pos_ for t in noun_tokens)))
                patterns.append(("NP_MULTIHEAD_LEMMA", tuple(t.lemma_.lower() for t in noun_tokens)))

    return patterns

# ------------------------
# Helper: get raw counters for a text
# ------------------------
def get_counters_for_text(text: str) -> Dict[str, Counter]:
    doc = nlp(text)
    # optional preprocessing hooks can go here (lowercasing/stopword filters) —
    # we keep raw tokens for syntactic patterns, as morphological descriptions rely on function words.
    return {
        "pos": Counter(extract_pos_patterns(doc)),
        "dep": Counter(extract_dependency_patterns(doc)),
        "lemma": Counter(extract_lemma_templates(doc)),
        "phrase": Counter(extract_phrase_patterns(doc)),
    }

# ------------------------
# discover_patterns: corpus-level aggregated
# ------------------------
def discover_patterns(corpus_texts: List[str], min_freq: int = 3):
    pos_ctr = Counter()
    dep_ctr = Counter()
    lemma_ctr = Counter()
    phrase_ctr = Counter()

    for text in corpus_texts:
        counters = get_counters_for_text(text)
        pos_ctr.update(counters["pos"])
        dep_ctr.update(counters["dep"])
        lemma_ctr.update(counters["lemma"])
        phrase_ctr.update(counters["phrase"])

    return {
        "pos_patterns":  {p: c for p, c in pos_ctr.items() if c >= min_freq},
        "dependency_patterns": {p: c for p, c in dep_ctr.items() if c >= min_freq},
        "lemma_templates": {p: c for p, c in lemma_ctr.items() if c >= min_freq},
        "phrase_patterns": {p: c for p, c in phrase_ctr.items() if c >= min_freq},
    }

# ------------------------
# Export helpers
# ------------------------
def export_patterns_to_csv(patterns: Dict[str, Any], filename_prefix: str):
    os.makedirs(os.path.dirname(filename_prefix) or ".", exist_ok=True)
    for name, patdict in patterns.items():
        if isinstance(patdict, Counter):
            items = patdict.most_common()
        else:
            items = sorted(patdict.items(), key=lambda x: -x[1])

        df = pd.DataFrame([
            {"pattern": repr(p), "count": c}
            for p, c in items
        ])
        csv_path = f"{filename_prefix}_{name}.csv"
        df.to_csv(csv_path, index=False)
        print(f"  CSV written: {csv_path}")

def generate_pdf_report(patterns: Dict[str, Any], pdf_filename: str, max_rows: int = 30):
    out_dir = os.path.dirname(pdf_filename)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    styles = getSampleStyleSheet()
    story = [Paragraph("<b>Pattern Discovery Summary Report</b>", styles["Title"]), Spacer(1, 12)]

    for category, pattern_dict in patterns.items():
        story.append(Paragraph(f"<b>{category.replace('_',' ').title()}</b>", styles["Heading2"]))
        rows = [["Pattern", "Count"]]

        if isinstance(pattern_dict, Counter):
            items = pattern_dict.most_common(max_rows)
        else:
            items = sorted(pattern_dict.items(), key=lambda x: -x[1])[:max_rows]

        for pat, count in items:
            rows.append([repr(pat), str(count)])

        table = Table(rows, colWidths=[380, 80])
        table.setStyle(TableStyle([
            ("BACKGROUND", (0,0), (-1,0), colors.lightgrey),
            ("GRID", (0,0), (-1,-1), 0.5, colors.grey),
        ]))
        story.append(table)
        story.append(Spacer(1, 12))

    SimpleDocTemplate(pdf_filename).build(story)
    print(f"  PDF written: {pdf_filename}")

# ------------------------
# Build pattern matrix by type
# ------------------------
def build_pattern_matrix_by_type(file_patterns, pattern_type):
    """
    pattern_type ∈ {"pos", "dep", "lemma", "phrase"}
    Returns DataFrame: rows = documents, columns = patterns
    """
    rows = {}
    for file_id, counters in file_patterns.items():
        rows[file_id] = counters.get(pattern_type, Counter())

    df = pd.DataFrame.from_dict(rows, orient="index").fillna(0)
    df = df.astype(int)
    return df

# ------------------------
# Pipeline runner
# ------------------------
def run_pattern_pipeline(config_file: str = DEFAULT_CONFIG,
                         corpus_min_freq: int = 3,
                         per_file_min_freq: int = 1):

    print("Loading config:", config_file)
    entries = load_corpus_from_config(config_file)
    if not entries:
        print("No entries found. Exiting.")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    all_file_patterns = {}

    # Per-file extraction
    print("Generating per-file pattern reports...")
    for entry in entries:
        file_id = entry["id"]
        text = entry["text"]
        print(f" Processing {file_id} ...")

        counters = get_counters_for_text(text)
        # filter per-file patterns by per_file_min_freq if desired:
        if per_file_min_freq > 1:
            counters = {k: Counter({p:c for p,c in ctr.items() if c >= per_file_min_freq}) for k, ctr in counters.items()}

        all_file_patterns[file_id] = counters

        file_prefix = os.path.join(OUTPUT_DIR, file_id)
        export_patterns_to_csv(counters, filename_prefix=file_prefix)

        pdf_path = os.path.join(OUTPUT_DIR, f"nlp/{file_id}_patterns.pdf")
        generate_pdf_report(counters, pdf_filename=pdf_path, max_rows=PER_FILE_TOP_N)

    # Export pattern matrix by type
    print("Generating pattern matrix by type...")
    os.makedirs("outputs/analyses", exist_ok=True)

    for ptype in ["pos", "dep", "lemma", "phrase"]:
        df = build_pattern_matrix_by_type(all_file_patterns, ptype)

        out = f"outputs/analyses/corpus_{ptype}_patterns.csv"
        df.to_csv(out, index_label="document_id")

        print(f"  Written {out} with shape {df.shape}")

    # Export metadata CSV (all Tier-1/2 fields from config)
    print("Writing metadata CSV...")
    meta_fields = [
        "id", "species", "description_type", "period_class",
        "author_linguistic_background", "publication_year", "publication_journal",
        "journal_type", "publication_country", "depository_code",
        "depository_country", "depository_language_environment",
        "taxonomy_order", "taxonomy_family", "authors", "notes",
    ]
    meta_rows = [{k: e.get(k) for k in meta_fields} for e in entries]
    meta_df = pd.DataFrame(meta_rows)
    meta_df.to_csv("outputs/analyses/metadata.csv", index=False)
    print("  Written outputs/analyses/metadata.csv")

    # Build pattern_comparison.csv: combined matrix across all pattern types
    print("Writing pattern_comparison.csv (combined matrix)...")
    type_dfs = []
    for ptype in ["pos", "dep", "lemma", "phrase"]:
        df_type = build_pattern_matrix_by_type(all_file_patterns, ptype)
        # prefix column names with type to avoid collisions
        df_type.columns = [f"{ptype}:{c}" for c in df_type.columns]
        type_dfs.append(df_type)
    if type_dfs:
        df_combined = pd.concat(type_dfs, axis=1).fillna(0).astype(int)
        df_combined.index.name = "document_id"
        df_combined.to_csv("outputs/analyses/pattern_comparison.csv")
        print(f"  Written outputs/analyses/pattern_comparison.csv with shape {df_combined.shape}")

    # Corpus-level aggregated discovery
    print("Generating corpus-level pattern report...")
    corpus_texts = [e["text"] for e in entries]
    corpus_patterns = discover_patterns(corpus_texts, min_freq=corpus_min_freq)

    corpus_prefix = os.path.join(OUTPUT_DIR, "corpus")
    export_patterns_to_csv(corpus_patterns, filename_prefix=corpus_prefix)

    corpus_pdf = os.path.join(OUTPUT_DIR, "nlp/corpus_patterns.pdf")
    generate_pdf_report(corpus_patterns, pdf_filename=corpus_pdf, max_rows=CORPUS_TOP_N)

    print("All done. Outputs in:", OUTPUT_DIR)

# ------------------------
# CLI entrypoint
# ------------------------
if __name__ == "__main__":
    run_pattern_pipeline()
