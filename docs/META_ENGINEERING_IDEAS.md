# Meta-engineering — 100 staff/principal-level swings

*Drafted 2026-06-28.* A holistic, ground-up engineering sweep aimed one altitude
**above** the two sibling docs. This file deliberately does **not** repeat
[ENGINEERING_EXCELLENCE_IDEAS.md](ENGINEERING_EXCELLENCE_IDEAS.md) (god-object
carve, typed contracts, verification gating) or
[SYSTEMIC_IMPROVEMENTS_IDEAS.md](SYSTEMIC_IMPROVEMENTS_IDEAS.md) (supply chain,
sim-rust fate, accessibility, docs nav). Treat those as the *table stakes*; treat
this as the *ambition*.

The throughline: turn walstad loom from **a beautiful aquarium game** into
**a sentience engine + ecosystem framework** — something where the mind is a
reusable cognition kernel, the sim is a deterministic replayable engine, content
is data not code, and the whole thing runs 10× lighter so the fish can think 10×
harder. The kind of architecture that makes a platform team jealous, not a demo.

Tags: Effort **S** (≤½ day) · **M** (1–3 days) · **L** (week+) · **XL** (epic).
Impact: **S** polish · **M** noticeable · **L** transforms · **XL** redefines.

Anchors cite real files in `shaders-godot/godot-project/scripts/` unless noted.

---

## A. Make the mind *genuinely* more sentient (predictive, social, self-aware)

The current kernel (`mind_cycle.gd`, `global_workspace.gd`, `fish_mind.gd`) is a
clean GWT bidder with episodic memory and a 6-D linear world model. It *looks*
sentient. These items make it *behave* sentient — closing the loop between
prediction, surprise, learning, and action so intelligence is earned, not faked.

