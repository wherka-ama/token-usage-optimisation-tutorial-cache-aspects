#!/bin/bash
# exp2-cache-hit.sh — Demonstrate cache hit on repeated identical prompts

set -euo pipefail

source ./setup.sh
setup_otel "exp2-cache-hit"

# Define a large stable context block to amplify the impact
LARGE_CONTEXT=$(printf 'Repeat this stable context to fill space. %.0s' {1..200})
PROMPT="Context: $LARGE_CONTEXT. Explain the concept of eventual consistency."

# First call — creates cache
echo "Running Call 1 (Warm up cache)..."
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Second call — should hit cache (same prefix, within TTL)
echo "Running Call 2 (Should be near 100% hit rate)..."
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp2: Repeated identical prompts"
