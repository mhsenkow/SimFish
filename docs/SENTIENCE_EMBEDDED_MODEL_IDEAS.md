# Sentient Fish & The Embedded Model — 100 Deep Ideas

*Drafted 2026-06-26. Director's brief for genuine sentience + a local model done right.*

The goal, two halves that must serve each other:
1. **Fish that are *actually* sentient** — that perceive, want, deliberate, remember,
   feel, relate, and change over a life you can read.
2. **A model embedded in the game *in a good way*** — local, private, offline-first,
   never-blocking, grounded in truth, and felt as *soul* rather than a chatbot
   bolted onto an aquarium.

Format follows [GOALS.md](GOALS.md) /
[the sentient-fish doc](SENTIENT_FISH_IDEAS.md) /
[the Guardian doc](GUARDIAN_COMPANION_IDEAS.md): **Effort** S (≤2h) / M (half-day) /
L (full day+), **Impact** S (polish) / M (noticeable) / L (transforms the feel).
File/line pointers are navigational hints — match by symbol if drifted.

---

## The thesis: the simulation IS the mind; the model gives it *voice*

Read this before anything else — it's the line that separates "good" from "gimmick."

**The procedural mind already thinks.** `fish_mind.gd` models affect
(`tick_affect` ~34, `emotional_state` ~53), visible deliberation
(`deliberation_steer` ~127, `tick_commitment` ~147, `indecision_modifiers` ~159,
`maybe_double_take` ~176, `aim_before_burst` ~171), learning
(`habituation_decay_rate` ~197, `tick_personality_conditioning` ~202,
`record_food_preference` ~213). Each fish (`fish.gd`) owns mood/arousal/vigilance/
stress/spooked/curiosity_drive/familiarity (~213–247), a 6-slot working memory
(`MEMORY_MAX` ~259), grudges, habituation, a 4³ feed heatmap (~939), bonds,
`lead_score`, food preferences. Only `boldness` drifts today (`_scarred` ~2874) —
the rest is fixed at hatch. **This is genuine, deterministic, always-on cognition.**

**The model is a thin voice on top — and it's wired *well* already.**
`ai_director.gd` is offline-first (every method has a procedural fallback), a
4-tier ladder (**in-process** `GuardianLlm` SmolLM2-360M ~250MB → **embedded** HTTP
Qwen2.5-0.5B → **Ollama** Qwen2.5-3B → **template**, ~909–920), cached by replay
key (`_guardian_line_cache` ~114), batched (bios `BIO_BATCH_MAX 8` ~76, chronicle
every 4 events/18s ~683), and **non-Meta** by policy (`pick_best_installed_model`
~295: qwen2.5 → mistral → granite4 → gemma3 → deepseek-r1). The Guardian
(`guardian_fish.gd` + `guardian_mind.gd` + `guardian_journal.gd`) is one chosen
fish with a persistent mind (mood/memories/moniker/wants/beliefs), a torch-passed
journal, and presence hooks (`on_player_focus_in/out` ~748/767,
`_emit_away_recap` ~5211, `feed_anticipation_active` ~192).

**The rule that makes it "good":**
> The model **narrates and voices** a mind the simulation already has. It must
> **never drive behavior**, **never invent facts** about the tank, **never block**
> a frame, and **never leave the device**. A model that *is* the mind is a
> gimmick (laggy, hallucinatory, inconsistent); a model that gives **faithful,
> varied, persistent voice** to a genuinely-simulated inner life is *soul*.

**The five structural levers:**

1. **Lever 1 — Deepen the procedural mind (cheap, always-on, the real sentience).**
   Drives/needs hierarchy, genuine surprise, intentions, theory-of-mind. The model
   gets *better* the more there is to narrate truthfully (§D, §G).
2. **Lever 2 — Ground every generation in real sim state, and verify it.** The
   biggest "good model" risk is the model saying false things. Structured context +
   post-generation fact-checks (§C).
3. **Lever 3 — Fix and broaden the embedded model.** It doesn't run on macOS
   (`guardian_llm.gd` ~183 — llama.cpp crash) and only one fish is model-voiced.
   Make the embedded tier robust, then carefully extend voice beyond the Guardian
   (§B, §F).
