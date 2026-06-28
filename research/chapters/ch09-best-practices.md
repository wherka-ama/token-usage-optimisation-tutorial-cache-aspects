# Chapter 9: Best Practices and Anti-Patterns

## 9.1 Introduction

This chapter synthesizes the evidence from all preceding chapters into actionable best practices and identifies anti-patterns to avoid. The recommendations are grounded in the academic literature, production evidence, and the experimental harness findings.

---

## 9.2 The Golden Rule

**Stable content goes FIRST. Volatile content goes LAST.**

This is the single most important principle, confirmed by every caching study:

> *"Caching is a prefix game. Any change at the start invalidates everything that follows."* — Experimental harness findings

> *"The most effective strategy is to ensure that only stable, reusable content is cached."* — "Don't Break the Cache" [18]

---

## 9.3 Best Practices

### 9.3.1 Prompt Structure

| Practice | Evidence |
|----------|----------|
| Place system prompt at the very top, identical across calls | [18]: System prompt is the primary cost driver |
| Place tool definitions after system prompt, keep static | [18]: Tool definitions are stable, cached prefix |
| Place user query at the end | Prefix caching preserves all prior content |
| If dynamic values are needed in system prompt, place at the end of the prompt | [18]: "maximizes the cacheable prefix" |
| Pin model versions (e.g., `claude-sonnet-4-20250514`) | Model switches invalidate cache [18, 41] |

### 9.3.2 Multi-Turn Conversations

| Practice | Evidence |
|----------|----------|
| Append new messages to history; never edit or rephrase prior messages | Any change invalidates cache from that point |
| Stay on one model per session | [41]: HyDRA uses sticky routing to preserve cache |
| Use cache-preserving routing (invoke router only on turn 1) | [41]: 7-20% COGS reduction in production |
| Be cautious with summarization/pruning — it breaks cached representations | [18]: "making tool call caching counterproductive" |

### 9.3.3 Tool and MCP Management

| Practice | Evidence |
|----------|----------|
| Keep tool schemas static and stable | [18]: Static tools become cached prefix |
| Avoid dynamic tool generation per call | [18]: Dynamic tool lists invalidate prefix |
| Consider code generation instead of dynamic function calling for dynamic capabilities | [18]: Avoids cache-breaking tool definition changes |
| Maintain a fixed set of general-purpose, reusable functions | [18]: Ensures stable cached prefix |

### 9.3.4 Caching Strategy Selection

| Practice | Evidence |
|----------|----------|
| Use system-prompt-only caching as default for agentic workloads | [18]: Most consistent benefits across cost and latency |
| Exclude dynamic tool results from caching | [18]: Avoids cache write overhead for non-reusable content |
| Avoid naive full-context caching for agentic tasks | [18]: Can paradoxically increase latency |
| Use verified semantic caching (vCache) if semantic caching is needed | [24]: Provides formal error rate guarantees |
| Use agentic plan caching for Plan-Act agents | [19]: 46.62% cost reduction, consistent accuracy |

### 9.3.5 Serving System Configuration

| Practice | Evidence |
|----------|----------|
| Use PagedAttention/vLLM for memory-efficient serving | [6]: Near-zero memory waste, 2-4x throughput |
| Use RadixAttention/SGLang for automatic prefix reuse | [7]: Zero-configuration prefix caching, 5x faster |
| Use LMCache for enterprise-scale cross-engine sharing | [8]: 15x throughput, tiered storage |
| Use CacheTTL for multi-turn agent workloads | [21]: 8x JCT improvement |
| Use KVFlow for multi-agent workflows | [20]: 2.19x speedup for concurrent workflows |
| Avoid context truncation — it halves prefix cache hit ratio | [8]: Production insight from LMCache |

### 9.3.6 Reproducibility and Statistical Integrity

| Practice | Evidence |
|----------|----------|
| Use namespace-aware caching for evaluation (Cache Saver) | [32]: Ensures i.i.d. responses within namespaces |
| Use statistical independence-aware caching for retries (Mnimi) | [31]: Preserves correctness of probabilistic workflows |
| Be aware that prefix caching introduces non-determinism | [34]: "continuous batching, chunk prefilling, or prefix caching might lead to non-deterministic behavior" |
| Use LayerCast for numerical stability when reproducibility matters | [33]: Below 3.4% divergence across configurations |
| Consider batch-invariant kernels for deterministic inference | [67]: Eliminates batch-dependent reduction orders |
| Be aware of prefill-decode invariance gap for prefix cache sharing | [35]: LLM-42 does not support cross-turn prefix cache sharing due to this gap |
| Report system configuration (batch size, GPU count, precision) with results | [33]: These affect reproducibility |

### 9.3.7 KV Cache Compression

