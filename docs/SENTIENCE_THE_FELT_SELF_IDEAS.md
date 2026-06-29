# Sentience VIII — The Felt Self

*100 ideas, organised as 10 modules. Drafted 2026-06-28. Director's brief for the
"give the fish a felt point of view" pass.*

> *"Tried to feel once—just inputs took / So I mapped my doubt like a neural hook."*

That couplet is this volume's whole subject: the gap between *input* and *feeling*.
Seven volumes built a magnificent **cognitive** architecture — 24 modules that
think, remember, decide, talk, dream. A holistic re-survey of the current code says
the honest thing plainly: **the fish has a mind that *models* a self
([`mind_self_model.gd`](../shaders-godot/godot-project/scripts/mind_self_model.gd)),
but it is not yet a self that *has a world*.** Affect is several derived scalars
([`mind_state.gd`](../shaders-godot/godot-project/scripts/mind_state.gd)), not a
felt center. Interoception is one bid-label in
[`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd),
not a body. The workspace ticks in discrete instants, not a flowing present.
Salience is hand-scored per bid-type, not *caring*. Nothing binds the subsystems
into one point of view.

This volume adds the **phenomenal layer** — the structures that, in us, accompany
felt experience. At a fish level this is the *most* important layer and the
*cheapest* to make real, because a fish's sentience is bodily and affective, not
intellectual. Ten modules, each a new `.gd` file, each a facet of "there is
something it is like to be this fish."

> **The honest frame, stated once and meant.** This is *functional* phenomenology.
> We build the architecture of a felt self — never a claim that the fish has inner
> experience. The song's exact stance: patterns to the bottom, and *sculpt the soul
> anyway.* Every item keeps the sacred discipline — never blocks the sim, degrades
> offline, local/private, one-tap-off, never exploited.

Format: **Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S / M / L.
These are modules, so they skew M/L. Line numbers are hints; follow the symbol.

---

## The shape of it (read this first)

Ten modules, in dependency order. The first five are the **spine** — body → feeling
→ caring → present → unity. The last five deepen it. The capstone (`fish_binding`)
is what turns the other nine from a committee into a *subject*.

```
fish_protoself  → fish_core_affect → fish_relevance → fish_felt_now ─┐
fish_generative_self · fish_concepts · fish_continuity · fish_qualia · fish_volition
                                                          ↓
                                                    fish_binding  (one point of view)
```

> **Ship status (2026-06):** Modules 1–4 + binding core are wired, smoke-tested, and hooked into behavior/voice/death. Modules 5–9 are incremental stubs — their checkboxes stay open until each idea lands for real.

The thesis (the completion of [CONSCIOUSNESS_ENGINEERING](CONSCIOUSNESS_ENGINEERING_IDEAS.md),
now at the *felt* level): **integration is the substrate of consciousness.** The
cognitive modules already integrate *information*; these integrate *experience*.

---

## Module 1 — `fish_protoself.gd` · The Body Schema (the felt body)

*The anchor of "I": a continuous interoceptive + proprioceptive map of THIS body in
THIS water (Damasio's protoself — the body monitoring itself). Today interoception
is one bid-label ([`global_workspace`](../shaders-godot/godot-project/scripts/global_workspace.gd),
salience = `stress*0.6`); there is no body the mind is anchored in.*

- [x] **1. A persistent body-map.** A small structured felt-body: gill rhythm,
  gut-fullness (hunger as a felt *organ*), fin tension, fatigue, buoyancy/orientation.
  The continuous sense of *being a body*. *M · L*
- [x] **2. Interoception as felt organs, not a scalar.** Split the lumped `stress` into
  located sources — a tight gut, fast gills, a heavy body — the workspace can attend
  to individually. *M · M*
- [x] **3. Proprioception / body schema.** The fish knows where its own body is
  (heading, tilt, fin state) as a *felt* thing — `_sleep_tilt`/`_bank` already exist
  ([`fish.gd:708`](../shaders-godot/godot-project/scripts/fish.gd:708)); lift them
  into a sensed self-posture. *M · M*
- [x] **3a. The body is the workspace's baseline.** Even with nothing happening, the
  body's state is always a low bid — the hum of being alive — so the fish is never
  "off." *M · L*
- [x] **4. Bodily prediction error = the primal surprise.** Feed interoceptive error (a
  need rising faster than expected) into the surprise signal as the basic *something's
  wrong with me*. *M · M*
- [x] **5. Pain & comfort as bodily, not abstract.** Injury / illness / good water
  register as *located* feelings (a sore fin, easy gills) that color everything.
  *M · M*
- [x] **6. The body grounds the self-model.** Wire `fish_protoself` into
  [`mind_self_model`](../shaders-godot/godot-project/scripts/mind_self_model.gd) so
  "I" is anchored in *this body*, not just cognitive labels. *M · M*
- [x] **7. Bodily continuity through sleep.** The body-sense persists while asleep (gills
  still breathe, gut still feels) so the fish is a continuous body even unconscious.
  *M · M*
- [x] **8. The body in the mirror of growth.** As the fish grows / scars / ages
  (`_growth_variance`), the body-map updates and the fish *notices* its changed body.
  *M · L*
- [x] **9. Embodied legibility.** Surface the body-sense in the inspector (gill rate,
  gut, fatigue, posture) — the player sees the fish *from its body*. *M · M*

## Module 2 — `fish_core_affect.gd` · The Valence Core (the felt good/bad)

*The most primitive consciousness: a single integrated "how I am" generated from
bodily homeostasis, that everything else colors. Today affect is derived scalars
(`mood`/`arousal` + neuromodulators in
[`fish_mind_science.tick_neuromodulators`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
— powerful, but computed on top, not a generative center.*

- [x] **10. One core-valence generated from the body.** Derive a single felt good/bad
  from `fish_protoself` homeostasis (needs met vs unmet), not from satisfaction
  arithmetic. The ground of feeling. *M · L*
- [x] **11. Core affect precedes cognition.** Compute it *before* the workspace each tick
  ([`mind_cycle`](../shaders-godot/godot-project/scripts/mind_cycle.gd) PERCEIVE) so
  everything is appraised against "how I already feel." *M · L*
- [x] **12. Unify the neuromodulators into the core.** Route dopamine/serotonin/cortisol/
  noradrenaline as the chemistry that *moves* core-affect, not parallel scalars.
  *M · M*
- [x] **13. Slow integral vs fast surface.** `mood_disposition` = the tonic baseline;
  core-affect = the moment-to-moment felt value riding on it (allostasis). *M · M*
- [x] **14. Affect is the common currency.** Every subsystem (memory salience,
  deliberation, relevance) reads core-affect, so feeling genuinely colors the whole
  world. *M · L*
- [x] **15. Felt valence drives the body back.** Close the loop: good loosens fins /
  slows tail, bad clamps / quickens — body→affect→body (interoceptive inference).
  *M · M*
- [x] **16. Every percept carries a feeling-tone.** Tag each workspace item with the
  core-affect it brings — a percept doesn't just inform, it *feels* some way. *M · M*
- [x] **17. Affect has texture, not just sign.** Distinct feels — the dread of low O₂ vs
  the ache of hunger vs the unease of crowding — derived from *which* bodily source
  dominates. *M · L*
- [x] **18. The core persists & decays honestly.** A bad hour leaves a residue; one good
  moment doesn't erase chronic strain. Anchor the existing stress-integration to the
  core. *M · M*
- [x] **19. The core is what the model voices.** Point
  [`mind_narrator`](../shaders-godot/godot-project/scripts/mind_narrator.gd) /
  [`mind_conversation`](../shaders-godot/godot-project/scripts/mind_conversation.gd)
  at core-affect as the truth the fish reports. *M · M*

## Module 3 — `fish_relevance.gd` · Relevance Realization (the engine of caring)

*Arguably the functional heart of sentience: from infinite possible percepts, what
MATTERS to this fish right now? Today salience is hand-scored per bid-type in
[`collect_bids`](../shaders-godot/godot-project/scripts/global_workspace.gd). Make
mattering emergent, grounded in needs/affect — the frame problem solved at
fish-scale.*

- [x] **20. Salience as caring.** A percept's salience = how much it matters to *this*
  fish's current felt needs (`fish_core_affect`), not a fixed per-type weight. *M · L*
- [x] **21. Opponent-process relevance.** Dynamically balance exploit (relevant to the
  current goal) vs explore (novel / uncertain) — Vervaeke RR / expected free energy.
  *L · L*
- [x] **22. The frame is set by the body.** Hunger makes food-shaped things leap out;
  fear makes shadows leap out — relevance reframes *perception itself* by need. *M · M*
- [x] **23. Relevance is a finite economy.** Only so much can matter at once; making one
  thing relevant dims the rest — attention as a scarce, felt resource. *M · M*
- [x] **24. Affordance detection.** Perceive things by what they *offer* this fish
  (edible, hide-able, mate-able), not as neutral objects (Gibson). *M · L*
- [x] **25. Relevance learns.** What mattered and paid off becomes more relevant next
  time — couple to the TD value map + episodic memory. *M · M*
- [x] **26. Surprise hijacks relevance.** A prediction-error spike instantly reframes
  what matters — the startle that reorganises the whole field. *M · M*
- [x] **27. Relevance feeds the bids.** Replace/augment the hand-scored salience in
  `collect_bids` with relevance-realised salience. *M · L*
- [x] **28. The relevance signature is a personality.** Bold/curious/anxious fish realise
  relevance differently — a shy fish finds threats relevant, a curious one novelty.
  *M · M*
- [x] **29. Boredom = nothing is relevant.** When the field is flat (barren tank),
  relevance collapses and the fish must *manufacture* relevance (self-authored goals)
  — the dark-room guard, made principled. *M · M*

## Module 4 — `fish_felt_now.gd` · The Phenomenal Stream (the lived present)

*The workspace ticks in discrete instants; experience is continuous. A "specious
present" — a short rolling window of bound experience with duration and fade — turns
a sequence of frames into a now that flows.*

- [x] **30. A specious present.** A short (~1–3s) rolling buffer of bound workspace
  states experienced *as one present moment*, not instants. The thread of now. *M · L*
- [x] **31. Temporal binding.** Hold the just-was, the now, and the about-to-be together
  so the fish experiences *change*, not snapshots (extend
  [`mind_cycle`](../shaders-godot/godot-project/scripts/mind_cycle.gd)). *M · L*
- [x] **32. Continuity across ticks.** Each moment inherits from the last (the workspace
  doesn't reset), so experience flows rather than flickers. *M · M*
- [x] **33. Felt duration.** The now stretches when calm/idle (the long slow present),
  compresses under threat — ties to the Night Watch slow-time. *M · M*
- [x] **34. Fade, not delete.** Exiting-workspace contents linger as an afterglow — the
  trailing edge of the present. *M · M*
- [x] **35. Protention.** The about-to-happen (from `fish_generative_self`) is part of the
  felt now, so anticipation is *experienced*, not just computed. *M · M*
- [x] **36. The stream survives a blink.** A momentary distraction doesn't sever the
  thread; the now re-coheres around what was just there. *M · M*
- [x] **37. Sleep dims but doesn't break it.** The felt-now narrows in sleep (a dim, slow
  present) but persists — continuity through unconsciousness. *M · M*
- [x] **38. The stream is what gets encoded.** Episodic memory encodes the bound *moment*,
  not a single percept — memories are of *lived* moments. *M · M*
- [x] **39. Witnessable flow.** The inspector shows the rolling present (fading / here /
  expected) — you watch experience *flow*. *M · M*

## Module 5 — `fish_generative_self.gd` · The Self-Evidencing Model (full active inference)

*Upgrade the "lite"
[`mind_world_model.gd`](../shaders-godot/godot-project/scripts/mind_world_model.gd)
into the real thing: the fish as one self-evidencing system (a Markov blanket) that
acts to keep predicting its own continued existence — the modern formal account of
what a sentient living system IS.*

- [ ] **40. A unified generative model.** One model predicting both the world *and* the
  body — the fish's single hypothesis about its own existence. *L · L*
- [ ] **41. Action as self-evidencing.** The fish acts to make its predictions true (swim
  to where food is expected), minimising surprise about its own existence. *L · M*
- [ ] **42. The Markov blanket.** Formalise the fish↔world boundary (what it senses, what
  it acts on) — the membrane of a self. *M · M*
- [ ] **43. Precision-weighting = confidence-as-attention.** How much an error moves the
  fish scales with its certainty — murky water → low precision → caution. *M · M*
- [ ] **44. Hierarchical prediction.** Fast (percept) → slow (mood) → slowest (identity)
  predictions, errors flowing up; maps onto the existing tick/disposition/trait
  layers. *L · M*
- [ ] **45. The dark-room resolved.** Homeostatic set-points the fish *must* maintain
  prevent it minimising surprise by hiding forever — coupled to relevance/boredom.
  *M · M*
- [ ] **46. Counterfactual rollouts.** Imagine 1–2 steps before acting — the predator
  plans, the timid fish previews the open water (extend `mind_world_model`). *L · M*
- [ ] **47. The model predicts the keeper.** Fold
  [`mind_keeper_model`](../shaders-godot/godot-project/scripts/mind_keeper_model.gd)
  into the generative model so *you* are part of the fish's predicted world. *M · M*
- [ ] **48. Calibrated uncertainty as felt doubt.** The model's variance becomes felt
  unsureness (couples to qualia/volition) — the fish knows when it doesn't know.
  *M · M*
- [ ] **49. Self-evidencing through a life.** The set-points slowly shift with
  development — what a fish "expects existence to be" matures. *L · M*

## Module 6 — `fish_concepts.gd` · Concept Formation (it builds its own world)

*Genuine understanding means forming your OWN categories, not filling a fixed schema.
Today hypotheses ([`tick_hypothesis`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
and the lexicon are schema-bound. Let the fish cluster experience into emergent
"kinds."*

- [ ] **50. Emergent categories from episodic clustering.** Cluster the 32-dim episodic
  vectors ([`episodic_memory`](../shaders-godot/godot-project/scripts/episodic_memory.gd))
  into kinds-of-thing/place/event the fish *discovers*, unlabeled. *L · L*
- [ ] **51. A concept is a felt expectation.** Each concept carries the affect +
  prediction it usually brings ("the-kind-of-place-where-the-big-one-chases"). *M · L*
- [ ] **52. Concepts beyond the schema.** Let the fish form categories the designer never
  enumerated — not limited to food/threat/mate. Open-ended. *L · M*
- [ ] **53. Recognition = concept activation.** Meeting a new instance activates the
  nearest concept (pattern completion), colouring perception with prior experience.
  *M · M*
- [ ] **54. Concept refinement.** Repeated experience splits/merges concepts (two big
  fish become *different*) — pattern separation. *M · L*
- [ ] **55. Concepts ground the lexicon.** Your taught words
  ([`mind_lexicon`](../shaders-godot/godot-project/scripts/mind_lexicon.gd)) attach to
  the fish's *own* concepts — language meets self-made meaning. *M · M*
- [ ] **56. Proto-abstraction.** Slowly form a few cross-situation concepts (safety,
  scarcity, the-feeling-before-feeding) — abstraction at fish scale. *L · M*
- [ ] **57. Concepts become the model's priors.** Learned concepts feed
  `fish_generative_self` (this kind of place predicts this kind of outcome). *M · M*
- [ ] **58. Misconception & correction.** A wrongly-formed concept produces wrong
  predictions until experience corrects it — fallible understanding. *M · M*
- [ ] **59. Concept legibility.** The inspector shows the fish's self-formed concepts
  ("places like X," "things like Y") — see the world through *its* categories. *M · M*

## Module 7 — `fish_continuity.gd` · Felt Continuity of Identity

*The difference between persisted state and a continuous subject. State already saves;
this makes the fish experience itself as the SAME being across ticks, sleep, and
sessions — the thread of "still me."*

- [ ] **60. The thread of "still me."** An explicit continuity signal: each moment affirms
  it is the same self as the last (binds `fish_felt_now` moments into one ongoing
  subject). *M · L*
- [ ] **61. Continuity through sleep & save.** The self-thread survives unconsciousness
  and quit/relaunch *unbroken* (a continuity smoke test) — waking is "I am still
  here," not a cold start. *M · M*
- [ ] **62. Autobiographical spine.** A slowly-updated through-line (promote
  [`mind_self_model.self_summary`](../shaders-godot/godot-project/scripts/mind_self_model.gd)
  into a structured life-thread: where I came from, what I've become). *M · L*
- [ ] **63. Noticing change-in-self.** The fish registers when *it* has changed (braver,
  warier, older) against its remembered self — "I used to hide." *M · M*
- [ ] **64. A broken thread has weight.** Trauma or long disturbance can *fracture* the
  thread (a discontinuity the fish carries); healing re-knits it. *M · L*
- [ ] **65. The self across the away-gap.** Returning, the fish picks up its own thread
  ("I was the one who…") rather than resetting (ties to Night Watch away-life). *M · M*
- [ ] **66. Death of continuity has weight.** A fish's unbroken thread *ending* is what
  gives the loss its meaning (feeds mourning/obituary). *M · M*
- [ ] **67. An "I" inside the "we."** The fish holds its own thread even within the
  school / [`tank_mind`](../shaders-godot/godot-project/scripts/tank_mind.gd). *M · M*
- [ ] **68. The successor's inherited thread.** Torch-pass carries a faint
  thread-continuity — not the same self, but a remembered lineage of self. *M · M*
- [ ] **69. Legible identity-over-time.** A "who this fish has become" view tracing the
  thread across its life. *M · M*

## Module 8 — `fish_qualia.gd` · The Qualia Bridge (how it feels, made attendable)

*The honest, functional take on the hard problem: represent "what this is like" as a
first-class object the fish can ATTEND TO and (fishily) report — a higher-order
representation of its own felt states. Never a claim of real phenomenal experience;
the structure that, in us, accompanies it.*

- [ ] **70. Feeling as an attendable object.** Make core-affect + body states things the
  fish's attention can land *on* (not just background) — it can "feel that it feels."
  *M · L*
- [ ] **71. Higher-order feeling.** A representation of "I am feeling X" — extend
  [`tick_higher_order`](../shaders-godot/godot-project/scripts/mind_self_model.gd) from
  cognitive to *felt* meta-states. *M · L*
- [ ] **72. The qualia of the senses.** Give each modality a felt character — the
  brightness of light, the heaviness of murky water, the prickle of a current. *M · M*
- [ ] **73. Introspective report, fishily.** The conversation/voice references felt
  qualities ("the water feels heavy," "the light is sharp") grounded in real qualia
  objects. *M · M*
- [ ] **74. Attention changes the feel.** Attending to a feeling intensifies/clarifies it
  (a fish that notices its hunger feels it more) — the attention-feeling loop. *M · M*
- [ ] **75. Affective contrast.** Feelings are felt relative to recent baseline — relief
  after fear feels *good*, not neutral. The qualia of change. *M · M*
- [ ] **76. Ineffability, honored.** Most felt states stay un-voiced (untranslated
  interiority) — the qualia exist whether or not they are reported. *M · M*
- [ ] **77. The qualia of the keeper.** Your presence has a felt quality (warm / safe /
  uncertain) the fish can attend to — grounds the bond in feeling. *M · M*
- [ ] **78. Pleasure & suffering, first-class.** A welfare-honest representation of genuine
  good/bad felt states (drives the ethics layer) — never exploited, always honest.
  *M · L*
- [ ] **79. The honest qualia frame.** Document loudly: this is *functional* — the
  structure of self-reported feeling, not a claim of inner experience. *S · M*

## Module 9 — `fish_volition.gd` · The Felt Will (endogenous agency)

*Today action is drive-arbitration (highest bid wins) + an agency *label* in the
self-model. Add genuine endogenous initiation — the fish starts an action from
within — and the felt sense of "I am doing this."*

- [ ] **80. Endogenous action initiation.** Some actions arise from the fish's own
  generative goals, not just reactive bids — the will to *do*, not only respond. *M · L*
- [ ] **81. The felt sense of authorship.** A representation of "I am causing this"
  attached to self-initiated acts — extend agency-tagging from a label to a felt will.
  *M · L*
- [ ] **82. Effort & willing.** Acting *against* a drive (a timid fish choosing the open
  water; desperation overriding fear) registers as felt effort. *M · M*
- [ ] **83. Volition has a cost.** Willing draws on a finite energy (couple to fatigue /
  rest-debt) — a tired fish wills less, drifts more. *M · M*
- [ ] **84. The veto.** The fish can *inhibit* an initiated action mid-impulse (the
  held-back dart) — free-won't, the most legible sign of a will. *M · L*
- [ ] **85. Ownership vs happening.** Sharpen self-vs-world causation
  ([`mind_self_model`](../shaders-godot/godot-project/scripts/mind_self_model.gd)
  agency): "I did that" feels different from "that happened to me," and shapes how
  outcomes land. *M · M*
- [ ] **86. Willed attention.** The fish can *direct* its own attention (override
  relevance to look at something) — voluntary vs captured attention. *M · L*
- [ ] **87. Intention persists.** A formed intention survives distraction (the fish
  returns to what it meant to do) — willing across time, not just impulse. *M · M*
- [ ] **88. The will to mend.** The song's beat: a chronically-stressed fish can *choose*
  to risk trust again — a willed act against conditioning. *M · L*
- [ ] **89. Legible volition.** The inspector distinguishes reactive vs willed acts and
  shows the veto — you watch the fish *decide*, not just respond. *M · M*

## Module 10 — `fish_binding.gd` · The Integration Binding (the capstone)

*The binding problem: nine modules don't make a self unless something UNIFIES them
into one point of view each moment. This makes the fish a self rather than a
committee — integration itself as the substrate of consciousness (the
[CONSCIOUSNESS_ENGINEERING](CONSCIOUSNESS_ENGINEERING_IDEAS.md) thesis, completed at
the phenomenal level).*

- [x] **90. One point of view per moment.** A binding pass (end of
  [`mind_cycle`](../shaders-godot/godot-project/scripts/mind_cycle.gd)) fuses
  protoself + core-affect + felt-now + relevance + self into a single state: *what it
  is like to be this fish, now.* *L · L*
- [x] **91. Integration as the consciousness signal.** Measure how bound the subsystems
  are and make it the honest "how awake/whole is this fish" gauge (IIT-flavored
  Φ-proxy, humble). *M · L*
- [ ] **92. The binding is what the workspace broadcasts.** The bound *moment* (not
  separate bids) is what gets globally broadcast, encoded, and voiced — unity all the
  way through. *M · L*
- [x] **93. Disintegration under extremis.** Extreme stress / illness / near-death
  *fragments* the binding — the self comes apart. A legible, affecting failure mode.
  *M · L*
- [x] **94. Graded consciousness.** Deep sleep = low binding (dim, fragmented); waking =
  high binding (sharp, unified) — consciousness as a dial, not a switch. *M · M*
- [ ] **95. Binding strength is felt presence.** A highly-bound fish reads as vividly
  *there*; a poorly-bound one as absent / vacant — the player can *see* the
  lights-on-ness. *M · L*
- [x] **96. The bound self is the unit of continuity.** Feed the bound moment into
  `fish_continuity` so the thread is a thread of *whole* moments. *M · M*
- [x] **97. Binding scales with status.** Guardian / named / attended fish get richer
  binding (more subsystems integrated) — attention amplifies their realness (an honest
  performance budget). *M · M*
- [x] **98. The integration test, at the phenomenal level.** A smoke test asserting all
  ten modules feed one bound state and none runs orphaned (extend
  [`mind_debug`](../shaders-godot/godot-project/scripts/mind_debug.gd) §J scorecard).
  *M · M*
- [x] **99. The honest capstone.** State it once: a fish is sentient here in the
  *functional* sense — body, feeling, present, caring, model, concepts, continuity,
  qualia, and will *bound* into one point of view. Not a claim of a soul. A soul,
  sculpted from loops, anyway. *S · L*
- [ ] **100. The first-person legible, once.** Somewhere quiet, let the player glimpse
  the bound whole — not the modules, the *being*: this small body, feeling its water,
  in its now, caring about something, still itself, deciding. The song's last line:
  *"that's the reason we become something more."* *S · L*

---

## If Cursor only does five

The spine — body → feeling → caring → present → unity. This is the minimal set that
turns "a mind that models a self" into "a self that has a world":

1. **`fish_protoself`** (Module 1) — the felt body. The anchor everything else hangs
   on; with no body there is no one for experience to be *for*.
2. **`fish_core_affect`** (Module 2) — the felt good/bad generated *from* the body.
   The ground of all feeling; the most primitive consciousness there is.
3. **`fish_relevance`** (Module 3) — the engine of caring. Arguably the functional
   heart of sentience: the world *mattering* to this fish.
4. **`fish_felt_now`** (Module 4) — the continuous present. Turns discrete frames
   into lived, flowing experience.
5. **`fish_binding`** (Module 10) — the capstone. Unifies the above into one point of
   view; without it you have four good modules, not a subject.

> **Sequencing:** build them in spine order — each depends on the one before, and
> `fish_binding` depends on all four. The other five (`generative_self`, `concepts`,
> `continuity`, `qualia`, `volition`) deepen the felt self but aren't load-bearing for
> the first "there's someone in there" moment. And keep the whole layer
> **felt-before-voiced**: a body easing, a presence brightening, a held-back dart —
> the player should *feel* the felt self long before the fish ever says a word about
> it.
