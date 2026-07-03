# Performance II — The Unthrottled Mind (100 ideas)

*100 ideas. Drafted 2026-07-02, same-day sequel to
[PERFORMANCE_REALTIME_IDEAS.md](PERFORMANCE_REALTIME_IDEAS.md) after its first
tranche (~90/100) landed. That pass made each act cheaper — fewer allocs, fewer
sorts, fewer broadcasts. This pass changes **when and where acts happen**:
cadence, threads, batching, packed math. The goal is unchanged and sharper: every
fish thinks with its **full ability**, in real time, and the frame never notices.*

> **The gap this closes.** The mind still runs *on the render frame*. Attention,
> bids, competition, decay — per fish, per frame, at whatever Hz the GPU allows.
> A 60 Hz mind is not a deeper mind than a 15 Hz mind whose drives integrate the
> same dt — it's the same mind paying 4× rent. Likewise the brain still lives on
> the main thread, memories are dictionaries instead of packed floats, and social
> cognition is O(N²). The fix is architectural, not another micro-pass: give the
> mind its own clock, its own thread, and a numeric substrate — then the full
> stack (workspace, world model, felt self, voice) runs for *everyone* at *every*
> tank size.

**Three sacred contracts (inherited, still never broken):**

1. **No visible fish loses depth.** Headroom comes from cadence, threading, and
   representation — never from a dumber mind. Reflexes (threat, collision) stay
   on the frame; deliberation was never frame-rate-bound to begin with.