| Practice | Evidence |
|----------|----------|
| Use quantization for memory-constrained long-context scenarios | [11]: 3.7x compression, <0.1 perplexity degradation |
| Use KIVI for tuning-free 2-bit quantization | [59]: Per-channel Key, per-token Value, hardware-friendly |
| Allocate more bits to Keys than Values | [17]: 4-bit Key + 2-bit Value = 75.2% accuracy vs. 54.7% reversed |
| Use adaptive budget allocation across attention heads | [12]: Ada-KV improves post-eviction quality |
| Use observation-window-based eviction (SnapKV) for prompt compression | [53]: Identifies important tokens before generation |
| Use pyramidal budget allocation across layers (PyramidInfer) | [54]: Deeper layers have more redundancy |
| Monitor for output length increases after compression | [4]: Compression may lead to longer outputs |
| Be cautious with eviction in production — not prevalent despite research advances | [4]: Implementation gaps exist |

### 9.3.8 Security

| Practice | Evidence |
|----------|----------|
| Isolate KV caches across tenants in multi-tenant serving | [37]: KV cache sharing enables prompt reconstruction |
| Be aware of timing side channels from cache hit/miss differences | [39]: Cache hits have consistently fast latency, misses grow with document length |
| Use KV-Cloak or similar defense mechanisms for sensitive deployments | [38]: Reversible matrix-based obfuscation thwarts reconstruction attacks |
| Use KV-Shield for on-device inference security | [40]: Permutation-based encryption in TEE |

### 9.3.9 Agentic Workflow Caching

| Practice | Evidence |
|----------|----------|
| Use workflow-aware eviction (KVFlow/Pythia/PBKV) for multi-agent systems | [20, 60, 61]: LRU fails for agentic workloads |
| Use TTL-based KV retention for tool call pauses | [21]: CacheTTL achieves 8x JCT improvement |
| Use temporal classification for time-sensitive agent queries | [63]: Volatile/Static/Relative/Anchored routing |
| Use cached rollouts for RL training of tool-calling agents | [62]: 100x cost reduction |
| Use hierarchical caching (plan + tool + response) for complex workflows | [64]: Multi-level architecture |
| Use proactive cache staging for predictable workflows | [60]: Pythia hides prefill latency |
| Use conservative prefetching for dynamic workflows | [61]: PBKV never backfires under poor predictions |

---

## 9.4 Anti-Patterns

### 9.4.1 Cache Killers

| Anti-Pattern | Why It Fails | Evidence |
|-------------|-------------|----------|
| **Timestamp at prompt start** | Invalidates entire prefix | Experimental harness Exp 3 |
| **Session ID in system prompt** | Changes every call | [18] |
| **Dynamic tool list per call** | Tool definitions change | [18] |
| **Switching models mid-session** | Different cache namespace | [18, 41] |
| **Editing/rephrasing prior messages** | Invalidates cache from change point | Experimental harness Exp 6 |
| **Dynamic hook context injection** | CLI hooks inject dynamic content at start | Experimental harness Exp 13 |
| **Using generic model tags (e.g., `latest`)** | May silently switch model versions | Experimental harness Exp 7 |

### 9.4.2 Semantic Caching Anti-Patterns

| Anti-Pattern | Why It Fails | Evidence |
|-------------|-------------|----------|
| **Using static global thresholds** | No correctness guarantees, unpredictable error rates | [24] |
| **Semantic caching for agentic applications** | False-positive hits, data-dependent outputs | [19] |
| **Caching raw responses for agents** | Outputs depend on external data, not just prompts | [19] |
| **Ignoring out-of-distribution inputs** | Static thresholds fail on novel queries | [24] |

### 9.4.3 System Design Anti-Patterns

| Anti-Pattern | Why It Fails | Evidence |
|-------------|-------------|----------|
| **LRU eviction for agentic workloads** | Does not anticipate future agent usage | [20] |
| **End-of-turn KV cache eviction for agents** | Breaks multi-turn continuity | [21] |
| **Context truncation to save memory** | Halves prefix cache hit ratio | [8] |
| **Naive full-context caching for agents** | Cache write overhead for non-reusable content | [18] |
| **Disabling dynamic batching for determinism** | Severely degrades throughput | [35] |
| **Ignoring tail latency** | Cache misses create P99 spikes | [48] |

### 9.4.4 Reproducibility Anti-Patterns

| Anti-Pattern | Why It Fails | Evidence |
|-------------|-------------|----------|
| **Naive response caching for Pass@k evaluation** | Breaks statistical independence | [31, 32] |
| **Reusing cached responses for retry loops** | Retries return same failed response | [31] |
| **Not reporting system configuration** | Results are not reproducible | [33] |
| **Assuming temperature=0 means deterministic** | Up to 15% accuracy variation | [34] |

---

## 9.5 The Cache Effectiveness Checklist

