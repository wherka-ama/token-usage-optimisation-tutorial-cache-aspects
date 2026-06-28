# Chapter 6: Caching in Harnesses, Tooling, and Agentic Frameworks

## 6.1 Introduction

Beyond the model-level KV cache and provider-level prompt caching, a distinct layer of caching operates within the **harnesses, tooling, and agentic frameworks** that orchestrate LLM interactions. This includes CLI tools (e.g., GitHub Copilot CLI), coding assistants (e.g., Claude Code, Cursor), multi-agent frameworks, and serving systems designed specifically for agentic workloads. This chapter examines how these systems utilize caching and the unique challenges they face.

---

## 6.2 The Agentic Caching Landscape

### 6.2.1 Why Agentic Workloads Are Different

Agentic workloads introduce caching challenges that traditional chatbot-oriented caching cannot address [19, 21, 22]:

1. **Multi-turn with tool calls**: Agents alternate between LLM reasoning and tool execution, creating pauses that break the continuity of inference
2. **Data-dependent outputs**: Agent outputs depend on external data and environmental context, not just input prompts
3. **Long-horizon sessions**: Conversations can span dozens of API calls with accumulating context
4. **Dynamic tool discovery**: Tools may change at runtime (e.g., MCP servers connecting/disconnecting)
5. **Plan-Act loops**: The Plan stage (expensive LLM reasoning) is often repeated across similar tasks

### 6.2.2 Levels of Harness/Tooling Caching

| Level | What is Cached | Example Systems |
|-------|---------------|-----------------|
| **CLI tool context** | System prompts, hooks, custom instructions | GitHub Copilot CLI [experimental harness] |
| **Agent execution plans** | Structured plan templates from prior executions | Agentic Plan Caching [19] |
| **Tool execution results** | API call results, search results, file contents | LLM-dCache [23] |
| **Multi-turn KV cache** | KV cache retention across tool call pauses | CacheTTL [21] |
| **Workflow-aware KV** | KV cache managed per agent step graph | KVFlow [20] |
| **Client-side responses** | Full (prompt, response) pairs with namespaces | Cache Saver [32], Mnimi [31] |

---

## 6.3 CLI Tool Caching: The Experimental Harness Perspective

### 6.3.1 GitHub Copilot CLI as a Case Study

The experimental harness in this repository demonstrates caching challenges in CLI-based LLM tools:

- **System prompts**: Copilot CLI injects system instructions that are stable across calls — ideal cache candidates
- **Tool definitions**: MCP server tool schemas are part of the cached prefix when static
- **Custom instructions**: `AGENTS.md` files add stable, cached tokens
- **Skills**: Large skill files increase cached density (more tokens in the stable prefix)

**Cache killers identified through experiments**:
- **Timestamps at prompt start** (Experiment 3): A single date string at the beginning invalidates the entire prefix
- **Dynamic hook context** (Experiment 13): CLI hooks injecting session IDs or timestamps break the cache
- **Model switches** (Experiment 7): Different models have different cache namespaces
- **Reasoning effort changes** (Experiment 8): Changing reasoning parameters can reset prefix compute

### 6.3.2 Experiment Isolation

The harness implements **Experiment Isolation** to prevent personal configurations from biasing results:
- Sets a temporary `COPILOT_HOME` to avoid personal skills/instructions
- Unsets `COPILOT_SKILLS_DIRS` to prevent external skill loading
- This demonstrates how tooling configuration directly impacts caching behavior

### 6.3.3 OTel-Based Cache Analytics

The harness uses OpenTelemetry (OTel) traces to measure caching:
- `cache_read_input_tokens`: Tokens served from cache (cache HIT)
- `cache_creation_input_tokens`: Tokens written to cache (cache WRITE)
- `overall_cache_hit_rate`: Fraction of input tokens from cache reads

This instrumentation pattern is representative of how production harnesses measure cache effectiveness.

---

## 6.4 Agentic Plan Caching

### 6.4.1 The Plan-Act Paradigm

Many LLM-based agents follow a two-stage pipeline [19]:
1. **Plan**: A planner LLM generates a strategy (task decomposition, information retrieval)
2. **Act**: An actor LLM executes the plan based on external context/environment

The Plan stage incurs the **majority of LLM compute cost** but is often repeated across semantically similar tasks.

### 6.4.2 How Agentic Plan Caching Works

