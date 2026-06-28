# Chapter 5: Semantic Caching Approaches

## 5.1 Introduction

While prefix caching requires exact token-level matching, **semantic caching** relaxes this constraint by returning cached responses for prompts that are *semantically similar* (not necessarily identical) to previously seen prompts. This enables cache hits even when prompts differ in wording, phrasing, or language. However, this relaxation introduces fundamental correctness challenges that recent research has begun to address formally.

---

## 5.2 Mechanism

### 5.2.1 Basic Architecture

A semantic cache operates as follows:

1. **Embedding**: Each incoming prompt is converted to a vector embedding using an embedding model (e.g., OpenAI text-embedding-3, sentence-transformers)
2. **Storage**: The embedding and corresponding LLM response are stored in a vector database (e.g., Redis, FAISS, HNSWLib)
3. **Lookup**: When a new prompt arrives, its embedding is compared against cached embeddings using a similarity metric (typically cosine similarity)
4. **Decision**: If similarity exceeds a threshold, the cached response is returned; otherwise, the LLM is invoked
5. **Update**: New (prompt, response) pairs are added to the cache

### 5.2.2 Similarity Metrics

Common similarity metrics include:
- **Cosine similarity**: Most widely used; measures angle between vectors
- **Euclidean distance**: Less common for normalized embeddings
- **Dot product**: Equivalent to cosine similarity for normalized vectors

The choice of embedding model and similarity metric significantly affects cache performance [24, 25, 27].

---

## 5.3 Systems and Approaches

### 5.3.1 GPTCache

GPTCache [29] is the foundational open-source semantic cache for LLMs:
- Customizable embedding models, similarity assessment, and eviction policies
- Widely used as a baseline in academic evaluations
- Limitation: Uses static, global similarity thresholds with no correctness guarantees

### 5.3.2 GPT Semantic Cache

GPT Semantic Cache [25] demonstrates practical semantic caching using Redis:
- Stores query embeddings in in-memory Redis
- Uses top-k cosine similarity for retrieval
- **Results**: 68.8% reduction in API calls, cache hit rates of 61.6-68.8%
- **Accuracy**: Positive hit rates exceeding 97%
- Limitation: Fixed threshold; no formal correctness guarantees

### 5.3.3 Ensemble Embedding Approach

The ensemble approach [27] combines multiple embedding models:
- Trains a meta-encoder to fuse multiple embedding models
- **Results**: 92% cache hit ratio for semantically equivalent queries
- 85% accuracy in correctly rejecting non-equivalent queries
- 10.3% boost in hit ratio over single-model approaches
- Response time reduction from 2.7s to 0.3s, ~20% token savings

### 5.3.4 Generative Caching

The generative caching system [28] goes beyond returning single cached responses:
- **Synthesizes** multiple cached responses to answer novel queries
- Functions as a repository of information that can be mined and analyzed
- Adaptively varies semantic similarity parameters to balance cost, latency, and quality
- Considerably faster than GPTCache

### 5.3.5 ContextCache

ContextCache [30] addresses multi-turn query caching:
- Traditional semantic caches treat each query independently
- Multi-turn conversations require context-aware similarity matching
- Considers conversation history when determining cache hits

---

## 5.4 The Correctness Challenge

### 5.4.1 The Fundamental Problem

vCache [24] identifies the core issue:

> *"Even with high-quality embeddings and a presumably carefully tuned threshold, semantic caches remain inherently approximate. Unless a threshold of 1.0 is used (effectively restricting cache hits to exact prompt matches), there is always a risk of returning incorrect responses."* [24]

Existing systems (GPTCache, Portkey, GPT Semantic Cache) rely on **fixed, static thresholds** with:
- No formal correctness guarantees
- Unexpected and unpredictable error rates
- Suboptimal cache hit rates (threshold too high → few hits; too low → many errors)

### 5.4.2 vCache: Verified Semantic Caching

vCache [24] introduces the first semantic cache with **user-defined error rate guarantees**:

**Key Innovation**: Instead of a global threshold, vCache learns a **separate threshold for each cached embedding** using an online learning algorithm.

**How it works**:
1. User specifies maximum error rate δ (e.g., 1%, 5%)
2. For each cached prompt, vCache maintains an adaptive threshold
3. When a new prompt arrives, its similarity to the nearest cached prompt is compared against that prompt's learned threshold
4. The online learning algorithm adjusts thresholds based on observed outcomes
5. Guarantee: Pr(vCache(x) = correct(x)) ≥ (1 - δ) for all x

