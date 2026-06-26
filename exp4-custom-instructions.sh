#!/bin/bash
# exp4-custom-instructions.sh — Show impact of custom instructions on caching

set -euo pipefail

source ./setup.sh

# Create a large AGENTS.md file to make the impact visible
mkdir -p .github
cat > .github/copilot-instructions.md << 'EOF'
# Project Instructions
## Coding Standards
This project follows strict coding standards for all contributions.
All code must be written in TypeScript with explicit type annotations.
We use functional programming patterns and avoid classes unless necessary.
Error handling follows the Result pattern — no exceptions in business logic.
All functions must have JSDoc comments with @param and @returns tags.
Tests are written using Vitest and must achieve 100% code coverage.
We use pnpm as our package manager and enforce conventional commits.
(Repeat stable instructions to fill context)
EOF

PROMPT="Explain the builder pattern in software design."

# Phase A: WITHOUT custom instructions
setup_otel "exp4-no-instructions"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp4A: No custom instructions"

# Phase B: WITH custom instructions (same user prompt)
setup_otel "exp4-with-instructions"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp4B: With custom instructions"

# Cleanup
rm -f .github/copilot-instructions.md
