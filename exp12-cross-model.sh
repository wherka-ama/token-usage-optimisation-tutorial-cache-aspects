#!/bin/bash
# exp12-cross-model.sh — Compare caching across providers

set -euo pipefail

source ./setup.sh
setup_otel "exp12-cross-model"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Claude
echo "Testing Claude..."
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# GPT
echo "Testing GPT..."
copilot -p "$PROMPT" --model gpt-5.4 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model gpt-5.4 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Gemini
echo "Testing Gemini..."
copilot -p "$PROMPT" --model gemini-3.5-flash --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model gemini-3.5-flash --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp12: Cross-model comparison"