**Results**:
- Up to **12.5× higher cache hit rates** vs. static-threshold baselines
- Up to **26× lower error rates** vs. static-threshold baselines
- Consistently meets specified error bounds across two embedding models, two LLMs, and five datasets
- Robust to out-of-distribution inputs
- No upfront training required; agnostic to embedding model

**Significance**: This makes semantic caching **production-viable** for applications where correctness guarantees are required.

### 5.4.3 Semantic Caching with Mismatch Costs

The framework by [26] introduces a more nuanced model:
- **Mismatch cost**: Models the utility loss when serving a semantically similar (but not identical) response
- **Unified loss function**: Balances mismatch cost against serving cost
- Three settings of increasing uncertainty:
  1. **Oracle**: Query arrival probabilities and serving costs known
  2. **Offline learning**: Parameters unknown but learned from static data
  3. **Online adaptive**: Agent learns and adapts in real time from partial feedback
- Provides provably efficient algorithms with state-of-the-art guarantees

### 5.4.4 Asynchronous Verified Semantic Caching

The asynchronous approach [49] (Krites) extends vCache to tiered LLM architectures:
- Applies verified semantic caching across multiple LLM tiers (strong/weak models)
- **Asynchronous LLM-judged verification**: When a request misses the static tier but its nearest neighbor falls in a "grey zone," Krites asynchronously invokes an LLM judge to verify whether the static response is acceptable
- **Critical path preservation**: On the serving path, Krites behaves exactly like a standard static threshold policy — no added latency
- Approved matches are promoted into the dynamic cache, expanding static reach over time
- **Results**: Up to 3.9× increase in requests served with curated static answers vs. tuned baselines
- Designed for modern agentic stacks with multi-step workflows

### 5.4.5 User-Centric Semantic Caching (MeanCache)

MeanCache [75] addresses privacy concerns in semantic caching:
- **User-side embedding computation**: Embeddings computed at the user side, preserving privacy (no storing user queries at server)
- **Optimal threshold selection**: Varies threshold based on embedding model — MPNet optimal at 0.83, Albert at 0.78
- **GPTCache comparison**: GPTCache's suggested threshold of 0.7 is suboptimal — MeanCache outperforms by 16% in precision and 4% in F-score for MPNet
- **Key insight**: The optimal similarity threshold is embedding-model-dependent, not universal

### 5.4.6 Semantic Cache Eviction Policies

Biton et al. [76] study eviction policies specifically for semantic caches:
- **SphereLFU**: Adapts LFU to the semantic domain using soft-frequency updates distributed across neighboring vectors
- **SurprisalLFU**: Uses linguistic surprisal as a tie-breaking mechanism for eviction — more intelligent than random or recency-based selection
- **NP-hardness**: Implementing an optimal semantic cache is NP-hard, motivating online heuristics
- **Semantic-aware policies** combine recency, frequency, and locality in the embedding space
- Key finding: SphereLFU excels at high density (low thresholds), SurprisalLFU is robust at conservative thresholds

### 5.4.7 Empirical Threshold Analysis

GPT Semantic Cache [74] provides detailed threshold analysis:
- Cosine similarity threshold of 0.8 achieves optimal balance: 68.8% cache hit rate, >97% positive hit accuracy
- Thresholds below 0.8 lead to false positives; above 0.8 reduce hit rates significantly
- API calls reduced by up to 68.8% across query categories
- Uses Redis in-memory storage for embedding caching

---

## 5.5 Semantic Caching for Agentic Applications

### 5.5.1 Limitations of Semantic Caching for Agents

The Agentic Plan Caching work [19] identifies three critical limitations:

1. **Data-Dependent Outputs**: Agent outputs depend on external data and environmental context, not just input prompts. Two semantically similar queries may require different actions depending on dataset characteristics or runtime state.

2. **False-Positive Cache Hits**: Semantic caching "suffers from a high rate of false-positive cache hits, leading to substantial performance degradation" in agentic contexts.

3. **Limited Adaptability**: Semantic caching does not capture the transformation process from prompt to response, hindering adaptation to queries with minor differences (e.g., numeric values, variable names).

### 5.5.2 Agentic Plan Caching as Alternative

Agentic Plan Caching [19] proposes a fundamentally different approach:
- **Extracts structured plan templates** from completed agent executions (not raw responses)
- Uses **keyword extraction** to match semantic targets (not full-query similarity)
- Adapts templates with **lightweight models** to task-specific contexts
- **Results**: 46.62% cost reduction while maintaining 96.67% of application-level performance
- Cache-miss and cache-hit accuracy are consistent (no degradation on cache hits)

---

## 5.6 Empirical Evidence on Query Similarity

