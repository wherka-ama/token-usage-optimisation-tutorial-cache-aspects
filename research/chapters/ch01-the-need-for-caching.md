# Chapter 1: The Need for Caching in LLM Systems

## 1.1 Introduction

Large Language Models (LLMs) have become the backbone of modern AI applications, from chatbots and coding assistants to autonomous agents and research tools. However, the computational and financial costs of LLM inference present significant challenges at scale. Caching — the storage and reuse of previously computed results — has emerged as one of the most impactful optimization techniques for LLM systems, offering reductions in latency, cost, and resource consumption.

This chapter establishes the fundamental motivation for caching in LLM systems, examining the principles, advantages, and trade-offs that underpin all subsequent caching strategies discussed in this report.

---

## 1.2 The Computational Problem

### 1.2.1 Autoregressive Generation and Quadratic Complexity

Transformer-based LLMs generate text autoregressively — one token at a time, each conditioned on all previously processed tokens. At each decoding step *t*, the model computes self-attention over the entire sequence, requiring Key and Value matrices for all prior tokens. Without caching, this means recomputing attention values for every token at every step, resulting in **O(n²)** time and space complexity that grows quadratically with sequence length [1].

The KV cache addresses this by storing the Key and Value matrices computed during previous decoding steps. At step *t*, only the Key and Value for the new token *x_t* need to be computed; the cached matrices for tokens *x_1* through *x_{t-1}* are reused. This reduces the per-step complexity from quadratic to **linear** in sequence length [1].

### 1.2.2 Memory as the Bottleneck

While the KV cache eliminates redundant computation, it introduces a new challenge: **memory consumption**. The KV cache grows linearly with sequence length and number of layers. For a model like LLaMA-13B, a single sequence's KV cache can consume up to 1.7 GB [6]. At production scale, with hundreds or thousands of concurrent requests, the KV cache can consume the majority of available GPU memory.

Profiling results from the PagedAttention work show that in existing systems, only **20.4%–38.2%** of KV cache memory is used to store actual token states — the rest is wasted to fragmentation and over-reservation [6]. This inefficiency directly limits batch size and throughput.

### 1.2.3 The Cost Dimension

LLM inference is not just a technical challenge — it is an economic one. Major providers charge per token:
- Input tokens: $0.15–$5.00 per million (model-dependent)
- Output tokens: $0.60–$15.00 per million (model-dependent)

For agentic workloads that span dozens of API calls with large context windows, costs accumulate rapidly. The "Don't Break the Cache" evaluation found that agentic sessions with 10,000-token system prompts and 30–50 tool calls can cost significant amounts per session without caching [18]. Caching reduces these costs by 41–80% across providers.

---

## 1.3 Principles of Caching in LLM Systems

### 1.3.1 The Fundamental Trade-off

All caching systems operate on a fundamental trade-off: **spend resources to store computed results now, to save recomputation later**. The value of this trade-off depends on:

- **Reuse frequency**: How often the cached result is accessed
- **Storage cost**: Memory/storage required to maintain the cache
- **Recomputation cost**: Compute time and expense saved on cache hits
- **Staleness risk**: Whether cached results remain valid over time

