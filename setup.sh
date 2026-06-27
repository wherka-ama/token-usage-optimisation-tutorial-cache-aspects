#!/bin/bash
# setup.sh — Prepare environment for cache invalidation experiments

set -euo pipefail

export COPILOT_OTEL_ENABLED=true
# Ensure we have the REAL home path for data storage
# If setup.sh was already sourced, REAL_HOME is already set.
export REAL_HOME="${REAL_HOME:-$HOME}"

# Always store data in the real home to avoid nesting
export EXPERIMENT_DIR="$REAL_HOME/cache-experiments"
mkdir -p "$EXPERIMENT_DIR/otel" "$EXPERIMENT_DIR/results" "$EXPERIMENT_DIR/scripts" "$EXPERIMENT_DIR/.tmp"

# Isolation Mode (default: true)
export COPILOT_ISOLATION="${COPILOT_ISOLATION:-true}"

if [ "$COPILOT_ISOLATION" = "true" ]; then
  # Use a stable path for isolated config
  export COPILOT_HOME="$EXPERIMENT_DIR/.tmp/isolated-copilot-home"
  mkdir -p "$COPILOT_HOME"
  
  # Redirect HOME so the CLI doesn't find ~/.agents or ~/.copilot personal skills
  export HOME="$COPILOT_HOME/fake-home"
  mkdir -p "$HOME"

  # Maintain auth by copying settings.json if it exists
  if [ -f "$REAL_HOME/.copilot/settings.json" ] && [ ! -f "$COPILOT_HOME/settings.json" ]; then
    cp "$REAL_HOME/.copilot/settings.json" "$COPILOT_HOME/settings.json"
  fi
  
  # Clear additional resource paths
  export COPILOT_CUSTOM_INSTRUCTIONS_DIRS=""
  export COPILOT_SKILLS_DIRS=""
  
  echo "Experiment Isolation: ENABLED (Data in $EXPERIMENT_DIR, CLI HOME in $HOME)"
else
  echo "Experiment Isolation: DISABLED (using system/user configuration)"
fi

# Default model if not set by environment
export COPILOT_MODEL="${COPILOT_MODEL:-claude-sonnet-4.6}"
echo "Using model: $COPILOT_MODEL"

# Default OTel path for smoke test; experiments will override this
export COPILOT_OTEL_FILE_EXPORTER_PATH="$EXPERIMENT_DIR/otel/copilot-otel-smoke.jsonl"

# Each experiment gets its own OTel file
setup_otel() {
  local experiment_name="$1"
  local timestamp=$(date +%Y%m%d-%H%M%S)
  export COPILOT_OTEL_FILE_EXPORTER_PATH="$EXPERIMENT_DIR/otel/${experiment_name}-${timestamp}.jsonl"
  echo "OTel output: $COPILOT_OTEL_FILE_EXPORTER_PATH"
}

# Validate that OTel is configured correctly
validate_otel() {
  if [[ -z "${COPILOT_OTEL_ENABLED:-}" || "$COPILOT_OTEL_ENABLED" != "true" ]]; then
    echo "ERROR: COPILOT_OTEL_ENABLED is not set to true" >&2
    exit 1
  fi
  if [[ -z "${COPILOT_OTEL_EXPORTER_TYPE:-}" || "$COPILOT_OTEL_EXPORTER_TYPE" != "file" ]]; then
    echo "ERROR: COPILOT_OTEL_EXPORTER_TYPE is not set to file" >&2
    exit 1
  fi
  if [[ -z "${COPILOT_OTEL_FILE_EXPORTER_PATH:-}" ]]; then
    echo "ERROR: COPILOT_OTEL_FILE_EXPORTER_PATH is not set" >&2
    exit 1
  fi
}

# Smoke test to verify OTel output is being produced
smoke_test_otel() {
  echo "Running OTel smoke test..."
  copilot -p "Say 'telemetry test'" --output-format json --silent \
    --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

  if [[ ! -f "$COPILOT_OTEL_FILE_EXPORTER_PATH" ]]; then
    echo "ERROR: OTel file was not created after smoke test" >&2
    exit 1
  fi

  local span_count
  span_count=$(grep -c '"type":"span"' "$COPILOT_OTEL_FILE_EXPORTER_PATH" 2>/dev/null || true)
  if [[ "$span_count" -eq 0 ]]; then
    echo "ERROR: OTel file has no span entries after smoke test" >&2
    exit 1
  fi

  echo "OTel smoke test passed: $span_count span(s) written to $COPILOT_OTEL_FILE_EXPORTER_PATH"
}

# Run validations at startup
validate_otel
smoke_test_otel
