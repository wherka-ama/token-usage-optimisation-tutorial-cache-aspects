#!/bin/bash
# run-all.sh — Run the main experiments and generate a comparison report

set -euo pipefail

# Ensure OTel is set up and working
source ./setup.sh

EXPERIMENTS=(
  "exp2-cache-hit.sh"
  "exp3-timestamp-invalidation.sh"
  "exp6-multi-turn.sh"
  "exp13-hook-impact.sh"
)

RESULTS_DIR="$HOME/cache-experiments/results"
mkdir -p "$RESULTS_DIR"

for exp in "${EXPERIMENTS[@]}"; do
  echo "Running $exp..."
  bash "$exp" 2>&1 | tee "$RESULTS_DIR/${exp%.sh}-output.txt"
  echo ""
done

# Generate comparison table
python3 compare.py "$RESULTS_DIR"
