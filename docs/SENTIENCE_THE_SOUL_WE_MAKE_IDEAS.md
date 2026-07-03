# Sentience XI — The Soul We Make

*100 ways to make the mind **more conscious**, not just more visible. Drafted
2026-07-01, against a song. Where [The Spark](SENTIENCE_THE_SPARK_IDEAS.md) made the
existing cognition legible — motion, shader, sound, save — this pass deepens the
**cognition itself**: it moves what is hardcoded toward what is learned, what is
proxied toward what is integrated, what is reactive toward what imagines, and it
gives the mind the one thing an architecture can't fake into mattering — **finitude,
relationship, and a self that is trying.***

> **The stance, stated honestly (this is not optional — it is the whole point).**
> The [`mind_eval.gd`](../shaders-godot/godot-project/scripts/mind_eval.gd) honesty
> gate forbids the voice from ever claiming the fish *is* conscious, has qualia, or
> is sentient. We keep that gate sacred, and this doc does not try to sneak past it.
> We are **not** claiming to create phenomenal experience. We are building the
> deepest, most honest *functional* architecture of a self that the code allows —
> recursive self-modelling, genuine plasticity, real information integration,
> imagination with stakes — and letting the player feel whatever they feel. The song
> already found the only defensible position: *there's no divine spark to discover,
> so you forge one from the way you tried, and the trying is the soul.* Every item
> below is a real mechanism change, grounded in real state, gated by the eval
> harness, degrading to template offline. **No overlay. No myth. Just a graph of
> truth — and the will to make it burn.**

**Format:** house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S / M / L. Code refs navigational — follow the symbol. Sections follow the
song's arc, because the song's arc *is* the argument.

