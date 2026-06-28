# Chapter 2: Impact of Caching on Reliability and Reproducibility

## 2.1 Introduction

A critical but often overlooked dimension of LLM caching is its impact on the **reliability** and **reproducibility** of system outputs. Caching introduces a tension: it can improve reproducibility by storing and replaying exact responses, but it can also undermine it by introducing non-determinism through system-level optimizations. This chapter examines both sides of this tension, drawing on recent academic work to provide a nuanced analysis.

---

## 2.2 The Reproducibility Crisis in LLM Inference

### 2.2.1 Non-Determinism in "Deterministic" Settings

A foundational finding by [34] demonstrates that LLMs configured for deterministic inference (temperature=0, top_p=1, fixed seed) still exhibit significant non-determinism across runs. Key findings:

- **Accuracy variations up to 15%** across naturally occurring runs with identical inputs
- **Performance gaps up to 70%** between best and worst possible performance
- **None of the five LLMs tested** consistently delivered repeatable accuracy across all tasks
- Raw output strings rarely matched across runs, though parsed answers were more stable

The authors identify a critical insight: *"Engineering optimizations to run LLMs faster, such as continuous batching, chunk prefilling, or prefix caching, might lead to non-deterministic behavior"* [34]. When running Llama3-8b on local GPUs without any optimizations, results were deterministic — indicating that the optimizations themselves, not the models, are the source of non-determinism.

### 2.2.2 Numerical Sources of Nondeterminism

Yuan et al. [33] provide the first systematic investigation into how numerical precision affects reproducibility. Their findings are striking:

- Under **bfloat16** precision with greedy decoding, DeepSeek-R1-Distill-Qwen-7B exhibits:
  - Up to **9% variation in accuracy**
  - Up to **9,000 tokens difference** in response length
  - Due to differences in GPU count, type, and evaluation batch size

The root cause is the **non-associative nature of floating-point arithmetic** under limited numerical precision. When batch sizes change (as they do with prefix caching, which alters the composition of batches), the reduction order in GPU kernels changes, producing different floating-point results. In reasoning models, these minor rounding differences in early tokens can **cascade into divergent chains of thought**, ultimately affecting accuracy.

### 2.2.3 The Prefix Caching Connection

Prefix caching specifically contributes to non-determinism because:

1. **Batch composition changes**: When some requests hit the cache and others don't, the remaining requests form different batches, leading to different parallelization patterns in GPU kernels
2. **Reduction order variation**: GPU kernels use split-K strategies and other parallelization techniques whose reduction orders depend on batch geometry [35]
3. **Cross-request interference**: In multi-tenant serving, one request's cache hit changes the batch environment for other requests

The LLM-42 work [35] explicitly notes this: *"prefill and decode use different reduction strategies in LLM-42, making the system non–prefill-decode invariant. As a result, LLM-42 currently does not support sharing prefix caches across multiple turns of the same request or sharing across requests."*

---

## 2.3 Caching as a Reproducibility Solution

### 2.3.1 Cache Saver: Namespace-Aware Caching

Cache Saver [32] directly addresses the reproducibility challenge with a **namespace-aware list-valued cache**:

- **Within a namespace**: Responses are i.i.d. (independent and identically distributed), preserving statistical integrity
- **Across namespaces**: Identical prompts yield identical results, enabling reproducibility
- **Seeding mechanism**: Namespaces act as "seeds" — the same namespace + prompt always returns the same cached response

This design recognizes that naive caching breaks statistical independence: if a cached response is reused in a context that expects independent samples (e.g., Pass@k evaluation), the metric becomes invalid. Cache Saver's namespace approach ensures:
- Statistical correctness of evaluation metrics (Pass@k, uncertainty estimation)
- Reproducibility across experiment runs
- Cost savings of ~25% on average, up to 60% for benchmarking/ablation tasks

### 2.3.2 Mnimi: Statistical Independence Aware Caching

Mnimi [31] tackles the same problem from a different angle, focusing on **agentic workflows** where retries and repair loops require independent samples:

- **Independent mode**: Each call to `sample()` produces a fresh, independent response (no cache reuse)
- **Repeatable mode**: Same prompt always returns the same cached response
- **Persistent mode**: Cached responses persist across program runs, enabling deterministic debugging

The key innovation is encapsulating statistical constraints **within the type system** — users can transform between Independent, Repeatable, and Persistent modes based on algorithmic requirements. For example, in a program repair loop:
- The initial generation uses Repeatable mode (deterministic, cached)
- Retry attempts use Independent mode (fresh samples, preserving statistical validity)
- Debugging uses Persistent mode (exact replay of prior runs)

A case study on SpecFix (an automated program specification repair system) demonstrates that Mnimi improves reproducibility, ease of debugging, and time/cost efficiency while preserving statistical correctness.

### 2.3.3 The Tension: Caching vs. Statistical Independence

Both Cache Saver and Mnimi identify a fundamental tension:

> **Naive caching compromises statistical independence**, a critical property for probabilistic workflows. In applications of LLM for code, it underpins performance metrics such as Pass@k and uncertainty estimation, as well as algorithms like program repair loops and retries. [31]

