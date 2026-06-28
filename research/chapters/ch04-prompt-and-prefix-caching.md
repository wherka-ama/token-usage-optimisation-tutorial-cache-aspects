# Chapter 4: Prompt and Prefix Caching

## 4.1 Introduction

While the KV cache (Chapter 3) operates at the token level within a single request, **prompt caching** and **prefix caching** extend KV cache reuse across requests. These mechanisms exploit the observation that many LLM requests share common prefixes — system prompts, tool definitions, conversation history, or document context. This chapter examines the mechanisms, provider implementations, and empirical evidence for prompt/prefix caching.

---

## 4.2 Mechanism

### 4.2.1 Prefix-Based KV Cache Reuse

When two requests share an identical token prefix, the KV cache computed for that prefix during the first request's prefill can be reused for the second request. This eliminates redundant prefill computation for the shared portion.

The key insight is that transformer attention processes tokens sequentially, so the KV state for tokens *x₁...x_k* is independent of tokens *x_{k+1}...x_n*. If request A = [prefix | suffix_A] and request B = [prefix | suffix_B], the KV cache for [prefix] is identical in both cases and can be shared.

### 4.2.2 Cache Line Granularity

Providers and serving systems cache at different granularities:
- **Token-level**: Individual token KV pairs (theoretical minimum)
- **Block-level**: Fixed-size blocks of tokens (e.g., 16 tokens in vLLM's PagedAttention [6])
- **Segment-level**: Logical prompt segments (system prompt, tools, conversation)
- **Radix tree nodes**: Variable-length prefixes in SGLang's RadixAttention [7]

### 4.2.3 Cache Write vs. Cache Read

Prompt caching involves two operations with different cost profiles:
- **Cache write (creation)**: First request with a new prefix computes and stores KV tensors. This is equivalent to normal prefill cost (or slightly higher due to storage overhead).
- **Cache read (hit)**: Subsequent requests with the same prefix load cached KV tensors, skipping prefill computation. This is priced at 10-50% of full input token cost.

The economics depend on the **cache hit rate** — the fraction of requests that benefit from cache reads vs. cache writes.

---

## 4.3 Provider Implementations

### 4.3.1 Anthropic

Anthropic offers explicit prompt caching with the following characteristics:
- **Cache reads**: ~10% of base input token price (90% discount)
- **Cache writes**: ~125% of base input token price (25% premium for first write)
- **Minimum cacheable length**: 1,024 tokens (Claude 3.5 Sonnet)
- **TTL**: ~5 minutes (refreshed on each cache hit)
- **Explicit control**: Developers mark cacheable segments with `cache_control` breakpoints
- **Reported results**: 90% cost reduction and 85% latency reduction for long prompts [18]

### 4.3.2 OpenAI

OpenAI provides automatic prompt caching:
- **Cache reads**: ~50% of base input token price (50% discount)
- **Automatic**: No explicit cache directives needed; caching triggers when prompts exceed a threshold
- **TTL**: 5-10 minutes (provider-managed)
- **Minimum**: ~1,024 tokens for caching to activate
- **Reported results**: 50% cost savings on cached input tokens [18]

### 4.3.3 Google (Gemini)

Google's Gemini models also support prompt caching:
- **Cache reads**: Discounted rate (provider-dependent)
- **Explicit context caching API**: Developers can pre-cache content and reference it
- **TTL**: Configurable, with longer retention options
- **Reported results**: 28-41% cost reduction depending on cache strategy [18]

### 4.3.4 Provider Comparison

The "Don't Break the Cache" evaluation [18] provides the first systematic cross-provider comparison:

| Metric | GPT-5.2 | Claude Sonnet 4.5 | GPT-4o | Gemini 2.5 Pro |
|--------|---------|-------------------|--------|-----------------|
| Cost reduction | 79-81% | 78-79% | 46-48% | 28-41% |
| TTFT improvement | 13.0% | 20.9-22.9% | 28-31% | 6.1% |
| Best cache strategy | Exclude tool results | Full context | System prompt only | System prompt only |

Key finding: *"The consistency of cost savings across cache strategies suggests that the primary driver of cost reduction is caching the large system prompt, which remains stable across all requests within a session."* [18]

---

## 4.4 Caching Strategies for Agentic Workloads

### 4.4.1 Three Cache Strategies

The "Don't Break the Cache" evaluation [18] compares three strategies:

1. **Full Context Caching**: Cache the entire context (system prompt + conversation + tool results)
   - Maximizes potential cache hits
   - But: dynamic tool results trigger cache writes for content that won't be reused
   - Can **paradoxically increase latency** due to cache write overhead

2. **System Prompt Only Caching**: Cache only the stable system prompt
   - Most consistent benefits across both cost and latency
   - Avoids overhead from caching dynamic content
   - Recommended as the default strategy

3. **Exclude Tool Results Caching**: Cache system prompt + conversation but exclude tool results
   - Good balance: caches stable and semi-stable content
   - Avoids the most volatile component (tool results)
   - Best for GPT-5.2 (13.0% TTFT improvement)

### 4.4.2 Strategic Cache Boundary Control

The key insight from [18] is that **strategic cache boundary control outperforms naive full-context caching**:

> *"Providers abstract much of the caching mechanism, automatically triggering cache creation when token thresholds are exceeded. Without explicit boundary control, this automatic behavior can cache dynamic, session-specific content that will not be reused, leading to cache write overhead without corresponding read benefits."* [18]

Practical guidance:
- **Do**: Place stable content (system prompt, tool definitions) at the beginning
- **Do**: Place dynamic content (timestamps, session IDs, user-specific data) at the end
- **Don't**: Include dynamic values in the system prompt
- **Don't**: Cache tool results that produce variable outputs
- **Don't**: Use dynamic function calling where tool definitions change between requests

### 4.4.3 Tool Call Caching Considerations

For long-running agentic sessions with 30-50+ tool calls:
- Cache creation incurs overhead on the first request, only amortized if subsequent requests benefit
- For tool calls producing variable results, caching provides no benefit and may introduce overhead
- Context management strategies (summarizing, pruning old tool calls) **break cached representations**, making tool call caching counterproductive
- The emerging pattern: **maintain a stable system prompt** (cached) while treating tool calls as **dynamic content** (not cached) [18]

---

## 4.5 Serving System Implementations

### 4.5.1 vLLM: Automatic Prefix Caching

vLLM implements automatic prefix caching on top of PagedAttention [6]:
- KV cache blocks are shared across requests with identical prefixes
- Block-level reference counting with Copy-on-Write
- No explicit cache directives needed — prefix matching is automatic
- Block size trade-off: smaller blocks = better sharing but more metadata overhead

### 4.5.2 SGLang: RadixAttention

SGLang's RadixAttention [7] uses a radix tree for prefix management:
- **Automatic detection**: The radix tree naturally identifies shared prefixes
- **Variable-length matching**: Unlike block-based approaches, matches can be at any token boundary
- **Zero configuration**: No cache directives or block size tuning needed
- **Tree-structured cache**: Supports branching (e.g., multiple continuations of the same prefix)
- **Result**: Up to 5× faster inference for workloads with shared prefixes

### 4.5.3 KVFlow: Workflow-Aware Prefix Caching

KVFlow [20] extends prefix caching for multi-agent workflows:
- **Agent Step Graph**: Abstracts the agent execution schedule, modeling which agents will be activated next
- **Steps-to-execution value**: Estimates temporal proximity of future agent activation
- **Workflow-aware eviction**: Replaces LRU with eviction guided by the step graph
- **Overlapped prefetching**: Proactively loads KV tensors from CPU to GPU in background threads
- **Result**: Up to 1.83× speedup for single workflows, 2.19× for concurrent workflows vs. SGLang

### 4.5.4 LMCache: Enterprise-Scale Prefix Reuse

LMCache [8] enables prefix reuse at enterprise scale:
- Cross-request prefix reuse via tiered storage (GPU → CPU → SSD → remote)
- Cross-engine sharing (vLLM ↔ SGLang)
- Modular connector architecture decoupled from inference engine evolution
- **Production insight**: Context truncation reduces prefix cache hit ratio by half

---

## 4.6 Ablation Evidence

### 4.6.1 Prompt Size Ablation

The "Don't Break the Cache" ablation [18] across prompt sizes (500-50,000 tokens) shows:
- **Universal linear cost benefits** after the provider's caching token minimum
- Larger system prompts → greater absolute cost savings
- Below the minimum threshold, caching provides no benefit

### 4.6.2 Tool Call Count Ablation

Across tool call counts (3-50):
- Cost benefits scale linearly with tool call count
- TTFT benefits also scale, though with more variance
- Provider-specific discrepancies emerge at high tool call counts

### 4.6.3 Provider-Specific Variability

The evaluation reveals significant provider implementation differences:
- GPT-4o: Full context caching shows 8.8% TTFT **regression** (overhead negates benefits)
- Claude Sonnet 4.5: Consistent TTFT improvement across all strategies (20.9-22.9%)
- This indicates providers handle dynamic content caching differently

---

## 4.7 The Tail-Optimized Caching Perspective

Tail-Optimized Caching [48] examines caching from the perspective of **tail latency** rather than average latency:

- Standard prefix caching optimizes for average-case performance
- But tail latency (P99) is often more critical for user experience
- Proposes caching strategies that specifically target tail-latency reduction
- Highlights that cache miss scenarios can create latency spikes that dominate user-perceived performance

---

## 4.8 Summary

Prompt and prefix caching represents the most immediately impactful caching optimization for LLM applications, offering:

- **41-80% cost reduction** across major providers [18]
- **13-31% TTFT improvement** [18]
- **Up to 15× throughput improvement** in serving systems [8]

The key principles are:
1. **Stable content first, dynamic content last** — the golden rule of prefix caching
2. **System prompt only caching** is the most consistently beneficial strategy
3. **Strategic boundary control** outperforms naive full-context caching
4. **Workflow-aware eviction** (KVFlow) outperforms LRU for agentic workloads
5. **Cross-engine sharing** (LMCache) enables enterprise-scale cache reuse

The main trade-off is between caching more content (higher potential hit rate) and caching only stable content (avoiding write overhead for dynamic content that won't be reused).

---

## References

- [6] Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang: Efficient Execution of Structured Language Model Programs," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference," arXiv:2510.09665, 2025.
- [18] "Don't Break the Cache: An Evaluation of Prompt Caching for Long-Horizon Agentic Tasks," arXiv:2601.06007, 2026.
- [20] Pan et al., "KVFlow: Efficient Prefix Caching for Accelerating LLM-Based Multi-Agent Workflows," arXiv:2507.07400, 2025.
- [48] "Tail-Optimized Caching for LLM Inference," arXiv:2510.15152, 2025.
