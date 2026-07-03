# The Refinement Pass II — 100 items. Nothing new. Everything better. Again.

*Drafted 2026-07-02, late. Sequel to [REFINEMENT_100_IDEAS.md](REFINEMENT_100_IDEAS.md)
under the same iron rule: **every item makes something that already exists work
right, look right, or cost less — zero new features.** The difference this round:
the codebase shipped at ferocious speed today (Perf I tranche, Perf II §A–§C,
the murmuration §A, v0.2.24) and same-day machinery always has loose bolts. This
pass is two audits deep — one over the fresh mind/perf infrastructure, one over
the sim/UX/lifecycle systems — cross-checked against the working tree.*

> **Honesty header.** Items marked **[V]** were verified by hand against the
> working tree on 2026-07-02 — the defect is real as described. Items marked
> **[A]** came from the audit sweep and are stated as *audit-then-fix*: confirm
> the behaviour first (the audit's line numbers are navigational, not gospel);
> if the code already does the right thing, check the box with "no-op, verified"
> — that's a win too. A refinement doc that asserts unverified bugs as facts
> would itself need refining.

**Shipped log (2026-07-02 pass + 2026-07-03 complete):** All §A–§M S/M items shipped or smoke-verified. L items landed: async saves (#26), synth ring (#30), golden replay file (#86, hash `495717595`), feed-dock satiety (#94), deferred smoke harness (`smoke_refinement_ii_deferred`, default 45s soak via `SOAK_SECONDS`). Still manual/deferred: full 30-min soak (#87 `SOAK_SECONDS=1800`), ledger µs field measurements (#27), motion tuning publish (#77), batch/glow/hydro eye-check (#80–81), first-run full-scene (#99), Refinement III re-audit (#100). CI triad in `test.yml` (#85).

**Format:** house style. **Effort** S (≤2h) / M (half-day) / L (full day+).
**Impact** S / M / L. Where a fix is behaviour-visible, it lands behind the
replay-parity eval ([PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md](PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md) #97)
or an eye-check against a reference save, same as Refinement I.

---

## A. Freshly shipped, freshly loose — harden today's machinery

*The 15 Hz mind tick, the slow-lane bids, the digest caches, and the murmuration
waves all landed today. They work. These make them* right.

1. **[V] Exponential, not linear, slow-bid decay.** `_decay_cached_bids()` uses
   `k = 1 - dt * 0.35` ([global_workspace.gd:117](../shaders-godot/godot-project/scripts/global_workspace.gd:117));
   at mind-tick dt this under-decays vs the intended exponential. Use
   `exp(-0.35 * dt)` so cached salience decays identically at any cadence/idle
   multiplier. *Effort S, Impact M.*
2. **[V] Clear the retrieval hint in play.** `_episodic_retrieval_hint` is set on
   a strong retrieve ([episodic_memory.gd:249](../shaders-godot/godot-project/scripts/episodic_memory.gd:249))
   and consumed by four systems, but only `mind_replay_parity.gd` ever clears it —
   a minutes-old memory hint keeps biasing bids until the next strong hit. TTL it
   (a few mind ticks) and clear on situation change. *Effort S, Impact M.*
3. **[V] One cadence contract for the mind-adjacent tickers.** Attention runs at
   mind cadence with `_mind_dt`, but `MindDaring.tick`, `MindConversation.tick`,
   and the lexicon run every frame with raw `dt`
   ([fish.gd:1384–1391](../shaders-godot/godot-project/scripts/fish.gd:1384)).
   Decide per system: frame-fast (then document why) or mind-tick (then move it
   behind `_run_mind` with `_mind_dt`). No accidental double-clocking. *Effort M, Impact M.*
4. **[A] Double-decay guard on the slow lane.** Audit the interplay of
   `_bid_slow_accum` and `_decay_cached_bids` call sites — the sweep flagged a
   path where cached bids can decay twice in one mind tick when the slow lane
   isn't due. One decay per tick, asserted in the parity smoke. *Effort S, Impact M.*
5. **[A] Digest includes what the result depends on.** `resolve_competition`'s
   bid digest snapshots label + salience (0.02 snap) but reportedly not
   `coal_mask` — two bid sets with equal saliences but different coalitions would
   hit the same cache entry. Fold the mask into the digest hash. *Effort S, Impact M.*
6. **[A] Order-insensitive broadcast digest.** `broadcast_if_changed` skips on a
   digest of the contents array; if insertion order can differ for the same
   logical winners, identical states re-broadcast (waste) or — worse — a changed
   order masks a real change. Hash winners as an order-independent set.
   *Effort S, Impact S.*
7. **[A] Reset the digests on load and reset.** `_ws_broadcast_digest` (and any
   competition digest) reportedly survives save/load — a reloaded fish whose
   first-frame bids match its pre-save state skips its first broadcast. Clear
   all digest/cache fields in the fish reset path. *Effort S, Impact M.*
8. **[A] Tier-hysteresis hold that actually resets.** The 0.5 s LOD debounce
   (`mind_lod.gd`) reportedly accumulates `_lod_tier_hold_s` without reset after
   graduation — a fish oscillating at the boundary can promote/demote on stale
   hold time. Reset on every committed transition; add a two-fish smoke.
   *Effort S, Impact S.*
9. **[A] Broadcast after the rerank, not before.** `MindSoulPass3.after_broadcast`
   runs after `broadcast_if_changed` and can rerank; if it does, the stored
   digest no longer matches what fish state actually holds. Either soul-pass
   reranks before broadcast, or a rerank invalidates the digest. *Effort M, Impact M.*
10. **[A] Cycle tier == sim tier, guaranteed.** `_cycle_lod_tier` (cached at
    `begin_cycle`) and `sim_driver`'s live tier can diverge within a frame; the
    gated phases should all read the *same* tier snapshot for one cycle. Assert
    it in debug builds. *Effort S, Impact S.*
11. **[A] EFE on/off is one decision per cycle.** `MindActiveInference.enabled_for()`
    is re-evaluated inside bid collection; if a runtime flag flips mid-cycle,
    bids can mix EFE and non-EFE kinds. Resolve once in `begin_cycle`, stash on
    the cycle state. *Effort S, Impact S.*
12. **[A] Signals: collect only what's emitted.** `FishSignals.collect_signal_bid`
    runs in the fast lane while emit/scan sit behind the ablation flag
    ([fish.gd:1369](../shaders-godot/godot-project/scripts/fish.gd:1369)) — with
    ablation off you can collect bids for signals nobody emits (or vice versa).
    One flag governs the whole path. *Effort S, Impact S.*
13. **Murmuration constants into the tuning surface.** `motion_wave.gd` shipped
    with hard consts (`AGITATION_DECAY 2.6`, `MANOEUVRE_WAVE_SPEED 5.2`,
    `PROPAGATION_BLEND 0.44`…). Wire them to TankConfig (LIVING_MOTION #92) so the
    feel is dialable without recompiles — and so the smoke can sweep them.
    *Effort S, Impact M.*
14. **Wave-system idempotence under fast-forward.** `MotionWave.tick` integrates
    agitation with dt; verify at time_scale 4×/16× the wave crosses the school in
    the same *sim* time (not wall time), and that `REFRACTORY_DURATION` scales.
    Add a time-scale case to `smoke_murmuration.gd`. *Effort S, Impact M.*

## B. Caches that know when they're wrong

15. **[A] Retrieval cache keyed on focus, invalidated on focus.** The episodic
    TTL cache keys on `situation|attention_focus` but nothing invalidates it when
    focus changes mid-tick — a fish that just snapped to "threat" can read the
    "idle" retrieval for up to 2 s. Invalidate on focus transition; keep the TTL
    for same-focus repeats. *Effort S, Impact M.*
16. **A cache-registry sweep.** One place lists every per-fish cache (bias
    targets, self-model, digests, retrieval, name allowlist, lexicon, habit keys)
    with its invalidation event; the fish reset/load path iterates the registry.
    Today each cache hand-rolls its own lifecycle — that's how #7 happened.
    *Effort M, Impact L.*
17. **Cache hit-rate counters behind the perf HUD.** The digest/retrieval/habit
    caches ship blind — one counter pair (hits/misses) each, surfaced on the
    perf HUD next to mind-Hz, so a cache that silently stopped hitting shows up
    as a number, not a vibe. *Effort S, Impact M.*
18. **[A] Glance/keeper fields null-safe at death.** Bid collection reads
    per-fish cached fields (`_cached_glance_strength` et al.) that can be read
    while a fish is being freed; sweep the fast-lane reads for
    `is_instance_valid` guards at the entry point (one check, not per-field).
    *Effort S, Impact S.*
19. **Config lookups on the mind tick, snapshotted.** `MindTick.target_hz()`
    walks `/root/TankConfig` per call; correct but repeated. Snapshot cadence +
    idle multiplier once per sim tick into `AmbientSnap` (it exists for exactly
    this). *Effort S, Impact S.*
20. **[A] Silent config defaults get one log line.** Missing config keys default
    silently (`episodic_quant_8bit` → true was the flagged example) — one
    `push_warning` on first fallback per key, so a build with a missing setting
    says so once instead of behaving differently in silence. *Effort S, Impact S.*

## C. Finish the partials (the Perf I ledger's own confessions)

*Perf I checked eleven items as "partial." Partial shipped is partial debt.*

21. **Shader tier, the rest of it (Perf I #5).** Tier drives blob cap/caustics/
    irid/SSS today; finish the sweep — Worley, outline, region dither — so tier ≥2
    provably zeroes every listed feature (pairs with the #57 post split).
    *Effort M, Impact M.*
22. **Deep-copy audit, completed (Perf I #10).** `duplicate(false)` landed on ops;
    finish the remaining `duplicate(true)` sites on the thought path (grep
    audit + ownership comments), each either justified or removed. *Effort S, Impact M.*
23. **Alloc watchdog with teeth (Perf I #45).** `alloc_delta_since_baseline()` +
    HUD line exists; add per-subsystem attribution and make the smoke fail on
    steady-state growth (Perf II #99 promised this — land it). *Effort M, Impact M.*
24. **StringName sweep, completed (Perf I #46).** `SN_IDLE`/`SN_SITUATION` landed;
    finish the hot-string inventory (focus labels, situation kinds, stream tags)
    across the mind stack — one const module, no raw string compares on the tick.
    *Effort M, Impact S.*
25. **Delta-gate the remaining music uniforms (Perf I #49).** `aquatic_shimmer`
    got its gate; sweep the rest of the music-reactive uniform writes with the
    same |Δ| < 0.02 rule via the #77 uniform-ledger smoke. *Effort S, Impact S.*
26. **Async saves, truly async (Perf I #86).** The flush moved off the input
    frame via `call_deferred` — but serialization still happens on main. Finish:
    snapshot on main, stringify + write on `WorkerThreadPool` (Perf II #92), and
    the delta-mind payload (Perf II #36) shrinks what's snapshotted. *Effort M, Impact M.*
27. **The ledger, filled (Perf I #100).** `record_ledger()` exists; the checked
    items above it mostly lack their before/after numbers. Backfill the ten
    biggest (competition, retrieval, glow path, save debounce…) with measured
    µs — the receipts this whole doc series promised. *Effort M, Impact M.*
28. **Foliage-MM registry: bounded → owned (Perf I #55).** The cap (96) landed;
    finish the ownership story — eviction order, what happens at cap on a big
    planted tank, and a smoke that plants 120 species variants without material
    churn. *Effort S, Impact S.*
29. **Node-count pin, widened (Perf I #73).** The waste-batch assert landed;
    extend the smoke to pin per-fish node count and per-plant node count so the
    §G scene-diet wins can't silently regress. *Effort S, Impact M.*
30. **Synth thread residency (Perf I #79 / Perf II #89).** Batch-on-pool landed;
    the persistent thread + ring buffer is designed and still open — this is the
    oldest partial on the books. Land it or explicitly re-scope it. *Effort M, Impact M.*

## D. Save/load — the tank you come back to is the tank you left

31. **[A] Algae reload keeps its shape.** Algae restore spawns *random* voxels up
    to the saved count ([algae.gd:105](../shaders-godot/godot-project/scripts/algae.gd:105))
    — clusters visibly re-sprout on load. Save the voxel offsets (they're few) or
    reseed the layout RNG from a saved seed. *Effort S, Impact M.*
32. **[A] Floater state persists.** The sweep found no floater save coverage for
    vitality/bud/flower/turion state beyond position — a floating carpet reloads
    younger than it was. Round-trip the full floater dict; add to the save smoke.
    *Effort M, Impact M.*
33. **[A] Plant silhouettes don't snap on load.** Rebuild-at-height plus a stale
    `growth_progress` can jump a plant a voxel on reload; restore progress *into*
    the rebuild so the silhouette matches pre-save exactly. *Effort S, Impact S.*
34. **[A] Guard the growth_factor round-trip.** A corrupted/NaN `growth_factor`
    clamps to 1.0 and silently erases a fish's size history — validate at save
    time (refuse to write NaN) rather than repair at load. *Effort S, Impact S.*
35. **[A] Death state round-trips coherently.** Dying-fish reload applies the
    pose but reportedly not the wall-clock safety timer — a twice-dying fish gets
    force-freed early. Serialize `_dying_timer` and reset the safety clock on
    load. *Effort S, Impact S.*
36. **[A] Widow cleanup.** A dead fish's partner keeps `_mate_id` pointing at the
    corpse until reload — clear partner links (and any `_hunt`/bond refs) in the
    death path, with a lifecycle smoke. *Effort S, Impact M.*
37. **[A] Pregnancy visible after reload.** `_gestation_progress ≈ 1.0` at save
    drops fry on the first tick after load; hold release for a grace window so
    the player sees the gravid state before the birth. *Effort S, Impact S.*
38. **[A] Life-phase vs water-level conflicts resolve deterministically.** Saved
    `life_phase` restored after height-init can contradict the current surface
    (canopy plant in a lowered tank); define the precedence (phase re-derives
    from geometry) and test it. *Effort S, Impact S.*
39. **Save-smoke: the round-trip diff.** One headless smoke saves a busy tank,
    reloads, re-saves, and diffs the two dicts field-by-field — every mismatch is
    a bug in this section. The cheapest possible net under all of §D. *Effort M, Impact L.*
40. **Mind digests + caches excluded from saves.** Sweep `mind_to_dict` for
    transient fields (digests, TTL caches, scratch) that serialize today; the
    save shrinks and #7-class staleness can't ride through disk. *Effort S, Impact S.*

## E. Things appear where things can be

41. **[A] Spawn spacing.** Multi-fish spawns can stack at one point until the sim
    spreads them ([world.gd:8483](../shaders-godot/godot-project/scripts/world.gd:8483));
    jitter each spawn by a body length and reject points inside another fish's
    radius. *Effort S, Impact S.*
42. **[A] Substrate spawns respect hardscape.** Shrimp/snail/clam placement
    samples the substrate disk without checking rocks — creatures can wake up
    inside a boulder. Reuse the aquascape occupancy grid for a reject test.
    *Effort S, Impact M.*
43. **[A] Epiphytes without wood say so.** Spawning an epiphyte with no hardscape
    silently roots it in gravel; either surface the "needs driftwood" hint or
    visibly attach to the nearest hard surface. *Effort S, Impact S.*
44. **[A] Plant height vs tank height.** `spawn_library_entry` doesn't check
    mature height against water depth — tall stems clip the surface plane on day
    one. Cap initial height and let the canopy logic (#67, LIVING_MOTION) handle
    the rest. *Effort S, Impact S.*
45. **Spawn-position audit smoke.** Headless: spawn every library entry into a
    crowded reference tank 50×, assert zero intersections with hardscape/glass
    and no stacked fish. Locks §E forever. *Effort M, Impact M.*
46. **Camera presets vs tank shapes.** The portrait-cylinder preset assumption
    ([main.gd:273](../shaders-godot/godot-project/scripts/main.gd:273)) — sweep
    every preset × tank shape for clipping/wrong radius; presets derive from
    tank AABB, not hardcoded numbers. *Effort M, Impact S.*

## F. The feeding loop, closed properly

47. **[A] Filter intake always exists.** Pellet drift targets `filter_intake_pos`;
    if it's unset at load, food wanders aimlessly
    ([waste_particle.gd:177](../shaders-godot/godot-project/scripts/waste_particle.gd:177)).
    Default it from the aeration jet on world init, assert non-null in the smoke.
    *Effort S, Impact S.*
48. **[A] Heatmap learns every drop.** Rapid multi-pellet drops dedupe into one
    feed-memory event — the learning feels inconsistent. Accumulate weight per
    event instead of dropping duplicates. *Effort S, Impact M.*
49. **[A] Float window meets the fish.** Surface food sinks on a fixed timer even
    with feeders inches away; extend the float window while fish are actively
    approaching (they're already tracked in the heatmap). *Effort S, Impact S.*
50. **Uneaten food closes the loop visibly.** Pellets that expire become waste
    with a visible transition (soften, discolor, sink) — the player learns
    overfeeding by *seeing* it, not by reading ammonia. *Effort S, Impact M.*
51. **Feed-frenzy fairness.** Verify dominant fish don't structurally starve
    timid ones at the pellet (rank defer exists in boids; check it doesn't gate
    feeding) — the residents panel's hunger spread is the metric. *Effort M, Impact M.*

## G. Light that breathes, music that lands

52. **[A] Un-knee the dusk.** `deep_night = smoothstep(0.08, 0.38, dl)` puts a
    visible knee at the transition
    ([world_atmosphere.gd:41](../shaders-godot/godot-project/scripts/world_atmosphere.gd:41));
    widen/re-curve so dusk reads as minutes of fade, not a step. Eye-check
    against the reference save at 4× time. *Effort S, Impact M.*
53. **[A] Sunset boost clamps coherently.** The 1.5 clamp on sunset intensity
    isn't known to the shader side — peak brightness can behave unpredictably
    with boost > 1. One authority for the max. *Effort S, Impact S.*
54. **[A] Music stop is instant everywhere.** `stop()` deactivates the drive but
    `is_active()` subscribers can linger a frame, and beats echo ~2 frames after
    audio cut ([music_reactive.gd:412](../shaders-godot/godot-project/scripts/music_reactive.gd:412));
    flush the beat queue on stop so the tank exhales *with* the music.
    *Effort S, Impact S.*
55. **[A] Phrase jumps ease, never snap.** External phrase-state jumps (seek,
    skip) lerp choreography targets instantly; carry a short easing window over
    the old phrase's remainder. *Effort S, Impact M.*
56. **[V-class, verify at 16×] One clock for the dance.** `music_reactive`
    runs on wall time while the sim scales by `time_scale` — at 16× the fish do
    16× logic against 1× beats. Decide the contract (dance is wall-time, sim is
    sim-time is defensible — but then choreography *targets* must read wall-dt
    consistently) and add the 16× case to the choreography smoke. *Effort M, Impact M.*
57. **Sleep/wake edge sweep.** Startle-wake during the sleep-skip cadence, dawn
    while dreaming, lights-on at midnight — walk the transitions and assert no
    fish stays asleep with `_run_mind` true or awake with the skip active
    (pairs with Perf II #8's event scheduler). *Effort S, Impact S.*

## H. Chemistry the keeper can feel

58. **[A] Un-pin the crisis.** Ammonia/nitrite clamp at hard caps every tick —
    in a crisis, water changes are numerically invisible until far below cap
    ([water_chemistry.gd:185](../shaders-godot/godot-project/scripts/water_chemistry.gd:185)).
    Soft-cap (asymptotic) instead of clamp so every keeper action moves the
    number. *Effort S, Impact L.*
59. **[A] Relief is immediate.** pH-down reducing toxic ammonia should visibly
    ease fish stress the same tick, not next frame — order the chemistry →
    stress reads within one tick. *Effort S, Impact S.*
60. **[A] Mood weights can't invert the crisis.** O₂ 0.30 vs ammonia −0.35 lets a
    toxic-but-oxygenated tank out-score a clean-but-still tank
    ([keeper_care.gd:49](../shaders-godot/godot-project/scripts/keeper_care.gd:49));
    make lethal parameters gating (a hard mood ceiling under toxicity), not
    additive. *Effort S, Impact M.*
61. **Chemistry → visible water, verified.** Sweep that every chemistry state the
    game tracks has a visual channel (turbidity, tint, particulates) and that the
    channel actually moves when the value does — the "invisible ammonia" class of
    bug, made a checklist. *Effort M, Impact M.*
62. **[A] Clam intake stops cleanly.** Particles in flight to a stalled clam
    hiccup for a tick ([sim_driver.gd:3817](../shaders-godot/godot-project/scripts/sim_driver.gd:3817));
    release them to the flow field on stall. *Effort S, Impact S.*

## I. The director and the guardian, unbreakable

63. **[A] Errored guardian lines retry once.** `_on_generation_error()` drops the
    queued thought silently ([guardian_llm.gd:720](../shaders-godot/godot-project/scripts/guardian_llm.gd:720));
    one retry, then the template fallback speaks instead — the guardian never
    just goes quiet. *Effort S, Impact M.*
64. **[A] Sanitizer fails open to the template.** A false-positive profanity/spam
    match blanks the whole line ([guardian_llm.gd:728](../shaders-godot/godot-project/scripts/guardian_llm.gd:728));
    on sanitize-to-empty, substitute the offline template line rather than
    silence. *Effort S, Impact S.*
65. **[A] Director failure states reach the UI.** `test_connection()` failures
    set `last_error` but the panel shows only a generic state — surface
    "Ollama reachable, model missing" vs "not running" vs "timeout" distinctly;
    the fix for each is different. *Effort S, Impact M.*
66. **[A] Parse failures log once with a sample.** Nested/malformed LLM JSON
    falls back silently ([ai_director.gd:45](../shaders-godot/godot-project/scripts/ai_director.gd:45));
    keep the fail-soft behaviour but log the first 200 chars once per session so
    prompt bugs are debuggable. *Effort S, Impact S.*
67. **Offline parity check.** Snapshot the template-path outputs (names, bios,
    thoughts) in a smoke so offline mode is a first-class citizen that can't
    quietly degrade as the LLM path evolves. *Effort M, Impact M.*
68. **Intent-field staleness bound.** If Ollama stops responding mid-session, the
    last intent field persists indefinitely — decay it toward neutral over ~5 min
    so a dead director fades out instead of steering forever. *Effort S, Impact S.*

## J. Settings that do what they say, panels that tell the truth

69. **[A] Render config applies on change, not on resize.** RenderPanel edits to
    width/height/adaptive-target only take effect at the next size event
    ([main.gd:1136](../shaders-godot/godot-project/scripts/main.gd:1136)); apply
    on value-commit. *Effort S, Impact M.*
70. **[A] Light-preset selector can't lock wrong.** The `_light_applying_preset`
    flag races panel init — a slider firing early locks the selector to "custom"
    ([main.gd:147](../shaders-godot/godot-project/scripts/main.gd:147)); set the
    flag before wiring signals. *Effort S, Impact S.*
71. **[A] Integer-upscale toggle re-derives the pipeline.** Toggling it stretches
    without re-running quantize until the next frame event ([main.gd:1512](../shaders-godot/godot-project/scripts/main.gd:1512)
    — the one TODO in the tree); re-apply the render path on toggle. *Effort S, Impact S.*
72. **[A] Panels subscribe to the events they display.** Library/residents panels
    show stale rosters until reopened; they already share `UiTicker` — add
    spawn/death/evolution signals so counts are live. *Effort S, Impact M.*
73. **[A] Pause vs aquascape vs fast-forward: one owner.** Both pause and
    aquascape mode write `time_scale = 0` and can restore each other's stale
    value ([main.gd:2477](../shaders-godot/godot-project/scripts/main.gd:2477));
    a single time-authority stack (push/pop) replaces the flag dance.
    *Effort M, Impact M.*
74. **[A] Adaptive quality acts within a beat.** The 1.2 s check + queued step
    means a stutter takes 2+ s to answer; on a p95 breach, step immediately
    (the governor already has the number). *Effort S, Impact S.*
75. **Settings round-trip smoke.** Headless: set every TankConfig field to a
    non-default, save, reload, assert applied — catches the whole "works until
    restart" class. *Effort M, Impact M.*
76. **HUD numbers agree with the ledger.** Perf HUD mind-Hz, cache hit rates
    (#17), alloc deltas (#23), and `PerfGovernor` scopes should visibly be the
    same numbers the smokes assert — one source of truth, read twice.
    *Effort S, Impact S.*

## K. Motion polish on what just landed

77. **Wave + boids interplay tuning pass.** With topological boids (#1) and
    agitation waves (#11) both live, sweep the combined parameter space once with
    the order-parameter eval (LIVING_MOTION #95): polarization, correlation
    length, wave transit time at 20/40/80 fish — publish the chosen constants in
    the doc header. *Effort M, Impact L.*
78. **Startle threshold vs wave floor.** `CASCADE_FLOOR 0.04` and per-fish
    startle entry must not chatter (agitation hovering at the floor re-triggering
    micro-startles); add hysteresis at the floor. *Effort S, Impact S.*
79. **Dart-trail pool under mass startle.** `dart_trail_pool.gd` shipped — verify
    pool exhaustion behaviour when the whole school darts at once (drop oldest,
    never allocate) and pin it in the murmuration smoke. *Effort S, Impact S.*
80. **Species-batch fauna + per-fish glow coexist.** `fauna_species_batch.gd`
    landed alongside the per-fish INSTANCE_CUSTOM path; verify a glowing fish in
    a batched school renders its biolum (the batch's CUSTOM.a packing vs the
    legacy walk) — the two paths must agree or the batch must own it fully.
    *Effort M, Impact M.*
81. **Hydro-on-by-default regression sweep.** `use_full_physics` now returns
    `true` unconditionally ([hydrodynamics.gd:169](../shaders-godot/godot-project/scripts/hydrodynamics.gd:169)
    — verified); eye-check the species that never ran it: station-keeping
    angelfish, fry, shrimp climb, snail glide. Any regression gets a per-pattern
    coupling factor, not a global revert. *Effort M, Impact M.*
82. **Sleep-drift under waves.** Asleep fish receiving an agitation wave should
    wake *through* the groggy path (LIVING_MOTION #60), not snap to full flight —
    verify the wave respects the sleep-skip cadence handoff. *Effort S, Impact S.*
83. **Boids batch vs fallback parity.** `MindBoidsBuffer` outputs vs the in-line
    neighbour loop ([fish.gd:7150](../shaders-godot/godot-project/scripts/fish.gd:7150))
    are a fast/fallback dual — add a parity assert to `smoke_murmuration.gd` so
    the two paths can't drift (the SoA competition already has one; boids needs
    the same). *Effort S, Impact M.*
84. **Kernel twin-test on boot, extended.** `mind_kernel.gd` shipped; ensure the
    GDScript-twin parity self-test (Perf II #50) covers every kernel entry point
    actually in use — competition landed, check dots/EFE/boids as they migrate.
    *Effort S, Impact M.*

## L. Proof — the net under all of it

85. **The regression triad, wired to CI.** `smoke_perf_realtime` +
    `smoke_murmuration` + the save round-trip (#39) run on every release build;
    v0.2.24 shipped same-day work — the triad is what makes tomorrow's same-day
    work safe. *Effort S, Impact L.*
86. **Replay-parity gets a golden file.** The parity harness exists
    (`mind_replay_parity.gd`); commit a golden replay (seed + N ticks + expected
    winners hash) so parity is checked against *history*, not just self-
    consistency within a run. *Effort M, Impact M.*
87. **Crash-free soak.** Headless 30-minute soak at 4× with spawns, deaths,
    feeds, day/night flips, music on/off — assert zero errors in the log tail.
    Finds the §D/§F/§G edge cases no targeted smoke will. *Effort M, Impact L.*
88. **The false-positive ledger.** This audit's sweep flagged ~10 "dead wiring"
    findings that grep disproved (flow deposit, writeback, retrieval-hint
    consumers, `flow_coupling`) — record them in this doc's footer as
    verified-fine so the next audit doesn't re-chase them. *Effort S, Impact S.*
89. **Warning-clean boot.** A fresh tank boot currently prints engine/script
    warnings; drive to zero and assert in a smoke — every warning after that is
    signal. *Effort S, Impact M.*
90. **The one-TODO rule.** The tree has exactly one TODO ([main.gd:1512](../shaders-godot/godot-project/scripts/main.gd:1512),
    fixed by #71). Keep it at zero-or-tracked: any TODO must name a doc item or
    it fails the lint smoke. *Effort S, Impact S.*

## M. Small truths (each one someone will notice)

91. **[A] Fish never stack on the first frame.** (#41's visible symptom) — the
    first second after "add 6 tetras" is the player's first impression of the
    school; it must fan out, not erupt. *Effort S, Impact M.*
92. **Death is an event the tank notices.** Verify neighbours' minds actually
    receive the death (grief/startle path) *and* the body's handling reads
    intentional — sink, dim, guardian comment — with no physics jitter on the
    corpse. *Effort M, Impact M.*
93. **Load order: water before life.** On tank load, chemistry/flow/light apply
    before creatures tick once — no first-frame flash of default-blue water or
    un-swayed plants. *Effort S, Impact S.*
94. **Feed dock reflects satiety.** After a good feed, the dock's state (and the
    guardian, if asked) agree the tank is fed — sweep for any "still hungry" UI
    within minutes of a full feed. *Effort S, Impact S.*
95. **Window resize mid-everything.** Resize during aquascape edit, during music,
    during a dying animation — the render path (#69/#71) reapplies cleanly with
    no stuck letterbox or stretched frame. *Effort S, Impact S.*
96. **Fast-forward returns gracefully.** Dropping 16× → 1× mid-startle should
    leave no residual doubled speeds or compressed timers (bursts, gestation,
    flower stages all use sim-time — verify the sweep). *Effort S, Impact M.*
97. **The residents panel is never wrong about who exists.** After a death +
    spawn in the same minute, names/counts/portraits match the tank exactly
    (#72's assertion, made a smoke). *Effort S, Impact S.*
98. **Guardian voice cadence under load.** When the LLM is slow, guardian lines
    queue rather than pile up or interleave out of order — one voice, one line at
    a time, timestamps monotonic. *Effort S, Impact S.*
99. **First-run tank is the best-case tank.** Boot a fresh install headlessly:
    default scenario, default settings — assert the murmuration smoke passes,
    chemistry is stable, and zero warnings (#89) on the exact configuration every
    new player sees. *Effort S, Impact M.*
100. **Re-audit in one release.** After ~50 of these land, run the same two-agent
     audit again and diff the findings — the definition of done for Refinement II
     is that Refinement III's audit comes back thin. *Effort S, Impact M.*

---

## Suggested first serve (highest truth-per-hour)

1. **#58 un-pin the chemistry** — one soft-cap makes every keeper action visible
   again; the biggest felt fix in the doc.
2. **#1 + #2 + #7 the verified mind-stack trio** — exponential decay, hint TTL,
   digest reset on load; all S-effort, all provably correct-making.
3. **#39 the save round-trip smoke** — one harness that turns all of §D from
   anecdotes into assertions.
4. **#63/#64 the guardian never goes silent** — retry + fail-open-to-template;
   the soul of the tank shouldn't have silent failure modes.
5. **#85 the regression triad in CI** — perf + murmuration + save smokes on every
   build, so today's shipping pace stays survivable.

*Then #16 (the cache registry) and #87 (the soak) pay compound interest: one
makes staleness bugs structurally rare, the other finds the edge cases this doc
inevitably missed.*

---

**Footer — verified-fine (do not re-chase):** `TankFlowField.deposit` *is* called
(fish wakes, [world.gd:7973](../shaders-godot/godot-project/scripts/world.gd:7973));
`MindWriteback.apply_op` *is* invoked (keeper model, daring);
`_episodic_retrieval_hint` *is* consumed (spark, relevance, workspace ×2 — the bug
is staleness, #2, not dead wiring); `_salient_top_cache` and `_meta_ring` *are*
used (fish_mind, mind_self_model); `Hydrodynamics.flow_coupling` *is* applied
(fish + shrimp); `MindTick.target_hz()` null-checks TankConfig correctly;
`SaveManager` snapshots on main and stringifies on `WorkerThreadPool` (#26);
`SynthRingBuffer` + worker synth in `ambient_audio.gd` (#30); `filter_intake_active`
gates waste pull (#62); `TimeAuthority` owns pause stack (#73); `library_panel`
listens to `creature_added`/`creature_removed` (#72); feed dock shows `Fed ·`
when `tank_feed_satiety_ok()` (#94); golden mind digest pinned in
`data/golden_mind_replay.json` (#86).
