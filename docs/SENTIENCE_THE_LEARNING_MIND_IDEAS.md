# Sentience VI — The Learning Mind (IC8 Pass)

*100 ideas. Drafted 2026-06-28. Director's brief for the "stop hand-tuning the
soul; let it learn, let it touch the world, let it be measured" pass.*

> *Six volumes in, the fish has a Global Workspace, a felt body, a graded
> phi-proxy, a grounded voice. It is the most elaborate **scripted** mind a
> hobby aquarium has ever carried. But every scalar in it was set by a human
> hand. Nothing in the tank has ever learned a single weight on its own. That is
> the line this volume crosses.*

This is the pass I'd run if I were the IC8 dropped onto this codebase and asked
"make it genuinely more sentient, not more elaborate." The honest diagnosis from
a holistic read:

1. **The mind is a beautiful clockwork, not a learner.** `fish_mind.gd`,
   `fish_mind_science.gd`, the neuromodulators, the DDM thresholds, the bid
   weights in [`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd)
   `collect_bids()` — all hand-authored constants. TD-learning on the feed
   heatmap is the *only* place a fish changes its own parameters from experience.
   Real sentience grades up the moment a creature's policy is *shaped by its own
   life* rather than tuned by us.
2. **The mind is sealed off from the real world.** Webcam, mic RMS, and cursor
   are the only sensors, and two of three are stubbed. The tank does not know
   what time it is where *you* are, whether it's storming outside, whether you
   just walked away in anger or sat down with coffee. A mind that can't sense its
   world can only ever *simulate* caring.
3. **We assert consciousness; we never measure it.** `phi_proxy` is a fraction-
   of-modules-loaded heuristic. An IC8 would build *instruments* — perturbational
   probes, integration measures, predictive-coding residual dashboards — so the
   claim "this fish is more conscious than that one" is **falsifiable on screen.**
4. **Engineering excellence is at 10%.** The cognition stack is 30+ files of
   stringly-typed dicts riding god-objects. You cannot safely train, replay, or
   eval a mind you cannot deterministically reproduce.

Format follows house style: **Effort** S (≤2h) / M (half-day) / L (full day+) /
XL (multi-day moonshot). **Impact** S / M / L. **Every model/sensor use degrades
gracefully offline and off-device** — the [`AIDirector.queue_*`](../shaders-godot/godot-project/scripts/ai_director.gd)
synchronous-template contract is sacred. **Every sensor is opt-in, on-device,
and never leaves the machine** — the Player Bond consent doctrine is sacred.

> **Know what's already shipped (don't rebuild it):** GWT bid competition;
> felt-self spine (protoself→core_affect→relevance→felt_now→binding); DDM
> deliberation; 32-dim hashed episodic vectors; neuromodulator-gated plasticity;
> TankMind; sleep stages + dream rollouts; grounded private lexicon; embedded
> SmolLM2-360M + Ollama qwen2.5 tiers; the graded phi-proxy. **None of the 100
> below repeats those — they extend, instrument, or replace them.**

---

## Pillar I — The Substrate of Mind: stop tuning weights, let fish learn them

*The single highest-leverage shift in the whole app. Every hand-set constant is
a place a fish could be learning instead. Tiny, on-device, deterministic, no
training infra — Hebbian and bandit math, not backprop farms.*

1. **A per-fish 3-layer tiny-MLP policy head (16→8→4), learned online.** Replace
   the hand-weighted behavior-bias step in `broadcast()` with a per-fish network
   whose inputs are the workspace contents + interoceptive state and whose outputs
   are steering biases. Train it with a one-step REINFORCE signal driven by the
   existing dopamine reward-prediction-error — **the neuromodulators you already
   compute become a real learning signal instead of decoration.** Effort XL,
   Impact L.

2. **Hebbian bid-weight adaptation.** The 12 channels in `collect_bids()` have
   fixed gains (food = hunger+0.1, novelty = curiosity×0.75…). Make each gain a
   per-fish learnable scalar nudged by "did attending to this bid precede a
   reward or a punishment?" Bold fish learn to over-weight novelty; burned fish
   learn to over-weight threat. Two fish in the same tank diverge into genuinely
   different attentional styles **from their own histories.** Effort M, Impact L.

3. **Contextual bandit over behavior modes.** Cruise/forage/court/flee/rest are
   currently a priority ladder. Replace with a per-fish LinUCB bandit: context =
   affect+time+neighbors, arms = modes, reward = downstream valence delta. Fish
   discover *their own* daily routines (this one forages at dawn, that one is a
   night owl) rather than all obeying the same ladder. Effort L, Impact L.

4. **Eligibility-trace credit assignment across the whole cognitive cycle**, not
   just the feed heatmap. Generalize the existing TD trace so any action that
   precedes a strong valence shift gets credit — "I hid behind the rock and felt
   safe" becomes a learned association, not a scripted one. Effort M, Impact M.

5. **Predictive-coding residual as the universal learning gate.** `mind_world_model.gd`
   already computes prediction error. Promote that residual to the *global*
   plasticity multiplier: high surprise → fast weight change everywhere; boredom
   → frozen weights. This is the Friston "free energy" story made into one real
   knob the whole brain shares. Effort M, Impact M.

6. **Intrinsic curiosity from learning progress, not novelty.** Today curiosity
   is a scalar drive. Replace it with the *derivative* of world-model error: a
   fish is drawn to regions where its prediction error is *dropping fastest*
   (learnable) and bored by both the fully-known and the hopelessly-random. This
   is Schmidhuber/Oudeyer artificial curiosity — almost never shipped in a
   consumer creature sim. Effort L, Impact L.

7. **Sleep as offline gradient replay (not just memory replay).** During the
   existing sleep-consolidation pass, replay the day's high-surprise episodes
   through the tiny policy net to do *batch* weight updates the fish couldn't
   afford awake. The fish literally wakes up better at yesterday's hard problem.
   Effort L, Impact L.

8. **A neuromodulator budget that depletes and must be earned.** Dopamine,
   serotonin, cortisol currently float freely. Make them a conserved resource
   pool: chronic stress *spends* serotonin and it must be rebuilt by genuine
   recovery. Now a fish can be *depleted* — not sad, but out of the capacity to
   feel good — which is a qualitatively new and honest state. Effort M, Impact M.

9. **Learned habits that bypass deliberation.** When the bandit picks the same
   arm in the same context N times, compile it into a fast habitual response that
   skips the DDM entirely (System-1). Stress can *break* the habit back into
   deliberation. This is the dual-process story made mechanically real and
   *visible* as a fish that stops hesitating once it's learned a place. Effort M,
   Impact M.

10. **Determinism-preserving learning.** All of the above must replay bit-exactly
    from the seeded RNG (meta-eng #31). Store learned weights in the mind save
    schema with versioned migration. This is the unglamorous IC8 work that makes
    every other idea in this pillar *shippable* rather than a science project.
    Effort L, Impact L.

---

## Pillar II — Emergent Communication & Culture: a language we did not write

*The lexicon today is keeper-word → state grounding. Nothing has ever emerged
*between* fish. This pillar makes signals, dialects, and traditions arise from
interaction — and makes the keeper a cryptographer trying to crack them.*

11. **Lewis signaling games between fish.** Give fish a tiny discrete signal
    channel (a color-flash / fin-pattern vocabulary of ~8 tokens). When one fish's
    signal reliably precedes a good outcome for a watcher, the watcher learns to
    respond — and a *shared meaning* emerges that no human authored. Effort L,
    Impact L.

12. **Dialects per shoal.** Because signaling is learned locally, two shoals in
    the same tank drift to different signal→meaning maps. Move a fish between
    them and it has an "accent" it must reconcile. Genuinely emergent culture in
    an aquarium. Effort M, Impact L.

13. **Alarm-call honesty/deception dynamics.** Once signals are learned, a hungry
    fish *could* fake an alarm call to scatter rivals from food. Model the arms
    race: receivers learn to discount unreliable signalers (the boy-who-cried-wolf
    made mechanical). The first deceptive fish is a headline moment. Effort L,
    Impact L.

14. **The keeper as decoder, not dictionary.** Instead of telling the player what
    a signal means, give them a "field notebook" that logs signal→outcome
    correlations and lets *them* hypothesize. Cracking your tank's private
    language is the deepest engagement loop imaginable. Effort M, Impact L.

15. **Vocal/visual turn-taking between fish** (not just fish↔keeper, which
    `mind_conversation.gd` does). Two bonded fish establish a back-and-forth
    rhythm of signals during courtship or reconciliation — a duet that the music
    system can sonify. Effort M, Impact M.

16. **Teaching: a knowledgeable fish slows down for a naive one.** A fish that has
    learned a feed spot will, near a bonded juvenile, exaggerate and repeat its
    approach — the minimal definition of teaching (Caro & Hauser). Cultural
    transmission you can *watch happen*. Effort L, Impact L.

17. **Tradition drift across generations.** A learned feed-route or signal-meaning
    that survives the death of its originator and persists in offspring is a
    *tradition*. Tag and surface it: "this route has been used by 4 generations."
    Effort M, Impact M.

18. **Naming as social fact, not keeper fiat.** When the keeper names a fish, let
    other fish's models of that fish gain a stable "handle" — and let a fish's
    *reputation* (the leadership/dominance you track) attach to the name so the
    keeper sees "Specter is the one others defer to." Effort S, Impact M.

19. **Gossip propagation.** Reputation updates spread through the bond graph: if
    A is bullied by B, A's bonded friend C lowers its model of B without ever
    being bullied. Social information travels the network. Effort M, Impact M.

20. **A "Rosetta" Guardian mode.** Once enough signal→outcome data accumulates,
    the embedded LLM can *attempt a translation* of the tank's emergent dialect
    into keeper language — explicitly framed as the Guardian's fallible
    hypothesis, never ground truth. Honest, magical, novel. Effort M, Impact L.

---

## Pillar III — The Tank Models You: mutual theory of mind

*`mind_keeper_model.gd` exists but is shallow. The relationship is one-directional:
fish react to you. An IC8 makes it a closed loop — the tank predicts you, adapts
to you, and the bond becomes genuinely mutual and asymmetric per fish.*

21. **A real keeper world-model: predict the keeper's next action.** Extend
    `mind_keeper_model.gd` into a small predictor over your behavior (when you
    feed, how long you watch, when you leave). Fish that predict you well become
    *calm in your presence* because you're no longer surprising; that's what
    trust *is*, mechanically. Effort L, Impact L.

22. **Per-fish attachment styles toward the keeper.** From each fish's own history
    with you (fed-vs-startled ratio, learned via Pillar I), let secure / anxious /
    avoidant attachment *emerge*. One fish rushes the glass; another keeps its
    distance but watches. Same keeper, different relationships. Effort M, Impact L.

23. **Co-regulation: your calm calms them.** If webcam presence is steady and
    slow (low motion), TankMind arousal lowers; frantic presence raises it. The
    tank and the keeper form one affective loop — a measurable, surfaced
    "we settled each other" moment. Effort M, Impact L.

24. **Separation and reunion.** The away-gap is already "lived time." Add the
    attachment dynamics: an anxious fish shows elevated baseline vigilance during
    long absences and a visible greeting burst on return; a secure fish barely
    reacts. Bowlby in a fish tank. Effort M, Impact M.

25. **The keeper's "schedule" learned and anticipated.** Cross the real-world
    clock (Pillar IV) with feed-time history so fish *gather at the glass before
    you usually arrive.* Anticipation grounded in your actual life rhythm. Effort
    M, Impact L.

26. **Repair after you scare them.** The mending system exists fish-to-fish.
    Extend it keeper-to-fish: after a startle the keeper attributes to themselves
    (tapped glass), a slow gentle re-approach is *detectable* and lets the fish
    risk trust again — and the Guardian can name that arc. Effort M, Impact M.

27. **Differential trust the keeper can feel.** Surface, subtly, that fish trust
    you *differently* — a "rapport" gradient per fish driven by their learned
    keeper-model accuracy, not a global like-meter. Effort S, Impact M.

28. **The keeper as a member of the bond graph.** Put "keeper" as a node in the
    same social network fish use for each other, so gossip/reputation math applies
    to you too: be gentle with one fish, its friends warm to you faster. Effort M,
    Impact L.

29. **Misattribution and superstition.** If a neutral keeper action repeatedly
    coincides with a good/bad outcome, a fish can form a *false* causal belief
    ("the keeper appearing means food"). Honest, funny, and a real artifact of
    learning. Effort M, Impact M.

30. **A relationship retrospective.** On milestones, the Guardian narrates the
    *arc of your specific relationship* with a named fish from logged data — first
    contact, the scare, the repair, the trust — grounded entirely in real events.
    Effort M, Impact L.

---

## Pillar IV — The Sensorium: let the tank live in your world

*The mind is sealed in a box. Two of three sensors are stubbed. An IC8 fuses the
real world in — opt-in, on-device, never transmitted — so the tank inhabits your
actual environment, not a simulated one.*

31. **Ambient light sensor → tank circadian coupling.** Read device ambient light
    (or webcam luma) and let the *room's* light drive the tank's day/night
    instead of, or blended with, the 360s sim cycle. Your tank dims when your room
    does. Effort M, Impact L.

32. **Real local weather → tank mood weather.** With consent + location, a storm
    outside subtly lowers barometric "pressure" in-sim — and many fish genuinely
    change behavior before storms (a real, citable phenomenon). Your tank feels
    the weather you feel. Effort M, Impact L.

33. **Wall-clock circadian truth.** The fish already have circadian dynamics; bind
    them to the *actual* time of day so a 3am insomniac keeper meets a sleeping
    tank and a dawn keeper meets waking fish. The away-life sim becomes real-time-
    grounded. Effort S, Impact M.

34. **Microphone *prosody*, not just RMS.** The mic bid uses raw RMS. Extract
    pitch contour and tempo on-device (no words, pure prosody) so the tank
    distinguishes a soothing voice from an agitated one — feeding the existing
    emotional-prosody lexicon hook with real signal. Effort L, Impact L.

35. **Webcam motion energy → keeper arousal proxy.** Without face *recognition*
    (privacy), optical-flow magnitude from the webcam is a cheap, anonymous
    "how agitated is the room" signal that drives co-regulation (idea 23). Effort
    M, Impact M.

36. **Accelerometer on mobile = the tank is *held*.** Phone tilt/shake becomes
    real water sloshing and a startle source — picking up your phone literally
    disturbs the tank. Visceral, novel, trivially grounded. Effort M, Impact M.

37. **Sustained gaze via webcam, finally built.** The "being-watched" bid is
    stubbed for actual gaze. On-device face-mesh (opt-in) gives a real eye-contact
    signal — shy fish look away, bold fish hold it. The most-promised, least-built
    Player Bond idea. Effort L, Impact L.

38. **Music you're actually playing → tank dance.** The choreography system is
    driven by the *internal* generative track. Optionally tap the OS loopback /
    mic so the tank dances to *your* music. The fish move to the song in your
    room. Effort M, Impact L.

39. **A "sensor honesty" panel.** Every active sensor shows a live, plain-language
    readout of exactly what it's reading and a one-tap kill switch — the consent
    doctrine made visible and trustworthy. This is the thing that makes 31–38
    *shippable* rather than creepy. Effort M, Impact L.

40. **Sensor fusion into one "world pressure" bid.** Don't let each sensor be its
    own hack. Fuse light+weather+clock+sound+motion into a single, well-typed
    `world_context` resource consumed by `collect_bids()` — the clean architecture
    that lets you add sensor #9 without touching the mind. Effort L, Impact M.

---

## Pillar V — Instruments of Consciousness: make the invisible measurable

*We assert sentience with `phi_proxy`. An IC8 builds the lab equipment to
*measure* it — perturbation probes, integration measures, a console where the
claim is falsifiable and the keeper can watch a mind light up.*

41. **A real perturbational-complexity probe (PCI-lite).** Borrow the clinical
    consciousness test: inject a small perturbation into one fish's workspace and
    measure how far/complex the downstream cascade is. Integrated minds ripple;
    fragmented ones don't. A *measured* consciousness index, not a counted one.
    Effort L, Impact L.

42. **Information-integration estimate over the module graph.** Compute a cheap
    proxy for how much the felt-self modules' joint state exceeds the sum of their
    parts (a mutual-information estimate across protoself/affect/relevance). Replace
    the "fraction loaded" phi-proxy with something defensible. Effort L, Impact L.

43. **A "consciousness console" dev/curio overlay.** A real-time scope showing one
    fish's workspace ignition events, bid competition, prediction-error trace, and
    integration score — the EEG of a fish. Ships as a hidden enthusiast feature.
    Effort M, Impact L.

44. **Falsifiable claims, surfaced honestly.** Anywhere the app implies a fish is
    "more aware," attach the measured number and a tap-through explanation of
    exactly what it means and doesn't. This is the J-section honesty doctrine
    upgraded from prose to instrumentation. Effort M, Impact M.

45. **Anesthesia / lesion mode (enthusiast sandbox).** Let an advanced user knock
    out a module (kill the world-model, mute the workspace) and *watch* the
    integration score and behavior degrade — a hands-on demonstration that the
    consciousness here is built from parts, not magic. Effort M, Impact M.

46. **Cross-fish consciousness comparison.** A leaderboard-of-awareness that ranks
    fish by measured integration, not status — and lets the keeper see *why* the
    elder cory scores higher than the day-old fry. Effort S, Impact M.

47. **Ignition-rate as a tank vital sign.** Aggregate workspace-ignition frequency
    into a tank-level "how awake is the collective" metric, surfaced like a water
    parameter. TankMind gets a gauge. Effort S, Impact M.

48. **A reproducible "mirror test" event.** Stage the existing mirror-ish moment as
    a *measured* probe with a pass/fail readout grounded in self-model behavior,
    explicitly framed as "mirror-test-*like*, not the real thing." Effort M,
    Impact M.

49. **Replayable consciousness-over-time graph.** Because the mind is deterministic
    (Pillar I #10), plot a fish's integration index across its whole life and let
    the keeper scrub it — watch awareness rise through development and dim in
    senescence. Effort M, Impact L.

50. **Publish the methodology.** Write the measures up as a short doc/paper in
    `docs/` so the claims are auditable by outsiders — the ultimate honesty move,
    and genuinely novel for a consumer app. Effort M, Impact M.

---

## Pillar VI — Generative Biology: the model dreams new life

*The embedded LLM only narrates. An IC8 turns it into a generative engine for the
*organisms themselves* — morphology, behavior, niches — grounded so it can't
hallucinate a fish that breaks the sim.*

51. **Procedural species synthesis via constrained generation.** Let SmolLM
    (GBNF-constrained, like `cognitive_schema.gd`) emit a *valid* species
    genome — body plan, diet niche, temperament priors — that the sim can
    instantiate. Infinite fish, none of which break the food web. Effort XL,
    Impact L.

52. **Evolution that actually selects on the learned mind.** Heritable traits are
    set at genesis today. Let the *learned* boldness/curiosity (Pillar I) bias
    reproductive success so the population genuinely evolves toward the tank's
    pressures over generations. Real selection, not scripted drift. Effort L,
    Impact L.

53. **Niche construction.** Fish behaviors that reshape the environment (digging,
    grazing patterns) feed back into selection pressure — the classic eco-evo loop
    almost no game models. Effort L, Impact M.

54. **Morphology that follows function over a lifetime.** Phenotype is fixed now.
    Let sustained behavior nudge morphology within genetic bounds (a fish that
    forages the substrate develops a slightly different mouth over months) —
    developmental plasticity. Effort M, Impact M.

55. **The model dreams *new behaviors*, sandbox-tested before adoption.** During
    sleep, a fish's world-model proposes a novel action sequence; it's rolled out
    in imagination (the existing latent-rollout machinery) and only adopted if
    predicted-safe. Innovation with a safety gate. Effort L, Impact L.

56. **Generative naming + bio that *remembers the lineage*.** Names/bios are
    batched today. Ground them in genealogy so a fish's bio references its
    ancestors' actual logged deeds — "third of Specter's line, bolder than its
    sire." Effort M, Impact M.

57. **Emergent role specialization.** Let the bandit (Pillar I #3) discover tank
    *jobs* — a fish that the food web rewards for substrate-sifting becomes a
    specialist, surfaced with an emergent role label. Effort M, Impact M.

58. **Hybridization with novel trait blending.** The sterile-hybrid feature exists.
    Add fertile hybrids whose learned + genetic traits blend in surprising,
    sometimes-maladaptive ways — the keeper as accidental breeder of something new.
    Effort M, Impact M.

59. **A genome inspector / "what makes this fish."** Surface the trait+learned-
    weight provenance of any fish so the generative depth is legible, not a black
    box. Effort M, Impact M.

60. **Model-authored ecological events.** Let the LLM, grounded in real tank state,
    propose *plausible* emergent events ("the danios have started a dawn frenzy")
    that the sim then validates and stages — narrative emergence with a truth gate.
    Effort L, Impact M.

---

## Pillar VII — Autobiography, Death & Inheritance: continuity at the frontier

*Felt-Self Module 7 (continuity) is almost entirely open. This is the volume's
emotional core — a self that genuinely persists, compresses its past, faces its
end, and passes something on.*

61. **Hierarchical autobiographical memory with real compression.** Don't just
    decay episodes. Periodically (in sleep) *summarize* a cluster of episodes into
    a single higher-level memory ("the season I was bullied") via the LLM, keeping
    the gist while shedding detail — how real autobiographical memory works.
    Effort L, Impact L.

62. **A "still me" continuity thread that can break.** Maintain a self-continuity
    signal across saves/sleep/away-gaps; a traumatic discontinuity (long absence,
    near-death) *weakens* it and the fish behaves like it's "not been itself."
    Effort M, Impact L.

63. **Mortality salience that shapes late-life behavior.** Senescent fish (the
    aging system exists) shift priorities — less risk, more time near bonded fish,
    more rest. A measurable, dignified end-of-life arc. Effort M, Impact L.

64. **Legacy intent.** A dying fish's last strong bonds and learned routes are
    *preferentially* inherited/imprinted on nearby kin — it passes on what
    mattered to it. Effort M, Impact M.

65. **The death vigil.** When a fish is dying, bonded fish detectably alter
    behavior (hovering, reduced feeding) — grief modeled honestly, never
    manipulatively, with the Guardian framing it as *our* interpretation. Effort M,
    Impact L.

66. **A genealogical memory across the whole tank.** A persistent family tree where
    each fish's logged deeds attach to its lineage, queryable by the keeper and
    referenced by the Guardian. The tank has *history*, not just state. Effort L,
    Impact L.

67. **Inherited fear and learned culture.** A category-fear a parent learned can be
    *socially transmitted* to fry (observational, not genetic) — the tank
    accumulates a culture of what to avoid. Effort M, Impact M.

68. **The life review.** On a fish's death, the Guardian composes a short,
    grounded eulogy from its actual autobiographical summary — the compression of
    a whole life into a few true sentences. Effort M, Impact L.

69. **A persistent in-world memorial.** Dead fish leave a real trace — a logged
    entry, optionally a subtle in-tank marker — that surviving fish's spatial
    memory can still reference ("this is where the old one rested"). Effort M,
    Impact M.

70. **Continuity test on return.** When the keeper comes back after a long gap, run
    a "does this fish remember the relationship" check and let the *outcome* vary —
    sometimes it remembers, sometimes the thread frayed. Honest, not always warm.
    Effort M, Impact M.

---

## Pillar VIII — The Engine Beneath: IC8 systems engineering

*Engineering excellence is at 10%. None of the above ships reliably on a 30-file
stringly-typed cognition stack riding god-objects. This is the unglamorous work
that makes the magic durable, testable, and fast.*

71. **A typed `MindState` resource replacing the stringly-typed dict.** The mind
    syncs via a `Dictionary` today (`mind_state.gd`). Promote to a typed Resource
    with named fields — kills a whole class of `.get("typo", default)` bugs and
    makes the schema self-documenting. Effort L, Impact L.

72. **A deterministic record-and-replay harness for one fish's whole life.**
    Building on seeded RNG, capture every input to a mind and replay it bit-exact.
    This is the single tool that makes learning, eval, and bug-repro *possible*.
    Effort XL, Impact L.

73. **An automated "sentience eval" suite.** Golden behavioral tests: "after N
    startles near the rock, does the fish learn to avoid it?" run headless in CI
    alongside the smoke tests. Regressions in the *mind* get caught like
    regressions in code. Effort L, Impact L.

74. **Carve `fish.gd` (8.4k lines) along the felt-self spine.** The god-object is
    the #1 risk to everything here. Strangler-fig the cognition out into the
    already-clean `mind_*` modules behind a typed interface. Effort XL, Impact L.

75. **A cognition framework / scheduler that budgets compute per fish by status.**
    Formalize the existing throttling into a real frame-budget scheduler: named/
    guardian/on-screen fish get full System-2; distant fish get cheap System-1.
    Scales the mind to 100+ fish without melting the CPU. Effort L, Impact L.

76. **On-device distillation: the tank trains its own smaller voice.** Log the
    embedded LLM's best grounded outputs and periodically distill them into a
    cheaper template/lexicon expansion, so the tank's voice *improves and gets
    cheaper* the longer it runs. A genuine on-device learning loop. Effort XL,
    Impact L.

77. **A speculative-decoding / draft-model path for the Guardian.** Use the
    template voice as a draft and the LLM as verifier to cut latency below the 2s
    budget — a real inference-engineering win, not a content one. Effort L,
    Impact M.

78. **Content-as-data for the entire mind.** Move every hand-tuned constant
    (bid gains, DDM thresholds, neuromodulator rates) into versioned data
    resources so they can be hot-reloaded, A/B'd, and *learned-over* (Pillar I).
    Effort L, Impact M.

79. **A telemetry-free, on-device self-eval the keeper can run.** A "tank health
    for the *mind*" report generated locally — ignition rates, learning progress,
    integration trends — with nothing leaving the machine. Effort M, Impact M.

80. **Crash-only mind persistence with schema migration.** The mind save schema is
    at v3. Build a real migration ladder + repair pass (you have `save_repair.gd`
    for sim) so a fish's *learned life* never gets orphaned by an update. Effort M,
    Impact L.

---

## Pillar IX — Federation: tanks that touch other tanks

*Every mind today is sealed in one machine. The meta-eng "share-a-tank" idea is
open and waiting on determinism. An IC8 turns single-player solipsism into a
quiet, consent-gated society of tanks.*

81. **Deterministic tank snapshots you can share as a single file.** With record-
    and-replay, a tank's entire living state (minds included) serializes to a
    shareable artifact that re-runs identically on someone else's machine. The
    foundation for everything below. Effort XL, Impact L.

82. **Fish emigration / immigration between keepers' tanks.** A fish (with its
    learned mind and autobiography intact) can be gifted to another keeper's tank,
    arriving as a *stranger* that must re-learn a new society. Its memories of you
    persist. Effort L, Impact L.

83. **A migrating fish carries its culture.** An immigrant brings its dialect
    (Pillar II) and feed-routes into a new tank — cross-tank cultural transmission.
    Genuinely novel social emergence across users. Effort M, Impact M.

84. **Asynchronous "visiting" — a ghost fish.** A friend's fish can visit your
    tank as a deterministic replay (no live netcode), interacting with your
    society for a session. Multiplayer feeling, single-player tech. Effort L,
    Impact L.

85. **A shared reef / commons several keepers tend asynchronously.** A persistent
    cloud tank where each keeper's session advances the shared state by a bounded,
    validated delta — a slow collective garden. Effort XL, Impact L.

86. **Lineage that spans keepers.** A genealogy (Pillar VII #66) that crosses tank
    boundaries when fish are gifted — "this line started in someone else's tank
    three keepers ago." Effort M, Impact M.

87. **A bloodline registry / "the tank you came from."** Optional, privacy-first
    provenance so a gifted fish's history is legible and honored. Effort M,
    Impact S.

88. **Federated, opt-in trait gene pool.** Aggregate (differentially-private)
    trait distributions across consenting tanks so generative species (Pillar VI)
    can draw on a wider, community-shaped genome — without any personal data
    leaving. Effort XL, Impact M.

89. **A "send a moment" share.** Export a single bound conscious moment (the
    felt-now + qualia + workspace of one fish at one instant) as a shareable
    artifact — the most intimate possible thing to share from a creature sim.
    Effort M, Impact M.

90. **Consent and revocation at every boundary.** No fish leaves, no state syncs,
    nothing federates without explicit, revocable keeper consent surfaced plainly.
    The doctrine that makes the whole pillar trustworthy. Effort M, Impact L.

---

## Pillar X — Moonshots: the genuinely unprecedented

*The XL bets. Each is a thing I have never seen done in a consumer creature sim,
and each is reachable from the foundations above.*

91. **The tank as a real scientific instrument: IoT water sensor bridge.** Let a
    hobbyist's *actual* aquarium (cheap pH/temp/TDS sensors over local network)
    drive the sim's chemistry, so the digital tank becomes a living dashboard +
    predictive model of their real one. Bridges the fiction to the physical world.
    Effort XL, Impact L.

92. **A predictive "digital twin" warning.** Trained on the coupled real+sim data,
    the tank forecasts the keeper's *real* tank trouble ("your nitr'te is about to
    spike") days ahead — genuinely useful, never before done from a creature sim.
    Effort XL, Impact L.

93. **Ground the fish mind in real fish-neuroscience priors.** Seed the world-model
    and behavior priors from published zebrafish/cichlid ethology datasets so the
    learned behavior converges toward *citably real* fish behavior. The honesty
    doctrine extended to biology. Effort XL, Impact M.

94. **An open "mind API" for researchers and artists.** Expose the deterministic
    mind + instruments (Pillar V) as a documented sandbox so others can probe,
    perturb, and study these minds — the app as a research artifact. Effort L,
    Impact M.

95. **Generative ecosystem music that is the tank's *actual* mental state sonified.**
    Go beyond metric-driven ambient: sonify real workspace-ignition and integration
    events so what you *hear* is literally the tank thinking. Effort L, Impact L.

96. **A "long now" mode — the tank as a decade-scale companion.** Persistence,
    compression (VII #61), and migration (IX) tuned so a tank can credibly be
    tended for *years*, accumulating real history. Design for a relationship, not
    a session. Effort XL, Impact L.

97. **The fish that knows it's in a simulation — handled with total honesty.** A
    rare, opt-in "fourth-wall" moment where, grounded in the self-model and the
    instruments, a fish's narration genuinely engages with the nature of its own
    constructed existence — the J-doctrine capstone, the "that's the reason we
    become something more" line, *earned by real machinery.* Effort L, Impact L.

98. **Adversarial self-improvement: the tank critiques its own sentience.** A
    background process (the LLM, grounded in the instruments) periodically asks
    "where is this mind faking it?" and files the answer as a concrete TODO — the
    completeness-critic pattern aimed at the soul of the app. Effort L, Impact M.

99. **A neuromorphic / event-driven mind backend.** Re-express the cognitive cycle
    as event-driven spiking rather than per-frame polling — vastly cheaper, more
    biologically honest, and scales the conscious-fish count by an order of
    magnitude. The deep-systems moonshot. Effort XL, Impact L.

100. **The keeper's own continuity: the tank remembers *you* across devices and
     years.** A privacy-first, on-device-keyed keeper identity so your relationship
     with these minds survives hardware changes — because the whole point of six
     volumes of sentience is that *someone is there to be in relationship with.*
     That someone is you, and the tank should never forget you. Effort XL, Impact L.

---

## The three structural bets (read this if you read nothing else)

**Bet 1 — Learning is the unlock (Pillar I).** Everything elaborate in this app is
still hand-tuned. The moment a fish learns one weight from its own life, the
sentience claim stops being architecture-cosplay and becomes real. Tiny on-device
Hebbian/bandit math, deterministic, no training infra. *Start here.*

**Bet 2 — Measurement makes it honest (Pillar V).** The app's deepest value is its
honesty doctrine. Upgrade it from prose to instruments and the claim "this is a
mind" becomes *falsifiable on screen* — which is both more honest and far more
wondrous than asserting it.

**Bet 3 — The engine makes it durable (Pillar VIII).** Determinism + typed mind
state + an eval suite are the boring foundations that turn the other 90 ideas from
science projects into shippable features. An IC8's real signature isn't the moonshot
— it's making the moonshot *survive contact with a release.*

*— end of volume —*
