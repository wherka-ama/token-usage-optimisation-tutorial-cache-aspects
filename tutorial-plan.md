# Cache Invalidation Exercise — How NOT to Work with Your Context to Badly Affect Caching

## A Mini Tutorial on the Impact of Prompting Techniques, Shared Resources, MCP, CLI Tools, and More on Input Token Caching

---

## Part 1: GitHub Copilot CLI — Scripted Mode Capabilities Map

### 1.1 Core Non-Interactive Execution

The Copilot CLI supports fully scripted, non-interactive execution via:

```bash
copilot -p "<prompt>" [options]
```

Key flags for scripted mode:

| Flag | Purpose |
|---|---|
| `-p, --prompt <text>` | Execute a prompt non-interactively; exits after completion |
| `--output-format json` | JSONL output (one JSON object per line) — essential for parsing telemetry |
| `-s, --silent` | Output only the agent response (no stats) — useful for clean scripting |
| `--model <model>` | Pin a specific model (e.g., `gpt-5.4`, `claude-sonnet-4.6`, `gemini-3.5-flash`) |
| `--session-id <id>` | Set a specific UUID for a new session or resume an existing one |
| `-r, --resume[=<value>]` | Resume a previous session by ID, name, or prefix |
| `--name <name>` | Name a new session for later resumption |
| `--no-custom-instructions` | Disable loading of custom instructions (AGENTS.md etc.) — isolates the system prompt |
| `--no-ask-user` | Disable the ask_user tool — agent works autonomously |
| `--yolo` / `--allow-all` | Enable all permissions (tools, paths, URLs) — no confirmation prompts |
| `--effort, --reasoning-effort <level>` | Set reasoning effort: `none`, `low`, `medium`, `high`, `xhigh`, `max` |
| `--share[=path]` | Share session to markdown file after completion |
| `--share-gist` | Share session to a secret GitHub gist |
| `--stream <mode>` | Enable or disable streaming (`on`/`off`) |

### 1.2 Telemetry — The Critical Piece for Data Capture

The CLI exports traces and metrics via **OpenTelemetry (OTel)** following the GenAI Semantic Conventions. This is how we capture token-level data from our experiments.

#### Activation (any one of these enables OTel):

```bash
COPILOT_OTEL_ENABLED=true
# OR
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
# OR
COPILOT_OTEL_FILE_EXPORTER_PATH=/path/to/output.jsonl
```

#### File-based exporter (best for our tutorial — offline, no collector needed):

```bash
export COPILOT_OTEL_ENABLED=true
export COPILOT_OTEL_EXPORTER_TYPE=file
mkdir -p "$HOME/.copilot/otel"
export COPILOT_OTEL_FILE_EXPORTER_PATH="$HOME/.copilot/otel/copilot-otel-$(date +%Y%m%d-%H%M%S).jsonl"
```

> **Critical:** These variables must be exported in the **same shell session** before the `copilot` process starts. OTel is initialized at CLI startup; it cannot be retroactively enabled for a running session. Sessions run without these variables produce no local usage data.

#### OTEL Preparation Checklist

Before running any experiment, verify each step:

1. **Enable OTel export**
   ```bash
   export COPILOT_OTEL_ENABLED=true
   export COPILOT_OTEL_EXPORTER_TYPE=file
   ```

2. **Create and point to a writable directory**
   ```bash
   mkdir -p "$HOME/.copilot/otel"
   export COPILOT_OTEL_FILE_EXPORTER_PATH="$HOME/.copilot/otel/copilot-otel-$(date +%Y%m%d-%H%M%S).jsonl"
   ```

3. **Confirm the environment variables are set**
   ```bash
   echo "COPILOT_OTEL_ENABLED=$COPILOT_OTEL_ENABLED"
   echo "COPILOT_OTEL_EXPORTER_TYPE=$COPILOT_OTEL_EXPORTER_TYPE"
   echo "COPILOT_OTEL_FILE_EXPORTER_PATH=$COPILOT_OTEL_FILE_EXPORTER_PATH"
   ```

4. **Run a quick smoke test and verify the file is populated**
   ```bash
   copilot -p "Say 'telemetry test'" --output-format json --silent --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
   wc -l "$COPILOT_OTEL_FILE_EXPORTER_PATH"
   head -n 5 "$COPILOT_OTEL_FILE_EXPORTER_PATH"
   ```
   You should see several JSONL lines with `"type":"span"` entries.

5. **Check for `chat` spans with token usage**
   ```bash
   grep '"gen_ai.operation.name":"chat"' "$COPILOT_OTEL_FILE_EXPORTER_PATH" | head -n 1
   ```
   Look for `gen_ai.usage.input_tokens`, `gen_ai.usage.cache_read_input_tokens`, and `gen_ai.usage.cache_creation_input_tokens`.

6. **For resumed sessions, set variables before `--resume`**
   ```bash
   export COPILOT_OTEL_ENABLED=true
   export COPILOT_OTEL_EXPORTER_TYPE=file
   export COPILOT_OTEL_FILE_EXPORTER_PATH="$HOME/.copilot/otel/copilot-otel-resumed.jsonl"
   copilot --resume=<session-id> ...
   ```
   Earlier activity from the original session is **not recovered** if it was started without OTel export.

#### Optional: Using `ccusage` with `npx` for richer reports

The custom `analyze.py` script in this tutorial is designed to work directly with the OTel JSONL output. However, you can also use **`ccusage`** for pre-built reports, cost calculations, and nicer formatting. The easiest way to run it is with `npx` (no install required):

```bash
# Show help for the Copilot data source
npx ccusage@latest copilot --help

# Session report (aggregates all sessions found in ~/.copilot/otel/)
npx ccusage@latest copilot session

# Daily report
npx ccusage@latest copilot daily

# Monthly report
npx ccusage@latest copilot monthly

# Machine-readable JSON output
npx ccusage@latest copilot session --json

# Narrow terminal layout
npx ccusage@latest copilot session --compact

# No network calls (use cached pricing data)
npx ccusage@latest copilot session --offline
```

##### How `ccusage` finds Copilot CLI data

`ccusage` reads Copilot OTel JSONL files from two locations:
1. `~/.copilot/otel/*.jsonl` (all files in this directory)
2. The explicit file pointed to by `COPILOT_OTEL_FILE_EXPORTER_PATH`

Because our experiments set a unique `COPILOT_OTEL_FILE_EXPORTER_PATH` per experiment, the file is automatically picked up. The default `~/.copilot/otel/` directory is also a fallback if you copy files there.

##### Using `ccusage` to sanity-check an experiment

After running any experiment, you can cross-check the custom `analyze.py` output with `ccusage`:

```bash
# 1. Run the experiment
bash exp2-cache-hit.sh

# 2. Verify the OTel file was captured
ls -l "$HOME/cache-experiments/otel/"

# 3. Run ccusage session report (picks up the file via COPILOT_OTEL_FILE_EXPORTER_PATH)
npx ccusage@latest copilot session

# 4. Compare with the custom analyzer output
python3 analyze.py "$HOME/cache-experiments/otel/exp2-cache-hit-*.jsonl"
```

`ccusage` reports token usage, cache read tokens, cache creation tokens, reasoning tokens, and cost estimates using LiteLLM pricing data. The custom `analyze.py` focuses specifically on cache hit/miss analytics per call and per model.

> **Note:** `ccusage` is experimental for Copilot CLI. If your model is not in LiteLLM's pricing database, cost will show as `$0.00`.

#### What gets exported (per the GenAI Semantic Conventions):

