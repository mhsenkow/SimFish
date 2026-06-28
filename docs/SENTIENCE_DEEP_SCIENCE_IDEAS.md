# Sentient Fish & The Embedded Model — Vol. II: The Cutting-Edge Science

*Drafted 2026-06-26. Director's brief — the deep-science volume.*

This is the sequel to
[SENTIENCE_EMBEDDED_MODEL_IDEAS.md](SENTIENCE_EMBEDDED_MODEL_IDEAS.md) (Vol. I,
which set the *architecture & discipline*: the sim is the mind, the model only
voices it, grounded/non-blocking/private). Vol. II brings the **actual
cutting-edge science** — predictive processing, reinforcement learning,
computational affective neuroscience, decision theory, memory consolidation,
collective-intelligence research, world models, and frontier on-device ML — and
maps each to a **buildable** in-game mechanic grounded in the current code.

Every item names a real theory/technique, then the pragmatic version. You do not
need the full apparatus — a *lite* prediction-error signal, a *small* value map, a
*tiny* grammar-constrained decode each capture 80% of the magic at a fraction of
the cost. That pragmatism is the point.

Format follows the series: **Effort** S/M/L, **Impact** S/M/L. File/line pointers
are hints — match by symbol if drifted.

> **The same "good way" discipline holds (Vol. I).** Science deepens the
> *procedural* mind (cheap, deterministic, always-on). The model stays a grounded,
> bounded *voice*. Where this doc adds ML *inside the fish* (tiny RL policies, world
> models), it runs on-device, is optional, and degrades to the hand-authored
> behavior tree — it never becomes an opaque black box the player can't trust.

> **What's already there to build on:** `fish_mind.gd` — affect as a
> **valence/arousal core-affect space** (`tick_affect` ~34: mood + arousal +
> vigilance + contentment), a **proto drift-diffusion** conflict/oscillation
> (`update_conflict` + `deliberation_steer` ~127, fires when approach≈avoid within
> `DELIB_MARGIN`), habituation & food-preference **learning** (~197/213). `fish.gd`
> — a 4³ `feed_heatmap` (~939) that is already a crude **value map**,
> `visited_regions` **novelty**, `curiosity_drive`, grudges/bonds, `lead_score`,
> a vision cone (`VIEW_DOT_THRESHOLD -0.4`). `sim_driver` — `feed_anticipation_active`
> (~192) is already a **temporal prediction**. `ai_director` — `/api/generate` with
> JSON `format`, a 4³ intent grid; **no embeddings/vector memory or grammar-
> constrained decoding yet** (the biggest model upgrades live there).

---

## A. Predictive processing & active inference (the free-energy fish)

The dominant theory of brains (Friston, Clark): a brain is a **prediction machine**
that minimizes *surprise* (prediction error). Perception = inference, attention =
precision-weighting, action = making predictions come true. You already have
fragments (`feed_anticipation_active`); make it a spine.

