#!/bin/bash
# exp8-reasoning-effort.sh — Show impact of reasoning effort changes

set -euo pipefail

source ./setup.sh
setup_otel "exp8-reasoning-effort"

PROMPT="Analyze the trade-offs between strong and eventual consistency in a distributed database."

# Call 1 — low effort
echo "Calling with effort=low"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort low 2>/dev/null

# Call 2 — same prompt, same effort (should cache hit)
echo "Repeating with effort=low"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort low 2>/dev/null

# Call 3 — same prompt, DIFFERENT effort
echo "Calling with effort=high"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort high 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp8: Reasoning effort changes"
