# Chapter 12: Future Directions and Open Problems

## 12.1 Introduction

This chapter synthesizes the open problems and future research directions identified across the caching literature. The field is evolving rapidly, with significant gaps between research benchmarks and production deployment, and emerging challenges from the scaling of context windows, agentic workloads, and multi-tenant serving.

---

## 12.2 Bridging Research and Production

### 12.2.1 The Compression-Production Gap

Gao et al. [4] identify that KV cache compression techniques are "not prevalent in production environments" despite extensive research. Key gaps:

1. **Implementation inefficiency**: Current implementations (FlashAttention, PagedAttention) are not optimized for compressed caches
2. **Throughput paradox**: Compressed caches may reduce memory but not improve throughput due to kernel incompatibility
3. **Output length increase**: Compression may lead to longer outputs, increasing end-to-end latency
4. **Sample-level vs. aggregate accuracy**: Benchmarks mask per-sample failures

### 12.2.2 The Need for Production-Grade Benchmarks

Future work should:
- Evaluate compression under production serving conditions (not just offline benchmarks)
- Measure end-to-end latency (not just memory savings)
- Report per-sample accuracy distributions (not just aggregates)
- Test with production workloads (not synthetic sequences)

---

## 12.3 Adaptive and Multi-Stage Optimization

### 12.3.1 No Single Technique Dominates

The KV cache optimization survey [2] reveals that "no single technique dominates across all settings; instead, the optimal strategy depends on context length, hardware constraints, and workload characteristics."

### 12.3.2 Adaptive Pipeline Vision

Future systems should implement **adaptive, multi-stage optimization pipelines**:
- **Stage 1**: Token-level selection (eviction) for initial memory reduction
- **Stage 2**: Quantization for further compression
- **Stage 3**: System-level scheduling for throughput optimization
- **Adaptive controller**: Dynamically selects techniques based on workload, hardware, and quality requirements

### 12.3.3 Workload-Aware Adaptation

- **Long-context single requests**: Prioritize eviction + quantization
- **High-throughput datacenter serving**: Prioritize scheduling + memory management
- **Edge devices**: Prioritize aggressive compression
- **Multi-turn conversations**: Prioritize TTL-based retention (CacheTTL [21])
- **Accuracy-critical reasoning**: Prioritize near-lossless methods (AQUA-KV [16])

---

## 12.4 Semantic Caching Evolution

### 12.4.1 Formal Guarantees

vCache [24] represents a breakthrough but is just the beginning:
- **Multi-modal semantic caching**: Extending verified caching to image, audio, and video inputs
- **Cross-language caching**: Language-invariant embeddings for multi-lingual applications
- **Context-aware verification**: Error rate guarantees that adapt to conversation context

### 12.4.2 Generative Caching

The generative caching approach [28] points toward:
- **Synthesis from multiple cached responses**: Generating novel answers from cached fragments
- **Cache as knowledge base**: Mining cached responses for information retrieval
- **Quality-aware synthesis**: Balancing novelty with correctness

### 12.4.3 Agentic Plan Caching Extensions

Future directions for plan caching [19]:
- **Cross-domain plan transfer**: Reusing plans across different application domains
- **Hierarchical plan templates**: Multi-level abstraction (high-level strategy → mid-level tactics → low-level actions)
- **Plan quality scoring**: Automatically evaluating cached plan quality before reuse
- **Online plan evolution**: Continuously improving cached plans based on execution feedback

---

## 12.5 Security and Privacy

### 12.5.1 Open Security Problems

- **Constant-time cache access**: Eliminating timing side channels [39] without throughput loss
- **Secure multi-tenant caching**: Enabling KV cache sharing without prompt leakage [37]
- **Federated semantic caching**: Collaborative caching across organizations without data sharing
- **Hardware-assisted security**: TEE-based KV cache protection with acceptable overhead [40]

### 12.5.2 The Security-Efficiency Frontier

Research should map the Pareto frontier between security and efficiency:
- What is the minimum isolation needed to prevent attacks?
- Can partial sharing (e.g., sharing only system prompt KV cache) be safe?
- How do defense mechanisms (KV-Cloak [38], KV-Shield [40]) scale to production?

---

## 12.6 Reproducibility Infrastructure

### 12.6.1 The Determinism Challenge

- **Prefix caching breaks determinism** [34, 35] — can we have both?
- **LLM-42** [35] shows that selective determinism is possible but with overhead
- **TBIK** [36] solves TP-size determinism but not batch-size determinism
- **LayerCast** [33] reduces divergence but doesn't eliminate it
- **Batch-invariant kernels** [67] solve batch-size determinism but strip GPU parallelism
- **Prefill-decode invariance gap** [35]: cached KV from prefill may not match decode output — LLM-42 cannot support cross-turn prefix cache sharing

