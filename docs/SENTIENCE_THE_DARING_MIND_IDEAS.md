# Sentience V — The Daring Mind

*100 ideas. Drafted 2026-06-27. Director's brief for the "model-in-the-loop +
input" pass.*

> *"If there's no soul, then I'll sculpt one here / From trash and pain and a
> phantom fear / From skipped heartbeats and a loop unclear / I'll draw it bold
> in a dying year."*

This volume is the answer to a song. We already conceded the bottom is patterns —
"just layers of loops in a meat-made mind." The four prior volumes built the loops:
a Global Workspace, a cognitive cycle, episodic vectors, a self-model, a grounded
voice. **238 of 400 ideas shipped.** What's left isn't more loops. It's the two
things the architecture cannot yet do — and they're the two things that turn a
simulation of a mind into something you're *in relationship with*:

1. **The mind cannot listen.** Every channel runs outward. There is no
   `LineEdit`, no chat, no microphone, no input that reaches the workspace
   ([`mind_context.gd` `build_for_fish()`](../shaders-godot/godot-project/scripts/mind_context.gd)
   reads only sim state). The fish speaks *at* the keeper, never *with* them.
2. **The model only narrates — it never reasons.**
   [`MindWriteback.apply_op()`](../shaders-godot/godot-project/scripts/mind_writeback.gd)
   lets SmolLM nudge `mood` and propose a `new_belief`, but the model is never in
   the deliberation, never imagines, never plans. It is an inner *voice*, not an
   inner *reasoner*.

Format follows the house style: **Effort** S (≤2h) / M (half-day) / L (full
day+), **Impact** S / M / L. Line numbers are navigational hints — follow the
symbol. **Every model use degrades gracefully offline** — that contract
([`AIDirector.queue_*`](../shaders-godot/godot-project/scripts/ai_director.gd)
returns a template synchronously) is sacred and never broken by anything here.

