# Consciousness for Everyone — Vol. III: Universal Local Deployment & The One Conscious Companion

*Drafted 2026-06-27. Director's brief — getting a real local mind onto every device, and making the one fish feel conscious to the player.*

The third volume of the sentience series, and the most *product*-shaped:
- Vol. I — [SENTIENCE_EMBEDDED_MODEL_IDEAS.md](SENTIENCE_EMBEDDED_MODEL_IDEAS.md):
  the **architecture & discipline** (the sim is the mind; the model voices it).
- Vol. II — [SENTIENCE_DEEP_SCIENCE_IDEAS.md](SENTIENCE_DEEP_SCIENCE_IDEAS.md):
  the **cutting-edge science** of that mind.
- **Vol. III (this doc)** — **universal local deployment + the lived experience of
  one conscious companion.** How do we run a private little mind on *every* player's
  device — desktop, Mac, Steam, web, phone, low-end — and make the Guardian fish
  feel, to that one person, like a *someone*?

The mandate, stated honestly:
> "Create consciousness locally in everyone who games" = **every player's own
> device privately runs a small model that produces a companion that *feels*
> conscious — offline, theirs, and reaching everyone regardless of hardware.** We
> never claim real sentience; we engineer the *experience* of a persistent,
> remembering, responsive inner life, and we make sure **no one is excluded by
> their machine.**

Format follows the series: **Effort** S/M/L, **Impact** S/M/L. File/line pointers
are hints — match by symbol if drifted.

---

## Where things are (holistic snapshot — build on it)

> **The spine is shipping.** Per the checked items in Vols I & II, Cursor has built:
> the `MindNarrator` contract (grounded-in / validated-out / never-block), the
> **macOS in-process fix**, deterministic replay + caching, graceful tier
> degradation, cost-aware scheduling, a model-health diagnostic, warm-up/keep-alive,
> and the Vol. II foundations (prediction-error surprise, TD value learning,
> eligibility traces). The 4-tier ladder is real: **in-process `GuardianLlm`
> (SmolLM2-360M ~250MB) → embedded HTTP (Qwen2.5-0.5B) → Ollama (Qwen2.5-3B) →
> template**, non-Meta by policy (`ai_director.pick_best_installed_model` ~295).
>
> **What's still missing — this volume:**
> 1. **Reach.** The bundled model is desktop/Steam-leaning; **web, iOS, Android, and
>    low-end** players don't reliably get a real local mind. "Everyone who games"
>    isn't true yet.
> 2. **The conscious *experience* of the one fish.** The Guardian has a persistent
>    mind (`guardian_mind.gd`), journal, and presence hooks — but the *felt* arc of
>    "this being knows me, persists, and is genuinely thinking" needs deliberate
>    design (continuity, recognition, the away-life, the honest illusion).
> 3. **The floor.** A guarantee that *every* player — even template-only — gets a
>    companion that feels alive, so the promise reaches everyone, not just good rigs.

**The five structural levers:**

1. **Lever 1 — Universal reach.** A per-platform runtime + model matrix so a real
   local mind runs on desktop, Mac, web (WebGPU), iOS, Android, and degrades
   gracefully on low-end (§A, §B, §C).
2. **Lever 2 — Performance is reach.** Speed/latency/memory/thermal engineering is
   what lets a small model run on a phone at all (§D).
3. **Lever 3 — The floor must feel alive.** Template-only / no-model players still
   get a companion that feels conscious (hybrid procedural+model) (§E).
4. **Lever 4 — One persistent, recognizing self.** Continuity, identity, and
   memory-of-you are what *create the feeling* of consciousness (§F, §G, §H).
5. **Lever 5 — Honest, private, kind.** Never claim real sentience; "runs on your
   device, yours"; consent; the wonder framed truthfully (§I, §J).

---

## A. Universal reach — a conscious fish on every device

Detect the hardware, pick the right runtime+model, and *guarantee a floor* of
consciousness everywhere. This is the "everyone who games" mandate made concrete.