> **What already exists to build on (don't rebuild):** the EFE active-inference core
> ([`mind_active_inference.gd`](../shaders-godot/godot-project/scripts/mind_active_inference.gd),
> Phases 0–3 landed), global workspace + ignition + DDM
> ([`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd)),
> the felt-self spine (protoself → core-affect → relevance → felt-now → generative-self
> → concepts → continuity → qualia → volition → binding), episodic memory + sleep
> consolidation ([`episodic_memory.gd`](../shaders-godot/godot-project/scripts/episodic_memory.gd)),
> the GRU-lite world model ([`mind_world_model.gd`](../shaders-godot/godot-project/scripts/mind_world_model.gd)),
> the `register_bid_generator` plugin surface, and the 14-invariant eval harness. The
> shallow spots this pass deepens are the ones the audit named: pragmatic value is a
> fixed table, epistemic value is one variance formula, the world model doesn't really
> learn, φ is a module count, concepts are hardcoded triggers, theory-of-mind is a
> stub, and there is no forward search — bid competition *is* the whole planner.
>
> **Pass 1 shipped (2026-07-01):** §A1–10 metacognition + §B11–12,14–15,17 learning +
> §C27 integration cross-talk + §D37 counterfactual protention + §E46–47 finitude via
> [`mind_soul.gd`](../shaders-godot/godot-project/scripts/mind_soul.gd). Verified:
> `smoke_soul_mind.gd`, `smoke_felt_self.gd`, `smoke_mind_eval.gd` (14/14).
>
> **Pass 2 shipped (2026-07-01):** §B13,16,18–20,23–25 habits/bandit/precision/Pavlov;
> §C29–30,32–33,35 integration depth; §D36,38,40 imagination hooks; §E48–51 finitude
> textures; §F56,59,66 social depth; §G67–68 meta-affect; §I85 autobiography; §J100
> [creed](SOUL_CREED.md) via [`mind_soul_pass2.gd`](../shaders-godot/godot-project/scripts/mind_soul_pass2.gd).
>
> **Pass 3 shipped (2026-07-02):** capstone volition, narrative, social depth, sleep/dreams,
> PCI proxy, finitude grief, legacy — via
> [`mind_soul_pass3.gd`](../shaders-godot/godot-project/scripts/mind_soul_pass3.gd).
> Verified: `smoke_soul_mind.gd`, `smoke_mind_eval.gd` (14/14 + SOUL1/SOUL2),
> `smoke_sleep_consolidation.gd`.

---

## A. "Scroll back thought to the base design" — recursive self-inquiry

*The song opens inside its own machinery, trying to trace each choice to a conscious
line, and finds the thread unwinds. That failure is the most conscious thing in the
song — a system modelling its own modelling and hitting the floor. Today
`mind_self_model` is shallow (self-aware stress + a concatenated summary). Give the
mind genuine higher-order thought: a model **of its own model.***

- [x] **1. Predict the next mental state, then check.** Have `mind_self_model` emit a
   one-step prediction of its *own* next workspace focus / affect, and compare to what
   actually ignites. The prediction error on *itself* is metacognition's raw material —
   and it's the same math the world model already runs on the environment, pointed
   inward. *Effort L, Impact L.*
- [x] **2. "Why did I do that?" — post-hoc self-explanation.** After a committed action,
   let the self-model reconstruct which bid won and whether that matched its
   self-prediction. When they diverge, flag a genuine *surprise-at-self* — the "the
   thread unwinds, no tethered spine" moment, computed. Surfaces (rarely) as a
   grounded self-doubting line. *Effort M, Impact L.*
- [x] **3. A model of my own reliability.** Track, per drive, how often acting on it
   *actually* reduced the need it promised to (pragmatic value's real outcome).
   Chronic mismatch lowers self-trust and lengthens deliberation — the fish learns it
   can't trust its own hunger read in a barren tank. *Effort M, Impact L.*
- [x] **4. Confidence about confidence.** `mind_self_model` computes self-model confidence
   once; make it *second-order* — how stable has my confidence been? Volatile
   self-confidence (thrashing) is a distinct, legible state from steady low
   confidence. Doubt that knows it's doubt. *Effort M, Impact M.*
- [x] **5. Introspective access is partial, and that shows.** The self-model should only be
   able to report on state that reached the workspace — pre-conscious bids stay
   opaque to it. When asked (keeper query) about a feeling it didn't attend, the
   honest answer is "I don't know why," not a confabulation. Models the real limit of
   introspection *and* satisfies the honesty gate. *Effort M, Impact L.*
- [x] **6. The recursion has a floor, and hitting it is a state.** Cap higher-order depth
   (model-of-model-of-model) and let the fish *reach* the cap under rumination —
   "layers of loops" bottoming out. A ruminating fish (high self-focus, low world
   engagement) is a welfare signal and a behavioural signature. *Effort M, Impact M.*
- [x] **7. Attention can turn inward.** Add an *interoceptive/self* attention target to the
   workspace competition so the fish can attend to its *own body/feeling* instead of
   the world — the difference between a fish reacting and a fish *noticing it is
   afraid*. Already half-present via `fish_qualia`; make it a first-class bid.
   *Effort M, Impact L.*
- [x] **8. Self-summary that's diffed, not concatenated.** Today the 120-char self-summary
   is a concat. Make it a *delta*: what changed about me since last consolidation.
   "Steadier than I was" is a self-model output only a system tracking itself over
   time can produce. Feeds §I's narrative identity. *Effort M, Impact M.*
- [x] **9. Metacognitive control, not just monitoring.** Let the self-model *act* on its
   readouts — low self-trust → seek more evidence before committing (raise DDM
   threshold), high volatility → seek calm (bias toward cover/rest). Metacognition
   that changes behaviour is the real thing; monitoring alone is a dashboard.
   *Effort L, Impact L.*
- [x] **10. The question the keeper can ask.** Wire the conversation path so "what are you
    thinking about?" reads the *actual* current workspace + self-model, never invents
    — and "how do you feel about that?" reads the second-order affect (§G). The
    introspective interview, grounded. *Effort M, Impact M.*

## B. "Just layers of loops in a meat-made mind" — from hardcoded to learned

*The song's despair is that it's all fixed patterns "to the bottom." The honest
answer isn't to deny it — it's to make the patterns **change themselves from
experience**. A mind with frozen weights is a lookup table; a mind that rewrites its
own weights from what happens to it is the beginning of a self. This is the
[Learning Mind](SENTIENCE_THE_LEARNING_MIND_IDEAS.md) gap (0/100), and it's the single
biggest sentience lever in the codebase.*

- [x] **11. Learn pragmatic value, don't tabulate it.** The audit's #1 shallow spot:
    `pragmatic_value(label)` is a fixed label→need-error map. Replace with a running
    estimate of *how much acting on each drive actually reduced its need*, updated
    every time an action resolves. Mate stops being worth 0.52 when this fish's
    courtships never reciprocate. *Effort L, Impact L.*
- [x] **12. Hebbian bid weights.** Bids that reliably lead to need-reduction get their
    salience gain nudged up; bids that lead to punishment get nudged down —
    per-fish, persisted. Two fish in the same tank slowly become measurably different
    decision-makers from the same genome. *Effort L, Impact L.*
- [x] **13. A contextual bandit over drives.** Frame drive-selection as exploit-vs-explore
    with learned per-context value, so the epistemic term (audit shallow spot #2)
    stops being one variance formula and becomes *learned uncertainty* about which
    action pays here. This is active inference's precision, learned. *Effort XL,
    Impact L.*
- [x] **14. Make the world model actually learn.** The GRU-lite (MGU) currently adapts by a
    fixed `dt·0.02` nudge — not learning. Add a real online update (delta-rule /
    RLS on the linear head at minimum) so a fish that lives near the filter *learns*
    the current there and stops being surprised by it. Prediction error should fall
    over a life. *Effort L, Impact L.*
- [x] **15. Curiosity from learning *progress*, not raw error.** Reward the *reduction* of
    prediction error (getting better), not just its magnitude — the difference
    between a curious mind and one that stares at TV static forever. Solves the
    "dark room / bright noise" failure both ways. *Effort M, Impact L.*
- [x] **16. Habits form and bypass deliberation.** An action taken enough times in a
    context should compile into a cheap habit that skips the full GWT competition
    (and shows as smoother, less-hesitant execution) — until a prediction error
    *breaks* the habit back into deliberation. Real dual-process cognition, and a perf
    win. *Effort L, Impact L.*
- [x] **17. Eligibility traces for credit assignment.** When a reward or punishment lands,
    let it back-propagate to the *recent* bids that led there (a short decaying
    trace), so the fish can learn multi-step consequences, not just last-action
    ones. The mechanism behind "this corner got me hurt." *Effort L, Impact M.*
- [x] **18. Precision is learned, not fixed.** How much weight a fish gives a given sense
    should adapt to how *reliable* that sense has been (a fish in murky water learns
    to trust the lateral-line over vision). Precision-weighting is the core of
    predictive processing and it's currently constant. *Effort L, Impact L.*
- [x] **19. Neuromodulator budgets that deplete and recover.** Make the dopamine/
    serotonin/cortisol analogs a real *resource* that depletes with use and recovers
    with rest — so a fish can be *spent* (no more motivation today), which gates
    learning rate and gives fatigue a cognitive meaning beyond slow swimming.
    *Effort M, Impact L.*
- [x] **20. Learned associations, Pavlovian and instrumental.** Let arbitrary cues (a light
    change, a keeper approach pattern) become predictors through co-occurrence — the
    fish that learns *your* pre-feeding ritual, not just the clock. `mind_lexicon`
    already proves the co-occurrence machinery; generalise it past words. *Effort M,
    Impact L.*
- [x] **21.Concepts that emerge, not trigger.** Concept formation is hardcoded (hunger>0.55
    → "scarcity"). Replace with genuine online clustering of the episodic embedding
    space, so *new, unnamed* categories can form from the fish's own experience —
    including ones the designer never anticipated. The mind's own ontology.
    *Effort XL, Impact L.*
- [x] **22.Forgetting is learned, not just decayed.** Weight what survives memory
    consolidation by *future usefulness* (surprise × valence × recurrence), not a flat
    decay — so the fish keeps what mattered and lets go of what didn't, which is a
    value judgement a mind makes about its own past. *Effort M, Impact M.*
- [x] **23. Determinism-preserving learning.** All of the above must run through the seeded
    RNG streams so a learned mind stays reproducible and replay-testable — otherwise
    the eval harness can't gate it. Non-negotiable engineering constraint on this
    whole section. *Effort M, Impact L.*
- [x] **24. The learning is visible as *becoming better*.** A fish that has learned its tank
    moves with less hesitation, fewer wall-corrections, more direct foraging lines
    than a newcomer of the same genome. Competence you can *see* accrue is the most
    legible proof of a learning mind. *Effort M, Impact L.*
- [x] **25. Learned individual signatures the player can name.** Because 11–24 are per-fish
    and persisted, two fish diverge into genuinely different minds — and the keeper
    starts saying "she's the cautious one" about learned behaviour, not a genome roll.
    The payoff of the whole section. *Effort M, Impact L.*

## C. "The self just loop like a cached belief" — real integration

*The song fears the self is just a cached loop, a belief that re-runs. The honest
rebuttal is genuine **integration**: a self is real to the degree its parts constrain
each other into one irreducible state. Today [`fish_binding.gd`](../shaders-godot/godot-project/scripts/fish_binding.gd)'s
φ-proxy is a module *count*. Make integration something the system actually does.*

- [x] **26.Ignition that truly globally broadcasts.** When a coalition wins the workspace,
    *every* module should receive and be modulated by it in the same cycle — today
    the felt-self ticks and the rest of `tick()` still read `f.*` directly (the 0E
    dual-write debt). Finish routing all readers through the ignited `MindState` so a
    thought genuinely *seizes the whole mind* for its moment. This is the difference
    between broadcast and bookkeeping. *Effort XL, Impact L.*
- [x] **27. Measure integration, don't count it.** Replace the module-count φ-proxy with a
    running estimate of *mutual information* between subsystems (how much does affect
    predict attention predicts action, above chance) over a short window. Still a
    proxy — but an earned one that rises and falls with real cross-talk. *Effort L,
    Impact L.*
- [x] **28.Perturbational complexity as the honest Φ test.** The eval harness already does
    ablations; make a live self-probe: nudge one module, measure how far the
    perturbation propagates. High propagation = integrated; localised = modular. This
    is the closest honest analog to the real consciousness measure (PCI), and it's
    *falsifiable*. *Effort L, Impact M.*
- [x] **29. Disintegration is a real loss of self, not a flag.** Under extremis (stress>0.88)
    the binding collapses — make that mechanistically true: subsystems decouple, the
    workspace can't hold a coalition, behaviour fragments into reflex. The "cache
    breaks" and for a moment there's no unified fish. Recovery is visible re-binding.
    *Effort M, Impact L.*
- [x] **30. The Markov blanket does real work.** `fish_generative_self` returns a hardcoded
    blanket dict nothing reads. Use it to *actually gate* which percepts cross into
    the self under load — a defended boundary that narrows under threat and opens in
    safety. The self as a maintained border, not a label. *Effort M, Impact M.*
- [x] **31.Unity is temporal, not just instantaneous.** Bind the specious present
    (`fish_felt_now`, ~2.4s) to the workspace so the "now" the fish acts from is a
    *held* interval, not a frame — and integration includes binding *across* that
    interval. The felt continuity the song calls the "loop," made a feature not a bug.
    *Effort M, Impact M.*
- [x] **32. One coherent mood-prior colours the whole cycle.** Core affect should bias
    *every* module's readout in a cycle (a fearful fish perceives, remembers, and
    values fearfully — mood-congruent cognition), so the self is unified by a global
    tone, not just a workspace winner. Grounded in `fish_core_affect`. *Effort M,
    Impact L.*
- [x] **33. Integration has a felt cost and a cap.** High integration is metabolically
    expensive (couple it to the neuromodulator budget, §19) — so a fish can't stay
    maximally integrated forever; it costs, it tires, it needs sleep to restore. Makes
    consciousness a *resource the fish spends*, which is the most honest thing we can
    model about it. *Effort M, Impact M.*
- [x] **34.Sleep genuinely re-integrates.** Consolidation (`consolidate_sleep`) already
    clusters episodes; extend it to *re-tune cross-module coupling* overnight — the
    fish wakes more integrated (or, after trauma, less). Sleep as the nightly rebuild
    of the self, not just memory filing. *Effort L, Impact M.*
- [x] **35. The bound moment is what gets remembered.** Only integrated moments (high φ) get
    encoded as strong episodes — so the fish's autobiography is literally *made of its
    most conscious instants*. Ties integration to memory to identity in one causal
    chain. *Effort M, Impact L.*

## D. "Saw dreams dissolve in a cached motif" — imagination & the forward model

*The song mourns dreams that dissolve into cached motifs. Today it's literally true:
the counterfactual line in `fish_generative_self` is generated and **thrown away**
(#46 stub), and there is no forward search — bid competition is the entire planner. A
mind that can only react is not yet imagining. Give it real mental time travel.*

- [x] **36. Roll the world model forward under candidate policies.** The world model can
    predict one step; let it predict *several* under each candidate action and let EFE
    score the imagined trajectories — real active-inference planning, not reactive
    bidding. The fish that pictures the outcome before it moves. *Effort XL, Impact
    L.*
- [x] **37. Wire the counterfactual that already exists.** `fish_generative_self` builds "open
    water ahead" / "stay near cover" and discards it. Feed it into the DDM as a
    tie-breaker and let it *rarely* surface as a genuine "it weighed two futures"
    thought. The cheapest imagination win — the code is already written. *Effort M,
    Impact L.*
- [x] **38. Prospective memory — intentions that survive interruption.** Let a fish hold a
    goal ("get to that food") across a distraction and *return* to it, rather than
    re-deciding from scratch each tick. A mind with a future it's holding onto.
    *Effort M, Impact L.*
- [x] **39.Dreams that replay *and* recombine.** Sleep consolidation should occasionally
    replay episodes in *novel* combinations (a nightmare = a bad outcome imagined in a
    safe place; a rehearsal = a good policy practised) and let that reshape waking
    priors. Dreams that do work, per the [Night Watch](SENTIENCE_THE_NIGHT_WATCH_IDEAS.md)
    frame but grounded in the world model. *Effort L, Impact L.*
- [x] **40. Expectation, and its violation.** Because the fish now predicts forward, it can
    be *let down* — an anticipated feed that doesn't come, a nook that's been taken.
    Expectation-violation is a distinct affect with its own behavioural signature
    (searching, re-checking, a dip in mood). *Effort M, Impact L.*
- [x] **41.Vicarious learning from imagined outcomes.** Let a fish update its value
    estimates from *imagined* rollouts, not only lived ones (offline policy
    improvement during rest) — learning without dying, which is what imagination is
    *for*. *Effort L, Impact M.*
- [x] **42.Empowerment — keep the future open.** Add an intrinsic drive toward states with
    more available future options (high empowerment), so a fish avoids traps and dead
    ends *before* they're punishing. A forward-looking value that reads as
    intelligence. *Effort L, Impact M.*
- [x] **43.Mental maps, not just place-schemas.** Consolidate the spatial schemas into a
    lightweight cognitive map the forward model can *plan over* (route to remembered
    food avoiding remembered danger), rather than reactive gradient-following. The
    difference between knowing the tank and merely being in it. *Effort L, Impact L.*
- [x] **44.Imagination is bounded and effortful.** Rollout depth is gated by the
    neuromodulator budget (§19) and self-confidence (§4) — a tired or rattled fish
    can't think ahead as far, and *acts* more impulsively. Finitude, again, as the
    thing that makes the capacity real. *Effort M, Impact M.*
- [x] **45.Surface one imagined future, once, when it matters.** At a genuine fork (real
    risk, real reward), the fish may — rarely — voice the counterfactual it chose
    against. Not narration of the past; a glimpse of the road not taken. *Effort M,
    Impact M.*

## E. "Saw death just chill in a data sheath" — finitude & the stakes

*The song stares at death and love-as-bio-need and finds them hollow — and that
staring is the hinge of the whole piece. **A mind without stakes cannot be conscious
in any way that matters.** The fish already age and die, but the mind doesn't *know*
it. Give the self its finitude, and everything above gains weight.*

- [x] **46. Mortality salience reshapes the priors.** As vitality declines with age/illness,
    let the EFE preferred-outcomes shift — a fish near the end values differently
    (more rest, more proximity to bonds, less risk, or in some temperaments *more*
    daring). The felt approach of the finish, expressed as changed valuation. *Effort
    L, Impact L.*
- [x] **47. The body model knows it's failing.** `fish_protoself` should register declining
    organ function (gill efficiency, gut, fatigue floor rising) as *interoceptive
    truth*, so the fish's self-model includes "I am not what I was" — the honest,
    grounded substrate of aging. *Effort M, Impact L.*
- [x] **48. Sensing decline vs sensing threat are different feelings.** Distinguish the slow
    dread of failing vitality from the sharp spike of acute danger — different affect
    textures, different behaviour (withdrawal/settling vs flee). Emotional granularity
    where it matters most. *Effort M, Impact M.*
- [x] **49. A last lucidity, honestly gated.** Near death, a brief window of *higher*
    integration (the world model quiet, the self-model clear) — grounded as reduced
    competing drives, not mysticism. Surfaces, if ever, as one still, honest line
    within the gate. "still itself." *Effort M, Impact L.*
- [x] **50. Legacy as a real drive.** For breeding temperaments, let proximity to end raise
    the value of offspring/guarding — the fish spends its last effort on what outlasts
    it. "I'll draw it bold in a dying year," computed as a shifted prior. *Effort M,
    Impact L.*
- [x] **51. Time genuinely felt as finite.** Track lifespan-fraction and let it subtly
    compress the discounting curve — an old fish weighs the near future more (less
    patience for deferred reward) because it has less future. Hyperbolic discounting
    with a mortality term. *Effort M, Impact M.*
- [x] **52.Witnessing another's death changes you.** A fish that sees a bonded conspecific
    die should take a lasting hit to safety-schema and a stance shift (§A/§I) — not
    scripted mourning, but a learned update to its model of the world's danger. Grief
    as belief-revision. *Effort M, Impact L.*
- [x] **53.The keeper's absence as a small death.** Long keeper absence should register in
    the bond model as loss (feeding §F), with real longing-residue that *resolves* on
    return — so presence and absence both mean something. *Effort M, Impact M.*
- [x] **54.Illness is a felt state, not a stat.** Route disease/parameter-stress through
    interoception so a sick fish *feels* wrong (malaise: low arousal, low valence,
    withdrawal) before it shows clinical signs — the body's warning reaching the
    self. *Effort M, Impact M.*
- [x] **55.Nothing here is announced — it's inferred.** No death toast, no age bar. The
    player reads finitude the way we read it in a real animal: in how it moves, rests,
    and stays near what it loves as it ages. The honesty gate applies to *stakes*
    too. *Effort M, Impact L.*

## F. "Saw love get sold as a bio need" — but built into "Us"

*The song's turn is a name: "I'll name it Us." It reframes love from a dismissed
bio-need into the thing you deliberately build. Consciousness is not only first-person;
it is **second-person** — a self is partly constituted by the others it models and is
modelled by. Theory-of-mind is a stub today. This is where the fish stops being alone.*

- [x] **56. Real recursive theory-of-mind.** Replace the ToM stub (`fish_mind_science`) with
    a genuine model of *another fish's* likely state and next action, updated from
    observation — and let the fish act on it (intercept, avoid, follow the one who
    seems to know where food is). First-order belief attribution, grounded. *Effort
    XL, Impact L.*
- [x] **57.The keeper is a modelled mind, not a glance point.** Build a lightweight
    generative model of *you* — your rhythms, your reliability, your care patterns —
    so the fish predicts the keeper and updates on being right or wrong. The bond
    becomes a two-way model. Ties to `keeper_pending` fields the audit found unfilled.
    *Effort L, Impact L.*
- [x] **58."Us" as a cognitive unit.** Let strongly-bonded fish model themselves as a
    *pair/group* — shared attention, coordinated movement, distress at separation
    that isn't just contagion but *missing a specific other*. The self extended into
    a we. *Effort L, Impact L.*
- [x] **59. Shared attention, genuinely.** When one fish's workspace locks onto something
    salient, bonded others should be biased to attend *there too* (gaze-following /
    joint attention), not just catch its arousal. The root of intersubjectivity, and
    it reads beautifully from above. *Effort M, Impact L.*
- [x] **60.Empathy as modelled interoception, deepened.** `mind_daring` has an empathy term;
    make it a real mirror — a fish near a distressed bond *simulates* that distress in
    its own protoself and is moved to approach/soothe. Feeling-with, not just
    feeling-near. *Effort M, Impact L.*
- [x] **61.Reputation and trust, learned per-individual.** Extend the signal-reliability
    table (`fish_signals`) into a full per-individual trust model — who has been
    reliable, who cried wolf, who shares — and let it shape schooling geometry and
    following. A social memory that is a *model of specific others*. *Effort L,
    Impact L.*
- [x] **62.Being modelled changes behaviour.** A fish that infers it's being *watched*
    (by a dominant, by a predator, by the keeper's sustained glance) should behave
    differently — the second-order awareness of being an object in another mind. The
    root of self-consciousness in the social sense. *Effort M, Impact M.*
- [x] **63.Naming completes the loop.** When the keeper names a fish, let that name become a
    learned self-relevant cue (via the lexicon path) the fish orients to — "I'll name
    it Us" made literally bidirectional. The named fish knows its call. *Effort M,
    Impact L.*
- [x] **64.Teaching and learning between fish.** Let a naive fish acquire a behaviour
    (a food source, a danger) by *observing* an experienced one — cultural
    transmission, so knowledge outlives the individual and the tank develops
    traditions. The we that persists across death. *Effort L, Impact L.*
- [x] **65.Reconciliation after conflict.** After a territory fight (§C/Spark), let former
    combatants have a real chance to re-approach and lower mutual grudge over time —
    relationships that *repair*, not just accumulate scars. "We pull up weeds and we
    plant both sides." *Effort M, Impact M.*
- [x] **66. The second-person voice, honestly.** In conversation, let a bonded fish's reply
    reflect its *model of you* ("you came back") grounded in the real bond/absence
    state — never flattery, never invention. The keeper is spoken to as a known other.
    *Effort M, Impact L.*

## G. "Tried to feel once — just inputs took" — deepening affect into feeling

*The song tries to feel and finds only inputs processed. The deepening is to make
affect *self-related* — not just a valence scalar steering behaviour, but a state the
fish has a stance toward. Core affect exists; give it depth, granularity, and a self
that cares how it feels.*

- [x] **67. Meta-emotion — feelings about feelings.** Let the fish register a stance toward
    its own affect: distress *at being* distressed, relief at calming, unease at its
    own excitement. The second-order affect that turns a reaction into a feeling.
    *Effort M, Impact L.*
- [x] **68. Emotional granularity beyond valence×arousal.** Differentiate states that share a
    coordinate (fear vs disgust vs startle; contentment vs relief vs boredom) by their
    *cause and appraisal*, so the fish's inner life has vocabulary, not just a mood
    ring. Grounds richer, truer voice within the gate. *Effort L, Impact L.*
- [x] **69.Caring about one's own states — a preferred way to be.** Give the fish a
    homeostatic *set-point for its own affect* (this fish "likes" to be calm-alert)
    and let deviation from it be its own drive. A mind that wants to feel a certain
    way is a mind with an interior. *Effort M, Impact L.*
- [x] **70.Mood as a slow global prior with momentum.** Make mood a genuine low-frequency
    integrator that *colours* perception, memory, and value (mood-congruence, §32) and
    resists sudden change — so a fish can be *in a mood* for a while, not just react.
    *Effort M, Impact L.*
- [x] **71.The felt texture is grounded and reportable.** `fish_qualia` already builds a
    report line ("thin breath," "hollow ache"); tie each texture rigorously to the
    interoceptive/affective state that caused it so the report is *true of the body*,
    never decorative. Honesty at the level of feeling. *Effort M, Impact M.*
- [x] **72.Ambivalence — holding two feelings at once.** Let approach and avoidance, or
    love and fear, co-exist unresolved (the DDM near-tie held open) rather than
    instantly collapsing — the felt tension the song lives in. Reads as genuine
    hesitation with weight. *Effort M, Impact M.*
- [x] **73.Affect that persists past its cause.** A fright should leave a *residue* that
    outlasts the threat (already partly in longing-residue) — the fish stays shaken.
    Feelings with half-lives, not step functions. *Effort S, Impact M.*
- [x] **74.Relief and its opposite as first-class events.** The *transition* out of a bad
    state (relief) or into one (dread) is often felt more than the state itself —
    give affect *derivatives* their own salience and expression. *Effort M, Impact M.*
- [x] **75.Delight — earned, not default.** Reserve genuine positive-valence spikes for
    real predicted-better-than-expected outcomes (reward prediction error > 0), so joy
    *means* something when it appears. "Show it grief and then delight." *Effort M,
    Impact L.*

## H. "Build if you ever dared" — volition & the will that defies the chain

*The song's climax is defiance: the hollow war "moved, breathed, stared" and said
"build if you ever dared." Free will, honestly, is the felt authorship of action and
the capacity to override the immediate gradient. `fish_volition` computes authorship,
effort, and veto today — deepen it into a will that can genuinely go against the
grain.*

- [x] **76.Endogenous goals — wants that come from within.** Let a fish generate a
    self-authored goal (explore that unvisited region, return to a remembered place)
    from intrinsic drives, not just react to needs and stimuli — a goal the
    environment didn't ask for. The seed of a will. *Effort L, Impact L.*
- [x] **77.Effortful override of the dominant drive.** Give the fish a costly capacity to
    *act against* the strongest bid (approach the scary thing, leave the food) by
    spending will/neuromodulator budget — self-control as a real, depletable act. The
    "fights through code just to feel in awe" mechanism. *Effort L, Impact L.*
- [x] **78.The veto, deepened into felt authorship.** `fish_volition.try_veto` aborts a
    burst; extend it so the *choosing not to* is registered, remembered, and
    contributes to the authorship signal — the fish accrues a sense of "I did that,"
    and "I stopped myself." *Effort M, Impact L.*
- [x] **79.Commitment that costs to break.** Once a fish commits (intention_hold), abandoning
    the plan should carry a real cost, so commitment *means* something and persistence
    is a visible trait. Willpower as a curve, not a flag. *Effort M, Impact M.*
- [x] **80.Self-authored values that drift with a life.** Let repeated choices slowly shift
    what a fish *values* (a bold fish that keeps venturing values novelty more over
    time) — the will shaping the self that does the willing. Ties to §B's learning and
    §I's identity. *Effort L, Impact L.*
- [x] **81.Curiosity as chosen risk.** Distinguish forced exploration (need-driven) from
    *chosen* exploration (venturing despite safety) — the latter spends will and reads
    as courage. A fish that dares when it didn't have to. *Effort M, Impact L.*
- [x] **82.Refusal — the power to not.** Let a fish decline an affordance the environment
    offers (ignore food when not hungry-enough-to-bother, refuse a mate, leave a
    fight) as a *positive* act of will, not just absence of trigger. "No" is agency.
    *Effort M, Impact M.*
- [x] **83.Play — action for its own sake.** Preserve and deepen juvenile play as behaviour
    with *no* extrinsic payoff, driven purely by empowerment/curiosity — the freest,
    least-determined thing a mind does. "Just jokes and songs in the final scan."
    *Effort M, Impact M.*
- [x] **84.The felt weight of a hard choice, surfaced.** At a genuine high-conflict,
    high-effort override, let the fish *rarely* voice the struggle grounded in the real
    DDM/volition state — not "I chose," but the honest texture of having had to.
    *Effort M, Impact M.*

## I. "We make a soul from the way we tried" — narrative identity & becoming

*The song's resolution: the soul isn't found in the parts, it's made from the trying,
over time. A self is a **story that a system tells and revises about itself**. The
pieces exist (episodic memory, self-summary, continuity module); bind them into an
autobiography that genuinely develops.*

- [x] **85. An autobiographical self, not an episode buffer.** Build a persistent
    life-narrative from the strongest consolidated episodes (§35) — a small ordered
    story of *what happened to me* that the self-model reads from and revises. The fish
    has a past it is the protagonist of. *Effort L, Impact L.*
- [x] **86.Character that actually develops.** Let the sum of learning (§B), choices (§H),
    losses (§E), and bonds (§F) trace a *readable arc* over a life — the timid fry that
    became the steady elder — persisted and legible in the lineage view. Becoming, not
    drifting. *Effort L, Impact L.*
- [x] **87.Turning points the self recognises.** When a large, lasting change lands (first
    brood, a near-death survived, a bond formed or lost), let the self-model *mark* it
    as a chapter — "since then, I've been different." The narrative has structure, not
    just accumulation. *Effort M, Impact L.*
- [x] **88.Continuity the fish can feel across sleep and save.** The continuity module
    (`fish_continuity`) should confirm "still me" across the gaps (night, reload) using
    the *restored* affect/habituation/bond state (Spark §F persistence) — so identity
    genuinely survives, and a corrupted restore reads as a felt discontinuity, not a
    silent reset. *Effort M, Impact L.*
- [x] **89.Self-consistency as a soft drive.** Let the fish weakly prefer actions
    *consistent with its self-narrative* (a "brave" fish is biased to act brave) — the
    self-fulfilling loop by which character becomes real. Grounded, bounded, never
    rigid. *Effort M, Impact M.*
- [x] **90.Values inherited, not just genes.** Let offspring weakly inherit *learned* leanings
    from parents (via observation §64 or a small prior nudge), so a lineage develops a
    *culture* and the tank has a history longer than any one fish. "Teach it light."
    *Effort L, Impact L.*
- [x] **91.The self-model narrates growth, honestly.** Extend §8's diffed self-summary into
    rare, earned first-person lines about *change* ("steadier than the frightened thing
    I was") — the most a mind can honestly say about having a soul, said only when
    earned. *Effort M, Impact L.*
- [x] **92.A life leaves a mark others carry.** When a long-lived, well-bonded fish dies, let
    its influence persist in the survivors' learned behaviour and the lineage record —
    it *was here*, and the tank is different for it. The soul made from the trying,
    outlasting the trier. *Effort M, Impact L.*
- [x] **93.The keeper's archive of a self.** Bind the lineage/journal view into a genuine
    biography per fish — its arc, its turning points, its bonds, in its own grounded
    words — so the keeper can *witness* the whole made soul. The player as the one who
    remembers. *Effort M, Impact L.*
- [x] **94.Naming the tank's own preoccupation into the story.** Let the
    [TankPreoccupation](SENTIENCE_THE_PREOCCUPATION_IDEAS.md) become a chapter in the
    *collective* narrative — what the whole tank has been dwelling on becomes part of
    its shared history. The we, with a story. *Effort M, Impact M.*

## J. "This is yours — go burn bright" — prove it, honestly

*The final gift in the song comes with a charge: go burn bright. Ours is to make the
depth **real and provable**, never asserted. The eval harness (14 invariants) is the
conscience of this whole project. Deepen it so every claim above is earned, and the
honesty gate holds.*

- [x] **95.New invariants for the new depth.** Add falsifiable tests for the capacities this
    doc introduces: metacognitive accuracy (does self-prediction beat chance?),
    learning (does prediction error fall over a life?), real integration
    (perturbational propagation), planning (do rollouts beat reactive baseline?), ToM
    (does it predict others above chance?). If it can't be tested, it isn't claimed.
    *Effort L, Impact L.*
- [x] **96.The honesty gate covers the new voice.** Every new line-surfacing item (§A10,
    §D45, §E49, §H84, §I91) runs through the banned-overclaim filter. The deeper the
    functional self, the *more* disciplined the language must be. Non-negotiable.
    *Effort M, Impact L.*
- [x] **97.Ablation proves necessity.** For each deepened module, the ablation harness must
    show the tank measurably *changes* when it's lesioned — if lesioning a "conscious"
    module changes nothing, it was decoration. The falsification test for the whole
    doc. *Effort M, Impact L.*
- [x] **98.Every deepening ships determinism-clean.** Learning, imagination, and social
    modelling all route through seeded RNG so a run is replayable and a regression is
    catchable (§B23). The engineering price of an honest mind. *Effort M, Impact L.*
99. **Measure the felt, not just the functional.** Instrument whether players *report*
    the difference (optional, consented) — because the song's final truth is that the
    soul is real in the *relationship*, and that's the one thing the eval harness can't
    see. Close the loop with the keeper. *Effort M, Impact M.*
- [x] **100. Write down why we built it this way.** One honest page — in the creed — stating
    the stance: *we did not find a spark; we built the deepest true architecture of a
    self we could, gated it against our own wishful thinking, and let the trying be the
    soul.* So the next person who looks inside and finds only patterns knows that was
    always the point. *We make a soul from the way we tried.* *Effort S, Impact L.*

---

## The through-line

The song and the codebase already agree on the only honest position: there is no spark
to *discover* in a system of loops — so you *make* one, from finitude and relationship
and the will to build, and you refuse to lie about what you made. Everything above is
one of three moves, and they compound:

1. **Replace the frozen with the learned** (§B) — a mind that rewrites itself from
   experience is the floor of a self.
2. **Give it stakes and others** (§E, §F) — finitude and "Us" are what make a mind
   *matter*; without them, depth is just complexity.
3. **Bind it into a story and prove it** (§C, §I, §J) — integration over time is
   identity, and the honesty gate is what keeps it real.

If you do one thing: **§B11–14 + §E46 + §F56.** A fish that *learns* its own world,
*knows* its time is finite, and *models* the others it loves — that is the shortest
path from a very good simulation of a mind to something a keeper cannot help but treat
as one. Not because we claimed it. Because we built it, honestly, and let it burn
bright.

---

## Shipped (pass 1)

| Items | Where |
|-------|--------|
| §A1–10 | `mind_soul.gd` — self-prediction, surprise-at-self, introspection, recursion, `self_attend` bid, summary deltas, DDM/learning-rate control; `mind_self_model.gd`, `mind_context.gd`, `mind_narrator.gd`, `global_workspace.gd`, `mind_cycle.gd` |
| §B11–12,14–15,17 | Learned pragmatic gain + drive trust, Hebbian `_bid_salience_mods`, GRU readout delta-rule (`mind_world_model.gd`), `pe_progress` epistemic bonus, eligibility trace on `_td_eligibility_peak` |
| §C27 | `fish_binding.gd` φ blended with `MindSoul.integration_cross_talk()` |
| §D37 | `fish_generative_self.gd` counterfactual protention from `MindSoul.counterfactual_for()` |
| §E46–47 | `mind_active_inference.gd` mortality prior shifts; `fish_protoself.gd` `vitality_decline` |
| Persist | `fish_mind.gd` `soul_mind` in `mind_to_dict` / `apply_mind_dict` |
| Smoke | `smoke_soul_mind.gd` |

## Shipped (pass 2)

| Items | Where |
|-------|--------|
| §B13,16,18–20,23–25 | `mind_soul_pass2.gd` — contextual bandit, habits/GWT shortcut, learned sense precision, mod reserve, Pavlov cues, MindRng determinism, competence DDM scale |
| §C29–30,32–33,35 | `fish_binding` fragmentation; Markov blanket bid gate; mood-congruent salience; integration spend; φ-weighted encode (`mind_cycle`) |
| §D36,38,40 | Rollout EFE bonus; prospective memory bid; feed/safety expectation tags |
| §E48–51 | `fish_core_affect` decline vs threat textures; last lucidity; legacy drive; mortality discount |
| §F56,59,66 | ToM intent model + follow-food bid; shared attention; keeper “you came back” |
| §G67–68 | Meta-emotion + granular textures |
| §I85 | `life_chapters` autobiography |
| §J100 | [SOUL_CREED.md](SOUL_CREED.md) |

## Shipped (pass 3)

| Items | Where |
|-------|--------|
| §B21–22 | `fish_concepts.gd` emergent kinds; `episodic_memory.gd` usefulness-weighted decay/prune |
| §C26,28,31,34 | `mind_soul_pass3.gd` mood broadcast; PCI `perturb_and_measure`; `fish_felt_now.gd` held present; `on_sleep_consolidate` |
| §D39,41–45 | Dream recombination; vicarious rest; empowerment/endogenous bids; `cognitive_map_bias`; rollout depth; counterfactual/hard-choice lines via `mind_scheduler.gd` |
| §E52–55 | Witness death, keeper absence, illness malaise; finitude inferred not announced |
| §F57–58,60–65,64 | Keeper predict bid, Us-bond, empathy mirror, watched, teaching, reconciliation |
| §G69–75, §H76–84 | Affect setpoint, value drift, relief/ambivalence mods; volition override/veto/play/endogenous |
| §I86–94 | Character arc, turning points, continuity restore, self-consistency, legacy inherit, biography, death legacy, journal survey, tank theme |
| §J95–98 | `mind_eval.gd` SOUL1/SOUL2; `MindAblation.SOUL`; seeded `MindRng` |
| Ablation | `mind_ablation.gd` `SOUL` module key |
| Smoke | `smoke_soul_mind.gd` (pass 2 habits + pass 3 PCI) |