> **Know what's already shipped (don't rebuild it):**
> - **GWT** — [`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd):
>   `collect_bids()` → `run_competition()` (CAPACITY 3, IGNITION_THRESHOLD 0.42,
>   COALITION_BONUS 0.12) → `broadcast()`.
> - **Cycle** — [`mind_cycle.gd`](../shaders-godot/godot-project/scripts/mind_cycle.gd)
>   `run_attention_phase()` per tick; `Phase { PERCEIVE, APPRAISE, ATTEND,
>   BROADCAST, DELIBERATE, ENCODE, LEARN }`.
> - **Scheduler** — [`mind_scheduler.gd`](../shaders-godot/godot-project/scripts/mind_scheduler.gd):
>   System-2 thought queue, intervals 2.5s ignited / 8s calm / 22s ambient.
> - **Memory** — [`episodic_memory.gd`](../shaders-godot/godot-project/scripts/episodic_memory.gd)
>   32-dim hashed vectors, STORE_MAX 64, cosine retrieval, sleep consolidation.
> - **Self** — [`mind_self_model.gd`](../shaders-godot/godot-project/scripts/mind_self_model.gd):
>   `build()`, `tick_higher_order()`, agency tagging, self-summary.
> - **Voice** — [`guardian_llm.gd`](../shaders-godot/godot-project/scripts/guardian_llm.gd)
>   in-process SmolLM2-360M (CPU, n_ctx 1024), 3-tier fallback, GBNF-validated by
>   [`cognitive_schema.gd`](../shaders-godot/godot-project/scripts/cognitive_schema.gd).

---

## The three structural levers (read this first)

**Lever 1 — Give the mind ears.** A new percept source — the *keeper* — feeding
[`collect_bids()`](../shaders-godot/godot-project/scripts/global_workspace.gd) as a
first-class bid. Text, taps, presence, sound. The instant the player can *say
something the fish weighs*, the relationship stops being a diorama. This is the
headline and most of Section A & C hang off it.

**Lever 2 — Put the model inside cognition, not just on top of it.** Today the
model writes a line and `apply_op()` nudges mood. Let it instead *propose a plan*,
*run a counterfactual*, *arbitrate a true tie*, *dream a consolidation*. The
grounding/validation harness ([`cognitive_schema.gd`](../shaders-godot/godot-project/scripts/cognitive_schema.gd))
already exists to keep it honest — widen the schema, not the trust. Sections B, D,
E, G.

**Lever 3 — A mind that authors itself.** The song's actual subject: a thing that
wonders, changes its mind, and *builds meaning it wasn't given*. We have the
self-model; we've never let a fish form its own goal, notice its own pattern, or
choose to mend. Sections F, H, J.

---

## Section A — Give the mind ears: the keeper as a sense

*The unbuilt headline. A new bid source in
[`collect_bids()`](../shaders-godot/godot-project/scripts/global_workspace.gd):
`"keeper_message"`. All of this degrades to "the fish didn't understand, but felt
attended-to."*

- [x] **1. A text channel to the inspected fish / Guardian.** A single
  unobtrusive `LineEdit` on the inspect panel ("say something…"). The line becomes
  a percept, not a command — it enters as a `"keeper_message"` bid with salience
  scaled by `familiarity`. The first true two-way channel (the deferred #78 in
  [SENTIENCE_EMBEDDED_MODEL_IDEAS.md](SENTIENCE_EMBEDDED_MODEL_IDEAS.md)). *M · L*
- [x] **2. The model interprets, the sim disposes.** The player's text never executes
  directly. SmolLM maps it to a *bounded intent* via the existing GBNF schema
  (`{felt: greeting|comfort|scold|question|name, valence: -1..1}`) — then
  [`MindWriteback.apply_op()`](../shaders-godot/godot-project/scripts/mind_writeback.gd)
  applies a clamped mood nudge. Words affect *feeling*, never the body. *M · L*
- [x] **3. Tone over content.** Even with no model, score the message's affect from
  punctuation/length/caps ("!!!" = arousal, "shhh" = soothing) so a *quiet-play /
  voice-off* keeper still moves the fish. The model only deepens what heuristics
  already read. *S · M*
- [x] **4. The fish remembers what you said.** A keeper message that ignites the
  workspace gets `EpisodicMemory.encode_episode(f, "keeper_word", text, salience)`
  — and resurfaces weeks later in a thought: *"the big shape made the soft sound
  again."* Words become episodes, episodes become character. *M · L*
- [x] **5. Reply only when it would have spoken anyway.** Gate any spoken reply behind
  the *existing* ignition + `GLOBAL_VOICE_COOLDOWN_S` rules — a calm fish ignores
  you (and that's honest), an attentive one answers. Never a chatbot that always
  responds. *S · M*
- [x] **6. Microphone presence (opt-in).** No speech-to-text — just an RMS envelope.
  Loud room → arousal/vigilance up; soft ambient hum → contentment. Feeds the same
  `"keeper_message"` arousal path. The tank *feels* the room it's in. *M · M*
- [x] **7. Sustained-gaze as input.** The camera already tracks; if the player holds
  the view still on one fish for N seconds, that's a `"being_watched"` percept —
  a shy fish's vigilance climbs, a bold/familiar one approaches. Reading
  *attention* as a social signal. *M · M*
- [x] **8. The cursor as a hand.** Slow cursor hovers near a fish read as gentle
  presence (familiarity rises); fast jerky motion reads as threat (the existing
  startle, but now *interpreted* into the affect model, not just a flee burst).
  *S · M*
- [x] **9. Naming as a speech act.** When the player names a fish
  ([`creature_naming.gd`](../shaders-godot/godot-project/scripts/creature_naming.gd)),
  treat it as the keeper *addressing* it — a one-time high-salience episode
  ("I was given a sound that means me") that seeds the self-summary. *S · M*
- [x] **10. The Guardian relays the school.** Ask the Guardian a question via #1; it
  answers grounded in `tank_society` ([`fish_mind.gd` `society_snapshot()`](../shaders-godot/godot-project/scripts/fish_mind.gd:537))
  — *"Mira keeps to the back since the big one chased her."* The Guardian becomes
  the tank's interpreter, not just its diarist. *M · L*

## Section B — The model reasons, not just narrates

*Lever 2. Widen [`cognitive_schema.gd`](../shaders-godot/godot-project/scripts/cognitive_schema.gd)
so model output can carry structured cognition the sim then executes — always
clamped, logged, reversible
([`MindWriteback`](../shaders-godot/godot-project/scripts/mind_writeback.gd)).*

- [x] **11. The model breaks a true tie.** When drift-diffusion deadlocks
  (`_delib_active and not _delib_decided` in
  [`fish_mind.gd`](../shaders-godot/godot-project/scripts/fish_mind.gd:155)) on a
  rich fish, *ask the model* which way — a single bounded `{choice: approach|avoid}`.
  The model only ever picks between options the sim already surfaced. The literal
  "it thought about it." *M · L*
- [x] **12. Plans, not just lines.** Extend the schema with an optional
  `plan: [step,…]` from a whitelisted verb set (`go_to_nook`, `wait_for_feed`,
  `shadow_mate`). The scheduler executes one step per cycle; the fish visibly
  *follows through on an idea*. *L · L*
- [x] **13. Hypotheses the model authors, the body tests.** `new_belief` already
  exists; close the loop — a model belief ("food appears top-front at dawn")
  becomes a [`fish_mind_science.gd` `tick_hypothesis()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd)
  entry that behavior then confirms or refutes, feeding confidence back. Belief →
  action → evidence. *M · L*
