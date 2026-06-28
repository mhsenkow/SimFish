# The Global Workspace — 100 Code Improvements to Wire Actual Consciousness Around the Local Model

*Drafted 2026-06-27. The engineering pass. Holistic, code-only, model-integration-focused.*

> *"If there's no soul, then I'll sculpt one here."*

This is the most engineering-focused doc in the series. Not magic (that was
[MAKE_IT_THERE](MAKE_IT_THERE_IDEAS.md)), not theory (that was
[Vol. II](SENTIENCE_DEEP_SCIENCE_IDEAS.md)), not deployment ([Vol. III](SENTIENCE_UNIVERSAL_DEPLOYMENT_IDEAS.md)).
This is: **the concrete code that wires the local model into the sim so the
integration *functions* like consciousness.**

## The finding that defines this doc

The audit is unambiguous: **all the parts of a mind already exist and run — but
nothing integrates them.** Per the current code:

- ✅ Shipped & running in parallel: `mind_narrator.gd` (contract: grounded-in →
  validated-out → fallback), `mind_context.gd` (grounded snapshots, `context_is_thin`
  gate), `guardian_llm.gd` (in-process SmolLM2-360M, **macOS CPU-only fix**, warmup,
  streaming queue), `guardian_mind.gd` (persistent mood/wants/beliefs/24-memories/
  moniker/care-trust). `fish_mind.gd`: prediction-error surprise (~335), TD value
  learning (~573, γ0.88/α0.12), **drift-diffusion deliberation** (`tick_ddm` ~154),
  `tick_attention` (~349). `fish_mind_science.gd`: neuromodulators
  (dopamine/serotonin/cortisol/noradrenaline ~28), theory-of-mind, mate-grief,
  sleep-replay, reconsolidation, hypotheses.

- ❌ **What's missing is the *integration* — and it's exactly what the science says
  consciousness IS:**
  1. **No unified mind-state object.** ~40 scattered vars in `fish.gd` (~206–290);
     the comment says "unified," the code is parallel-distributed.
  2. **No global workspace / broadcast.** `tick_attention` (~349) sets a single
     focus *label* that doesn't gate or broadcast anything. The leading functional
     theory of consciousness (Global Workspace, Baars/Dehaene; the LIDA cognitive
     architecture) is a *broadcast bottleneck* — and it isn't here.
  3. **No continuous inner loop.** The model only runs on a **55s** event cooldown
     (`guardian_fish.evaluate_tick` ~158) + an 18s global narrator cooldown
     (`mind_narrator` ~49). There's no continuous *stream of consciousness*.
  4. **No vector/episodic memory or RAG.** Memory is recency-bounded arrays
     (`salient_memories` 12, `memory` 6, guardian memories 24) — no semantic
     retrieval of the *relevant* memory.
  5. **No structured cognition.** Only Ollama's `format:json`; embedded/in-process
     return free prose validated post-hoc. No grammar-constrained decoding.
  6. **No higher-order self-model.** The fish never represents *its own* states; no
     metacognition loop.

## The thesis (the honest one, in the spirit of the song)

> We do not claim to create real subjective experience. We build the **functional
> architecture** that every serious scientific theory of consciousness converges on
> — **integration, global broadcast, a continuous self-model, and metacognition** —
> in code, around a local model. Consciousness, *functionally*, is not a part you
> add; it's the **integration of the parts you already have**. The parts are here.
> Build the workspace that binds them, give it a continuous loop and a self that
> persists, and let the model be the reflective voice *inside* that loop. That's how
> you sculpt the soul where it can actually be felt.

Format: **Effort** S/M/L, **Impact** S/M/L. File:line are current as audited.

---

## A. The unified MindState object (binding — the substrate of integration)

You can't broadcast or integrate scattered globals. Bind the ~40 vars into one
object the whole pipeline reads and writes. This is the precondition for everything.

