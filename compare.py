#!/usr/bin/env python3
"""compare.py — Generate comparison table, token cost estimates, and best-practice
gain/loss analysis across all experiments.

Usage:
    python3 compare.py <results-dir> [--pricing <pricing-json-file>]

If --pricing is omitted, default per-token rates are used (see DEFAULT_PRICING).
Pricing JSON format:
    {"claude-sonnet-4.6": {"input": 3.0, "cached_read": 0.30, "cached_write": 3.75, "output": 15.0}, ...}
All rates are per 1M tokens, in USD.
"""

import json
import os
import sys
import argparse

# Default pricing per 1M tokens (USD), grounded in public provider pricing as of mid-2025.
# These are approximate and should be updated with current provider docs.
# cached_write typically costs 25% more than input (Anthropic) or equals input (OpenAI).
DEFAULT_PRICING = {
    "claude-sonnet-4.6": {"input": 3.0, "cached_read": 0.30, "cached_write": 3.75, "output": 15.0},
    "claude-sonnet-4.5": {"input": 3.0, "cached_read": 0.30, "cached_write": 3.75, "output": 15.0},
    "claude-haiku-4.5": {"input": 0.80, "cached_read": 0.08, "cached_write": 1.0, "output": 4.0},
    "gpt-5.4": {"input": 2.50, "cached_read": 1.25, "cached_write": 2.50, "output": 10.0},
    "gpt-5.5": {"input": 2.50, "cached_read": 1.25, "cached_write": 2.50, "output": 10.0},
    "gpt-5.4-mini": {"input": 0.15, "cached_read": 0.075, "cached_write": 0.15, "output": 0.60},
    "gpt-5-mini": {"input": 0.15, "cached_read": 0.075, "cached_write": 0.15, "output": 0.60},
    "gemini-3.5-flash": {"input": 0.075, "cached_read": 0.01875, "cached_write": 0.075, "output": 0.30},
    "gemini-3.1-pro-preview": {"input": 1.25, "cached_read": 0.3125, "cached_write": 1.25, "output": 5.0},
    "default": {"input": 3.0, "cached_read": 0.30, "cached_write": 3.75, "output": 15.0},
}

# Pairs of experiments for best-practice gain/loss comparison.
# Each pair: (anti_pattern_label, anti_pattern_key, best_practice_label, best_practice_key, description)
# Keys are matched against the experiment label (source_file with timestamp stripped).
GAIN_LOSS_PAIRS = [
    ("Exp3: Timestamp prefix", "exp3-timestamp",
     "Exp14B: Dynamic suffix", "exp14-dynamic-suffix",
     "Moving dynamic content from prefix to suffix"),
    ("Exp15A: Unstable RAG order", "exp15-rag-unstable",
     "Exp15B: Stable RAG order", "exp15-rag-stable",
     "Deterministic RAG chunk ordering"),
    ("Exp16A: Shuffled schema", "exp16-shuffled-schema",
     "Exp16B: Canonical schema", "exp16-canonical-schema",
     "Canonical JSON/schema serialization"),
    ("Exp7: Model switching", "exp7-model-switch",
     "Exp2: Repeated identical", "exp2-cache-hit",
     "Staying on one model vs switching mid-session"),
]


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


def clean_label(filename: str) -> str:
    """Extract a clean experiment label from the analytics filename."""
    label = filename.split("-202")[0] if "-202" in filename else filename.replace("-analytics.json", "")
    return label


def get_pricing(model: str, pricing: dict) -> dict:
    """Get pricing for a model, falling back to default."""
    return pricing.get(model, pricing.get("default", pricing["default"]))