1. **Template Extraction**: When an agent completes a workflow, structured plan templates are extracted from the execution log
2. **Keyword Extraction**: Key semantic targets are identified from the query
3. **Cache Matching**: New requests are matched against cached plan templates using keyword-based similarity (not full-query semantic similarity)
4. **Template Adaptation**: A lightweight model adapts the cached template to task-specific context (e.g., fiscal year, company name)
5. **Execution**: The adapted plan is executed by the actor LLM

### 6.4.3 Results

- **46.62% average cost reduction** while maintaining 96.67% of application-level performance [19]
- **27.28% average latency reduction**
- Cache-miss and cache-hit accuracy are consistent (no degradation on cache hits)
- Overhead: keyword extraction and cache generation account for only 1.04% of total cost
- Worst-case (zero hit rate): overhead is only 1.31%

### 6.4.4 Why It Outperforms Semantic Caching for Agents

- Semantic caching stores raw responses, which are data-dependent and not reusable
- Plan caching stores **abstract templates** that capture the intent, not the specific execution
- Template adaptation handles task-specific variations
- Keyword matching avoids the false-positive problem of full-query semantic similarity

---

## 6.5 CacheTTL: Multi-Turn Agent Scheduling

### 6.5.1 The Tool Call Pause Problem

In agentic workloads, when an LLM generates a tool call, the inference pauses while the tool executes. Standard serving systems evict the KV cache at end-of-turn to free GPU memory. When the tool returns and the next turn begins, the entire KV cache must be recomputed (re-prefilled) [21].

### 6.5.2 CacheTTL's Solution

CacheTTL introduces a **time-to-live (TTL)** mechanism for KV cache retention:

1. **TTL Assignment**: For each request that generates a tool call, CacheTTL assigns a TTL based on:
   - **Reload cost**: The prefill computation saved if the cache is retained
   - **Queueing delay reduction**: The benefit of not blocking behind other requests
   - **Tool call distribution**: Expected duration of the tool execution

2. **Automatic Eviction**: When TTL expires, the KV cache is automatically evicted, preventing memory pressure from long-running or failed tool calls

3. **Program-level FCFS**: Combines TTL with program-level first-come-first-serve scheduling to enforce request ordering

### 6.5.3 Results

- **Over 8× improvement** in average job completion time [21]
- Improved throughput across real-world agents (SWE-Bench, BFCL, OpenHand)
- Works with Llama-3.1 8B/70B, Gemma-3 12B, and GLM-4.5 355B
- Robust against edge cases (failed tool calls, unexpectedly long executions)

---

## 6.6 KVFlow: Workflow-Aware KV Cache Management

### 6.6.1 The Agent Step Graph

KVFlow [20] abstracts multi-agent workflows as an **Agent Step Graph**:
- Each agent is a node in the graph
- Edges represent execution dependencies
- Each agent is assigned a **steps-to-execution** value estimating temporal proximity to future activation

### 6.6.2 Workflow-Aware Eviction

- Replaces LRU with eviction guided by steps-to-execution values
- Agents scheduled in the next step have their KV caches preserved
- Agents far from execution are evicted first
- Fine-grained eviction at the KV node level (not just per-request)

### 6.6.3 Overlapped Prefetching

- Proactively loads KV tensors from CPU to GPU in background threads
- For agents scheduled in the next step, prefetching begins immediately
- Avoids cache miss stalls during generation

### 6.6.4 Results

- Up to **1.83× speedup** for single workflows with large prompts
- Up to **2.19× speedup** for scenarios with many concurrent workflows
- Compared against SGLang with hierarchical radix cache

---

## 6.7 LLM-dCache: GPT-Driven Data Caching

### 6.7.1 Concept

LLM-dCache [23] introduces a novel approach: **treating cache operations as callable API functions** exposed to the tool-augmented agent:

- The LLM is granted autonomy to manage cache decisions via prompting
- Cache operations (store, retrieve, invalidate) are integrated as tools
- Compatible with existing function-calling mechanisms
- Plug-and-play: no changes to baseline agents

### 6.7.2 Results

- **1.24× average improvement** in Copilot times across various LLMs and prompting techniques
- Cache hit rates consistently around 97%
- GPT-driven cache operations closely match fully programmatic approaches
- Demonstrates the versatility of LLM-guided cache management

### 6.7.3 Significance

This work positions caching as a **system-level optimization that LLMs themselves can manage**, opening a direction toward LLM-guided infrastructure optimization (DVFS, core allocation, thermal management).

---

## 6.8 Efficient LLM Serving for Agentic Workflows

### 6.8.1 The Data Systems Perspective