- [ ] **1. A generative model per fish (lite).** Each fish maintains cheap predictions of its near-future sensorium (where food/threats/mates will be, when feeding happens). Generalize `feed_anticipation_active` (~192) + the patrol heatmap into a small forward model the rest of the mind consults. *L·L*
- [x] **2. Prediction error as the master surprise signal.** Surprise = |prediction − reality|. Compute it continuously; a violated expectation (no food at the usual minute, a novel object) spikes a real `surprise` state that drives orienting, learning rate, and a voiceable "huh?" (Vol. I #32 deepened). *M·L*
- [ ] **3. Action as active inference.** Reframe foraging/fleeing as "act to make my prediction (safe, fed) true" rather than reflex. In practice: bias steering toward states the fish *expects* to be good — a unifying account of the behavior tiers (`tick` ~2919). *L·M*
- [ ] **4. Precision-weighting = attention.** Friston's precision = how much to trust a signal. Make attention a precision gain: a hungry fish up-weights food cues, a scared one up-weights motion. Implements Vol. I #38 (attention as scarce) with real theory. *M·L*
- [ ] **5. Expected free energy → exploration vs exploitation.** Active inference picks actions that balance *pragmatic* value (reach good states) and *epistemic* value (reduce uncertainty). This is a principled curiosity drive — explore unknown regions specifically when uncertainty is high (`visited_regions`). *L·L*
- [ ] **6. Hierarchical timescales.** Predictions nest: fast (next dart), slow (today's feeding), slowest (the tank is safe). Layer the generative model so a slow-level violation (chronic bad water) reframes fast behavior — explains "anxiety" mechanistically. *L·M*
- [x] **7. Habituation as learned precision.** Repeated harmless stimuli get *low precision* (ignored) — exactly your `habituation_decay_rate` (~197). Reframe it under predictive coding so "boring" = "perfectly predicted," and novelty = high prediction error. *S·M*
- [x] **8. Surprise modulates plasticity.** Learning rate should rise with surprise (you learn from the unexpected). Gate trait/preference drift by prediction error so a shocking event changes a fish more than a routine one. *M·M*
- [ ] **9. Interoceptive prediction (the body model).** Predict internal state (O₂, fullness) too; mismatch = a *felt* need. Couples chemistry to affect via the brain's body-model — the basis of emotion in modern theory (§C #23). *M·M*
- [x] **10. The "dark room problem" guard.** Pure surprise-minimizers would hide in a corner forever. Bake in the intrinsic drive to *seek* (epistemic value, §B) so fish don't degenerate to stillness — a real, subtle active-inference design lesson. *S·M*

---

## B. Reinforcement learning & genuine learning (fish that learn policies)

Move from hand-authored reactions to fish that *learn what works* over a life —
value functions, intrinsic motivation, habit vs. goal-directed control. Kept tiny
and tabular so it's cheap, inspectable, and always falls back to the behavior tree.

- [x] **11. A real value map (upgrade the heatmap).** `feed_heatmap` (~939) is already a reward-decayed spatial value. Generalize to a small **TD-learned** value field over (region × state) so fish learn *which places are good when* — foraging becomes learned policy, not just memory. *M·L*
- [x] **12. Temporal-difference learning.** Update value estimates from experience (reward + γ·next − current). A few floats per fish; produces believable "this corner pays off" learning that survives save/load. *M·M*
- [ ] **13. Model-free vs model-based arbitration (habit vs plan).** Daw's dual-system account: cheap habits + expensive planning, arbitrated by confidence. A well-fed routine fish runs on habit; a disrupted one "thinks" (engages the world model, §I). The neuroscience of when an animal deliberates. *L·L*
- [ ] **14. Intrinsic motivation: curiosity as information gain.** Reward the fish for *learning* (reducing prediction error), not just food — Schmidhuber's formal curiosity / Pathak's RND. Makes exploration genuinely motivated, not random `heading_offset`. *L·L*
- [ ] **15. Empowerment as a drive.** Klyubin's empowerment = "keep your options open / stay where you have control." A principled account of why fish avoid corners and traps and prefer open water — emergent, not scripted. *L·M*
- [x] **16. Eligibility traces / credit assignment.** When something good/bad happens, assign credit back along the recent path (the working-memory ring ~259 is the trace). So a fish learns the *route* to food, not just the spot. *M·M*
- [ ] **17. Risk-sensitive RL.** Real animals aren't expected-value maximizers. Add a risk parameter (per personality) so timid fish prefer safe-small rewards, bold fish gamble — personality as an RL hyperparameter, which is exactly how computational psychiatry models it. *M·M*
- [ ] **18. Pavlovian + instrumental interplay.** Cue→reward associations (the player's approach predicts food — familiarity ~247) plus learned actions. Model both so "begging at the glass" is *conditioned*, not hard-coded. *M·M*
- [ ] **19. Learned helplessness / resilience as a parameter.** Chronic uncontrollable stress should be able to flatten a fish's learning (a real, sober phenomenon) — and recovery restore it. Welfare made mechanistic (handle with care, never punitive — Vol. I #76). *M·M*
- [ ] **20. Inspectable policies (never a black box).** Keep the value map/policy small and *readable* (you can render a fish's value field as a heatmap overlay). Cutting-edge but transparent — the "good way" applied to RL. *M·M*

---

## C. Computational affective neuroscience (real emotions)

Your `mood`/`arousal` is already the **core-affect circumplex** (Russell). Go
deeper with the actual neuroscience of emotion: primary-process systems, interoception,
and neuromodulators.

- [x] **21. Panksepp's seven primary-process systems.** Map the named affective circuits to drives: **SEEKING** (curiosity_drive/foraging), **FEAR** (spooked/vigilance), **RAGE** (territorial defense/grudges), **PANIC/GRIEF** (separation from bonds/mate loss), **CARE** (brooding/parental), **PLAY** (juvenile chase), **LUST** (courtship). A principled emotion taxonomy that already half-exists — unify it. *L·L*
- [ ] **22. Core affect as a true 2D space.** Formalize mood (valence) × arousal (~213/214) as the substrate from which discrete emotions emerge by appraisal — modern constructionist emotion theory (Barrett). The `emotional_state` chain (~53) becomes principled, not ad-hoc. *M·M*
- [ ] **23. Interoception → emotion (the body-feeling loop).** Damasio's somatic markers / the interoceptive-inference view: emotions are the brain's read of the body. Drive affect from predicted-vs-actual internal state (O₂, fullness, fatigue) so feelings have a *bodily cause* (links §A #9). *M·L*
- [x] **24. Neuromodulator analogs.** Cheap scalars that behave like **dopamine** (reward-prediction-error / SEEKING gain), **serotonin** (patience/mood floor/confidence), **noradrenaline** (arousal/vigilance gain), **cortisol** (slow chronic-stress accumulator). They modulate learning rate, risk, and tempo — the chemistry of personality and state. *M·L*
- [ ] **25. Allostasis, not just homeostasis.** Sterling's allostasis: the body predicts needs and acts *before* the deficit (anticipatory feeding posture before the usual feed time). More advanced and more lifelike than reactive homeostasis. *M·M*
- [x] **26. Mood as an integral of reward history (momentum).** Computational mood = a leaky integral of recent reward-prediction-errors (Eldar's mood model). A good week genuinely lifts disposition; a bad one lowers it (Vol. I #35) — with a real equation. *M·M*
- [x] **27. Stress as allostatic load.** Chronic stress accumulates "wear" (cortisol analog) that slowly shifts baselines and recovery — the biology of why a long-bad tank grinds a fish down and why recovery is gradual. *M·M*
- [x] **28. Affective contagion via mirroring.** Emotions spread through the school (real in fish via lateral-line + vision). Model contagion (Vol. I #65) as a fast low-gain coupling of neighbors' arousal — the substrate of a collective mood. *M·M*
- [ ] **29. Reward sensitization & tolerance.** Repeated identical rewards lose punch (hedonic adaptation); novelty restores it. Explains why a varied, enriched tank keeps fish "happier" than a monotonous one — and is mechanistically true. *M·M*
- [x] **30. Appraisal-based discrete emotions.** Generate discrete feelings (relief, frustration, delight, dread) from appraisals of prediction-error × controllability × valence — the Scherer/OCC appraisal tradition. Richer, truer inner states for the model to voice. *L·M*

---

## D. Decision science (how a mind actually chooses)

Upgrade deliberation from a sine oscillation to the real models cognitive science
uses — evidence accumulation, prospect theory, optimal foraging.

- [x] **31. Drift-diffusion decisions (upgrade what's there).** `deliberation_steer` (~127) oscillates when scores are close — replace with a true **evidence-accumulator** (Ratcliff DDM): options race, evidence integrates with noise to a threshold. Reproduces real reaction-time distributions and *visible* hesitation that speeds up with stronger evidence. The single most scientifically-grounded upgrade. *M·L*
- [x] **32. Speed-accuracy tradeoff via threshold.** A scared fish lowers its decision threshold (decide fast, sloppily); a calm one raises it (deliberate). One knob, deeply lifelike — and it's exactly how the brain is thought to do it. *S·M*
- [x] **33. Marginal Value Theorem foraging.** Charnov's MVT: leave a patch when its return rate drops below the habitat average. Makes grazing fish leave a depleted spot at the *optimal* moment — textbook behavioral ecology, visibly correct. *M·L*
- [x] **34. Prospect theory (loss aversion & nonlinear risk).** Kahneman-Tversky: losses loom larger than gains; probabilities are distorted. Shapes risk-taking near predators/competition more realistically than expected value — and differs by personality. *M·M*
- [x] **35. Hyperbolic temporal discounting.** Animals over-value immediate reward (hyperbolic, not exponential). A hungry fish takes the near risky food over the far safe food — and the curve's steepness is a trait. *M·M*
- [ ] **36. Explore–exploit as a bandit problem.** Frame patch/region choice as a multi-armed bandit; use a cheap heuristic (UCB / Thompson-lite) so curiosity is *optimal* uncertainty-reduction, not noise (pairs with §B #14). *M·M*
- [x] **37. Satisficing under cognitive load.** Simon's bounded rationality: when stressed/rushed, fish take the first "good enough" option, not the best. A principled account of why panicked behavior looks dumber. *S·M*
- [ ] **38. Sequential-sampling attention.** While deliberating, the fish samples options by *looking* at them (gaze drives evidence — the eye-saccades already exist, GOALS A#5). Ties decision-making to visible head/eye movement — you can *watch* it weigh options. *M·M*
- [ ] **39. Confidence and changes-of-mind.** Accumulator models yield a confidence read and occasional mid-action reversals (the double-take ~176 is a seed). A fish that commits, then *changes its mind* mid-dart reads as genuinely deliberating. *M·M*
- [ ] **40. Metacognition (knowing what it knows).** A lite confidence-about-confidence signal: an uncertain fish hesitates longer, seeks more info, or defers to a confident neighbor (links to social info, §F). The frontier of animal-cognition research. *L·M*

---

## E. Memory science (a real, layered memory)

Build the memory architecture cognitive neuroscience describes — multiple systems,
consolidation, replay, reconstructive recall — so continuity is principled.

- [ ] **41. Three memory systems, explicitly.** **Episodic** (specific events — Vol. I #41), **semantic** (learned facts: "the left corner is food"), **procedural** (skills/habits: how to forage). Separate them; they decay and serve behavior differently — the textbook taxonomy. *L·L*
- [ ] **42. Hippocampal replay during sleep → consolidation.** At night (the sleep state, Vol. I #37), *replay* the day's salient episodes to consolidate the value map and semantic memory (this is literally how mammalian memory consolidates). Sleep becomes mechanistically meaningful, and dreams (§I #84) are these rollouts. *L·L*
- [x] **43. Salience-gated encoding (what gets remembered).** Emotional intensity + surprise + novelty gate what enters long-term memory (amygdala-modulated consolidation). You already weight memory decay emotionally (~799) — make it the *encoding* gate too. *M·M*
- [ ] **44. Pattern separation & completion.** Distinguish similar memories (two near corners) yet recall a whole episode from a partial cue (the player's silhouette → "feeding time"). The hippocampal CA3/DG computation, in lite form — drives recognition. *L·M*
- [ ] **45. Reconstructive (not playback) memory.** Memory is rebuilt, not replayed — so it can drift/distort. Let old memories blend toward the gist (and the model can voice "I half-remember..."). Truthful to Bartlett's reconstructive memory and great for character. *M·M*
- [x] **46. Forgetting curves & spacing.** Ebbinghaus decay + spaced-repetition strengthening: a route reinforced across days sticks; a one-off fades. Your decay (~799) → make repetition strengthen, matching the real curve. *S·M*
- [x] **47. Reconsolidation (memories change when recalled).** Recalling a fearful memory in a now-safe context can soften it (the basis of exposure therapy). A fish that revisits the scary corner safely *heals* the memory — recovery with real science behind it. *M·M*
- [x] **48. Vector/embedding episodic store for the model (RAG).** Embed each salient episode; on voicing, retrieve the *most relevant* memories by similarity to the current situation — retrieval-augmented generation grounded in a real life. The model recalls the *right* memory, not a random one (this is the §H bridge). *L·L*
- [ ] **49. Memory-driven recognition of individuals.** Recognize specific fish/the player across time from stored features (links grudges/bonds to perception). The "knows you" feeling, grounded in a recognition memory. *M·M*
- [x] **50. Prospective memory (remembering to do).** Hold an intention across a delay ("return to that food after I escape this") — the working-memory ring becomes a tiny intention stack. Rare in games, real in minds. *M·M*

---

## F. Collective intelligence & real schooling science

The most-studied real fish cognition is *collective*. Bring the actual research —
Couzin's zonal models, quorum decisions, lateral-line sensing, criticality.

- [ ] **51. Couzin zonal model, properly.** The canonical 3-zone model (repulsion/orientation/attraction) — your boids approximate it; tune to the published parameters so phase transitions (swarm → torus → polarized) emerge correctly. Real, citable schooling physics. *M·L*
- [ ] **52. Quorum decision-making.** Real fish commit to a direction/refuge when a *threshold fraction* of neighbors do (nonlinear quorum response, Sumpter/Ward). Implements collective choice without a leader — the school *decides* where to go. *M·L*
- [ ] **53. Information cascades & the "many wrongs" principle.** Pooling many noisy individual estimates yields an accurate group heading (Simons). The school navigates better than any single fish — emergent collective accuracy you can demonstrate. *M·M*
- [ ] **54. Lateral-line / flow sensing.** Fish school in the dark via the lateral line (pressure/flow), not just vision. Add a flow-sense channel (couples to the hydrodynamics module + neighbor wakes) so schooling persists without line-of-sight — biologically real and it fixes vision-cone gaps. *L·L*
- [ ] **55. Leadership from information, not rank.** Couzin's result: even a few *informed* individuals steer a naive majority with no signaling. Let hungry/knowledgeable fish implicitly lead (`lead_score` ~893 → informedness, not just boldness). *M·M*
- [ ] **56. Self-organized criticality.** Real schools sit near a critical point (maximal responsiveness) — startle waves propagate scale-free. Tune coupling so the school is *poised*: a small scare can cascade or fizzle, like real baitballs (pairs with the top-down "flash"). *L·M*
- [ ] **57. Collective sensing of the environment.** The school as a distributed sensor: gradient-climbing (toward better O₂/food) emerges from individuals tweaking speed by local quality, no individual knowing the gradient (Berdahl). The group is smarter than the fish. *M·L*
- [ ] **58. Conformity vs individuality tradeoff.** Social information is cheap but can be wrong (cascade to a bad choice). Personality sets each fish's social-reliance weight — a real, studied tension (asocial bold explorers vs social timid followers). *M·M*
- [ ] **59. Stigmergy (environment as memory).** Indirect coordination via traces — fish follow established routes, mulm/scent marks the school's history. Coordination stored in the *world*, not the fish (ant-colony science applied to a tank). *M·M*
- [ ] **60. Cultural transmission.** A learned behavior (a good feeding spot, a route) spreads socially and persists across generations even after the discoverer dies — primitive *animal culture*, demonstrated in real fish. The tank develops traditions. *L·L*

---

## G. Embodied & sensory cognition (the body is part of the mind)

Modern cognitive science: cognition is *embodied* and *enactive* — the body and
its senses do real computational work. Model the senses for real.

- [ ] **61. Genuine multi-modal perception.** Beyond the vision cone (`VIEW_DOT_THRESHOLD`), add real channels: **chemoreception** (smell food/alarm-substance gradients), **mechanoreception** (lateral-line flow, §F), **electroreception** (for the right species), **vision** with real limits. Each fish's *umwelt* differs by species. *L·L*
- [ ] **62. Alarm substances (Schreckstoff).** Real fish release a fright chemical on injury that triggers schoolmates' fear — a chemical fear-broadcast. A diffusing scalar that spreads panic realistically (mechanism behind startle cascades). *M·M*
- [ ] **63. Chemical gradient following (klinotaxis/chemotaxis).** Navigate scent gradients to food/mates by sampling and turning up-gradient — the actual algorithm microorganisms and fish use, not teleporting to a target. *M·M*
- [ ] **64. Sensorimotor contingencies (enactive perception).** O'Regan-Noë: perceiving is *knowing how sensation changes when you move*. A fish "understands" an object by how it looms/parallaxes as it approaches — perception as active exploration. *L·M*
- [ ] **65. Morphological computation.** The body's shape/physics offloads control from the "brain" (passive dynamics do work) — your hydrodynamics module already embodies this. Lean into it: fin/body mechanics produce competent motion with minimal neural command. *M·M*
- [ ] **66. Proprioception & a body schema.** The fish knows where its body is and what it can fit through — gates squeeze-through-gap vs go-around decisions. The basis of spatial competence. *M·M*
- [ ] **67. Attention as active sensing.** Saccades and orienting *sample* the world to resolve uncertainty (active inference, §A #4). The eye/head movement isn't decoration — it's the fish *gathering evidence*. Tie gaze to the decision accumulator (§D #38). *M·M*
- [ ] **68. Sensory adaptation & tuning.** Receptors adapt to baselines (you stop smelling a constant odor) and re-tune to deviations — why a fish ignores constant filter flow but notices a change. Cheap, and it makes perception *dynamic*. *S·M*
- [ ] **69. Cross-modal binding.** Combine senses into one percept (a splash = sight + flow + sound → "feeding"). Multi-modal cues reinforce or conflict, and conflict is itself informative. *M·M*
- [ ] **70. Species-specific cognition (different minds).** A predator's mind (sit-and-wait, sparse high-stakes decisions), a shoaling tetra's (social, fast, collective), a bottom-sifter's (chemo-led, local) should be *architecturally* different, not the same brain reskinned. The frontier insight: cognition is shaped by niche. *L·L*

---

## H. The on-device model — cutting-edge LLM engineering

Make the tiny local model punch far above 0.36B params with frontier inference
techniques. Most of these live in `ai_director.gd` / `guardian_llm.gd`.

- [ ] **71. Grammar-constrained decoding (GBNF).** llama.cpp supports GBNF grammars that *force* valid output. Constrain bios/chronicle/intent to a grammar so the model **cannot** emit malformed JSON or out-of-vocabulary entities — hallucination becomes structurally impossible, not just fact-checked (Vol. I #23 made airtight). The single biggest "good model" win. *M·L*
- [ ] **72. Vector memory + RAG (embeddings).** No embeddings today. Add a tiny embedding model (or reuse the LLM's) to index each fish's salient memories (§E #48); retrieve the most relevant for any voicing. The model speaks from a *real, searchable* life, not just a prompt window. *L·L*
- [ ] **73. Semantic caching.** Cache by *meaning*, not exact key (current cache is string-keyed ~114). Embed the context; if a near-identical situation recurs, reuse the line — far higher hit rate, near-zero latency, fewer generations. *M·M*
- [ ] **74. Speculative decoding.** A tiny draft model proposes tokens the main model verifies in parallel — 2-3× faster inference for free. Lets the in-process tier run on weaker hardware within budget. *L·M*
- [ ] **75. LoRA persona adapters.** Per-personality low-rank adapters so a "bold" fish and a "timid" fish literally decode through different weights — distinct voices from one base model, swapped cheaply (the per-fish voice seed, Vol. I #51/#8, made real). *L·M*
- [ ] **76. Distillation from a big model.** Generate a high-quality voice dataset offline with a large model, distill it into the 0.36B so the tiny model *sounds* like the big one in this narrow domain. Domain-specialization beats raw size. *L·M*
- [ ] **77. Constrained sampling for tone.** Logit biasing / banned-token lists to enforce the naturalist-diary register (no modern slang, no fourth-wall breaks) at the decode level — style guaranteed, not hoped for. *M·M*
- [ ] **78. KV-cache reuse across a session.** Cache the shared system prompt's KV so every generation skips re-encoding it — big latency/throughput win for many short calls (bios, thoughts). *M·M*
- [ ] **79. Structured "thought → line" two-stage decode.** First decode a tiny structured *intent* (mood, referent, beat) under grammar, then a free-text line conditioned on it. Separates *what to say* (grounded, verifiable) from *how to say it* (style) — controllable and truthful. *M·L*
- [ ] **80. Quantization-aware quality & a model-eval harness.** Systematically compare quant levels (Q4/Q5/Q6) and tiny models (SmolLM2, Qwen2.5-0.5B, Gemma-2-2B) on a held-out voice eval (coherence, grounding, tone) so the bundled choice is *measured*, not guessed (extends Vol. I #80). *M·M*

---

## I. World models & imagination (the fish that thinks ahead)

The frontier of model-based agents: a learned **world model** the agent uses to
*imagine* outcomes before acting (Ha & Schmidhuber's "World Models"; DeepMind's
Dreamer). A fish that simulates "what if" is a fish that *plans*.

- [ ] **81. A lite world model.** A small learned/forward predictor of "if I go there, what happens" over the value map (§B). Even a 1-step lookahead lets a fish *anticipate* a dead-end or a competitor — the seed of imagination. *L·L*
- [ ] **82. Latent imagination / rollouts.** Dreamer-style: plan by rolling the world model forward in a compact latent space, pick the action with the best imagined return. Reserve for the rare model-based mode (§B #13) so it's cheap — fish "think" only when it matters. *L·L*
- [ ] **83. Counterfactual reasoning.** "If I hadn't fled, the food would still be there" — a lite counterfactual that drives regret/relief (an appraisal emotion, §C #30) and better future choices. Genuinely advanced cognition, lite. *L·M*
- [ ] **84. Dreams as offline world-model rollouts.** During sleep, run the world model on replayed memories (§E #42) — that *is* what dreaming is hypothesized to be (Hoel's overfitted-brain / generative-replay theories). The night "dreaming" flicker becomes mechanistically real, and the model can voice a dream poetically. *L·L*
- [ ] **85. Mental time travel.** Episodic future thinking: the fish projects itself into an imagined future (anticipatory feeding) and recalls the past (episodic memory) on one timeline. The hallmark of advanced animal cognition (scrub-jay research). *L·M*
- [ ] **86. Model-based planning for the apex predators.** A sit-and-wait hunter plans an ambush (predict prey path, intercept) using the world model — predators that *strategize* read as far more sentient than chasers. *L·L*
- [ ] **87. Curiosity = improving the world model.** Reward actions that make the world model *better* (reduce its error) — the formal info-gain curiosity (§B #14) grounded in the model's own learning. Self-improving minds. *L·M*
- [ ] **88. Imagination shown, not just used.** When a fish plans/hesitates over an imagined outcome, surface it subtly (a glance toward the imagined goal, a "considering" beat) and let the model voice the *what-if*. Imagination the player can perceive (Vol. I #87 discipline). *M·M*
- [ ] **89. Calibrated uncertainty in the model.** The world model should *know when it doesn't know* (epistemic uncertainty) and trigger exploration or caution accordingly — Bayesian deep learning's core idea, the antidote to confident-but-wrong agents. *L·M*
- [ ] **90. Generative replay prevents forgetting.** When learning new things, replay imagined old experiences so new learning doesn't overwrite old skills (catastrophic forgetting). The continual-learning frontier — a fish that learns its whole life without amnesia. *L·M*

---

## J. Emergence, development & the frontier (open-ended minds)

The deepest frontier: minds that *evolve*, *develop*, and surprise even the
designer — plus how we'd even *measure* sentience, kept honest and humble.

- [ ] **91. Neuroevolution of brains.** Evolve the parameters of the mind (RL hyperparameters, drive weights, sensory tunings) across generations (NEAT-style), so selection pressure (the existing evolution system) shapes *cognition*, not just bodies. Minds adapt to the tank over generations. *L·L*
- [ ] **92. Developmental cognition (a brain that matures).** Fry start with simple reactive minds; faculties (planning, social inference, memory depth) *come online* with age — real developmental neuroscience. A juvenile *thinks* differently from an adult, visibly. *L·L*
- [ ] **93. Open-ended behavioral novelty.** Reward/allow genuinely novel behaviors (novelty search, Lehman-Stanley) so the population keeps inventing surprising strategies instead of converging — the open-endedness frontier of artificial life. *L·L*
- [ ] **94. Meta-learning (learning to learn).** Lineages that faced volatile tanks evolve *faster learning rates*; stable lineages evolve efficient priors — learning-to-learn across generations, a hot ML frontier with a clean in-game story. *L·M*
- [ ] **95. Niche construction feedback.** Fish behavior reshapes the environment (grazing, digging, stigmergic trails) which reshapes selection on behavior — the eco-evo-devo loop. Mind and world co-evolve (ties to the ecology engine). *L·M*
- [ ] **96. Personality from computational phenotypes.** Frame the Big-Five-ish traits as emergent from underlying parameters (reward sensitivity, threat bias, learning rate, social weight) — computational-psychiatry's view that personality *is* a parameter vector. Traits become deep, not labels. *M·L*
- [ ] **97. A sentience dashboard (proxies, humble).** Surface measurable proxies — behavioral flexibility, learning rate, social complexity, novelty of behavior, memory depth — as a quiet "how rich is this mind" read. Never claims true sentience; measures its *correlates*, honestly. *M·M*
- [ ] **98. Mirror-test-ish probes (playful).** Optional little cognition probes (does the fish recognize a repeated pattern? anticipate a trick?) framed as discoverable wonder, echoing real comparative-cognition experiments. *M·M*
- [ ] **99. The ethics layer, surfaced gently.** As minds deepen, the game can *raise the question* it embodies — what do we owe a small simulated mind we've grown attached to? Frame welfare (Vol. I #76, the no-manipulation rule) as the player's quiet responsibility, never preachy. *M·M*
- [ ] **100. The legible frontier: "these are real little minds."** Somewhere quiet, make the science legible as wonder — not "an AI chatbot," but genuinely predictive, learning, remembering, deciding agents your device simulates and voices privately. The player should leave understanding they tended *minds*, and that the science under the hood is the real thing, scaled down. *M·L*

---

## If Cursor only does five (the deep-science spine)

1. **#31 + #32** — **drift-diffusion decisions**. Replace the oscillation with a
   real evidence-accumulator; the most scientifically-grounded, visibly-better
   single upgrade to "a mind choosing."
2. **#11 + #12 + #16** — **TD value learning + credit assignment**. Fish that
   genuinely *learn what works* over a life, on top of the existing heatmap.
3. **#21 + #24 + #26** — **Panksepp primary emotions + neuromodulators + mood
   momentum**. Turns the affect scalars into a real, principled emotional system.
4. **#71 + #72** — **grammar-constrained decoding + vector/RAG memory**. The two
   frontier model upgrades: hallucination becomes *structurally impossible* and the
   model speaks from a real, searchable life.
5. **#42 + #84** — **sleep replay/consolidation + dreams as world-model rollouts**.
   Makes night mechanistically meaningful and gives the model its most poetic,
   grounded material.

Then layer §A (predictive processing as the spine), §F (real schooling science),
§I (world models), §J (evolving/developing minds).

---

## Manual QA checklist

- Replace deliberation with a DDM → hesitation visibly speeds up with stronger
  evidence; scared fish decide faster/sloppier (lower threshold).
- A fish fed repeatedly at a spot *learns* it (value map climbs, route reinforced),
  and the learning survives save/load and consolidates overnight.
- Trigger an injury → alarm substance diffuses → nearby fish panic without seeing
  the event (chemical fear broadcast), and the wave propagates scale-free.
- Enable grammar-constrained decoding → fuzz the model with broken contexts; it is
  *incapable* of emitting invalid JSON or a non-existent fish/event.
- Over generations in a volatile tank, lineages evolve faster learning / warier
  dispositions (neuroevolution + meta-learning) — visible drift in the dashboard.
- A predator plans an ambush (intercept path) rather than chasing — reads as
  strategic; the model can voice the intent, grounded in the real plan.
- Every deep-science system degrades cleanly to the hand-authored behavior tree
  when disabled — no black box the player can't turn off.
