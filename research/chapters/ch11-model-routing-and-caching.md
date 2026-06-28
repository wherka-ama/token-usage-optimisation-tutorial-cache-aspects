# Chapter 11: Model Routing and Cache-Preserving Strategies

## 11.1 Introduction

Model routing — dynamically selecting which LLM processes each query — is a complementary optimization to caching. Routing reduces cost by sending simple queries to cheaper models and reserving expensive models for complex tasks. However, routing and caching interact in complex ways: model switching invalidates caches, but cache-preserving routing strategies can combine both benefits. This chapter examines this interaction, focusing on the HyDRA architecture as a production case study.

---

## 11.2 The Routing-Caching Tension

### 11.2.1 The Fundamental Conflict

- **Routing benefit**: Cheaper models for simple queries → cost reduction
- **Caching benefit**: Reusing KV cache for identical prefixes → cost reduction
- **Conflict**: Switching models mid-conversation invalidates the entire cache → cost increase

When a router switches from Model A to Model B between turns:
1. The KV cache built for Model A is useless for Model B (KV caches are model-specific [19])
2. Model B must re-process the entire conversation from scratch
3. The cache write cost for Model A is wasted
4. A new cache write cost is incurred for Model B

### 11.2.2 The Cost of Model Switching

The experimental harness (Experiment 7) demonstrates this directly:
- Turn 1: `claude-sonnet-4-20250514` → cache created
- Turn 2: `gpt-4o` → cache invalidated, full re-processing
- Turn 3: `claude-sonnet-4-20250514` → cache invalidated again, full re-processing

Each switch invalidates the entire cache, requiring full re-processing. At scale, this can eliminate all caching benefits.

---

## 11.3 Model Routing Approaches

### 11.3.1 Hybrid LLM

Hybrid LLM [42] introduces a router that assigns queries to a small or large model:
- Uses a BERT-style encoder (DeBERTa) to predict query difficulty
- Routes easy queries to a small model (e.g., Llama-2-13B), hard queries to a large model
- Tunable quality-cost trade-off via a threshold parameter
- **Result**: Up to 40% fewer calls to the large model with no drop in response quality

### 11.3.2 RouteLLM

RouteLLM [43] learns routers from human preference data:
- Routes between a strong model (e.g., GPT-4) and a weak model (e.g., Mixtral-8x7B)
- Uses data augmentation to enhance performance
- **Result**: Over 2× cost reduction without sacrificing response quality
- Strong generalization across model pairs not included in training

### 11.3.3 CARROT

CARROT [44] performs minimax-optimal routing:
- Predicts both cost and accuracy for each question
- Simple router that is provably minimax optimal
- Introduces the SPROUT dataset for routing evaluation
- Routes to all possible models (not just two), increasing accuracy coverage

### 11.3.4 OmniRouter

OmniRouter [45] introduces budget-controllable routing:
- Models routing as a **constrained optimization problem** (not per-query greedy)
- Minimizes total cost while ensuring required performance level
- Uses Lagrangian dual decomposition with adaptive multipliers
- **Result**: Up to 6.30% accuracy improvement, 10.15% cost reduction vs. baselines

---

## 11.4 HyDRA: Cache-Preserving Routing in Production

### 11.4.1 Architecture

HyDRA [41] is deployed in GitHub Copilot's VS Code Chat auto-mode, serving tens of millions of developers:

- **ModernBERT encoder** with K=4 independent sigmoid heads
- Scores each query along: reasoning, code generation, debugging, tool use
- **Shortfall matching**: Selects the cheapest model whose capabilities meet predicted requirements
- Predictor runs at 86 ms median CPU inference latency
- **Decoupled from model catalog**: Adding/removing models requires only configuration change, zero retraining

### 11.4.2 Cache-Preserving Sticky Routing

HyDRA's key innovation for caching is **session-sticky routing**:

> *"To preserve provider prompt caches and user experience, HyDRA implements prompt-cache-preserving sticky routing, invoking the router only at the start of a conversation or after explicit conversation compaction/summarization."* [41]

