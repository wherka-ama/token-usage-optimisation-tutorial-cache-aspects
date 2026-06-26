#!/bin/bash
# exp1-baseline.sh — Establish baseline token usage with a single call

set -euo pipefail

source ./setup.sh
setup_otel "exp1-baseline"

# Single call — no prior cache to hit
copilot -p "Explain the concept of eventual consistency in distributed systems in 3 paragraphs." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

echo "OTel file: $COPILOT_OTEL_FILE_EXPORTER_PATH"
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp1: Baseline single call"
