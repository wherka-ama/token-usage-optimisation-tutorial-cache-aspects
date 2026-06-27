#!/usr/bin/env python3
"""analyze.py — Parse Copilot CLI OTel JSONL and compute cache analytics."""

import json
import sys
import os


def parse_otel_jsonl(filepath: str) -> list[dict]:
    """Parse OTel JSONL file and extract chat span token data."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(
            f"OTel file not found: {filepath}\n"
            "Did you set COPILOT_OTEL_ENABLED=true, COPILOT_OTEL_EXPORTER_TYPE=file, "
            "and COPILOT_OTEL_FILE_EXPORTER_PATH before running copilot?"
        )

    spans = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Only interested in span entries (not metrics)
            if entry.get("type") != "span":
                continue

            attrs = entry.get("attributes", {})
            op_name = attrs.get("gen_ai.operation.name", "")

            # We want chat spans (LLM API calls)
            if op_name != "chat":
                continue

            span_data = {
                "span_name": entry.get("name", ""),
                "trace_id": entry.get("traceId", ""),
                "span_id": entry.get("spanId", ""),
                "parent_span_id": entry.get("parentSpanId", ""),
                "start_time": entry.get("startTime", ""),
                "end_time": entry.get("endTime", ""),
                "model": attrs.get("gen_ai.request.model", attrs.get("gen_ai.response.model", "unknown")),
                "input_tokens": attrs.get("gen_ai.usage.input_tokens", 0),
                "output_tokens": attrs.get("gen_ai.usage.output_tokens", 0),
                "cache_read_tokens": attrs.get("gen_ai.usage.cache_read_input_tokens", 0),
                "cache_creation_tokens": attrs.get("gen_ai.usage.cache_creation_input_tokens", 0),
                # Fallback: dot-separated variants (VS Code format)
                "cache_read_tokens_alt": attrs.get("gen_ai.usage.cache_read.input_tokens", 0),
                "cache_creation_tokens_alt": attrs.get("gen_ai.usage.cache_creation.input_tokens", 0),
            }
            # Use whichever variant is non-zero
            span_data["cache_read"] = span_data["cache_read_tokens"] or span_data["cache_read_tokens_alt"]
            span_data["cache_creation"] = span_data["cache_creation_tokens"] or span_data["cache_creation_tokens_alt"]

            # Compute derived metrics
            span_data["total_input"] = span_data["input_tokens"]
            span_data["uncached_input"] = span_data["input_tokens"] - span_data["cache_read"]
            span_data["cache_hit_rate"] = (
                span_data["cache_read"] / span_data["input_tokens"]
                if span_data["input_tokens"] > 0
                else 0.0
            )
            spans.append(span_data)

    if not spans:
        raise ValueError(
            f"No chat spans found in {filepath}.\n"
            "Possible causes:\n"
            "  - OTel was not enabled before copilot started\n"
            "  - No LLM call was made\n"
            "  - The call failed before reaching the LLM layer\n"
            "  - The cache attributes use the dot-separated variant (VS Code) instead of underscore (Copilot CLI)"
        )

    return spans


def compute_analytics(spans: list[dict]) -> dict:
    """Compute aggregate analytics from chat spans."""
    if not spans:
        return {"error": "No chat spans found"}

    total_input = sum(s["input_tokens"] for s in spans)
    total_output = sum(s["output_tokens"] for s in spans)
    total_cache_read = sum(s["cache_read"] for s in spans)
    total_cache_creation = sum(s["cache_creation"] for s in spans)
    total_uncached = sum(s["uncached_input"] for s in spans)

    # Per-model breakdown
    by_model = {}
    for s in spans:
        model = s["model"]
        if model not in by_model:
            by_model[model] = {
                "calls": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cache_read": 0,
                "cache_creation": 0,
            }
        by_model[model]["calls"] += 1
        by_model[model]["input_tokens"] += s["input_tokens"]
        by_model[model]["output_tokens"] += s["output_tokens"]
        by_model[model]["cache_read"] += s["cache_read"]
        by_model[model]["cache_creation"] += s["cache_creation"]

    for model, data in by_model.items():
        data["cache_hit_rate"] = (
            data["cache_read"] / data["input_tokens"]
            if data["input_tokens"] > 0
            else 0.0
        )
        data["uncached_input"] = data["input_tokens"] - data["cache_read"]

    return {
        "total_llm_calls": len(spans),
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_cache_read_tokens": total_cache_read,
        "total_cache_creation_tokens": total_cache_creation,
        "total_uncached_input_tokens": total_uncached,
        "overall_cache_hit_rate": total_cache_read / total_input if total_input > 0 else 0.0,
        "by_model": by_model,
        "per_call": spans,
    }


def print_report(analytics: dict, label: str = ""):
    """Print a human-readable analytics report."""
    print(f"\n{'=' * 70}")
    print(f"  CACHE ANALYTICS REPORT{' — ' + label if label else ''}")
    print(f"{'=' * 70}")
    print(f"  Total LLM calls:          {analytics['total_llm_calls']}")
    print(f"  Total input tokens:       {analytics['total_input_tokens']:,}")
    print(f"  Total output tokens:      {analytics['total_output_tokens']:,}")
    print(f"  Cache READ tokens:        {analytics['total_cache_read_tokens']:,} (HIT)")
    print(f"  Cache CREATION tokens:    {analytics['total_cache_creation_tokens']:,} (MISS/WRITE)")
    print(f"  Uncached input tokens:    {analytics['total_uncached_input_tokens']:,}")
    print(f"  Overall cache hit rate:   {analytics['overall_cache_hit_rate']:.1%}")

    if analytics['overall_cache_hit_rate'] > 0.5 and "invalidation" in (label or "").lower():
        print("\n  [!] NOTE: High hit rate on an invalidation test suggests a large")
        print("      shared system prefix (e.g. skills) is still being cached.")

    print(f"{'-' * 70}")
    print(f"  Per-model breakdown:")
    for model, data in analytics["by_model"].items():
        print(f"    {model}:")
        print(f"      Calls:              {data['calls']}")
        print(f"      Input tokens:       {data['input_tokens']:,}")
        print(f"      Cache read:         {data['cache_read']:,}")
        print(f"      Cache creation:     {data['cache_creation']:,}")
        print(f"      Cache hit rate:     {data['cache_hit_rate']:.1%}")
        print(f"      Uncached input:     {data['uncached_input']:,}")
    print(f"{'-' * 70}")
    print(f"  Per-call detail:")
    for i, s in enumerate(analytics["per_call"], 1):
        print(f"    Call {i}: model={s['model']}, "
              f"in={s['input_tokens']:,}, "
              f"cache_read={s['cache_read']:,}, "
              f"cache_create={s['cache_creation']:,}, "
              f"hit_rate={s['cache_hit_rate']:.1%}")
    print(f"{'=' * 70}\n")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze.py <otel-jsonl-file> [label]")
        sys.exit(1)

    filepath = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        spans = parse_otel_jsonl(filepath)
        analytics = compute_analytics(spans)
        print_report(analytics, label)

        # Also save JSON output
        json_output = filepath.replace(".jsonl", "-analytics.json")
        with open(json_output, "w") as f:
            json.dump(analytics, f, indent=2)
        print(f"JSON analytics saved to: {json_output}")
    except FileNotFoundError as e:
        print(f"Error: {e}")
        # sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}")
        # sys.exit(1)


if __name__ == "__main__":
    main()