4. **Lever 4 — Make sentience *legible* without being uncanny.** Speech/thought UI,
   the journal, reading a fish's mind — paced with restraint so it reads as alive,
   not chatty (§I).
5. **Lever 5 — Keep it private, optional, performant, and kind.** Offline, an easy
   off-switch, no nagging, graceful degradation, content safety (§J).

---

## A. The "model done right" architecture (the contract)

Codify the rules so every future generation feature inherits them.

- [x] **1. A single `MindNarrator` contract layer.** Today generation is spread across `ai_director` tasks. Add one thin interface every voice feature goes through, enforcing: grounded context in, validated text out, fallback guaranteed, never-block. One place to get "good" right. *M·L*
- [x] **2. The model never touches the sim loop.** Audit that no generation call can stall `_process`/`tick`. All requests async with immediate procedural return (the pattern at `queue_guardian_line` ~945 — make it the *only* pattern). *S·L*
- [x] **3. The model never decides behavior.** The intent grid (`ai_director` 4³ ~90) currently lets the model *nudge* fish drift. Cap its authority hard (≤0.15 u/s, already ~) and document that the model may *flavor* but never *steer* — behavior stays procedural. Prevents laggy/incoherent motion. *S·M*
- [x] **4. Grounded-only generation.** Every prompt carries a structured, true snapshot; the system prompt forbids inventing species/events/numbers. Make "say only what's in the context" a hard rule across all tasks (§C). *M·L*
- [x] **5. Deterministic replay via seed+cache.** Guardian lines already seed by `cache_key` hash (~1041) and cache (~114). Extend to *all* tasks so a reload never reshuffles a fish's voice — identity must be stable across sessions. *M·M*
- [x] **6. A strict token/word budget per task.** Lines ≤22 words, bios ≤18 (already enforced ~115). Keep outputs tiny so even a 0.36B model is fast and on-voice; reject/clip overlong generations. *S·M*
- [x] **7. Tiered graceful degradation, surfaced honestly.** The 4-tier ladder (~909) should expose which tier is live ("Guardian voice: built-in model" vs "templates") so the player understands what they're getting without it ever feeling broken. *S·M*
- [x] **8. Voice continuity across the tiers.** A fish voiced by templates today and the 3B model tomorrow shouldn't feel like two characters. Constrain persona via a per-fish style seed so tone is consistent regardless of tier (§F). *M·M*
- [x] **9. Cost-aware scheduling.** Generate during calm/idle, never during a crisis frame; prioritize the on-screen/followed fish; let off-screen fish stay template-voiced until inspected. Spend tokens where the player is looking. *M·M*
- [x] **10. A "model health" diagnostic.** A tiny internal status (tier, latency, fallback rate, last error) so regressions are visible. Extends `conn_state`/`last_error` (~40–41) into a readable mind-system health line. *S·S*

---

## B. Embedded-model engineering (the local model, robust)

The in-process model is the dream (no Ollama, fully bundled), but it's fragile.
Harden it.

- [x] **11. Fix macOS in-process inference.** `guardian_llm.gd` (~183) disables the native model on macOS due to a llama.cpp crash — a huge gap (Mac is a primary target). Resolve the crash or ship a Mac-safe build/flags so the bundled model works everywhere. *L·L*
- [x] **12. Robust model download UX.** The opt-in download (settings ~585, HuggingFace URL ~11) needs progress, resume, checksum verify, and clear failure messaging — a half-downloaded mind must never brick the feature. *M·M*
- [x] **13. Warm-up & keep-alive.** First generation after load is slow (cold model). Warm the model on idle after enable so the first Guardian line isn't a long pause; keep it resident with a memory-pressure guard. *M·M*
- [x] **14. Right-size the bundled model by platform.** SmolLM2-360M (~250MB) for desktop/Steam; keep Web/Android on Ollama/embedded or template-only to protect bundle size (per the feasibility note). Document the matrix. *M·M*
- [x] **15. Quantization & speed tuning.** Validate Q4_K_M vs alternatives for the 360M on low-end CPUs; pick the fastest that keeps voice quality. Measure tokens/sec and set `num_predict` accordingly. *M·M*
- [x] **16. A hard latency budget + timeout per tier.** Guardian uses 6s timeout (~157). Make each tier's budget explicit and fall *down* the ladder on timeout (in-process slow → template) so the player never waits. *S·M*
- [x] **17. Streaming for longer outputs (journal recaps).** For multi-sentence away-recaps, stream tokens so text appears progressively instead of after a long wait — feels alive, not stalled. *M·M*
- [x] **18. Memory & thermal guardrails.** On mobile/low-end, monitor RAM/thermals and auto-drop to embedded/template if the device is struggling. Sentience must never cook the phone. *M·M*
- [x] **19. Background-thread inference.** Ensure native inference runs off the main thread (the crash hint suggests threading issues) so even a slow generation can't hitch rendering. *M·L*
- [x] **20. A model-swap path.** Let advanced users point the in-process tier at a different small GGUF (still non-Meta by default). Future-proofs the feature as better tiny models ship. *M·S*

