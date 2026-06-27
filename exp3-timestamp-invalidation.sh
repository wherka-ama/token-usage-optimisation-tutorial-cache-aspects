#!/bin/bash
# exp3-timestamp-invalidation.sh — Demonstrate how dynamic prefix content kills cache

set -euo pipefail

source ./setup.sh
setup_otel "exp3-timestamp"

# Define a large stable context block to amplify the impact
LARGE_CONTEXT=$(printf 'Repeat this stable context to fill space. %.0s' {1..200})

# Call 1 — with a dynamic prefix (timestamp).
echo "Running Call 1 (Timestamp A)..."
copilot -p "Today is $(date -u +%H:%M:%S). Context: $LARGE_CONTEXT. Explain eventual consistency." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2

# Call 2 — the only difference is the timestamp at the VERY BEGINNING.
# This should cause the ENTIRE large context block to be re-processed (cache miss).
echo "Running Call 2 (Timestamp B - should break cache for the large block)..."
copilot -p "Today is $(date -u +%H:%M:%S). Context: $LARGE_CONTEXT. Explain eventual consistency." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp3: Timestamp invalidation"
