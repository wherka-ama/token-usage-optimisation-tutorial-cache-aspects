# Chapter 8: Influence of Caching on Agentic System Behaviour

## 8.1 Introduction

Caching does not merely reduce cost and latency — it fundamentally shapes the behaviour of agentic LLM systems. The presence or absence of caching influences agent planning strategies, tool usage patterns, context management decisions, and even the quality of agent outputs. This chapter examines how caching affects agentic behaviour, drawing on recent research to identify both positive and negative behavioural impacts.

---

## 8.2 How Caching Shapes Agent Architecture

### 8.2.1 The Plan-Act Loop and Caching

The Plan-Act paradigm [19] creates a natural caching boundary:
- **Plan stage**: Expensive LLM reasoning that generates execution strategies
- **Act stage**: LLM execution based on plans and external context

Caching influences this loop in several ways:

1. **Plan reuse changes planning behaviour**: When plans are cached, agents can skip the planning stage for similar tasks, effectively changing from "plan-then-act" to "retrieve-plan-then-act"
2. **Context accumulation patterns**: With prefix caching, agents benefit from accumulating context (each turn appends to the cached prefix). Without caching, context management (summarization, pruning) becomes more important for cost control
3. **Tool call frequency**: With prompt caching, the marginal cost of additional tool calls decreases (system prompt is cached), potentially encouraging more thorough exploration

### 8.2.2 The Sticky Routing Effect

HyDRA's [41] cache-preserving sticky routing demonstrates how caching constraints shape system architecture:
- The router is invoked **only** on turn 1, after compaction, or after summarization
- This means the agent's model selection is "frozen" for the duration of a conversation
- **Behavioural implication**: The agent cannot dynamically switch to a stronger model mid-conversation if it encounters a difficult sub-task
- **Trade-off**: This constraint preserves the 90% cache discount but may sacrifice quality on hard sub-tasks

### 8.2.3 Context Engineering Adaptations

The "Don't Break the Cache" evaluation [18] reveals how caching drives context engineering:
- **Dynamic content placement**: Practitioners must restructure prompts to place stable content first
- **Tool definition management**: Dynamic tool discovery (MCP) breaks the cache, driving toward fixed tool sets
- **System prompt design**: Dynamic values (timestamps, session IDs) must be excluded from system prompts or placed at the end
- **Conversation management**: Summarization and pruning — standard context management techniques — **break cached representations**

> *"Common context management strategies can interact poorly with tool call caching. Techniques such as summarizing or pruning old tool calls break cached representations, making tool call caching counterproductive."* [18]

This creates a fundamental tension: **context management (to control cost) vs. cache preservation (to reduce cost)**. The optimal strategy depends on whether the cost of context growth exceeds the savings from caching.

---

## 8.3 Behavioural Impact of Plan Caching

### 8.3.1 Template-Based Behaviour

Agentic Plan Caching [19] changes agent behaviour from generating plans from scratch to adapting cached templates:
- **Positive**: Faster response, lower cost, consistent plan quality
- **Negative**: Reduced plan diversity; agents may converge on similar approaches for similar tasks
- **Risk**: Over-reliance on cached plans may cause agents to miss novel solutions

### 8.3.2 Cache-Hit vs. Cache-Miss Accuracy

A critical finding from [19]:
- For semantic caching and full-history caching: **cache-hit accuracy is significantly lower than cache-miss accuracy**
- For agentic plan caching: **accuracy is consistent regardless of cache-use status**

This means that naive caching can create a **quality degradation feedback loop**: as the cache grows and hit rates increase, average quality decreases. Agentic plan caching avoids this by adapting templates rather than returning raw cached responses.

### 8.3.3 The Adaptation Quality Factor

The quality of agentic plan caching depends on the **adaptation step** — how well the lightweight model can adapt a cached template to task-specific context:
- If adaptation is too weak: the plan may not account for task-specific requirements
- If adaptation is too strong: it approaches full planning, negating the cost savings
- The lightweight model (e.g., GPT-4o-mini) must balance specificity with generality

---

## 8.4 Tool Call Behaviour

### 8.4.1 Tool Call Frequency and Caching

With prompt caching, the cost structure of tool calls changes:
- **Without caching**: Each tool call adds to context length, increasing cost quadratically
- **With caching**: System prompt and prior conversation are cached; only new tool results are uncached
- **Behavioural effect**: Agents may make more tool calls (lower marginal cost) but must manage growing uncached context

### 8.4.2 Dynamic Tool Discovery

The Model Context Protocol (MCP) introduces dynamic tool discovery, where available tools vary based on connected servers [18]:
- **Cache-breaking**: Any change to the tool set invalidates the cached prefix
- **Behavioural adaptation**: Practitioners may avoid dynamic tool discovery to preserve caching
- **Alternative**: Implement dynamic capabilities through code generation rather than traditional function calling [18]

