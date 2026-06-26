#!/bin/bash
# exp7-model-switch.sh — Demonstrate cache invalidation on model switch

set -euo pipefail

source ./setup.sh
setup_otel "exp7-model-switch"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Call 1 — Primary model
echo "Calling primary model: $COPILOT_MODEL"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 2 — Same prompt, same model (should cache hit)
echo "Repeating call to: $COPILOT_MODEL"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 3 — Same prompt, DIFFERENT model (cache miss)
ALT_MODEL="gpt-5.4"
if [ "$COPILOT_MODEL" == "gpt-5.4" ]; then ALT_MODEL="claude-sonnet-4.6"; fi
echo "Switching to alternative model: $ALT_MODEL"

copilot -p "$PROMPT" --model "$ALT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 4 — Back to primary model
echo "Switching back to primary model: $COPILOT_MODEL"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp7: Model switching"
