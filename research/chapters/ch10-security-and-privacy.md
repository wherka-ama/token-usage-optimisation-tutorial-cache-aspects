# Chapter 10: Security and Privacy Implications of Caching

## 10.1 Introduction

While caching improves performance and reduces cost, it introduces significant security and privacy risks that are only beginning to be studied systematically. The KV cache, semantic caches, and prefix-sharing mechanisms all create potential attack surfaces. This chapter examines the security landscape of LLM caching, drawing on recent work from NDSS, arXiv, and other venues.

---

## 10.2 KV Cache Sharing Attacks

### 10.2.1 The Multi-Tenant Problem

Modern LLM serving frameworks (vLLM, SGLang) share KV caches for identical token sequences among multiple users to save memory and computation. Wu et al. [37] present the **first investigation of security risks** associated with this practice.

### 10.2.2 PROMPTPEEK Attack

The PROMPTPEEK attack [37] demonstrates that KV cache sharing creates **side-channel attack vectors** allowing unauthorized reconstruction of user prompts:

- **Three attack scenarios** with varying degrees of prior knowledge
- The adversary can **reverse-engineer prompts** from other users
- Unlike previous studies that only approximate prompt content, PROMPTPEEK **accurately reconstructs** prompts
- Prompts may contain sensitive information like bank account numbers or health records

The attack exploits the timing and behavior differences between cache hits and misses to infer the content of other users' prompts.

### 10.2.3 Attack Conditions

Wu et al. [37] outline three critical attack conditions:
1. **Cache co-residency**: The attacker and victim share the same serving infrastructure
2. **Cache observability**: The attacker can detect whether their queries hit or miss the cache
3. **Prefix knowledge**: The attacker has partial knowledge of the victim's prompt structure

### 10.2.4 Implications

- KV cache sharing is "not secure" in multi-tenant environments [37]
- Service providers and framework developers must consider these risks
- The attack is practical and low-cost
- This creates a tension between **efficiency (sharing) and security (isolation)**

---

## 10.3 Timing Side Channels

### 10.3.1 Cache Hit/Miss Timing Differences

The "Early Bird Catches the Leak" work [39] discovers **timing side channels** in LLM serving systems arising from shared caches and GPU memory allocations:

- **Cache hits** have consistently fast latency regardless of document length
- **Cache misses** grow noticeably slower with larger documents
- This timing difference can be exploited to infer whether specific content was cached by another user

### 10.3.2 Attack Methodology

1. The attacker prepares a set of "interested" documents
2. The victim submits documents, some from the interested set and some not
3. The attacker measures response times for their queries
4. Cache hit/miss timing differences reveal which documents the victim submitted

### 10.3.3 Scope

The attack targets both:
- **KV cache**: Per-request in-memory state reused throughout service time
- **Semantic cache**: Shared response cache across users

Experimental studies on popular online LLM services demonstrate that these privacy risks are "completely realistic, with significant consequences" [39].

---

## 10.4 KV Cache Content Reconstruction

### 10.4.1 Shadow in the Cache

Luo et al. [38] provide the **first comprehensive analysis** of KV cache privacy vulnerabilities, demonstrating three attack vectors:

1. **Inversion Attack**: Directly reconstructs sensitive user inputs from the KV cache
2. **Collision Attack**: More broadly applicable and potent; exploits KV cache collisions
3. **Injection Attack**: Semantic-based attack that manipulates cached representations

### 10.4.2 KV-Cloak Defense

To mitigate these vulnerabilities, Luo et al. [38] propose **KV-Cloak**:
- Uses a **reversible matrix-based obfuscation** scheme
- Combined with **operator fusion** for efficiency
- Reduces reconstruction quality to random noise
- Achieves robust security with **virtually no degradation in model accuracy**
- Minimal performance overhead

### 10.4.3 KV-Shield

KV-Shield [40] addresses on-device LLM inference security:
- Protects KV pairs from malicious processes on mobile GPUs
- Uses **permutation-based encryption** in a Trusted Execution Environment (TEE)
- Ensures insecure GPUs cannot access original KV pairs
- Even if permuted KV pairs are leaked, user conversation cannot be reconstructed
- FHE (Fully Homomorphic Encryption) is too computation-intensive; permutation is lightweight

---

## 10.5 Semantic Cache Privacy Risks

### 10.5.1 Cross-User Information Leakage

Semantic caches that store (prompt, response) pairs across users create additional risks:
- If user A's query is semantically similar to user B's cached query, user A may receive user B's response
- This can leak sensitive information if the response contains user-specific data
- The risk increases with lower similarity thresholds (more cache hits = more potential leakage)

### 10.5.2 Mitigation

- **Per-user caches**: Isolate caches across users (reduces hit rate but improves privacy)
- **vCache** [24]: Per-embedding thresholds reduce false positives, indirectly reducing leakage
- **MeanCache** (cited in [28]): Places a local cache on each user's device, using federated learning for collaborative training while preserving privacy

---

## 10.6 The Security-Efficiency Trade-off

| Mechanism | Efficiency Benefit | Security Risk | Mitigation |
|-----------|------------------|---------------|------------|
| **KV cache sharing** | Memory savings, faster inference | Prompt reconstruction [37] | Per-tenant isolation |
| **Prefix caching** | Reduced prefill computation | Timing side channels [39] | Constant-time cache access |
| **Semantic caching** | Higher hit rates | Cross-user leakage | Per-user caches, verified thresholds [24] |
| **Cross-engine sharing** | Enterprise-scale reuse [8] | Multi-tenant exposure | Encryption, access control |
| **KV cache compression** | Memory reduction | Quality degradation may leak structure | Near-lossless methods [16] |

---

## 10.7 Summary

Security and privacy are emerging as critical concerns in LLM caching:

1. **KV cache sharing** in multi-tenant environments enables prompt reconstruction attacks [37]
2. **Timing side channels** from cache hit/miss differences can reveal user behavior [39]
3. **KV cache content** can be directly reconstructed via inversion, collision, and injection attacks [38]
4. **Semantic caches** risk cross-user information leakage
5. **Defense mechanisms** (KV-Cloak [38], KV-Shield [40]) provide protection with minimal overhead

The fundamental tension is between **efficiency (sharing caches)** and **security (isolating caches)**. As LLM serving scales to millions of users, resolving this tension becomes a first-order concern for production deployments.

---

## References

- [8] Liu et al., "LMCache," arXiv:2510.09665, 2025.
- [24] Schroeder et al., "vCache," arXiv:2502.03771, 2025.
- [37] Wu et al., "I Know What You Asked: Prompt Leakage via KV-Cache Sharing in Multi-Tenant LLM Serving," NDSS 2025.
- [38] Luo et al., "Shadow in the Cache: Unveiling and Mitigating Privacy Risks of KV-cache in LLM Inference," arXiv:2508.09442, 2025.
- [39] "The Early Bird Catches the Leak: Unveiling Timing Side Channels in LLM Serving Systems," arXiv:2409.20002, 2024.
- [40] "KV-Shield: Protecting KV Cache in On-Device LLM Inference," arXiv:2409.04040, 2024.
