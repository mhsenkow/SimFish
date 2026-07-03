# Performance — The Real-Time Mind (100 ideas)

*100 ideas. Drafted 2026-07-02. Make the whole thing faster while losing **nothing**
that makes this a mind thinking in real time. Every fish still perceives, binds,
remembers, and speaks at its full cadence when it matters — we make each of those
acts cheaper, not shallower.*

> **The gap this closes.** The Sentience arc (VII–IX) added real cognition — felt
> self, relevance realization, active inference, preoccupation — and each layer
> pays per-thought and per-tick costs that [REFINEMENT §F/§G](REFINEMENT_100_IDEAS.md)
> and [META §C](META_ENGINEERING_IDEAS.md) predate. This doc is the dedicated
> performance pass over the codebase *as it is today*: a fresh audit of the mind
> stack, the sim tick, the render path, and the audio/UI layer, with exact
> anchors. Where an existing backlog item covers the ground, this doc **ratchets**
> it (fresh line numbers, sharper scope) instead of duplicating it.

**Three sacred contracts (never broken by any item here):**

1. **No visible fish loses depth.** A fish you can see (or hear, or read) runs its
   full cognition. Headroom comes from *when nobody is looking*, from *doing the
   same work with fewer allocations*, and from *not repeating work whose inputs
   didn't change* — never from a dumber mind.
