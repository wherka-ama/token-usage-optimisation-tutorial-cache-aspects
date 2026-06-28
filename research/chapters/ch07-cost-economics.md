# Chapter 7: Cost Economics and Token Usage Impact

## 7.1 Introduction

Caching is fundamentally an economic optimization. This chapter synthesizes the empirical evidence on how caching influences the cost of LLM inference, drawing on both provider-level pricing analysis and system-level throughput measurements. The evidence spans provider APIs, serving systems, and agentic frameworks.

---

## 7.2 Provider-Level Cost Economics

### 7.2.1 Pricing Models

Major LLM providers have introduced cache-aware pricing:

| Provider | Cache Read Price | Cache Write Price | Full Input Price | Cache Discount |
|----------|-----------------|------------------|-----------------|----------------|
| **Anthropic** | ~10% of input | ~125% of input | Base rate | 90% |
| **OpenAI** | ~50% of input | Base rate (automatic) | Base rate | 50% |
| **Google** | Discounted rate | Base rate | Base rate | Variable |

### 7.2.2 Empirical Cost Reductions

The "Don't Break the Cache" evaluation [18] provides the most comprehensive cross-provider cost analysis:

| Model | Cost Reduction (Best Strategy) | Cache Strategy |
|-------|-------------------------------|----------------|
| GPT-5.2 | 79-81% | Exclude tool results |
| Claude Sonnet 4.5 | 78-79% | Full context |
| GPT-4o | 46-48% | System prompt only |
| Gemini 2.5 Pro | 28-41% | System prompt only |

Key finding: *"The consistency of cost savings across cache strategies suggests that the primary driver of cost reduction is caching the large system prompt, which remains stable across all requests within a session."* [18]

### 7.2.3 The Write-Read Economics

The economics of prompt caching depend on the ratio of cache writes to cache reads:

- **First request (cache write)**: Pays full price (or premium) to compute and store KV tensors
- **Subsequent requests (cache read)**: Pays discounted rate for cached tokens
- **Break-even**: A single cache write is profitable if followed by at least 1 cache read (for Anthropic's 90% discount) to 2 cache reads (for OpenAI's 50% discount)

For agentic workloads with 30-50 tool calls per session, the system prompt is read on every call but written only once — making caching highly profitable.

### 7.2.4 Scale Economics

At production scale, caching transforms the economics of LLM deployment:

- **HyDRA** [41]: Cache-preserving sticky routing contributed to 7-20% COGS reduction in GitHub Copilot's VS Code Chat auto-mode, serving tens of millions of developers
- At 1M+ calls/day, a 90% cache hit rate on a 10K-token prefix saves ~9M tokens per call
- The difference between 50% and 90% cache hit rate can determine whether an AI feature is profitable

---

## 7.3 System-Level Cost Economics

### 7.3.1 Throughput Improvements

Caching improves throughput, which reduces the per-request cost of self-hosted LLMs:

| System | Improvement | Workload |
|--------|------------|----------|
| vLLM/PagedAttention [6] | 2-4× throughput | General serving |
| SGLang/RadixAttention [7] | Up to 5× faster | Shared-prefix workloads |
| LMCache [8] | Up to 15× throughput | Multi-round QA, document analysis |
| CacheTTL [21] | 8× JCT improvement | Multi-turn agents |
| KVFlow [20] | 2.19× speedup | Concurrent multi-agent workflows |

### 7.3.2 Memory Cost Reduction

KV cache compression reduces the GPU memory required for inference, enabling:
- Longer context windows on existing hardware
- Larger batch sizes (more concurrent requests)
- Cheaper GPU instances (less memory needed)

| Technique | Compression Ratio | Accuracy Impact |
|-----------|------------------|-----------------|
| KVQuant [11] | 3.7× (nuq4) to 10× (nuq2) | <0.1 perplexity degradation at 3-bit |
| AQUA-KV [16] | 6-8× (2-2.5 bits/value) | <1% relative error |
| KV-AdaQuant [17] | 4-bit Key + 2-bit Value | 75.2% accuracy (vs. 54.7% reversed) |
| DMS [15] | 8× | Better accuracy than training-free sparse attention |

### 7.3.3 The Cost of Cache Misses

Cache misses are not free — they incur:
- **Recomputation cost**: Full prefill for uncached tokens
- **Latency penalty**: TTFT increases for cache misses
- **Opportunity cost**: GPU time spent on recomputation could serve other requests

The Tail-Optimized Caching work [48] highlights that while average-case cost improves with caching, **tail latency (P99)** can degrade if cache misses create latency spikes. This is particularly important for SLA-bound production systems.