**Traces** — a hierarchical span tree:
```
invoke_agent                          # Agent orchestration (all LLM calls + tool executions)
  chat <model>                        # Individual LLM API call ← THIS IS WHERE TOKEN DATA LIVES
  execute_tool <tool>                 # Individual tool invocation
```

**Key span attributes for token analysis:**

| Attribute | Description |
|---|---|
| `gen_ai.operation.name` | `chat` for LLM calls |
| `gen_ai.request.model` | Requested model |
| `gen_ai.response.model` | Resolved model |
| `gen_ai.usage.input_tokens` | Total input tokens (includes cached) |
| `gen_ai.usage.output_tokens` | Output tokens |
| `gen_ai.usage.cache_read_input_tokens` | **Cache-read input tokens** (cache HIT) |
| `gen_ai.usage.cache_creation_input_tokens` | **Cache-creation input tokens** (cache WRITE) |
| `gen_ai.usage.reasoning.output_tokens` | Reasoning tokens (when available) |

> **Note:** Copilot CLI emits cache attributes with underscore format: `gen_ai.usage.cache_read_input_tokens` and `gen_ai.usage.cache_creation_input_tokens` (not the dot-separated `gen_ai.usage.cache_read.input_tokens` variant used by VS Code Copilot Chat).

**Metrics:**

| Metric | Type | Description |
|---|---|---|
| `gen_ai.client.operation.duration` | Histogram | LLM API call duration (seconds) |
| `gen_ai.client.token.usage` | Histogram | Token counts by type |
| `gen_ai.invoke_agent.duration` | Histogram | Agent invocation duration |
| `gen_ai.execute_tool.duration` | Histogram | Tool execution latency |

#### OTel Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| OTel JSONL file is empty or missing | Variables were set after `copilot` started, or not exported at all | Export `COPILOT_OTEL_ENABLED`, `COPILOT_OTEL_EXPORTER_TYPE`, and `COPILOT_OTEL_FILE_EXPORTER_PATH` before running `copilot` |
| OTel file has no `chat` spans | No LLM call was made, or the call failed before the LLM layer | Check CLI output for errors; ensure authentication is valid |
| No `cache_read_input_tokens` field | Cache was not hit (e.g., prompt too short, prefix changed, TTL expired) | This is expected on cache misses — review the experiment conditions |
| `cache_read_input_tokens` uses dot separator | You are looking at VS Code Copilot Chat output, not Copilot CLI output | Use the underscore variant: `gen_ai.usage.cache_read_input_tokens` |
| `ccusage` shows no data | File is not in `~/.copilot/otel/` and `COPILOT_OTEL_FILE_EXPORTER_PATH` is not set | Move the JSONL file to `~/.copilot/otel/` or set the env var before running `ccusage` |
| Resumed session has no earlier data | Original session was started without OTel export | Export variables before the *original* session; resumed sessions only capture activity from the resume point forward |
| OTel file is huge / contains sensitive data | `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true` is enabled | Disable content capture unless you need it; the file contains prompts and tool outputs |

#### Content capture (optional, for deeper analysis):

```bash
OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true
```

This captures full prompt/response content, system instructions, and tool definitions — useful for verifying what was actually sent to the model.

### 1.3 In-Session Token Visibility Commands

| Command | What it shows |
|---|---|
| `/usage` | Session AI credit usage + token breakdown (input, output, cached) |
| `/context` | Context-window token usage by largest consumers (system prompt, tools, messages) |
| `/model` | Per-model pricing (input, cached input, output token costs) |
| `/exit` | Exit summary with session usage |

### 1.4 Shared Resources That Affect the Prompt Prefix

These are the mechanisms that inject content into the prompt prefix — and thus affect caching:

