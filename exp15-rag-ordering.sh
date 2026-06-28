#!/bin/bash
# exp15-rag-ordering.sh — Demonstrate unstable RAG ordering vs deterministic chunk ordering

set -euo pipefail

source ./setup.sh

CHUNK_A="DOC-001: Caching stores reusable computation to reduce repeated prefill work."
CHUNK_B="DOC-002: Prompt prefixes should remain stable across related requests."
CHUNK_C="DOC-003: Dynamic content such as timestamps should be placed near the tail."
CHUNK_D="DOC-004: Tool schemas and retrieved context ordering affect cache reuse."
QUESTION="Using the retrieved context, summarize the practical rule for prompt caching."

setup_otel "exp15-rag-unstable"

echo "Phase A: Retrieved chunks in different relevance order (cache-hostile)"
PROMPT_A="Retrieved context:\n$CHUNK_B\n$CHUNK_D\n$CHUNK_A\n$CHUNK_C\n\n$QUESTION"
PROMPT_B="Retrieved context:\n$CHUNK_A\n$CHUNK_C\n$CHUNK_D\n$CHUNK_B\n\n$QUESTION"

copilot -p "$PROMPT_A" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT_B" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp15A: Unstable RAG order"

setup_otel "exp15-rag-stable"

echo "Phase B: Retrieved chunks sorted by stable document ID (cache-friendly)"
STABLE_PROMPT="Retrieved context:\n$CHUNK_A\n$CHUNK_B\n$CHUNK_C\n$CHUNK_D\n\n$QUESTION"

copilot -p "$STABLE_PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$STABLE_PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp15B: Stable RAG order"