### 8.4.3 LLM-Driven Cache Management

LLM-dCache [23] introduces a novel behavioural pattern: **LLMs managing their own caches**:
- The LLM decides when to store, retrieve, and invalidate cache entries
- Cache operations are exposed as tools
- **Behavioural implication**: The LLM's decision-making now includes cache management as a first-class concern
- GPT-driven cache operations achieve 97% hit rates, closely matching programmatic approaches
- This suggests LLMs can effectively reason about caching strategies

---

## 8.5 Multi-Turn Continuity

### 8.5.1 The Tool Call Pause Problem

CacheTTL [21] identifies a fundamental behavioural pattern in agentic workloads:
- Agents alternate between LLM reasoning and tool execution
- Tool execution introduces pauses of varying duration
- Standard serving systems evict KV cache at end-of-turn
- When the tool returns, the agent must "restart" — re-processing the entire context

**Behavioural impact without CacheTTL**:
- Longer tool calls → longer pauses → more likely KV cache is evicted → more recomputation
- This creates a **penalty for thorough tool usage**: agents that take longer to execute tools are penalized with higher recomputation costs
- This may bias agents toward faster, less thorough tool execution

**With CacheTTL**:
- KV cache is retained with a TTL proportional to expected tool duration
- Agents can take longer for tool execution without cache eviction penalty
- This enables **more thorough, deliberate agent behaviour**

### 8.5.2 Workflow-Aware Scheduling

KVFlow [20] introduces workflow-aware scheduling that changes how multi-agent systems behave:
- The Agent Step Graph predicts which agents will be activated next
- KV caches for upcoming agents are preserved and prefetched
- **Behavioural impact**: Multi-agent systems can operate with lower latency between steps, enabling tighter collaboration patterns
- Concurrent workflows benefit more than sequential ones (2.19× vs. 1.83× speedup)

---

## 8.6 The Caching-Quality Trade-off

### 8.6.1 KV Cache Compression and Quality

KV cache compression techniques (quantization, eviction) can affect output quality:
- **KVQuant** [11]: Less than 0.1 perplexity degradation at 3-bit — generally safe
- **AQUA-KV** [16]: Less than 1% relative error at 2-2.5 bits — near-lossless
- **Eviction methods**: More variable; SAGE-KV [14] maintains accuracy at 4x compression, but aggressive eviction can degrade quality
- **DMS** [15]: Actually improves accuracy by enabling more token generation within the same compute budget

### 8.6.2 The Compression-Output Length Paradox

Gao et al. [4] identify a surprising behavioural effect:
- Compressing KV cache may lead to **longer outputs**
- Longer outputs increase end-to-end latency despite reduced prefill time
- This creates a **behavioural feedback**: compression changes the model's output distribution, potentially making outputs more verbose

### 8.6.3 Semantic Caching and Response Quality

Semantic caching can degrade response quality in subtle ways:
- Returning a cached response for a "similar" prompt may miss task-specific nuances
- **vCache** [24] shows that static thresholds lead to unpredictable error rates
- In agentic contexts, false-positive cache hits cause "substantial performance degradation" [19]
- The response may be technically correct but contextually inappropriate

---

## 8.7 Non-Determinism and Agent Behaviour

### 8.7.1 The Cascading Divergence Problem

Yuan et al. [33] demonstrate that in reasoning models, minor numerical differences in early tokens can **cascade into divergent chains of thought**:
- Up to 9% accuracy variation and 9,000 token response length differences
- This means the same agent, given the same input, may produce fundamentally different reasoning paths
- Prefix caching, by changing batch composition, contributes to this non-determinism

### 8.7.2 Implications for Agent Reliability

For agentic systems that must make consistent decisions:
- **Non-determinism undermines trust**: Users cannot rely on an agent that gives different answers to identical questions
- **Reproducibility is essential for debugging**: When an agent fails, reproducing the exact failure is necessary for diagnosis
- **Cache-aware determinism**: Mnimi [31] and Cache Saver [32] provide mechanisms for deterministic replay while preserving statistical integrity

### 8.7.3 The Determinism-Performance Trade-off

LLM-42 [35] identifies that enforcing determinism has a cost:
- Disabling dynamic batching (for determinism) severely degrades throughput
- Batch-invariant kernels [67] strip GPU kernels of parallelism
- *"Batch-invariant execution makes determinism the default for all requests, even when determinism is undesirable or even harmful"* [35]
- The solution: **selective determinism** — enforce determinism only when needed