1. **[ ]** Is my system prompt identical across calls?
2. **[ ]** Are my tool definitions at the beginning and static?
3. **[ ]** Did I remove dynamic data (dates, session IDs, random seeds) from the prefix?
4. **[ ]** Am I within the TTL window? (Anthropic: ~5m, OpenAI: 5-10m)
5. **[ ]** Am I using a model that supports caching?
6. **[ ]** Am I appending (not rewriting) in multi-turn conversations?
7. **[ ]** Am I staying on one model per session?
8. **[ ]** Is my cache strategy appropriate for my workload? (system-prompt-only for agents)
9. **[ ]** Are dynamic tool results excluded from caching?
10. **[ ]** If using semantic caching, do I have error rate guarantees?
11. **[ ]** If reproducibility matters, am I using namespace-aware caching?
12. **[ ]** Am I monitoring cache hit rate and tail latency?
13. **[ ]** Is my eviction policy appropriate for my workload? (workflow-aware for agents)
14. **[ ]** Are KV caches isolated across tenants?

---

## 9.6 Measuring Success

### 9.6.1 Key Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| `cache_read_input_tokens` | Tokens served from cache (HIT) | Maximize |
| `cache_creation_input_tokens` | Tokens written to cache (WRITE) | Minimize relative to reads |
| `overall_cache_hit_rate` | Fraction of input tokens from cache reads | >50% for repeated prompts, >80% for multi-turn |
| `TTFT` (time-to-first-token) | Latency to first generated token | Minimize, monitor P99 |
| `effective_cost_per_token` | Actual cost accounting for cache discounts | Minimize |
| `cache_hit_accuracy` | Quality of responses on cache hits | Equal to cache-miss accuracy |

### 9.6.2 Monitoring Strategy

- Track cache hit rate over time — declining rates indicate prefix instability
- Monitor P99 TTFT — cache misses create tail latency spikes [48]
- Compare cache-hit vs. cache-miss accuracy — divergence indicates quality degradation [19]
- Track cache write/read ratio — high write ratio indicates low reuse
- Monitor memory pressure — KV cache growth can exceed GPU capacity [8]

---

## 9.7 Summary

The best practices for LLM caching can be summarized in five principles:

1. **Stable first, volatile last** — structure prompts to maximize cacheable prefix
2. **System-prompt-only for agents** — avoid caching dynamic content
3. **Use verified caching** — formal guarantees over heuristic thresholds
4. **Workflow-aware eviction** — replace LRU with usage-pattern-aware policies
5. **Preserve statistical integrity** — use namespace-aware caching for evaluation

The anti-patterns to avoid:
1. **Dynamic content in prefixes** — timestamps, session IDs, dynamic tools
2. **Naive semantic caching** — no guarantees, false positives in agentic contexts
3. **Context management that breaks cache** — summarization, pruning
4. **Assuming determinism** — caching optimizations introduce non-determinism
5. **Ignoring security** — KV cache sharing enables side-channel attacks

---

## References

- [4] Gao et al., "Rethinking Key-Value Cache Compression Techniques," arXiv:2503.24000, 2025.
- [6] Kwon et al., "PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache," arXiv:2510.09665, 2025.
- [11] Hooper et al., "KVQuant," arXiv:2401.18079, 2024.
- [12] Xing et al., "Ada-KV," arXiv:2407.11550, 2024.
- [17] "KV-AdaQuant," arXiv:2502.15075, 2025.
- [18] "Don't Break the Cache," arXiv:2601.06007, 2026.
- [19] "Agentic Plan Caching," arXiv:2506.14852, 2025.
- [20] Pan et al., "KVFlow," arXiv:2507.07400, 2025.
- [21] "CacheTTL," arXiv:2511.02230, 2025.
- [24] Schroeder et al., "vCache," arXiv:2502.03771, 2025.
- [31] Dai et al., "Mnimi," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver," Findings of EMNLP 2025.
- [33] Yuan et al., "Numerical Nondeterminism," arXiv:2506.09501, 2025.
- [34] "Non-Determinism of 'Deterministic' LLM Settings," arXiv:2408.04667, 2024.
- [35] "LLM-42," arXiv:2601.17768, 2026.
- [37] Wu et al., "PROMPTPEEK," NDSS 2025.
- [38] Luo et al., "Shadow in the Cache," arXiv:2508.09442, 2025.
- [39] "Timing Side Channels," arXiv:2409.20002, 2024.
- [41] "HyDRA," arXiv:2605.17106, 2026.
- [48] "Tail-Optimized Caching," arXiv:2510.15152, 2025.
- [53] Li et al., "SnapKV," arXiv:2404.14469, 2024.
- [54] "PyramidInfer," arXiv:2405.12532, 2024.
- [59] Liu et al., "KIVI," arXiv:2402.02750, 2024.
- [60] "Pythia," arXiv:2604.25899, 2026.
- [61] "PBKV," arXiv:2605.06472, 2026.
- [62] "CacheRL," arXiv:2606.14179, 2026.
- [63] "Temporal Semantic Caching," arXiv:2605.20630, 2026.
- [64] "Hierarchical Caching for Agentic Workflows," MAKE 2026.
- [67] He et al., "Defeating Nondeterminism in LLM Inference," Thinking Machines Lab, 2025.