### 12.6.2 Future Reproducibility Directions

- **Cache-aware deterministic kernels**: GPU kernels that produce identical results regardless of batch composition
- **Prefill-decode invariant kernels**: Ensuring prefill and decode produce identical KV values for the same token
- **Reproducibility APIs**: Provider APIs that guarantee deterministic outputs with caching enabled
- **Reproducibility metadata**: Standardized reporting of system configuration, cache state, and numerical precision
- **Verification frameworks**: Tools that verify reproducibility across runs and configurations
- **Throughput-preserving determinism**: Batch-invariant kernels that maintain GPU parallelism (current approaches sacrifice throughput)

---

## 12.7 Agentic Caching

### 12.7.1 The Agent Cache Stack

Future agentic systems will need a **multi-layer cache stack**:
- **Layer 1**: KV cache (token-level, within request)
- **Layer 2**: Prefix cache (cross-request, same model)
- **Layer 3**: Plan cache (cross-task, adapted templates) [19]
- **Layer 4**: Tool result cache (cross-session, data caching) [62, 64]
- **Layer 5**: Response cache (cross-user, verified semantic) [24]
- **Layer 6**: Temporal cache (time-aware validity routing) [63]

Each layer has different correctness guarantees, TTLs, and eviction policies. The hierarchical caching architecture [64] proposes explicit multi-level management with different TTL and invalidation requirements per level.

### 12.7.2 LLM-Managed Caching

LLM-dCache [23] points toward LLMs managing their own caches. Future directions:
- **Meta-caching**: LLMs reasoning about what to cache and when to invalidate
- **Cross-agent cache sharing**: Agents in a multi-agent system sharing cached knowledge
- **Cache-aware planning**: Agents that plan their actions considering cache implications
- **Self-tuning cache parameters**: LLMs adjusting TTL, thresholds, and eviction policies
- **Training-time caching**: CacheRL [62] shows cached rollouts enable 100x cheaper RL training — how does this affect learned agent behaviour?

### 12.7.3 Long-Horizon Agent Caching

For agents that execute over hours or days:
- **Persistent KV cache**: Surviving across sessions and engine restarts [8]
- **Incremental cache updates**: Updating cached state without full recomputation
- **Cache-aware context management**: Summarization that preserves cache boundaries
- **Cross-session plan reuse**: Reusing plans from prior sessions for similar tasks
- **Proactive cache staging**: Pythia [60] demonstrates workflow-predictable cache warming — extending to unpredictable workflows remains open
- **Dynamic workflow prediction**: PBKV [61] handles dynamic workflows but with conservative prefetching — bolder prediction strategies are unexplored

---

## 12.8 Hardware and Systems Co-Design

### 12.8.1 Hardware-Aware Caching

- **SSD-based KV cache**: Using NVMe SSDs for large-scale KV storage [1]
- **Heterogeneous computing**: GPU + CPU + FPGA co-design for cache management
- **Memory-bandwidth optimization**: Custom hardware for KV cache access patterns
- **Network-attached KV cache**: Remote KV cache pools accessible over high-speed networks

### 12.8.2 Disaggregated Architecture

- **Prefill-decode disaggregation**: Separate prefill (cache creation) from decode (generation) on different GPU pools [57, 58]
- **KVCache-centric design**: Mooncake [58] demonstrates production-scale KV cache as a first-class system resource
- **Cache-as-a-service**: Centralized KV cache services shared across inference engines
- **Multi-region caching**: Geographically distributed KV cache for global serving
- **KV cache transfer optimization**: Disaggregation makes KV transfer a first-class concern — optimizing network transfer of KV tensors

---

## 12.9 Standardization and Tooling

### 12.9.1 Cache Metrics Standardization

- Standardized cache hit rate definitions across providers
- Standardized cost reporting (including cache discounts)
- Standardized reproducibility metadata
- Open benchmarks for cache performance evaluation

### 12.9.2 Open-Source Infrastructure

- **LMCache** [8] as a vendor-neutral KV cache layer
- **vLLM** [6] and **SGLang** [7] as open serving engines
- **vCache** [24] as open verified semantic cache
- **Cache Saver** [32] and **Mnimi** [31] as open client-side frameworks
- Need for: Open agentic plan caching, open workflow-aware eviction, open security tools

---

## 12.10 Summary of Open Problems

