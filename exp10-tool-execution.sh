#!/bin/bash
# exp10-tool-execution.sh — Show impact of tool execution on caching

set -euo pipefail

source ./setup.sh
setup_otel "exp10-tool-execution"

SESSION_ID=$(uuidgen)

# Turn 1 — simple question
echo "Turn 1: Simple question"
copilot -p "What is the capital of France?" --model "$COPILOT_MODEL" \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 2 — requires file listing tool
echo "Turn 2: Tool execution (ls)"
copilot -p "List all files in the current directory." --model "$COPILOT_MODEL" \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 3 — follow-up
echo "Turn 3: Follow-up question"
copilot -p "Now explain why prefix stability matters for the output I just saw." --model "$COPILOT_MODEL" \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp10: Tool execution impact"