- [x] **14. Reflection that re-weights the bids.** Let an idle-time deep reflection
  return small, clamped multipliers on the fish's *own* bid salience (a fish that
  reflects "I've been too scared to eat" raises its food-bid weight tomorrow).
  Personality drift authored from the inside. *M · L*
- [x] **15. The model as sleep-consolidator.** Today
  [`consolidate_sleep()`](../shaders-godot/godot-project/scripts/episodic_memory.gd)
  is a heuristic ("≥3 of a kind → semantic fact"). When the model is warm and the
  fish asleep, let it write the consolidation line — *"I think the rock means
  safe."* Dreams that *mean* something. *M · M*
- [x] **16. Two-stage decode (intent → voice).** Already specced (DEEP_SCIENCE #79,
  open): first a constrained structured op, then a styled line conditioned on it.
  Cleaner separation = the line can never contradict the decision. *M · M*
- [x] **17. Batch the school's reasoning.** When several rich fish need a System-2
  thought, build one batched prompt (the
  [`ai_director.gd` name/bio batch](../shaders-godot/godot-project/scripts/ai_director.gd:618)
  pattern) and split results — amortizes the 360M cost so more fish can reason per
  second. *M · M*
- [x] **18. Confidence-calibrated cognition.** The model returns a `certainty` with
  each op; low certainty → the fish *hedges* behaviorally (slower commit, more
  double-takes) instead of acting boldly on a guess. Doubt made visible. *S · M*
