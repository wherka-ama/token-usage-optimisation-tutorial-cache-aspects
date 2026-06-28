# Chapter 3: KV Cache Mechanisms and Techniques

## 3.1 Introduction

The Key-Value (KV) cache is the foundational caching mechanism in transformer-based LLMs. It stores the Key and Value matrices computed during the attention mechanism, enabling autoregressive generation to proceed in linear (rather than quadratic) time per step. This chapter provides a comprehensive taxonomy of KV cache mechanisms, drawing primarily on the survey by Luo et al. [1] and subsequent specialized works.

---

## 3.2 The KV Cache in Transformer Models

### 3.2.1 Mechanism

At each decoding step *t*, the transformer computes attention over the sequence *X = [x₁, ..., x_t]*. For each attention head *i*, the model computes:

- Query vector: **q_i^t** from the new token embedding
- Key vector: **k_i^t** from the new token embedding
- Value vector: **v_i^t** from the new token embedding

The KV cache stores the Key and Value matrices from all previous steps: **K̂_i^{t-1}** and **V̂_i^{t-1}**. At step *t*, only **k_i^t** and **v_i^t** need to be computed; the cached matrices are appended:

- **K̂_i^t** = [**K̂_i^{t-1}**; **k_i^t**]
- **V̂_i^t** = [**V̂_i^{t-1}**; **v_i^t**]

The attention output **z_i^t** is then computed using the full cached matrices [1].

### 3.2.2 Time and Space Complexity

