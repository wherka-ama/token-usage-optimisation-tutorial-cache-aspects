#!/bin/bash
# exp6-multi-turn.sh — Demonstrate that appending messages preserves cache

set -euo pipefail

source ./setup.sh
setup_otel "exp6-multi-turn"

SESSION_ID=$(uuidgen)

# Turn 1 — create initial cache
copilot -p "Explain the CAP theorem." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 2 — appended to conversation; prior context should be cached
copilot -p "Now explain how it relates to eventual consistency." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 3 — continues appending; cached prefix grows
copilot -p "Give me a real-world example of each combination." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp6: Multi-turn append"