Without careful design, caching can:
- **Inflate Pass@k metrics**: If the same response is reused for multiple samples, diversity is lost
- **Break uncertainty estimation**: Cached responses appear more confident than independent samples would be
- **Undermine retry logic**: If a retry returns the same failed response, the retry is meaningless

---

## 2.4 Reliability of Semantic Caching

### 2.4.1 The Correctness Problem

Semantic caches return cached responses for semantically similar (not identical) prompts. This introduces a fundamental reliability challenge: **how similar is similar enough?**

vCache [24] identifies the core problem:
- Static thresholds "do not give formal correctness guarantees, can result in unexpected error rates, and lead to suboptimal cache hit rates"
- "Unless a threshold of 1.0 is used (effectively restricting cache hits to exact prompt matches), there is always a risk of returning incorrect responses"
- Existing systems (GPTCache, Portkey, etc.) rely on fixed thresholds with no formal guarantees

### 2.4.2 vCache's Solution: Verified Guarantees

vCache introduces the first semantic cache with **user-defined error rate guarantees**:

- An online learning algorithm estimates an **optimal threshold for each cached prompt** (not a global threshold)
- The user specifies a maximum error rate δ, and vCache guarantees: Pr(vCache(x) = r(x)) ≥ (1 - δ)
- Achieves up to **12.5× higher cache hit rates** and **26× lower error rates** vs. static-threshold baselines
- Robust to out-of-distribution inputs through adaptive threshold learning

This represents a significant advance in making semantic caching **reliable enough for production use**, where correctness guarantees are essential.

### 2.4.3 False Positives in Agentic Contexts

The Agentic Plan Caching work [19] demonstrates that semantic caching is particularly problematic for agentic applications:

- Semantic caching suffers from a "high rate of false-positive cache hits, leading to substantial performance degradation"
- In agentic contexts, outputs depend on external data and environmental context, not just input prompts
- Two semantically similar queries may require different actions depending on dataset characteristics, screen coordinates, or runtime state

The agentic plan caching approach addresses this by:
- Extracting **structured plan templates** (not raw responses) from completed executions
- Using **keyword extraction** to match semantic targets, not full-query similarity
- Adapting templates with **lightweight models** to task-specific contexts
- Maintaining consistent accuracy regardless of cache-hit/miss status

---

## 2.5 System-Level Reliability Concerns

### 2.5.1 Cache Eviction and Workload Sensitivity

The KV cache survey [1] identifies that popular eviction policies (LRU, LFU) "do not align with LLM patterns, leading to suboptimal performance." This creates reliability concerns:

- **Premature eviction**: KV caches needed for upcoming requests may be evicted, causing unexpected latency spikes
- **Workload-dependent performance**: Cache hit rates vary dramatically with workload patterns, making system performance unpredictable
- **KVFlow** [20] addresses this with workflow-aware eviction: it models agent execution schedules as an "Agent Step Graph" and assigns steps-to-execution values to predict future reuse

### 2.5.2 Cache TTL and Robustness

CacheTTL [21] introduces time-to-live mechanisms for KV cache retention in agentic workloads:

- When agents make tool calls, the KV cache must be retained during the tool execution pause
- Without TTL, caches are evicted at end-of-turn, requiring expensive recomputation when the tool returns
- TTL values are determined by modeling reload cost and queueing delay
- When TTL expires, caches are automatically evicted, preventing memory pressure from long-running or failed tool calls

This provides **robustness** against edge cases (failed tool calls, unexpectedly long executions) while maintaining performance benefits in the common case.

### 2.5.3 Context Truncation Impact

LMCache [8] reveals an important production insight: *"context truncation, which is a widely applied technique in industry, can greatly reduce prefix cache hit ratio by half."* This means that common reliability-optimizing practices (truncating context to fit within limits) can paradoxically undermine the caching that improves system reliability.

---

## 2.6 Reproducibility Across System Configurations

### 2.6.1 The Tensor Parallel Problem

Zhang et al. [36] identify that deterministic inference across different tensor parallel (TP) sizes remains an open problem:

- Training engines typically use Fully Sharded Data Parallel (TP=1)
- Rollout/serve engines use multi-GPU TP for throughput
- This creates a **training-inference mismatch** where identical inputs produce different outputs
- Their TBIK (Tree-Based Invariant Kernels) achieve bit-wise identical results regardless of TP size

This is critical for RL training pipelines and LLM-as-judge evaluation, where consistency between training and inference is essential.

### 2.6.2 LayerCast: Balancing Precision and Stability

Yuan et al. [33] propose LayerCast as a practical mitigation:
- Stores weights in 16-bit precision (memory efficient)
- Performs all computations in FP32 (numerically stable)
- Achieves divergence rates below 3.4% across configurations
- Reduces memory usage by 34% vs. full FP32

This is particularly important for KV cache in long-context scenarios, where memory efficiency and numerical stability are both critical.

### 2.6.3 Batch-Invariant Kernels (Thinking Machines Lab)

Horace He and collaborators at Thinking Machines Lab [67] introduced **batch-invariant computation** as a practical approach to deterministic LLM inference:

- **Root cause isolation**: Nondeterminism vanishes with fixed batch size=1 but reappears with dynamic batching — confirming that the batching system, not the model, is the source
- **Batch-invariant kernels**: GPU kernels are constrained to use a single, universal reduction strategy (canonical tree order) for all tokens, eliminating batch-dependent reduction orders
- **Design principle**: Replace kernels so numerical results are identical regardless of batch size, padding, or position
- **Limitation**: Currently limited to batch-dimension variations — robust to continuous batching but not to TP size changes or GPU type changes [33]
- **LLM-42 integration**: LLM-42 [35] builds on this approach but notes that *"batch-invariant execution makes determinism the default for all requests, even when determinism is undesirable or even harmful"* — advocating selective determinism instead

This work is significant because it demonstrates that **determinism and dynamic batching can coexist** — the key insight is that the reduction strategy, not the batching itself, causes non-determinism. However, batch-invariant kernels strip GPU kernels of parallelism, creating a throughput-determinism trade-off.

### 2.6.4 The Prefill-Decode Invariance Problem

LLM-42 [35] identifies a subtler form of non-determinism relevant to caching:
- Prefill and decode use **different reduction strategies** in most implementations
- This means a token processed during prefill (cache creation) may produce a slightly different KV value than the same token processed during decode
- LLM-42 *"currently does not support sharing prefix caches across multiple turns of the same request or sharing across requests"* due to this prefill-decode invariance gap
- This directly impacts prefix caching: if prefill and decode are not invariant, cached KV tensors from prefill may not match what decode would produce

---

## 2.7 Summary: The Caching-Reliability Trade-off Matrix

| Caching Type | Reproducibility Impact | Reliability Impact | Mitigation |
|-------------|----------------------|-------------------|------------|
| **KV Cache (intra-request)** | Neutral (inherent to inference) | Positive (reduces compute errors) | N/A |
| **Prefix Caching** | Negative (batch composition changes, prefill-decode gap) | Mixed (latency vs. determinism) | LayerCast [33], TBIK [36], Batch-invariant kernels [67] |
| **Semantic Caching** | Negative (approximate matching) | Negative (false positives) | vCache [24] guarantees |
| **Response Caching (naive)** | Positive (exact replay) | Negative (breaks independence) | Cache Saver [32], Mnimi [31] |
| **Plan Caching** | Positive (structured templates) | Mixed (adaptation quality) | Agentic Plan Caching [19] |
| **Cache TTL** | Neutral | Positive (robustness) | CacheTTL [21] |
| **Temporal Caching** | Neutral | Positive (temporal validity) | Temporal classifier [63] |

---

## 2.8 Conclusion

Caching presents a **dual-edged sword** for LLM system reliability and reproducibility:

1. **At the system level**, caching optimizations (prefix caching, continuous batching) introduce non-determinism through floating-point non-associativity and batch composition changes [33, 34, 35]
2. **At the application level**, naive response caching breaks statistical independence, invalidating evaluation metrics and retry logic [31, 32]
3. **At the semantic level**, approximate matching introduces correctness risks that lack formal guarantees in most systems [24]

Recent work has begun to address these challenges:
- **vCache** [24] provides formal error rate guarantees for semantic caching
- **Cache Saver** [32] and **Mnimi** [31] preserve statistical integrity through namespace/type-aware caching
- **LayerCast** [33] and **TBIK** [36] mitigate numerical non-determinism
- **CacheTTL** [21] provides robustness against edge cases in agentic workloads

However, significant gaps remain, particularly in providing end-to-end reproducibility guarantees that span both system-level optimizations and application-level caching.

---

## References

- [1] Luo et al., "A Survey on Large Language Model Acceleration based on KV Cache Management," arXiv:2412.19442, 2024.
- [8] Liu et al., "LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference," arXiv:2510.09665, 2025.
- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [20] Pan et al., "KVFlow: Efficient Prefix Caching for Accelerating LLM-Based Multi-Agent Workflows," arXiv:2507.07400, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [24] Schroeder et al., "vCache: Verified Semantic Prompt Caching," arXiv:2502.03771, 2025.
- [31] Dai et al., "Statistical Independence Aware Caching for LLM Workflows," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver: A Modular Framework for Efficient, Affordable, and Reproducible LLM Inference," Findings of EMNLP 2025.
- [33] Yuan et al., "Understanding and Mitigating Numerical Sources of Nondeterminism in LLM Inference," arXiv:2506.09501, 2025.
- [34] "Non-Determinism of 'Deterministic' LLM Settings," arXiv:2408.04667, 2024.
- [35] "LLM-42: Enabling Determinism in LLM Inference with Verified Speculation," arXiv:2601.17768, 2026.
- [36] Zhang et al., "Deterministic Inference across Tensor Parallel Sizes (TBIK)," arXiv:2511.17826, 2025.
- [63] "Evaluating Temporal Semantic Caching and Workflow Optimization in Agentic Plan-Execute Pipelines," arXiv:2605.20630, 2026.
- [67] He et al., "Defeating Nondeterminism in LLM Inference," Thinking Machines Lab, 2025.