def compute_cost(analytics: dict, pricing: dict) -> dict:
    """Compute estimated token cost for a single experiment's analytics."""
    total_cost = 0.0
    cost_breakdown = {"input": 0.0, "cached_read": 0.0, "cached_write": 0.0, "output": 0.0}

    by_model = analytics.get("by_model", {})
    for model, data in by_model.items():
        p = get_pricing(model, pricing)
        uncached_input = data["input_tokens"] - data["cache_read"]
        input_cost = (uncached_input / 1_000_000) * p["input"]
        cached_read_cost = (data["cache_read"] / 1_000_000) * p["cached_read"]
        cached_write_cost = (data["cache_creation"] / 1_000_000) * p["cached_write"]
        output_cost = (data["output_tokens"] / 1_000_000) * p["output"]
        model_cost = input_cost + cached_read_cost + cached_write_cost + output_cost
        total_cost += model_cost
        cost_breakdown["input"] += input_cost
        cost_breakdown["cached_read"] += cached_read_cost
        cost_breakdown["cached_write"] += cached_write_cost
        cost_breakdown["output"] += output_cost

    return {"total_cost_usd": total_cost, **cost_breakdown}


def compute_no_cache_cost(analytics: dict, pricing: dict) -> float:
    """Compute what the experiment would cost with zero caching (all input at full rate)."""
    total = 0.0
    by_model = analytics.get("by_model", {})
    for model, data in by_model.items():
        p = get_pricing(model, pricing)
        total += (data["input_tokens"] / 1_000_000) * p["input"]
        total += (data["output_tokens"] / 1_000_000) * p["output"]
    return total


def print_comparison_table(results: list[dict], pricing: dict):
    """Print a markdown comparison table with token cost estimates."""
    results.sort(key=lambda x: x.get("source_file", ""))

    print("\n## Cache Experiment Results — Token Usage & Cost Estimates\n")
    print("| Experiment | Calls | Input Tokens | Cache Read | Cache Creation | Output Tokens | Hit Rate | Est. Cost (USD) | No-Cache Cost | Savings |")
    print("|---|---|---|---|---|---|---|---|---|---|")

    grand_input = 0
    grand_cache_read = 0
    grand_cache_create = 0
    grand_output = 0
    grand_cost = 0.0
    grand_no_cache = 0.0

    for r in results:
        label = clean_label(r.get("source_file", "unknown"))
        calls = r.get("total_llm_calls", 0)
        input_tok = r.get("total_input_tokens", 0)
        cache_read = r.get("total_cache_read_tokens", 0)
        cache_create = r.get("total_cache_creation_tokens", 0)
        output_tok = r.get("total_output_tokens", 0)
        hit_rate = r.get("overall_cache_hit_rate", 0)

        cost = compute_cost(r, pricing)
        no_cache = compute_no_cache_cost(r, pricing)
        savings = no_cache - cost["total_cost_usd"]
        savings_pct = (savings / no_cache * 100) if no_cache > 0 else 0.0

        print(f"| {label} | {calls} | {input_tok:,} | {cache_read:,} | {cache_create:,} | {output_tok:,} | {hit_rate:.1%} | ${cost['total_cost_usd']:.4f} | ${no_cache:.4f} | ${savings:.4f} ({savings_pct:.0f}%) |")

        grand_input += input_tok
        grand_cache_read += cache_read
        grand_cache_create += cache_create
        grand_output += output_tok
        grand_cost += cost["total_cost_usd"]
        grand_no_cache += no_cache

    grand_hit = grand_cache_read / grand_input if grand_input > 0 else 0
    grand_savings = grand_no_cache - grand_cost
    grand_savings_pct = (grand_savings / grand_no_cache * 100) if grand_no_cache > 0 else 0
    print(f"| **TOTAL** | | **{grand_input:,}** | **{grand_cache_read:,}** | **{grand_cache_create:,}** | **{grand_output:,}** | **{grand_hit:.1%}** | **${grand_cost:.4f}** | **${grand_no_cache:.4f}** | **${grand_savings:.4f} ({grand_savings_pct:.0f}%)** |")
    print()