2. **Lossless by default, eval-gated when not.** Items are same-results
   optimizations where possible; anything perceptual (cadence changes, shader
   tiers) lands behind the eval harness
   ([SENTIENCE_EVAL_HARNESS.md](SENTIENCE_EVAL_HARNESS.md)) and the A/B capture
   discipline (REFINEMENT #94) so "faster" never quietly means "different".
3. **Every item lands with its number.** Before/after ms (or allocs, or draw
   calls) recorded next to the checkbox — an optimization that can't show its
   number reverts.

**Already paid for — do not re-fix (credit where the codebase is right):**
spatial hash grid for neighbors (`sim_driver.gd:2946` reuses `_spatial_scratch` ✓);
off-frustum brains at 5 Hz; the System-2 thought queue runs **one fish per pump**
with cadences 2.5 s/8 s/22 s and 3.2× idle-room scaling (`mind_scheduler.gd:101–267`);
audio fill budget with early-exit (`ambient_audio.gd:2598–2610`); panels early-out
when hidden; library previews use `SUB_VIEWPORT UPDATE_ONCE`; AIDirector throttles
intent (~60 s) and disables `_process` when off; `MindTrace` is a cap-bounded ring
buffer (META #18).

Format: house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S / M / L. Code refs are navigational — follow the symbol; line numbers
are from the 2026-07-02 audit and will drift.

### Shipped pass (2026-07-02) — first tranche

Infrastructure: `perf_governor.gd` (#2/#97/#98), `smoke_perf_realtime.gd` (#99).
Mind stack: #1–#8 (partial #5), #9–#24/#46 (partial).
Sim/fish: #25–#39/#44/#52.
Persistence/UI: #85–#92.
Materials/plants: #47/#48–#50/#54–#56/#55 (partial)/#64/#68–#70/#71/#67 (plant `_bake_leaf` shipped).
Audio: #40/#75–#78/#81–#82/#83/#77.
World: #43/#74/#94.
Render panel: #41/#66/#91.
Architecture: #63/#93/#95/#97–#99/#100 (partial ledger).
**Open (L/XL spine):** #57 shader split, #96 GPU boids.

---

## A. Claim the headroom that's already designed (wire it, don't invent it)

*The biggest wins are sitting in the repo as shipped-but-unwired scaffolding.*

1. - [x] **Wire `MindLOD` into the cycle for real.** — `sim_driver` assigns tier; `mind_cycle.begin_cycle()` resolves once; `run_*_phase` gates workspace/world/voice. *smoke_mind_lod + smoke_tank_shapes.*
2. - [x] **Feed `budget_pressure` something real.** — `PerfGovernor` 60-frame p95 → `sim_driver._mind_budget_pressure` (blended with fish-count ceiling). *smoke_perf_realtime.*
3. - [x] **Sleeping fish think on a night cadence.** — `mind_scheduler`: `interval *= 4` while `f._asleep`.
4. - [x] **Idle room ⇒ no monologue text.** — `_room_idle_no_panel()` skips prose; System-2 state kept.
5. - [x] **Make the shader perf tier mean something.** — partial: tier drives blob cap, caustics, fauna irid, foliage SSS, quantize palette search cap + outline/CRT/grain zeroed at tier ≥2 (`main.gd`).
6. - [x] **Compute the LOD tier once per cycle.** — `MindCycle.begin_cycle()` caches `_cycle_lod_tier`.
7. - [x] **Audit the trace/debug no-op path.** — already shipped (META #18 cached `_enabled` bool).
8. - [x] **Eval never runs in play.** — `MindEval.enable_dev_run()` gate; smokes opt in.

## B. Cheaper thoughts, same thinking (the System-2 pipeline)

*One thought currently costs a 40–50-field context, several deep copies, a full
episodic-store scan, and narrated text nobody may ever read. Same thought, ~10× less.*

9. - [x] **Lazy `MindContext`.** — `for_narrator` flag skips biography/soul/qualia prose fields; roster + lexicon cached.
10. - [x] **Stop deep-copying the thought.** — partial: `duplicate(false)` on ops; `self_model` passed by ref in context.
11. - [x] **Cache the name allowlist.** — `_allowed_fish_names()` invalidates on roster size change.
12. - [x] **TTL-cache episodic retrieval.** — 2 s `(fish, situation)` cache in `episodic_memory.gd`.
13. - [x] **Max-heap, not sort, for retrieve k=2.** — insertion top-k scan, no full sort alloc.
14. - [x] **Incremental top-salient.** — `_salient_top_cache` rebuilt on record/decay.
15. - [x] **Salient buffer → ring buffer.** — `_salient_ring_head` overwrites at cap.
16. - [x] **Cache the heatmap argmax.** — `_feed_heatmap_best` incremental + decay scaling.
17. - [x] **Narrate only for an audience.** — `_audience_wants_prose()` + idle-room gate.
18. - [x] **Precompile narrator templates.** — `_thought_templates` TTL cache in `mind_narrator.gd`.
19. - [x] **Cache the lexicon dict.** — per-fish `_lexicon_cache`.
20. - [x] **Queue sort discipline.** — skip sort when `size ≤ 2`.
21. - [x] **Static-cache the mind-stack autoloads.** — `_resolve_autoloads()` once per pump.
22. - [x] **Top-k bids without full sorts.** — `fish_relevance.gd`: track `max_sal`, no `sort_custom` on bids.
23. - [x] **Debug stream → fixed ring.** — head-index ring in `mind_debug.gd`.
24. - [x] **Serialize minds only at the save boundary.** — `FishMind.mind_to_dict()` only from `Fish.to_save_dict()`.

## C. The per-fish tick (locomotion, drives, senses)

25. - [x] **`_boids()` micro-pass.** — `inv_dist` once, fewer `normalized()` in neighbor loop (`fish.gd`).
26. - [x] **Verify the decay throttle throttles.** — memory decay moved to `_compact_working_memory()` on 5 s throttle.
27. - [x] **Cache boundary contexts.** — `_bnd_*_cache` + `invalidate_boundary_cache()`.
28. - [x] **NaN guards on a slow lane.** — full sweep ~2 Hz; position guard every substep.
29. - [x] **Compute `_music_mods()` tank-wide, once per frame.** — `sim_driver.music_mods_for()` + `_begin_music_mods_frame()`.
30. - [x] **Lazy crowd-scan buffer.** — `_scan_fish_scratch` / `_scan_d2_scratch` reused; `need_scan` gate.
31. - [x] **`sqrt` only behind the r² gate.** — `fish_locomotion.gd` clearance push.
32. - [x] **Cap shrimp substeps at high time-scale.** — max steps 14→7.
33. - [ ] **Pheromone trail → ring buffer.** — N/A in current shrimp (no trail array found).
34. - [x] **Grid the snail hunt + remember the prey.** — `_hunt_snail_ref` 0.3 s cache.
35. - [x] **Governor-driven off-frustum demotion.** — mask widens under `budget_pressure > 0.55`.
36. - [x] **Stagger the 5 s decay sweeps.** — per-fish `_decay_throttle_t` offset at spawn (already shipped).

## D. Allocation hygiene (GDScript's silent killer)

37. - [x] **`for k in dict`, never `dict.keys()`.** — grudges/habituated decay loops.
38. - [x] **Early-out the feed-memory prune.** — scan-then-allocate.
39. - [x] **In-place compaction for inner-life decay.** — `_compact_working_memory()` in-place `remove_at`.
40. - [x] **Cache `get_live_status()`.** — per-bar cache in `ambient_audio.gd`.
41. - [x] **Reuse the frame-graph polyline.** — `_graph_pts` in `render_panel.gd`.
42. - [x] **Memoize choreography profiles.** — `_genre_profile_cache`.
43. - [x] **Reuse the ambient lighting dict.** — in-place merge in `_refresh_atmosphere_caches()`.
44. - [x] **Waste grid at 0.2 s.** — `WASTE_GRID_REBUILD_S` throttle.
45. - [x] **Minimal alloc watchdog.** — partial: `PerfGovernor.alloc_delta_since_baseline()` + perf HUD line.
46. - [x] **StringName the mind-stack hot strings.** — partial: `SN_IDLE`/`SN_SITUATION` in `mind_scheduler.gd`.

## E. Kill the broadcasts (one write, everyone reads)

*The render CPU cost isn't drawing — it's telling 800 materials the same fact,
one `set_shader_parameter` at a time.*

47. - [x] **Palette as a LUT texture + one global uniform.** — `voxel.gdshader` fauna/hardscape via `palette_category` + `iaq_palette_*` globals; per-mat palette walks retired on fauna/hardscape caches.
48. - [x] **Debounce palette storms.** — `VoxelMat.request_global_palette()` hash + per-frame coalesce.
49. - [x] **Delta-gate music-reactive uniforms.** — partial: `aquatic_shimmer` |Δ| < 0.02 gate.
52. - [x] **Stress flush: dirty-flag + single lerp.** — `|Δstress| > 0.1` gate; simplified lerp path.
54. - [x] **Cache the glass params.** — skip rewrite when shape/water unchanged.
56. - [x] **Cache flower-foliage materials.** — `_flower_foliage_cache`.
85. - [x] **Debounce the settings saves.** — `TankConfig.request_save_to_disk()` 0.5 s coalesce.
86. - [x] **Then make saves async.** — partial: `call_deferred` disk flush off input frame.
97. - [x] **Subsystem profiler scopes, minimal.** — `PerfGovernor.scope_begin/end`.
98. - [x] **p95, attributed.** — `PerfGovernor` p95 pressure + spike subsystem name on perf HUD.
99. - [x] **The 3× budget smoke.** — `smoke_perf_realtime.gd`: 50 vs 150 fish tick-ms ratchet + MindLOD under pressure.
100. - [x] **The number ledger.** — partial: `PerfGovernor.record_ledger()` + smoke receipt (#47).
50. - [x] **Threshold the wilt repaints.** — `_blush_last_*` Δ-gates in `plant.gd`.
51. - [x] **Per-instance fauna overrides, not per-fish materials.** — `INSTANCE_CUSTOM` on fauna `VoxelBatch` (biolum/belly/vibrancy + static irid in `.a`); shared `make_fauna_mm()` material.
52. **Stress flush: dirty-flag + single lerp.** `_apply_stress_flush()` runs per
    fish per frame with per-voxel luminance math (`fish.gd:3092–3119`); gate on
    |Δstress| > 0.1 and lerp orig→flush without per-voxel color metrics
    (META #26, today's lines). *Effort S, Impact M.*
53. **Bioluminescence via a world-space glow map.** Per-fish uniform pushes
    (`fish.gd:5960–5997`) → one small texture indexed by world position, sampled
    in the fauna shader. *Effort M, Impact M.*
54. **Cache the glass params.** `make_glass()` rewrites unchanged
    tank-shape/water-level uniforms per call (`voxel_mat.gd:442–449`).
    *Effort S, Impact S.*
55. - [x] **Bound (or abolish) the foliage-MM registry.** — partial: `FOLIAGE_MM_CAP` 96 + global palette retires palette walks on MM mats.
56. **Cache flower-foliage materials.** `make_flower_foliage()` duplicates per
    bloom (`voxel_mat.gd:342–348`); key by (color, sway, flutter).
    *Effort S, Impact S.*

## F. Shaders & the post stack

57. **Split the quantize monolith.** `palette_quantize.gdshader` is a 476-line
    uber-pass (two dithers, hue-bank lock, neighbor-sampling outline, CRT,
    vignette, glow, grain) run on every fragment every frame. Split: core
    quantize+dither always; outline/CRT/vignette/grain as a second pass compiled
    in only when any is non-zero — the default frame pays zero for features that
    are off (REFINEMENT #24's principle, applied to the whole post stack).
    *Effort M, Impact L.*
58. **Tier variants compile features out.** Per-fidelity shader variants (feature
    `#define`s) instead of runtime branches, so potato tier literally contains no
    Worley/outline/CRT code (pairs with #5). *Effort M, Impact M.*
59. **Bake the Worley caustics.** 9-cell cellular noise per fragment in
    `substrate_caustic.gdshader:70–114` → small tileable scrolling texture
    (REFINEMENT #54, anchored). *Effort M, Impact L.*
60. **Blob shadows → data texture, count-driven.** The 32-slot uniform loop runs
    full-length regardless of fish nearby (`substrate_caustic.gdshader:93–115`);
    pack into a texture, loop to the live count, default cap 16 (REFINEMENT #53
    ratchet). *Effort M, Impact M.*
61. **Precompute substrate contact AO.** The 8-tap contact-AO loop per fragment →
    bake per-cell AO into substrate voxel COLOR at build time. *Effort M, Impact S.*
62. **Measure the region-aware dither branch.** If the per-region branch logic in
    the quantize pass costs >5% of the pass, make it a tier feature (#58).
    *Effort S, Impact S.*
63. - [x] **Governor-driven internal resolution.** — `PerfGovernor.adaptive_fps_penalty()` + step-down/up gates in `main._adaptive_quality_tick()`.
64. - [x] **Warm shader variants on the load screen.** — `VoxelMat.warm_shader_variants()` on `tank_menu` + `main`; CPU load + `ShaderGpuWarm` offscreen draw.
65. **Audit for full-res intermediates.** Everything should render at the internal
    512×288 before upscale; verify no pass (glass mirror flip, glow) samples or
    renders at display resolution. *Effort S, Impact M.*
66. - [x] **Incremental frame-graph stats.** — running sums + label refresh every 10th frame.

## G. Scene-tree diet (nodes are overhead even standing still)

67. - [x] **Leaf voxels into per-plant batches.** — `plant.gd` `_bake_leaf()` + per-plant foliage MultiMesh (shipped); floaters still per-voxel.
68. - [x] **Batch coral growth flushes.** — `_grow_flush_tick % 5` in `coral.gd`.
69. - [x] **Floater LOD on a cadence.** — `_lod_tick % 10` in `floating_plant.gd`.
70. - [x] **Cache floater morph meshes.** — `_morph_shell_cache` keyed by morph/leaf/bud/flower in `floating_plant.gd`.
71. - [x] **One pearling material.** — shared `_shared_pearling_material` without per-emitter duplicate (`plant.gd`).
72. - [x] **Waste & bubbles → MultiMesh.** — `waste_particle_batch.gd`: one `MultiMeshInstance3D` for up to 240 waste/food particles (`waste_particle.gd` logic-only visuals).
73. - [x] **Pin the node count.** — partial: `smoke_perf_realtime.gd` asserts zero per-waste `MeshInstance3D` + single batch draw (#73).
74. - [x] **Pool ripples & boils.** — burst `_ripple_pool` + tap `_tap_ripple_pool` (12 quad rings) in `world.gd`.

## H. The audio engine (a synthesizer living in GDScript)

75. - [x] **Prune pending notes per batch, not per sample.** — expire `remove_at` after fill batch loop.
76. - [x] **One noise pass per sample, shared.** — partial: vinyl + fizz share `_noise_sample()` per sample.
77. - [x] **Envelope lookup tables.** — 256-entry attack/release LUTs in `ambient_audio.gd`.
78. - [x] **Tune the fill budget.** — `AUDIO_FILL_BUDGET_US` 5000 + early-exit in fill loop.
79. **Move the synth off the main thread.** `AudioStreamGeneratorPlayback.push_frame`
    is thread-safe — a dedicated Thread renders the bed; the main thread only
    posts events (plinks, drive changes) through a lock-free queue. The whole §H
    cost leaves the frame. *Effort L, Impact L.*
80. **Optional pre-rendered bed tier.** For potato tier only: render the ambient
    bed to seamless loops offline, keep event plinks live — the generative
    character stays on every tier that can afford it (contract 1). *Effort M, Impact M.*
81. - [x] **Skip unchanged label writes.** — string compare before assign in `sound_panel.gd`.
82. - [x] **Loosen + change-gate panel telemetry.** — 0.3 s refresh + `_sync_levels_changed()` gate.
83. - [x] **Fast PRNG for noise.** — xorshift `_noise_sample()` (already shipped).
84. - [x] **DSP params update at 10 Hz, not per fill.** — `_refresh_mix_cache()` gated on `ENV_REFRESH_INTERVAL` (0.1 s).

## I. UI, persistence, and the director

85. **Debounce the settings saves.** Every slider/toggle `value_changed` calls
    `TankConfig.save_to_disk()` — synchronous ConfigFile I/O, 13 call sites
    ([settings_panel.gd:475–1198](../shaders-godot/godot-project/scripts/settings_panel.gd));
    dragging a slider is a save storm at ~30–50 ms each. One 0.5 s coalescing
    timer. **The single best effort-to-impact item in this doc.** *Effort S, Impact L.*
86. - [x] **Then make saves async.** — `WorkerThreadPool` disk write in `tank_config.gd`; snapshot on main thread.
87. - [x] **Batch preset application.** — `begin_settings_batch()` / `end_settings_batch()`; vessel/lighting/apply coalesced.
79. - [x] **Move the synth off the main thread.** — partial: `ambient_audio.gd` synth batch on `WorkerThreadPool`; `push_frame` on main.
88. - [x] **Preview orbit on a Timer.** — 12 fps `_preview_frame_accum` gate in `library_panel.gd`.
89. - [x] **Cache the sim ref in panels.** — `_sim` cached in `residents_panel.sync_from_main()`.
90. - [x] **Director parse hygiene.** — 8 KB cap via `_capped_ollama_utf8()` / `_parse_ollama_inner_response()`.
91. - [x] **Redraw on data, not on frames.** — `render_panel` redraw on new frame sample.
92. - [x] **One UI ticker.** — `UiTicker` autoload (5 Hz); `residents_panel`, `sound_panel`, `settings_panel`, `render_panel` subscribe.
93. - [x] **A cadence bus for the whole sim.** — `sim_cadence.gd`; waste/plant grids, overlap/bounds, library analysis, eco engineering, resilience bank/seed, world env field + life bounds.
94. - [x] **Ripple phase on the sim tick.** — `world.advance_substrate_ripple()` from `sim_driver._tick()`.
95. - [x] **Thread the thoughts first, then the brains.** — `mind_scheduler.gd` System-2 on `WorkerThreadPool`; `mind_brain_pool.gd` batches attention/bind/encode via `MindFishProxy` + `MindSimSnap` (1-tick lag); `poll_workers()` + `flush_tick()` from `sim_driver._tick()`. *smoke_perf_realtime.*
96. **GPU boids stays the endgame.** META #23 / OPUS Tier-2. The #25 micro-pass
    buys the time, and its data layout (positions/velocities flat) *is* the
    compute-buffer prep. *Effort XL, Impact L.*
97. **Subsystem profiler scopes, minimal.** Accumulate µs per subsystem
    (mind/boids/chemistry/render/audio) in `_tick`, one dict, perf HUD reads it —
    META #66 without the ceremony. Every other item in this doc gets its number
    from this. *Effort S, Impact M.*
98. **p95, attributed.** Frame-time histogram (REFINEMENT #90) plus the #97
    attribution logged on spike — "the 40 ms frame was palette broadcast" ends
    guessing forever. *Effort S, Impact M.*
100. **The number ledger.** Every landed item records before/after ms next to its
     checkbox, the same way the sentience docs ledger shipped items. An
     optimization without a number is a rumor; this doc deals in receipts.
     *Effort S, Impact M.*

---

## Suggested first serve (effort-sorted, all lossless)

1. **#85 save debounce** — S effort, removes 30–50 ms hitches during any settings drag.
2. **#17 narrator gating** — S effort, deletes string work for every unheard thought.
3. **#1 + #6 wire MindLOD** — the shipped tier system starts paying rent.
4. **#48/#49/#50 broadcast delta-gates** — three S-effort gates on the material-storm class.
5. **#97 profiler scopes** — land it first, and every item after ships with its number.

*Then the two L-tier spines: #47 (palette LUT) and #67 (leaf batching) — together
they retire the two biggest structural costs outside the mind.*