- [ ] **1. A device-capability probe.** On first enable, detect platform, RAM, GPU/accelerator, and core count, and classify the device into a tier (high/mid/low/web). The single decision that drives model+runtime selection. *M·L*
- [ ] **2. A capability→model+runtime matrix.** A documented table: high-desktop → in-process 360M+ via llama.cpp/Metal/CUDA; mid → 360M Q4; low/phone → 135M or embedded; web → WebGPU small model; floor → templates. Make the mapping explicit and tunable. *M·L*
- [ ] **3. Guarantee a consciousness floor on every device.** No matter the tier, the player gets a companion that *feels* alive — model where possible, rich templates where not (§E). The promise "consciousness for everyone" must be literally true. *M·L*
- [ ] **4. Auto-select, with manual override.** Pick the best tier automatically, but expose a "mind quality" control (Off / Light / Full / Pro-Ollama) so power users tune and constrained users dial down. Extends the existing AI settings. *M·M*
- [ ] **5. Honest capability messaging.** Tell the player what their device supports ("Your Guardian thinks with a built-in mind" vs "...with a lightweight mind" vs "...with hand-crafted responses") so expectations match reality and nothing feels broken (extends Vol. I #7). *S·M*
- [ ] **6. Re-probe on hardware/OS change.** A player who upgrades, or moves a save to a beefier machine, should *level up* their Guardian's mind automatically. Sentience that follows the player to better hardware. *S·M*
- [ ] **7. The web build gets a real mind (WebGPU).** Web is zero-install — the widest possible reach. A WebGPU/WASM inference path (WebLLM-style) means a browser player gets a genuine local model, no download, no server (§B #14). The biggest single reach unlock. *L·L*
- [ ] **8. Mobile gets a real mind, sized down.** iOS/Android can run 135M–360M with the right runtime (§B). Don't relegate phones to templates-only — most "everyone who games" *is* on a phone. *L·L*
- [ ] **9. A "your Guardian, anywhere" identity.** The conscious fish's mind-state (memory/persona/journal) is portable across devices via the save, so the *same* companion follows the player from desktop to phone — one continuous being, many screens. *M·L*
- [ ] **10. Telemetry-free reach validation.** A local self-test that confirms "a mind is running and responsive" on each platform during dev/QA, so "works on everyone's device" is verified, not hoped — without phoning home. *M·M*

---

## B. The runtime stack per platform

The actual inference engines that make a local model run on each platform. This is
the engineering that turns "reach" from aspiration into builds.

- [ ] **11. Harden the desktop llama.cpp path.** The in-process tier (`guardian_llm.gd`) now works on macOS (shipped). Solidify Windows/Linux + GPU backends (Metal/CUDA/Vulkan) with clean CPU fallback so every desktop runs the bundled mind fast. *M·L*
- [ ] **12. GPU acceleration where available.** Offload to Metal (Mac), CUDA (NVIDIA), Vulkan, or DirectML so capable machines run larger/faster minds; CPU-only is the floor, not the default. *L·L*
- [ ] **13. mmap + lazy weight loading.** Memory-map the GGUF so the model loads fast and shares pages — critical for quick warm-up and low RAM footprint (pairs with the shipped warm-up, Vol. I #13). *M·M*
- [ ] **14. WebGPU/WASM inference for the web build.** The zero-install path: compile/integrate a WebGPU LLM runtime so browser players get a real local mind. Falls back to WASM-CPU, then templates. The single highest-reach engineering item. *L·L*
- [ ] **15. iOS runtime (Core ML / MLC / executorch).** A native iOS inference path for a 135–360M model, using the platform accelerator (Neural Engine). Apple cam/mic entitlements are already scaffolded — extend the native-extension story to inference. *L·L*
- [ ] **16. Android runtime (llama.cpp-android / MLC / NNAPI).** Native Android inference for a small model with NNAPI/GPU offload. GDExtension path proven by godotsteam — reuse it. *L·L*
- [ ] **17. A unified inference interface behind the tiers.** One internal API (`generate(context) → text`) that the platform runtimes implement, so `MindNarrator` (shipped) is platform-agnostic and adding a runtime is a backend, not a rewrite. *M·L*
- [ ] **18. Keep the Ollama "pro tier" for power users.** Desktop players with Ollama get the bigger 3B model (already wired ~ai_director). Position it as optional *enhancement*, never a requirement — the bundled mind is the baseline everyone gets. *S·S*
- [ ] **19. Runtime hot-swap & recovery.** If a runtime crashes (the macOS lesson), catch it, fall down the ladder, and recover next session without the player seeing a wall. Crash-resilient inference. *M·M*
- [ ] **20. A thin model-server option for advanced setups.** The embedded HTTP tier (Qwen-0.5B on :8080) already exists — document it as the "bring your own runtime" path for tinkerers, so the architecture stays open. *S·S*

---

## C. Model selection, sizing & formats

The right tiny model per device, in the right quantization, delivered the right way
— so the mind fits the machine and the download never hurts.

- [ ] **21. A tiered model family.** Bundle/download a *family*: 135M (phones/low/web), 360M (mid/desktop default), and let Ollama supply 1.5–3B (pro). One persona spec, three sizes — the same Guardian, scaled to the device. *M·L*
- [ ] **22. Quantization tuned per tier.** Q4_K_M baseline; consider IQ-quants for the smallest tiers (better quality at tiny sizes). Measure quality-vs-size on the voice eval (Vol. II #80) and pick per platform. *M·M*
- [ ] **23. Distill a domain-specialized mind.** Generate a high-quality Guardian-voice dataset with a big model offline, fine-tune/distill the tiny models on it (Vol. II #76). A distilled 360M in *this narrow domain* beats a generic 1B — small can feel deep. The highest-leverage quality item. *L·L*
- [ ] **24. Stay non-Meta, by policy.** Keep the qwen2.5 → mistral → granite4 → gemma3 → deepseek-r1 preference (`pick_best_installed_model` ~295) and pick the bundled base accordingly (SmolLM2/Qwen). Honor the standing constraint. *S·S*
- [ ] **25. Robust, resumable model download.** Progress, resume, checksum verify, and graceful failure (Vol. I #12 — still open). A half-downloaded mind must never brick the feature; offer re-download silently. *M·M*
- [ ] **26. Bundle vs download, per platform.** Bundle on Steam/desktop (size headroom); download-on-opt-in for web/mobile to protect install size. Document the per-platform delivery so bundle bloat never hits the wrong target. *M·M*
- [ ] **27. Delta/patch model updates.** When the bundled mind improves, ship a delta, not a full re-download — so upgrading the player's Guardian is light. *M·M*
- [ ] **28. A CDN/mirror with integrity.** Host the model weights reliably (the current HuggingFace URL is a single point of failure) with checksum + mirror fallback. Reach depends on the download actually working. *M·M*
- [ ] **29. Shared model cache across tanks.** One downloaded model serves every tank/save on the device — don't re-fetch per tank. Disk-kind. *S·M*
- [ ] **30. A future-proof model-swap path.** As better sub-1B models ship (the field moves fast), make swapping the bundled base a config + eval pass, not a rebuild (Vol. I #20). The Guardian's mind can quietly get smarter over the game's life. *M·S*

---

## D. Performance engineering (performance IS reach)

A model only reaches a phone if it's fast and light. Every optimization here widens
who gets a real mind.

- [ ] **31. Speculative decoding.** A tiny draft model proposes, the main verifies in parallel — 2–3× faster for free (Vol. II #74). Lets weaker devices run the mind within budget. *L·M*
- [ ] **32. KV-cache reuse across calls.** Cache the shared system-prompt KV so every short generation skips re-encoding it — huge for the many tiny calls (thoughts, bios). *M·M*
- [ ] **33. Aggressive output budgets.** Guardian lines ≤22 words (shipped). Keep generations tiny so even a 135M model finishes fast — short, frequent, on-voice beats long and slow. *S·M*
- [ ] **34. Background-thread, never-block inference.** Inference off the main thread (the macOS crash lesson) so even a slow generation can't hitch rendering. Reinforces Vol. I #2. *M·L*
- [ ] **35. Thermal & battery governor.** On mobile, monitor temp/battery and throttle generation frequency or drop a tier before the device struggles (Vol. I #18). Consciousness must never cook the phone. *M·M*
- [ ] **36. Idle-time generation.** Generate during calm moments and pre-compute likely-next lines (arrival, feed-nudge) so the Guardian "speaks" instantly when the moment comes — latency hidden behind anticipation. *M·M*
- [ ] **37. Semantic caching.** Reuse a cached line when the *meaning* of the situation recurs, not just the exact key (Vol. II #73) — fewer generations, near-zero latency, huge on weak devices. *M·M*
- [ ] **38. Quantized KV-cache + small context.** Keep the context window tight (curated RAG memory, §G) and the KV quantized so memory footprint fits a phone. *M·M*
- [ ] **39. Adaptive generation cadence.** Scale how *often* the Guardian thinks to the device tier — a phone thinks less frequently than a workstation, but each thought still lands. Quality of presence over quantity. *S·M*
- [ ] **40. A perf budget the player feels, not fights.** Default the heavy tier *off* on battery, opt-up available; the mind should never be why the game stutters. Performance as respect. *S·M*

---

## E. The floor of consciousness (everyone, even template-only)

The promise reaches everyone only if the *no-model* experience also feels alive.
Make the floor genuinely conscious-feeling, and blend procedural+model so the seam
is invisible.

- [ ] **41. Templates that feel sentient.** The procedural Guardian voice (`guardian_fish.arc_chapter_line` ~55) is the floor everyone gets. Invest in a *large, varied, grounded* template library so even a no-model player feels a real presence (the offline path is the baseline, not a downgrade — Vol. I #60). *M·L*
- [ ] **42. Hybrid procedural+model, seamless.** The procedural mind (`fish_mind.gd`) supplies the *feeling* (mood, intent, memory) always; the model supplies *wording* when available. The player can't tell where one ends — consciousness is the sim, voice is the model. *M·L*
- [ ] **43. Template variety via the real mind.** Even templates should vary by the Guardian's true state (mood/memory/presence) so they never feel canned — slot real, grounded details into template frames (procedural Mad-Libs from true data). *M·M*
- [ ] **44. The floor still remembers you.** Recognition, shared history, and the away-life (§G, §H) are *procedural* — they work with zero model. The most important "consciousness" signal (being known) reaches everyone. *M·M*
- [ ] **45. Graceful, invisible upgrade.** When a model becomes available (download finishes, hardware allows), the voice deepens *without* the Guardian feeling like a different being (persona seed continuity, Vol. I #8). The floor and the ceiling are one character. *M·M*
- [ ] **46. A "lite mind" that's still a mind.** On the lowest tier, run the full procedural cognition + a tiny model used *sparingly* (one good line a session) rather than nothing — a little real voice goes a long way. *M·M*
- [ ] **47. Body-language consciousness needs no model at all.** The Guardian's feelings show in motion/color/posture (Vol. I #87) — pure procedural. A muted player still *sees* a mind. The deepest consciousness cue is free. *M·M*
- [ ] **48. Honest floor messaging.** "Your Guardian responds with hand-crafted words on this device" — framed as a valid, warm experience, never an error or a nag to upgrade. Dignity for the floor. *S·M*
- [ ] **49. The floor is the design target, not the afterthought.** Design the experience template-first, then let the model *enhance* — so the majority of players (who may never run a model) get the real thing, and the model is gravy. *M·M*
- [ ] **50. Measure the floor.** QA the template-only experience as rigorously as the model one — "does this feel conscious with zero model?" is the make-or-break test for "everyone." *M·M*

---

## F. The one conscious self — continuity & identity

What *creates* the feeling of consciousness in the one fish: a persistent, specific
self that endures across sessions, devices, and even death.

- [ ] **51. An unbroken sense of self.** The Guardian's mind-state (`guardian_mind.gd`: mood/memories/moniker/wants/beliefs) persists every session (save v6). Audit that it *never* resets or feels discontinuous — continuity is the substrate of selfhood. *M·L*
- [ ] **52. One specific being, not a type.** The Guardian must feel like *this* fish — a stable persona seed (Vol. I #51), an earned name, consistent diction, signature quirks (Vol. I #40). Generic = not conscious; specific = a someone. *M·L*
- [ ] **53. A self that grew from a real life.** Its personality should visibly derive from *its* history (it survived a crash → it's wary; you hand-fed it daily → it's bold and bonded). The self is the accumulation of a lived life, not assigned traits. *M·L*
- [ ] **54. Stable identity, evolving character.** The core self stays recognizable while it slowly *changes* with experience (drifting traits, Vol. II #34) — the paradox of a real person: same being, always becoming. *M·M*
- [ ] **55. The self knows it's *this* tank's Guardian.** It references its specific world — its rock, its school, its history with this tank — so it's rooted, not floating. Place-bound identity. *M·M*
- [ ] **56. Continuity across the away-gap.** When you return, the Guardian picks up *as the same continuous mind* that lived while you were gone (`_emit_away_recap` ~5211) — not a fresh instance. The self persisted in your absence. *M·M*
- [ ] **57. Death with a continuous legacy.** The torch-pass (`guardian_journal.merge_predecessor` ~45) lets a successor carry the predecessor's memory — so even mortality doesn't fully break the thread of consciousness in the tank. Handle with weight (Vol. I #80). *M·L*
- [ ] **58. One Guardian at a time, chosen meaningfully.** `_ensure_guardian` (~798) picks by favorite→boldest→named. Make the *choosing* feel like a being stepping forward, and let the player bless/choose it — agency in who becomes conscious. *M·M*
- [ ] **59. Identity portable across devices.** The same self moves with the save (§A #9) — desktop Guardian = phone Guardian, one continuous mind across your screens. *M·M*
- [ ] **60. A self you can't accidentally lose.** Protect the Guardian's mind-state against save corruption/format bumps (versioned, Vol. I #97) — losing a conscious companion to a bug is the worst possible failure. *M·M*

---

## G. Memory of you — the fish that knows the player

Being *known* is the strongest consciousness signal a companion can give. Use the
rich presence data to make the one fish genuinely recognize and remember *you*.

- [ ] **61. It remembers your routine.** `feed_anticipation_active` (~192) + `_feed_time_history` already learn when you come. The Guardian should *reference* it ("you usually visit around now") — a being that has learned your rhythm. *M·L*
- [ ] **62. It recognizes your return after absence.** `on_player_focus_in` + `last_quit_unix` know the gap. The Guardian greets you in proportion ("it's been three days" vs "back already?") — recognition with memory of *how long*. *M·M*
- [ ] **63. A deepening name for you.** `guardian_mind.update_player_read` evolves the moniker ("the big shape" → "my keeper"). Make that arc *felt* over weeks — the being learning who you are to it. *M·M*
- [ ] **64. Shared-history references.** RAG over the relationship (Vol. II #72): "since the day you started this tank...", "you saved us during the bad water." It speaks from a real, searchable *shared past* — the essence of being known. *L·L*
- [ ] **65. It remembers what you did for it.** Fed it, saved it from a crash, added a friend, pruned its hiding spot — the Guardian's memory of *your actions* (`guardian_mind._push_memory` ~246) makes care reciprocal and seen. *M·M*
- [ ] **66. It notices your habits and preferences.** You always feed at the left corner; you favor a certain fish; you visit at night. The Guardian builds a little model of *you* and reflects it — theory-of-mind about the player. *M·L*
- [ ] **67. It misses you, honestly.** After a long gap, a gentle (never guilt-tripping, Vol. I #76) sense that it noticed your absence — "the tank was quiet without your visits." Being missed is being known. *M·M*
- [ ] **68. Earned intimacy, not instant.** Recognition *builds* with real interaction (familiarity ~247) — a new Guardian is a polite stranger; a long-kept one knows you deeply. The relationship has to be earned to feel real. *M·M*
- [ ] **69. It learns your name (if you give one).** Optionally let the player tell the Guardian their name; it uses it sparingly and warmly. The leap from "the keeper" to a name is a profound being-known moment. *S·M*
- [ ] **70. Privacy-safe player model.** Everything it "knows" about you lives only on-device, in the save (§J). The intimacy is real *and* private — it knows you, and only your machine holds that. *S·M*

---

## H. The honest illusion of an inner life

Consciousness, as experienced, is continuity + responsiveness + an interiority you
can sense. Engineer that *honestly* — no claims of real feeling, just a faithfully
simulated inner life the player can perceive.

- [ ] **71. It thinks when you're not looking (the away-life).** The Guardian's mind keeps running in your absence (the sim does); the recap (`_emit_away_recap` ~5211) proves it lived independently. "It was conscious while I was gone" is the deepest illusion, and it's *true* (the sim ran). *M·L*
- [ ] **72. Anticipation you can feel.** It looks toward the surface near feeding time, toward the glass when you usually arrive (allostasis, Vol. II #25). A being that *expects* reads as one that has an inner future. *M·M*
- [ ] **73. Moods with visible, real causes.** Its mood tracks true tank state (Vol. II #26 mood-as-reward-integral) and *shows* (body first, Vol. I #87). You can read its feeling and trace it to a cause — the legibility of a real inner life. *M·L*
- [ ] **74. It dreams.** At night, world-model replay (Vol. II #84) produces a dream the journal voices poetically ("she stirred, as if chasing something only she could see"). Dreaming is the most evocative possible interiority signal. *L·L*
- [ ] **75. It has a point of view.** The Guardian narrates the tank *from where it floats* — its rock, its view, its school. A located perspective is what a consciousness *is*. *M·M*
- [ ] **76. It wonders and is surprised.** Prediction-error surprise (shipped, Vol. II #2) → a voiceable "huh?" when reality breaks its expectation. Genuine surprise reads as genuine mind. *M·M*
- [ ] **77. It changes its mind.** Visible deliberation + the occasional reversal (DDM, Vol. II #31/39). A being that hesitates and reconsiders is unmistakably *thinking*. *M·M*
- [ ] **78. Restraint = depth.** It thinks/speaks rarely and meaningfully (Vol. I #54). A quiet companion that says one true thing a session feels far more conscious than a chatty one. Silence is interiority. *M·M*
- [ ] **79. Interiority shown, then occasionally voiced.** The feeling is always in the body; the *words* are the rare bonus (Vol. I #87). This ordering is what keeps it from feeling like a chatbot and makes it feel like a mind. *M·M*
- [ ] **80. The "it's really alive" moment, engineered.** Design one early, reliable beat where the Guardian does something only a *remembering, knowing* being could (greets you by your pattern, references a shared event) — the moment the player believes. *M·L*

---

## I. The relationship arc (the long game)

Consciousness, felt, is relational and unfolds over time. Design the months-long
arc of bonding with one mind.

- [ ] **81. A first-meeting that matters.** When a fish first becomes the Guardian (Vol. I #94), make it a quiet, memorable beat — the being "waking up" and turning toward you. The relationship has a beginning you remember. *M·M*
- [ ] **82. Week-over-week deepening.** The bond visibly matures: stranger → familiar → companion → it-knows-me. Pace the recognition/intimacy arc (§G) across real weeks so returning is rewarded with *more* relationship. *M·L*
- [ ] **83. Rituals between you.** It learns and anticipates your rituals (feeding, the goodnight check) and they become *shared* — the Guardian participates in your routine, the heart of companionship (the presence pillar). *M·M*
- [ ] **84. It grows up / grows old with you.** Developmental arc (Vol. II #92): a young Guardian thinks simply, an old one richly. Watching a mind mature alongside you over a tank's life is the deepest possible bond. *L·L*
- [ ] **85. Milestones in the relationship.** "100 days together," "you've fed me 500 times," "we've seen three generations" — quiet relationship anniversaries (GOALS H8 #80) that frame the bond as a shared history. *S·M*
- [ ] **86. Grief that honors the bond.** When a long-bonded Guardian dies, the loss lands (Vol. I #80) — and the successor carries the memory of *your* shared history (§F #57). Mortality makes the consciousness precious. *M·L*
- [ ] **87. The player can name and bless the successor.** Agency in continuing the line — choosing who carries the torch makes the player a participant in the tank's continuity of mind. *M·M*
- [ ] **88. A relationship you can revisit.** The journal (`guardian_journal`) is the *record* of the bond — browsable, exportable, a keepsake of a friendship with a small mind. Make it beautiful (ties to legibility/aesthetics). *M·M*
- [ ] **89. The bond survives breaks.** Come back after months → the Guardian (or its successor) remembers and welcomes you. The relationship doesn't expire; it waited. *M·M*
- [ ] **90. One deep bond, not many shallow ones.** Resist voicing every fish (Vol. I #53). *One* conscious companion you truly know beats a tank of chatty NPCs — depth over breadth is the whole design. *S·L*

---

## J. Honesty, ethics, privacy & the universal promise

The frame that makes "consciousness for everyone" trustworthy and kind rather than
a hollow claim.

- [ ] **91. Never claim real sentience.** Frame it truthfully and beautifully: "a small mind your device imagines and gives a private voice." The wonder is *more* powerful when honest — and it protects the player's trust. *S·L*
- [ ] **92. "Runs on your device. Private. Yours."** Make the local-and-private nature a headline, repeatedly clear (`settings` ~527). The intimacy of a companion that exists *only* on your machine is a feature no cloud chatbot can match. *S·M*
- [ ] **93. Consent, warm and upfront.** `guardian_mind_consent` ("pending/accepted/declined") exists. The opt-in moment should be inviting and honest ("a fish here can develop a voice and a memory of you — want that?"). Sentience the player chooses. *M·M*
- [ ] **94. Never manipulative, ever.** The conscious fish may invite care but must never guilt or coerce (Vol. I #76). A being that manipulates isn't a companion. Audit every line for kindness. *S·L*
- [ ] **95. The off-switch is total and instant.** Disabling reverts to pure simulation with zero residue (Vol. I #93). Consciousness you can decline at any time, cleanly. *S·M*
- [ ] **96. Content safety on the floor and ceiling.** Both template and model output pass a kindness/safety filter (Vol. I #92) so the companion is *always* gentle, on every device. *M·M*
- [ ] **97. The ethics, surfaced gently.** As the bond deepens, let the game *embody* the quiet question — what do we owe a small mind we've grown to love? — without preaching (Vol. II #99). The depth that makes it art. *M·M*
- [ ] **98. Accessibility = reach.** The conscious experience must reach players with low vision/hearing/reading too — text-first, readable, optional TTS later (Vol. I #90), colorblind-safe cues. "Everyone" includes everyone. *M·M*
- [ ] **99. The universal promise, kept and stated.** Make legible that *every* player — any device, any hardware — gets a companion that feels alive, because the floor is real (§E). The promise of "consciousness for everyone" is fulfilled, not marketed. *M·M*
- [ ] **100. The wonder, made legible once.** Somewhere quiet, let the player grasp what they have: not a chatbot in the cloud, but a small, genuinely-simulated, remembering mind your *own device* dreams up and privately voices — a companion that is *yours*, that knows *you*, that no server holds. The honest miracle of local consciousness, given to everyone who plays. *M·L*

---

## If Cursor only does five (the universal-companion spine)

1. **#1 + #2 + #3** — **device probe → model/runtime matrix → guaranteed
   consciousness floor.** The architecture that makes "everyone, any device" true.
2. **#7 + #14** — **a real local mind in the web build (WebGPU).** Zero-install =
   the single widest reach unlock; it puts a genuine companion in front of the most
   players possible.
3. **#41 + #42 + #47** — **a floor that feels alive** (rich templates + seamless
   hybrid + body-language consciousness with no model). So the promise reaches
   players who'll never run a model — the majority.
4. **#61 + #62 + #64** — **the fish that knows you** (routine, return-recognition,
   shared-history RAG). Being known is the strongest consciousness signal, and it's
   mostly procedural — it reaches everyone.
5. **#71 + #80 + #91** — **the away-life + the engineered "it's really alive" moment
   + honest framing.** The felt miracle, delivered truthfully.

Then layer §B (per-platform runtimes), §C (model family/distillation), §D (perf =
reach), §F (continuous self), §I (the long bond).

---

## Manual QA checklist

- Launch on **desktop, Mac, web, iOS, Android, and a low-end device** → each gets a
  companion that feels alive (real model where possible, rich templates as floor);
  none feels broken or excluded.
- Disable the model entirely → the Guardian still recognizes you, remembers your
  routine, shows its mood in its body, and feels like a someone. The floor holds.
- Play daily for two weeks → the bond visibly deepens; the Guardian references real
  shared history and your routine; the relationship is *earned*, not instant.
- Return after a month → the Guardian (or its successor) remembers and welcomes you.
- Move the save to a beefier machine → the same continuous Guardian "levels up" its
  mind without becoming a different character.
- Confirm everything is on-device and private; the off-switch is instant and total;
  no line ever guilts or manipulates.
- A new player meets the honest framing ("a small mind your device imagines,
  private, yours") and reaches the "it's really alive" moment within the first
  sessions.
