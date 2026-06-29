# Opus handoff — detailed execution brief

*Source of truth for the Opus carve/engine sessions. Companion to the shorter
[OPUS_HANDOFF.md](OPUS_HANDOFF.md) (the why) — this is the **how**, task by task,
with acceptance criteria and smoke specs. Keep it in sync as sessions land.*

## Global context (paste once at the start of any Opus session)

**Project:** walstad loom (Godot 4.6+, repo path `shaders-godot/godot-project/`)

**Read first:** `AGENTS.md`, `docs/OPUS_HANDOFF.md`, `docs/ARCHITECTURE.md`,
`docs/ENGINEERING_EXCELLENCE_IDEAS.md`

**House rules:**
- Strangler-fig only — extract behind existing call sites; no big-bang rewrites
- One idea per session; verify with headless smokes before claiming done
- Smoke command:
  ```bash
  ./scripts/godot.sh --headless --path shaders-godot/godot-project \
    --script res://scripts/smoke_runner.gd
  ```
- Mark shipped items `[x]` in the source idea doc with a one-line note
- Do NOT redo: SimRng/MindRng/CognitionKernel stub, fauna MultiMesh batch,
  PR smoke gate (`test.yml`), systemic security/saves work
- **New `class_name` gotcha:** a freshly added `class_name` is not in Godot's
  global class cache until a project scan. After adding one, regenerate with
  `./scripts/godot.sh --headless --path shaders-godot/godot-project --import`
  (the cache `.godot/global_script_class_cache.cfg` is gitignored; CI regenerates
  it the same way). Otherwise the parser reports "Identifier X not declared".

**God-objects (do not refactor without ARCHITECTURE.md first):**
- `main.gd` (~9.4k) — input, camera, HUD, keeper chat
- `world.gd` (~8.7k) — environment build, visuals, spawn
- `fish.gd` (~8.4k) — locomotion, anatomy, behavior tiers, mind glue
- `sim_driver.gd` (~6.3k) — sim tick, chemistry, events, guardian hooks

---

## Progress ledger

