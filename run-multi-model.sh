#!/bin/bash
# run-multi-model.sh — Run all experiments across multiple models sequentially
#
# For each model: runs all experiments, generates a per-model report.
# After all models: generates a combined sky-view comparison report.
#
# Usage:
#   bash run-multi-model.sh "model1" "model2" "model3"
#   bash run-multi-model.sh $(bash discover-models.sh)
#   COPILOT_MODELS="claude-sonnet-4.6 gpt-5.4 gemini-3.5-flash" bash run-multi-model.sh
#
# Output:
#   $EXPERIMENT_DIR/results/multi-model/
#     ├── <model>/                    # Per-model OTel + analytics
#     │   ├── otel/*.jsonl
#     │   ├── otel/*-analytics.json
#     │   └── report.md
#     ├── sky-view-comparison.md      # Combined cross-model report
#     └── sky-view-raw-data.json      # Machine-readable summary

set -euo pipefail

# Source setup.sh once for the initial smoke test and base configuration
source ./setup.sh
# After initial setup, skip smoke tests for subsequent experiment runs
export COPILOT_SKIP_SMOKE_TEST=true

# Collect models from arguments or environment
if [[ $# -gt 0 ]]; then
  MODELS=("$@")
elif [[ -n "${COPILOT_MODELS:-}" ]]; then
  read -ra MODELS <<< "$COPILOT_MODELS"
else
  echo "Usage: bash run-multi-model.sh <model1> [model2] [modelN]"
  echo "   or: COPILOT_MODELS=\"m1 m2\" bash run-multi-model.sh"
  echo "   or: bash run-multi-model.sh \$(bash discover-models.sh)"
  exit 1
fi

if [[ ${#MODELS[@]} -eq 0 ]]; then
  echo "ERROR: No models specified." >&2
  exit 1
fi

MULTI_DIR="$EXPERIMENT_DIR/results/multi-model"
mkdir -p "$MULTI_DIR"

# Experiments to run (same as run-all.sh minus exp11 TTL and exp12 cross-model)
EXPERIMENTS=(
  "exp1-baseline.sh"
  "exp2-cache-hit.sh"
  "exp3-timestamp-invalidation.sh"
  "exp4-custom-instructions.sh"
  "exp5-mcp-impact.sh"
  "exp6-multi-turn.sh"
  "exp7-model-switch.sh"
  "exp8-reasoning-effort.sh"
  "exp9-skills-impact.sh"
  "exp10-tool-execution.sh"
  "exp13-hook-impact.sh"
  "exp14-dynamic-tail-mitigation.sh"
  "exp15-rag-ordering.sh"
  "exp16-schema-canonicalization.sh"
)

# Save the original model to restore later
ORIG_MODEL="$COPILOT_MODEL"

echo "=== Multi-Model Benchmark Run ==="
echo "Models: ${MODELS[*]}"
echo "Experiments: ${#EXPERIMENTS[@]}"
echo ""

# JSON accumulator for sky-view
echo "{" > "$MULTI_DIR/sky-view-raw-data.json"
echo '  "models": [' >> "$MULTI_DIR/sky-view-raw-data.json"

FIRST_MODEL=true

for model in "${MODELS[@]}"; do
  echo "--- Running all experiments with model: $model ---"

  MODEL_DIR="$MULTI_DIR/$model"
  mkdir -p "$MODEL_DIR/otel"

  # Set the model for this run
  export COPILOT_MODEL="$model"

  # Clear previous OTel data for this model
  rm -f "$MODEL_DIR/otel"/*.jsonl "$MODEL_DIR/otel"/*.json

  # Redirect experiment OTel output to model-specific directory
  # setup.sh respects EXPERIMENT_DIR_OVERRIDE when sourced by experiments
  export EXPERIMENT_DIR_OVERRIDE="$MODEL_DIR"

  for exp in "${EXPERIMENTS[@]}"; do
    echo "  Running $exp..."
    bash "$exp" 2>&1 | tee "$MODEL_DIR/${exp%.sh}-output.txt" || {
      echo "  WARNING: $exp failed for model $model, continuing..." >&2
    }
    echo ""
  done

  # Generate per-model report
  python3 compare.py "$MODEL_DIR/otel" > "$MODEL_DIR/report.md" 2>/dev/null || {
    echo "  WARNING: compare.py failed for model $model" >&2
  }
  echo "  Per-model report: $MODEL_DIR/report.md"

  # Run offline semantic simulation (model-independent)
  python3 exp17-semantic-threshold-simulation.py > "$MODEL_DIR/exp17-output.txt" 2>/dev/null || true

  # Collect summary stats for sky-view JSON
  TOTAL_INPUT=0
  TOTAL_CACHE_READ=0
  TOTAL_CACHE_CREATE=0
  TOTAL_OUTPUT=0
  TOTAL_CALLS=0
  TOTAL_COST=0
  TOTAL_NO_CACHE=0

  for jsonfile in "$MODEL_DIR/otel"/*-analytics.json; do
    [[ -f "$jsonfile" ]] || continue
    # Extract totals using python
    read -r inp cr cc out calls <<< "$(python3 -c "
import json, sys
with open('$jsonfile') as f:
    d = json.load(f)
print(d.get('total_input_tokens',0), d.get('total_cache_read_tokens',0),
      d.get('total_cache_creation_tokens',0), d.get('total_output_tokens',0),
      d.get('total_llm_calls',0))
" 2>/dev/null || echo "0 0 0 0 0")"
    TOTAL_INPUT=$((TOTAL_INPUT + inp))
    TOTAL_CACHE_READ=$((TOTAL_CACHE_READ + cr))
    TOTAL_CACHE_CREATE=$((TOTAL_CACHE_CREATE + cc))
    TOTAL_OUTPUT=$((TOTAL_OUTPUT + out))
    TOTAL_CALLS=$((TOTAL_CALLS + calls))
  done

  HIT_RATE="0"
  if [[ $TOTAL_INPUT -gt 0 ]]; then
    HIT_RATE=$(python3 -c "print(f'{$TOTAL_CACHE_READ / $TOTAL_INPUT * 100:.1f}')")
  fi

  # Append to sky-view JSON
  if ! $FIRST_MODEL; then
    echo "    ," >> "$MULTI_DIR/sky-view-raw-data.json"
  fi
  echo "    {\"model\": \"$model\", \"calls\": $TOTAL_CALLS, \"input_tokens\": $TOTAL_INPUT, \"cache_read\": $TOTAL_CACHE_READ, \"cache_creation\": $TOTAL_CACHE_CREATE, \"output_tokens\": $TOTAL_OUTPUT, \"hit_rate_pct\": $HIT_RATE}" >> "$MULTI_DIR/sky-view-raw-data.json"
  FIRST_MODEL=false

  echo "  Summary: calls=$TOTAL_CALLS, input=$TOTAL_INPUT, cache_read=$TOTAL_CACHE_READ, hit_rate=${HIT_RATE}%"
  echo ""
done

echo "  ]" >> "$MULTI_DIR/sky-view-raw-data.json"
echo "}" >> "$MULTI_DIR/sky-view-raw-data.json"

# Restore original model and clear override
export COPILOT_MODEL="$ORIG_MODEL"
unset EXPERIMENT_DIR_OVERRIDE
unset COPILOT_SKIP_SMOKE_TEST

# Generate sky-view comparison report
echo "=== Generating Sky-View Comparison Report ==="

{
  echo "# Multi-Model Sky-View Comparison Report"
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "## Cross-Model Token & Cache Summary"
  echo ""
  echo "| Model | LLM Calls | Input Tokens | Cache Read | Cache Creation | Output Tokens | Hit Rate |"
  echo "|---|---|---|---|---|---|---|"

  python3 -c "
import json
with open('$MULTI_DIR/sky-view-raw-data.json') as f:
    data = json.load(f)
for m in data['models']:
    print(f\"| {m['model']} | {m['calls']} | {m['input_tokens']:,} | {m['cache_read']:,} | {m['cache_creation']:,} | {m['output_tokens']:,} | {m['hit_rate_pct']}% |\")
"

  echo ""
  echo "## Per-Model Detailed Reports"
  echo ""
  for model in "${MODELS[@]}"; do
    echo "### $model"
    echo ""
    if [[ -f "$MULTI_DIR/$model/report.md" ]]; then
      cat "$MULTI_DIR/$model/report.md"
    else
      echo "_Report not available (experiment run may have failed)._"
    fi
    echo ""
  done

  echo "## Key Cross-Model Observations"
  echo ""
  echo "- Compare hit rates across models to check whether caching behavior is consistent."
  echo "- Models with lower hit rates may have different prefix-matching granularity or TTL behavior."
  echo "- Token counts vary by tokenizer; the same prompt produces different token counts across providers."
  echo "- Cost estimates depend on per-model pricing; see per-model reports for cost breakdowns."
  echo ""
} > "$MULTI_DIR/sky-view-comparison.md"

echo "Sky-view report: $MULTI_DIR/sky-view-comparison.md"
echo "Raw JSON data: $MULTI_DIR/sky-view-raw-data.json"
echo ""
echo "=== Multi-Model Benchmark Complete ==="