The work by [22] examines agentic workflows from a data systems perspective:
- Modern agentic workflows resemble traditional data processing pipelines
- Multiple operators (retrieval, planning, tool use, reflection) are chained
- Each operator may invoke the LLM with different prompts and contexts
- Naive sequential execution on unmodified vLLM backends is inefficient

### 6.8.2 Optimizations

- **Operator-level caching**: Cache results of individual workflow operators
- **Cross-operator KV reuse**: Share KV caches between operators that process similar prefixes
- **Batched execution**: Group independent operators for batched LLM calls
- **Prefill-decode disaggregation**: Separate prefill (cache creation) from decode (generation) across different GPU pools

### 6.8.3 Pythia: Workflow-Predictable Agent-Native Serving

Pythia [60] exploits the **predictability of agentic workflows** for proactive cache management:

- **Workflow profiler**: Extracts execution graphs and prompt templates from agent workflows at registration time
- **Proactive Belady-like eviction**: Replaces reactive LRU with a strategy that leverages workflow information to accurately prefetch shared contexts and immediately drop transient tokens no longer needed
- **Forward cache staging**: Anticipates the precise prompt composition of upcoming requests and asynchronously warms the cache for the next probable agent, effectively hiding prefill latency before the subsequent request arrives
- **Three-tier hierarchical prefix cache**: L1 (GPU HBM) for immediate access, L2 (CPU DRAM) as staging buffer, L3 (shared storage) for cross-engine persistence
- **Graph-driven global priority assignment**: Prevents cluster-wide starvation by assigning priorities based on workflow dependencies rather than FCFS

Key insight: *"By anticipating the precise prompt composition of upcoming requests, [the manager] asynchronously warms the cache for the next probable agent, effectively hiding prefill latency before the subsequent request even arrives"* [60].

### 6.8.4 PBKV: Prediction-Based KV-Cache for Dynamic Workflows

PBKV [61] addresses **dynamic** multi-agent workflows where the execution pattern is not known in advance:

- **Complementary signal fusion**: Combines cross-workflow agent transition patterns with per-request semantics for prediction
- **Multi-step horizon**: Cache reuse distances can span several invocations (e.g., across retry loops); single-step predictors are myopic
- **Hierarchical eviction**: Reclaims retired (terminated workflow) cache first, then ranks active cache by lookahead reuse score — embedding deterministic guardrails within a probabilistic system
- **Conservative prefetching**: Consumes only otherwise-idle GPU space and PCIe bandwidth, so it never backfires even under poor predictions
- **Graceful degradation**: Theoretically proven to degrade gracefully under prediction error

Key distinction from KVFlow [20]: PBKV handles **dynamic** workflows (unpredictable execution patterns) while KVFlow assumes a static Agent Step Graph. PBKV also outperforms the SOTA method on static workflows.

### 6.8.5 CacheRL: Cached Rollouts for RL Training of Tool-Calling Agents

CacheRL [62] introduces a fundamentally different caching application: **caching tool results for RL training** of multi-turn agents:

- **Three-tier fuzzy cache**: Exact, fuzzy, and best-effort cache lookups for tool results
- **CacheAgentLoop**: Generates reasoning and tool calls (mask=1), performs cache lookup, injects cached results (mask=0) — maintaining trajectory structure without live tool execution
- **Token-level masking**: Separate masks for generated vs. cached tokens enable proper credit assignment in RL
- **Cost reduction**: Reduces per-rollout cost from dollars to fractions of a cent — 100× reduction vs. live tool execution
- **Cache-tier-aware reward**: Dynamically adjusts reward weights based on cache quality, preventing the model from being penalized for cache limitations
- Scales to trajectories with 30+ tool calls while maintaining sub-second latency per rollout

This work demonstrates that caching is not just an inference optimization but also a **training enabler** — making multi-turn RL training practical at scale.

### 6.8.6 Temporal Semantic Caching for Plan-Execute Pipelines

The temporal semantic caching work [63] addresses a critical gap: **existing semantic caches break down when output validity depends on time, asset, or sensor parameters**:

- **Temporal classifier**: Routes queries into four buckets:
  - **Volatile**: Live state, bypass cache entirely
  - **Static**: No temporal dependence, standard semantic match
  - **Relative**: e.g., "yesterday," resolved into a concrete time window
  - **Anchored**: Fixed time window, matched against compatible windows