- [ ] **1. Active inference as the action-selection core.** Today `mind_world_model.gd`'s `expected_free_energy_explore()` computes info-gain but is read-only. Make **expected free energy** the bid currency in `global_workspace.gd`: fish act to minimize surprise *and* seek information. This single change turns curiosity, foraging, and caution into one principled objective instead of three hand-tuned drives. *XL · XL*
- [x] **2. Prediction-error as a first-class salience signal.** `world_model.error` exists but never enters bidding. Route it in as a "novelty/uncertainty" bid so a fish genuinely orients toward what it can't predict — the difference between a scripted "investigate" timer (`fish.gd:1700`) and real attention. *M · L* — **shipped:** `uncertainty` bid in `global_workspace.gd` from `_prediction_error` / world model.
- [ ] **3. Upgrade the world model from 6-D linear to a tiny recurrent predictor.** Replace the linear map in `mind_world_model.gd:45–63` with a 16–32 state GRU-lite (hand-rolled, no deps) that predicts next interoceptive state. Persists per-fish; learns multi-step dynamics, not just decay constants. *L · L*
- [x] **4. Theory of mind that predicts, not just labels.** `fish_mind_science.gd:78–108` stores `inferred_states[other]="threat"`. Promote it to a 1-step behavioral predictor per neighbor ("Red usually charges when I enter its corner") and feed the prediction into approach/avoid. Cheap Bayesian filter, enormous perceived-intelligence payoff. *L · XL* — **Shipped 2026-06-29 (Tier-1):** `fish_mind_science.tick_theory_of_mind` now learns a per-neighbour `charge` tendency (EMA over closing-distance + aimed-at-me when threat/dominant), `_tom_pred`/`_tom_alert` on Fish; `collect_predict_bid` raises an ANTICIPATORY threat bid in `collect_bids` so the fish flees a learned charger before contact (ablatable via #14). Smoke `smoke_theory_of_mind.gd` (learns charger / anticipatory bid / ablation gate / non-approaching control).
- [x] **5. Inter-fish signaling channel (a proto-language).** There is currently **zero** fish↔fish communication. Add a tiny discrete signal bus (alarm / food / mate / submit) that fish emit and neighbors learn to interpret over time. Schooling stops being hardcoded flocking and becomes *learned coordination*. *L · XL* — **Shipped 2026-06-28 (Tier-1/1D):** `fish_signals.gd` — 4 state-driven signals (alarm/food_found/mate_call/submit), 8u radius, ~3s linger; a fish emits + scans neighbours in `_update_inner_life` before the attention phase, the loudest heard signal enters `collect_bids` as a salience-weighted bid (intersubjectivity → workspace), and a per-fish reliability table learns trust (reinforced when a heard alarm precedes real fright). Smoke `smoke_fish_signals.gd` (emit/receive/range/learn/integration) + 9 cognition smokes green.
- [x] **6. Metacognitive gating: confidence actually changes behavior.** `mind_self_model.gd:20` computes confidence and throws it away. Use it as the drift-diffusion commitment threshold (`fish_mind.gd:175–217`): low-confidence fish gather more evidence before committing, reading as visible hesitation and deliberation. *S · L* — **shipped:** `ddm_threshold()` scales up when `_mind_self_model.confidence` is low.
- [x] **7. Φ (integration) feeds back into risk.** `fish_binding.gd:62–71` reduces the phi proxy under extremis but logs it only. Inject phi as a risk modulator — a "fragmented" fish becomes conservative. Makes the felt-self layer *causal* instead of decorative. *S · M* — **shipped:** low-Φ dampens food/novelty/mate bids; fragmented boosts threat in `global_workspace.gd`.
- [ ] **8. Sleep that consolidates episodic → semantic.** `episodic_memory.gd` does FIFO pruning + TD heatmap replay. Add real systems-consolidation: cluster episodes into reusable schemas during the night rest state so a fish wakes with *generalized* rules ("the top-left is dangerous at dawn"), not just raw episodes. *L · L*
- [x] **9. Multi-goal blending instead of binary approach/avoid.** Deliberation is currently a 2-choice DDM. When two workspaces co-ignite (hungry *and* scared), synthesize a blended motor vector (skirt the edge toward food) rather than oscillating. This is the single biggest "these fish seem to actually think" upgrade. *M · L* — **Shipped 2026-06-28 (Tier-1/1C):** `GlobalWorkspace.blend_behavior_bias()` — when the workspace holds >1 winner, per-goal biases (`_bias_for`, refactored pure) sum salience-weighted (primary full, secondaries ×0.6) into one skirt vector; `broadcast` routes co-ignition to it, a lone winner reduces exactly to the old single-goal bias. Smoke `smoke_motor_blend.gd` (food+threat → keeps +food, folds in −threat, primary leads) + 7 cognition smokes green.
- [x] **10. Emotional contagion across the school.** Stress/affect are per-fish islands. Let arousal propagate through neighbors (one fish bolts → the school's baseline arousal ticks up, decays over seconds). Turns 60 independent agents into one visibly-coupled organism. *M · L* — **Shipped 2026-06-28 (Tier-1):** `mind_contagion.gd` — arousal (fast) + mood (slow) drift toward the proximity-weighted neighbour mean, scaled by social susceptibility; a damped pull (converges, never self-amplifies); ticked in `_update_inner_life` (ablatable via #14). Smoke `smoke_contagion.gd`.

## B. Turn the mind into a reusable *cognition framework* (not bolted to fish.gd)

The mind modules are stateless functions whose state all lives in `fish.gd`
fields, synced through `MindState`/`MindChannel`. That's a great start but it
means the kernel can't run on anything that isn't a Fish. Make it a library.

- [x] **11. `CognitionKernel` — one entry point, mutable state struct in/out.** Extract the perceive→attend→bind→encode→learn sequence into a single `CognitionKernel.tick(mind_state, percept) -> mind_state` with **no Fish dependency**. Fish, Guardian, snail, even the tank itself become hosts. This is the keystone the other 9 in this section hang off. *L · XL* — **foundation:** `cognition_kernel.gd` + `fish.gd` calls `run_bind_encode_learn`; full perceive→attend path still via `MindCycle` adapters.
- [ ] **12. A bid-generator registry (plugin attention).** `global_workspace.gd` hardcodes its bid sources. Make bid generators registerable so a new drive (territoriality, play, grief) is a 30-line plugin, not a kernel edit. Mods and experiments slot in without touching the core. *M · L*
- [ ] **13. Module dependency DAG + topological tick order.** The felt-self spine order is enforced by hand in `felt_self_layer.gd`. Declare module deps as data and topo-sort the tick — adding a module can't silently break ordering, and the order becomes inspectable/testable. *M · M*
- [x] **14. Per-module ablation switches, not one big toggle.** `TankConfig` has coarse `consciousness_*` flags. Give every cognitive module an independent enable so you can A/B "does theory-of-mind actually change observed behavior?" — turning the mind into an experimental apparatus, not a black box. *S · M* — **Shipped 2026-06-28 (Tier-1/1E):** `mind_ablation.gd` per-module enable flags (signals/contagion/theory_of_mind/world_model), gated in `_update_inner_life` + the active-inference bid; verified by lesioning the world-model and watching the free_energy drive vanish/return (`smoke_cognition_framework.gd`).
- [x] **15. Deterministic, seedable cognition.** Thread a per-fish PRNG seed through the kernel so a given (state, percept, seed) always yields the same decision. Unlocks golden-trace tests, replay, and debugging — currently impossible because cognition reads global RNG. *M · L* — **foundation:** `mind_rng.gd` + cognition/behavior streams; `smoke_cognition_kernel.gd`.
- [ ] **16. Package the kernel as a standalone Godot addon.** Once #11 lands, ship `addons/cognition_kernel/` with zero game deps + a 50-line demo scene (a dot that forages). This is the artifact that makes the architecture *legible to the outside world* (talks, hiring, open-source). *M · XL*
- [ ] **17. Mind schema versioning + migration chain.** `MindState.SCHEMA_VERSION=3` exists but there's no migration. Add a `MindMigration` ladder so a v3 save loads into a v5 kernel with new felt-self fields defaulted — no silent `.get(k, default)` degradation. *M · M*
- [x] **18. A cognition trace bus.** Emit a structured per-tick event (bids, winner, ignition, decision, surprise) on a ring buffer. Powers the debugger (#61), the eval harness (#67), and replay — and costs ~nothing when no listener is attached. *M · L* — **Shipped 2026-06-28 (Tier-1/1E):** `mind_trace.gd` cap-bounded ring buffer; structured event (focus/ignition/winners/surprise/pred_err) emitted from `mind_cycle` when enabled, true no-op when off; `smoke_cognition_framework.gd` covers no-op/cap/order/real-cycle.
- [ ] **19. Promote Guardian's generative model to all fish (opt-in).** `guardian_generative.gd`'s free-energy math runs for the Guardian only. Once the kernel is host-agnostic (#11), any fish can opt into the richer model under a perf budget — graduated intelligence instead of one special fish. *M · L*
- [ ] **20. Cognition LOD tiers as a first-class concept.** Define explicit tiers (T0 reflex-only, T1 GWT, T2 +world-model, T3 +LLM voice) and assign by salience/visibility/budget. The off-frustum phase hack in `sim_driver.gd:3222` becomes a principled scheduler input instead of a special case. *M · L*

## C. Make the whole game *fast* (10× headroom = 10× more thinking)

The Explore pass found the cost is dominated by per-voxel materials and
per-fish brain ticks. Win the frame budget and you can afford the Section A
mind upgrades. Targets are concrete and measured.

- [x] **21. MultiMesh the fish body (50 nodes → 1 draw call).** Each fish is ~50 `MeshInstance3D` + a duplicated `ShaderMaterial` per voxel (`fish.gd:2814`). Rebuild voxel bodies as one `MultiMeshInstance3D` per fish with per-instance color. ~98% fewer draw calls and materials; the single biggest rendering win available. *L · XL* — **shipped via** `fauna_voxel_builder.gd` + `voxel_batch.gd` (MultiMesh per pivot×material); per-voxel stress tint still a follow-up (#26).
- [ ] **22. Shared material pool keyed by (shader, palette slot).** `VoxelMat.make_*` mints a new material per voxel everywhere (`fish.gd`, `plant.gd:755`). Pre-allocate a pool and hand out references. Kills ~200ms of startup material churn and the per-frame stress-flush cost. *M · L*
- [ ] **23. GPU compute boids.** `_boids()` (`fish.gd:6761`) is 6–24ms/tick of CPU vector math. Move separation/alignment/cohesion to a compute shader over position/velocity storage buffers — 5–10× on that path, and it scales to 200+ fish. *L · L*
- [ ] **24. Time-slice the brain across frames.** `sim_driver.gd` ticks all fish in one 10Hz burst (a 15–30ms spike). Round-robin N/10 fish per frame with a deferred event-resolution phase. Same total work, frame variance collapses from 20ms to 2ms. *M · L*
- [ ] **25. SoA hot-state arrays for the sim core.** Pull the ~8 fields the sim actually iterates (pos, vel, heading, hunger, stress, species, age, flags) into `Packed*Array` columns. Cache-friendly + SIMD-friendly; OOP `Fish` keeps the cold fields. Foundation for everything else in this section. *XL · XL*
- [ ] **26. Stress-flush early-out + per-instance tint.** `_apply_stress_flush()` (`fish.gd:5782`) walks every voxel every frame when stressed. Gate on a dirty flag and push tint as a per-instance MultiMesh param (pairs with #21) instead of per-voxel material writes. *S · M*
- [ ] **27. Distance LOD on creature bodies.** No LOD today. Swap far fish to a 6-voxel proxy or a billboard; reduce plant voxel detail past a radius. ~50% voxel reduction off-screen for free smoothness in big tanks. *M · M*
- [ ] **28. WorkerThreadPool for the substrate + chemistry diffusion.** `SubstrateGrid.tick()` (1.5–3ms) and water chemistry are embarrassingly parallel grid stencils. Run them on `WorkerThreadPool` and join before the write-back phase. *M · M*
- [ ] **29. Pool the particle systems (pearling, ripples, dust).** `plant.gd:1001` duplicates material+mesh per pearling emission (~300/sec). Keep a recycled pool of `GPUParticles3D` nodes; reparent and reset instead of allocating. *M · M*
- [x] **30. Cache results keyed by sim-minute, not recomputed per fish.** `feed_anticipation_active()` (`sim_driver.gd:534`) re-scans history for every fish every tick. Compute tank-global derived values once per sim-minute and broadcast. Class of fix: hoist anything O(fish) that's actually tank-global. *S · M* — **shipped:** wall-clock minute cache on `feed_anticipation_active()`.

## D. Make the sim a deterministic, replayable *engine*

Right now sim and render are entangled and RNG is global, so you can't record,
replay, or test trajectories. Separating authoritative sim from presentation is
the move that unlocks testing, debugging, multiplayer, and trust.

- [x] **31. Single authoritative seeded RNG with named streams.** Replace ambient `randf()` calls with an injected `SimRng` carrying independent streams (genetics, behavior, events). Same seed → same tank, forever. The precondition for every item below. *M · XL* — **foundation:** `sim_rng.gd`, `sim_driver.rng`, fish/mind paths migrated; ambient `randf()` in world/plants/shrimp still a backlog sweep.
- [ ] **32. Fixed-timestep authoritative tick, decoupled from render.** Formalize the 10Hz sim as the source of truth with render interpolating between snapshots. Removes time-scale substep drift (`fish.gd:5818`) and makes the sim frame-rate-independent and reproducible. *L · L*
- [ ] **33. Record/replay: serialize the input+event stream, not the state.** Capture (seed, keeper actions, timestamps); replay reconstructs the exact tank. A 2KB recording reproduces a 50MB tank — and a crash report becomes a perfect repro. *L · XL*
- [ ] **34. Time-travel scrubber for debugging.** With #32+#33, snapshot every N seconds and let a dev scrub the tank backward/forward. Watch *why* the fish died, not just that it did. A debugging superpower no aquarium game has. *L · L*
- [ ] **35. Headless fast-forward / soak as a supported mode.** `dev/balance_soak.gd` exists; promote it to a first-class `--simulate days=30 seed=X` headless mode that emits a metrics CSV. Balance tuning becomes data, not vibes. *M · L*
- [ ] **36. Conservation-law assertions baked into the tick (debug build).** The trophic ledger tracks produced/consumed/recycled/lost. Assert mass-balance invariants every tick in debug builds so an ecology bug trips immediately at its source, not 10 minutes later as a mystery crash. *M · M*
- [ ] **37. Sim/render contract: render reads, never writes sim state.** Audit and enforce that `_process` visual code never mutates authoritative fields (today motion + sim are interleaved in `fish.gd`). Clean read-only boundary makes threading (#28) and replay safe. *M · L*
- [ ] **38. Snapshot diffing for save efficiency + cloud sync.** Once state is structured, store deltas between snapshots instead of full 50MB dumps. Smaller saves, cheap autosave, and the basis for cloud/shared tanks. *L · L*
- [ ] **39. Property-based fuzzing over the tick.** Generate random valid tanks, run M ticks, assert no NaNs / no negative populations / O₂ in bounds. Catches the ecological edge cases manual play never reaches. *M · L*
- [ ] **40. Speculative "what-if" forks.** Because the sim is deterministic and forkable, let the Guardian (or a tutorial) simulate "if you don't fix O₂, here's day +3" in a hidden fork and narrate the consequence. Predictive care advice grounded in the *actual* engine. *L · XL*

## E. Content as data, not code (a real pipeline + modding)

`tank_config.gd` (3k LOC) inlines every species, preset, palette, and tuning
const. `data-schemas/` has JSON schemas that nothing consumes. Close that gap and
content becomes hot-reloadable, moddable, A/B-testable, and community-extensible.

- [ ] **41. Species library loads from JSON validated by `fauna.schema.json`.** Make the schema the source of truth and `tank_config.SPECIES_LIBRARY` a fallback. Adding a fish becomes a data file, not a code edit + rebuild. *L · L*
- [ ] **42. Hot-reload content from `user://mods/`.** Watch the mods dir; reload species/plants/palettes live without restart. Turns balance tuning and modding into a tight feedback loop instead of a build cycle. *M · L*
- [ ] **43. Preset composition via inheritance.** Presets are flat dicts with massive duplication. Let `advanced_planted = vessel(rimless_60) + stocking(high_tech) + lighting(co2)`. Fewer bugs, trivial new variants. *M · M*
- [ ] **44. Content-addressable, signed mod packs.** Hash + optionally sign mod bundles (reuse the supply-chain SHA256 tooling). Shareable, verifiable community content without arbitrary-code-execution risk. *M · L*
- [ ] **45. Schema-validate saves on load.** The save loader trusts whatever's on disk (`tank_saves.gd`). Validate against schema + clamp before the sim sees it, so corrupt/edited saves fail loud and safe, not as in-sim surprises. *M · M*
- [ ] **46. A balance-tuning console / live knobs.** Expose chemistry/population constants through a dev panel bound to the data layer so you retune `nh3_to_no2` etc. at runtime and watch the curve move. Pairs with #35's metrics. *M · M*
- [ ] **47. Procedural species generator from the genome space.** The genome ranges are already defined. Generate plausible novel species (color, finnage, behavior genes) from the constrained space — infinite stocking variety, "Surprise Me" with real depth. *M · L*
- [ ] **48. Localization-ready content strings.** Pull narration templates, species names, UI copy into a string table now, while content is being dataified — retrofitting i18n later is 10× the work. *M · M*
- [ ] **49. Content versioning + dependency resolution for mods.** A mod declares "needs core ≥ v6, conflicts with X." Standard package-manager hygiene that prevents the modding ecosystem from becoming a support nightmare on day one. *M · M*
- [ ] **50. Author-time content linter.** A schema-aware checker that flags "this scenario stocks above its mature carrying capacity" (the H7 audit, automated) before the content ships. Catches GOALS.md §H7-class bugs at author time. *M · L*

## F. Persistence & history as an event-sourced *life record*

Saves are atomic-write snapshots today — good, but the tank's *story* is computed
and discarded. Treat the tank's life as an append-only event log and the entire
"this is a tended living thing" metaphor gets a durable spine.

- [ ] **51. Event-sourced tank history (append-only log).** Births, deaths, spawns, crashes, keeper actions become immutable events. The current `story_events` ring buffer is the lossy version of this; make it the durable source and derive state + diary + stats from it. *L · L*
- [ ] **52. Derived projections instead of stored aggregates.** Population graphs, anniversary stats, lineage trees all re-derive from the event log — one source of truth, no drift between the diary and reality. *M · M*
- [ ] **53. Lineage as a first-class queryable graph.** `lineage_tree_view.gd` reconstructs ancestry; back it with a real parent-edge store so "show me every descendant of the founder pair" is a query, not a re-walk. *M · M*
- [ ] **54. Cloud save + share-a-tank.** With deterministic state (#31) and deltas (#38), a tank is portable. Let players publish a tank others can load and watch continue — the "visit other people's tanks" backlog idea, finally tractable. *XL · XL*
- [ ] **55. Crash-to-repro pipeline.** On an unhandled error, auto-bundle the event log + seed. Every bug report becomes a deterministic replay you can scrub (#34). *M · L*
- [ ] **56. Multi-device continuity.** Event log + cloud means a tank lives across desktop/phone, continuing its independent life — the "it managed while you were gone" promise extended across devices. *L · L*
- [ ] **57. Save-format soak test in CI.** Generate a tank, save, load, assert byte-identical projections. Wire to CI so a save regression can never ship silently. *M · M*
- [ ] **58. Compaction + retention policy.** Old events compact into periodic snapshots so a 2-year-old tank's log doesn't grow unbounded — keep the milestones, summarize the noise. *M · M*
- [ ] **59. Export a tank's life as a shareable artifact.** Render the event log into a timelapse/diary export (video or web page). The emotional payload of "here's my tank's year" is a viral loop competitors can't copy without this spine. *L · L*
- [ ] **60. Tamper-evident history.** Hash-chain the event log so a shared/published tank's claimed history is verifiable — quietly important once tanks are social. *M · S*

## G. Observability, evaluation & the "is it actually sentient?" question

You can't improve sentience you can't measure. Build the instruments. This is the
section that separates "we vibe-tuned some fish" from "we have a rigorous
cognition platform."

- [ ] **61. A live mind debugger overlay.** Click a fish → see its workspace bids, winner, world-model prediction vs reality, current goal, top memories. Powered by the trace bus (#18). The single best tool for developing Section A. *M · L*
- [ ] **62. Frame-budget governor with graceful degradation.** A central scheduler tracks ms spent in sim/mind/render and auto-drops cognition LOD (#20) under pressure, instead of stuttering. The tank never janks; it just thinks a little less when busy. *M · L*
- [ ] **63. Cognition eval harness ("sentience benchmarks").** Scripted scenarios with measurable expectations: does a fish learn the feed corner in N trials? avoid a bully? explore an unpredictable zone? Turns "more sentient" into a number you can move. *L · XL*
- [ ] **64. Behavioral-diversity metric.** Measure entropy of fish trajectories/decisions — guards against the failure mode where "smarter" fish all converge to identical optimal behavior and the tank feels robotic. *M · M*
- [ ] **65. Opt-in anonymized telemetry.** Aggregate which scenarios crash, where players intervene, which fish get named. Closes the loop on balance (§H of GOALS) with real data instead of guesses — privacy-respecting, local-first. *M · L*
- [ ] **66. In-engine profiler scopes around every subsystem.** Named profile regions (`mind`, `boids`, `chemistry`, `render`) surfaced in a dev HUD, so perf regressions are visible per-subsystem, not as a mystery total. *S · M*
- [ ] **67. Golden-trace regression tests for the mind.** With seeded cognition (#15), pin a fish's decision trajectory over 500 ticks; CI flags any cognitive drift the eye can't catch. Lets you refactor the kernel fearlessly. *M · L*
- [ ] **68. A "Turing booth" demo mode.** Side-by-side two fish, one with the full kernel and one ablated, and let a viewer guess which is "more alive." Doubles as QA, marketing, and the most honest sentience test you can ship. *M · L*
- [ ] **69. Automated balance report per release.** Run the headless soak (#35) across all scenarios in CI and diff equilibrium populations vs last release. Balance becomes a tracked, reviewable artifact. *M · M*
- [ ] **70. Memory/alloc budget watchdog.** Track per-frame allocations (GDScript's silent killer) and assert a ceiling in debug builds. Catches the slow GC-pressure leaks before they ship. *M · M*

## H. Embedded-LLM engineering (the real moat is *cheap, grounded* voice)

`guardian_llm.gd` runs one SmolLM2-360M in-process, async-queued, guardian-only,
template-fallback. Solid foundation. These make the voice cheaper, more grounded,
broader, and harder to copy.

- [ ] **71. Batched multi-fish inference.** Today thoughts are FIFO single jobs (`QUEUE_MAX=24`). Batch concurrent prompts into one llama.cpp forward pass — near-linear throughput win that lets *many* fish have voice instead of one Guardian. *L · L*
- [ ] **72. Constrained / grammar-guided decoding.** Force LLM output into grounded slots (mood word, referent, intensity) via GBNF grammar so the model literally cannot hallucinate an event that didn't happen. Hardens the Engineering Creed's "grounded" rule into a guarantee, not a hope. *M · L*
- [ ] **73. System-prompt KV-cache reuse.** The grounding preamble from `MindContext` is largely stable per fish. Cache its KV state and only prefill the delta — big latency cut on the 48-token Guardian budget. *M · M*
- [ ] **74. Per-platform quantization tiers.** Bundle Q4 for low-end, Q5/Q6 for desktop, gated by a capability probe. Better voice where there's headroom, still-runs everywhere — instead of one compromise model. *M · M*
- [ ] **75. Speculative decoding with a tiny draft model.** A 30M draft proposes tokens the 360M verifies. 1.5–2× tokens/sec on CPU, which is the whole ballgame for in-process latency. *L · L*
- [ ] **76. Distill a "fish voice" adapter.** Fine-tune/LoRA a small adapter on curated grounded outputs so the model's *default* register is the naturalist diary tone (GOALS §H10) — less prompt overhead, more consistent voice, a genuinely proprietary asset. *XL · XL*
- [ ] **77. A mock/stub LLM for tests + CI.** No deterministic LLM path exists, so smokes skip voice. Add a canned-output stub keyed to context so the *plumbing* (queue, grounding, sanitize, render) is testable without the 250MB model. *S · M*
- [ ] **78. Per-fish persona vectors.** Persist a small style embedding per fish (terse/florid, bold/timid voice) fed into generation, so a long-kept fish has a *recognizable* voice that drifts with its experiences — ties to personality drift in GOALS §H9. *M · L*
- [ ] **79. Token-budget governor tied to the frame governor (#62).** Generation steals from a shared cognition budget so a busy frame shortens thoughts instead of dropping frames. Makes the LLM a well-behaved citizen of the frame, not a spike. *M · M*
- [ ] **80. Structured prompt-injection shielding for keeper chat.** Keeper text is escaped + delimited (good), but creative escaping is still possible. Add a dedicated input/output guard pass and red-team it — quietly essential once fish talk back to arbitrary player text. *M · M*

## I. Emergence over scripting (let the systems compute the game)

A lot of "alive" behavior is hand-authored (dance variants, courtship choreos,
behavior tiers). Replacing scripts with generative systems is more code-elegant,
more surprising, and scales without authoring every case.

- [ ] **81. Behavior as a utility/HTN system, not an if-ladder.** `fish.tick()` is a long tiered if-ladder (the doc's own #7). Replace with a scored utility selector over the kernel's drives — emergent behavior arbitration, trivially extensible, and far easier to reason about. *L · L*
- [ ] **82. Evolutionary genome selection over generations.** Genomes already mutate/blend. Let selection pressure (who survives + breeds) actually shift population traits over in-tank generations, so a tank visibly *evolves* toward its niche — `GOALS §H8` generational drift made mechanical. *L · XL*
- [ ] **83. Learned, not authored, courtship/dance.** Per-species dances are hardcoded (`GOALS A#20`). Drive them from the signaling channel (#5) + a tiny pattern-generator so display emerges from arousal/genome — endless variety, no per-species authoring. *L · L*
- [ ] **84. Ecology as a constraint solver.** Instead of tuning each scenario by hand (`GOALS §H7`), express "this tank should settle near N fish" as a constraint and let the sim's parameters be *solved* toward it. Self-balancing content. *XL · L*
- [ ] **85. Emergent niches from trait space.** Let detritivores/grazers/predators differentiate from continuous traits rather than discrete `kind` flags, so coexistence and competition emerge (`GOALS §H5 #44`) instead of being enumerated. *L · L*
- [ ] **86. Procedural music from the ecosystem state.** `ambient_audio.gd` is generative but loosely coupled. Drive harmony/density directly from tank health + activity so the *sound is a readout of the sim* — the tank literally sounds healthier when it is. *M · L*
- [ ] **87. Reaction-diffusion for algae/biofilm patterns.** Replace heuristic bloom spawning with a Gray-Scott-style RD field for genuinely organic, never-repeating algae/biofilm — cheap on GPU, far more believable than placed voxels. *M · M*
- [ ] **88. Emergent flow field instead of scripted currents.** Filter outflow currents are hand-placed. A lightweight 2D/3D flow solver from equipment positions would make currents, particle drift, and plant flutter all consistent and emergent. *L · L*
- [ ] **89. Self-organizing schools via local rules + learning.** Combine GPU boids (#23) with the learned coordination (#5) so formation, fission/fusion, and leadership *emerge* rather than being formation presets. *L · L*
- [ ] **90. Generative aquascape suggestions.** With content-as-data (#41) + the constraint solver (#84), the Guardian can *propose* a balanced aquascape ("add stems here for the nitrate load") grounded in the real engine — design help no competitor has. *L · XL*

## J. Moonshots that make a platform team jealous

The big swings. Each reframes what the project *is*. Pick one or two as a north
star; the preceding 90 items are largely the substrate that makes these possible.

- [ ] **91. The cognition kernel as an open research platform.** Ship `addons/cognition_kernel` (from #11/#16) as a real open-source agent sandbox — a GWT + active-inference micro-mind anyone can embed. The aquarium becomes the flagship demo of a reusable framework. *XL · XL*
- [ ] **92. WASM/web build via the deterministic engine.** With sim/render split (#32) and seeded determinism (#31), a template-voice web build becomes viable. A tank that runs in a browser tab is the ultimate distribution + viral surface. *XL · XL*
- [ ] **93. Shared multiplayer reef.** Deterministic sim + event log + cloud (#31/#51/#54) → multiple keepers tending one persistent tank, each tank a tiny authoritative server. A genre nobody owns yet. *XL · XL*
- [ ] **94. Live desktop-wallpaper / ambient mode.** Run the tank as a low-power animated wallpaper (the deferred `GOALS A#50`), trivial once cognition LOD (#20) + frame governor (#62) exist. Always-on presence = daily emotional touchpoint. *L · L*
- [ ] **95. The aquarium as an LLM-agent evaluation environment.** A grounded, deterministic, observable world with social agents is *exactly* what agent researchers need. Expose a headless API and the tank becomes a benchmark, not just a game. *XL · XL*
- [ ] **96. Native sim backend via Rust GDExtension.** `sim-rust/` is an orphaned reference chemistry sim. If the SoA refactor (#25) proves the hot path, port it to Rust via gdext for a deterministic, 10×-faster, fuzz-tested core. (Decide live-or-archive first, per SYSTEMIC #46.) *XL · L*
- [ ] **97. On-device personality fine-tuning.** Over a tank's life, accumulate its grounded narration and periodically LoRA-tune the persona adapter (#78) locally — a fish whose voice is *literally* shaped by its own history. Privacy-preserving, deeply personal, uncopyable. *XL · XL*
- [ ] **98. AR / spatial tank.** With the render/sim split, project the tank onto a desk via passthrough AR. The deterministic engine means the same tank lives on phone, desktop, and headset. *XL · L*
- [ ] **99. A "consciousness science" mode.** Surface the real GWT/IIT/active-inference machinery (Φ proxy, ignition, free energy) as an interactive teaching layer. The project's genuine technical depth becomes its differentiator — edutainment no clone can fake. *L · XL*
- [ ] **100. The closing loop, at platform scale.** GOALS §H10 #100 makes "nothing is added or removed" legible *within* one tank. The platform version: an interconnected world of shared tanks where a fish bred in yours seeds someone else's — the metaphor of a small complete world that keeps itself alive, made literal across a whole community. *XL · XL*

---

## How to use this doc

These are intentionally **above** the table-stakes refactors. But they have a
dependency spine — most of the moonshots are cheap once the foundations land:

1. **Foundations first (unlock everything):** #11 CognitionKernel · #15/#31 determinism · #25 SoA · #18 trace bus · #41 content-as-data.
2. **Then the force-multipliers:** #21/#23/#24 perf headroom · #32 sim/render split · #51 event sourcing · #61 mind debugger.
3. **Then pick a north star moonshot** (§J) and let it pull the rest.

Suggested first three sessions, highest leverage / lowest regret:
- **#21 MultiMesh fish bodies** — biggest perf win, self-contained, immediately visible.
- **#11 + #16 extract the CognitionKernel** — the keystone that makes the mind a framework and unlocks §A, §B, §G, §J.
- **#31 seeded RNG + #15 deterministic cognition** — small, and the precondition for testing, replay, and half the moonshots.
