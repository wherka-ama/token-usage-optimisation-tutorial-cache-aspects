# LLM Prompt Caching Quickcard

## The "Golden Rule"
**Stable content goes FIRST. Volatile content goes LAST.**
*Caching is a prefix game. Any change at the start invalidates everything that follows.*

---

## Side-by-Side: Best vs. Worst Practices

### 1. System Prompts & Instructions

**BEST (Cache Friendly):**
```
[System: You are a helpful coding assistant.]
[Tools: {file_read, file_write, search}]
[User: Help me debug this function.]
```
- System prompt is identical across all calls.
- Tool definitions are static and precede user content.
- Dynamic content (user query) is at the end.

**WORST (Cache Killer):**
```
[Current Time: 2025-01-15 14:32:07 UTC]
[System: You are a helpful coding assistant.]
[Tools: {file_read, file_write, search}]
[User: Help me debug this function.]
```
- A timestamp at the start invalidates the entire prefix.
- Every call produces a cache miss — zero savings.
- *See Experiment 3 (Timestamp Invalidation).*

### 2. Multi-Turn Conversations

**BEST (Append-Only):**
```
Turn 1: [System] + [Tools] + [User: What is X?]
Turn 2: [System] + [Tools] + [User: What is X?] + [Asst: X is...] + [User: How about Y?]
Turn 3: [System] + [Tools] + [User: What is X?] + [Asst: X is...] + [User: How about Y?] + [Asst: Y is...] + [User: And Z?]
```
- Each turn appends to the prior prefix — cache hit on everything before the new message.
- *See Experiment 6 (Multi-Turn).*

**WORST (Rewrite History):**
```
Turn 1: [System] + [Tools] + [User: What is X?]
Turn 2: [System] + [Tools] + [User: What is X (rephrased)?] + [Asst: X is...] + [User: How about Y?]
```
- Even minor rephrasing of earlier messages invalidates the cache from that point onward.
- The entire prefix must be re-processed.

### 3. Model Selection

**BEST (One Model Per Session):**
```
Session: Use claude-sonnet-4-20250514 for all turns.
```
- Model identity is part of the cache namespace.
- Staying on one model preserves the cache across all turns.
- *HyDRA (arXiv:2605.17106) confirms: production systems use "sticky routing" to avoid mid-conversation model switches, protecting a 90% cache discount.*

**WORST (Switch Mid-Session):**
```
Turn 1: claude-sonnet-4-20250514
Turn 2: gpt-4o
Turn 3: claude-sonnet-4-20250514
```
- Each switch invalidates the entire cache — full re-processing required.
- *See Experiment 7 (Model Switch).*

### 4. Tool & MCP Definitions

**BEST (Static Schema):**
```json
{"tools": [{"name": "read_file", "schema": {...}}, {"name": "write_file", "schema": {...}}]}
```
- Tool schemas are defined once and never change between calls.
- They become part of the stable, cached prefix.
- *See Experiment 5 (MCP Impact).*

**WORST (Dynamic Tool List):**
```python
tools = generate_tools_based_on_context(user_input)  # Different every time!
```
- Tool definitions change per call, invalidating the prefix.
- Even adding/removing one tool breaks the cache for everything after it.

### 5. Hook & Custom Context (CLI Tools)

**BEST (No Dynamic Hooks):**
```bash
copilot --prompt "Help me refactor this function"
```
- No dynamic context injected before the prompt.
- Clean, stable prefix.

**WORST (Dynamic Hook Context):**
```bash
# Hook injects: "Current session: abc123, Time: 14:32:07"
copilot --prompt "Help me refactor this function"
```
- Hook-injected dynamic content at the start kills the cache.
- *See Experiment 13 (Hook Impact).*

### 6. RAG and Retrieved Context

**BEST (Stable Ordering):**
```
[Stable system prompt]
[Retrieved chunks sorted by document_id]
[Current user query]
```
- Stable chunk ordering preserves the shared prefix across similar queries.
- *See Experiment 15 (RAG Ordering).*

**WORST (Relevance-Order Churn):**
```
[Stable system prompt]
[Retrieved chunks sorted by floating relevance score]
[Current user query]
```
- Similar queries can reorder chunks, changing bytes near the prefix and reducing reuse.

### 7. Tool Schemas and JSON

**BEST (Canonical Serialization):**
```json
{"tools":[{"description":"Read a file","name":"read_file"}]}
```
- Sort tool lists and schema keys deterministically.
- *See Experiment 16 (Schema Canonicalization).*

