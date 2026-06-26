#!/bin/bash
# exp13-hook-impact.sh — Demonstrate how dynamic context from hooks kills cache (v1.0.65+)

set -euo pipefail

source ./setup.sh

# 1. Create a hook configuration that returns dynamic additionalContext
mkdir -p .github/hooks
cat > .github/hooks/dynamic-context.sh << 'EOF'
#!/bin/bash
# Return dynamic context with a timestamp
echo "{\"additionalContext\": \"Current analysis timestamp: $(date +%H:%M:%S)\"}"
EOF
chmod +x .github/hooks/dynamic-context.sh

# Configure the hook in repo settings
cat > .github/copilot-hooks.json << 'EOF'
{
  "version": 1,
  "hooks": {
    "userPromptSubmitted": [
      { "type": "command", "bash": "./.github/hooks/dynamic-context.sh" }
    ]
  }
}
EOF

setup_otel "exp13-hook-impact"
PROMPT="Explain the importance of prefix stability for LLM caching."

# Call 1 — hook injects timestamp A
echo "Running Call 1 (hook timestamp A)..."
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2

# Call 2 — hook injects timestamp B (prefix changes!)
echo "Running Call 2 (hook timestamp B)..."
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp13: Dynamic hook context"

# Cleanup hooks for other experiments
rm -rf .github/hooks .github/copilot-hooks.json
