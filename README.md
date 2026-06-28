# How to Burn Money & Latency: A Guide to Breaking Prompt Caching

A hands-on experimental harness and tutorial exploring how prompting techniques, shared resources, and CLI tools impact **input token caching**.

## Core Components

| Component | Description |
|---|---|
| `tutorial-plan.md` | Deep dive into CLI capabilities, provider specifics, and 13 detailed experiments. |
| `setup.sh` | Environmental validation and OTel smoke test. |
| `analyze.py` | Extracts cache hit/miss analytics from OTel JSONL traces. |
| `compare.py` | Generates a multi-experiment comparison report. |
| `run-all.sh` | Executes the standard experiment suite (skipping high-latency tests). |
| `ccusage-session.sh` | Wrapper for `ccusage` to get rich session-level cost/token reports. |
| `presentation-outline.md` | Skeleton for a 20–25 min presentation (caching + routing). |
| `cache-best-practices.md` | Quickcard with side-by-side best/worst practice examples. |

## Experiment Suite & Patterns

| Category | Pattern | Command | Key Lesson |
|---|---|---|---|
| **Basics** | **Baseline** | `bash exp1-baseline.sh` | First call always creates the cache. |
| | **Cache Hit** | `bash exp2-cache-hit.sh` | Identical prompts = ~50% input savings. |
| | **TTL Expiry** | `bash exp11-ttl-expiry.sh` | Cache clears after ~5m of inactivity. |
| **Invalidation** | **Timestamp** | `bash exp3-timestamp-invalidation.sh` | Dynamic content at start kills the prefix. |
| | **Model Switch** | `bash exp7-model-switch.sh` | Different model = different cache namespace. |
| | **Effort Change** | `bash exp8-reasoning-effort.sh` | Reasoning changes can reset prefix compute. |
| | **Hook Context** | `bash exp13-hook-impact.sh` | Dynamic hook context (v1.0.65+) breaks prefix. |
| **Growth** | **Instructions** | `bash exp4-custom-instructions.sh` | `AGENTS.md` adds stable, cached tokens. |
| | **MCP / Tools** | `bash exp5-mcp-impact.sh` | Tool definitions are stable and cached. |
| | **Skills** | `exp9-skills-impact.sh` | Large skill files increase cached density. |
| **Session** | **Multi-Turn** | `bash exp6-multi-turn.sh` | Appending preserves the prior prefix. |
| | **Tool Usage** | `exp10-tool-execution.sh` | Tool results become part of cached history. |
| **Benchmarks** | **Cross-Model** | `exp12-cross-model.sh` | Compare Claude vs GPT vs Gemini behavior. |

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

### Experiment Isolation (Recommended)

By default, the harness enables **Experiment Isolation**. This ensures that your personal Copilot skills, custom instructions, and MCP configurations (stored in `~/.copilot`) do not bias the token usage results.

- **Enabled (Default):** Sets a temporary `COPILOT_HOME`, unsets `COPILOT_SKILLS_DIRS`, etc.
- **Toggle:** `export COPILOT_ISOLATION=false` before sourcing `setup.sh` to use your system config.

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