This means:
- **Turn 1**: Router selects the cheapest capable model
- **Turns 2-N**: Same model is reused (sticky), preserving the KV cache
- **After compaction/summarization**: Router is re-invoked (cache is already broken by compaction)

### 11.4.3 Production Results

HyDRA's A/B flight results (~1M users per arm):

| Metric | Improvement |
|--------|------------|
| Time-to-complete | -6.4% |
| Error rate | -17.7% |
| COGS | 7-20% reduction |

On SWE-Bench Verified (5-model pool):
- **Peak-quality**: 75.4% resolution (vs. 74.2% always-strong baseline) at 12.9% cost savings
- **Iso-quality**: Matches Sonnet 4.6 at 54.1% cost savings (6× improvement over prior binary router)
- **Aggressive**: 72.5% cost savings for 3.2-point quality trade

### 11.4.4 Additional Production Features

- **Health-aware filtering**: CAPI infrastructure filters unhealthy models
- **Image hardgating**: Image-bearing requests bypass the text-only predictor
- **Zero-downtime model lifecycle management**: Models can be added/removed without service interruption
- **Dynamic INT8 quantization**: Excluding attention nodes for efficiency
- **99.98% availability** with 142 ms median end-to-end latency
- **Language-invariant routing**: First in LLM routing literature, works across CJK, European, and other script families

---

## 11.5 The Combined Caching-Routing Savings

### 11.5.1 Complementary Optimizations

When designed with cache preservation:
- **Caching alone**: 41-80% cost reduction [18]
- **Routing alone**: 40-72% cost savings [41, 42, 43]
- **Combined (HyDRA production)**: 7-20% COGS reduction on top of existing caching

### 11.5.2 Why the Combined Savings Aren't Simply Additive

The savings are not simply additive because:
1. Caching already reduces the cost of the expensive model, reducing the marginal benefit of routing to a cheaper model
2. Sticky routing means the router's benefit is only realized on turn 1 (not every turn)
3. The router itself adds 86 ms latency overhead
4. Cache-preserving routing sacrifices some routing flexibility (cannot switch mid-conversation)

### 11.5.3 Optimal Strategy

The optimal combined strategy depends on:
- **Conversation length**: Longer conversations benefit more from caching (sticky routing)
- **Query difficulty variance**: High variance benefits more from routing (different models for different difficulties)
- **Model cost differential**: Large cost gaps between models make routing more valuable
- **Cache discount**: Larger cache discounts (Anthropic 90% vs. OpenAI 50%) make caching more valuable relative to routing

---

## 11.6 Routing Without Cache Preservation

### 11.6.1 The Cost of Non-Sticky Routing

If a router switches models on every turn:
- Turn 1: Model A, cache write (full price)
- Turn 2: Model B, cache miss (full price, new cache write)
- Turn 3: Model A, cache miss (cache from Turn 1 may have expired)
- **Result**: No caching benefit; full price on every turn

### 11.6.2 When Non-Sticky Routing May Still Be Beneficial

- **Single-turn queries**: No multi-turn cache to preserve
- **Very large cost differentials**: If Model B is 100× cheaper, the savings may exceed the cache loss
- **Quality-critical turns**: If a specific turn requires a stronger model, the quality benefit may exceed the cache cost

### 11.6.3 The Broader Routing Landscape

Beyond HyDRA, the routing literature offers several approaches with different cache implications:

**RouteLLM** [77]: Learns router models from preference data to dynamically select between strong/weak LLMs:
- Up to 2× cost reduction without sacrificing response quality
- 3.66× cost savings on GPT-4 vs. Mixtral routing
- Strong generalization across model pairs without retraining
- **Cache implication**: Per-query routing (no sticky routing) — best for single-turn workloads

**OmniRouter** [78]: Formulates routing as constrained optimization:
- Minimizes total cost while ensuring required performance level
- Uses Lagrangian dual decomposition with adaptive multipliers
- 6.30% accuracy improvement + 10.15% cost reduction vs. baselines
- **Cache implication**: Global budget constraints may conflict with sticky routing requirements