def print_gain_loss_analysis(results: list[dict], pricing: dict):
    """Print best-practice gain/loss analysis by comparing anti-pattern vs best-practice experiments."""
    results.sort(key=lambda x: x.get("source_file", ""))
    by_label = {}
    for r in results:
        by_label[clean_label(r.get("source_file", ""))] = r

    print("\n## Best-Practice Gain/Loss Analysis\n")
    print("Compares anti-pattern experiments against their best-practice counterparts to estimate")
    print("the cost impact of each practice, grounded in actual benchmark results.\n")
    print("| Anti-Pattern | Best Practice | Practice Description | Anti-Pattern Cost | Best-Practice Cost | Delta | Delta % |")
    print("|---|---|---|---|---|---|---|")

    for anti_label, anti_key, best_label, best_key, desc in GAIN_LOSS_PAIRS:
        anti_r = by_label.get(anti_key)
        best_r = by_label.get(best_key)
        if not anti_r or not best_r:
            print(f"| {anti_label} | {best_label} | {desc} | _not found_ | _not found_ | — | — |")
            continue

        anti_cost = compute_cost(anti_r, pricing)["total_cost_usd"]
        best_cost = compute_cost(best_r, pricing)["total_cost_usd"]
        delta = anti_cost - best_cost
        delta_pct = (delta / anti_cost * 100) if anti_cost > 0 else 0.0

        print(f"| {anti_label} | {best_label} | {desc} | ${anti_cost:.4f} | ${best_cost:.4f} | ${delta:.4f} | {delta_pct:+.1f}% |")

    print()
    print("> **Note:** Cost deltas are approximate, based on default per-token pricing.")
    print("> Override with `--pricing <file>` for provider-specific rates.")
    print("> Token counts are from actual experiment runs; costs are estimates derived from those counts.")
    print()


def print_per_model_summary(results: list[dict], pricing: dict):
    """Print a per-model token and cost summary across all experiments."""
    model_totals = {}

    for r in results:
        by_model = r.get("by_model", {})
        for model, data in by_model.items():
            if model not in model_totals:
                model_totals[model] = {
                    "calls": 0, "input_tokens": 0, "output_tokens": 0,
                    "cache_read": 0, "cache_creation": 0,
                }
            model_totals[model]["calls"] += data["calls"]
            model_totals[model]["input_tokens"] += data["input_tokens"]
            model_totals[model]["output_tokens"] += data["output_tokens"]
            model_totals[model]["cache_read"] += data["cache_read"]
            model_totals[model]["cache_creation"] += data["cache_creation"]

    if not model_totals:
        return

    print("\n## Per-Model Token & Cost Summary\n")
    print("| Model | Calls | Input Tokens | Cache Read | Cache Creation | Output Tokens | Hit Rate | Est. Cost (USD) |")
    print("|---|---|---|---|---|---|---|---|")

    for model in sorted(model_totals.keys()):
        d = model_totals[model]
        hit = d["cache_read"] / d["input_tokens"] if d["input_tokens"] > 0 else 0
        p = get_pricing(model, pricing)
        uncached = d["input_tokens"] - d["cache_read"]
        cost = (
            (uncached / 1_000_000) * p["input"]
            + (d["cache_read"] / 1_000_000) * p["cached_read"]
            + (d["cache_creation"] / 1_000_000) * p["cached_write"]
            + (d["output_tokens"] / 1_000_000) * p["output"]
        )
        print(f"| {model} | {d['calls']} | {d['input_tokens']:,} | {d['cache_read']:,} | {d['cache_creation']:,} | {d['output_tokens']:,} | {hit:.1%} | ${cost:.4f} |")

    print()


def main():
    parser = argparse.ArgumentParser(description="Compare cache experiment results with cost estimates")
    parser.add_argument("results_dir", help="Directory containing *-analytics.json files")
    parser.add_argument("--pricing", help="JSON file with per-model token pricing (per 1M tokens)")
    args = parser.parse_args()

    pricing = DEFAULT_PRICING
    if args.pricing:
        with open(args.pricing) as f:
            pricing = json.load(f)
        if "default" not in pricing:
            pricing["default"] = DEFAULT_PRICING["default"]

    results = load_analytics(args.results_dir)
    if not results:
        print(f"No *-analytics.json files found in {args.results_dir}")
        sys.exit(1)

    print_comparison_table(results, pricing)
    print_per_model_summary(results, pricing)
    print_gain_loss_analysis(results, pricing)


if __name__ == "__main__":
    main()