In LLM systems, these factors manifest uniquely:
- KV cache reuse is guaranteed within a single generation (every token reuses all prior tokens' KV pairs)
- Prefix reuse is common across requests that share system prompts, tool definitions, or conversation history
- Semantic reuse (similar but not identical prompts) is possible but introduces correctness risks

### 1.3.2 Levels of Caching

Caching in LLM systems operates at multiple levels, each with distinct characteristics:

| Level | What is Cached | Granularity | Transferability |
|-------|---------------|-------------|-----------------|
| **Token-level (KV Cache)** | Key-Value tensors per token | Per-token, per-layer | Model-specific, not transferable |
| **Prefix-level (Prompt Caching)** | KV tensors for shared prompt prefixes | Multi-token blocks | Same model, same prefix |
| **Response-level (Semantic Cache)** | Complete input-output pairs | Full request | Cross-model possible |
| **Plan-level (Agentic Cache)** | Structured execution plans | Task-level | Cross-task, adapted |
| **System-level (Serving Cache)** | KV cache management, scheduling | Infrastructure | Cross-request, cross-engine |

### 1.3.3 The Prefix Principle

A unifying principle across most LLM caching mechanisms is **prefix-based matching**. Because transformer attention processes tokens sequentially, the KV cache for a prompt prefix is independent of what follows. This means:

1. If two requests share an identical prefix, the KV cache for that prefix can be reused
2. Any change to the prefix invalidates all cached state from that point onward
3. Stable content should be placed at the **beginning** of prompts; dynamic content at the **end**

This principle is confirmed by both the KV cache survey [1] and the "Don't Break the Cache" evaluation [18], which found that strategic placement of stable content at the prefix maximizes cache hit rates.

---

## 1.4 Advantages of Caching

### 1.4.1 Latency Reduction

Caching directly reduces the prefill computation — the initial processing of input tokens before generation begins. For long prompts, prefill can dominate total latency. Cache hits skip the recomputation of cached tokens' KV pairs, reducing time-to-first-token (TTFT).

- **"Don't Break the Cache"** [18]: TTFT improvements of 13–31% across providers
- **LMCache** [8]: Up to 15× throughput improvement for multi-round QA workloads
- **SGLang/RadixAttention** [7]: Up to 5× faster inference for workloads with shared prefixes
- **Anthropic prompt caching**: 85% latency reduction for long prompts (reported by Introl, 2025)

### 1.4.2 Cost Reduction

Cache hits are priced at a fraction of full input token cost:
- **Anthropic**: Cache reads cost ~10% of full input price (90% discount)
- **OpenAI**: Cache reads cost ~50% of full input price (50% discount)
- **"Don't Break the Cache"** [18]: 41–80% API cost reduction across providers
- **Agentic Plan Caching** [19]: 46.62% average cost reduction for agentic workloads
- **Cache Saver** [32]: ~25% average cost reduction, up to 60% for benchmarking/ablation

### 1.4.3 Throughput Improvement

By reducing per-request computation, caching allows serving systems to process more requests concurrently:
- **vLLM/PagedAttention** [6]: 2–4× throughput improvement through efficient KV cache memory management
- **LMCache** [8]: Up to 15× throughput improvement via cross-engine KV cache sharing
- **CacheTTL** [21]: Over 8× improvement in average job completion time for multi-turn agents

### 1.4.4 Resource Efficiency

Caching reduces GPU memory pressure, energy consumption, and carbon footprint:
- **Cache Saver** [32]: ~35% CO₂ reduction on average, up to 60% for benchmarking tasks
- **KVQuant** [11]: 3.7× KV cache compression, enabling 1M token context on a single A100
- **PagedAttention** [6]: Near-zero memory waste (under 4%) vs. 60–80% waste in prior systems

### 1.4.5 Reproducibility Enhancement

Caching can improve reproducibility by storing and replaying exact responses:
- **Cache Saver** [32]: Namespace-aware cache ensures i.i.d. responses within namespaces and reproducibility across namespaces
- **Mnimi** [31]: Statistical independence-aware caching preserves correctness of probabilistic workflows while enabling deterministic debugging

---

## 1.5 Disadvantages and Trade-offs

### 1.5.1 Memory Overhead

The KV cache itself is a major memory consumer. As context windows grow from thousands to millions of tokens, KV cache memory can exceed GPU capacity:
- LLaMA-7B with 128K context: ~13 GB KV cache (fp16)
- LLaMA-7B with 1M context: ~100 GB KV cache (fp16) [11]

This necessitates offloading to CPU memory, SSDs, or remote storage, introducing latency for cache retrieval [8].

### 1.5.2 Correctness Risks in Semantic Caching

Semantic caches that return responses for "similar" (not identical) prompts introduce fundamental correctness risks:
- **vCache** [24]: Static thresholds "do not give formal correctness guarantees, can result in unexpected error rates, and lead to suboptimal cache hit rates"
- Unless threshold is 1.0 (exact match), there is always a risk of returning incorrect responses
- **Agentic Plan Caching** [19]: Semantic caching suffers from "high rate of false-positive cache hits, leading to substantial performance degradation"

### 1.5.3 Non-determinism and Reproducibility Challenges

Caching mechanisms themselves can introduce non-determinism:
- **Non-Determinism of "Deterministic" LLM Settings** [34]: "Engineering optimizations to run LLMs faster, such as continuous batching, chunk prefilling, or prefix caching, might lead to non-deterministic behavior"
- **Understanding and Mitigating Numerical Sources of Nondeterminism** [33]: Up to 9% accuracy variation and 9,000 token response length differences due to GPU count, type, and batch size changes
- Prefix caching changes batch composition, which changes floating-point reduction orders, which changes outputs

### 1.5.4 Security and Privacy Risks

KV cache sharing in multi-tenant environments creates side-channel attack vectors:
- **PROMPTPEEK** [37]: KV cache sharing allows "unauthorized reconstruction of user prompts"
- **Timing side channels** [39]: Cache hit/miss timing differences can reveal whether specific content was cached by another user
- **Shadow in the Cache** [38]: Three attack vectors (Inversion, Collision, Injection) can reconstruct sensitive inputs from KV cache

### 1.5.5 Complexity and Maintenance

Caching adds system complexity:
- Cache invalidation strategies must be carefully designed
- Eviction policies (LRU, LFU) "do not align with LLM patterns, leading to suboptimal performance" [1]
- Multi-level cache hierarchies (GPU → CPU → SSD → remote) require careful orchestration [8]
- Provider-specific caching APIs have different thresholds, TTLs, and behaviors [18]

### 1.5.6 Staleness and Invalidation

Cached results can become stale when:
- Underlying data changes (RAG scenarios where source documents are updated)
- Model versions change (KV caches are model-specific) [19]
- Tool definitions change (MCP servers connect/disconnect) [18]
- Time-sensitive information is embedded in prompts (timestamps, session IDs)

---

## 1.6 When Caching Is Most Beneficial

Research identifies several workload patterns where caching provides the greatest benefit:

1. **Multi-turn conversations**: Each turn appends to the prior prefix, preserving cache hits on all prior content [18, 21]
2. **Shared system prompts**: Large, stable system prompts (10K+ tokens) are the primary cost driver and ideal cache candidates [18]
3. **Repeated tool definitions**: Static tool schemas become part of the cached prefix [18]
4. **RAG workloads**: Document chunks shared across queries can have their KV caches reused [8, 10]
5. **Benchmarking and ablation studies**: 50% prompt redundancy across reasoning strategies [32]
6. **Multi-agent workflows**: Agents sharing common prompts or plan structures [19, 20]

---

## 1.7 Summary

Caching is not merely an optimization in LLM systems — it is a **first-order design concern** that affects latency, cost, throughput, memory, security, and reproducibility. The KV cache is foundational to transformer inference, and its efficient management determines whether LLM deployments are economically viable at scale. Higher-level caching (prefix, semantic, plan) extends these benefits to cross-request and cross-session scenarios, but introduces trade-offs in correctness, complexity, and security that must be carefully managed.

The subsequent chapters examine each of these dimensions in detail, drawing on the academic literature to provide evidence-based guidance for practitioners and researchers.

---

## References

- [1] Luo et al., "A Survey on Large Language Model Acceleration based on KV Cache Management," arXiv:2412.19442, 2024.
- [6] Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang: Efficient Execution of Structured Language Model Programs," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference," arXiv:2510.09665, 2025.
- [11] Hooper et al., "KVQuant: Towards 10 Million Context Length LLM Inference with KV Cache Quantization," arXiv:2401.18079, 2024.
- [18] "Don't Break the Cache: An Evaluation of Prompt Caching for Long-Horizon Agentic Tasks," arXiv:2601.06007, 2026.
- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [24] Schroeder et al., "vCache: Verified Semantic Prompt Caching," arXiv:2502.03771, 2025.
- [31] Dai et al., "Statistical Independence Aware Caching for LLM Workflows," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver: A Modular Framework for Efficient, Affordable, and Reproducible LLM Inference," Findings of EMNLP 2025.
- [33] Yuan et al., "Understanding and Mitigating Numerical Sources of Nondeterminism in LLM Inference," arXiv:2506.09501, 2025.
- [34] "Non-Determinism of 'Deterministic' LLM Settings," arXiv:2408.04667, 2024.
- [37] Wu et al., "I Know What You Asked: Prompt Leakage via KV-Cache Sharing in Multi-Tenant LLM Serving," NDSS 2025.
- [38] Luo et al., "Shadow in the Cache: Unveiling and Mitigating Privacy Risks of KV-cache in LLM Inference," arXiv:2508.09442, 2025.
- [39] "The Early Bird Catches the Leak: Unveiling Timing Side Channels in LLM Serving Systems," arXiv:2409.20002, 2024.