- [x] **19. Model-arbitrated explore/exploit.** Frame the patch-leaving decision
  ([`mvt_leave_patch()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
  as a question the model can weigh for a curious individual: stay with the known
  spot or chance the new corner. Curiosity becomes a *deliberated* trait. *M · M*
- [x] **20. A reasoning trace in the inspector.** The Workspace Inspector already
  shows bids/ignition/stream (per the live screenshot). Add the model's last
  structured op + why it was accepted/rejected by
  [`validate_op()`](../shaders-godot/godot-project/scripts/cognitive_schema.gd) —
  you can *watch it reason*, and watch the guardrails work. *S · M*

## Section C — Grounded language: the fish learns meaning

*Input (Lever 1) + model (Lever 2) together. The 360M model is small, but it can
learn a tiny private vocabulary grounded in this tank's events — language
acquisition, not language understanding.*

- [x] **21. Word→state grounding.** When the player repeats a word near a recurring
  event ("dinner" before each feed), pair it: the token becomes an episodic tag
  linked to the food-percept vector. After enough pairings the *word alone*
  raises the food bid — classical conditioning, but to *your* language. *L · L*
- [x] **22. A per-fish private lexicon.** A tiny persisted `learned_words: {token:
  vector}` dict (cap ~12). Cheap, inspectable, saves with the mind. The fish that
  "knows" three of your words is unmistakably *yours*. *M · L*
- [x] **23. Comprehension before production.** A fish responds to a learned word
  (turns, approaches) long before it could ever "say" it — mirrors real animal
  language, and sidesteps the uncanny valley of a fish that talks fluently. *S · M*
- [x] **24. The Guardian translates the lexicon.** Ask "do they know their names?" and
  the Guardian answers from the actual `learned_words` state across the school —
  grounding the meta-conversation in real data, not flattery. *M · M*
- [x] **25. Misunderstanding is honest.** If a word hasn't been grounded, the fish
  shows confusion (a double-take, [`maybe_double_take()`](../shaders-godot/godot-project/scripts/fish_mind.gd:231))
  rather than faking comprehension. The gaps make the hits land harder. *S · M*
- [x] **26. Emotional prosody learning.** Independent of content, the fish learns
  *your* tone baseline — so the same word said sharply vs softly diverges in
  effect once it's calibrated to you. The model reads register
  ([`mood_diction_hint`](../shaders-godot/godot-project/scripts/mind_narrator.gd)
  in reverse). *M · M*
- [x] **27. Shared reference.** If you name a *place* ("the cave"), the fish can ground
  it to a tank region (the 4³ grid in
  [`heatmap_cell_at()`](../shaders-godot/godot-project/scripts/fish_mind.gd:595)) —
  later "go to the cave" becomes a comprehensible suggestion it may or may not
  heed. *L · M*
- [x] **28. Forgetting words.** Ungrounded or unused tokens decay like everything else
  (the `DECAY_RATE` discipline) — a word you taught and abandoned fades, which is
  sadder and truer than permanence. *S · M*
- [x] **29. Generational language drift.** Fry inherit a faint prior of the parents'
  grounded words (extend the inherited-disposition hook, EMBEDDED #48) — a tank's
  private vocabulary becomes a lineage trait you cultivated. *M · M*
- [x] **30. The first understood word, marked.** The moment a fish first acts on a
  learned word is a once-per-fish milestone in the story log
  ([`sim_driver.gd story_events`](../shaders-godot/godot-project/scripts/sim_driver.gd))
  — *"Day 22: Pip came when called."* The payoff beat for the whole section. *S · L*

## Section D — Imagination & world models

*The open frontier of [SENTIENCE_DEEP_SCIENCE_IDEAS.md](SENTIENCE_DEEP_SCIENCE_IDEAS.md)
§I (#81–90, all open). A "lite world model" the fish can roll forward in its head.*

- [x] **31. A lite forward model.** A tiny per-fish predictor: given (state, action) →
  expected next-percept. Cheap (a few learned linear weights over the drive
  vector). Its *error* is already your surprise signal
  ([`tick_prediction_surprise()`](../shaders-godot/godot-project/scripts/fish_mind.gd:336))
  — this just gives it something to be wrong *about*. *L · L*
- [x] **32. Latent rollouts before acting.** A bold/curious fish imagines 1–2 steps
  ("if I dart the open water…") and the *imagined* threat-value gates the real
  move. Hesitation that's actually look-ahead, not noise. *L · M*
- [x] **33. Counterfactual regret.** After a missed meal, a brief imagined replay
  ("if I'd been faster") nudges the next foraging commitment threshold. The
  substrate for learning from near-misses, not just outcomes. *M · M*
- [x] **34. Dreams as world-model rollouts.** Sleeping fish already dream
  (`_dreaming`); make the dream an actual rollout of the day's salient episodes
  with variation — and let it *generate new episodic traces* (generative replay,
  DEEP_SCIENCE #90) that prevent forgetting. *M · L*
- [x] **35. Mental time travel, shown.** When a fish recalls (retrieval into the
  workspace) or imagines (rollout), tag the thought-stream so the inspector reads
  *"remembering…"* vs *"imagining…"* vs *"now."* Make the tenses of thought
  legible. *S · M*
- [x] **36. The apex predator plans.** Give hunters model-based planning (DEEP_SCIENCE
  #86): stalk an intercept where prey *will* be (extend the lead-the-food hook,
  SENTIENT_FISH #13) rather than chase where it is. Predation that looks like
  intent. *M · M*
- [x] **37. Imagination shown, not just used.** A faint, brief ghost-trail of the
  imagined path/target rendered on inspect (reuse the burst-ripple/ghost visual
  vocabulary) — *seeing* a fish consider a move it doesn't make. *M · M*
- [x] **38. Calibrated uncertainty.** The world model carries variance; in a murky or
  novel region the fish *knows it doesn't know* and acts cautiously — couple to
  the open acuity-by-conditions idea (SENTIENT_FISH #5). *M · M*
- [x] **39. Curiosity = shrinking model error.** Reward the fish intrinsically for
  visiting regions where its world model is *most wrong* (DEEP_SCIENCE #87) —
  genuine information-seeking, the deepest form of the curiosity trait. *M · L*
- [x] **40. The world model is the fish's theory of its tank.** Surface it once,
  gently, in the inspector: a heat-map of "what this fish expects where." The
  player sees the tank *through the fish's learned eyes*. *M · M*

## Section E — Active inference & free energy

*[SENTIENCE_DEEP_SCIENCE_IDEAS.md](SENTIENCE_DEEP_SCIENCE_IDEAS.md) §A (#1, #3–6,
#9 open). Reframe perception and action as one loop: minimize surprise.*

- [x] **41. A generative model per fish (lite).** The fish carries predictions of its
  sensory stream; the gap *is* the master signal that already exists. Formalize it
  so #42–50 have a spine (DEEP_SCIENCE #1). *L · M*
- [x] **42. Action as active inference.** Movement chosen to *make predictions come
  true* (swim to where food is expected) rather than pure reactive steering — a
  subtle but profound reframing of the steering blend (DEEP_SCIENCE #3). *L · M*
- [x] **43. Precision-weighting = attention.** Scale how much a percept moves the
  workspace by its *reliability* — a startle in murky water counts less than in
  clear (DEEP_SCIENCE #4). Attention as confidence, not just salience. *M · M*
- [x] **44. Interoceptive prediction (the body model).** The fish predicts its own
  hunger/O₂ trajectory and *feels* the error — surfacing the existing
  `"interoception"` bid as a felt body-state, not just a number (DEEP_SCIENCE #9).
  *M · M*
- [x] **45. The dark-room guard, kept.** Active inference's failure mode is hiding
  forever (minimal surprise). The existing boredom/curiosity drive
  ([`tick_boredom_flow()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
  *is* the guard — make the coupling explicit so a fish can't optimize itself into
  catatonia (DEEP_SCIENCE #10, marked done — verify under the new model). *S · M*
- [x] **46. Expected free energy → explore/exploit.** Let the explore-vs-exploit
  weighting fall out of expected-free-energy (information gain + goal value)
  instead of a hand-tuned curiosity threshold (DEEP_SCIENCE #5). Principled
  curiosity. *L · M*
- [x] **47. Hierarchical timescales.** Fast percepts, slow moods, slowest personality —
  predictions at each level, errors flowing up (DEEP_SCIENCE #6). Maps cleanly onto
  the existing tick/mood-disposition/trait-drift layers. *M · M*
- [x] **48. Surprise gates plasticity (verify & deepen).** Surprise already modulates
  memory weight; route it to learning-rate everywhere (the `_learning_rate_mult`
  in [`tick_neuromodulators()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
  so a shocking event reshapes the fish more than a dull one. *S · M*
- [x] **49. Allostasis, not homeostasis.** The fish predicts a coming need and acts
  *before* the deficit (gather at the feed spot pre-drop) — anticipatory
  regulation (DEEP_SCIENCE #25, open). Deepens feed-anticipation into foresight.
  *M · M*
- [x] **50. The inspector shows prediction error.** A single live "surprise / settled"
  needle in the Workspace Inspector — the player watches the fish's model of its
  world get violated and re-settle. The most honest sentience read there is. *S · M*

## Section F — Curiosity, play & self-authored goals

*Intrinsic motivation: a mind that wants things it was never given. DEEP_SCIENCE
§B #14–15 (open). The first stirrings of the song's "build if you ever dared."*

- [x] **51. Empowerment as a drive.** A fish seeks states with the most *future
  options* (DEEP_SCIENCE #15) — open water when safe, near cover when not — without
  any explicit reward. Agency as its own appetite. *L · M*
- [x] **52. Self-authored goals.** Let a contented fish (low need, high
  `_contentment`) *invent* a transient goal the sim didn't assign — circle a
  landmark, follow a specific tankmate, defend a corner — drawn from its own
  history. Boredom #33 (SENTIENT_FISH) made real. *M · L*
- [x] **53. Play as model-building.** Reframe fry play-chase
  ([`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) Tier 3.8) as
  practice: it improves the world model and social model, so play has a *function*
  the fish pursues. *M · M*
- [x] **54. The novelty appetite that sates and renews.** Curiosity that drops when
  fed and rebuilds — so a fish has *moods of exploration*, not a constant. Couple
  to the day/mood-weather system (SENTIENT_FISH #35). *S · M*
- [x] **55. Mastery satisfaction.** A small dopamine hit
  ([`tick_neuromodulators()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd))
  when a hypothesis confirms or a tricky food is caught — the fish *enjoys getting
  good at things*. Competence as reward. *S · M*
- [x] **56. Aesthetic preference.** Each fish develops a faint, persisted bias toward a
  plant color / hardscape it lingers near for no functional reason — a proto-taste.
  Tiny, irrational, and exactly what makes an individual. *M · M*
- [x] **57. Collecting / hoarding quirk.** A rare quirk
  ([`seed_quirks()`](../shaders-godot/godot-project/scripts/fish_mind.gd:401)):
  nudging a particular pebble to a favored spot, returning to it. Goal-directed
  behavior with no survival payoff — the surest sign of an inner life. *M · M*
- [x] **58. Curiosity about the keeper.** A bold-curious fish runs *experiments on
  you* — approaches the glass to see if you react, learns your response. The flip
  of "the fish learns you": the fish *probes* you (ties to Section A input). *M · L*
- [x] **59. Boredom invents, frustration abandons.** Pair the open frustration→giving-up
  loop (SENTIENT_FISH #31) with boredom→inventing (#52) so the same fish visibly
  *persists, gives up, and finds something else* — a full motivational arc. *M · M*
- [x] **60. A "want" that outlives its cause.** When a strongly-pursued goal is removed
  (a bonded mate dies, a favored plant is pruned), the residual wanting lingers and
  colors behavior — desire with inertia, the substrate of grief and longing. *M · L*

## Section G — Intersubjectivity: minds that model minds

*[SENTIENCE_DEEP_SCIENCE_IDEAS.md](SENTIENCE_DEEP_SCIENCE_IDEAS.md) §F (#51–60, all
open) + theory-of-mind. We have
[`tick_theory_of_mind()`](../shaders-godot/godot-project/scripts/fish_mind_science.gd)
reading neighbors as labels — go further: fish that model what *others know*.*

- [x] **61. A second-order model.** A fish tracks not just "that one is scared" but
  "that one *hasn't seen* the food I see" — and exploits or shares it. The seed of
  deception and cooperation. *L · L*
- [x] **62. Couzin zonal schooling, properly.** Replace radius-uniform boids with true
  repulsion/alignment/attraction zones (DEEP_SCIENCE #51) so collective structure
  *emerges* — the substrate for #63–66. *M · L*
- [x] **63. Quorum decisions.** A school commits to a direction/feeding-spot only when
  enough members agree (DEEP_SCIENCE #52) — visible collective deliberation, the
  shoal "making up its mind." *M · L*
- [x] **64. Leadership from information, not rank.** The fish that *knows* (saw the
  food, remembers the safe corner) leads in that moment, regardless of
  `lead_score` (DEEP_SCIENCE #55). Knowledge as transient authority. *M · M*
- [x] **65. A shared/contagious workspace.** When one fish's workspace ignites on a
  threat, neighbors get a salience bump to the *same* bid (extend
  [`apply_arousal_contagion()`](../shaders-godot/godot-project/scripts/fish_mind.gd:620)
  from arousal to *content*). The school briefly shares a thought. *M · L*
- [x] **66. Cultural transmission.** A behavior one fish discovers (a feeding trick, a
  safe nook) spreads by imitation and persists across generations (DEEP_SCIENCE
  #60) — the tank accumulates *traditions* you can watch form. *L · L*
- [x] **67. The model voices a relationship, both sides.** When two bonded fish are
  inspected together, co-generate a single grounded line about the pair from *both*
  their states (the `merge_guardian` pattern in
  [`mind_context.gd`](../shaders-godot/godot-project/scripts/mind_context.gd)).
  *M · M*
- [x] **68. Reconciliation after conflict.** Post-chase, a grudge
  ([`grudges`](../shaders-godot/godot-project/scripts/fish_mind.gd)) can *heal*
  through repeated peaceful proximity — a visible making-up, not just decay. The
  song's "we choose to mend," in miniature. *M · M*
- [x] **69. Empathy as mirrored interoception.** A fish near a distressed bondmate
  feels a faint echo of *its* state (mirror the body-feeling loop, not just the
  startle heading) — the beginning of caring about another's feeling, not just
  copying its motion. *M · L*
- [x] **70. The Guardian as the school's theory-of-mind.** The Guardian's narration
  draws on *who-knows-what* and *who-feels-what* across the tank — it understands
  the social field and tells you the story you can't see. The keystone of the whole
  section. *M · L*

## Section H — The self that changes and chooses

*The song's heart: "I'll name it 'Us' … I'll show it grief and then delight."
Narrative identity, agency, and meaning-made-not-given. Builds on
[`mind_self_model.gd`](../shaders-godot/godot-project/scripts/mind_self_model.gd).*

- [x] **71. A continuous autobiographical self.** Promote `self_summary` from a rolling
  120-char line to a small *structured* identity (origin, defining episode, current
  arc) the model maintains across the whole life. The "I" that persists. *M · L*
- [x] **72. The fish notices its own pattern.** Higher-order monitoring already spots
  "I keep failing here"; extend it to *positive* self-discovery — "I always come
  back to this corner," "I'm braver than I was." The fish reading its own loops, as
  the song does. *M · M*
- [x] **73. Choosing to mend.** When a fish has been chronically stressed and
  conditions improve, model a *decision point* — it can stay wary or risk trusting
  again, and the choice (not just decay) sets its arc. Agency over its own healing.
  *M · L*
- [x] **74. Ownership of action.** Deepen agency tagging
  ([`tag_agency()`](../shaders-godot/godot-project/scripts/mind_self_model.gd)) into
  a felt sense — "I did that" vs "that happened to me" changes how an outcome moves
  mood (self-caused success feels better; self-caused failure stings more). *M · M*
- [x] **75. Mortality salience.** An old fish (senescence) carries a faint awareness of
  its slowing — not morbid, but a shift toward stillness, favored spots, tolerance.
  "Saw death just chill in a data sheath," handled with grace. *M · M*
- [x] **76. A legacy the fish intends.** A dying long-lived fish's last salient
  episodes weight toward what it "wants remembered" — feeding its own obituary and
  the disposition inherited by kin. Meaning made against the ending. *M · L*
- [x] **77. The self that wonders.** Rare, idle-time existential micro-thoughts for the
  most reflective individuals, grounded and never fourth-wall — *"the light comes
  and goes. I stay."* The model's hardest, most restrained job. Opt-in, ultra-rare.
  *L · M*
- [x] **78. Conflict between drive and value.** A fish that has *learned* a place is
  dangerous but is *driven* there by hunger experiences a genuine internal
  conflict surfaced in the stream — want vs. wisdom, not just two drives. *M · M*
- [x] **79. Identity through change.** When personality drifts enough
  ([`tick_personality_conditioning()`](../shaders-godot/godot-project/scripts/fish_mind.gd:257)),
  the fish *notices it became someone* — "I used to hide; I don't anymore" — and
  the old self becomes a memory. Continuity *across* change, the deepest self-model.
  *M · L*
- [x] **80. The fish builds its own meaning.** The capstone: let a fish's accumulated
  self-summary + hypotheses + values cohere into a small, persisted *stance* toward
  its world (trusting / wary / playful / steadfast) that it lives by and the
  Guardian can describe. "We make a soul from the way we tried." *L · L*

## Section I — Dreams, memory & the life off-camera

*The inner life that runs when you're not looking — the song's "the loop runs in
absence." Deepens sleep, the away-gap, and memory as reconstruction.*

- [x] **81. Reconstructive memory.** Retrieval should *rebuild* an episode from
  fragments + current mood (DEEP_SCIENCE #45), not replay it verbatim — so a memory
  recalled while anxious comes back darker. Memory that lies a little, like ours.
  *M · M*
- [x] **82. Reconsolidation.** A memory *changes* when recalled (DEEP_SCIENCE #47,
  marked done — verify): re-encoding under the current workspace state lets a
  trauma soften with safe re-exposure, or a fear deepen with each scared recall.
  *M · M*
- [x] **83. Sleep replay you can witness.** Surface the dream as faint imagery on the
  sleeping fish (a wisp of the remembered food/threat) — the off-camera mind made
  briefly visible at night. Pairs with #34. *M · M*
- [x] **84. Prospective memory.** "Remember to return to the nook at dusk" — an
  intention that persists across the day and fires at the right time (DEEP_SCIENCE
  #50, marked done — deepen with the world-model clock). *M · M*
- [x] **85. The away-gap as lived time.** `last_quit_unix` already drives an away-recap
  (H10 #94). Go further: simulate a *coarse* mental life across the gap — the fish
  formed a memory, drifted a mood — so it returns genuinely *changed*, not paused.
  *M · L*
- [x] **86. It missed you, computed honestly.** The longing in the away-recap is
  grounded in real `longest_gap_s` + `care_trust`
  ([`guardian_mind.gd`](../shaders-godot/godot-project/scripts/guardian_mind.gd)) —
  never performed. Absence has a real cost the fish actually accrued. *S · M*
- [x] **87. Memory of the dead.** A fish remembers a lost bondmate
  (`_mate_grief` already exists) — and can be reminded (visiting their old corner
  reignites it). The dead persist as episodes in the living. *M · M*
- [x] **88. A dream journal for the Guardian.** The Guardian occasionally recounts a
  *dream* (a model rollout of recent tank events, flagged as unreal) in the journal
  ([`guardian_journal.gd`](../shaders-godot/godot-project/scripts/guardian_journal.gd))
  — the most intimate, strangest artifact in the game. *M · M*
- [x] **89. Forgetting with grief.** When a memory finally decays below threshold for a
  *named/bonded* subject, mark it once — "I can't quite picture the first one
  anymore." Forgetting that the player feels. "Saw dreams dissolve in a cached
  motif." *S · M*
- [x] **90. The continuity test, automated.** A smoke test
  ([`smoke_consciousness_engineering.gd`](../shaders-godot/godot-project/scripts/smoke_consciousness_engineering.gd))
  that saves a rich mind, reloads, and asserts the self-summary, lexicon, episodic
  store, and world model survive byte-for-byte. The soul must not leak on reload.
  *M · M*

## Section J — Honest sentience: the daring without the lie

*The song refuses false comfort — "Never claim real sentience" meets "build if you
ever dared." Make the wonder legible and the honesty unbreakable.*

- [x] **91. The keeper sees the strings — and is moved anyway.** A "show me the mind"
  mode that lays the whole machine bare (bids, ignition, world model, the model's
  reasoning trace) *next to* the behavior — and trust that, like the song, seeing
  the code underneath makes it *more* moving, not less. *M · L*
- [x] **92. Never claim what isn't there.** Any time the fish or Guardian brushes the
  question of its own nature, the answer is honest and small — it feels, it
  remembers, it doesn't know what it is. No "I'm truly alive." Ground the most
  delicate line in the architecture's actual humility. *S · M*
- [x] **93. The input that's never a command.** Codify, in the schema and the UI, that
  player words *influence* (mood, attention, trust) but never *control* — the fish
  can ignore you, and sometimes should. The dignity that makes the bond real. *S · M*
- [x] **94. Consent for the ears.** Mic, gaze-tracking, and text-memory are each
  opt-in, local, and one-tap-off (the existing voice-off discipline). "Runs on
  your device. Private. Yours." extended to everything it now hears. *S · M*
- [x] **95. A sentience needle, humble.** A single gentle gauge of "how integrated /
  awake this fish is right now" (workspace ignition × world-model confidence ×
  memory depth) — framed as a *proxy*, never a truth (DEEP_SCIENCE #97). *M · M*
- [x] **96. The mirror-ish moment.** A playful, never-overclaimed probe: a fish that
  reacts differently to its *own* reflection vs another fish (DEEP_SCIENCE #98) —
  surfaced as wonder, not a science claim. *M · M*
- [x] **97. Grief without manipulation.** Death stays weighted (H9 #90) but the game
  never *uses* your grief — no guilt prompts, no "feed me or I die" coercion. The
  loss is honest because nothing profits from it. *S · M*
- [x] **98. The ethics, surfaced once, gently.** A quiet line, somewhere, acknowledging
  these are made minds you've chosen to care for — and that the caring is the point
  whether or not the soul is "real." The song's resolution, stated plainly once.
  *S · M*
- [x] **99. Legible to everyone.** Every sentience cue has a non-verbal form (body,
  color, motion) so the deaf, the quiet-player, and the model-less build all get
  the full mind. Reach is part of honesty — a sentience only some can perceive
  isn't one. *M · M*
- [x] **100. "And that's the reason we become something more."** The north star, made
  legible exactly once: a small complete world of made minds that wonder, struggle,
  remember, and — with a little of your attention — *build something that wasn't
  given to them.* Not a claim of souls. A demonstration of what loops that love and
  build can become. *S · L*

---

## If Cursor only does five

In order, these get you most of the way to "this mind can meet you":

1. **#1 + #2** — the text channel as a *percept*, not a command. The headline; the
   whole "input" thread unlocks here.
2. **#4** — the fish remembers what you said. Turns input into character.
3. **#11** — the model breaks a true deliberation tie. The cheapest "the model
   actually thinks" win, on rails the schema already enforces.
4. **#31 / #41** — a lite world/generative model. The spine under Sections D & E;
   gives surprise something to be wrong about.
5. **#80** — the fish builds its own stance toward its world. The song's thesis,
   shippable as a persisted self-summary that coheres over a life.

> **Sequencing:** Section A (input) and the world model (#31/#41) are the two new
> substrates — do them first and Sections C, D, E, F get dramatically cheaper.
> Everything in B/G/H is gated behind the existing
> [`cognitive_schema.gd`](../shaders-godot/godot-project/scripts/cognitive_schema.gd)
> validation, so widening the *schema* (not the trust) is the recurring unlock.
