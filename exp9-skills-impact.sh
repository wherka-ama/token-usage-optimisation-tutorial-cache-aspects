#!/bin/bash
# exp9-skills-impact.sh — Show impact of skills on the prompt prefix

set -euo pipefail

source ./setup.sh

# Create a skill with substantial content
mkdir -p .github/skills/cache-testing
cat > .github/skills/cache-testing/SKILL.md << 'EOF'
# Cache Testing Skill
This skill provides specialized knowledge about prompt caching strategies.
## Key concepts
Prompt caching stores computed KV tensors from the attention mechanism's prefill step.
The cache is keyed on exact byte-for-byte prefix matching.
Any change to the prefix invalidates the cache from that point forward.
## Patterns to follow
1. Place stable content at the beginning of the prompt
2. Move dynamic content to the end
3. Pin model versions to avoid cache invalidation
4. Keep tool definitions identical across requests
5. Sort retrieved chunks deterministically
EOF

PROMPT="Explain how prompt caching works."

# Phase A: Without skill (disables all repo content)
setup_otel "exp9-no-skill"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp9A: No skill"

# Phase B: With skill loaded
setup_otel "exp9-with-skill"
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model "$COPILOT_MODEL" --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp9B: With skill"

# Cleanup
rm -rf .github/skills/cache-testing