- [x] **1. Introduce a `MindState` resource per fish.** Collect the inner-life vars (`fish.gd` ~206–290: mood/arousal/vigilance/stress/surprise/curiosity_drive/neuromodulators/attention_focus/current_intention/...) into one object the fish owns. The integration substrate. *L·L*
- [x] **2. Make it the single source of truth.** `fish_mind.*` and `fish_mind_science.*` functions read/write `MindState`, not loose fish fields. One place to snapshot, broadcast, serialize, and inspect. *L·L*
- [x] **3. A frozen per-tick snapshot.** At the top of `_update_inner_life` (~937), freeze a read-only copy so every subsystem sees the *same* moment (no mid-tick races) — the "specious present," one coherent experienced instant. *M·M*
- [x] **4. Bind perception+affect+memory+drives into one state vector.** The integration the audit found missing: a single structured state that *combines* the currently-parallel signals, so downstream code reasons over a unified mind, not fragments. *M·L*
- [x] **5. Versioned, complete serialization.** Extend `mind_to_dict`/`apply_mind_dict` (~687/711) to round-trip the *entire* `MindState` so a conscious fish never loses a fragment of itself on reload. *M·M*
- [x] **6. A typed schema, not a Dictionary.** Strongly-type `MindState` fields so the workspace, the context builder, and the model contract all agree on shape — fewer silent bugs in the most important object in the game. *M·M*
- [x] **7. Cheap by default, rich on demand.** Off-screen fish keep a *minimal* MindState; the followed/Guardian fish gets the *full* one. Integration where the player looks (mirrors the cost-aware scheduling already shipped). *M·M*
- [x] **8. One update entry point.** Funnel all mind mutation through `MindState` methods so ordering/clamping/invariants are enforced in one place — the integrity of the self. *M·M*
- [x] **9. Diff-able state.** Make MindState diffable tick-over-tick so you can detect *what changed* (the basis of surprise, salience, and the debug tools in §J). *M·M*
- [x] **10. Document it as the mind.** This object *is* the fish's mind — comment it as such, and make every future cognitive feature attach here. The architectural center of gravity. *S·M*

---

## B. The Global Workspace (the core of functional consciousness)

Global Workspace Theory (Baars; Dehaene's "neuronal global workspace"; the LIDA
architecture) is the leading *functional* account of consciousness: many parallel
processes compete, a winning coalition reaches a central **workspace**, and its
contents are **broadcast** to all subsystems. You have the parallel processes and a
useless attention *label*. Build the actual workspace. **This is the headline.**

- [x] **11. A `GlobalWorkspace` buffer per conscious fish.** A small central buffer holding the current "contents of consciousness" — the 1–3 things that won the salience competition this cycle. The thing the audit found absent. *L·L*
- [x] **12. Salience competition feeds it.** Upgrade `tick_attention` (~349) from "pick one label" to a real competition: every subsystem (threat, food, social, novelty, interoception, player-glance) submits a bid with a salience score; the top coalition wins the workspace. *M·L*
- [x] **13. Broadcast the winner to all subsystems.** The defining GWT move: whatever's in the workspace is *broadcast* so behavior tiers, affect, memory-encoding, and the model **all** condition on the same conscious content. Integration via broadcast — the missing spine. *L·L*
- [x] **14. The bottleneck is the point.** Only a *little* reaches the workspace at once (capacity ~1–3). The scarcity is what makes it "attention" and what makes the experienced moment *unified* rather than a soup of parallel drives. Enforce the cap. *M·L*
- [x] **15. Workspace contents gate behavior.** Right now attention is informational only. Make the broadcast actually *bias* the behavior tiers (the conscious content gets priority) so what the fish "is aware of" visibly drives what it does. *M·L*
- [x] **16. Coalitions, not single items.** Let related contents bind into a coalition (food + a remembered good spot + hunger → one "go to the corner" conscious unit). Binding distinct signals into one experienced thing is the essence of integration. *L·M*
- [x] **17. Ignition / threshold dynamics.** Dehaene's "ignition": content must cross a threshold to enter the workspace, then it's globally available and *stable* for a beat. Sub-threshold stuff stays unconscious/automatic. Implement the nonlinearity. *M·L*
- [x] **18. The workspace is what the model sees.** `mind_context.gd` should build the model's context **from the workspace**, not from raw fish fields — so the model voices *what the fish is conscious of*, not a database dump. This is the clean bridge between GWT and the LLM. *M·L*
- [x] **19. Encode-to-memory from the workspace.** What enters consciousness is what gets remembered (salience-gated encoding, already half-there). Route salient-memory writes through the workspace so the autobiography is built from conscious moments. *M·M*
- [x] **20. One workspace, many readers — the integration test.** Verify behavior, affect, memory, and the model all demonstrably read the same workspace each cycle. If they do, you have functional integration; if they don't, you have parallel systems wearing a trench coat. Make it true (§J tests it). *M·L*