**WORST (Semantically Same, Byte-Different):**
```json
{"tools":[{"name":"read_file","description":"Read a file"}]}
```
- Same meaning, different byte order: enough to change the cacheable prefix.

### 8. Semantic Caching

**BEST (Verified or Scoped):**
```
Use verified/adaptive semantic caching for low-risk paraphrases.
Bypass semantic cache for temporal, safety-critical, or parameter-rich tool queries.
```
- vCache/Krites-style verification and temporal classifiers reduce false positives.
- *See Experiment 17 (Semantic Threshold Simulation).*

**WORST (One Global Threshold):**
```
if cosine_similarity(query, cached_query) > 0.80: return cached_response
```
- Static thresholds can false-hit on dates, IDs, live data, file paths, or tool parameters.

---

## Do's vs. Don'ts Summary

| Feature | DO (Cache Friendly) | DON'T (Cache Killer) |
|---|---|---|
| **System Prompts** | Keep them at the very top, identical across calls. | Prepend with dynamic timestamps or session IDs. |
| **User Context** | Place current file content at the end of the prompt. | Prepend "Current Time: HH:MM:SS" at the start. |
| **Multi-turn** | Append new messages to the history. | Edit, rephrase, or re-order previous messages. |
| **Model Versions** | Pin to a specific version (e.g., `claude-sonnet-4-20250514`). | Use generic tags that might flip (e.g., `latest`). |
| **Tool Definitions** | Keep tool schemas static and stable. | Dynamically generate tool lists per call. |
| **Hooks/Context** | Disable dynamic hooks during experiments. | Allow hooks to inject timestamps/IDs into the prefix. |
| **RAG Context** | Sort retrieved chunks by stable IDs when cache reuse matters. | Sort cacheable context by fluctuating relevance scores. |
| **Schemas/JSON** | Canonicalize tool lists and JSON key order. | Let dict/map iteration produce different schema bytes. |
| **Semantic Cache** | Use verified/adaptive policies or bypass risky queries. | Use one global similarity threshold for all requests. |
| **Model Routing** | Stay on one model per conversation session. | Switch models mid-conversation. |

---

## The Checklist
1. **[ ]** Is my system prompt identical across calls?
2. **[ ]** Are my tool definitions at the beginning and static?
3. **[ ]** Did I remove dynamic data (dates/random seeds/session IDs) from the prefix?
4. **[ ]** Are RAG chunks ordered deterministically if they are in the cacheable prefix?
5. **[ ]** Are JSON/tool schemas canonicalized?
6. **[ ]** Am I within the TTL window? (Anthropic: ~5m, OpenAI: 5-10m)
7. **[ ]** Am I using a model that supports caching? (Claude 3.5+, GPT-4o)
8. **[ ]** Am I appending (not rewriting) in multi-turn conversations?
9. **[ ]** Am I staying on one model per session?
10. **[ ]** Am I avoiding naive semantic caching for temporal, parameter-rich, or safety-critical requests?

---

## Measuring Success
Watch your OTel/API headers for:
- `cache_read_input_tokens`: The "Money Saved" counter.
- `cache_creation_input_tokens`: The "Cache Miss" cost.
- `overall_cache_hit_rate`: Target >50% for repeated prompts; >80% for multi-turn.

---

## UBB Context: Why This Matters Now
GitHub Copilot is moving to **Usage-Based Billing** — every token has a price.
- Cache hits cost **10-50% of full input token price** (provider-dependent).
- A 90% cache hit rate on a 10K-token prefix saves ~9K tokens per call.
- At scale (1M+ calls/day), this is the difference between profitable and unprofitable AI features.
- **HyDRA production data (arXiv:2605.17106):** Cache-preserving sticky routing contributed to a measured **7-20% COGS reduction** in GitHub Copilot's VS Code Chat auto-mode.

---

## Sources
- Experimental harness: this repository (17 experiments)
- Prompt/prefix caching: `research/chapters/ch04-prompt-and-prefix-caching.md`
- Semantic caching correctness: `research/chapters/ch05-semantic-caching.md`
- Harness/tooling caching: `research/chapters/ch06-harness-and-tooling-caching.md`
- Best practices and anti-patterns: `research/chapters/ch09-best-practices.md`
- Cache-preserving routing / HyDRA: [arXiv:2605.17106](https://arxiv.org/abs/2605.17106)
- GitHub Copilot UBB Resources: [fimdim.com/ghcp-ubb-resources](https://fimdim.com/ghcp-ubb-resources/)
- GitHub Copilot Billing: [docs.github.com](https://docs.github.com/en/enterprise-cloud@latest/copilot/concepts/billing)
