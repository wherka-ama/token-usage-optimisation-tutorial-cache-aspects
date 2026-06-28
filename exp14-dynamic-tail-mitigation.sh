#!/bin/bash
# exp14-dynamic-tail-mitigation.sh — Compare dynamic prefix vs dynamic suffix placement

set -euo pipefail

source ./setup.sh

LARGE_CONTEXT=$(printf 'Stable architecture context for cache reuse. %.0s' {1..220})
QUESTION="Explain why prefix stability matters for prompt caching."

setup_otel "exp14-dynamic-prefix"

echo "Phase A: Dynamic timestamp at the beginning (cache-hostile)"
copilot -p "Timestamp: $(date -u +%H:%M:%S). Context: $LARGE_CONTEXT. $QUESTION" \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2

copilot -p "Timestamp: $(date -u +%H:%M:%S). Context: $LARGE_CONTEXT. $QUESTION" \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp14A: Dynamic prefix"

setup_otel "exp14-dynamic-suffix"

echo "Phase B: Same dynamic timestamp moved to the end (cache-friendly)"
copilot -p "Context: $LARGE_CONTEXT. $QUESTION Timestamp: $(date -u +%H:%M:%S)." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2

copilot -p "Context: $LARGE_CONTEXT. $QUESTION Timestamp: $(date -u +%H:%M:%S)." \
  --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp14B: Dynamic suffix"