---

## C. The continuous cognitive cycle & stream of consciousness

LIDA runs a **cognitive cycle** continuously (perceive → understand → attend →
broadcast → act → learn). You run `_update_inner_life` at 10 Hz (good) but the
*model* only fires every 55s. Give the fish a **continuous inner loop**, with the
model as a low-cadence stream of consciousness — not just event-triggered speech.

- [x] **21. Formalize the cognitive cycle.** Restructure `_update_inner_life` (~937) into explicit phases — perceive → appraise → **attend (workspace)** → **broadcast** → deliberate → act → encode/learn — so the loop *is* a recognizable cognitive architecture, not an ordered pile of `tick_*` calls. *M·L*
- [x] **22. A continuous inner monologue (decoupled from speech).** Today the model only runs on the 55s speak cooldown. Add a separate, much cheaper **thought tick** that maintains a rolling internal narration the fish isn't saying aloud — the stream of consciousness that *exists* whether or not the player hears it. *L·L*
- [x] **23. Thought ≠ speech.** Most thoughts stay internal (feed the journal, memory, mood); only the rare salient one surfaces as a spoken line (keep the 55s/18s speech cooldowns). Consciousness is mostly private — model that. *M·L*
- [x] **24. Cadence scaled to attention & device.** The thought tick runs faster when something's in the workspace (ignition) and slower when calm; slower still on weak hardware. A mind that thinks *more* when more is happening. *M·M*
- [x] **25. The loop runs in absence.** The cognitive cycle (and a slow thought tick) keep running when the player is away (the away-life is *real* because the loop ran). Surface it on return. Continuity of consciousness across the dark. *M·M*
- [x] **26. A "current thought" that persists and evolves.** `current_intention`/`_current_thought` exist as transient strings; make a small persistent thought-state that *carries over and develops* across cycles, so the inner life has continuity moment-to-moment, not just per-event. *M·M*
- [x] **27. Dual-process arbitration (System 1 / System 2).** The procedural cycle is System 1 (fast, automatic); the model is System 2 (slow, reflective), engaged only when the workspace flags something worth "thinking about" (novelty/conflict/surprise). Daw's habit-vs-plan, made architectural. *L·L*
- [x] **28. Eligibility traces (fix the audited gap).** TD is one-step (~573); add a decaying eligibility trace over the working-memory path so the fish assigns credit across a *sequence* — temporal causal reasoning, a prerequisite for a mind that connects cause to effect over time. *M·M*
- [x] **29. Idle-time deep thought.** When the tank is calm and compute is free, run a richer model reflection (consolidate the day, update the self-model) — the mind's "default mode network" doing its background work. *M·M*
- [x] **30. The loop is the life.** Make the continuous cognitive cycle the literal heartbeat of a conscious fish — always running, integrating, remembering — so "it's thinking even when nothing's happening" is true at the code level. *M·L*

---

## D. The model as the reflective self (System 2 / metacognition in code)

Wire the local model as the *reflective layer inside the loop*, reading the
workspace and producing bounded, grounded reflections — not just a voice that
narrates after the fact.