---

## 7.4 Agentic Cost Economics

### 7.4.1 The Cost of Agentic Workloads

Agentic workloads are significantly more expensive than single-turn queries:
- Multiple LLM calls per task (Plan + Act loop)
- Large, accumulating context windows
- Expensive reasoning models for planning
- Tool call overhead

### 7.4.2 Cost Reduction by Caching Type

| Caching Type | Cost Reduction | Source |
|-------------|---------------|--------|
| Prompt caching (provider) | 41-80% | [18] |
| Agentic plan caching | 46.62% avg | [19] |
| Cache Saver (client-side) | ~25% avg, ~60% for benchmarking | [32] |
| LLM-dCache (data caching) | 1.24× improvement | [23] |
| HyDRA (routing + cache) | 7-20% COGS reduction | [41] |

### 7.4.3 The Benchmarking Cost Problem

Cache Saver [32] reveals an important cost dimension: **LLM benchmarking and ablation studies** are extremely expensive due to prompt redundancy:
- Reasoning strategies exhibit ~50% prompt redundancy across runs
- Hyperparameter tuning: 6× cheaper, 7× faster with caching
- Ablation studies: 2.5× cheaper
- Benchmarking: 2× cheaper
- This makes caching essential for **research economics**, not just production

### 7.4.4 Carbon Footprint

Cache Saver [32] also measures environmental impact:
- ~35% CO₂ reduction on average across all methods, tasks, and LLMs
- Up to 60% CO₂ reduction for benchmarking and ablation tasks
- LLMs are estimated to account for ~2% of total electricity consumption of major web applications
- Inference dominates cost and energy consumption, sometimes up to 90% of the model's total lifecycle

### 7.4.5 Energy Consumption of LLM Inference

Recent work provides more granular energy measurements:

**Quantifying Energy and Carbon Emissions** [68]:
- Inference now accounts for **more than half** of total LLM lifecycle carbon emissions
- Existing simulation frameworks lack energy consumption concepts
- Caching directly reduces inference energy by avoiding redundant computation

**TokenPowerBench** [69]:
- The AI inference market is forecast to grow from $106B (2025) to over $250B (2030)
- Benchmarks power consumption of LLM inference across hardware configurations
- Caching reduces both compute and memory access, directly lowering power draw

**From Prompts to Power** [70]:
- Uses CodeCarbon with NVIDIA Management Library (NVML) for GPU power monitoring
- Measures vLLM energy consumption under various workloads
- Caching reduces prefill computation, which is the most energy-intensive phase

### 7.4.6 Token Pricing Economics

**The Economics of LLMs** [71] develops a formal economic framework:
- Optimal pricing structure depends on whether token allocation is contractible
- Higher markups for more intensive users (two-part tariffs)
- Caching changes the effective cost per token, altering the optimal pricing strategy
- Providers may need to account for cache hit rates in pricing models

**Tokenization Multiplicity** [72]:
- The same output string can have **multiple different tokenizations** — leading to arbitrary price variation
- Particularly affects non-English outputs
- "Canonical generation" constrains LLMs to unique tokenizations, eliminating price variation
- Implication for caching: different tokenizations of the same content produce different cache keys

**Pay-Per-Token Vulnerabilities** [73]:
- Per-token pricing creates financial incentives for providers to misreport token counts
- Users cannot verify whether they are being overcharged
- Proposes pay-per-character pricing as incentive-compatible alternative
- Implication: caching discounts should be verifiable by users

---

## 7.5 The Usage-Based Billing (UBB) Context

### 7.5.1 The Shift to UBB

GitHub Copilot's move to Usage-Based Billing exemplifies a broader industry trend: **every token now has a price tag**. This makes caching a first-order economic concern:

- Cache hits cost 10-50% of full input token price
- A 90% cache hit rate on a 10K-token prefix saves ~9K tokens per call
- At scale (1M+ calls/day), this is the difference between profitable and unprofitable AI features

### 7.5.2 Token Economics

The Tokenomics Foundation (Linux Foundation) is establishing standards for token-level cost accounting. Key metrics include:
- **Cost per token**: Amortized cost including cache hits/misses
- **Cache hit rate**: Fraction of input tokens served from cache
- **Effective token cost**: Actual cost accounting for cache discounts
- **Token efficiency**: Output quality per token spent

### 7.5.3 FinOps for LLMs

As LLM costs become a significant line item, FinOps practices are being adapted:
- **Budget controls**: Setting per-user, per-team token budgets
- **Cost monitoring**: Real-time tracking of cache hit rates and effective costs
- **Model selection**: Choosing models based on cost-quality trade-offs (enabled by routing — see Chapter 11)
- **Cache optimization**: Tuning prompt structure and TTL to maximize cache hits