Research provides evidence for the potential of semantic caching:

- **31% of ChatGPT interactions** contain semantically similar queries [30, citing Gill et al., 2024]
- **33% of search engine queries** are resubmitted [30, citing Markatos, 2001]
- GPT Semantic Cache [25, 74]: 61.6-68.8% cache hit rates across query categories, >97% positive hit accuracy at threshold 0.8
- MeanCache [75]: F1=0.89, precision=0.92 at optimal threshold for MPNet (0.83)
- Ensemble approach [27]: 92% hit ratio for equivalent queries
- vCache [24]: Up to 12.5× hit rate improvement over baselines
- Krites [49]: 3.9× increase in curated static answers served vs. baselines
- SphereLFU [76]: Semantic-aware eviction outperforms standard LRU/LFU at high density

However, the gap between hit rate and correctness remains the central challenge. High hit rates with incorrect responses can be worse than no caching at all.

---

## 5.7 Trade-off Analysis

| Factor | Exact-Match Cache | Semantic Cache (Static Threshold) | vCache (Verified) |
|--------|------------------|-----------------------------------|-------------------|
| **Hit rate** | Low (exact match only) | Medium-High | High (12.5× over static) |
| **Correctness** | Guaranteed | No guarantee | User-defined guarantee (1-δ) |
| **Latency** | Lowest on hit | Low on hit | Low on hit (online learning overhead minimal) |
| **Complexity** | Simple | Moderate | Higher (online learning) |
| **Production-ready** | Yes | Risky | Yes (with guarantees) |
| **Cross-language** | No | Possible | Possible (embedding-dependent) |

---

## 5.8 Summary

Semantic caching offers the potential for significantly higher cache hit rates than exact-match or prefix caching, but introduces fundamental correctness challenges:

1. **Static thresholds are unsafe** for production use — they provide no formal guarantees [24]
2. **Optimal thresholds are embedding-model-dependent** — GPTCache's universal 0.7 is suboptimal [75]
3. **vCache** [24] represents a breakthrough: first semantic cache with user-defined error rate guarantees
4. **Krites** [49] extends verification to tiered architectures with asynchronous LLM-judged approval
5. **Semantic caching is problematic for agentic applications** where outputs depend on external data [19]
6. **Agentic Plan Caching** [19] offers a task-level alternative that extracts and adapts structured plans
7. **Ensemble embeddings** [27] and **generative caching** [28] improve hit rates but don't address correctness
8. **Context-aware caching** [30] is needed for multi-turn conversations
9. **Semantic eviction policies** [76] require combining recency, frequency, and locality in embedding space
10. **Temporal awareness** [63] is essential for time-sensitive queries — pure semantic caching returns stale results

The field is converging toward **verified, adaptive, context-aware, temporally-aware** semantic caching that provides formal correctness guarantees while maximizing cache utility.

---

## References

- [19] "Agentic Plan Caching: Test-Time Memory for Fast and Cost-Efficient LLM Agents," arXiv:2506.14852, 2025.
- [24] Schroeder et al., "vCache: Verified Semantic Prompt Caching," arXiv:2502.03771, 2025.
- [25] "GPT Semantic Cache: Reducing LLM Costs and Latency via Semantic Embedding Caching," arXiv:2411.05276, 2024.
- [26] "Semantic Caching for Low-Cost LLM Serving: From Offline Learning to Online Adaptation," arXiv:2508.07675, 2025.
- [27] "An Ensemble Embedding Approach for Improving Semantic Caching Performance," arXiv:2507.07061, 2025.
- [28] "A Generative Caching System for Large Language Models," arXiv:2503.17603, 2025.
- [29] Bang, F., "GPTCache: An Open-Source Semantic Cache for LLM Applications," NLP-OSS 2023.
- [30] "ContextCache: Context-Aware Semantic Cache for Multi-Turn Queries," arXiv:2506.22791, 2025.
- [49] "Asynchronous Verified Semantic Caching for Tiered LLM Architectures," arXiv:2602.13165, 2026.
- [63] "Evaluating Temporal Semantic Caching and Workflow Optimization in Agentic Plan-Execute Pipelines," arXiv:2605.20630, 2026.
- [74] "GPT Semantic Cache: Reducing LLM Costs and Latency via Semantic Embedding Caching," arXiv:2411.05276, 2024.
- [75] "MeanCache: User-Centric Semantic Caching for LLM Web Services," arXiv:2403.02694, 2024.
- [76] Biton et al., "From Exact Hits to Close Enough: Semantic Caching for LLM Embeddings," arXiv:2603.03301, 2026.