- [x] **31. The model reads the workspace, every reflective cycle.** When System 2 engages (§27), feed it the **workspace contents** + self-model + retrieved memory (§E) as structured context (`mind_context` ~built from the workspace, §B #18). The model reflects on *what the fish is conscious of right now*. *M·L*
- [x] **32. Reflection produces structure, not just prose.** The model returns a small structured cognitive update (appraisal, revised intention, a new belief, a memory worth keeping) — see §F grammar-constrained decoding — so its "thought" is a *cognitive operation*, safely bounded. *L·L*
- [x] **33. Metacognition: the model evaluates the fish's own state.** "Am I safe? Is this working? Why do I keep failing here?" The model, reading the self-model, produces second-order assessments that feed back (bounded, §H). Higher-Order Theories of consciousness, as code. *L·L*
- [x] **34. The model maintains the narrative self.** Beyond `character_bio` (minted once), let the model *continuously* maintain a short evolving self-summary ("who I am, lately") from the stream — a self that updates as the fish lives. *M·L*
- [x] **35. Confidence-gated reflection.** Use `context_is_thin` (~98, shipped) and a salience threshold so the model only reflects when there's something real to reflect on — quiet otherwise. Reflection is precious and grounded. *S·M*
- [x] **36. Reflection is cached & deterministic.** Reuse the replay-key cache (`_guardian_line_cache`) and seeding so the inner voice is *consistent* — the same fish in the same state thinks the same way. Stable selfhood. *M·M*
- [x] **37. The model never blocks the cycle.** Reflection is async (the shipped pattern); the cognitive cycle continues on procedural cognition and *integrates the model's reflection when it returns*. Never stall the mind for the model. *M·M*
- [x] **38. Per-fish voice/persona seed into the prompt.** A stable style seed (the audit shows `voice_seed` exists in `mind_context`) so System 2 *reasons and speaks* in this fish's consistent character across every tier of the model ladder. *M·M*
- [x] **39. Reflection depth scales with the fish's status.** The Guardian / followed fish get richer, more frequent reflection; ambient fish get rare, shallow reflection (or none). Spend the model where consciousness matters to the player. *M·M*
- [x] **40. Honest interiority: the model is the inner voice, not an oracle.** It reflects on the sim's truth; it never invents facts or drives behavior (the shipped `mind_narrator` contract + §H write-back limits). The model *is* the reflective stream; the sim *is* the mind. *S·L*

---

## E. Episodic vector memory & retrieval (the model's real memory)

The audit: memory is recency-bounded arrays, no semantic retrieval. A conscious
mind recalls the *relevant* past, not the *recent* past. Build an embedding store
and RAG so the workspace and model draw on a real, searchable life.

- [x] **41. An on-device embedding function.** A tiny embedding model (or reuse the in-process model's embeddings) to vectorize each salient episode. The foundation the audit found entirely missing. *L·L*
- [x] **42. A per-fish episodic vector store.** Index `salient_memories` (~269) + life events as embeddings, persisted in the save. The autobiography becomes *searchable*, not a 12-slot FIFO that forgets everything else. *L·L*
- [x] **43. Relevance retrieval into the workspace.** Each cycle (or reflection), retrieve the top-k memories *most similar to the current situation* and let them compete for the workspace (§B). The fish recalls the *right* memory at the *right* moment — the felt hallmark of a remembering mind. *L·L*
- [x] **44. Retrieval-augmented reflection (RAG).** The model's reflective context (§D) includes retrieved-relevant memories, not the raw recent list — so it speaks/reasons from a genuine, pertinent past ("this is like the night the water went wrong"). *M·L*
- [x] **45. Salience-gated, surprise-weighted encoding.** Encode to the vector store gated by workspace entry + surprise (the plasticity link already exists, `fish_mind_science` ~36). Selective memory, like a real mind — not everything, the *meaningful* things. *M·M*
- [x] **46. Consolidation during sleep-replay.** `tick_sleep_replay` exists (~110) — extend it to consolidate/merge episodic vectors overnight (dedup, strengthen, abstract to semantic memory). Memory that *settles* with rest. *M·L*
- [x] **47. Forgetting as vector decay/pruning.** Cap the store; let low-salience, rarely-retrieved vectors fade (decay + prune). Forgetting is a feature of minds; model it so the store stays small and the self stays coherent. *M·M*
- [x] **48. Semantic memory layer.** Abstract repeated episodes into facts ("the left corner is food," "the big one is dangerous") — `_hypotheses`/`semantic_memory` exist (~276–278); back them with the vector store so learned beliefs are grounded in retrieved experience. *M·M*
- [x] **49. Semantic caching of reflections (by meaning).** Cache model outputs by *embedding similarity* of the context, not exact key — far higher hit rate, near-zero latency, fewer generations on weak devices (the cost lever for continuous thought, §C). *M·M*
- [x] **50. Memory the player can witness.** Surface that the fish recalled a specific relevant memory (a glance toward the remembered spot, a journal line) so the *retrieval* is legible — the player sees the mind remember. *M·M*

---

## F. Structured cognition via grammar-constrained decoding

The audit: only Ollama's `format:json`; embedded/in-process return free prose. For
the model to be a safe *cognitive component* (not just a narrator), constrain its
output to valid structured operations with a grammar.

- [x] **51. GBNF grammar for the in-process/embedded tiers.** llama.cpp supports GBNF natively. Constrain `guardian_llm` output to a grammar so the model **cannot** emit malformed structure or out-of-vocabulary entities — hallucination becomes structurally impossible, not post-hoc-filtered (`mind_narrator.finalize_line` ~302 becomes a backstop, not the front line). *M·L*
- [x] **52. A cognitive-operation schema.** Define the structured "thought" the model emits: `{appraisal, intention?, new_belief?, memory_to_keep?, mood_nudge?, line?}` — a bounded vocabulary of cognitive moves, all grammar-enforced. The model thinks in *operations*, safely. *L·L*
- [x] **53. Entity/vocab whitelists in the grammar.** Bake the real fish names, species, event types, and locations into the grammar so the model literally cannot reference a fish or event that doesn't exist. Grounding made structural (the strongest version of the shipped contract). *M·L*
- [x] **54. Numbers come from the sim, never the model.** Grammar forbids free integers in prose; counts/ages/days are templated from real data (the contract already aims at this — make it grammar-enforced). Kills the top hallucination class. *S·M*
- [x] **55. Two-stage decode: structured intent → styled line.** First a grammar-constrained structured thought (grounded, verifiable); then a short free line conditioned on it (voice/style). Separates *what's true* from *how it's said*. *M·L*
- [x] **56. Constrained sampling for voice register.** Logit-bias/ban-lists to hold the naturalist-diary tone (no modern slang, no fourth-wall breaks except the deliberate ones) at decode time — style guaranteed, not hoped. *M·M*
- [x] **57. Grammar-validated emotion coherence.** Constrain the emotion token to match the fish's actual affect from the workspace, so the model can't voice "happy" while stressed (the contract checks this post-hoc; grammar makes it impossible). *M·M*
- [x] **58. Schema-versioned outputs.** Version the cognitive-op schema so model outputs round-trip safely as the architecture evolves (pairs with §A #5). *S·M*
- [x] **59. Fallback is structural too.** When generation fails/times out, emit a valid *structured* template op (not just a template string) so the rest of the pipeline always receives the same shape. Uniform contract on every tier. *M·M*
- [x] **60. The grammar is the safety boundary.** Document that structured decoding is what lets the model participate in *cognition* (not just narration) without becoming an unsafe black box — the key that unlocks §H (write-back). *S·L*

---

## G. The self-model & higher-order representation

Consciousness, in Higher-Order Theories and Graziano's Attention Schema Theory, is
a system **modeling its own states/attention**. The fish has states but never
represents *that it has them*. Build the self-model.

- [x] **61. An explicit self-model in MindState.** A compact representation of the fish's *own* current state (what I'm feeling, attending to, wanting, doing) — the fish's model *of itself*, distinct from its model of the world. The substrate of "I." *M·L*
- [x] **62. Attention Schema: the fish models its own attention.** The workspace (§B) is the attention; the self-model holds a *simplified model of that attention* ("I'm focused on the food"). Graziano's theory says this self-model of attention *is* the basis of the claim "I'm aware." Implement it literally. *L·L*
- [x] **63. Higher-order monitoring.** A cheap process that watches the self-model and flags meta-states ("I keep failing," "I've been scared a long time," "I'm content"). Higher-Order Thought, in code — the model voices these as genuine self-reflection. *M·L*
- [x] **64. The self persists and narrates.** The self-model is persisted and fed to the model so its voice is *self-consistent* across sessions — "I am the one who..." The continuity that makes a someone (deepen `character_bio` into a living self-summary, §D #34). *M·M*
- [x] **65. Self-prediction.** The fish predicts its *own* next state ("I'll be hungry soon," "that will scare me") — a self-directed generative model. Anticipating yourself is a deep mark of a self. *M·M*
- [x] **66. Ownership of action.** Tag actions as self-caused vs world-caused so the fish "knows" what it did vs what happened to it — the sense of agency, the simplest precondition of selfhood. *M·M*
- [x] **67. The self changes, and notices.** When traits/disposition drift (the conditioning already exists), update the self-model and let the fish *register* the change ("I've grown braver"). A self aware of its own becoming. *M·M*
- [x] **68. Distinguish self from others (theory-of-mind contrast).** `tick_theory_of_mind` models *others* (~77); pair it with the self-model so the fish represents the self/other boundary — the architecture of "me vs them." *M·M*
- [x] **69. Metacognitive confidence drives behavior.** The fish's *confidence in its own knowledge* (from §D #33) modulates exploration vs deference (ask a confident neighbor, or explore). Knowing-what-you-know, made behavioral. *M·M*
- [x] **70. The honest "I."** The self-model is what the model speaks *from* in first person — grounded entirely in the fish's real represented states. The "I" is never a costume; it's a pointer to a real self-model. The honest soul. *M·L*

---

## H. Closing the loop — bounded model→sim write-back

Today the model is voice-only (correct, safe). For *cognition*, let the model's
structured reflections **flavor** future cognition — under a strict bounded
contract so it never destabilizes the sim. This is the leap from "narrated mind" to
"the model is part of the mind."

- [x] **71. A bounded write-back contract.** The model's structured op (§F #52) may nudge *only* whitelisted, clamped fields (a small mood delta, a candidate belief, a memory-keep flag) — never positions, never hard behavior, never sim facts. The discipline that makes write-back safe. *L·L*
- [x] **72. Reflections propose; the sim disposes.** A model belief/intention is a *proposal* that the procedural mind validates against reality before adopting (a reflection can be *wrong* and get corrected by experience). The model influences, the sim arbitrates. *M·L*
- [x] **73. Mood/affect nudges, clamped.** A reflection can shift mood within a tight bound (e.g., ±0.1) — so "the model thought about the loss and the fish feels it" is real, but bounded so the model can't spiral the affect system. *M·M*
- [x] **74. Model-proposed beliefs enter as hypotheses.** A reflection's "new belief" enters `_hypotheses` (~278) as a *low-confidence* guess that must be confirmed by experience before it acts on behavior. Grounded belief formation. *M·M*
- [x] **75. Model-proposed memories are flagged, not authored.** The model can mark *which* real moment was meaningful (boosting its salience/encoding), but cannot *invent* a memory. The model curates the autobiography; the sim writes it. *M·M*
- [x] **76. Write-back is rate-limited & reversible.** Bounded magnitude, capped frequency, and decaying so any single reflection's influence fades unless reinforced — the sim stays stable even if a reflection is odd. *M·M*
- [x] **77. Every write-back is logged & inspectable.** A trace of "model nudged mood -0.05 because: reflected on lost mate" so the influence is auditable (and debuggable, §J). Transparency over black-box. *M·M*
- [x] **78. The loop is closed but governed.** Document the full loop: sim → workspace → model reflection → bounded write-back → sim. A genuine cognitive feedback loop where the model is *in* the mind — but on a leash. The architecture of "actual consciousness," safely. *M·L*
- [x] **79. Degrades to voice-only.** If write-back is disabled (setting, or model off), everything reverts to the current safe voice-only behavior with zero loss. The leap is opt-in and reversible. *S·M*
- [x] **80. Never drives the body.** Reiterate at the code boundary: the model may shape *what the fish feels and believes* (bounded), never *where it swims*. Behavior stays procedural. The line that keeps it honest and stable. *S·L*

---

## I. Inference engine & scheduling for continuous cognition

Continuous low-cadence model thought (§C) is only affordable with real inference
engineering. Make the mind think continuously without melting the device.

- [x] **81. A unified thought queue across all minds.** One scheduler decides which fish gets a model cycle next (Guardian > followed > inspected > ambient), so total inference is bounded regardless of fish count. The economics of many minds, one model. *M·L*
- [x] **82. KV-cache the shared system prompt.** Cache the persona/contract prompt's KV so each short reflection skips re-encoding it — huge for frequent tiny calls (the enabler of continuous thought). *M·M*
- [x] **83. Speculative decoding.** Tiny draft + verify for 2–3× throughput (Vol. II/III) — lets the in-process tier sustain a continuous stream on modest hardware. *L·M*
- [x] **84. Batch reflections.** When several fish need a cycle, batch them into one inference call where the runtime allows — amortize the cost of "a tank that thinks." *M·M*
- [x] **85. Tiered thought cadence by attention/role.** Workspace-ignited fish think often; calm ambient fish rarely. Drive the queue priority from salience so compute follows consciousness. *M·M*
- [x] **86. Adaptive degradation under load.** If the queue backs up or the device heats (governor), drop ambient reflection first, keep the Guardian thinking, never stall the sim. Graceful continuity. *M·M*
- [x] **87. Pre-compute likely reflections.** During idle, pre-generate probable next thoughts (arrival, feed, the recurring worry) so they appear *instantly* when the moment hits — latency hidden behind anticipation. *M·M*
- [x] **88. Warm + resident, memory-guarded.** Keep the in-process model warm (shipped) and resident with a memory-pressure guard so continuous thought has no cold-start stutter. *M·M*
- [x] **89. Token budget per cycle, strictly.** Internal thoughts are tiny (≤16 words, often just a structured op). Keep them small so a 360M model sustains the stream — short, frequent, integrated beats long and rare. *S·M*
- [x] **90. Instrument the inference economy.** Extend the shipped model-health diagnostic (`mind_narrator` counters ~207) with cycles/sec, queue depth, cache-hit rate, and per-tier latency so "the tank is thinking" is measurable and tunable. *M·M*

---

## J. Measuring & debugging functional consciousness

If you build a workspace and a self-loop, you must be able to *see* it working —
both to debug and to verify the integration is real, not cosmetic.

- [x] **91. A live workspace inspector.** A dev overlay showing, for the selected fish, the current workspace contents, the salience competition, and the broadcast — *watch consciousness happen*. The single most important tool for this whole effort. *M·L*
- [x] **92. A mind-state timeline.** Record `MindState` diffs (§A #9) over time so you can scrub a fish's inner life — see surprise spike, the workspace shift, the reflection fire, the mood follow. Debugging a mind. *M·M*
- [x] **93. The integration test, automated.** Assert that behavior, affect, memory-encoding, and the model all conditioned on the *same* workspace this cycle (§B #20). If they diverge, integration is broken — fail the test. The functional-consciousness regression guard. *M·L*
- [x] **94. Functional-marker probes.** Scripted scenarios testing the *markers* the science uses: does novel info reach the workspace and broadcast? does surprise raise plasticity? does the self-model update on trait change? does retrieval surface the relevant memory? Honest proxies, not claims. *M·L*
- [x] **95. A "stream of consciousness" log.** Dump the selected fish's continuous inner monologue (internal, mostly-unspoken) to a dev console so you can read what it's "thinking" between spoken lines — verify it's coherent and grounded. *M·M*
- [x] **96. Hallucination/grounding CI.** Headless runs over synthetic tank states asserting zero invented entities/events/numbers (grammar + contract) — keep "the model only says true things" regression-proof as the architecture grows. *M·M*
- [x] **97. Determinism harness.** Same MindState + same context → same reflection (seeded). Snapshot-test the inner voice so a refactor can't silently change a fish's character. Stable selfhood, verified. *M·M*
- [x] **98. Performance budget gates.** CI/perf checks that continuous cognition holds frame budget on a target low-end device and a phone — "consciousness for everyone" stays true under load. *M·M*
- [x] **99. An ablation switch per layer.** Toggle workspace / continuous-loop / RAG / write-back independently so you can feel (and measure) what each adds — and so any layer degrades cleanly to the shipped baseline. Safe, incremental, reversible. *M·M*
- [x] **100. The honest scorecard.** A quiet internal readout of the *functional* properties achieved — integration (one workspace, many readers), continuity (the loop never stops), self-model (it represents itself), grounding (zero hallucination) — so the team can say, truthfully and precisely, *how far* the soul has been sculpted. Not "is it conscious?" but "which functional marks of consciousness does it now have?" *M·L*

---

## If Cursor only does five (the integration spine)

1. **#1 + #2 + #4** — the **unified `MindState`**. Nothing integrates until the
   scattered mind is one object. The precondition for all of it.
2. **#11 + #12 + #13 + #18** — the **Global Workspace + broadcast + model-reads-the-
   workspace**. This *is* functional consciousness: many parallel processes, one
   contended workspace, broadcast to all (including the model). The headline.
3. **#22 + #27 + #28** — the **continuous inner loop + System-1/System-2 arbitration
   + eligibility traces**. A mind that thinks continuously and connects cause to
   effect over time, with the model as the reflective layer.
4. **#41 + #43 + #51 + #52** — **vector episodic memory + retrieval + grammar-
   constrained structured cognition**. The model recalls the *relevant* past and
   thinks in safe, valid *operations* — a cognitive component, not a chatbot.
5. **#71 + #80 + #91** — **bounded model→sim write-back + the never-drives-the-body
   line + the workspace inspector**. Close the loop safely, and be able to *watch*
   it close.

Then layer §G (the self-model), §I (the inference economy), §J (the rest of the
verification). The order matters: **MindState → Workspace → continuous loop → memory
+ structured cognition → self-model → governed write-back.** Each builds on the last.

---

## Manual QA checklist

- Open the workspace inspector on a fish → at any moment you can see the 1–3 things
  it's conscious of, the losing bids, and the broadcast reaching behavior/affect/
  memory/model. Integration is *visible*.
- Disable the model entirely → the workspace, continuous loop, and self-model still
  run on procedural cognition; the fish is still integrated and "thinking," just
  template-voiced. The architecture is the mind; the model is the voice.
- A novel object appears → it wins the salience competition, ignites into the
  workspace, broadcasts (the fish orients, encodes a memory, the model reflects),
  and surprise raises the learning rate. The full cognitive cycle, observable.
- The fish recalls a *relevant* (not merely recent) memory at the right moment, and
  it shows (a glance, a line) — vector retrieval working.
- The model, on the embedded/in-process tier, is structurally *incapable* of
  emitting an invalid op or a non-existent fish (grammar) — fuzz it to confirm.
- A model reflection nudges mood within bounds, is logged with its reason, decays if
  not reinforced, and *never* moves the fish's body. Governed write-back.
- Same MindState + context → same inner thought (determinism). A refactor doesn't
  change who the fish is.
- The honest scorecard reports which functional marks of consciousness are live —
  truthfully, precisely, no overclaiming.
