# Presentation Outline: Token Usage Optimisation — Caching & Routing Aspects

**Duration:** 20–25 minutes
**Audience:** Developers using LLM APIs / GitHub Copilot CLI

---

## Slide 1: The Hidden Cost of "Context"
- **The Hook:** We want "infinite" context, but context isn't free.
- **The Problem:** Latency increases and costs explode as prompts grow.
- **The Solution:** Prompt Caching (KV-Cache Reuse) + Smart Model Routing.
- **UBB Context:** GitHub Copilot is moving to Usage-Based Billing — every token now has a price tag.

## Slide 2: How Caching Actually Works
- **Mechanism:** Practical prefix matching over the stable serialized/tokenized prompt.
- **The "Cache Line":** Providers cache the *processed* KV state of the prefix, not a final response replay.
- **Academic grounding:** KV cache survey, PagedAttention, SGLang/RadixAttention, LMCache, and cross-provider prompt-caching evaluations.
- **The Cost/Latency Delta:** 41–80% cost reduction in long-horizon agentic prompt-caching evaluations; provider discounts vary by model/API.

## Slide 3: The Golden Rule of Prompt Engineering
- **Concept:** Stable content at the START, Volatile content at the END.
- **Visual:**
  - `[System Instructions] + [Tools] + [User Query]` ✅
  - `[Timestamp] + [System Instructions] + [User Query]` ❌

## Slide 4: Experiment Walkthrough — The "Silent Killers"
- **Exp 3 (Timestamp):** How a single date string at the start invalidates the reusable prefix.
- **Exp 14 (Dynamic Tail):** The fix: move dynamic values behind stable reusable content.
- **Exp 15 (RAG Ordering):** Relevance-order churn vs. stable chunk IDs.
- **Exp 16 (Schema Canonicalization):** Same schema meaning, different bytes, different cache result.
- **Exp 7 (Model Switch):** Why pinning versions matters — confirmed by HyDRA's cache-preserving sticky routing.
- **Exp 13 (Hooks):** The risk of dynamic context in CLI tools.

## Slide 5: Side-by-Side — Best vs. Worst Practices
- **Multi-turn conversations:** Append vs. Rewrite.
- **MCP & Tools:** Static vs. Dynamic definitions.
- **RAG:** Stable IDs vs. relevance-order churn.
- **Schemas:** Canonical JSON vs. incidental map/dict ordering.
- **Skills/Agents:** Strategic usage to increase cached density.
- **Model selection:** Stay within one model per session vs. switching mid-conversation.

## Slide 6: Production Evidence — HyDRA (arXiv:2605.17106)
- **What it is:** Hybrid Dynamic Routing Architecture deployed in GitHub Copilot VS Code Chat auto-mode.
- **Key insight for caching:** HyDRA deliberately avoids mid-conversation model switches to protect the 90% prompt cache discount.
- **Sticky routing:** Router is invoked only on turn 1, after compaction, or after summarization — every other turn reuses the cached model.
- **A/B flight results (~1M users/arm):** −6.4% time-to-complete, −17.7% error rate, 7–20% COGS reduction.
- **Full presentation:** See `presentation-hydra.md`.

## Slide 7: Semantic Caching Is Different
- **Prefix caching:** exact/stable prefix reuse; safe when prefix matches.
- **Semantic caching:** approximate reuse; can false-hit when parameters, time, files, or tool results differ.
- **Exp 17:** Static threshold simulation shows precision/recall trade-offs.
- **Research takeaway:** Prefer verified/adaptive approaches (vCache/Krites), temporal classifiers, or plan/tool-level caches for agentic workflows.

## Slide 8: The Bigger Picture — Usage-Based Billing (UBB)
- GitHub Copilot is moving to UBB: tokens are the atomic unit of AI cost.
- **Resources:** GitHub Copilot billing docs, models & pricing, budget controls, token efficiency guides.
- **FinOps angle:** Token economics, tokenization multiplicity, and provider transparency concerns.
- **Full resource list:** See `README.md` and `research/references/references.md`.

## Slide 9: Summary & Takeaways
- **The Checklist:** stable first, dynamic last, canonical ordering, model pinning, append-only history.
- **Two levers:** Caching (stable prefixes) + Routing (right model for the job) — but routing must preserve cache when sessions are multi-turn.
- **Caveat:** approximate semantic caching needs verification or careful scoping.
- **Resources:** Experimental harness, research chapters, HyDRA presentation, UBB resource list, quickcard.
