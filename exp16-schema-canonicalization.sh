#!/bin/bash
# exp16-schema-canonicalization.sh — Demonstrate shuffled JSON/schema blocks vs canonical ordering

set -euo pipefail

source ./setup.sh

QUESTION="Explain what these tool schemas let an assistant do."

SCHEMA_A='{"tools":[{"name":"read_file","description":"Read a file","input_schema":{"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"integer"}},"required":["path"]}},{"name":"search","description":"Search files","input_schema":{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"}},"required":["query"]}}]}'
SCHEMA_B='{"tools":[{"description":"Search files","name":"search","input_schema":{"required":["query"],"properties":{"path":{"type":"string"},"query":{"type":"string"}},"type":"object"}},{"input_schema":{"required":["path"],"properties":{"offset":{"type":"integer"},"path":{"type":"string"}},"type":"object"},"description":"Read a file","name":"read_file"}]}'
CANONICAL_SCHEMA='{"tools":[{"description":"Read a file","input_schema":{"properties":{"offset":{"type":"integer"},"path":{"type":"string"}},"required":["path"],"type":"object"},"name":"read_file"},{"description":"Search files","input_schema":{"properties":{"path":{"type":"string"},"query":{"type":"string"}},"required":["query"],"type":"object"},"name":"search"}]}'

setup_otel "exp16-shuffled-schema"

echo "Phase A: Semantically equivalent schema serialized differently (cache-hostile)"
copilot -p "Tool schema: $SCHEMA_A\n\n$QUESTION" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "Tool schema: $SCHEMA_B\n\n$QUESTION" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp16A: Shuffled schema"

setup_otel "exp16-canonical-schema"

echo "Phase B: Canonical schema ordering reused exactly (cache-friendly)"
copilot -p "Tool schema: $CANONICAL_SCHEMA\n\n$QUESTION" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "Tool schema: $CANONICAL_SCHEMA\n\n$QUESTION" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp16B: Canonical schema"
