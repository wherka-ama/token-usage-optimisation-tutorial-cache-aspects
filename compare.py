#!/usr/bin/env python3
"""compare.py — Generate comparison table across all experiments."""

import json
import os
import sys


def load_analytics(results_dir: str) -> list[dict]:
    """Load all analytics JSON files from results directory."""
    results = []
    for root, dirs, files in os.walk(os.path.expanduser(results_dir)):
        for f in files:
            if f.endswith("-analytics.json"):
                filepath = os.path.join(root, f)
                with open(filepath) as fh:
                    data = json.load(fh)
                    data["source_file"] = f
                    results.append(data)
    return results


def print_comparison_table(results: list[dict]):
    """Print a markdown comparison table."""
    print("\n## Cache Invalidation Experiment Results\n")
    print("| Experiment | LLM Calls | Input Tokens | Cache Read | Cache Creation | Hit Rate |")
    print("|---|---|---|---|---|---|")

    for r in results:
        label = r.get("source_file", "unknown").replace("-analytics.json", "")
        calls = r.get("total_llm_calls", 0)
        input_tok = r.get("total_input_tokens", 0)
        cache_read = r.get("total_cache_read_tokens", 0)
        cache_create = r.get("total_cache_creation_tokens", 0)
        hit_rate = r.get("overall_cache_hit_rate", 0)
        print(f"| {label} | {calls} | {input_tok:,} | {cache_read:,} | {cache_create:,} | {hit_rate:.1%} |")

    print()


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 compare.py <results-dir>")
        sys.exit(1)
    results = load_analytics(sys.argv[1])
    print_comparison_table(results)


if __name__ == "__main__":
    main()
