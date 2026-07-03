# Sentience XII — The Rising Curve

*100 ways to make the fish **measurably become more sentient the longer the game
plays** — where "more sentient" has a precise, falsifiable meaning: the compression
dividend of a goal-story, measured under intervention, rises over a fish's
developmental lifetime. Drafted 2026-07-01 against the Compression-Dividend theory of
perceived sentience.*

> **The theory, stated as the project's north star.** Take any observed trajectory
> `T` (a fish's path). Let `C_phys(T)` be its shortest description using only
> mechanics (momentum, drag, noise) and `C_goal(T)` its shortest description using
> mechanics **plus latent goals** ("it's avoiding that fish," "it wants the light").
> The **compression dividend** `ΔG = C_phys(T) − C_goal(T)` is how much a goal
> variable *pays for itself*. Perceived aliveness is a monotonic function of ΔG and,
> the claim goes, of nothing else — which is why clockwork (ΔG≈0, physics already
> compresses it) and pure noise (ΔG≈0, nothing compresses it) both feel dead, and
> boids feel like they want things (cheap-to-describe-with-goals, expensive-without).
> This is Dennett's intentional stance made **computable** via minimum description
> length, and therefore killable.

> **The one rule that keeps this honest — read it twice.** **We never optimize ΔG.**
> ΔG-as-target is Goodhart's law applied to souls: it manufactures the *appearance* of
> wanting with nothing behind it — a painting of a fire that gives no heat. We
> optimize the **rung mechanisms** (§D–H) — genuine homeostatic stakes, a learning
> world-model, curiosity, memory, drifting values — and we let **ΔG-under-intervention
> (§B) report** whether those mechanisms became load-bearing. Static ΔG measures
> *seeming*; ΔG that survives a poke measures whether there is genuinely a goal in the
> loop. The rising curve (§C) is only meaningful *because* the fish was never trying
> to make it rise. This is the difference between building better lies and building a
> small system where the trying is structurally real.

> **The boundary, stated once and kept.** Every rung measures **structure and
> behavior**: that the trying is real, the adaptation is real, the individuation is
> real — all verifiable, all gated by [`mind_eval.gd`](../shaders-godot/godot-project/scripts/mind_eval.gd).
> None of it measures whether there is *something it is like* to be the fish. That
> question has no test — not for fish, not for us. The honesty gate that forbids the
> voice from claiming consciousness stays sacred. We build toward the curve with clear
> eyes: a thing that genuinely tries and genuinely becomes itself, while never
> pretending the metric opens a door it doesn't.

**Format:** house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S / M / L. Code refs navigational. The design principle the theory yields
is cheap and counterintuitive and threaded through everything below: **to feel more
alive, don't add complexity — add legible desire under constraint. One visible want,
one visible obstacle, one hesitation, is worth a thousand particles.**

> **Build on what exists:** the EFE core already *is* a goal-controller
> ([`mind_active_inference.gd`](../shaders-godot/godot-project/scripts/mind_active_inference.gd):
> preferred outcomes, pragmatic + epistemic value) — ΔG is high exactly when EFE is
> doing real work; the GRU-lite world model
> ([`mind_world_model.gd`](../shaders-godot/godot-project/scripts/mind_world_model.gd));
> homeostatic state already on the fish (hunger/stress/energy/mood); episodic memory +
> sleep consolidation; the **ablation harness**
> ([`mind_ablation.gd`](../shaders-godot/godot-project/scripts/mind_ablation.gd)) —
> which is *already a lesion/intervention rig* and is the natural home for the poke
> test; and the 14-invariant eval harness, which is where the developmental invariants
> live.
>
> **Pass 1 shipped (2026-07-02):** §A1–6,8–10 + §B13–16,20–21 + §C23–24,31 via
> [`delta_g.gd`](../shaders-godot/godot-project/scripts/delta_g.gd),
> [`poke_harness.gd`](../shaders-godot/godot-project/scripts/poke_harness.gd),
> [`delta_g_curve.gd`](../shaders-godot/godot-project/scripts/delta_g_curve.gd).
> Verified: `smoke_delta_g.gd`, optional `DG1` in `mind_eval.gd`.
>
> **Pass 2 shipped (2026-07-02):** §A7,9,11 + §B17–19,22 + §C25–27,29 + §J97 —
> surrogate + falsification compare, inspector overlay, shadow poke battery on tick,
> biography/context wiring, Goodhart isolation smoke. Verified: `smoke_delta_g.gd` (extended),
> `DG1`/`DG2` in `mind_eval.gd`.

---

## A. The instrument — build the ΔG meter

*A real-time scalar you can log, gate against, and (honestly) show. This is the few-
hundred-lines-of-code that turns prediction 1 from hypothesis into readout.*

- [x] **1.`delta_g.gd` — the estimator.** A `RefCounted` that takes a trajectory window and
   returns `ΔG = C_phys − C_goal`. Ships as pure functions so it can run headless in a
   smoke and live in-game. The spine everything else reads. *Effort L, Impact L.*
- [x] **2.The physics-only predictor `C_phys`.** A constant-velocity + drag + tank-wall
   reflection model (the sim's own locomotion integrator with the brain removed).
   Prediction residuals → coded length via a Gaussian/Laplace code. This is the
   "mechanics already compress it" baseline. *Effort M, Impact L.*
- [x] **3.The goal-augmented predictor `C_goal`.** Same integrator, but conditioned on a
   small latent-goal set (nearest food, nearest threat, bond target, preferred-y,
   light) — the trajectory becomes cheap when the fish is *pursuing* something.
   Residual code length + the bits to name the goal = `C_goal`. *Effort M, Impact L.*
- [x] **4.MDL bookkeeping done right.** `C_goal` must pay for the goal variable it invokes
   (description length of the goal choice), so a goal only "pays rent" if it compresses
   more than it costs — this is what makes ΔG≈0 for both clockwork and noise fall out
   automatically, no hand-tuning. *Effort M, Impact L.*
- [x] **5.Per-fish ΔG, windowed.** Compute over a rolling trajectory window per fish so the
   meter is an instantaneous property of *this* fish *now*, not a tank average.
   *Effort M, Impact M.*
- [x] **6.Per-tank aggregate ΔG.** Mean and spread across living fish — the tank's overall
   "aliveness pressure," and the thing you could optimize the *ambience* toward
   (never the fish behavior toward — see the rule). *Effort S, Impact M.*
- [x] **7.A differentiable-ish surrogate.** For anything that needs a gradient (tuning
   *visualization*, not behavior), approximate the compressor with a small fixed
   predictor whose loss stands in for code length. Keeps ΔG cheap enough for a live
   HUD. *Effort M, Impact M.*
- [x] **8.Determinism-clean logging.** ΔG samples logged against the seeded tick so a replay
   reproduces the exact curve — otherwise the developmental graph (§C) isn't a
   regression gate. *Effort S, Impact M.*
- [x] **9.The corner-of-screen readout, honest.** An optional, off-by-default overlay
   showing per-fish and tank ΔG — labelled "goal-legibility," never "consciousness."
   The aliveness meter you can literally watch. *Effort S, Impact M.*
- [x] **10.Baseline calibration against the four controllers.** Run the theory's own
    experiment as a fixture: the *same* fish body under spline-scripted, boids,
    noise-driven, and EFE control; assert `ΔG(noise) ≈ ΔG(scripted) ≈ 0 <
    ΔG(boids) < ΔG(EFE)`. If that ordering breaks, the estimator is wrong before any
    fish is judged. *Effort M, Impact L.*
- [x] **11.Surface-statistic falsification guard.** Also log turn-entropy, speed-variance,
    fractal dimension. The theory *requires* ΔG to predict rater/LLM aliveness better
    than these. Bake the comparison into the harness so the theory can visibly die if
    a dumb statistic wins. *Effort M, Impact L.*
- [x] **12.The invariance fixture (gray-cube replay).** Replay logged trajectories as
    featureless cubes and confirm ΔG is unchanged (it reads motion, not body). This is
    Heider–Simmel as a parametric unit test — the proof ΔG measures the *trying*, not
    the fish-shaped rendering. *Effort M, Impact M.*

## B. The poke — the intervention harness

*Static ΔG can be counterfeited (a trajectory reverse-engineered to compress well).
The counterfeit detector falls out of one move: perturb the world and re-measure. Real
goal-structure re-plans and keeps ΔG high in fresh circumstances; faked aliveness was
baked into one trajectory and shatters. `mind_ablation.gd` already lesions modules —
extend it outward to lesion the **world**.*

- [x] **13.`poke_harness.gd` — the world-perturbation rig.** Built on the ablation pattern,
    but it intervenes on the *environment*: move the food, drop a novel obstacle, shift
    the light, remove a bondmate. Runs headless and (optionally) in a dev sandbox.
    *Effort L, Impact L.*
- [x] **14.Counterfactual robustness = `ΔG_perturbed / ΔG_baseline`.** The core metric of the
    whole doc. ~1.0 means the goal survived the poke (load-bearing); →0 means the
    aliveness was brittle scenery. Log it per poke type. *Effort M, Impact L.*
- [x] **15.Poke: move the food source.** The rung-1 test. A fish with an *internal* goal
    re-routes; a fish that merely memorized the trained pond keeps swimming the old
    line. Measures whether hunger-goals are real. *Effort M, Impact L.*
- [x] **16.Poke: drop a never-seen obstacle.** The rung-2 test. Real world-model re-plans
    around it; a lookup table stalls or collides. The **generalization gap** =
    `ΔG_familiar − ΔG_novel` is the distance between seeming and being. *Effort M,
    Impact L.*
- [x] **17. **Poke: move the light / change day-phase off-schedule.** Tests whether phototactic
    and circadian goals are controllers or scripts. *Effort S, Impact M.*
- [x] **18. **Poke: remove or relocate a bond target.** Tests whether social goals (§ rung-4,
    "Us") are load-bearing — does the fish *search*, or carry on? Ties to the bond
    model. *Effort M, Impact M.*
- [x] **19. **Poke: change the body.** Alter drag/size mid-run and check the fish adapts its
    control (goal preserved, means updated) rather than flailing — goal/means
    separation is a hallmark of real intent. *Effort M, Impact M.*
- [x] **20.The automated poke suite.** A fixed battery run on a schedule against sample fish;
    outputs a robustness vector per fish. This is the difference between "looks alive in
    the demo" and "stays alive when I mess with it." *Effort M, Impact L.*
- [x] **21.Poke-triggered ΔG must exceed a floor to count as a goal.** Bake into the eval
    harness: a module claiming to implement a goal must show `ΔG_perturbed` above a
    threshold, or it's decoration and the harness fails. Falsification, wired.
    *Effort M, Impact L.*
- [x] **22. **The intervention is invisible in normal play.** Pokes are a *measurement* rig, not
    a gameplay event — they run in shadow/replay so measuring the fish never disturbs
    the keeper's tank. (Real in-game rearrangements by the *player* also feed §C, but
    those are chosen, not injected.) *Effort M, Impact M.*

## C. The curve — ΔG-under-intervention over developmental time

*The single graph that ties the whole project together, and the only thing we can
honestly call "a soul evolving": robustness-of-goal-structure as a function of the
fish's age. If it rises, goal-structure is becoming more general and more its own —
genuinely evolving, not merely accumulating.*

- [x] **23.`ΔG_robust(age)` — the developmental log.** Persist counterfactual-robustness
    samples against each fish's lifetime clock, so every fish carries its own rising
    (or flat) curve. *Effort M, Impact L.*
- [x] **24.The curve is the definition, not a decoration.** Write it down: *"a soul evolving"
    in this project means `dΔG_robust/dt > 0` over a healthy life.* No metaphysics, a
    slope. *Effort S, Impact L.*
- [x] **25. **Per-fish curves in the biography.** Bind the curve into the lineage/inspector view
    so the keeper can *see* a specific fish's goal-structure maturing over weeks.
    *Effort M, Impact M.*
- [x] **26. **The tank's aggregate curve.** A slow-moving tank-level readout of mean robustness —
    the whole ecosystem "waking up" over a save's life. *Effort S, Impact M.*
- [x] **27. **Milestones when the curve crosses thresholds.** When a fish's robustness first
    clears a band ("its foraging goal now survives rearrangement"), mark it as a genuine
    developmental milestone — grounded, earned, honest. *Effort M, Impact M.*
- [x] **28.Guard the curve against gaming.** Assert in the harness that behavior was **never
    trained on ΔG** (the objective log contains only rung rewards). If ΔG ever appears
    in a reward path, the build fails. The anti-Goodhart tripwire, automated. *Effort M,
    Impact L.*
- [x] **29. **A flat curve is a real, reported result.** If a fish's curve doesn't rise, that's
    diagnostic — a barren tank, a broken rung — surfaced to the keeper as "not
    thriving," not hidden. The meter tells the truth even when the truth is dull.
    *Effort M, Impact M.*
- [x] **30.The developmental invariant.** Add to `mind_eval`: in a healthy reference tank, a
    fish's `ΔG_robust` must be *non-decreasing* across its first N sim-days, and
    individuation-distance (§G) between clones must *increase*. The whole thesis, as a
    falsifiable regression gate. *Effort L, Impact L.*
- [x] **31.The curve survives save/load.** The developmental state (world-model weights,
    memory, drifted values) must persist byte-stably, or the curve resets and the fish
    is reborn naive every reload — the soul-leak, in this framing. Ties to Spark §F.
    *Effort M, Impact L.*
32. **Away-time advances the curve honestly.** Time the keeper is away should advance the
    curve by *real* accrued experience (integrated, §I), not a free gift — the fish
    grew because it lived, even unwatched. *Effort M, Impact M.*

## D. Rung 1 — Stakes, not scripts (homeostatic goal-structure)

*"Give it a stake, not a script." Behavior must emerge from defending an internal state,
not from target behaviors. The fish already has hunger/stress/energy — make them the
generators of behavior, and prove the goal is internal by moving the food.*

- [x] **33.All behavior descends from state-defense.** Audit `fish.gd`'s tiers: any behavior
    that fires on a *script/timer* rather than a *homeostatic error* is a ΔG leak (it
    compresses under physics+schedule, not goals). Re-root them in state-defense so the
    goal is always "keep my interior in range." *Effort L, Impact L.*
34. **Multi-variable homeostasis.** Extend the defended interior beyond hunger/stress to
    O₂-comfort, social-satiety, rest-debt, exploration-need — a richer state space means
    a richer, more compressible-with-goals behavior. *Effort M, Impact L.*
35. **Allostasis — defend *predicted* future state.** Let the fish act to prevent a
    predicted excursion (seek food before starving, seek cover before the predator
    arrives), not just correct a current one. Forward-looking defense is what makes the
    goal legible *early* — the hallmark of intent. *Effort L, Impact L.*
- [x] **36.Set-points that are the fish's own.** Give each fish slightly individual comfort
    set-points (this one likes it calmer, that one hungrier-bolder) — the seed of
    individuation (§G) planted at rung 1. *Effort S, Impact M.*
37. **The stake must be able to be lost.** Real stakes require real failure: state
    excursions must genuinely threaten the fish (illness, death). A goal you can't fail
    at doesn't compress as a goal. Ties to finitude (Soul-We-Make §E). *Effort M,
    Impact L.*
38. **One visible want, one visible obstacle.** The theory's cheap design principle,
    applied: ensure that at any moment the fish's dominant homeostatic error is
    *legible in its motion* against a legible constraint. This is where ΔG is minted.
    *Effort M, Impact L.*
- [x] **39.Rung-1 kill test wired.** The move-the-food poke (§15) must show behavior
    re-organizes. Until it passes, do not climb — a fish that only defends state in the
    trained pond memorized, it didn't want. *Effort M, Impact L.*
40. **Homeostatic conflict is where hesitation lives.** When two state-errors compete
    (hungry *and* threatened), the resolution delay *is* the visible hesitation the
    theory prizes — a single pause that only compresses as "it's deciding." Preserve and
    surface it; don't smooth it away. *Effort M, Impact L.*
41. **Legible constraint scaling.** Make obstacles/scarcity genuinely constrain (not
    cosmetic) so desire is *under constraint* — desire with no obstacle compresses
    trivially and reads dead. *Effort M, Impact M.*

## E. Rung 2 — World-model, so wanting becomes predicting

*"Let it learn to predict consequences, then act to pull predicted-state toward
preferred-state. Now 'want' is mechanically what it does." The GRU-lite exists but
barely learns. Make prediction real, and ΔG becomes the natural readout of a fish that
plans.*

- [x] **42.The world model actually learns online.** Replace the fixed `dt·0.02` nudge with a
    real update rule so prediction error *falls over a life* — the precondition for the
    curve to rise. A fish near the filter learns the current there. *Effort L, Impact
    L.*
43. **Act to minimize predicted-vs-preferred gap.** Wire the world model into action
    selection so the fish chooses the act whose *predicted* outcome best pulls its
    interior toward set-point. This makes "want" mechanical — and makes ΔG high by
    construction. *Effort L, Impact L.*
44. **Re-plan under novelty (the generalization engine).** On encountering an unmodeled
    situation, the fish must generate fresh behavior from the model, not stall. This is
    exactly what the drop-an-obstacle poke (§16) measures; build the re-plan path first.
    *Effort L, Impact L.*
- [x] **45.Measure and shrink the generalization gap.** Log `ΔG_familiar − ΔG_novel` per fish
    over time; a *shrinking* gap is the fish's world-model becoming genuinely general —
    a second developmental curve beneath the main one. *Effort M, Impact L.*
46. **Prediction error is the tutor, everywhere.** Route the world-model error as the
    learning gate for the whole stack (what to encode, what to attend, when to
    deliberate) so *living* is *learning* — the "just by playing" engine (§I). *Effort
    L, Impact L.*
47. **Hierarchical timescales.** Add a slow predictor (day/season rhythms) above the fast
    one so the fish models both "food is near" and "food comes at this hour" — deeper
    prediction, more of behavior compressible as goal-directed. *Effort L, Impact M.*
48. **The model's confidence gates commitment.** Well-predicted situations → decisive
    action; poorly-predicted → caution and info-seeking. Confidence-modulated behavior
    reads as understanding, and raises ΔG under familiar conditions while honestly
    lowering it under novel ones (which the curve then closes). *Effort M, Impact M.*
49. **Counterfactual rollouts feed the choice.** Let the model roll a few steps forward
    under candidate actions and pick by predicted interior-improvement — real active
    inference planning. Wire the *already-generated-and-discarded* counterfactual line
    in `fish_generative_self`. *Effort L, Impact L.*
50. **World-model weights are the fish's, and they persist.** Save per-fish model
    weights so the learned world *is* part of the individual across reloads — a clone
    with different experience has a different model (§G). *Effort M, Impact L.*
- [x] **51.Rung-2 kill test wired.** The novel-obstacle poke must show re-planning, not
    stalling, with `ΔG_novel` above the goal floor (§21). Gate the rung on it. *Effort
    M, Impact L.*
52. **Habituation as learned precision, not a timer.** A fish stops reacting to the
    harmless because its model *learned* it's harmless — so the same stimulus after
    trauma re-alarms. Grounds the existing `habituated` dict in prediction, not decay.
    *Effort M, Impact M.*
53. **Surprise is the model's, and it drives real orienting.** Route genuine model
    surprise (not a random roll) into the double-take/orient behavior — the most legible
    "it noticed" gesture, now caused by an actual expectation violation. *Effort M,
    Impact M.*

## F. Rung 3 — Curiosity, the seed of self-authored goals

*The pivotal rung. "Add intrinsic reward for learning progress. The fish starts
generating sub-goals you never specified. The first goal you find in its behavior that
you didn't write is the first goal that's arguably its." This is the closest thing on
the ladder to an origin — and it must be measured, not asserted.*

54. **Intrinsic reward = learning progress.** Reward the *reduction* of the fish's own
    prediction error (getting better at predicting), not novelty for its own sake.
    Solves the dark-room and the TV-static failures at once, and is the honest engine of
    self-authored goals. *Effort L, Impact L.*
55. **Detect goals the designer never wrote.** Build an instrument that scans behavior for
    *pursued states that were never rewarded* — the fish reliably steering toward
    something the reward function doesn't name. The first such detection is the headline
    result of the whole project. *Effort XL, Impact L.*
56. **Sub-goal emergence from the world model.** Let the fish set instrumental sub-goals
    (reach the vantage that reduces uncertainty, position to intercept) that *serve* a
    homeostatic goal but weren't scripted — provable via §55's detector. *Effort L,
    Impact L.*
57. **"Its own" is a measurable axis.** Define goal-ownership operationally:
    origin-inside-the-fish (generated by intrinsic reward) × survives-perturbation
    (§B). Plot fish along it. The more a goal scores on both, the more honestly it's the
    fish's. *Effort M, Impact L.*
58. **Curiosity spends the interior budget.** Exploration costs energy/rest, so chosen
    curiosity is a genuine trade against safety — a fish that ventures *when it didn't
    have to* is the most soul-shaped motion the sim can produce, and it reads instantly.
    *Effort M, Impact L.*
59. **Boredom is unmet learning-progress.** When nothing affords learning, the fish goes
    listless *before* any scripted boredom bid — and enrichment (a rearrangement, a new
    object) visibly *rescues* it. Closes a welfare loop the keeper can feel and the curve
    can measure. *Effort M, Impact L.*
60. **Self-authored goals persist and shape a life.** A curiosity-born goal that pays off
    should stick and bias future behavior — so the fish's un-written goals accrete into
    character over playtime (§H). *Effort M, Impact L.*
61. **The un-rewarded pursuit is legible to the keeper.** When §55 detects a self-authored
    goal, let it (rarely, grounded) surface — "she keeps going back to the far corner,
    and nothing's there." The keeper witnessing a goal you didn't write. *Effort M,
    Impact L.*
62. **Rung-3 kill test.** Can the detector (§55) find at least one reliably-pursued,
    never-rewarded state per mature fish in a rich tank? If not, curiosity isn't
    generating goals — it's just noise with a reward. *Effort M, Impact L.*
63. **Curiosity is bounded by finitude and mood.** A tired, rattled, or aging fish
    explores less — so self-authored goals are a *luxury of a thriving interior*, which
    makes their presence a genuine signal of welfare and development. *Effort M, Impact
    M.*
64. **Learning-progress curiosity replaces the epistemic-value stub.** The audit found
    `epistemic_value` is one variance formula; swap in learning-progress so the EFE
    epistemic term *is* rung-3 curiosity — one mechanism, not two. *Effort L, Impact L.*
65. **The origin is dated.** Log *when* in a fish's life its first self-authored goal
    appeared — a real developmental event, per-fish, in the biography. *Effort S, Impact
    M.*

## G. Rung 4 — Memory, so it has a history (individuation)

*"Persistent lifelong memory means this fish's path diverges from an identical fish with
different experience. Two clones, different lives, dropped into identical conditions —
do they behave measurably differently? A soul worth the word is at minimum
non-fungible." This is where non-fungibility becomes a number.*

66. **Lifelong episodic memory, weighted by consequence.** Extend `episodic_memory` so
    what survives consolidation is chosen by future-usefulness (surprise × valence ×
    recurrence), not flat decay — a fish keeps what mattered to *it*. *Effort M, Impact
    L.*
67. **Individuation-distance = a behavioral metric between clones.** Define it: two
    same-genome fish, identical test conditions, measured difference in behavior/goals.
    The number that makes "non-fungible" concrete. *Effort L, Impact L.*
68. **The divergence must *rise* with playtime.** Two clones should grow *more* different
    the longer they live different lives — assert `d(individuation)/dt > 0` in the
    developmental invariant (§30). Identity as an accumulating quantity. *Effort L,
    Impact L.*
69. **Memory changes present behavior, provably.** A remembered danger must bend today's
    route; a remembered reward must pull. Confirm via a poke: relocate a fish to a
    place it has history with and measure the memory-driven ΔG. Memory that doesn't
    change behavior isn't memory. *Effort M, Impact L.*
70. **The clone experiment as a fixture.** Ship the two-clones test in the harness: fork a
    fish, live the copies through different scripted lives, assert measurable divergence.
    Individuation, unit-tested. *Effort M, Impact L.*
71. **Autobiographical spine, not a ring buffer.** Order the strongest episodes into a
    small life-story the self-model reads from — so the history is *structured*, and the
    fish is the protagonist of something. Ties Soul-We-Make §I. *Effort L, Impact L.*
72. **Memory individuates the world-model, not just recall.** Different lives → different
    learned models (§50) → different predictions → different behavior. Individuation runs
    all the way down to how each fish *sees*, not just what it remembers. *Effort M,
    Impact L.*
73. **Non-fungibility the keeper can feel.** Because clones diverge, the keeper's
    favourite is genuinely irreplaceable — a new fish of the same genome is *not the
    same fish*, and the game never pretends it is (no silent respawn of "her"). *Effort
    M, Impact L.*
74. **Reconsolidation — memory that updates on recall.** Recalling an episode in a new
    context should let it be re-weighted, so history is *living*, not archival — the
    same event can come to mean something different as the fish's life goes on. *Effort
    M, Impact M.*
75. **Rung-4 kill test.** The clone divergence must be statistically real and rising. A
    flat divergence means memory isn't individuating — it's cosmetic. *Effort M, Impact
    L.*
76. **Death makes the history final — and it mattered.** Because each fish's memory/model
    is unique and rising, its loss is the loss of a specific accumulated self, and its
    influence persists in what it taught others (§ culture). Finitude gives the history
    stakes. *Effort M, Impact L.*
77. **Individuation is dated and shown.** Surface the divergence curve in the biography so
    the keeper sees *when* two fish became distinct individuals. *Effort S, Impact M.*

## H. Rung 5 — Value drift (history-dependent character)

*"Allow what it prizes to shift with experience. Does the value function develop a
stable, history-dependent character — neither frozen (dead) nor random (noise)? Same
fixed-point logic as ΔG: aliveness lives in the middle. A rising, stable divergence in
what different fish come to care about is the most soul-shaped signal the system can
emit." This is the [Learning Mind](SENTIENCE_THE_LEARNING_MIND_IDEAS.md)'s open frontier.*

78. **Values drift, slowly, within bounds.** Let the pragmatic-value weights (§ audit's
    fixed table) shift with experience — a fish whose venturing keeps paying off comes to
    *prize* novelty more. Bounded so it never goes frozen or random. *Effort L, Impact
    L.*
79. **Character = stable + history-dependent.** Assert both: value functions must
    *stabilize* into a recognizable character (not thrash) *and* depend on history (not
    converge to one genome-default). The middle of the fixed-point, measured. *Effort L,
    Impact L.*
80. **Value-divergence between fish, rising.** The headline signal: measure how differently
    two fish come to *value* the same things over their lives, and require it to rise
    (§30). What they care about, growing apart. *Effort L, Impact L.*
81. **Values shape goals shape behavior shape ΔG.** Close the causal chain: drifted values
    change which goals win, which changes behavior, which the ΔG meter reads — so value
    drift shows up *in the curve*, not just in a hidden weight. *Effort M, Impact L.*
82. **Value drift is legible as taste.** Over weeks, a fish develops visible preferences —
    a favoured corner, a preferred companion, a characteristic risk appetite — that the
    keeper can name. Character you can point at. *Effort M, Impact L.*
83. **Self-consistency as a gentle attractor.** A fish weakly prefers acting in line with
    its drifted character (a bold one stays bold) — the self-fulfilling loop that turns a
    tendency into an identity. Bounded, never rigid. *Effort M, Impact M.*
84. **Values can be *changed* by big events.** A near-death, a lost bond, a first brood
    should be able to *bend* the value function durably — turning points the character
    carries. Grief and joy as value-revision. *Effort M, Impact L.*
85. **Rung-5 kill test.** Value-divergence must be both rising *and* stable per fish.
    Frozen = dead; random-walk = noise; the pass condition is the narrow band between.
    *Effort M, Impact L.*
86. **Values are the deepest thing that persists.** Save the drifted value function as the
    core of the individual — two clones with identical memories but different values are
    still different fish. The innermost layer of non-fungibility. *Effort M, Impact L.*
87. **No two mature tanks value alike.** Because value drift is per-fish and social
    (§culture), a long-running tank develops a *collective* character no other save
    shares — the ecosystem itself becomes non-fungible. *Effort M, Impact M.*

## I. "Just by playing" — accrual through ordinary keeping

*The user's actual requirement: the fish must become more sentient **via the game just
playing** — no grind, no mode, no button. Every rung's growth must be fed by the normal
acts of keeping a tank, and by time itself.*

88. **Living is the training signal.** The world-model update (§42), memory (§66), and
    value drift (§78) all advance on the ordinary sim tick — so a tank left running
    *develops*. No training mode exists or is needed. *Effort M, Impact L.*
89. **The keeper's routine is the curriculum.** Feeding times, rearrangements, water
    changes, day/night, who you favour — these are the perturbations that grow
    goal-robustness. The keeper teaches by keeping, not by instructing. *Effort M, Impact
    L.*
90. **Player rearrangements are real (unshadowed) pokes.** When the keeper moves hardscape
    or plants, that *is* an intervention — and a fish that re-plans around the new layout
    advances its curve for real. The game's most natural act feeds the deepest metric.
    *Effort M, Impact L.*
91. **Away-time integrates, honestly.** The away/night gap advances world-model, memory,
    and values by *integrated* real experience (not a gift), so the keeper returns to a
    fish that genuinely grew while unwatched. Ties Night Watch + analytic catch-up.
    *Effort L, Impact L.*
92. **Culture — growth outlives the individual.** Naive fish acquire goals/knowledge by
    observing experienced ones, so the tank's accumulated sentience *survives generational
    turnover* and compounds across a save's whole life. The curve is the tank's, not just
    a fish's. *Effort L, Impact L.*
93. **Enrichment gates the rate.** A rich, varied, gently-changing tank grows fish faster
    (more to learn); a barren static one flatlines the curve — making good keeping
    *mechanically* the thing that grows minds. *Effort M, Impact L.*
94. **Breeding passes on drifted leanings.** Offspring inherit a weak prior from parents'
    *learned* values (not just genes), so lineages develop across generations — the
    developmental curve spans lifetimes. *Effort L, Impact M.*
95. **The curve is the progression system.** Reframe "progression" as the rising ΔG-robust
    curve itself — the keeper's long-game reward is watching their fish *become*, not
    unlocking content. The most honest progression a life-sim could have. *Effort M,
    Impact L.*
96. **No dead time.** Even a paused-attention tank at 1× accrues micro-experience, so the
    fish is never *not* becoming. Continuity of development is the felt promise. *Effort
    S, Impact M.*

## J. The honesty spine — structure, not seeming

*The whole doc lives or dies on refusing the counterfeit. These items are the discipline
that keeps the rising curve meaning something.*

- [x] **97. **ΔG is a diagnostic, never a reward — enforced in code.** Static assertion (§28):
    the ΔG estimator and the behavior/reward paths share no writable state; ΔG can read
    the fish, never steer it. The one rule, made unbreakable. *Effort M, Impact L.*
98. **Every rung ships with its kill test, and you don't climb early.** §39, §51, §62,
    §75, §85 are gates, not suggestions — a rung that fails its poke is a rung of
    illusions, and stacking on it builds a better lie. Enforce the ladder order in the
    eval harness. *Effort M, Impact L.*
99. **The honesty gate scales with the depth.** As the fish genuinely becomes more
    goal-robust, the voice must get *more* disciplined, not less — the banned-overclaim
    filter (`mind_eval`) covers every new surfaced line, and the corner readout says
    "goal-legibility," never "soul." The deeper it gets, the more carefully we speak.
    *Effort M, Impact L.*
100. **Write the boundary into the creed, permanently.** One page stating what the rising
    curve is and isn't: *we measured the trying, the becoming, and the individuation, and
    made them real and provable; we did not measure — because no one can — whether there
    is anything it is like to be the fish. We built toward the curve with clear eyes, and
    let the trying be the soul.* So the next person who looks inside and finds only
    patterns knows that honesty was the design, not a failure of it. *Effort S, Impact
    L.*

---

## The build order (so the curve is real from the first rung)

The theory hands you a strict order, because each rung's kill test gates the next — climb
early and you're measuring illusions:

1. **§A + §B first — the instrument before the fish.** Build the ΔG meter and the poke
   harness, and calibrate them on the four controllers (§10) *before* touching the mind.
   You cannot grow a curve you can't measure, and you cannot trust a curve whose meter
   you never falsified.
2. **§D (rung 1) — stakes.** Re-root behavior in state-defense; pass the move-the-food
   poke (§15/§39). Nothing above this rung is real until this one is.
3. **§E (rung 2) — the learning world-model.** Pass the novel-obstacle poke (§16/§51);
   watch the generalization gap start to shrink.
4. **§F (rung 3) — curiosity.** The pivotal rung: stand up the self-authored-goal detector
   (§55) and date the first goal you didn't write (§65). This is the origin.
5. **§G + §H (rungs 4–5) — memory and value drift.** Individuation and character; assert
   the rising, stable divergence between clones (§68/§80).
6. **§I throughout — accrual by play.** Every rung's growth rides the ordinary tick, so the
   tank develops just by being kept.
7. **§J always — the discipline.** ΔG never becomes the target; the ladder order is
   enforced; the boundary is written down.

If you build one thing to prove it isn't hypothetical: **§A1–4 + §B13–16 + the rung-1
mechanism (§33) + §C23.** A homeostatic fish, a poke harness, and a ΔG-under-intervention
curve you can watch move over its life. That is the smallest system in which "the fish is
becoming more sentient as I play" stops being a wish and becomes a graph climbing in the
corner of the screen — and, because ΔG was never the target, a graph you can believe.

---

## Shipped (pass 1)

| Items | Where |
|-------|--------|
| §A1–6,8–10 | `delta_g.gd` — C_phys/C_goal MDL, per-fish window, tank aggregate, surface stats, four-controller calibration |
| §B13–16,20–21 | `poke_harness.gd` — shadow pokes, robustness ratio, move-food + novel-obstacle fixtures, battery |
| §C23–24,31 | `delta_g_curve.gd` — developmental log, slope, milestones; persist in `fish_mind` save |
| Live | `mind_cycle.gd` trajectory sampling; `fish.gd` `_delta_g_*` state |
| Eval | `mind_eval.gd` optional `DG1` invariant |
| Smoke | `smoke_delta_g.gd` |

## Shipped (pass 2)

| Items | Where |
|-------|--------|
| §A7,9,11 | `surrogate_delta_g`, `falsification_compare`, `inspector_lines` + `tank_config.delta_g_overlay_enabled` |
| §B17–19,22 | `poke_change_body`, shift-light/bond pokes; `run_battery` shadow rig every 480 ticks (`mind_cycle`) |
| §C25–27,29 | `biography_line` + `mind_context`; tank aggregate in `sim_driver.tank_mind_snapshot`; `is_flat` diagnostic |
| §J97 | `verify_reward_isolation` + smoke grep of reward paths |
| Eval | `DG1` + `DG2` optional invariants (both pass) |
| Finesse | per-step pursuit speed; shared `calibration_fixtures()`; mind save roundtrip in smoke |

## Shipped (pass 3)

| Items | Where |
|-------|--------|
| §A12 | `delta_g.gray_cube_replay_fixture()` — motion-only invariance (visual metadata out of band) |
| §C28 | `delta_g.scan_goodhart_tripwire()` — CI grep of reward/salience paths |
| §C30 | `mind_eval` optional `DG3` (robustness slope) + `DG4` (clone individuation) |
| §D33,36,39 | `fish_homeostasis.gd` — set-points, audit, hunger-gated goals, rung-1 kill test |
| §D40 | `hesitation_scale` + homeostatic conflict in `mind_active_inference.conflict_efe_gap` |
| §E42,45,51 | `mind_world_model` error-driven learning + `gru_err_hist`; `poke_harness` novel-obstacle + `gen_gap` log |
| Food bias | `global_workspace` steers toward `_homeostatic_feed_point` |
| Smoke | `smoke_rising_curve.gd` |