- **MCP workflow optimizations**: Disk-backed tool-discovery caching and dependency-aware parallel step execution over a persistent server pool
- **Results**: MCP optimizations alone → 1.67× speedup, ~40% median latency reduction; temporal cache hits → 30.6× median speedup
- **Critical finding**: Exposes *"a concrete failure mode of pure semantic caching for parameter-rich industrial queries"* — semantic caching without temporal awareness returns stale or incorrect results

### 6.8.7 Hierarchical Caching for Agentic Workflows

The hierarchical caching architecture [64] proposes a **multi-level caching system** specifically designed for agentic workflows:

- **Planning cache**: Caches LLM-generated plans for similar queries
- **Tool execution cache**: Caches results of external tool/API calls
- **Response cache**: Caches final agent responses
- Each level has different TTL, invalidation, and correctness requirements
- Eliminates planning redundancy and reduces tool execution overhead
- Designed for agents that handle similar queries or workflow patterns repeatedly

---

## 6.9 Client-Side Caching Frameworks

### 6.9.1 Cache Saver

Cache Saver [32] operates as a **client-side man-in-the-middle optimization layer**:
- Transparent: no changes to end-user application logic or underlying LLM
- Namespace-aware list-valued cache for statistical integrity
- Disk-resident cache with low memory overhead
- Supports both local and online models
- **Results**: ~25% cost reduction, ~35% CO₂ reduction on average; up to 60% for benchmarking

### 6.9.2 Mnimi

Mnimi [31] provides a **single-file, dependency-free** caching solution:
- ~300 lines of code; just copy `cached_llm.py` to a project
- Supports Independent, Repeatable, and Persistent caching modes
- Cache slicing for sharing minimal subsets
- Batch sampling support
- Replication mode (cache-only, no model queries)

---

## 6.10 Summary

Caching in harnesses and agentic frameworks operates at a higher abstraction level than KV cache or prompt caching:

1. **Agentic Plan Caching** [19] caches structured plans, not responses, achieving 46.62% cost reduction
2. **CacheTTL** [21] solves the tool-call pause problem with TTL-based KV retention, achieving 8× JCT improvement
3. **KVFlow** [20] introduces workflow-aware eviction with 2.19× speedup for concurrent workflows
4. **Pythia** [60] exploits workflow predictability with proactive Belady-like eviction and forward cache staging
5. **PBKV** [61] handles dynamic workflows with multi-step prediction and hierarchical eviction with graceful degradation
6. **CacheRL** [62] uses cached tool rollouts for RL training, reducing per-rollout cost by 100×
7. **Temporal semantic caching** [63] adds temporal awareness to semantic caching, achieving 30.6× speedup on cache hits
8. **Hierarchical caching** [64] proposes multi-level architecture for planning, tool, and response caching
9. **LLM-dCache** [23] lets LLMs manage their own caches, achieving 1.24× improvement
10. **Cache Saver** [32] and **Mnimi** [31] provide client-side caching with statistical integrity

The key insight is that agentic workloads require **task-level, workflow-aware, temporally-aware** caching that understands the Plan-Act loop, tool execution patterns, multi-turn continuity, and temporal validity — not just token-level prefix matching.

---

## References

- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [20] Pan et al., "KVFlow: Efficient Prefix Caching for Accelerating LLM-Based Multi-Agent Workflows," arXiv:2507.07400, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [22] "Efficient LLM Serving for Agentic Workflows: A Data Systems Perspective," arXiv:2603.16104, 2026.
- [23] "LLM-dCache: Improving Tool-Augmented LLMs with GPT-Driven Localized Data Caching," arXiv:2406.06799, 2024.
- [31] Dai et al., "Statistical Independence Aware Caching for LLM Workflows," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver: A Modular Framework for Efficient, Affordable, and Reproducible LLM Inference," Findings of EMNLP 2025.
- [60] "Pythia: Exploiting Workflow Predictability for Efficient Agent-Native LLM Serving," arXiv:2604.25899, 2026.
- [61] "PBKV: Efficient Serving for Dynamic Agent Workflows with Prediction-based KV-Cache Management," arXiv:2605.06472, 2026.
- [62] "CacheRL: Multi-Turn Tool-Calling Agents via Cached Rollouts and Hybrid Reward," arXiv:2606.14179, 2026.
- [63] "Evaluating Temporal Semantic Caching and Workflow Optimization in Agentic Plan-Execute Pipelines," arXiv:2605.20630, 2026.
- [64] "Hierarchical Caching for Agentic Workflows: A Multi-Level Architecture to Reduce Tool-Execution Overhead," MAKE 2026.
