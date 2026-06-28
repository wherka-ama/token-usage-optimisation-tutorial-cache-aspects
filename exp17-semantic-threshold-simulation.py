#!/usr/bin/env python3
"""exp17-semantic-threshold-simulation.py — Offline semantic-cache threshold exercise."""

from __future__ import annotations

from dataclasses import dataclass
from math import sqrt


@dataclass(frozen=True)
class Pair:
    cached_prompt: str
    incoming_prompt: str
    similarity: float
    equivalent: bool
    note: str


PAIRS = [
    Pair(
        "Reset my password",
        "How do I change my password?",
        0.91,
        True,
        "Safe paraphrase: same intent and same response policy.",
    ),
    Pair(
        "Delete my account",
        "Deactivate my account temporarily",
        0.86,
        False,
        "Dangerous false positive: similar words, different irreversible action.",
    ),
    Pair(
        "Summarize Q1 revenue",
        "Summarize Q2 revenue",
        0.84,
        False,
        "Parameter mismatch: quarter changes the correct answer.",
    ),
    Pair(
        "What was CPU usage yesterday?",
        "What is CPU usage now?",
        0.82,
        False,
        "Temporal mismatch: live state must bypass semantic cache.",
    ),
    Pair(
        "Explain eventual consistency",
        "Explain strong consistency",
        0.78,
        False,
        "Topic-near but answer should differ.",
    ),
    Pair(
        "Explain prompt caching",
        "What is prompt caching?",
        0.93,
        True,
        "Safe paraphrase.",
    ),
    Pair(
        "List files in /tmp",
        "List files in /var/log",
        0.80,
        False,
        "Tool parameter differs; cached tool result would be wrong.",
    ),
    Pair(
        "Convert 100 USD to EUR",
        "Convert 100 USD to EUR using current FX rate",
        0.88,
        False,
        "Fresh external data requirement changes validity.",
    ),
]


def evaluate(threshold: float) -> dict[str, float]:
    hits = [p for p in PAIRS if p.similarity >= threshold]
    false_hits = [p for p in hits if not p.equivalent]
    misses = [p for p in PAIRS if p.similarity < threshold]
    safe_misses = [p for p in misses if p.equivalent]
    precision = (len(hits) - len(false_hits)) / len(hits) if hits else 1.0
    recall = (len(hits) - len(false_hits)) / sum(1 for p in PAIRS if p.equivalent)
    return {
        "threshold": threshold,
        "hits": len(hits),
        "false_hits": len(false_hits),
        "safe_misses": len(safe_misses),
        "precision": precision,
        "recall": recall,
    }


def print_table() -> None:
    print("# Semantic Cache Static Threshold Simulation")
    print()
    print("This offline exercise mirrors the vCache/MeanCache lesson: one global similarity threshold can produce false positives or miss safe reuse opportunities.")
    print()
    print("| Threshold | Hits | False Hits | Safe Misses | Precision | Recall |")
    print("|---:|---:|---:|---:|---:|---:|")
    for threshold in [0.75, 0.80, 0.85, 0.90, 0.95]:
        row = evaluate(threshold)
        print(
            f"| {row['threshold']:.2f} | {row['hits']} | {row['false_hits']} | "
            f"{row['safe_misses']} | {row['precision']:.0%} | {row['recall']:.0%} |"
        )
    print()
    print("## Pairs that cause false positives at threshold 0.80")
    print()
    for pair in PAIRS:
        if pair.similarity >= 0.80 and not pair.equivalent:
            print(f"- similarity={pair.similarity:.2f}: {pair.cached_prompt!r} -> {pair.incoming_prompt!r}")
            print(f"  - {pair.note}")
    print()
    print("## Practical conclusion")
    print()
    print("- Static semantic thresholds can improve hit rate but do not provide correctness guarantees.")
    print("- Parameter-rich, temporal, tool-result, or safety-critical prompts should bypass naive semantic caching.")
    print("- Verified/adaptive policies such as vCache, Krites, temporal semantic caching, or plan/tool-level caches are safer patterns.")


if __name__ == "__main__":
    print_table()