| Resource | How it's loaded | Impact on cache |
|---|---|---|
| **Custom instructions** (`AGENTS.md`, `.github/copilot-instructions.md`) | Auto-loaded from repo root + `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | Injected into system prompt — part of cacheable prefix |
| **Skills** (`SKILL.md` files) | `.github/skills/`, `~/.copilot/skills/`, plugins, or `copilot skill add` | Injected as instructions — part of cacheable prefix. Manage via `copilot skill list/add/remove`. |
| **MCP servers** | `~/.copilot/mcp-config.json`, `.mcp.json` | Tool definitions injected into prefix — part of cacheable prefix |
| **Plugins** | Installed via `copilot plugin install` | Can bundle skills, agents, hooks, MCP servers, LSPs |
| **Agents/subagents** | Configured via `/subagents` | Subagent model selection; subagent invocations linked into same trace |
| **Hooks** | `.github/hooks/*.json`, config | Execute on events; `userPromptSubmitted` hook can inject `additionalContext` into the model-facing prompt — **directly affects prefix stability**. |

**Flags and Commands to control these for experiments:**

| Flag / Command | Effect |
|---|---|
| `--no-custom-instructions` | Disables AGENTS.md and related files — isolates system prompt |
| `copilot skill list/add/remove` | Manage skills explicitly (new in 1.0.65) |
| `--disable-builtin-mcps` | Disables all built-in MCP servers (currently: github-mcp-server) |
| `--disable-mcp-server <name>` | Disables a specific MCP server |
| `--excluded-tools[=tools...]` | Exclude specific tools from the model's view |
| `--available-tools[=tools...]` | Only include specified tools (disables all others) |
| `--disable-all-hooks` | Disable all repository and user-level hooks |

### 1.5 BYOK (Bring Your Own Key) — Direct Provider Access

For experiments requiring direct provider API access (to see raw cache token fields):

```bash
# OpenAI-compatible
COPILOT_PROVIDER_BASE_URL=https://api.openai.com/v1 \
COPILOT_PROVIDER_API_KEY=sk-... \
COPILOT_MODEL=gpt-5.4 \
COPILOT_PROVIDER_WIRE_API=responses \
copilot -p "..." --output-format json

# Anthropic
COPILOT_PROVIDER_TYPE=anthropic \
COPILOT_PROVIDER_BASE_URL=https://api.anthropic.com \
COPILOT_PROVIDER_API_KEY=sk-ant-... \
COPILOT_MODEL=claude-sonnet-4-6 \
copilot -p "..." --output-format json
```

### 1.6 Available Models (from config)

- **Claude:** `claude-sonnet-4.6`, `claude-sonnet-4.5`, `claude-haiku-4.5`, `claude-fable-5`, `claude-opus-4.8`, `claude-opus-4.7`, `claude-opus-4.6`, `claude-opus-4.6-fast`, `claude-opus-4.5`
- **GPT:** `gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex`, `gpt-5.4-mini`, `gpt-5-mini`
- **Gemini:** `gemini-3.1-pro-preview`, `gemini-3.5-flash`

---

## Part 2: Research — Patterns, Antipatterns, and Provider Guidance

### 2.1 How Prompt Caching Works (Fundamentals)

Prompt caching stores the **computed key/value (KV) tensors** — the intermediate representation from the model's attention layers produced during prefill — so they can be reused on later requests with the same prefix. Mechanistically, this is tensor reuse rather than response replay; it should not be confused with provider data-retention guarantees.

In practical provider and serving-system implementations, reuse depends on a **stable serialized/tokenized prefix**. Treat it as byte-for-byte exact in your prompt assembly code: any change to the prefix — even a single character, reordered JSON key, or shuffled retrieved chunk — can invalidate the cache from that point forward.

**The cache hierarchy (Anthropic):** `tools → system → messages`. Changes at each level invalidate that level and all subsequent levels.

**The cache key (OpenAI):** A hash of the initial prefix (typically first 256 tokens). The `prompt_cache_key` parameter can be combined with the prefix hash to influence routing.

### 2.2 Provider-Specific Details

#### OpenAI

- **Automatic caching** — no code changes needed; enabled for all models gpt-4o and newer
- **Minimum cacheable prompt:** 1,024 tokens
- **Cache routing:** Based on hash of initial prefix (~256 tokens); `prompt_cache_key` parameter improves routing stickiness
- **Cache retention:** In-memory (5–10 min default) or Extended (up to 24h for gpt-5.5+)
- **Cost savings:** Up to 90% on cached input tokens, up to 80% latency reduction
- **Overflow:** >15 req/min for same prefix+key combination may overflow to additional machines
- **Best practices (from OpenAI docs):**
  - Structure prompts with static content at the beginning, dynamic content at the end
  - Use `prompt_cache_key` consistently across requests sharing common prefixes
  - Monitor cache hit rates, latency, and proportion of tokens cached
  - Maintain steady stream of requests with identical prefixes
  - Tools and schemas are part of the cached prefix — keep them identical
  - Use `allowed_tools` in `tool_choice` to restrict tools per-call without changing the `tools` array
  - Move timestamps/debug metadata to the `metadata` field, not the prompt

#### Anthropic Claude

- **Both automatic and explicit caching** supported
- **Automatic caching:** Handles breakpoint management automatically for multi-turn conversations
- **Explicit caching:** `cache_control: { type: "ephemeral" }` markers on message blocks; up to 4 breakpoints
- **Minimum cacheable prompt:** Varies by model (512–4,096 tokens; e.g., 1,024 for Sonnet 4.5/4.6, 4,096 for Haiku 4.5)
- **TTL:** 5 minutes default; 1-hour option available at higher cost
- **Cache isolation:** Per workspace (since Feb 2026) on Claude API; per organization on Bedrock/GCP
- **Cache invalidation hierarchy:** `tools → system → messages`
- **What invalidates the cache:**
  - Any change to tools (definitions, ordering, schema keys)
  - Any change to system prompt
  - Any change to messages before the cache breakpoint
  - Changes to `tool_choice` or presence/absence of images
  - Non-deterministic JSON key ordering (Swift, Go randomize key order)
- **Cache diagnostics (beta):** Pass `diagnostics.previous_message_id` to compare consecutive requests and get exact divergence point
- **Best practices (from Anthropic docs):**
  - Start with automatic caching for multi-turn conversations
  - Use explicit breakpoints when different sections change at different frequencies
  - Cache stable, reusable content (system instructions, large contexts, tool definitions)
  - Place cached content at the prompt's beginning
  - Place breakpoint on the last block that stays identical across requests
  - On Claude Opus 4.8, append `{role: system}` messages instead of editing top-level system field
  - Regularly analyze cache hit rates

#### Google Gemini

- **Implicit caching:** Automatic, enabled by default on Gemini 2.5+; 90% discount on cached tokens
- **Explicit caching:** `cachedContents.create` API; reference by name in subsequent requests
- **Minimum cacheable tokens:** 2,048 (Gemini 2.5 Pro/Flash), 4,096 (Gemini 3.x)
- **TTL:** Default 1 hour; no maximum; minimum 1 minute
- **To increase implicit cache hit:** Put large/common content at the beginning; send requests with similar prefix in short time window
- **Cached content is a prefix to the prompt** — same prefix-matching rules apply

### 2.3 Patterns (Best Practices)

1. **Stable prefix first, mutable content last**
   - Layout: `system message → few-shot examples → tool definitions → retrieved context → conversation history → current user query`
   - The first three regions form the cacheable prefix

2. **Pin the model version**
   - Caches are scoped per model version; a model upgrade resets hit rate to zero
   - Pin exact version (e.g., `claude-sonnet-4-6`) not floating alias (`claude-sonnet`)

3. **Keep tools and schemas identical across requests**
   - Tool definitions, schema keys, and ordering are part of the cached prefix
   - Use `allowed_tools` / `tool_choice` to restrict per-call without changing the `tools` array

4. **Sort retrieved chunks deterministically**
   - Sort by stable key (chunk ID, document timestamp, alphabetical) — NOT by relevance score
   - Relevance order changes between similar queries and breaks the prefix

5. **Move dynamic content to the end or to metadata**
   - Timestamps, session IDs, user IDs → user message or API `metadata` field
   - Never embed "Today is YYYY-MM-DD" in the system prompt

6. **Append, don't modify**
   - In multi-turn conversations, append new messages rather than editing earlier ones
   - The Codex agent loop follows this: system instructions, tool definitions, sandbox config kept identical and consistently ordered

7. **Use explicit cache control where available**
   - Anthropic: `cache_control: { type: "ephemeral" }` on stable blocks
   - Gemini: `cachedContents.create` for very long stable contexts
   - OpenAI: automatic, but layout is the only lever

8. **Keep requests within cache TTL**
   - Anthropic: 5 min default (1 hour option)
   - OpenAI: 5–10 min (24h extended for gpt-5.5+)
   - Gemini: 1 hour default

9. **Pre-warm the cache**
   - Send an initial request to populate the cache before the real workload
   - Anthropic supports explicit pre-warming

10. **Monitor cache hit rate as a first-class metric**
    - Track per endpoint, per prompt version, per model version
    - Alert on sustained drops — usually faster than the cost dashboard

11. **Temperature/top_p/top_k do NOT affect caching**
    - These parameters affect the final token selection step, after attention has produced embeddings
    - Change them freely without worrying about cache invalidation

### 2.4 Antipatterns (What NOT to Do)

1. **Timestamp/date at the start of the prompt**
   - `"Today is November 5, 2026"` in the system prompt → invalidates every day at midnight
   - **Fix:** Move to user message or API metadata

2. **User-specific metadata in the system prompt**
   - `"You are a helpful assistant for {user_name}"` → invalidates per user, eliminates cross-user cache hits
   - **Fix:** Move to user message

3. **Non-deterministic JSON key ordering**
   - Some languages (Swift, Go) randomize key order during JSON conversion
   - Two structurally identical prompts serialize to different bytes
   - **Fix:** Use `sort_keys=True` in serialization; canonicalize before fingerprinting

4. **Floating tool list / tool reordering**
   - Building tool list from dict iteration that doesn't preserve order
   - **Fix:** Sort tools deterministically; use `allowed_tools` to restrict per-call

5. **RAG chunks sorted by relevance score**
   - Relevance order changes between similar queries → breaks prefix on every call
   - **Fix:** Sort by chunk ID, document timestamp, or alphabetical

6. **Dynamic content injected before static content**
   - `[system prompt] + [RAG chunks] + [conversation history] + [user message]`
   - If RAG chunks differ, cache never gets a stable prefix long enough to activate
   - **Fix:** Relocate dynamic content to the tail, after cache breakpoints

7. **Editing the system prompt in production without a version bump**
   - Old cached prefixes go stale on the next call
   - **Fix:** Version your system prompts; track hit rate before/after changes

8. **Using a floating model alias**
   - Cache resets silently when the provider rolls forward
   - **Fix:** Pin exact model version

9. **Trailing whitespace changes**
   - Adding or removing a trailing newline invalidates the cache
   - **Fix:** Normalize whitespace in prompt assembly

10. **Request IDs / session IDs / counters in the cacheable prefix**
    - `"Request #42"` or session metadata before the breakpoint
    - **Fix:** Move to metadata or after the breakpoint

11. **Naive truncation from hitting context window limits**
    - Truncating from the front of the prompt removes the cached prefix
    - **Fix:** Truncate from the end; use sliding window for conversation history

12. **Changes to reasoning effort mid-conversation**
    - Changing `--reasoning-effort` between turns can invalidate cache
    - **Fix:** Keep reasoning effort consistent across turns

13. **Parallel execution on not-yet-warmed-up prefix**
    - Cache entry only becomes available after the first response begins
    - **Fix:** Wait for first response before sending parallel requests

14. **Cache doesn't survive to next request (TTL expiry or eviction)**
    - Too much time between calls, or KV cache memory pressure
    - **Fix:** Keep calls within TTL; pre-warm; reduce number of unique prefixes

15. **Including `stream` parameter in cache fingerprint**
    - Streaming vs non-streaming doesn't change model output but splits cache if fingerprinted
    - **Fix:** Exclude `stream` from fingerprint; use consistent streaming mode

16. **Dynamic context from `userPromptSubmitted` hooks (v1.0.65+)**
    - Hooks returning `additionalContext` containing timestamps, random IDs, or changing directory paths.
    - **Fix:** Ensure `additionalContext` is stable across requests, or move dynamic parts to the end of the context.

### 2.5 Diagnostic Tools

| Tool | Provider | What it does |
|---|---|---|
| **Cache diagnostics (beta)** | Anthropic | Pass `diagnostics.previous_message_id` → API reports exact divergence point (model/system/tools/messages changed) |
| **`usage.cache_read_input_tokens`** | Anthropic | Response field showing cache hit count |
| **`usage.cache_creation_input_tokens`** | Anthropic | Response field showing cache write count |
| **`cached_tokens` in usage** | OpenAI | Response field showing cached token count |
| **`cachedContentTokenCount`** | Gemini | Response metadata showing cached token count |
| **cachelens** | Multi-provider (offline) | Static analysis: first-divergence diff, lint for antipatterns, CI gate |
| **ccusage** | Copilot CLI | Reads OTel JSONL files; reports token usage, cache tokens, costs |
| **Prompt cache fingerprinting** | Application-level | Hash prefix bytes; log hash with every request; diff when hits should occur but don't |

### 2.6 Sources

**Academic grounding (from `research/`):**
- KV/prefix mechanics: Luo et al. KV cache survey (`research/chapters/ch03-kv-cache-mechanisms.md`), PagedAttention, SGLang/RadixAttention, LMCache.
- Prompt caching for agentic workloads: `Don't Break the Cache` (`arXiv:2601.06007`), summarized in `research/chapters/ch04-prompt-and-prefix-caching.md`.
- Agentic workflow caching: Agentic Plan Caching, CacheTTL, KVFlow, Pythia, PBKV, CacheRL, summarized in `research/chapters/ch06-harness-and-tooling-caching.md` and `research/chapters/ch08-agentic-behaviour.md`.
- Semantic caching correctness: vCache, MeanCache, Krites, temporal semantic caching, summarized in `research/chapters/ch05-semantic-caching.md`.
- Cache-preserving routing: HyDRA plus RouteLLM/OmniRouter/Cascade Routing context, summarized in `research/chapters/ch11-model-routing-and-caching.md`.
- Reliability/security caveats: numerical nondeterminism, batch-invariant kernels, LLM-42, PROMPTPEEK, KV-Cloak, KV-Shield, summarized in `research/chapters/ch02-reliability-and-reproducibility.md` and `research/chapters/ch10-security-and-privacy.md`.

**Provider documentation (primary):**
- OpenAI Prompt Caching: https://developers.openai.com/api/docs/guides/prompt-caching
- OpenAI Prompt Caching 201 (Cookbook): https://developers.openai.com/cookbook/examples/prompt_caching_201
- Anthropic Prompt Caching: https://platform.claude.com/docs/en/build-with-claude/prompt-caching
- Anthropic Cache Diagnostics: https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics
- Google Gemini Context Caching: https://ai.google.dev/gemini-api/docs/generate-content/caching
- Google Vertex AI Context Cache: https://cloud.google.com/vertex-ai/generative-ai/docs/context-cache/context-cache-overview
- Azure OpenAI Prompt Caching: https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/prompt-caching

**GitHub Copilot CLI:**
- Copilot CLI docs: https://docs.github.com/copilot/how-tos/copilot-cli
- Copilot CLI billing: https://docs.github.com/en/copilot/concepts/billing
- VS Code Copilot monitoring: https://code.visualstudio.com/docs/copilot/guides/monitoring-agents
- Copilot SDK observability: https://github.com/github/copilot-sdk/blob/main/docs/observability/opentelemetry.md
- ccusage Copilot guide: https://ccusage.com/guide/copilot/
- Copilot CLI token usage issue: https://github.com/github/copilot-cli/issues/1152
- GitHub blog on token efficiency: https://github.blog/ai-and-ml/github-copilot/improving-token-efficiency-in-github-agentic-workflows/

**Community / analysis (verified):**
- ngrok — Prompt caching deep dive: https://ngrok.com/blog/prompt-caching
- llmbestpractices — Prompt caching strategies: https://llmbestpractices.com/prompt-engineering/prompt-caching-strategies
- DEV Community — Prompt assembly antipatterns: https://dev.to/parag_d/prompt-caching-works-your-prompt-assembly-code-does-not-5edc
- Prism — Cache fingerprinting pitfalls: https://ssimplifi.com/blog/prompt-cache-fingerprinting-pitfalls
- cachelens (offline checker): https://github.com/hinanohart/cachelens
- AWS — LLM caching strategies: https://aws.amazon.com/blogs/database/optimize-llm-response-costs-and-latency-with-effective-caching/
- Adaline — LLM cost optimization: https://www.adaline.ai/blog/llm-cost-optimization-token-efficiency-caching-prompt-design
- OneUptime — LLM caching strategies: https://oneuptime.com/blog/post/2026-01-30-llm-caching-strategies/view
- speedtesthq — How prompt caching works: https://speedtesthq.com/guides/ai/prompt-caching-how-it-works
- OpenTelemetry GenAI semantic conventions: https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-spans.md

---

## Part 3: Tutorial Plan

### 3.1 Tutorial Structure

**Title:** Cache Invalidation Exercise — How NOT to Work with Your Context to Badly Affect Caching

**Duration:** ~45–60 minutes

**Audience:** Developers using AI coding assistants (Copilot CLI, Claude CLI, etc.) who want to understand and optimize token caching

**Learning objectives:**
1. Understand what input token caching is and why it matters (cost, latency)
2. See real token-level data showing cache hits vs misses
3. Learn the patterns that maximize cache hits
4. Recognize the antipatterns that kill cache hit rates
5. Know how to measure and diagnose cache performance

### 3.2 Prerequisites

1. **Install Copilot CLI**
   ```bash
   # (follow https://docs.github.com/copilot/how-tos/copilot-cli)
   ```

2. **Authenticate**
   ```bash
   copilot login
   # Verify
   copilot --version
   ```

3. **Run the OTel setup and smoke test**
   ```bash
   source setup.sh
   ```
   This script exports the required OTel variables, validates them, and runs a smoke test that makes a tiny LLM call and verifies the JSONL file is populated with spans. **Do not run any experiment until the smoke test passes.**

4. **(Optional) Install ccusage**
   ```bash
   npx ccusage@latest copilot --help
   ```
   Useful for alternative reports and cost calculations.

### 3.3 Experiment Setup

#### Environment preparation script:

```bash
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
```

#### Analytics script (extracts token data from OTel JSONL):

```bash
#!/bin/bash
# analyze.sh — Extract and compute cache analytics from OTel JSONL files
# Usage: ./analyze.sh <otel-jsonl-file>

#!/usr/bin/env python3
"""analyze.py — Parse Copilot CLI OTel JSONL and compute cache analytics."""

import json
import sys
import os


def parse_otel_jsonl(filepath: str) -> list[dict]:
    """Parse OTel JSONL file and extract chat span token data."""
    if not os.path.exists(filepath):
        raise FileNotFoundError(
            f"OTel file not found: {filepath}\n"
            "Did you set COPILOT_OTEL_ENABLED=true, COPILOT_OTEL_EXPORTER_TYPE=file, "
            "and COPILOT_OTEL_FILE_EXPORTER_PATH before running copilot?"
        )

    spans = []
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            # Only interested in span entries (not metrics)
            if entry.get("type") != "span":
                continue

            attrs = entry.get("attributes", {})
            op_name = attrs.get("gen_ai.operation.name", "")

            # We want chat spans (LLM API calls)
            if op_name != "chat":
                continue

            span_data = {
                "span_name": entry.get("name", ""),
                "trace_id": entry.get("traceId", ""),
                "span_id": entry.get("spanId", ""),
                "parent_span_id": entry.get("parentSpanId", ""),
                "start_time": entry.get("startTime", ""),
                "end_time": entry.get("endTime", ""),
                "model": attrs.get("gen_ai.request.model", attrs.get("gen_ai.response.model", "unknown")),
                "input_tokens": attrs.get("gen_ai.usage.input_tokens", 0),
                "output_tokens": attrs.get("gen_ai.usage.output_tokens", 0),
                "cache_read_tokens": attrs.get("gen_ai.usage.cache_read_input_tokens", 0),
                "cache_creation_tokens": attrs.get("gen_ai.usage.cache_creation_input_tokens", 0),
                # Fallback: dot-separated variants (VS Code format)
                "cache_read_tokens_alt": attrs.get("gen_ai.usage.cache_read.input_tokens", 0),
                "cache_creation_tokens_alt": attrs.get("gen_ai.usage.cache_creation.input_tokens", 0),
            }
            # Use whichever variant is non-zero
            span_data["cache_read"] = span_data["cache_read_tokens"] or span_data["cache_read_tokens_alt"]
            span_data["cache_creation"] = span_data["cache_creation_tokens"] or span_data["cache_creation_tokens_alt"]

            # Compute derived metrics
            span_data["total_input"] = span_data["input_tokens"]
            span_data["uncached_input"] = span_data["input_tokens"] - span_data["cache_read"]
            span_data["cache_hit_rate"] = (
                span_data["cache_read"] / span_data["input_tokens"]
                if span_data["input_tokens"] > 0
                else 0.0
            )
            spans.append(span_data)

    if not spans:
        raise ValueError(
            f"No chat spans found in {filepath}.\n"
            "Possible causes:\n"
            "  - OTel was not enabled before copilot started\n"
            "  - No LLM call was made\n"
            "  - The call failed before reaching the LLM layer\n"
            "  - The cache attributes use the dot-separated variant (VS Code) instead of underscore (Copilot CLI)"
        )

    return spans


def compute_analytics(spans: list[dict]) -> dict:
    """Compute aggregate analytics from chat spans."""
    if not spans:
        return {"error": "No chat spans found"}

    total_input = sum(s["input_tokens"] for s in spans)
    total_output = sum(s["output_tokens"] for s in spans)
    total_cache_read = sum(s["cache_read"] for s in spans)
    total_cache_creation = sum(s["cache_creation"] for s in spans)
    total_uncached = sum(s["uncached_input"] for s in spans)

    # Per-model breakdown
    by_model = {}
    for s in spans:
        model = s["model"]
        if model not in by_model:
            by_model[model] = {
                "calls": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cache_read": 0,
                "cache_creation": 0,
            }
        by_model[model]["calls"] += 1
        by_model[model]["input_tokens"] += s["input_tokens"]
        by_model[model]["output_tokens"] += s["output_tokens"]
        by_model[model]["cache_read"] += s["cache_read"]
        by_model[model]["cache_creation"] += s["cache_creation"]

    for model, data in by_model.items():
        data["cache_hit_rate"] = (
            data["cache_read"] / data["input_tokens"]
            if data["input_tokens"] > 0
            else 0.0
        )
        data["uncached_input"] = data["input_tokens"] - data["cache_read"]

    return {
        "total_llm_calls": len(spans),
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_cache_read_tokens": total_cache_read,
        "total_cache_creation_tokens": total_cache_creation,
        "total_uncached_input_tokens": total_uncached,
        "overall_cache_hit_rate": total_cache_read / total_input if total_input > 0 else 0.0,
        "by_model": by_model,
        "per_call": spans,
    }


def print_report(analytics: dict, label: str = ""):
    """Print a human-readable analytics report."""
    print(f"\n{'=' * 70}")
    print(f"  CACHE ANALYTICS REPORT{' — ' + label if label else ''}")
    print(f"{'=' * 70}")
    print(f"  Total LLM calls:          {analytics['total_llm_calls']}")
    print(f"  Total input tokens:       {analytics['total_input_tokens']:,}")
    print(f"  Total output tokens:      {analytics['total_output_tokens']:,}")
    print(f"  Cache READ tokens:        {analytics['total_cache_read_tokens']:,}")
    print(f"  Cache CREATION tokens:    {analytics['total_cache_creation_tokens']:,}")
    print(f"  Uncached input tokens:    {analytics['total_uncached_input_tokens']:,}")
    print(f"  Overall cache hit rate:   {analytics['overall_cache_hit_rate']:.1%}")
    print(f"{'-' * 70}")
    print(f"  Per-model breakdown:")
    for model, data in analytics["by_model"].items():
        print(f"    {model}:")
        print(f"      Calls:              {data['calls']}")
        print(f"      Input tokens:       {data['input_tokens']:,}")
        print(f"      Cache read:         {data['cache_read']:,}")
        print(f"      Cache creation:     {data['cache_creation']:,}")
        print(f"      Cache hit rate:     {data['cache_hit_rate']:.1%}")
        print(f"      Uncached input:     {data['uncached_input']:,}")
    print(f"{'-' * 70}")
    print(f"  Per-call detail:")
    for i, s in enumerate(analytics["per_call"], 1):
        print(f"    Call {i}: model={s['model']}, "
              f"in={s['input_tokens']:,}, "
              f"cache_read={s['cache_read']:,}, "
              f"cache_create={s['cache_creation']:,}, "
              f"hit_rate={s['cache_hit_rate']:.1%}")
    print(f"{'=' * 70}\n")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze.py <otel-jsonl-file> [label]")
        sys.exit(1)

    filepath = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        spans = parse_otel_jsonl(filepath)
        analytics = compute_analytics(spans)
        print_report(analytics, label)

        # Also save JSON output
        json_output = filepath.replace(".jsonl", "-analytics.json")
        with open(json_output, "w") as f:
            json.dump(analytics, f, indent=2)
        print(f"JSON analytics saved to: {json_output}")
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
```

### 3.4 Experiments

Each experiment follows this pattern:
1. Set up OTel file for this experiment
2. Run scripted Copilot CLI commands
3. Parse the OTel JSONL with `analyze.py`
4. Compare results across experiments

---

#### Experiment 1: Baseline — Single Prompt, No Cache Reuse

**Goal:** Establish baseline token usage with a single non-interactive call.

**Script:**
```bash
#!/bin/bash
# exp1-baseline.sh
source ./setup.sh
setup_otel "exp1-baseline"

# Single call — no prior cache to hit
copilot -p "Explain the concept of eventual consistency in distributed systems in 3 paragraphs." \
  --model claude-sonnet-4.6 \
  --output-format json \
  --silent \
  --no-custom-instructions \
  --disable-builtin-mcps \
  --yolo 2>/dev/null

echo "OTel file: $COPILOT_OTEL_FILE_EXPORTER_PATH"
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp1: Baseline single call"
```

**Expected result:** `cache_read = 0`, `cache_creation > 0` (first call writes cache), `cache_hit_rate = 0%`

**Teaching point:** The first call always creates the cache. Cache reads only happen on subsequent calls with matching prefixes.

---

#### Experiment 2: Cache Hit — Repeated Identical Prompts

**Goal:** Show cache hits when the same prompt is sent twice in quick succession.

**Script:**
```bash
#!/bin/bash
# exp2-cache-hit.sh
source ./setup.sh
setup_otel "exp2-cache-hit"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# First call — creates cache
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Second call — should hit cache (same prefix, within TTL)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp2: Repeated identical prompts"
```

**Expected result:** Call 1: `cache_read=0, cache_creation>0`. Call 2: `cache_read>0, cache_creation=0`. Overall hit rate ~50% on input tokens.

**Teaching point:** Identical prompts sent within the cache TTL get cache hits. The prefix must be byte-for-byte identical.

---

#### Experiment 3: Cache Invalidation — Timestamp in System Context

**Goal:** Demonstrate how a dynamic timestamp at the start of the prompt kills caching.

**Script:**
```bash
#!/bin/bash
# exp3-timestamp-invalidation.sh
source ./setup.sh
setup_otel "exp3-timestamp"

# We simulate a "today is" injection by using different prompts that differ only at the start
# In a real scenario, custom instructions or system prompts with timestamps cause this

# Call 1 — with timestamp A
copilot -p "Current time context: $(date -u +%H:%M:%S). Explain eventual consistency in distributed systems in 3 paragraphs." \
  --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2  # Small delay to ensure timestamp changes

# Call 2 — with timestamp B (different prefix!)
copilot -p "Current time context: $(date -u +%H:%M:%S). Explain eventual consistency in distributed systems in 3 paragraphs." \
  --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp3: Timestamp invalidation"
```

**Expected result:** Both calls: `cache_read=0`. The timestamp at the start changes the prefix, so no cache hits.

**Teaching point:** Dynamic content at the start of the prompt (timestamps, session IDs, user names) invalidates the entire cache. Move dynamic content to the end.

---

#### Experiment 4: Custom Instructions Impact — With vs Without

**Goal:** Show how loading custom instructions (AGENTS.md) changes the system prompt prefix and affects caching.

**Script:**
```bash
#!/bin/bash
# exp4-custom-instructions.sh
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
... (repeat to generate ~2000+ tokens of stable instructions)
EOF

# Phase A: WITHOUT custom instructions
setup_otel "exp4-no-instructions"
PROMPT="Explain the builder pattern in software design."
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp4A: No custom instructions"

# Phase B: WITH custom instructions (same user prompt)
setup_otel "exp4-with-instructions"
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp4B: With custom instructions"
```

**Expected result:**
- Phase A: Smaller input tokens, cache hits on second call (same minimal system prompt)
- Phase B: Larger input tokens (instructions loaded), cache hits on second call (instructions are stable → cached)

**Teaching point:** Custom instructions increase the prefix size but are stable → they get cached. The key is that they don't change between calls. If they DID change (e.g., dynamic date in instructions), the cache would break.

---

#### Experiment 5: MCP Server Impact — Tool Definitions in Prefix

**Goal:** Show how MCP server tool definitions inflate the prefix and affect caching.

**Script:**
```bash
#!/bin/bash
# exp5-mcp-impact.sh
source ./setup.sh

PROMPT="What files are in the current directory?"

# Phase A: Without MCP (disabled)
setup_otel "exp5-no-mcp"
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp5A: No MCP"

# Phase B: With built-in MCP (github-mcp-server enabled)
setup_otel "exp5-with-mcp"
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp5B: With MCP"
```

**Expected result:**
- Phase A: Smaller prefix (no tool definitions), cache hits on second call
- Phase B: Larger prefix (MCP tool definitions injected), cache hits on second call IF tools are stable

**Teaching point:** MCP tool definitions are part of the cacheable prefix. They increase input tokens but are stable → cacheable. If tool definitions change between calls (e.g., dynamic tool list), cache breaks.

---

#### Experiment 6: Multi-Turn Conversation — Append vs Modify

**Goal:** Show that appending messages preserves cache while modifying earlier messages breaks it.

**Script:**
```bash
#!/bin/bash
# exp6-multi-turn.sh
source ./setup.sh
setup_otel "exp6-multi-turn"

# Use --resume to continue a session (simulates multi-turn)
# First turn
SESSION_ID=$(uuidgen)
copilot -p "Explain the CAP theorem." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Second turn — appends to conversation (should hit cache on prior context)
copilot -p "Now explain how it relates to eventual consistency." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Third turn — continues appending
copilot -p "Give me a real-world example of each combination." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp6: Multi-turn append"
```

**Expected result:**
- Turn 1: `cache_read=0, cache_creation>0` (initial cache write)
- Turn 2: `cache_read>0` (prior context cached), new tokens for new message
- Turn 3: `cache_read>0` (larger cached prefix), new tokens for new message

**Teaching point:** Multi-turn conversations naturally benefit from caching when messages are appended. The growing conversation history is cached up to the last breakpoint. Modifying or rewriting earlier messages would break the cache.

---

#### Experiment 7: Model Switching — Cache Invalidation

**Goal:** Show that switching models mid-session invalidates the cache.

**Script:**
```bash
#!/bin/bash
# exp7-model-switch.sh
source ./setup.sh
setup_otel "exp7-model-switch"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Call 1 — Claude
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 2 — Same prompt, same model (should cache hit)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 3 — Same prompt, DIFFERENT model (cache miss — different model = different cache)
copilot -p "$PROMPT" --model gpt-5.4 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 4 — Same prompt, back to Claude (may or may not hit — depends on TTL)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp7: Model switching"
```

**Expected result:**
- Call 1: `cache_read=0` (first call)
- Call 2: `cache_read>0` (cache hit, same model)
- Call 3: `cache_read=0` (different model = different cache namespace)
- Call 4: `cache_read>0` (back to original model, cache still valid if within TTL)

**Teaching point:** Caches are scoped per model version. Switching models invalidates the cache. Pin your model for consistent caching.

---

#### Experiment 8: Reasoning Effort Changes

**Goal:** Show that changing reasoning effort between calls can affect caching.

**Script:**
```bash
#!/bin/bash
# exp8-reasoning-effort.sh
source ./setup.sh
setup_otel "exp8-reasoning-effort"

PROMPT="Analyze the trade-offs between strong and eventual consistency in a distributed database."

# Call 1 — low effort
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort low 2>/dev/null

# Call 2 — same prompt, same effort (should cache hit)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort low 2>/dev/null

# Call 3 — same prompt, DIFFERENT effort
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --effort high 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp8: Reasoning effort changes"
```

**Expected result:**
- Call 1: `cache_read=0` (first call)
- Call 2: `cache_read>0` (cache hit)
- Call 3: `cache_read=0` or reduced (effort change may invalidate cache)

**Teaching point:** Changes to reasoning effort can invalidate the cache. Keep reasoning effort consistent across turns in a conversation.

---

#### Experiment 9: Skills Impact — Loading a Skill

**Goal:** Show how loading a skill injects instructions into the prefix and affects caching.

**Script:**
```bash
#!/bin/bash
# exp9-skills-impact.sh
source ./setup.sh

# Create a skill with substantial content
mkdir -p .github/skills/cache-testing
cat > .github/skills/cache-testing/SKILL.md << 'EOF'
# Cache Testing Skill

This skill provides specialized knowledge about prompt caching strategies.

## When to use this skill
Use this skill when analyzing or optimizing prompt caching behavior in LLM applications.

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

## Antipatterns to avoid
1. Timestamps in system prompts
2. User-specific metadata in cached prefix
3. Non-deterministic JSON key ordering
4. Floating tool lists
5. RAG chunks sorted by relevance score
... (repeat to generate ~1000+ tokens)
EOF

PROMPT="Explain how prompt caching works."

# Phase A: Without skill (no-custom-instructions also disables skills)
setup_otel "exp9-no-skill"
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp9A: No skill"

# Phase B: With skill loaded
setup_otel "exp9-with-skill"
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --disable-builtin-mcps --yolo 2>/dev/null
python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp9B: With skill"
```

**Expected result:**
- Phase A: Smaller prefix, cache hits on second call
- Phase B: Larger prefix (skill content injected), cache hits on second call (skill content is stable)

**Teaching point:** Skills inject stable content into the prefix. This increases input tokens but is cacheable. The danger is if skill content is dynamic or if skills are loaded/unloaded between calls.

---

#### Experiment 10: Tool Execution Impact — Calling CLI Tools

**Goal:** Show how tool execution adds tool results to the context, growing the prefix and affecting caching in subsequent turns.

**Script:**
```bash
#!/bin/bash
# exp10-tool-execution.sh
source ./setup.sh
setup_otel "exp10-tool-execution"

SESSION_ID=$(uuidgen)

# Turn 1 — simple question, no tools needed
copilot -p "What is the capital of France?" --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 2 — requires file listing tool
copilot -p "List all files in the current directory." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

# Turn 3 — follow-up that builds on tool results
copilot -p "Now read the first file you found and summarize it." --model claude-sonnet-4.6 \
  --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo \
  --session-id "$SESSION_ID" 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp10: Tool execution impact"
```

**Expected result:**
- Turn 1: Small input, `cache_creation>0`
- Turn 2: Larger input (includes turn 1 context + tool results), partial cache hit on prior context
- Turn 3: Even larger input (includes tool results from turn 2), cache hit on prior prefix

**Teaching point:** Tool results are appended to the conversation and become part of the cached prefix in subsequent turns. This is fine as long as the prefix up to that point remains stable.

---

#### Experiment 11: TTL Expiry — Cache Miss After Delay

**Goal:** Show that waiting too long between calls causes cache expiry.

**Script:**
```bash
#!/bin/bash
# exp11-ttl-expiry.sh
source ./setup.sh
setup_otel "exp11-ttl"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Call 1 — create cache
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Call 2 — immediate (should hit cache)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

echo "Waiting 6 minutes for cache TTL to expire..."
sleep 360  # 6 minutes — exceeds the 5-minute default TTL

# Call 3 — after TTL expiry (should miss cache)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp11: TTL expiry"
```

**Expected result:**
- Call 1: `cache_read=0, cache_creation>0`
- Call 2: `cache_read>0` (within TTL)
- Call 3: `cache_read=0, cache_creation>0` (TTL expired, cache recreated)

**Teaching point:** Caches have a TTL (5 min default for Anthropic, 5–10 min for OpenAI). Keep calls within the TTL window for cache hits. For longer gaps, use extended cache retention (OpenAI 24h) or 1-hour TTL (Anthropic).

---

#### Experiment 12: Cross-Model Comparison

**Goal:** Compare caching behavior across different model providers.

**Script:**
```bash
#!/bin/bash
# exp12-cross-model.sh
source ./setup.sh
setup_otel "exp12-cross-model"

PROMPT="Explain the concept of eventual consistency in distributed systems in 3 paragraphs."

# Claude
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# GPT
copilot -p "$PROMPT" --model gpt-5.4 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model gpt-5.4 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

# Gemini
copilot -p "$PROMPT" --model gemini-3.5-flash --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null
copilot -p "$PROMPT" --model gemini-3.5-flash --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp12: Cross-model comparison"
```

**Expected result:** All models should show cache hits on the second call, but the magnitude and cache hit rate may differ by provider.

**Teaching point:** Different providers have different caching mechanisms (automatic vs explicit), minimum cacheable token thresholds, and TTLs. The analytics script breaks down by model for comparison.

---

#### Experiment 13: `userPromptSubmitted` Hook Context Impact (v1.0.65+)

**Goal:** Demonstrate how `userPromptSubmitted` hooks can inject `additionalContext` and how dynamic context in these hooks kills caching.

**Script:**
```bash
#!/bin/bash
# exp13-hook-impact.sh
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
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

sleep 2

# Call 2 — hook injects timestamp B (prefix changes!)
copilot -p "$PROMPT" --model claude-sonnet-4.6 --output-format json --silent \
  --no-custom-instructions --disable-builtin-mcps --yolo 2>/dev/null

python3 analyze.py "$COPILOT_OTEL_FILE_EXPORTER_PATH" "Exp13: Dynamic hook context"

# Cleanup hooks for other experiments
rm -rf .github/hooks .github/copilot-hooks.json
```

**Expected result:** Both calls: `cache_read=0`. Even though the user prompt is identical, the hook injects a dynamic timestamp into the model-facing prompt prefix, breaking the cache.

**Teaching point:** The `userPromptSubmitted` hook is powerful but dangerous for caching. If you use it to inject context, ensure that context is **stable** across requests. Avoid timestamps or random IDs in `additionalContext`.

---

#### Experiment 14: Dynamic Tail Mitigation

**Goal:** Show the positive counterpart to Experiment 3: dynamic content is much less harmful when moved behind a large stable prefix.

**Script:** `bash exp14-dynamic-tail-mitigation.sh`

**Expected result:** Phase A (dynamic prefix) should show low reuse for the large context. Phase B (dynamic suffix) should preserve cache reuse for the stable context prefix.

**Teaching point:** The recommendation is not merely "remove all dynamic content." It is: keep stable content first, and isolate dynamic values after the stable cacheable prefix.

---

#### Experiment 15: RAG Ordering

**Goal:** Demonstrate how relevance-order churn in retrieved chunks can break prompt-prefix reuse, while deterministic ordering by stable chunk IDs preserves it.

**Script:** `bash exp15-rag-ordering.sh`

**Expected result:** The unstable ordering phase should miss or reduce cache reuse; the stable ordering phase should show a second-call cache hit.

**Teaching point:** RAG systems should avoid placing non-deterministically ordered retrieved chunks before otherwise reusable prefix content. If retrieved context must be cached, canonicalize its order.

---

#### Experiment 16: Schema Canonicalization

**Goal:** Show that semantically equivalent JSON/tool schemas can miss the cache when serialized with different key or tool order.

**Script:** `bash exp16-schema-canonicalization.sh`

**Expected result:** Shuffled schemas should reduce reuse; canonical schema serialization should allow the second call to reuse the prefix.

**Teaching point:** Tool definitions and JSON schemas are bytes in the prompt prefix. Use canonical serialization and stable tool ordering.

---

#### Experiment 17: Semantic Threshold Simulation

**Goal:** Provide an offline exercise showing why static semantic-cache thresholds trade hit rate against false positives.

**Script:** `python3 exp17-semantic-threshold-simulation.py`

**Expected result:** Lower thresholds produce more hits but also false hits for parameter-rich, temporal, or tool-result-sensitive queries. Higher thresholds reduce false positives but miss safe paraphrases.

**Teaching point:** Semantic caching is not the same as prefix caching. For approximate matches, use verified/adaptive approaches (vCache/Krites), temporal classifiers, or task-level caches rather than a global threshold alone.

---

### 3.5 Analytics and Comparison

#### Running all experiments and generating a comparison report:

```bash
#!/bin/bash
# run-all.sh — Run all experiments and generate comparison report

EXPERIMENTS=(
  "exp1-baseline.sh"
  "exp2-cache-hit.sh"
  "exp3-timestamp-invalidation.sh"
  "exp4-custom-instructions.sh"
  "exp5-mcp-impact.sh"
  "exp6-multi-turn.sh"
  "exp7-model-switch.sh"
  "exp8-reasoning-effort.sh"
  "exp9-skills-impact.sh"
  "exp10-tool-execution.sh"
  # exp11-ttl-expiry.sh excluded from quick run (6 min wait)
  "exp12-cross-model.sh"
  "exp13-hook-impact.sh"
  "exp14-dynamic-tail-mitigation.sh"
  "exp15-rag-ordering.sh"
  "exp16-schema-canonicalization.sh"
)

RESULTS_DIR="$HOME/cache-experiments/results"
mkdir -p "$RESULTS_DIR"

for exp in "${EXPERIMENTS[@]}"; do
  echo "Running $exp..."
  bash "$exp" 2>&1 | tee "$RESULTS_DIR/${exp%.sh}-output.txt"
done

# Generate comparison table
python3 compare.py "$EXPERIMENT_DIR/otel"

# Run offline semantic-cache simulation
python3 exp17-semantic-threshold-simulation.py | tee "$RESULTS_DIR/exp17-semantic-threshold-simulation-output.txt"
```

#### Comparison script:

```python
#!/usr/bin/env python3
"""compare.py — Generate comparison table across all experiments."""

import json
import os
import sys
from pathlib import Path


def load_analytics(results_dir: str) -> list[dict]:
    """Load all analytics JSON files from results directory."""
    results = []
    for root, dirs, files in os.walk(os.path.expanduser(results_dir)):
        for f in files:
            if f.endswith("-analytics.json"):
                filepath = os.path.join(root, f)
                with open(filepath) as fh:
                    data = json.load(fh)
                    data["source_file"] = f
                    results.append(data)
    return results


def print_comparison_table(results: list[dict]):
    """Print a markdown comparison table."""
    print("\n## Cache Invalidation Experiment Results\n")
    print("| Experiment | LLM Calls | Input Tokens | Cache Read | Cache Creation | Hit Rate |")
    print("|---|---|---|---|---|---|")

    for r in results:
        label = r.get("source_file", "unknown").replace("-analytics.json", "")
        calls = r.get("total_llm_calls", 0)
        input_tok = r.get("total_input_tokens", 0)
        cache_read = r.get("total_cache_read_tokens", 0)
        cache_create = r.get("total_cache_creation_tokens", 0)
        hit_rate = r.get("overall_cache_hit_rate", 0)
        print(f"| {label} | {calls} | {input_tok:,} | {cache_read:,} | {cache_create:,} | {hit_rate:.1%} |")

    print()


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 compare.py <results-dir>")
        sys.exit(1)
    results = load_analytics(sys.argv[1])
    print_comparison_table(results)


if __name__ == "__main__":
    main()
```

### 3.6 Expected Results Summary

| Experiment | Expected Cache Hit Rate | Key Lesson |
|---|---|---|
| Exp1: Baseline | 0% | First call always creates cache |
| Exp2: Repeated identical | ~50% (2nd call hits) | Identical prefix → cache hit |
| Exp3: Timestamp invalidation | 0% | Dynamic content at start kills cache |
| Exp4: Custom instructions | High on 2nd call | Stable instructions are cacheable |
| Exp5: MCP impact | High on 2nd call | Tool definitions are part of cached prefix |
| Exp6: Multi-turn append | Increasing per turn | Appending preserves cache |
| Exp7: Model switching | 0% on switch | Different model = different cache |
| Exp8: Reasoning effort | 0% on change | Effort changes can invalidate |
| Exp9: Skills impact | High on 2nd call | Skill content is stable → cacheable |
| Exp10: Tool execution | Partial per turn | Tool results append to cached prefix |
| Exp11: TTL expiry | 0% after 6 min | Cache expires after TTL |
| Exp12: Cross-model | Varies by provider | Different providers, different caching |
| Exp13: Hook impact | 0% | Dynamic hook context breaks prefix |
| Exp14: Dynamic tail | Prefix phase low; suffix phase higher | Dynamic content belongs after stable cacheable content |
| Exp15: RAG ordering | Unstable low; stable higher | Deterministic chunk ordering preserves reuse |
| Exp16: Schema canonicalization | Shuffled low; canonical higher | Canonical JSON/tool ordering preserves reuse |
| Exp17: Semantic thresholds | Offline precision/recall table | Static thresholds trade hits against false positives |

### 3.7 Tutorial Delivery Outline

1. **Introduction (5 min)**
   - What is input token caching? Why does it matter?
   - Cost and latency impact (up to 90% cost reduction, 80% latency reduction)

2. **How Caching Works (5 min)**
   - KV tensors, prefix matching, byte-for-byte requirement
   - Provider differences (automatic vs explicit)
   - Cache hierarchy: tools → system → messages

3. **OTel Prep & Validation (5 min)**
   - Set `COPILOT_OTEL_ENABLED=true`, `COPILOT_OTEL_EXPORTER_TYPE=file`, `COPILOT_OTEL_FILE_EXPORTER_PATH`
   - Run `setup.sh` smoke test and verify spans are written
   - Show the difference between `gen_ai.usage.cache_read_input_tokens` and `gen_ai.usage.cache_creation_input_tokens`

4. **CLI Tooling Overview (3 min)**
   - Copilot CLI scripted mode (`-p`, `--output-format json`)
   - Token attributes in OTel JSONL
   - Optional: `ccusage` for richer reports

5. **Live Experiments (25–30 min)**
   - Run Experiments 1–6, 7–10, 12–16 (skip 11 due to time)
   - Run Experiment 17 offline to discuss semantic-cache correctness
   - Show real-time analytics after each live experiment
   - Discuss results and lessons

6. **Patterns & Antipatterns Summary (5 min)**
   - Top 5 patterns to follow
   - Top 5 antipatterns to avoid
   - Provider-specific notes

7. **Diagnostic Tools (5 min)**
   - Anthropic cache diagnostics
   - cachelens offline checker
   - OTel-based monitoring with ccusage

8. **Q&A (5 min)**

### 3.8 Key Takeaways for Audience

1. **Cache is prefix-based and practically byte-for-byte** — any prefix change can invalidate reuse
2. **Stable content first, dynamic content last** — the golden rule
3. **Tools, system prompt, instructions, schemas, and retrieved context can all be part of the cached prefix**
4. **Canonicalize ordering** — stable JSON, stable tool lists, stable RAG chunk order
5. **Pin your model version** — model switches reset cache
6. **Keep calls within TTL** — 5 min default, 1h or 24h options available depending on provider
7. **Append, don't modify** — in multi-turn, never edit earlier messages
8. **Treat semantic caching as approximate unless verified** — static thresholds can false-hit
9. **Monitor cache hit rate** — it's a first-class production metric
10. **Use diagnostic tools** — Anthropic cache diagnostics, cachelens, OTel telemetry