**Cascade Routing** [79]: Unified framework integrating routing and cascading:
- Derives optimal strategy for cascading with formal proofs
- Proposes cascade routing: route first, then cascade if quality insufficient
- Outperforms individual approaches by a large margin
- **Cache implication**: Cascading means multiple model invocations per query — each may create separate caches

**CSCR** [80]: Cost-aware contrastive routing using shared embedding space:
- Maps prompts and models into shared space for fast cost-sensitive selection
- Microsecond latency via FAISS k-NN lookup
- 25% improvement in accuracy-cost tradeoff
- **Cache implication**: No retraining needed when expert pool changes — but no cache preservation mechanism

**IRT-Router** [81]: Uses Item Response Theory from psychometrics:
- Models relationship between LLM capabilities and query difficulty
- Provides interpretable insights (LLM abilities, query difficulty)
- Online query warm-up via semantic similarity for cold-start scenarios
- **Cache implication**: Semantic similarity warm-up could potentially be combined with cache lookups

---

## 11.7 Summary

Model routing and caching are complementary but interacting optimizations:

1. **The fundamental tension**: Model switching invalidates caches [18, 19, 41]
2. **Sticky routing resolves the tension**: HyDRA invokes the router only on turn 1, preserving cache across turns [41]
3. **Production evidence**: HyDRA achieves 7-20% COGS reduction on top of existing caching at GitHub Copilot scale [41]
4. **Routing approaches**: Hybrid LLM [42], RouteLLM [77], CARROT [44], OmniRouter [78], Cascade Routing [79], CSCR [80], IRT-Router [81] offer different trade-offs
5. **Optimal strategy**: Depends on conversation length, query difficulty variance, and model cost differentials
6. **Cache preservation is not universal**: Most routing frameworks (RouteLLM, OmniRouter, CSCR) do not address cache preservation — only HyDRA explicitly designs for it
7. **Cascade routing creates multiple caches**: Cascading implies multiple model invocations, potentially creating separate caches per query

The key insight from HyDRA is that **cache preservation must be a first-class design constraint** in routing systems, not an afterthought. Routing systems that ignore caching will undermine their own cost savings in multi-turn scenarios. The broader routing literature (RouteLLM, OmniRouter, Cascade Routing, CSCR, IRT-Router) provides increasingly sophisticated model selection strategies, but none explicitly address the cache-routing tension — representing a significant gap in the literature.

---

## References

- [18] "Don't Break the Cache," arXiv:2601.06007, 2026.
- [19] "Agentic Plan Caching," arXiv:2506.14852, 2025.
- [41] "HyDRA: Hybrid Dynamic Routing Architecture for Heterogeneous LLM Pools," arXiv:2605.17106, 2026.
- [42] "Hybrid LLM: Cost-Efficient and Quality-Aware Query Routing," arXiv:2404.14618, 2024.
- [43] "RouteLLM: Learning to Route LLMs with Preference Data," arXiv:2406.18665, 2024.
- [44] "CARROT: A Cost Aware Rate Optimal Router," arXiv:2502.03261, 2025.
- [45] Mei et al., "OmniRouter: Budget and Performance Controllable Multi-LLM Routing," arXiv:2502.20576, 2025.
- [77] "RouteLLM: Learning to Route LLMs with Preference Data," arXiv:2406.18665, 2024.
- [78] Mei et al., "OmniRouter: Budget and Performance Controllable Multi-LLM Routing," arXiv:2502.20576, 2025.
- [79] "A Unified Approach to Routing and Cascading for LLMs," arXiv:2410.10347, 2024.
- [80] Shirkavand et al., "Cost-Aware Contrastive Routing for LLMs (CSCR)," arXiv:2508.12491, 2025.
- [81] Song et al., "IRT-Router: Effective and Interpretable Multi-LLM Routing via Item Response Theory," arXiv:2506.01048, 2025.
