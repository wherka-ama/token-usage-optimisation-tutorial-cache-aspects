#!/bin/bash
# exp3-timestamp-invalidation.sh — Demonstrate how dynamic prefix content kills cache

set -euo pipefail

source ./setup.sh
setup_otel "exp3-timestamp"

# Call 1 — with a dynamic prefix (timestamp). This simulates a "Today is..." injection
# at the start of the system prompt or user context.
copilot -p "Current time context: $(date -u +%H:%M:%S). Explain eventual consistency in distributed systems in 3 paragraphs." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2  # Small delay to ensure the timestamp changes

# Call 2 — the only difference is the timestamp, so the prefix no longer matches
copilot -p "Current time context: $(date -u +%H:%M:%S). Explain eventual consistency in distributed systems in 3 paragraphs." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp3: Timestamp invalidation"