### 8.7.4 Caching as a Training Enabler

CacheRL [62] reveals a novel behavioural dimension: caching changes how agents are **trained**:
- Cached tool rollouts enable RL training with 100× cost reduction
- Three-tier fuzzy cache (exact, fuzzy, best-effort) introduces varying fidelity levels
- Cache-tier-aware rewards prevent the model from being penalized for cache limitations
- **Behavioural implication**: agents trained with cached rollouts may learn different strategies than those trained with live tool execution, particularly around tool call frequency and retry behaviour
- This opens a new research direction: how does training-time caching affect agent behaviour at inference time?

### 8.7.5 Temporal Awareness in Agent Caching

The temporal semantic caching work [63] identifies a critical behavioural gap:
- Agents operating in real-time environments (industrial assets, live data) need **temporal awareness** in caching
- Pure semantic caching returns stale results for time-sensitive queries
- The temporal classifier (Volatile, Static, Relative, Anchored) creates **behavioural routing**: agents bypass cache for live state, use cache for static queries
- **Implication**: agent caching systems must understand the temporal semantics of queries, not just their semantic similarity

---

## 8.8 Summary

Caching profoundly influences agentic system behaviour:

1. **Architecture**: Caching constraints (sticky routing, stable prefixes) shape agent design decisions [18, 41]
2. **Planning**: Plan caching changes agents from plan-generators to plan-adapters [19]
3. **Tool usage**: Caching reduces the marginal cost of tool calls, potentially encouraging more thorough exploration [18]
4. **Context management**: Caching creates tension with context management techniques (summarization, pruning) [18]
5. **Multi-turn continuity**: CacheTTL enables more deliberate tool execution by removing the eviction penalty [21]
6. **Quality**: Naive caching degrades quality (cache-hit accuracy < cache-miss accuracy); proper design maintains consistency [19]
7. **Determinism**: Caching introduces non-determinism that can cascade in reasoning models [33, 34, 67]
8. **Training**: Cached rollouts enable RL training at 100× lower cost, potentially shaping agent strategies [62]
9. **Temporal awareness**: Real-time agents need temporal classification to avoid stale cache hits [63]

The key insight is that **caching is not a transparent optimization** — it actively shapes how agents behave, plan, interact with tools, and are trained. System designers must consider these behavioural effects, not just the cost and latency metrics.

---

## References

- [4] Gao et al., "Rethinking Key-Value Cache Compression Techniques for Large Language Model Serving," arXiv:2503.24000, 2025.
- [11] Hooper et al., "KVQuant: Towards 10 Million Context Length LLM Inference with KV Cache Quantization," arXiv:2401.18079, 2024.
- [14] Wang et al., "SAGE-KV: Self-Attention Guided KV Cache Eviction," arXiv:2503.08879, 2025.
- [15] "Inference-Time Hyper-Scaling with KV Cache Compression (DMS)," arXiv:2506.05345, 2025.
- [16] "AQUA-KV: Adaptive Key-Value Quantization for Large Language Models," arXiv:2501.19392, 2025.
- [18] "Don't Break the Cache: An Evaluation of Prompt Caching for Long-Horizon Agentic Tasks," arXiv:2601.06007, 2026.
- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [20] Pan et al., "KVFlow: Efficient Prefix Caching for Accelerating LLM-Based Multi-Agent Workflows," arXiv:2507.07400, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [23] "LLM-dCache: Improving Tool-Augmented LLMs with GPT-Driven Localized Data Caching," arXiv:2406.06799, 2024.
- [24] Schroeder et al., "vCache: Verified Semantic Prompt Caching," arXiv:2502.03771, 2025.
- [31] Dai et al., "Statistical Independence Aware Caching for LLM Workflows," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver: A Modular Framework for Efficient, Affordable, and Reproducible LLM Inference," Findings of EMNLP 2025.
- [33] Yuan et al., "Understanding and Mitigating Numerical Sources of Nondeterminism in LLM Inference," arXiv:2506.09501, 2025.
- [35] "LLM-42: Enabling Determinism in LLM Inference with Verified Speculation," arXiv:2601.17768, 2026.
- [41] "HyDRA: Hybrid Dynamic Routing Architecture for Heterogeneous LLM Pools," arXiv:2605.17106, 2026.
- [62] "CacheRL: Multi-Turn Tool-Calling Agents via Cached Rollouts and Hybrid Reward," arXiv:2606.14179, 2026.
- [63] "Evaluating Temporal Semantic Caching and Workflow Optimization in Agentic Plan-Execute Pipelines," arXiv:2605.20630, 2026.
- [67] He et al., "Defeating Nondeterminism in LLM Inference," Thinking Machines Lab, 2025.