- **Without KV cache**: O(n²) time per step (recompute all prior KVs)
- **With KV cache**: O(n) time per step (compute only new token's KV)
- **KV cache memory**: O(n × L × d × p) where n = sequence length, L = layers, d = head dimension, p = precision bytes

For LLaMA-13B with 40 layers, 40 heads, 128-dim heads, and fp16:
- Per token: ~20 KB
- 2048 tokens: ~40 MB
- 128K tokens: ~2.6 GB
- 1M tokens: ~20 GB [11]

---

## 3.3 Taxonomy of KV Cache Optimizations

Following the taxonomy established by Luo et al. [1], KV cache optimization strategies are categorized into three levels:

### 3.3.1 Token-Level Optimization

Operates at the granularity of individual tokens without architectural changes:

| Technique | Description | Key Work |
|-----------|-------------|----------|
| **KV Cache Selection** | Retain only the most relevant tokens based on attention scores | H₂O, StreamingLLM, Quest [1] |
| **Budget Allocation** | Dynamically distribute memory across attention heads | Ada-KV [12] |
| **KV Cache Merging** | Combine similar or overlapping KV pairs | [1] |
| **Quantization** | Reduce bit precision of cached KVs | KVQuant [11], AQUA-KV [16], KV-AdaQuant [17] |
| **Low-rank Decomposition** | Reduce cache size via matrix decomposition | [1] |

### 3.3.2 Model-Level Optimization

Modifies the model architecture to improve KV cache efficiency:

| Technique | Description | Key Work |
|-----------|-------------|----------|
| **Attention Grouping & Sharing** | Share KV cache within/across layers | [1] |
| **Architecture Alteration** | New attention mechanisms or external modules | [1] |
| **Non-Transformer Architecture** | RNNs or hybrid models with fixed-size memory | Mamba, RWKV [1] |

### 3.3.3 System-Level Optimization

Optimizes infrastructure-level management:

| Technique | Description | Key Work |
|-----------|-------------|----------|
| **Memory Management** | Virtual memory, paged allocation, prefix sharing | PagedAttention/vLLM [6] |
| **Scheduling** | Prefix-aware scheduling, preemption | [1, 47] |
| **Hardware-aware Design** | Multi-GPU, I/O optimization, SSD-based | [1] |

---

## 3.4 Token-Level Techniques in Detail

### 3.4.1 KV Cache Selection (Eviction)

KV cache selection determines which tokens to retain when the cache exceeds its budget. Key approaches:

**StreamingLLM (Xiao et al., ICLR 2024)** [51]: Retains "attention sink" tokens (the first 4 tokens) plus a sliding window of recent tokens. The attention sink phenomenon shows that decoder-only LLMs assign disproportionately high attention scores to initial tokens regardless of their semantic content — the SoftMax function forces attention scores to sum to one, and when many tokens aren't strongly relevant, the model "dumps" attention on the first token simply because it's globally visible. Without retaining these sink tokens, window attention fails catastrophically when text length surpasses cache size. StreamingLLM enables Llama-2, MPT, Falcon, and Pythia to perform stable language modeling with up to **4 million tokens** without fine-tuning, achieving up to **22.2× speedup** over sliding window recomputation.

**H₂O (Zhang et al., NeurIPS 2023)** [52]: Implements a dynamic eviction policy using accumulated attention scores to identify "heavy hitter" tokens — those that consistently receive high attention across decoding steps. Balances retention of recent tokens with historically significant ones. However, AhaKV [46] shows that accumulated attention scores are biased toward initial positions (due to the attention sink phenomenon), limiting global context access for H₂O.

**SnapKV (Li et al., NeurIPS 2024)** [53]: Introduces the **observation window** approach — using a small window of recent tokens (typically 32) at the end of the prompt to identify which earlier tokens receive consistently high attention. Key insight: *"only a subset of prompt tokens convey essential information for response generation, and these tokens remain unchanged during generation"* [53]. SnapKV uses a voting process with clustering (max pooling kernel size 7) to select important KV positions. Focuses on compressing the **prompt KV cache** (the memory bottleneck in practice), not just the decoding KV cache. Easily integrated into popular frameworks with minimal code changes.

**PyramidInfer (2024)** [54]: Discovers that KV cache redundancy follows a **power law distribution** across layers — deeper layers have exponentially more redundancy. In LLaMA-2-13B, after Layer 27, perplexity remains stable even when 80% of keys and values are evicted. PyramidInfer maintains a pyramidal budget allocation: more KV retention in shallow layers, aggressive eviction in deep layers. Critically, it can compress KV cache **during the prefill phase** (not just after), reducing GPU memory and computation from the start. This distinguishes it from H₂O/Scissorhands which can only compress after the full KV cache has been computed.

**PyramidKV (2024)** [55]: Extends the pyramid concept with dynamic information funneling. Retains instruction tokens (last α tokens) across all layers, then uses attention scores from these instruction tokens to guide per-layer budget allocation. Combines the observation window approach of SnapKV with the pyramidal budget distribution of PyramidInfer.

**Quest (Tang et al., ICML 2024)** [56]: Uses **query-aware sparsity** — for each query, only loads the Top-K critical KV cache pages for attention. Achieves up to **2.23× self-attention speedup** without sacrificing accuracy. Key innovation: the query itself determines which KV pages are relevant, rather than using a fixed eviction policy.

**SAGE-KV** [14]: After prefilling, performs a one-time top-k selection at both token and head levels. Achieves 4× higher memory efficiency than StreamingLLM with improved accuracy, and 2× higher than Quest.

**KeyDiff** [13]: Evicts keys with highest cosine similarity to an "anchor" key, requiring no attention matrix materialization. Achieves only 0.04% accuracy drop on LongBench with 8K token budget (~23% KV cache reduction).

### 3.4.1.1 Evolution of Eviction Methods

The evolution of KV cache eviction reveals a clear trajectory:

1. **Static heuristics** (StreamingLLM): Fixed retention of initial + recent tokens
2. **Attention-score-based** (H₂O): Dynamic eviction based on accumulated attention
3. **Observation-window-based** (SnapKV): Use recent tokens to predict future attention patterns
4. **Layer-aware** (PyramidInfer/PyramidKV): Non-uniform budget across layers based on redundancy
5. **Query-aware** (Quest): Per-query dynamic selection of relevant KV pages
6. **Head-adaptive** (Ada-KV): Non-uniform budget across heads based on attention concentration

The state of the art combines multiple of these approaches: Ada-SnapKV and Ada-Pyramid integrate adaptive head-level budget allocation with observation-window-based eviction and pyramidal layer-level budgets [12].

### 3.4.2 Adaptive Budget Allocation

**Ada-KV** [12] identifies that uniform budget allocation across attention heads is suboptimal because heads exhibit diverse attention concentration patterns:
- Some heads focus narrowly (sparse concentration)
- Others distribute attention broadly (dispersed concentration)

Ada-KV dynamically reallocates budgets from sparse heads to dispersed heads, improving post-eviction generation quality. It is plug-and-play, integrating with existing eviction methods.

### 3.4.3 KV Cache Quantization

Quantization reduces the bit precision of cached KV pairs:

**KVQuant** [11]: Achieves sub-4-bit precision through:
- Per-channel Key quantization (matches distribution better)
- Pre-RoPE Key quantization (mitigates positional encoding impact)
- Non-uniform, sensitivity-weighted datatypes
- Per-vector dense-and-sparse quantization (isolates outliers)
- Results: <0.1 perplexity degradation at 3-bit; enables 1M context on single A100; 10M context on 8-GPU system

**AQUA-KV** [16]: Exploits cross-layer dependencies between Keys and Values, using compact adapters to predict Values from Keys and compressing only the unpredictable residual. Achieves near-lossless inference at 2-2.5 bits per value with <1% relative error.

**KV-AdaQuant** [17]: Discovers that Key matrices have consistently higher norm values and are more sensitive to quantization than Value matrices. Proposes mixed-precision: 4-bit for Keys, 2-bit for Values achieves 75.2% accuracy, while the reverse (2-bit Keys, 4-bit Values) yields only 54.7%.

**KIVI** [59]: A tuning-free **asymmetric 2-bit** quantization algorithm (ICML 2024):
- Key cache quantized **per-channel** (grouping elements along the channel dimension)
- Value cache quantized **per-token** (grouping along the token dimension)
- This asymmetry arises from the distinct distributional properties of Keys vs. Values
- Hardware-friendly design: Llama-2, Falcon, and Mistral maintain comparable performance
- Largely inspired the HuggingFace Transformers KV cache quantization implementation
- Enables 2-bit KV cache with negligible accuracy loss, dramatically reducing memory footprint

### 3.4.3.1 Quantization Method Comparison

| Method | Bits | Key Approach | Value Approach | Key Innovation |
|--------|------|-------------|----------------|----------------|
| KVQuant [11] | 2-4 | Per-channel, pre-RoPE | Per-vector dense-sparse | Non-uniform sensitivity-weighted |
| KIVI [59] | 2 | Per-channel | Per-token | Asymmetric dimension selection |
| AQUA-KV [16] | 2-2.5 | Cross-layer predictor | Residual compression | Adapter-based prediction |
| KV-AdaQuant [17] | 2-4 | Higher precision | Lower precision | Spectral norm analysis |
| Kitty (2025) | 2 | Mixed-precision | Mixed-precision | Algorithm-system co-design |

### 3.4.4 Dynamic Memory Sparsification (DMS)

DMS [15] combines the advantages of eviction and trained compression:
- Only 1K training steps for 8× compression
- Delays token eviction, implicitly merging representations before removal
- Enables inference-time "hyper-scaling": by compressing KV cache, more tokens can be generated within the same compute budget
- Qwen-R1 32B improved by 9.1 points on AIME 24, 7.6 on GPQA, 9.6 on LiveCodeBench

---

## 3.5 System-Level Techniques in Detail

### 3.5.1 PagedAttention (vLLM)

PagedAttention [6] applies OS virtual memory concepts to KV cache management:

- **Non-contiguous storage**: KV cache is partitioned into fixed-size blocks, stored in non-contiguous GPU memory
- **Block tables**: Each sequence has a block table mapping logical blocks to physical blocks (like page tables in OS)
- **Copy-on-Write**: Shared blocks are copied only when modified, enabling efficient beam search and parallel sampling
- **Near-zero waste**: Memory waste limited to the last block of each sequence (<4% vs. 60-80% in prior systems)
- **Result**: 2-4× throughput improvement at same latency

### 3.5.2 RadixAttention (SGLang)

SGLang [7] introduces RadixAttention for automatic prefix reuse:

- KV caches are stored in a **radix tree** structure
- The tree automatically detects and reuses any previously seen prompt prefix
- When a new request arrives, the tree is traversed to find the longest matching prefix
- Unmatched suffixes are computed and added to the tree
- Enables **zero-configuration prefix caching** — no explicit cache directives needed
- Result: Up to 5× faster inference for workloads with shared prefixes

### 3.5.3 LMCache: Cross-Engine KV Cache Sharing

LMCache [8] extends KV caching beyond single-engine, single-GPU boundaries:

- **Tiered storage hierarchy**: GPU → CPU → local SSD → remote backends (Redis, S3, etc.)
- **Cross-engine sharing**: KV caches generated by vLLM can be reused by SGLang and vice versa
- **Engine-independent deployment**: Runs as a standalone daemon, surviving engine crashes
- **Optimized data movement**: Batched operations, compute and I/O pipelining
- **Result**: Up to 15× throughput improvement for multi-round QA and document analysis

Key production insights from LMCache:
- Over time, total KV cache stored by users grows rapidly, far exceeding GPU memory capacity
- Over 19% of users reuse stored tokens for more than 1.5 times
- Context truncation can reduce prefix cache hit ratio by half

### 3.5.4 CacheGen: KV Cache Compression and Streaming

CacheGen [9] addresses the network transfer bottleneck for KV caches:
- Compresses KV cache for streaming over networks
- Enables remote KV cache storage and retrieval
- Uses delta encoding and quantization for compact representation

### 3.5.5 CacheBlend: Non-Prefix KV Cache Reuse

CacheBlend [10] extends caching beyond exact prefix matching:
- Enables reuse of KV caches for **non-contiguous** text segments (e.g., different paragraphs of the same document)
- Fuses cached knowledge from multiple sources
- Particularly valuable for RAG workloads where document chunks are shared across queries

### 3.5.6 DistServe: Prefill-Decode Disaggregation

DistServe [57] introduces **disaggregated prefill and decoding**:
- Assigns prefill and decoding computation to **different GPUs**, eliminating prefill-decoding interference
- Prefill (cache creation) is compute-bound; decoding (generation) is memory-bandwidth-bound — different resource profiles
- Co-optimizes resource allocation and parallelism strategy for each phase independently
- Minimizes communication overhead by placing phases according to cluster bandwidth
- **Result**: 7.4× more requests served or 12.6× tighter SLO compliance vs. state-of-the-art

This architecture has profound implications for caching: the KV cache created during prefill must be **transferred** to the decoding GPU, making KV cache transfer a first-class system concern.

### 3.5.7 Mooncake: KVCache-Centric Disaggregated Architecture

Mooncake [58] is the production serving platform for Kimi (Moonshot AI):
- **KVCache-centric design**: KV cache scheduling is central to the entire serving architecture
- Separates prefill and decoding clusters, with a dedicated **KVCache pool** leveraging underutilized CPU, DRAM, and SSD resources
- Enables KV cache reuse across requests and even across prefill-decode boundaries
- Production-scale: serves a leading LLM chatbot service
- Demonstrates that disaggregated KV cache management is viable at production scale

### 3.5.8 FlashInfer: Attention Kernel Optimization for KV Cache

FlashInfer [65] provides optimized GPU attention kernels specifically designed for diverse KV cache formats:

- **Block-sparse format**: Unified representation for page tables, radix trees, and importance masks
- **Composable formats**: Supports ragged tensors, page tables, and block-sparse row (BSR) format
- **JIT compilation**: Customizable attention template enabling adaptation to various settings
- **Compressed KV cache support**: Optimized kernels for Grouped-Query Attention (2-3× speedup vs. vLLM), Fused-RoPE Attention, and Quantized Attention (~4× for 4-bit, ~2× for 8-bit)
- **Cascade Inference**: Decouples attention of shared prefix and unique suffixes, storing shared KV cache in GPU shared memory for fast access — up to **31× speedup** vs. vLLM PageAttention for shared-prefix batch decoding on H100
- Integrated into SGLang, vLLM, and MLC-Engine
- **End-to-end**: 29-69% inter-token latency reduction, 28-30% latency reduction for long-context, 13-17% speedup for parallel generation

### 3.5.9 FlashAttention-3: Hardware-Aware Attention

FlashAttention-3 [66] exploits Hopper GPU capabilities for faster attention:
- **Asynchrony**: Warp-specialization to overlap computation and data movement via Tensor Cores and TMA
- **Interleaving**: Block-wise matmul and softmax operations interleaved for better pipeline utilization
- **Low-precision**: FP8 support with block quantization and incoherent processing (2.6× lower numerical error than baseline FP8)
- **Performance**: 1.5-2.0× speedup on H100 vs. FlashAttention-2; 740 TFLOPs/s (75% utilization) in FP16; ~1.2 PFLOPs/s in FP8
- Relevant to caching: faster attention kernels directly reduce the cost of KV cache access during decoding

---

## 3.6 Challenges in KV Cache Management

The survey by Luo et al. [1] identifies six fundamental challenges:

1. **Cache Eviction Policies**: LRU/LFU do not align with LLM attention patterns; attention-based eviction requires materializing the full attention matrix
2. **Memory Management**: KV cache grows linearly with sequence length and layers, requiring multi-tier storage coordination
3. **Latency Bottlenecks**: Cache access and update at each decoding step introduces overhead, especially on memory-bandwidth-limited hardware
4. **Compression Trade-offs**: Reducing cache size may degrade model performance if critical information is lost
5. **Dynamic Workloads**: Unpredictable access patterns require adaptive caching strategies
6. **Distributed Coordination**: Multi-node KV caches require consistency, fault tolerance, and efficient resource usage

---

## 3.7 The Rethinking of KV Cache Compression

Gao et al. [4] provide a critical practical perspective on KV cache compression:

1. **Implementation gap**: While compressing KV cache reduces memory, current implementations (FlashAttention, PagedAttention) are not optimized for compressed caches, resulting in suboptimal throughput
2. **Latency paradox**: Compressing KV cache may lead to longer outputs, increasing end-to-end latency
3. **Sample-level vs. aggregate accuracy**: Aggregate benchmarks may mask intrinsic limitations on individual samples
4. **Production adoption barrier**: Despite many algorithmic advances, KV cache compression is "not prevalent" in production environments

This highlights a gap between research benchmarks and production requirements — a theme that recurs throughout this report.

---

## 3.8 Summary

The KV cache ecosystem has evolved rapidly from simple in-GPU-memory storage to sophisticated multi-tier, cross-engine, compressed systems. Key developments include:

- **PagedAttention** [6] solved memory fragmentation with OS-inspired paging
- **RadixAttention** [7] enabled automatic prefix reuse with zero configuration
- **LMCache** [8] extended caching to enterprise scale with cross-engine sharing
- **Quantization** [11, 16, 17, 59] reduced memory footprint by 4-16× with minimal accuracy loss
- **Eviction policies** [12, 13, 14, 15, 51-56] became attention-aware, observation-window-based, layer-aware, and query-aware
- **CacheTTL** [21] introduced time-aware retention for agentic workloads
- **Disaggregated serving** [57, 58] made KV cache transfer a first-class system concern
- **Kernel optimization** [65, 66] reduced attention computation cost with hardware-aware designs

However, significant challenges remain in bridging the gap between research benchmarks and production deployment, particularly around implementation efficiency and the latency-compression trade-off.

---

## References

- [1] Luo et al., "A Survey on Large Language Model Acceleration based on KV Cache Management," arXiv:2412.19442, 2024.
- [4] Gao et al., "Rethinking Key-Value Cache Compression Techniques for Large Language Model Serving," arXiv:2503.24000, 2025.
- [6] Kwon et al., "Efficient Memory Management for Large Language Model Serving with PagedAttention," arXiv:2309.06180, 2023.
- [7] Zheng et al., "SGLang: Efficient Execution of Structured Language Model Programs," arXiv:2312.07104, 2023.
- [8] Liu et al., "LMCache: An Efficient KV Cache Layer for Enterprise-Scale LLM Inference," arXiv:2510.09665, 2025.
- [9] Liu et al., "CacheGen: KV Cache Compression and Streaming for Fast Large Language Model Serving," ACM SIGCOMM 2024.
- [10] Yao et al., "CacheBlend: Fast Large Language Model Serving for RAG with Cached Knowledge Fusion," EuroSys 2025.
- [11] Hooper et al., "KVQuant: Towards 10 Million Context Length LLM Inference with KV Cache Quantization," arXiv:2401.18079, 2024.
- [12] Xing et al., "Ada-KV: Optimizing KV Cache Eviction by Adaptive Budget Allocation," arXiv:2407.11550, 2024.
- [13] "KeyDiff: Key Similarity-Based KV Cache Eviction," arXiv:2504.15364, 2025.
- [14] Wang et al., "SAGE-KV: Self-Attention Guided KV Cache Eviction," arXiv:2503.08879, 2025.
- [15] "Inference-Time Hyper-Scaling with KV Cache Compression (DMS)," arXiv:2506.05345, 2025.
- [16] "AQUA-KV: Adaptive Key-Value Quantization for Large Language Models," arXiv:2501.19392, 2025.
- [17] "KV-AdaQuant: More for Keys, Less for Values: Adaptive KV Cache Quantization," arXiv:2502.15075, 2025.
- [21] "CacheTTL / Continuum: Efficient and Robust Multi-Turn LLM Agent Scheduling," arXiv:2511.02230, 2025.
- [46] "AhaKV: Adaptive Holistic Attention-Driven KV Cache Eviction," arXiv:2506.03762, 2025.
- [47] "LLM Query Scheduling with Prefix Reuse and Latency Constraints," arXiv:2502.04677, 2025.
- [51] Xiao et al., "Efficient Streaming Language Models with Attention Sinks (StreamingLLM)," arXiv:2309.17453, 2023 (ICLR 2024).
- [52] Zhang et al., "H₂O: Heavy-Hitter Oracle for Efficient Generative Inference of LLMs," arXiv:2306.14048, 2023 (NeurIPS 2023).
- [53] Li et al., "SnapKV: LLM Knows What You are Looking for Before Generation," arXiv:2404.14469, 2024 (NeurIPS 2024).
- [54] "PyramidInfer: Pyramid KV Cache Compression for High-throughput LLM Inference," arXiv:2405.12532, 2024.
- [55] "PyramidKV: Dynamic KV Cache Compression based on Pyramidal Information Funneling," arXiv:2406.02069, 2024.
- [56] Tang et al., "Quest: Query-Aware Sparsity for Efficient Long-Context LLM Inference," arXiv:2406.10774, 2024 (ICML 2024).
- [57] Zhong et al., "DistServe: Disaggregating Prefill and Decoding for Goodput-optimized LLM Serving," arXiv:2401.09670, 2024 (OSDI 2024).
- [58] "Mooncake: A KVCache-centric Disaggregated Architecture for LLM Serving," arXiv:2407.00079, 2024.
- [59] Liu et al., "KIVI: A Tuning-Free Asymmetric 2bit Quantization for KV Cache," arXiv:2402.02750, 2024 (ICML 2024).
- [65] "FlashInfer: Efficient and Customizable Attention Engine for LLM Inference Serving," arXiv:2501.01005, 2025.
- [66] Shah et al., "FlashAttention-3: Fast and Accurate Attention with Asynchrony and Low-precision," arXiv:2407.08608, 2024.