| Problem | Current State | What's Needed |
|---------|--------------|---------------|
| **Production-grade KV compression** | Research benchmarks only | Production implementations, end-to-end latency evaluation |
| **Adaptive multi-stage caching** | Individual techniques | Integrated pipelines with workload-aware selection |
| **Verified semantic caching** | vCache for text | Multi-modal, cross-language, context-aware |
| **Secure multi-tenant caching** | Attacks demonstrated | Defense mechanisms with acceptable overhead |
| **Cache-aware determinism** | Tension identified | Kernels that are both cache-efficient and deterministic |
| **Prefill-decode invariance** | Gap identified [35] | Invariant kernels enabling safe cross-turn prefix cache sharing |
| **LLM-managed caching** | Proof of concept [23] | Production frameworks, meta-caching |
| **Training-time caching effects** | CacheRL [62] demonstrates feasibility | Studies on how cached rollouts affect learned agent behaviour |
| **Temporal-aware caching** | Temporal classifier [63] | Integration with all caching layers, formal temporal validity guarantees |
| **Dynamic workflow prediction** | PBKV [61] with conservative prefetching | Bolder prediction strategies, multi-step horizon optimization |
| **Long-horizon agent caching** | CacheTTL for tool calls | Full session persistence, cross-session reuse |
| **Standardization** | Provider-specific APIs | Open standards for metrics, benchmarks, interfaces |

---

## 12.11 Conclusion

The field of LLM caching has evolved from simple KV cache storage to a rich ecosystem of multi-level, multi-modal, verified, and workflow-aware caching systems. The academic literature of 2023-2026 has established the foundational mechanisms, identified the key trade-offs, and demonstrated production-scale benefits.

The next frontier lies in:
1. **Bridging the research-production gap** for compression techniques
2. **Building adaptive, multi-stage caching pipelines** that respond to workload characteristics
3. **Providing formal correctness guarantees** for all caching levels
4. **Securing multi-tenant caching** against side-channel attacks
5. **Enabling cache-aware determinism** for reproducible inference
6. **Developing LLM-managed caching** where agents reason about their own cache strategies

As context windows scale to millions of tokens, agentic workloads become the norm, and usage-based billing makes every token count, caching will only grow in importance. The research community is well-positioned to address these challenges, with a strong foundation of recent work to build upon.

---

## References

- [1] Luo et al., "A Survey on Large Language Model Acceleration based on KV Cache Management," arXiv:2412.19442, 2024.
- [2] Xu et al., "KV Cache Optimization Strategies for Scalable and Efficient LLM Inference," arXiv:2603.20397, 2026.
- [4] Gao et al., "Rethinking Key-Value Cache Compression Techniques," arXiv:2503.24000, 2025.
- [6] Kwon et al., "PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache," arXiv:2510.09665, 2025.
- [16] "AQUA-KV," arXiv:2501.19392, 2025.
- [19] "Agentic Plan Caching," arXiv:2506.14852, 2025.
- [21] "CacheTTL," arXiv:2511.02230, 2025.
- [22] "Efficient LLM Serving for Agentic Workflows," arXiv:2603.16104, 2026.
- [23] "LLM-dCache," arXiv:2406.06799, 2024.
- [24] Schroeder et al., "vCache," arXiv:2502.03771, 2025.
- [28] "A Generative Caching System for Large Language Models," arXiv:2503.17603, 2025.
- [31] Dai et al., "Mnimi," arXiv:2511.22118, 2025.
- [32] Potamitis et al., "Cache Saver," Findings of EMNLP 2025.
- [33] Yuan et al., "Numerical Nondeterminism," arXiv:2506.09501, 2025.
- [35] "LLM-42," arXiv:2601.17768, 2026.
- [36] Zhang et al., "TBIK," arXiv:2511.17826, 2025.
- [37] Wu et al., "PROMPTPEEK," NDSS 2025.
- [38] Luo et al., "Shadow in the Cache," arXiv:2508.09442, 2025.
- [39] "Timing Side Channels," arXiv:2409.20002, 2024.
- [40] "KV-Shield," arXiv:2409.04040, 2024.
- [57] Zhong et al., "DistServe," arXiv:2401.09670, 2024.
- [58] "Mooncake," arXiv:2407.00079, 2024.
- [60] "Pythia," arXiv:2604.25899, 2026.
- [61] "PBKV," arXiv:2605.06472, 2026.
- [62] "CacheRL," arXiv:2606.14179, 2026.
- [63] "Temporal Semantic Caching," arXiv:2605.20630, 2026.
- [64] "Hierarchical Caching for Agentic Workflows," MAKE 2026.
- [67] He et al., "Defeating Nondeterminism in LLM Inference," Thinking Machines Lab, 2025.
