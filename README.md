# Cache Invalidation Exercise — How NOT to Work with Your Context to Badly Affect Caching

A mini tutorial and experimental harness demonstrating how prompting techniques, shared resources (instructions, agents, skills), MCP servers, CLI tools, and other context-handling choices impact **input token caching**.

## Files

| File | Purpose |
|---|---|
| `tutorial-plan.md` | Full tutorial plan: CLI capabilities, research, patterns, antipatterns, 12 experiments, analytics |
| `setup.sh` | OTel setup, validation, and smoke test |
| `analyze.py` | Parse OTel JSONL and compute cache analytics per experiment |
| `compare.py` | Compare analytics across all experiments |
| `exp2-cache-hit.sh` | Example: repeated identical prompts → cache hit |
| `exp3-timestamp-invalidation.sh` | Example: dynamic timestamp in prefix → cache miss |
| `exp6-multi-turn.sh` | Example: multi-turn conversation, append-only → cache preserved |
| `exp13-hook-impact.sh` | Example: dynamic hook context (v1.0.65+) → cache miss |
| `run-all.sh` | Run the example experiments and print a comparison table |

## Quick Start

1. Install and authenticate the GitHub Copilot CLI:
   ```bash
   # https://docs.github.com/copilot/how-tos/copilot-cli
   copilot login
   ```

2. Run the setup and smoke test:
   ```bash
   source ./setup.sh
   ```
   This exports `COPILOT_OTEL_ENABLED=true`, `COPILOT_OTEL_EXPORTER_TYPE=file`, and `COPILOT_OTEL_FILE_EXPORTER_PATH`, then verifies that spans are written.

3. Run a single experiment:
   ```bash
   bash exp2-cache-hit.sh
   ```

4. Run the included experiments and compare:
   ```bash
   bash run-all.sh
   ```

5. Analyze a specific OTel JSONL file:
   ```bash
   python3 analyze.py "$HOME/cache-experiments/otel/exp2-cache-hit-*.jsonl"
   ```

6. (Optional) Cross-check with `ccusage` via `npx`:
   ```bash
   npx ccusage@latest copilot session
   npx ccusage@latest copilot session --json
   ```
   `ccusage` reads the file from `~/.copilot/otel/*.jsonl` or from the `COPILOT_OTEL_FILE_EXPORTER_PATH` set during the experiment.

## How to Read the Numbers

- `input_tokens` — total input tokens for the call (includes cached ones)
- `cache_read_input_tokens` / `cache_read` — tokens served from cache (cache HIT)
- `cache_creation_input_tokens` / `cache_creation` — tokens written to cache (cache WRITE)
- `overall_cache_hit_rate` — fraction of input tokens that were cache reads across all calls

## Key Takeaways

- Caching is prefix-based and byte-for-byte exact.
- Place stable content at the **beginning** of the prompt; dynamic content at the **end**.
- Tools, system instructions, and MCP servers are all part of the cached prefix.
- Pin model versions; model switches invalidate cache.
- Keep calls within the cache TTL (5 min default for Anthropic; 5–10 min default for OpenAI).
- Append, don't modify, in multi-turn conversations.

## Sources

All sources are documented in `tutorial-plan.md` under **Part 2.6 Sources**.
