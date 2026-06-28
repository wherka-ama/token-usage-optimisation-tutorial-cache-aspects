#!/bin/bash
# discover-models.sh — Discover available Copilot CLI models
#
# Usage:
#   bash discover-models.sh              # Print models to stdout
#   bash discover-models.sh --json       # Print models as JSON array
#   bash discover-models.sh --save FILE  # Save models to FILE (one per line)
#
# Discovery strategy:
# 1. Try parsing copilot --help output for model hints
# 2. Try a probe call with --model auto and inspect OTel for the resolved model
# 3. Fall back to a curated list from tutorial-plan.md

set -euo pipefail

source ./setup.sh 2>/dev/null || true

JSON_MODE=false
SAVE_FILE=""
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=true
elif [[ "${1:-}" == "--save" ]]; then
  SAVE_FILE="${2:-}"
fi

# Curated list from tutorial-plan.md (kept in sync with known Copilot models)
CURATED_MODELS=(
  "claude-sonnet-4.6"
  "claude-sonnet-4.5"
  "claude-haiku-4.5"
  "claude-fable-5"
  "claude-opus-4.8"
  "claude-opus-4.7"
  "claude-opus-4.6"
  "claude-opus-4.6-fast"
  "claude-opus-4.5"
  "gpt-5.5"
  "gpt-5.4"
  "gpt-5.3-codex"
  "gpt-5.4-mini"
  "gpt-5-mini"
  "gemini-3.1-pro-preview"
  "gemini-3.5-flash"
)

# Try to discover models by probing each curated model with a minimal call
# and checking if it succeeds (exit code 0)
DISCOVERED=()
PROBE_PROMPT="Reply with just 'ok'"

probe_model() {
  local model="$1"
  # Suppress all output; check exit code
  copilot -p "$PROBE_PROMPT" --model "$model" --output-format json --silent \
    --no-custom-instructions --disable-builtin-mcps --yolo \
    --allow-all-tools 2>/dev/null >/dev/null
  return $?
}

echo "Discovering available models (this may take a moment)..." >&2
for model in "${CURATED_MODELS[@]}"; do
  if probe_model "$model"; then
    DISCOVERED+=("$model")
    echo "  [OK] $model" >&2
  else
    echo "  [--] $model (not available)" >&2
  fi
done

if [[ ${#DISCOVERED[@]} -eq 0 ]]; then
  echo "WARNING: No models discovered via probing. Falling back to curated list." >&2
  DISCOVERED=("${CURATED_MODELS[@]}")
fi

if $JSON_MODE; then
  echo -n "["
  for i in "${!DISCOVERED[@]}"; do
    [[ $i -gt 0 ]] && echo -n ", "
    echo -n "\"${DISCOVERED[$i]}\""
  done
  echo "]"
elif [[ -n "$SAVE_FILE" ]]; then
  : > "$SAVE_FILE"
  for model in "${DISCOVERED[@]}"; do
    echo "$model" >> "$SAVE_FILE"
  done
  echo "Saved ${#DISCOVERED[@]} models to $SAVE_FILE" >&2
else
  for model in "${DISCOVERED[@]}"; do
    echo "$model"
  done
fi
