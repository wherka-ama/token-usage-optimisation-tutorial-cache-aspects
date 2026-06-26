#!/bin/bash
# exp11-ttl-expiry.sh — Show cache miss after delay

set -euo pipefail

source ./setup.sh
setup_otel "exp11-ttl"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Call 1 — create cache
echo "Call 1: Creating cache"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 2 — immediate (should hit cache)
echo "Call 2: Immediate repeat (should hit)"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

echo "Waiting 6 minutes for cache TTL to expire (standard is 5m)..."
sleep 360

# Call 3 — after TTL expiry
echo "Call 3: After 6m delay (should miss)"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp11: TTL expiry"