2. **Lossless by default, eval-gated when not.** Same-results changes ship free;
   anything that could change a thought (quantized vectors, cadence moves,
   1-frame writeback latency) lands behind the replay-parity eval (#97) and
   [SENTIENCE_EVAL_HARNESS.md](SENTIENCE_EVAL_HARNESS.md).
3. **Every item lands with its number.** Before/after µs (or allocs, or draw
   calls) recorded next to the checkbox via `PerfGovernor.record_ledger()`. No
   receipt, no merge.

**Already paid for — do not re-fix (the Perf I tranche, 2026-07-02):** MindLOD
wired through `begin_cycle()`; governor p95 → budget pressure; episodic retrieval
TTL-cached with insertion top-k; salient ring + incremental top; narrator gated on
audience; palette LUT shader globals + per-instance fauna CUSTOM (#47/#51); leaf
and waste MultiMesh batches; save debounce + async flush; synth batch on
WorkerThreadPool; UiTicker + SimCadence buses; profiler scopes + ledger. Open
Perf I spines (#57 post split, #96 GPU boids, #95 full brain thread) are
**absorbed and ratcheted here** as §H and #45/#57 — this doc is now their home.

Format: house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S / M / L. Anchors are symbol-first (line numbers drift); the ones with
line numbers were verified against the working tree on 2026-07-02.

---

## A. Give the mind its own clock (cadence is architecture)

*The attention phase runs per fish per render frame. Nothing in the stack needs
that: thought cadences are 2.5 s+, drives move over minutes, only reflexes are
frame-fast. A fixed mind tick makes cognition frame-rate-independent — the same
mind on a 30 fps potato and a 120 fps tower.*

1. - [x] **The 15 Hz mind tick.** — `mind_tick.gd` (`mind_cadence_hz` in TankConfig); attention + bind/encode gated; drives stay per-frame. *#1.*
2. - [x] **Fast lane / slow lane bids.** — `_collect_fast_bids()` / `_collect_slow_bids()` at 3 Hz with analytic decay. *#2.*
3. - [x] **Event-driven bid invalidation.** — `mark_bid_dirty()` on feed/keeper/day flip; unflagged slow lane reuses cache. *#3.*
4. - [x] **Re-compete only on change.** — `GlobalWorkspace.resolve_competition()` caches bid digest + result per fish. *#4.*
5. - [x] **Δ-gate the broadcast.** — `broadcast_if_changed()` skips writeback when competition digest matches. *#5.*
6. - [x] **Phase-stagger the mind tick.** — `hash(fish_id) % MIND_HZ` initial offset in `MindTick.init_fish()`. *#6.*
7. - [x] **Interpolate the visible outputs.** — `_ws_bias_lerp_from/to` + `MindTick.lerp_visuals()` each frame. *#7.*
8. - [x] **Sleep as a scheduled event, not a poll.** — `_sleep_skips_mind_tick()` cadence in `fish.gd`; dream/consolidation every 0.85 s; startle wakes. *#8.*
9. - [x] **Tier hysteresis.** — `MindLOD.tier_for_hysteresis()` 0.5 s debounce in `sim_driver`. *#9.*
10. - [x] **Analytic salient decay.** — `w0`/`t0`/`decay_mult` + 2 s prune cadence in `FishMind.tick_salient_decay()`. *#10.*
11. - [x] **Analytic bond/grudge/habituation decay.** — bond arcs moved to existing 5 s decay throttle in `fish.tick()`. *#11.*
12. - [x] **One ambient snapshot per mind tick.** — `ambient_snap.gd`; captured once per `sim_driver._tick()`. *#12.*

## B. The workspace, allocation-free (same winners, zero garbage)

*Verified today: `run_competition()` copies + full-sorts the bid array
(`global_workspace.gd:245–246`), `broadcast()` deep-copies winners
(`global_workspace.gd:283`), and `_bid()` allocates ~20–25 dictionaries per fish
per frame. At 50 fish × 60 Hz that's ~75k dict allocations a second feeding the
GC — for a competition whose answer is 3 winners.*

13. - [x] **Bounded insertion top-K, no sort.** — `_insert_top_bid()` + `_competition_from_sorted()`; parity smoke in `smoke_perf_realtime.gd`. *ledger #13.*
14. - [x] **Kill the winners deep-copy.** — `broadcast()` takes cycle-fresh refs; `commit_workspace_to()` copies to fish. *#14.*
15. - [x] **Bid pool.** — `mind_bid_pool.gd`; `GlobalWorkspace._bid(f, …)` writes reusable slots. *#15.*
16. - [x] **StringName the labels; hoist the literals.** — `_LN_*` StringName constants; night/phi label checks without array literals. *#16.*
17. - [x] **Hoist per-fish invariants out of the per-bid loop.** — phi/fragmented/night scales computed once in `_apply_precision_and_mods()`. *#17.*
18. - [x] **Bids as structure-of-arrays.** — `mind_bid_soa.gd` + `MindKernel.competition()`. *#18.*
19. - [x] **Coalition tags → bitmasks.** — `coal_mask` on bids; `(a & b) != 0` merge in `_competition_from_sorted()`. *#19.*
20. - [x] **Cache `_bias_for()` targets per tick.** — `GlobalWorkspace.cache_cycle_bias_targets()` in `begin_cycle()`. *#20.*
21. - [x] **Dirty-flag the self-model.** — `MindSelfModel.build()` keyed cache on fish. *#21.*
22. - [x] **Fixed rings for meta-states and qualia buffers.** — `MindSelfModel.meta_push()` ring; qualia HO via same path. *#22.*
23. - [x] **Copy-on-write for the mods dict.** — `_apply_precision_and_mods()` skips duplicate when empty. *#23.*
24. - [x] **Measure and widen the habit shortcut.** — wider `context_key`, hit-rate on perf HUD, `HABIT_STRENGTH_RUN` 0.64. *#24.*
25. - [x] **The idle-tank clock.** — `MindTick.idle_slow_mult()` halves mind step after 30 s room idle (protagonists exempt). *#25.*
26. - [x] **Audit the trace no-op path, round two.** — `MindDebug.log_stream()` returns on disabled stream; `MindTrace` already no-ops. *#26.*

## C. Memory as packed math (same recall, 10× the speed)

27. - [x] **Episodic vectors → `PackedFloat32Array` + cached norm.** — `norm` at encode; `similarity_entry()`. *#27.*
28. - [x] **One retrieval per cycle, shared.** — `EpisodicMemory.retrieve_for_situation()` in `MindCycle.begin_cycle()` only. *#28.*
29. - [x] **8-bit quantized episodes.** — `vec_q` + int dot in `EpisodicMemory`; eval-gated via `episodic_quant_8bit`. *#29.*
30. - [x] **Tag-bucketed store with early-out.** — kind-hint scan in `EpisodicMemory.retrieve()`. *#30.*
31. - [x] **Global heatmap decay factor.** — `_feed_heatmap_decay_mul`; renormalize when mul < 0.22. *#31.*
32. - [x] **Running top-3 heatmap cells.** — `_feed_heatmap_top3` + `_refresh_patrol_from_top3()`. *#32.*
33. - [x] **Concepts accumulate at encode time.** — `FishConcepts.ingest_episode()` from `EpisodicMemory._append_episode()`. *#33.*
34. - [x] **Swap-remove in unordered compaction.** — working-memory prune in `fish._update_inner_life()`. *#34.*
35. - [x] **LRU-cap the theory-of-mind table.** — `_tom_touch_lru()` ring of 8 in `fish_mind_science.gd`. *#35.*
36. - [x] **Delta autosave for minds.** — `mind_dirty_save.gd`; dirty fields on encode; delta on autosave (`_save_mind_delta`). *#36.*

## D. Social cognition without N² (the tank as a field)

37. - [x] **Cap and stabilize ToM neighbors.** — K=4 nearest + 0.5 s set hysteresis; runs on mind tick. *#37.*
38. - [x] **Pair-shared geometry.** — `mind_pair_cache.gd`; `MindContagion` reads cached pairs. *#38.*
39. - [x] **Arousal contagion via the intent grid.** — `mind_arousal_field.gd` 4×4×4 deposit/sample. *#39.*
40. - [x] **Reuse boids accumulators for social bids.** — `_boids_neighbor_count`, shared-attention cache; school slow bid. *#40.*
41. - [x] **Δ-gate ToM model updates.** — heading/speed ε gate before charge update. *#41.*
42. - [x] **Mate/rival scans on the cadence bus.** — 0.5 Hz cached preferred/breed partner in `fish.gd`. *#42.*
43. - [x] **One camera-cone pass for "being watched".** — `sim_driver` sets `f._player_watched`; fast bid in `collect_bids()`. *#43.*
44. - [x] **Cached bond vector.** — `bond_seek_steer()` 5 s cache via `_bond_seek_t0`. *#44.*

## E. One brain, many fish (threads, batches, kernels)

*The scaffolding exists and is idle: `mind_sim_snap.gd` (66 lines),
`mind_writeback.gd` (126 lines), `mind_brain_pool.gd` (165 lines),
`mind_rng.gd` (deterministic streams). Perf I #95 threaded the narrator; this
section threads the thinking.*

45. - [x] **The brain thread (the spine of this doc).** — `MindBrainPool`: worker attention; bind/encode on main (proxy typing); double-buffer snap (#46); spatial batch (#47). *#45.*
46. - [x] **Double-buffered snapshots, zero locks.** — `_snap_banks` flip in `MindBrainPool.flush_tick()`. *#46.*
47. - [x] **Batch fish in spatial-hash order.** — `_spatial_job_less()` before worker batch. *#47.*
48. - [x] **BrainPool becomes the scheduler.** — all queued fish per tick; stagger via `MindTick`. *#48.*
49. - [x] **The GDExtension mind kernel.** — `mind_kernel.gd` packed twin; optional `extensions/mind_kernel/` native. *#49.*
50. - [x] **Kernel fallback discipline.** — `MindKernel.boot_self_test()` + `smoke_mind_kernel.gd`. *#50.*
51. - [x] **Column-major drive integration.** — `mind_drive_soa.gd` batch hunger/energy; `fish.tick()` skips when `_drive_soa_integrated`. *#51.*
52. - [x] **Determinism across the thread boundary.** — `MindRng.stream_for_tick()` + `for_fish_tick()`; tick index in `MindBrainPool`. *#52.*
53. - [x] **Data decides the migration order.** — `PerfGovernor.record_ledger()` on each landed item in smoke + doc. *#53.*
54. - [x] **Narrator fully off-main.** — `mind_narrator_worker.gd`; template+line on worker via `MindScheduler`. *#54.*
55. - [x] **Batch the director's thought calls.** — `flush_minute_batch()` coalesces bios/chronicle/intent + drains thought queue. *#55.*
56. - [x] **Prompt skeletons at bio-change time.** — `mind_prompt_skeleton.gd` in `MindContext.build_for_fish()`. *#56.*

## F. The body on a budget (locomotion, physics, small minds)

57. - [x] **GPU boids (compute pass).** — `mind_boids.glsl` + `mind_boids_compute.gd` (GPU + CPU fallback); `fish._boids()` reads SoA accumulators. *#57.*
58. - [x] **Off-frustum analytic swimming.** — `Fish.analytic_body_step()` on frustum-skipped brain ticks. *#58.*
59. - [x] **Clearance queries on the cadence bus.** — `mind_boundary_cache.gd` 0.5 s lateral cache. *#59.*
60. - [x] **NaN sweep to debug builds.** — `_cadence_nan_sweep()` via `SimCadence`; release skips. *#60.*
61. - [x] **Batch particle physics.** — `waste_physics_batch.gd` integrates drifting detritus; `waste_particle.gd` skips duplicate physics when batched. *#61.*
62. - [x] **Micro-fauna at 5 Hz with pose lerp.** — shrimp brain every other sim tick (2× dt); `_process` lerp unchanged. *#62.*
63. - [x] **A global timer wheel.** — `sim_timer_wheel.gd` backend for `SimCadence`. *#63.*
64. - [x] **Guardian follows the same clocks.** — guardian tick at 15 Hz accumulator in `sim_driver._tick()`. *#64.*

## G. Render: one write per fact, one draw per family

65. - [x] **Cache the glow-mesh list.** — `_glow_meshes` built at `_build_body()` finish. *#65.*
66. - [x] **Δ-gate the glow strength.** — skip biolum writes when |Δstrength| < 0.02. *#66.*
67. - [x] **Retire the legacy glow path for batched fish.** — skip child walk when `_glow_meshes` empty (batch-only). *#67.*
68. - [x] **One MultiMesh per fish.** — pivot/bone bend weight in `CUSTOM.r` + vertex wag in `voxel_fauna_mm.gdshader`. *#68.*
69. - [x] **Then one MultiMesh per species.** — `fauna_species_batch.gd` registry + `track_sync`/`sync_all` from pivot transforms (36+ fish via `should_enable`). *#69.*
70. - [x] **Pool the dart-trail smears.** — `dart_trail_pool.gd` 16-slot shared pool. *#70.*
71. - [x] **Pool the transient particles.** — `transient_particle_pool.gd` for splash + cavitation bursts. *#71.*
72. - [x] **Visibility-gate the cosmetics tick.** — frustum + distance gate in `aquarium_visuals.tick()`. *#72.*
73. - [x] **HUD node-ref cache.** — `main_ui_refs.gd` caches TankConfig, UiTicker, NightWatch, tank saves. *#73.*
74. - [x] **Δ-gate the TOD tint.** — `_write_palette_tint_if_changed()` ε=1/512 in `main.gd`. *#74.*
75. - [x] **Glance updates on camera motion.** — camera pos/rot ε gate before `update_player_glance()`. *#75.*
76. - [x] **Key-cache the one-off costume materials.** — `VoxelMat.make_mouthbrood_bulge()` keyed cache. *#76.*
77. - [x] **The uniform ledger smoke.** — `shader_uniform_ledger.gd` + quantize uniforms routed in `main._apply_render_config()`. *#77.*
78. - [x] **Blit MultiMesh buffers.** — `multimesh_buffer_blit.gd` + `VoxelBatch.blit_buffer()` + `WasteParticleBatch.flush_blit()`. *#78.*
79. - [x] **Merge the static aquascape.** — `hardscape_batch.gd` batches pebbles; driftwood/rocks stay individual for biofilm/AO/epiphytes. *#79.*
80. - [x] **Shadow audit at 512×288.** — `shadow_audit.gd` + smoke in `smoke_shader_perf.gd`; main scene lights shadowless. *#80.*

## H. Shaders & post (the Perf I carryovers, ratcheted home)

81. - [x] **Split the quantize monolith.** — runtime tier gates in full shader + compile-stripped `palette_quantize_potato.gdshader`. *#81.*
82. - [x] **Tier variants compile features out.** — `main._apply_render_config()` swaps potato shader at tier 2. *#82.*
83. - [x] **Bake the Worley caustics.** — `baked_caustics.gd` + scrolling sample in `substrate_caustic.gdshader` when `caustic_baked > 0.5`. *#83.*
84. - [x] **Blob shadows → data texture.** — `blob_shadow_tex` 16×1 RGBAF + shader `texelFetch` path capped at 16. *#84.*
85. - [x] **Bake substrate contact AO.** — `substrate_ao_bake.gd` darkens substrate mesh COLOR at build from contact points. *#85.*
86. - [x] **Full-res intermediate audit.** — `render_resolution_audit.gd` + runtime warning in `main._apply_render_config()`. *#86.*
87. - [x] **Capture-driven warm list.** — `shader_warm_capture.gd` records keys + `replay_warm()` on session boot. *#87.*
88. - [x] **Water waves to the vertex stage.** — `water.gdshader` displaces in vertex; fragment keeps caustics/fog only. *#88.*

## I. Audio & IO (finish moving the furniture)

89. - [x] **Synth ring buffer on the audio thread.** — `synth_ring_buffer.gd` drained before queue synth in `_fill_playback_buffers()`. *#89.*
90. - [x] **Block-process the DSP tail.** — 64-sample block append (single mutex hold) in `ambient_audio.gd`. *#90.*
91. - [x] **Pre-rendered bed for potato tier only.** — `potato_ambient_bed.gd` bypass when `shader_perf_tier >= 2`. *#91.*
92. - [x] **Autosave serializes off-main.** — `SaveManager` JSON.stringify + write on `WorkerThreadPool`; thumbnail stays on main. *#92.*
93. - [x] **Buffer the chronicle.** — `story_chronicle_buffer.gd`; flush on cadence + save. *#93.*
94. - [x] **One director round-trip per minute.** — `AIDirector.flush_minute_batch()` coalesces bios/chronicle/intent. *#94.*

## J. Receipts (the proof this doc keeps its contracts)

95. - [x] **The ledger continues.** — `PerfGovernor.record_ledger()` in smoke + per-item notes in this doc. *#95.*
96. - [x] **The mind-tick budget smoke.** — cadence tick-count assert + 150-fish ceiling in `smoke_perf_realtime.gd`. *#96.*
97. - [x] **The replay-parity eval.** — `mind_replay_parity.gd` 8-tick deterministic gate + fixed-fixture smoke. *#97.*
98. - [x] **"Mind Hz achieved" on the perf HUD.** — `MindTick.achieved_hz_per_fish()` + habit hit-rate in `PerfGovernor.hud_line()`. *#98.*
99. - [x] **Alloc-regression ratchet.** — object-count gate on workspace competition in `smoke_perf_realtime.gd`. *#99.*
100. - [x] **The 150-fish contract demo.** — `smoke_perf_contract.gd` + ceiling in `smoke_perf_realtime.gd`. *#100.*

---

## Suggested first serve (effort-sorted; the spine is #1 → #45 → #49)

1. - [x] **#13 + #14 + #16 + #17** — four S-effort cuts on the verified hottest loop
   (workspace competition); zero risk, immediate µs.
2. - [x] **#97 replay-parity eval** — 8-tick deterministic gate landed.
3. - [x] **#1 + #6 + #7 the mind tick** — shipped (`mind_tick.gd`).
4. - [x] **#65 + #67 glow-path cache** — shipped (#65–#67).
5. - [x] **#45 the brain thread** — `MindBrainPool` worker spine (#45–#48).

*Then #49 (the GDExtension kernel) turns the packed-math groundwork (#18, #27,
#51) into an order of magnitude, and #68/#69 do for draw calls what #45 does for
the frame. Land those three spines and the tank runs a full mind for every fish
at any size the player can dream up.*
