#!/bin/bash
# setup.sh — Prepare environment for cache invalidation experiments

set -euo pipefail

export COPILOT_OTEL_ENABLED=true
export COPILOT_OTEL_EXPORTER_TYPE=file
export EXPERIMENT_DIR="$HOME/cache-experiments"
mkdir -p "$EXPERIMENT_DIR/otel" "$EXPERIMENT_DIR/results" "$EXPERIMENT_DIR/scripts"

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