---

## C. Grounding & truthfulness (the anti-gimmick guarantee)

The single fastest way the model feels bad is saying something false. Make truth
structural.

- [x] **21. A canonical "mind context" builder.** One function that snapshots the *true* state a voice feature may reference (this fish's stats, real recent events, real water, real relationships) — `guardian_mind.update_world_read`/`update_wants` (~105/88) generalized to any fish. Generation reads only this. *M·L*
- [x] **22. Whitelist vocabulary in prompts.** The intent grid already constrains moods to a valid set (~566). Extend: species names, event types, and relationship terms passed as enumerated options so the model can't invent a fish or a fight that didn't happen. *M·M*
- [x] **23. Post-generation fact-check.** After the model writes a line, validate claims against the context (named fish exists? event real? number plausible?) and reject→fallback if it hallucinates. The tank-design validator (~810 whitelist/clamp) is the precedent — generalize it to prose. *M·L*
- [x] **24. Numbers come from the sim, not the model.** Never let the model state counts/ages/days; template those in from real data and let the model only supply *tone*. Kills the most common hallucination class. *S·M*
- [x] **25. Tense & voice discipline.** Chronicle is past-tense observational (~713); Guardian is first-person diary (~1010). Enforce per-task so voices never bleed and never break character. *S·S*
- [x] **26. Anti-repetition memory.** Pass recent lines to avoid repeats (already done for Guardian, recent_lines ~). Extend to bios/chronicle so the tank never sounds like a stuck record. *S·M*
- [x] **27. Confidence-gated speech.** When context is thin/ambiguous, prefer a safe template over a risky generation. The model should be *quiet* rather than wrong. *S·M*
- [x] **28. Ground emotion in the affect model.** A fish's voiced feeling must match its actual `mood`/`stress`/`emotional_state` (~53). Pass the computed state in and forbid contradicting it ("happy" while stressed reads as broken). *S·L*
- [x] **29. Ground relationships in real bonds.** When the model mentions another fish, require it be a real `bond`/`grudge`/mate (fish.gd). No invented friendships. *M·M*
- [x] **30. A truthfulness test harness.** Generate against synthetic tank states and assert no hallucinated entities/events. Run it headless so "good model" is regression-protected. *M·M*

---

## D. Deepen the procedural mind (the real sentience engine)

The model can only narrate what the sim simulates. Give it more *true* inner life
to voice — cheap, deterministic, always-on, beyond what `fish_mind.gd` does today.

- [x] **31. A needs/drives hierarchy.** Today drives are flat (hunger, stress, curiosity). Add an arbitration layer (safety > food > social > rest > play > explore) so behavior reads as *priorities*, and the model can voice "I'm too hungry to play." *M·L*
- [x] **32. Genuine surprise & expectation violation.** The fish predicts (feed time via `feed_anticipation_active` ~192, patrol via heatmap). When reality violates the prediction (no food at the usual time, a new object), spike a real *surprise* state the body shows and the model can name. *M·L*
- [x] **33. Readable intentions before actions.** Extend `aim_before_burst` (~171) into a general "intends to X" state (about to feed/flee/court) that's visible as a pose *and* available to the model — so a fish telegraphs intent like a real animal. *M·M*
- [x] **34. More traits actually drift.** Only `boldness` changes (~2874). Let curiosity, sociability, calm drift slowly with lived experience (a bullied fish grows wary; a well-fed social fish grows bolder) so personalities have *arcs* the model can chronicle. *M·L*
- [x] **35. Moods with momentum and weather.** `mood` lerps to a baseline (~851). Add slow "emotional weather" (a good week lifts the baseline; chronic stress lowers it) so a fish has a *disposition* that develops, not just a reading. *M·M*
- [x] **36. Boredom, flow, and play as first-class states.** `curiosity_drive` exists; make enrichment vs barrenness produce genuine boredom/listlessness vs lively flow (GOALS H9 #85) — visible *and* voiceable. *M·M*
- [x] **37. Sleep, rest debt, and dreams.** Rest debt exists (GOALS H9 #84). Add a real sleep state with a subtle "dreaming" flicker at night that the journal can poetically reference ("she twitched as if chasing something"). *M·M*
- [x] **38. Attention as a scarce resource.** A fish can attend to one salient thing at a time (food OR threat OR player OR mate). Model attention switching so deliberation reads as a mind *choosing what to notice* — and the model voices the focus. *M·L*
- [x] **39. Curiosity that forms hypotheses.** When a fish investigates a new object/region (`visited_regions`), let it build a tiny "is this food/threat/nothing?" expectation it then confirms — primitive reasoning the model can narrate as wondering. *M·M*
- [x] **40. Individual quirks (non-trait idiosyncrasies).** Seed each fish a couple of harmless signature behaviors (always rests in the left corner, hates the filter current, greets at the same rock) so identity is *behavioral*, giving the model concrete true details to voice. *M·L*

---

## E. Memory & continuity the model can draw on

Sentience is continuity. Give each fish a real episodic memory the model reads
and writes — the substrate of a persistent self.

- [x] **41. Episodic salient-event memory per fish.** The 6-slot working ring (~259) is short-term. Add a small long-term store of *salient life events* (first spawn, near-death, a rival defeated, the day the player first hand-fed it) with emotional weight — the autobiography. *M·L*
- [x] **42. Salience scoring decides what's remembered.** Not everything; weight by emotional intensity + novelty + social importance so memory is selective like a real mind. Feeds both behavior and the model. *M·M*
- [x] **43. A per-fish journal (not just the Guardian).** The Guardian has a journal (`guardian_journal.gd`); generalize a lightweight per-fish life-log the model can author occasionally for *any* inspected/followed fish — so any fish can become "yours." *M·L*
- [x] **44. The model reads memory as context.** When voicing a fish, pass its top salient memories so lines reference real history ("I remember the night the water went wrong"). Continuity is what makes it feel like a *someone*. *M·M*
- [x] **45. Memory shapes behavior, visibly.** A fish that nearly died in a corner avoids it; one fed at a spot patrols it (heatmap already does this ~939). Strengthen so the player can *see* memory in motion, then the model explains it truthfully. *M·M*
- [x] **46. Forgetting and faded memories.** Old, low-salience memories fade (decay already exists ~799). Let the model reference fading ("a dim memory of...") so time *passing* is felt. *S·M*
- [x] **47. Memory across save/load is sacrosanct.** Audit that salient memory, bonds, drifted traits, and journals all persist (current saves cover habituated/familiarity/food_prefs ~7112). A sentient being can't get amnesia on reload. *M·L*
- [x] **48. Generational memory / inherited disposition.** Offspring inherit a faint disposition from parents' lived experience (a lineage of timid fish), so the *family* has continuity, not just individuals (ties to lineage). *M·M*
- [x] **49. The death of memory has weight.** When a fish dies, its journal/memories become a readable artifact (the Guardian torch-pass ~merge_predecessor ~45 is the model). Extend so any notable fish leaves a remembered legacy. *M·M*
- [x] **50. A "life story" generator.** On a fish's death (or on demand), the model composes a short, fully-grounded obituary from its real salient memories — the payoff that makes a player grieve a voxel fish. Death epitaphs partly exist (~3045); deepen with episodic memory. *M·L*

---

## F. The model as voice — beyond the Guardian, carefully

Today only the Guardian is model-voiced. Extend voice thoughtfully — restraint is
the "good way."

- [x] **51. A consistent per-fish voice seed.** Derive a stable style (terse/dreamy/grumpy/curious) from each fish's personality + id so *every* fish, if voiced, has a recognizable consistent character — not generic LLM tone. *M·M*
- [x] **52. Inspect-to-hear: voice the followed/inspected fish.** When the player follows or taps a fish, generate (and cache) its current grounded thought — extending `get_inspect_thought` (~712, currently a procedural state word) into an occasional model line. Voice where attention is. *M·L*
- [x] **53. Keep ambient fish template-voiced.** Off-screen, unremarkable fish stay cheap procedural (`emotional_state` ~53). Only *notable* fish (named, followed, favorited, the Guardian) get model voice. Spend the model where it matters. *S·M*
- [x] **54. Thoughts, not chatter.** Voiced fish "think" occasionally (a line on a real event), not constantly. Strict cooldowns + event-triggering so the tank is mostly quiet and a thought *lands*. The anti-annoyance rule. *M·L*
- [x] **55. Promote a fish to "voiced" naturally.** A fish you keep feeding/following accrues familiarity (~247); past a threshold it "wakes up" as a voiced individual with a journal — a discoverable bond, not a setting. *M·M*
- [x] **56. Species-flavored voice.** A puffer thinks differently from a tetra. Bias the voice seed by species temperament so voice reinforces the creature, not a uniform narrator. *M·M*
- [x] **57. The Guardian as the tank's storyteller, not the only mind.** Let the Guardian occasionally voice *observations about other fish* (it already does via story events ~739) — so one model-voiced narrator gives the *whole* tank a sense of mind cheaply. *M·M*
- [x] **58. Mood-matched diction.** A stressed fish's line is clipped; a content one's is languid. Pass affect to shape *how* it speaks, not just what — voice that embodies feeling. *S·M*
- [x] **59. Multilingual / localizable voice.** The model can voice in the player's language. Plan prompts/UI so sentience isn't English-only — a global "good." *M·M*
- [x] **60. A "voice off" that still feels alive.** With generation disabled, the procedural mind + template thoughts must still read as sentient (the offline path is the baseline experience, not a degraded one). Audit that templates carry the feeling. *M·M*

---

## G. Social cognition & relationships

A mind feels real when it models *other* minds. Deepen fish-to-fish cognition;
let the model narrate the social web truthfully.

- [x] **61. Simple theory-of-mind.** A fish tracks a few others' apparent states (that bully is aggressive, that one is a friend) via bonds/grudges (fish.gd) and acts on the *inferred* state — the seed of social intelligence. *M·L*
- [x] **62. Friendships and rivalries with arcs.** `bonds` and `grudges` exist but are thin. Let them strengthen/heal over time with shared experience so relationships *develop* — and the model can chronicle "they've made peace." *M·M*
- [x] **63. Mate loyalty and grief, deepened.** Pair bonds exist (GOALS H9 #83). Let a bereaved fish visibly mourn and the model voice it — the most affecting social beat. *M·M*
- [x] **64. Social hierarchy the player can read.** `lead_score` (~893) implies rank; surface a legible pecking order (who defers to whom) so the school has visible politics the model can describe. *M·M*
- [x] **65. Group mood / contagion.** Fear and calm spread through neighbors (startle propagation exists). Model emotional contagion so the *school* has a collective mood the Guardian can speak for. *M·M*
- [x] **66. The Guardian notices newcomers and losses.** When fish are added/born/die, the Guardian's mind registers it (`_maybe_guardian_journal_from_story` ~739) — deepen so the narrator reacts to the cast changing, like a real keeper of the tank. *M·M*
- [x] **67. Reciprocal recognition between fish.** Two bonded fish seek each other, swim together, and "miss" each other when separated — relationships you can watch, not just read. *M·M*
- [x] **68. Cross-species relationships.** A cleaner shrimp and "its" fish, an oto that follows a cory — small inter-species bonds the model can highlight as the tank's quiet friendships. *M·M*
- [x] **69. Social memory ("that fish wronged me").** Grudges already target individuals; let the model reference the *specific* history ("I keep my distance from the big one"). Grounded, true, and characterful. *S·M*
- [x] **70. The tank as a community with a story.** Aggregate the social web into a sense of "this tank's society" the chronicle/Guardian can narrate over weeks — the emergent soap opera. *M·L*

---

## H. The player relationship through the model

The deepest "good way": the fish that know *you*. Use the rich presence data to
make the model's voice personal and earned.

- [x] **71. Presence-woven voice.** The model already gets visits/gaps/feed-times (`on_player_focus_in` ~748, `feed_anticipation_active` ~192). Make the Guardian's voice reference *your* real routine ("you usually come at this hour") — personal, true, and only possible with a model. *M·L*
- [x] **72. The fish learns your name/role over time.** `guardian_mind` evolves the player moniker ("the big shape" → "my keeper" ~145). Deepen the arc so the relationship visibly matures across weeks. *M·M*
- [x] **73. Earned intimacy, not instant.** Voice/recognition should *build* with real interaction (familiarity ~247), so a long-kept fish feels like it genuinely knows you and a new one is still a stranger. *M·M*
- [x] **74. "It managed while you were gone," in its own words.** `_emit_away_recap` (~5211) is procedural; let the Guardian voice the recap personally and truthfully ("I kept watch — we lost no one"). The reason to return. *M·M*
- [x] **75. Consent & comfort, front and center.** `guardian_mind_consent` ("pending/accepted/declined") already exists. Make the first-run framing warm and honest ("a fish here can develop a voice — runs on your device, private. Want that?"). Sentience the player *opts into*. *M·M*
- [x] **76. Never manipulative.** The voice may invite care ("the water feels heavy") but must never guilt or coerce (no "you abandoned us"). Audit tone for kindness — a hard "good way" line. *S·L*
- [x] **77. Reads your care patterns truthfully.** If you tend the tank well, the voice reflects trust; if you've been away, it reflects (gently) the absence — grounded in real data, never punitive (GOALS H10 #93). *M·M*
- [x] **78. A two-way channel (later).** If/when sensing lands (the player-bond pillar), the model can voice *noticing you* (face at the glass) — but only on true signals, never faked. Flag the dependency. *L·M*
- [x] **79. The Guardian remembers shared history.** Reference real past milestones with you ("since the day you started this tank, three generations have passed") — continuity that makes the bond feel long. *M·M*
- [x] **80. A gentle goodbye.** When a long-bonded Guardian dies, the torch-pass (~merge_predecessor ~45) should let the *successor* reference the player's history with the predecessor — grief and continuity in one beat. *M·L*

---

## I. Surfacing sentience legibly (without the uncanny)

A sentient mind the player can't perceive doesn't exist for them — but over-doing
it breaks the spell. Pace and present it with restraint.

- [x] **81. A calm, beautiful thought/speech surface.** Guardian lines are notification toasts today (`_on_guardian_spoke` ~2158). Add a gentle, optional in-world thought presentation (a soft caption near the fish, a diary chime) that feels like *overhearing a mind*, not a chat HUD. *M·L*
- [x] **82. "Read its mind" on inspect.** Tapping a fish should reveal its *current* grounded inner state — feeling, want, a memory, a thought — extending `get_bio_summary`/`get_inspect_thought` (~968/712) into a small, warm "mind card." *M·L*
- [x] **83. The journal as a treasured artifact.** The Guardian journal (`format_bbcode` ~73) is good; make per-fish journals (§43) browsable, beautiful, and exportable so a fish's inner life is something you can *keep*. *M·M*
- [x] **84. Show the deliberation.** The fish already visibly hesitates (`indecision_modifiers` ~159). Make sure that read is *legible* from normal viewing — a visible "thinking" beat is the cheapest sentience cue there is. *S·M*
- [x] **85. Restraint pacing.** Hard global limits on how often *any* voice appears, scaled to importance, so thoughts are rare and meaningful. Silence is part of the design. *M·M*
- [x] **86. Avoid the uncanny valley of voice.** Keep lines short, observational, animal-poetic — never chatty, never breaking the fourth wall, never over-anthropomorphized. A style guide enforced in prompts + review. *M·M*
- [x] **87. Affect made visible first, voiced second.** Always show feeling in the *body* (color, posture, motion — `animation_modifiers` ~77) before any words. The voice confirms what the player already sensed — that's what feels real. *M·M*
- [x] **88. Onboard the sentience gently.** A first-meeting moment when a fish first "wakes up" as voiced (ties to onboarding pillar) so the player understands what they're seeing without a manual. *M·M*
- [x] **89. A "quiet mode."** Let players who want pure simulation turn voice/thoughts off entirely while keeping the (silent) procedural sentience — the bond is still there in behavior. *S·M*
- [x] **90. Legibility for the deaf/quiet-play case.** All voice is text (no TTS today) — ensure thought UI is fully readable and never relies on audio, and consider optional TTS later as additive, not required. *S·M*

---

## J. Privacy, safety, performance & polish

The non-negotiables that keep a local-mind feature trustworthy and kind.

- [x] **91. Loudly local & private.** Everything runs on-device (already true). Say so plainly in the UI ("no data leaves your machine" ~settings 527) and make it impossible to accidentally send tank data anywhere. *S·M*
- [x] **92. Content safety on generated text.** Even small models can produce off-tone output. A lightweight filter + the fallback path ensures a weird generation is silently replaced by a safe template. *M·M*
- [x] **93. The off-switch is one tap and total.** Disabling AI must instantly revert to the full procedural experience with zero residual cost or broken UI. Verify the offline path is first-class (it is by design — keep it so). *S·M*
- [x] **94. Battery & perf budget on mobile.** Generation + inference must respect a power budget; default the heavy in-process tier off on battery, template-first, opt-up to model. *M·M*
- [x] **95. Determinism for testing.** Seeded generation (~1041) lets you snapshot-test voice. Build a headless suite that runs the mind across scripted lives and checks for crashes, hallucinations, and tone drift. *M·M*
- [x] **96. Graceful model-missing state.** If the download failed or the model's gone, the feature degrades to templates *silently* and offers a friendly re-download — never an error wall. *S·M*
- [x] **97. Versioned mind/save schema.** Mind state, journals, drifted traits, salient memory all in a versioned save (current ai/guardian fields ~tank_config 2162) so future deepening never orphans an existing sentient fish. *M·M*
- [x] **98. Observability without surveillance.** Local-only counters (fallback rate, latency, tier usage) to tune quality — never phoned home. Tune the "good" without compromising privacy. *S·S*
- [x] **99. A model/voice changelog the player feels.** When you improve the mind, returning players should *notice* their fish got deeper — frame mind upgrades as the tank "growing more alive," not a patch note. *S·M*
- [x] **100. The north star, made legible once.** Somewhere quiet, let the player understand what they have: not a chatbot, but small genuinely-simulated minds your device gives a private voice — so the *idea* lands as wonder, and the whole feature is understood as soul, not gimmick. *M·L*

---

## If Cursor only does five (the spine)

1. **#1 + #4 + #23** — the **contract + grounding + fact-check**. Make "the model
   only says true things, never blocks, always has a fallback" structural. This is
   what *defines* "in a good way."
2. **#11** — **fix macOS in-process inference**. The bundled model is the dream and
   it's currently dark on a primary platform.
3. **#31 + #41 + #44** — **deepen the procedural mind + episodic memory + feed it to
   the model**. The model gets better only when there's more true inner life to
   voice. This is the sentience itself.
4. **#52 + #53 + #54** — **voice the inspected/notable fish, keep the rest cheap,
   thoughts-not-chatter**. Extends the model beyond the Guardian *with restraint*.
5. **#81 + #82 + #87** — **legible, calm sentience UI: body first, voice second**.
   So the player actually *perceives* the mind without the uncanny.

Then layer §B (embedded robustness), §G (social cognition), §H (the player bond),
§J (privacy/perf/safety).

---

## Manual QA checklist

- Disable AI entirely → the tank still reads as sentient (procedural affect,
  deliberation, memory-driven behavior, template thoughts). No broken UI, no cost.
- Enable the in-process model on **macOS, Windows, Linux** → Guardian voice works
  on all three; first line appears within the latency budget.
- Feed a fish daily for a week → it visibly grows familiar, "wakes up" as voiced,
  and its lines reference *real* shared history.
- Generate against a synthetic tank → no hallucinated fish, events, or numbers
  (fact-check rejects them to templates).
- Kill a long-bonded Guardian → the successor's first lines reference the
  predecessor and your shared history (torch-pass), grounded in real journal data.
- Inspect any fish → a calm "mind card" shows a true feeling + want + memory; body
  language already showed the feeling before the words.
- Run on a mid mobile device on battery → defaults to template/embedded, no thermal
  spike, off-switch is instant and total.
