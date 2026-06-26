#!/bin/bash
# exp5-mcp-impact.sh — Show how MCP tool definitions affect the prefix

set -euo pipefail

source ./setup.sh

PROMPT="What files are in the current directory?"

# Phase A: Without MCP (disabled)
setup_otel "exp5-no-mcp"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp5A: No MCP"

# Phase B: With built-in MCP (github-mcp-server enabled)
setup_otel "exp5-with-mcp"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp5B: With MCP"
