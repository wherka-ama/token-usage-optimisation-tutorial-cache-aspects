# How to Burn Money & Latency: A Guide to Breaking Prompt Caching

A hands-on experimental harness and tutorial exploring how prompting techniques, shared resources, and CLI tools impact **input token caching**.

## Core Components

| Component | Description |
|---|---|
| `tutorial-plan.md` | Deep dive into CLI capabilities, provider specifics, academic grounding, and 17 detailed experiments. |
| `setup.sh` | Environmental validation and OTel smoke test. |
| `analyze.py` | Extracts cache hit/miss analytics from OTel JSONL traces. |
| `compare.py` | Generates a multi-experiment comparison report with token cost estimates and best-practice gain/loss analysis. |
| `run-all.sh` | Executes the standard experiment suite (skipping high-latency tests). |
| `run-multi-model.sh` | Runs all experiments across multiple models; produces per-model and combined sky-view reports. |
| `discover-models.sh` | Probes Copilot CLI to discover which models are currently available. |
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
| | **Dynamic Tail** | `bash exp14-dynamic-tail-mitigation.sh` | Moving dynamic data to the end preserves the stable prefix. |
| | **RAG Ordering** | `bash exp15-rag-ordering.sh` | Relevance-order churn breaks reuse; stable IDs preserve it. |
| | **Schema Canonicalization** | `bash exp16-schema-canonicalization.sh` | Semantically identical JSON can miss cache if byte order changes. |
| **Growth** | **Instructions** | `bash exp4-custom-instructions.sh` | `AGENTS.md` adds stable, cached tokens. |
| | **MCP / Tools** | `bash exp5-mcp-impact.sh` | Tool definitions are stable and cached. |
| | **Skills** | `exp9-skills-impact.sh` | Large skill files increase cached density. |
| **Session** | **Multi-Turn** | `bash exp6-multi-turn.sh` | Appending preserves the prior prefix. |
| | **Tool Usage** | `exp10-tool-execution.sh` | Tool results become part of cached history. |
| **Benchmarks** | **Cross-Model** | `exp12-cross-model.sh` | Compare Claude vs GPT vs Gemini behavior. |
| | **Semantic Thresholds** | `python3 exp17-semantic-threshold-simulation.py` | Static semantic thresholds trade hit rate against false positives. |

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

6. Run all experiments with cost estimates and gain/loss analysis:
   ```bash
   bash run-all.sh
   # compare.py now outputs per-experiment token costs, per-model summary,
   # and best-practice gain/loss analysis grounded in actual benchmark data
   ```

7. Discover available Copilot models:
   ```bash
   bash discover-models.sh
   bash discover-models.sh --json   # JSON array output
   bash discover-models.sh --save models.txt
   ```

8. Run benchmarks across multiple models with sky-view comparison:
   ```bash
   bash run-multi-model.sh claude-sonnet-4.6 gpt-5.4 gemini-3.5-flash
   # or: bash run-multi-model.sh $(bash discover-models.sh)
   # Output: $HOME/cache-experiments/results/multi-model/sky-view-comparison.md
   ```

9. (Optional) Cross-check with `ccusage` via `npx`:
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
- `Est. Cost (USD)` — approximate cost based on per-token pricing (override with `--pricing`)
- `No-Cache Cost` — what the same tokens would cost with zero caching
- `Savings` — delta between actual cost and no-cache cost (the value of caching)

## Cost Estimation & Best-Practice Gain/Loss

`compare.py` now provides three analysis layers:

1. **Per-experiment token cost** — estimates USD cost per experiment using default or custom pricing, with a no-cache baseline for comparison.
2. **Per-model summary** — aggregates token usage and cost by model across all experiments.
3. **Best-practice gain/loss** — pairs anti-pattern experiments with their best-practice counterparts to show the estimated cost impact of each practice, grounded in actual benchmark data.

Custom pricing file format (per 1M tokens, USD):
```json
{"claude-sonnet-4.6": {"input": 3.0, "cached_read": 0.30, "cached_write": 3.75, "output": 15.0}}
```
```bash
python3 compare.py $HOME/cache-experiments/otel --pricing my-pricing.json
```

## Multi-Model Benchmarking

`run-multi-model.sh` runs the full experiment suite across multiple models sequentially and produces:

- **Per-model reports** — each model gets its own `report.md` with token usage, cost estimates, and gain/loss analysis.
- **Sky-view comparison** — a combined cross-model report showing hit rates, token counts, and cost estimates side by side, so you can verify whether caching assumptions hold across providers.

```bash
bash run-multi-model.sh claude-sonnet-4.6 gpt-5.4 gemini-3.5-flash
```

Output location: `$HOME/cache-experiments/results/multi-model/`

## Key Takeaways

- Caching is prefix-based and practically byte-for-byte exact for shared prefixes.
- Place stable content at the **beginning** of the prompt; dynamic content at the **end**.
- Tools, system instructions, MCP servers, retrieved context, and schemas can all become part of the cached prefix.
- Canonicalize ordering for tools, JSON schemas, and RAG chunks.
- Pin model versions; model switches invalidate cache.
- Keep calls within the cache TTL (5 min default for Anthropic; 5–10 min default for OpenAI).
- Append, don't modify, in multi-turn conversations.
- Treat semantic caching as an approximate optimization unless it has verification/error guarantees.

## Contributing

Contributions are welcome. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening an issue or pull request.

## Maintainers

- [`@wherka-ama`](https://github.com/wherka-ama)
- [`@micheliknechtel`](https://github.com/micheliknechtel)

## Governance & Release Process

- Code ownership: [`.github/CODEOWNERS`](.github/CODEOWNERS)
- Release process: [`RELEASING.md`](RELEASING.md)
- Changelog: [`CHANGELOG.md`](CHANGELOG.md)

## Security

This project uses the organization-level security policy:

- https://github.com/AmadeusITGroup/.github/blob/main/SECURITY.md

## License

Licensed under the [Apache License 2.0](LICENSE).

## Contact

For general repository topics, open a GitHub issue.
For security vulnerabilities, follow the organization security policy linked above.

## Sources

All sources are documented in `tutorial-plan.md` under **Part 2.6 Sources** and the academic research corpus under `research/`. Provider-specific TTL/pricing details are separated from academic claims in the tutorial plan.