---

## 7.6 The Interaction Between Caching and Routing

### 7.6.1 The Routing-Caching Tension

Model routing (selecting different models for different queries) and caching are in tension:
- **Routing benefit**: Cheaper models for simple queries → cost reduction
- **Caching benefit**: Reusing KV cache for identical prefixes → cost reduction
- **Conflict**: Switching models mid-conversation invalidates the cache → cost increase

### 7.6.2 HyDRA's Cache-Preserving Solution

HyDRA [41] resolves this tension with **sticky routing**:
- The router is invoked only on turn 1, after compaction, or after summarization
- Every other turn reuses the cached model, preserving the 90% prompt cache discount
- This contributed to 7-20% COGS reduction in production

### 7.6.3 The Combined Savings

When caching and routing are combined:
- **Caching alone**: 41-80% cost reduction [18]
- **Routing alone**: 40-55% cost reduction (HyDRA iso-quality: 54.1% savings) [41]
- **Combined**: HyDRA's production deployment achieved 7-20% COGS reduction on top of existing caching, demonstrating that routing and caching are **complementary** when designed with cache preservation in mind

---

## 7.7 Summary

The economic case for caching is overwhelming:

1. **Provider-level**: 41-80% cost reduction across major providers [18]
2. **System-level**: 2-15× throughput improvement [6, 7, 8]
3. **Agentic**: 46.62% cost reduction via plan caching [19]
4. **Research**: Up to 60% cost and CO₂ reduction for benchmarking [32]
5. **Production**: 7-20% COGS reduction at GitHub Copilot scale [41]

The key economic principles are:
- **Cache writes are investments** that pay off through subsequent cache reads
- **System prompts are the highest-value cache targets** (large, stable, read every call)
- **Cache hit rate is the key metric** — the difference between 50% and 90% is transformative at scale
- **Caching and routing are complementary** when designed with cache preservation (sticky routing)
- **Carbon footprint matters** — caching reduces CO₂ by 25-60%

---

## References

- [6] Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang: Efficient Execution of Structured Language Model Programs," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference," arXiv:2510.09665, 2025.
- [11] Hooper et al., "KVQuant: Towards 10 Million Context Length LLM Inference with KV Cache Quantization," arXiv:2401.18079, 2024.
- [15] "Inference-Time Hyper-Scaling with KV Cache Compression (DMS)," arXiv:2506.05345, 2025.
- [16] "AQUA-KV: Adaptive Key-Value Quantization for Large Language Models," arXiv:2501.19392, 2025.
- [17] "KV-AdaQuant: More for Keys, Less for Values: Adaptive KV Cache Quantization," arXiv:2502.15075, 2025.
- [18] "Don't Break the Cache: An Evaluation of Prompt Caching for Long-Horizon Agentic Tasks," arXiv:2601.06007, 2026.
- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [20] Pan et al., "KVFlow: Efficient Prefix Caching for Accelerating LLM-Based Multi-Agent Workflows," arXiv:2507.07400, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [23] "LLM-dCache: Improving Tool-Augmented LLMs with GPT-Driven Localized Data Caching," arXiv:2406.06799, 2024.
- [32] Potamitis et al., "Cache Saver: A Modular Framework for Efficient, Affordable, and Reproducible LLM Inference," Findings of EMNLP 2025.
- [41] "HyDRA: Hybrid Dynamic Routing Architecture for Heterogeneous LLM Pools," arXiv:2605.17106, 2026.
- [48] "Tail-Optimized Caching for LLM Inference," arXiv:2510.15152, 2025.
- [68] "Quantifying the Energy Consumption and Carbon Emissions of LLM Inference," arXiv:2507.11417, 2025.
- [69] "TokenPowerBench: Benchmarking the Power Consumption of LLM Inference," arXiv:2512.03024, 2025.
- [70] "From Prompts to Power: Measuring the Energy Footprint of LLM Inference," arXiv:2511.05597, 2025.
- [71] Bergemann et al., "The Economics of Large Language Models: Token Allocation, Fine-Tuning, and Optimal Pricing," arXiv:2502.07736, 2025.
- [72] Chatzi et al., "Tokenization Multiplicity Leads to Arbitrary Price Variation in LLM-as-a-service," arXiv:2506.06446, 2025.
- [73] "Is Your LLM Overcharging You? Tokenization, Transparency, and Incentives," arXiv:2505.21627, 2025.