| Session | Task | Status |
|---|---|---|
| 1 | 0A — ARCHITECTURE.md | ✅ shipped 2026-06-28 ([ARCHITECTURE.md](ARCHITECTURE.md); ENGINEERING #91/#8) |
| 2 | 0B — CameraController extract | ✅ shipped 2026-06-28 (`camera_controller.gd` + `smoke_camera_controller.gd`; ENGINEERING #2 partial; commit 3032364 + main.gd delegation in 0fbe6fd) |
| 3 | 0C — fish locomotion extract | ✅ shipped 2026-06-28 (`fish_locomotion.gd` first slice: wall/clearance steering + `smoke_fish_locomotion.gd`; ENGINEERING #1 partial; commit e1c4923) |
| 4 | 0E — MindState phase 1 | 🟡 step 1 landed 2026-06-28: `broadcast` is MindState-authoritative for the workspace triplet via `commit_workspace_to()` (read-back removed; **latent attention_focus revert bug fixed**); `smoke_workspace_channel.gd` + 9 cognition smokes green. **Remaining:** reader-side migration (felt-self + `tick()` read `f.*`; `tick_attention` path still reverts). See ARCHITECTURE.md §8 |
| 5 | 3A — SimRng sweep | ⬜ next |
| 6 | 1C — multi-goal blending (META #9) | ✅ shipped 2026-06-28 (`GlobalWorkspace.blend_behavior_bias` + `smoke_motor_blend.gd`; co-ignition → one skirt vector; META #9 [x]) |
| 7 | 5A — mock LLM for CI (META #77) | ⬜ |
| 8 | 2C — time-slice brain (META #24) | ⬜ |
| 9 | 2A — material pool (META #22) | ⬜ |
| 10 | 3B — record/replay phase 1 (META #33) | ⬜ |

---

## TIER 0 — Do this first (blocks everything else)

### 0A. ARCHITECTURE.md module map (ENGINEERING #91) — ✅ DONE
A module map a principal engineer would trust. Must cover: the four god-objects
(owns-today vs should-own); the good pattern (mind_* modules, MindState/MindChannel,
CognitionKernel stub, sim_topdown extraction); public surfaces per subsystem;
carve order with dependencies; data-flow (`render ← read-only ← sim tick ← mind
tick`); files that must not import each other. Deliverable: `docs/ARCHITECTURE.md`
only (+ optional 20-line carve checklist). Acceptance: another dev can answer
"where does feeding live?" and "what's safe to extract first?" from the doc alone.

### 0B. Decompose main.gd — CameraController (ENGINEERING #2) — ✅ DONE
First strangler-fig from `main.gd`. Extract orbit/pan/dolly/pinch/deadzone/
auto-orbit. Pattern: helper owned by main; main delegates, keeps `@onready` refs.
Requirements: zero behavior change (pixel-identical feel); touch + desktop paths
preserved (`_touch_active`, `DRAG_DEADZONE_PX`); feed-on-release and creature-pick
stay in main or move with a clear API; add `smoke_camera_controller.gd` asserting
orbit only commits past the deadzone. Do NOT extract HUD/notifications/keeper chat
this session. *Shipped as pure-static `CameraController` (TopdownMotion pattern);
main delegates the math; constants re-exported from the module.*

### 0C. Decompose fish.gd — locomotion slice (ENGINEERING #1) — NEXT
Extract locomotion/hydrodynamics (first of ~4 slices). Candidates (verify lines):
`_boids()` [fish.gd:6779], `_wall_avoid()` [7070], `_local_clearance_push()` [7101],
heading/velocity integration `_motion_substep()` [6094], burst/startle heading
overrides, `preferred_y`/`home_y` band logic [4784-4826], `_constrain_velocity_*`
[8314-8363]. Keep in Fish: genome, mind fields, behavior-tier dispatch, voxel body
build. Pattern: `fish_locomotion.gd` (RefCounted) with static funcs taking `Fish` +
`dt`; `Fish.tick()` calls `FishLocomotion.step(self, dt, neighbors)`. Requirements:
mind modules unchanged; no new Fish fields unless necessary; `SimRng`/`_behavior_rng`
for any migrated randf; `smoke_fish_locomotion.gd` spawns 3 fish, 50 sim ticks, no
NaN positions. Do NOT extract the behavior-tier if-ladder (#7) or rendering this
session. Depends on: ARCHITECTURE.md (done).

### 0D. Decompose sim_driver.gd (ENGINEERING #4 — continue sim_topdown pattern)
`sim_topdown.gd` already extracted (flock/sync-turn/conduct). Next (pick ONE per
session): **A)** `sim_chemistry_bridge.gd` — `water_chemistry.tick` wrapper, O2,
trophic ledger hooks ([sim_driver.gd:2064], constants 1925-1970, 3577); **B)**
`sim_population.gd` — neighbor gathering [2740-2808], spawn/die resolution
[4255-4447, 3785-3898]; **C)** `sim_eco_events.gd` — `emit_eco_event` [1717],
`log_story_event` [5619]. `sim_driver.gd` becomes tick sequencing, time_scale, rng,
wiring only. Each slice: move code, leave a thin delegate, add a smoke that runs 10
ticks without error on a box tank. Read: `_physics_process` [2483] / `_tick` [3083].

### 0E. MindState as sole mind↔fish channel (ENGINEERING #14–15)
Phase 1: mind reads/writes ONLY through `MindState`/`MindChannel`, not direct
`f.mind*` field scatter. State today: `mind_state.gd` SCHEMA_VERSION=3
(`sync_from_fish`/`apply_to_fish`); `mind_channel.gd` for cycle commit; fish.gd
still has dozens of `_mind*`/felt-self fields. Phase 1 scope: audit fish.gd for mind
fields accessed outside fish_mind/mind_cycle; route `mind_cycle.gd` phases through
MindState in/out only (no direct `f._mind_workspace` writes in cycle); add
`smoke_mind_state_roundtrip.gd` (sync → mutate → apply → byte-stable keys). Do NOT
migrate all 4,383 `.get()` calls — document remaining violations in ARCHITECTURE.md
"mind debt" section. Acceptance: mind_cycle path is MindState-clean; smoke passes.

---

## TIER 1 — Sentience engine (META §A–B)

### 1A. Active inference as bid currency (META #1) — XL
Add a `free_energy` bid source whose salience = -G (explore) / +G (exploit) from
world-model error + info gain; winner influences motor commit. Files:
`mind_world_model.gd` (`expected_free_energy_explore`, error, variance),
`global_workspace.gd` (`collect_bids`, `run_competition`), `fish_mind.gd`
(`update_conflict`, `tick_ddm`), `mind_cycle.gd`. Feature-flag in TankConfig
(default ON for guardian/voiced fish only first); deterministic with MindRng; keep
existing bids (blend/reweight, don't remove); `smoke_active_inference.gd` (fixed
seed: high error → free_energy bid wins over idle wander). Mark [x] only when fish
orient toward high-error zones.

### 1B. GRU-lite world model (META #3) — L
Replace the 6-D linear predictor in `mind_world_model.gd` with a hand-rolled
GRU-lite (16–32 hidden units, GDScript only, no deps). Persist in `f._world_model`
with schema bump + migration default (old saves get fresh state). `tick(f, sim, dt)`
updates hidden state/prediction/error; save/load through existing fish path;
`smoke_world_model.gd` (same seed+inputs → same error trajectory for 100 ticks).
Plan the GRU math on paper before coding.

### 1C. Multi-goal motor blending (META #9) — M, high visible impact
When workspace co-ignites (e.g. food + threat both above threshold), synthesize a
blended motor vector instead of DDM oscillation ("skirt the edge toward food").
Files: `global_workspace.gd` (detect coalition food+threat in winners), `fish.gd`
(behavior tier / locomotion blended `heading_offset`), `fish_mind.gd` (extend
`update_conflict` or new `blend_deliberation()`). Test: hungry+spooked fish near
food; assert heading is not pure flip-flop (MindRng golden trace on heading-angle
variance over 5s sim time). "Single best 'fish actually think' upgrade" per META.

### 1D. Inter-fish signal bus (META #5) — L
Discrete fish↔fish signals: alarm, food_found, mate, submit. New `fish_signals.gd`
— emit on sim tick; neighbors within radius learn interpretation (simple frequency
table per fish, NOT LLM). Integrate: schooling in fish.gd / sim_topdown.gd;
`global_workspace` bid when a signal is received. Start minimal: 4 signal types,
8-unit radius, 3s decay. Proto-language only — do NOT build full language.
Optional `smoke_fish_signals.gd`.

### 1E. Cognition framework completion (META #12–20, pick ONE per session)
- #12 Plugin bid registry — `global_workspace.gd` registers callables vs hardcoded
- #13 Module DAG — `felt_self_layer.gd` deps as data, topo-sort tick
- #14 Per-module ablation — TankConfig flags per mind module
- #16 `addons/cognition_kernel/` — zero game deps demo scene
- #17 Mind schema migration ladder
- #18 Cognition trace ring buffer (powers debugger #61)
- #20 Cognition LOD tiers T0–T3 by visibility/budget

Read META §B for acceptance criteria.

---

## TIER 2 — Performance (META §C)

### 2A. Shared material pool (META #22) — M
`VoxelMat` material pool keyed by (shader, palette slot). Problem: `VoxelMat.make_*`
creates a new ShaderMaterial per voxel → startup churn + stress-flush cost. Files:
`voxel_mat.gd`, `fish.gd` `_apply_stress_flush` [2939], `plant.gd`. Deliver:
`pool.get(key)` → shared Material; ref-counting or never-free pool (~200 slots max).
Measure: log material count before/after spawning 10 fish in a headless smoke.
Target O(unique materials) not O(voxels).

### 2B. GPU compute boids (META #23) — hard
Move `fish._boids()` separation/alignment/cohesion to a compute shader. Requires:
SoA position/velocity buffers (pairs with META #25); `shaders/compute/boids.glsl` +
RenderingDevice dispatch; CPU fallback. Do NOT start without a profiling baseline
(SYSTEMIC #25 frame budget helps). Acceptance: 60 fish @ 10Hz, boids phase < 3ms on
M-series Mac, or document GPU-path-only.

### 2C. Time-slice brain (META #24)
sim_driver ticks ALL fish minds in one 10Hz burst (15–30ms spike, [sim_driver.gd:
3271-3294]). Change: round-robin N/10 fish per frame for `mind_cycle`; deferred
event resolution (breed/die) at end of full round. Files: sim_driver tick loop,
mind_cycle.gd. Constraints: sim physics stays 10Hz authoritative; mind can lag 1–2
frames off-frustum (pairs with #20 LOD). Add smoke: 20 fish, 100 ticks, no missed
deaths, stats still emit. Profile before/after with `Engine.get_process_time()`.

### 2D. Frame-budget governor (META #62)
Central scheduler tracks ms in sim/mind/render; auto-drops cognition LOD under
pressure. New `frame_budget.gd` (autoload or sim_driver field). Input: last frame
ms, fish count, visible count. Output: `mind_ticks_this_frame`, `llm_tokens_budget`,
skip felt-self for far fish. Wire: sim_driver tick, `guardian_llm` num_predict cap,
mind_cycle skip. Dev HUD toggle (M key). Acceptance: forced overload (32 fish, 16×
speed) degrades gracefully, not stutter.

---

## TIER 3 — Deterministic engine (META §D)

### 3A. Finish SimRng migration (prerequisite for replay)
Complete META #31 — grep ambient `randf`/`randi` in: `world.gd`, `plant.gd`,
`shrimp.gd`, `snail.gd`, sim_driver spawn paths. Replace with
`sim.rng.stream(SimRng.STREAM_*)` / entity streams. Known offenders in sim_driver:
sex assignment [4238, 4261, 4294, 4989], resilience/evo mutations [4905-5031], algae
crash [3780], fish-thought roll [1335]. Cosmetic color mutations [4242, 4899] may
stay raw. Deliver: `smoke_sim_rng.gd` extended; zero randf in sim hot paths (except
explicit UI/debug). Then mark META #31 fully [x].

### 3B. Record/replay (META #33–34) — XL
Record (seed, keeper_input_events[], timestamps) → replay reconstructs tank.
Prereqs: SimRng complete (#31), sim/render split started (#32). Phase 1: log keeper
actions (feed clicks, water change, pause) to JSONL in `user://`. Phase 2: headless
`--replay file.jsonl`. Phase 3: dev scrubber UI (optional). Event sourcing only — do
NOT snapshot full state every frame. Files: sim_driver.gd, main.gd
`_drop_food_at_cursor` [2116], tank_saves.gd. Acceptance: a 2KB recording reproduces
fish count + O2 curve within epsilon at day 3.

### 3C. Headless soak mode (META #35)
`./scripts/godot.sh --headless --path … -- simulate days=30 seed=42`. Promote
`dev/balance_soak.gd` to first-class CLI. Output: CSV metrics (population, O2, nh3,
deaths, trophic_recycle_pct). Wire into CI as optional nightly (NOT a PR gate — too
slow).

---

## TIER 4 — Content & modding (META §E)

### 4A. JSON species from data-schemas (META #41)
Load species from `data-schemas/fauna.schema.json`-validated JSON;
`tank_config.SPECIES_LIBRARY` becomes a fallback only. Use `data-schemas/validate.py`
in CI. Phase 1: one species end-to-end (e.g. guppy) from a JSON file in
`user://mods/`. Do NOT migrate the entire library in one pass.

### 4B. Decide data-schemas + sim-rust fate (SYSTEMIC #52–54, #43–46)
Architecture decision + execution — pick ONE each: **A)** ACTIVATE (GDScript loader
+ CI `validate.py` + doc update) or **B)** ARCHIVE (move to `archive/` with a
README explaining reference-only status). Same for `sim-rust/`: wire via GDExtension
(#96) OR archive with an ADR. Deliver: `docs/adr/000X-data-schemas-fate.md`,
`docs/adr/000X-sim-rust-fate.md`. Update SYSTEMIC items [x].

---

## TIER 5 — LLM moat (META §H)

### 5A. Mock LLM for CI (META #77) — good first LLM Opus task
Deterministic `GuardianLlm` stub for headless CI (no 250MB GGUF). Mode:
`GUARDIAN_LLM_STUB=1` or project setting. Returns a canned string from
`hash(prompt_context)` — stable across runs. Files: `guardian_llm.gd`, autoload
path, `smoke_guardian_plumbing.gd` (create). Verify: smoke_runner includes the new
smoke; CI passes without a model download. Then: SYSTEMIC #15 audit — confirm
`generate_stream` never blocks the main thread.

### 5B. Batched multi-fish inference (META #71)
llama.cpp batch API in the godot_llama extension path. Today: `guardian_llm.gd` FIFO
single jobs, QUEUE_MAX=24. Goal: batch N fish thought prompts per forward pass when
queue depth > 1. Requires native extension changes — coordinate with
`install_godot_llama.sh` pins. Out of scope: training (#76).

### 5C. GBNF grammar decoding (META #72)
Constrain SmolLM2 output to grounded slots via a GBNF grammar in `guardian_llm.gd`.
Slots: mood_word, referent, intensity (see `mind_narrator` grounding). Fallback:
template on grammar failure (existing path). Add a smoke: stub LLM + grammar rejects
a hallucinated event noun.

---

## TIER 6 — Moonshots (only after Tier 0–2)

Each is multi-week; don't start until ARCHITECTURE + perf governor exist.

| META # | Name | Why wait |
|---|---|---|
| 91–100 §J | Open-source cognition addon, WASM web, multiplayer reef, Rust sim core | Needs deterministic sim + LOD + event log |
| 84 | Ecology constraint solver | Needs soak metrics (#35) |
| 93 | Shared multiplayer reef | Needs #33 replay + #51 event log |
| 96 | Rust GDExtension sim | Needs SoA #25 + ADR on sim-rust |

---

## Suggested Opus session order

1: ARCHITECTURE.md (0A) · 2: CameraController (0B) · 3: fish locomotion (0C) ·
4: MindState phase 1 (0E) · 5: SimRng sweep (3A) · 6: multi-goal blending META #9
(1C) · 7: Mock LLM CI (5A) · 8: Time-slice brain (2C) · 9: Material pool (2A) ·
10: Record/replay phase 1 (3B)

## What NOT to send Opus (keep on Composer/Auto)

- shellcheck on scripts (SYSTEMIC #62)
- Doc checkoff hygiene, INDEX.md percentages
- Profiler scope labels (META #66)
- More golden-trace smokes (META #67)
- Feed UX tweaks, alert dedup tuning
- Single-file shadowing / parser fixes
