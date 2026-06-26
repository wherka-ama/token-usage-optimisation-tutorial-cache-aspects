#!/bin/bash
# exp2-cache-hit.sh — Demonstrate cache hit on repeated identical prompts

set -euo pipefail

source ./setup.sh
setup_otel "exp2-cache-hit"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# First call — creates cache
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Second call — should hit cache (same prefix, within TTL)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp2: Repeated identical prompts"
