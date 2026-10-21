"""CLI script to run the BankOps AI RAG evaluation harness.

Loads the eval dataset, runs retrieval from ``app.services.ai_retrieval`` over every
question, and prints a summary report: total questions, Recall@K, citation
accuracy, and per-question results.

Usage:
    python3 scripts/run_ai_eval.py
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Ensure the backend package (`app`) is importable regardless of CWD.
BACKEND_DIR = Path(__file__).resolve().parents[1] / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# Point the retrieval index at the repo docs folder.
REPO_DIR = Path(__file__).resolve().parents[1]
os.environ.setdefault("DOCS_DIR", str(REPO_DIR / "docs"))

from app.services.ai_evaluation import evaluate_rag, load_eval_dataset  # noqa: E402
from app.services.ai_retrieval import retrieve  # noqa: E402


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run BankOps AI RAG evaluation.")
    parser.add_argument(
        "--dataset",
        default=str(REPO_DIR / "backend" / "tests" / "data" / "ai_eval_dataset.jsonl"),
        help="Path to the JSONL eval dataset.",
    )
    parser.add_argument(
        "-k",
        type=int,
        default=3,
        help="Number of top retrieved documents to consider (default: 3).",
    )
    return parser


def print_report(report: dict) -> None:
    agg = report["aggregate"]
    print("=" * 72)
    print("BankOps AI RAG Evaluation Report")
    print("=" * 72)
    print(f"Dataset questions : {report['total_questions']}")
    print(f"Top-K (K)         : {report['k']}")
    print(f"Recall@K          : {agg['recall_hits']}/{report['total_questions']} = {agg['recall_at_k']:.2%}")
    print(f"Citation accuracy : {agg['citation_hits']}/{report['total_questions']} = {agg['citation_accuracy']:.2%}")
    print("-" * 72)
    print(f"{'#':>2}  {'category':<16} {'recall@K':<9} {'citation':<9}  retrieved files")
    print("-" * 72)
    for idx, item in enumerate(report["per_question"], 1):
        files = ", ".join(item["retrieved_source_files"]) or "(none)"
        print(
            f"{idx:>2}  {item['category']:<16} "
            f"{str(item['recall_at_k']):<9} {str(item['citation_accuracy']):<9}  {files}"
        )
    print("=" * 72)


def main() -> int:
    args = build_parser().parse_args()
    eval_set = load_eval_dataset(args.dataset)
    report = evaluate_rag(retrieve, eval_set, k=args.k)
    print_report(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
