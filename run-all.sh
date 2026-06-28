#!/bin/bash
# run-all.sh — Run the main experiments and generate a comparison report

set -euo pipefail

# Ensure OTel is set up and working
source ./setup.sh

# Clear previous experiment data for a clean report
rm -rf "$EXPERIMENT_DIR/otel"/*.jsonl
rm -rf "$EXPERIMENT_DIR/otel"/*.json
mkdir -p "$EXPERIMENT_DIR/otel"

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
  # "exp11-ttl-expiry.sh" # Excluded by default due to 6m wait
  "exp12-cross-model.sh"
  "exp13-hook-impact.sh"
  "exp14-dynamic-tail-mitigation.sh"
  "exp15-rag-ordering.sh"
  "exp16-schema-canonicalization.sh"
)

RESULTS_DIR="$HOME/cache-experiments/results"
mkdir -p "$RESULTS_DIR"

for exp in "${EXPERIMENTS[@]}"; do
  echo "Running $exp..."
  bash "$exp" 2>&1 | tee "$RESULTS_DIR/${exp%.sh}-output.txt"
  echo ""
done

# Generate comparison table
python3 compare.py "$EXPERIMENT_DIR/otel"

# Run offline semantic-cache simulation
python3 exp17-semantic-threshold-simulation.py | tee "$RESULTS_DIR/exp17-semantic-threshold-simulation-output.txt"
