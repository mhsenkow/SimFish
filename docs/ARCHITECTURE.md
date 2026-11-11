# ARCHITECTURE — module map for the carve

*Drafted 2026-06-28 (ENGINEERING #91 / OPUS_HANDOFF Tier 0A). The map that must
exist **before** any god-object decomposition. Wrong map → wrong extraction.*

**Companion:** clocks / state / RNG → [`ARCHITECTURE.md`](../ARCHITECTURE.md).
Doc map → [`INDEX.md`](INDEX.md).

This is a map a principal engineer can trust, not a folder listing. It answers
the two acceptance questions up front, then gives per-god-object ownership,
public surfaces, verified carve slices (with line numbers as navigational
hints — **follow the symbol, line numbers drift**), the dependency-ordered carve
plan, the import rules that keep cycles out, and a copy-paste carve checklist.

> **Scope.** Four god-objects still hold a large slice of the tree. Line
> counts as of 2026-11-10 (v0.2.53): **~45k LOC** —
> [`main.gd`](../shaders-godot/godot-project/scripts/main.gd) (13,794),
> [`world.gd`](../shaders-godot/godot-project/scripts/world.gd) (12,246),
> [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) (11,314),
> [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd) (7,601).
> Heading anchors such as `{#maingd-9428}` are historical; **follow the
> symbol, not the number.** The **mind subsystem** (~30 small modules) is
> already decomposed — it is the *destination pattern*, not a carve target.

---

## TL;DR — the two acceptance questions

### "Where does feeding live?"

Feeding is a **cross-cutting flow**, not one function — and that's the point of
the map. A tap/click becomes food through four owners:

| Step | Owner | Symbol (file:line) | Does |
|---|---|---|---|
| 1. Gesture → intent | `main.gd` (input) | `_process_mouse_input()` [main.gd:1826] (LMB release under `DRAG_DEADZONE_PX`) → and touch tap in `_handle_screen_touch()` [main.gd:4564] | Decides "this gesture is a feed, not an orbit/pick" |
| 2. Drop the food | `main.gd` (feeding) | `_drop_food_at_cursor()` [main.gd:2116] | Ray to water surface, validate, then fan out ↓ |
| 3. Splash visual | `world.gd` (visuals) | `spawn_feeding_boil()` [world.gd:6289] | Cosmetic surface boil |
| 4. Spawn the particle | `sim_driver.gd` (population) | `spawn_player_food()` / `_spawn_waste()` (KIND_FOOD) | Authoritative food entity in the sim |
| 5. Tell the fish | `main.gd` → `fish.gd` | `_alert_fish_to_feed()` [main.gd:2207] sets `heading_offset` / `burst_remaining` / `_startle_*` on `_sim.fish` | Nearby fish orient toward the drop |

So feeding **input + UI** lives in `main.gd`; the **food entity** is `sim_driver`'s;
the **splash** is `world`'s; the **fish reaction** is `fish`'s. After the carve it
should live in a `FeedingSystem` extracted from `main.gd` that *calls* the sim/world
surfaces below — see [main.gd carve](#maingd-9428).

### "What's safe to extract first?"

**`CameraController` out of `main.gd`** (OPUS_HANDOFF 0B). It is the most
orthogonal slice in the whole codebase: orbit/pan/dolly state + apply, with only a
light read of `TankConfig` and the `Camera3D` node, and it is smoke-testable in
isolation (press/drag/release vs deadzone). Nothing in the sim or mind depends on
it. Full dependency-ordered plan in [The carve order](#the-carve-order).

---

## 1. The big picture — scene, tick, data-flow

### Runtime ownership tree (who creates whom)

```
SceneTree
├── /root/  (11 autoloads — process-wide singletons, see §2)
│     TankSaves  TankConfig  SpeciesLibrary  SteamService
│     AIDirector  GuardianLlm  MusicContext
│
└── tank scene (main.tscn)
    ├── World (world.gd)            ← owns the simulation + the visuals
    │   ├── SimDriver (sim_driver.gd)   ← created by World in _ready() [world.gd:217]
    │   │     owns arrays: fish[] shrimp[] eggs[] waste[] plants[]; snails_root
    │   │     owns: water_chemistry, rng (SimRng), topdown (SimTopdown)
    │   ├── fauna_root / plants_root / waste_root / … (Node3D containers)
    │   │     └── Fish (fish.gd) nodes ← spawned by World, registered into SimDriver
    │   ├── DirectionalLight3D / WorldEnvironment / Glass / Hardscape …
    │   └── _visuals (AquariumVisuals), room presets, lights, caustics
    │
    └── Main (main.gd)              ← the player: camera, input, HUD, follow, chat
          holds @onready refs to World, SimDriver, Camera3D, SubViewport, UI panels
```

Key inversion to remember: **`World` owns `SimDriver`** (creates it as a child),
and **`Main` is a sibling view layer** that reads both. `Fish` nodes live under
`World`'s containers but their *array of record* is `SimDriver.fish`.

### The tick & data-flow (`render ← read-only ← sim tick ← mind tick`)

There are **three clock families** (Holistic #010 — see also root
[`ARCHITECTURE.md`](../ARCHITECTURE.md) state table):

1. **Sim clock — authoritative, 10 Hz fixed.** `SimDriver._physics_process()`
   accumulates `dt * time_scale` and drains `_tick(SIM_DT)` at `SIM_HZ = 10`
   (`SIM_DT = 0.1`). Ecology (chemistry, plants, waste, eggs, population events)
   runs here.
2. **Mind clock — nested in the sim tick.** `_tick` calls `f.tick(...)` →
   `_update_inner_life()` → `CognitionKernel` / `MindCycle`. So:
   **mind tick ⊂ fish tick ⊂ sim tick.** `MindScheduler.poll_workers()` runs at
   the start of `_tick`.
3. **Render / UI clock — per-frame `_process`.** `Fish._process` integrates
   locomotion (`_motion_substep`) at render rate using `sim.time_scale`.
   `World._process` and `Main._process` paint and camera — **read-only** on sim.

**Wall-time clocks (must not invent ecology):**

| Use | API | Owner |
|---|---|---|
| Tank dialogue quiet / kind / return gaps | `Time.get_unix_time_from_system` | `TankDialogue` |
| Keeper reply windows | `Time.get_ticks_msec` | `Main` |
| Narrator global voice spacing | sim-scaled `dt` (`GLOBAL_VOICE_COOLDOWN_S = 18`) | `MindNarrator` |
| Promise deadlines | prefer `sim.tank_age_s`, else unix | `TankDialogue` |

```
        ┌─────────────── 10 Hz fixed (authoritative) ───────────────┐
        │  SimDriver._tick(dt)                                       │
        │    chemistry → plants → FISH BRAINS(mind tick) → waste/eggs│
        │    → algae → water_chemistry.tick → event resolution       │
        └───────────────────────────┬────────────────────────────────┘
                                     │ writes sim state (positions intent, chem, stats)
                  read-only          ▼            read-only
   World._process() ───────► (sim state) ◄─────── Main._process()
   visuals/lights/caustics                        camera/HUD/follow/chat
   Fish._process() ───────── locomotion integrate (render rate)
```

| Concern | State owner | Clock | Save owner |
|---|---|---|---|
| Ecology / chem / population | `SimDriver` | 10 Hz sim tick | `SimDriver.save_state()` + `SaveMigrations` |
| Mind / cognition | `Fish` via `MindState` | Nested in `fish.tick` | `fish[].mind` |
| Locomotion pose | `Fish` | Render `_process` | `Fish.to_save_dict()` pos/vel/heading |
| Aquascape | `AquascapeController` | Player / UI | `aquascape` via `SaveManager` |
| Dialogue cooldowns | `TankDialogue` / `Main` | Wall unix / msec | `sim.tank_mind` (memory); reply windows session-only |

When you carve, **preserve this direction.** A `VisualsController` or
`HudController` reading `sim.day_phase` is fine; one *writing* a sim field is a bug
the current god-objects can hide and a clean module makes obvious.

---

## 2. Autoloads & shared singletons

**11 autoloads** (`project.godot [autoload]`, asserted by
`smoke_autoload_contract.gd`) — the only legitimate globals. Reach
them with a cached typed ref in `_ready()`, **not** `get_node_or_null("/root/X")`
per call (ENGINEERING #11/#12):

| Autoload | Script | Owns |
|---|---|---|
| `AppLog` | `app_log.gd` | Structured logging (load first) |
| `Localization` | `localization.gd` | `tr()` from frame 0 |
| `TankSaves` | `tank_saves.gd` | Per-slot save/load, compatibility checks |
| `TankConfig` | `tank_config.gd` | All tank/scenario/lighting/sentience/music settings |
| `SpeciesLibrary` | `species_library.gd` | Discovery state, real-species genomes |
| `SteamService` | `steam_service.gd` | Steam integration |
| `AIDirector` | `ai_director.gd` | Offline-first LLM tier ladder + `chronicle_line` |
| `GuardianLlm` | `guardian_llm.gd` | In-process SmolLM2-360M, 3-tier fallback |
| `MusicContext` | `music_context.gd` | Music clock, dance choreography, `now_playing` |
| `UiTicker` | `ui_ticker.gd` | UI cadence |
| `GamepadInput` | `gamepad_input.gd` | Controller routing |

**Static-class singletons** (preloaded `class_name`, *not* autoloads — called as
`Type.func()`): `CognitionKernel`, `MindCycle`, `MindState`, `MindChannel`,
`GlobalWorkspace`, `EpisodicMemory`, `FishMind`, `FishMindScience`, the `Fish*`
felt-self modules, `SimRng`/`MindRng`, `WorldAtmosphere`, `VoxelMat`, `KeeperInput`,
`KeeperCare`, `MindScheduler`, `MindConversation`, `MindLexicon`, `MindDaring`.
These are the *good pattern* (§3).

---

## 3. The exemplary pattern — the mind subsystem (imitate this)

The carve has a **destination**, and it already exists. ~30 focused `mind_*` /
`fish_*` modules orchestrated through one typed channel. Copy its shape.

- **One typed state object.** [`MindState`](../shaders-godot/godot-project/scripts/mind_state.gd)
  (`class_name`, `SCHEMA_VERSION = 3`) holds the mind as fields, not a loose dict.
  `sync_from_fish()` / `apply_to_fish()` are the *only* sanctioned bridge to the
  fish's scalar fields (kept on `Fish` for save-compat).
- **One host-agnostic entry.** [`CognitionKernel.tick(host, state, percept)`](../shaders-godot/godot-project/scripts/cognition_kernel.gd)
  — `perceive → attend → bind → encode → learn`, MindState in / MindState out. It
  takes a `host: Node`, not a `Fish` — so the same mind could drive a shrimp or the
  TankMind unchanged. **This is the composition target for `fish.gd`.**
- **Pure phase modules.** [`mind_cycle.gd`](../shaders-godot/godot-project/scripts/mind_cycle.gd)
  sequences `GlobalWorkspace` (bid → compete → broadcast), the felt-self spine
  (`FishProtoself → FishCoreAffect → FishRelevance → FishFeltNow → … → FishBinding`),
  `EpisodicMemory`, `MindSelfModel`, `MindScheduler`. Each is static, side-effect-
  scoped, individually smoke-tested (`smoke_mind_channel.gd`, `smoke_felt_self.gd`,
  `smoke_cognition_kernel.gd`).
- **Channel commit.** `MindChannel.for_cycle(f, voiced)` [fish.gd:1190] →
  `MindChannel.commit(f, ms)` [fish.gd:1341] flushes a write-back log instead of
  scattered field pokes.

The lesson for `fish`/`world`/`main`/`sim_driver`: **a thin host that composes
typed sub-components, each with a narrow public surface and its own smoke.**

---

## 4. The four god-objects

For each: what it **owns today**, what it **should own** after the carve, its
**public surface** (what others legitimately call), and the **verified carve
slices** with entry symbols.

### `main.gd` (9,428) {#maingd-9428}

**Owns today:** orbit camera; follow-mode + PiP portal; mouse/touch/keyboard input
dispatch; creature picking; **feeding** (drop + UI + fish alert); keeper chat
(say-edit + follow-thought typewriter); HUD chips/layout/idle-dim; the light panel;
aquascape-mode coordination; notifications/toasts; camera & tank-state persistence.

**Should own (after carve):** the `Main` node as a **thin view coordinator** — it
holds the `@onready` refs (World, SimDriver, Camera3D, SubViewport, panels), wires
signals in `_ready()` [main.gd:1108], and routes `_input`/`_process` to extracted
controllers. Nothing else.

**Public surface (called from elsewhere / signals it consumes):** subscribes to
`SimDriver` signals (`stats_changed`, `eco_event`, `creature_removed`,
`favorites_changed`, `guardian_spoke`, `fish_thought_spoke`, …) and `AIDirector`,
`GuardianLlm`, `SpeciesLibrary`, `TankConfig` signals. Calls into `SimDriver`
(living/favorite creatures, `request_creature_thought`, `spawn_player_food`,
`update_player_glance`, `time_scale`) and `World` (`spawn_feeding_boil`, ripples,
`WATER_HEIGHT`). These calls are heavily `has_method()`-guarded today — typing them
is ENGINEERING #13.

**Verified carve slices** (extract in this order — see §6 for why):

| Slice | Entry symbols (file:line) | Moves | Must stay in Main |
|---|---|---|---|
| **CameraController** (0B, first) | `_process_mouse_input()` [1826], `_zoom_camera_by_factor()` [327], `apply_camera_projection()` [657], `_reset_camera_to_default()` [316], camera state @ ~263-280/900-1000, save/restore [1271-1376] | orbit/pan/dolly state machine + apply + projection + presets | `@onready` camera/world refs; follow-cam *cinematic lerp* in `_process` [~1737]; wheel-dispatch *routing* in `_input` [4486-4503] |
| **FeedingSystem** | `_drop_food_at_cursor()` [2116], `_alert_fish_to_feed()` [2207], `_setup_feed_dock()` [2156], `_show_feed_toast()` [2230], `_feed_*` state [1093-1097] | food drop, fish alert, feed dock UI | the *trigger* in `_process_mouse_input` [1871-1874]; `_project_to_surface()` ray helper |
| **FollowController** | `follow_creature()` [2542], `cycle_follow()` [2644], `_cycle_pool()` [2617], `_update_portal_pip()` [3818], `_gather_creatures()` [3716], `_pick_creature_at_viewport()` [3752] | follow target/mode/scope, PiP portal, creature picking | input dispatch for creature pick; cinematic-cam blend; favorite halos |
| **KeeperChatUI** | `_tick_keeper_input()` [3148], `_on_keeper_say_submitted()` [3086], `_show_follow_thought_typewriter()` [3263], thought-strip layout [3182] | say-edit, follow-thought typewriter, guardian/fish-thought signal handlers | thought-strip *placement* depends on HUD layout; signal wiring stays Main's |
| **HudController** (last, most deps) | `_build_hud_chips()`/`_apply_hud_layout()` (~6000+), light panel [7506-8560], idle-dim in `_process` [1642-1672] | chips, responsive layout, light panel, idle/screensaver dim | top-level panel `@onready` refs; `stats_changed` handler |

### `world.gd` (8,713) {#worldgd-8713}

**Owns today:** environment building (substrate, hardscape, water, glass, light
fixture, heater, the lofi room presets); all visuals/day-night/caustics/room
animation; spawn of every organism (fish/shrimp/snails/plants/corals/floaters/
microfauna); per-frame maintenance (floater drift, biofilm, mineral spots, env
field, flow field); tank-constraint + habitat-sampling queries. **It also creates
and owns `SimDriver`.**

**Should own (after carve):** a thin `World` that creates `SimDriver`, holds the
tank dimensions/containers, and sequences `_ready()` build + `_process()` ticks by
delegating to typed builders/controllers.

**Public surface (called by Fish/Sim/Main):** habitat & constraint queries — `is_inside_tank*()`,
`clamp_*_in_tank()`, `preferred_y_at()`, `sample_flow()`/`deposit_wake()`,
`light_penetration_at()`, `effective_warmth_at()`, `query_floaters_in_radius()`,
`query_lily_pads_in_radius()`, `query_build_shelter_near()`, `nearest_driftwood_pos()`,
`add_mulm_voxel()`, `spawn_feeding_boil()`, ripple spawners, `floater_coverage()`.
Fish reach `World` via `sim.get_parent()` — a coupling to formalize.

**Verified carve slices:**

| Slice | Entry symbols (file:line) | Notes |
|---|---|---|
| **EnvironmentBuilder** | `_build_substrate()` [2310], `_build_hardscape()` [2558], `_build_water_volume()` [2906], `_build_glass()` [3031], hardscape occupancy [1958-1995] | static construction; mutates `terrain_grid`/`substrate_grid` then hands off |
| **MicrofaunaController** | `_maintain_microfauna()` [8094], wriggle/tubifex/mycelium/biofilm maintainers [8102-8249], mulm/film [7620-8022] | pure-visual population upkeep on ~0.8s cadence |
| **VisualsController** (largest) | split `_process()` [495], `_refresh_atmosphere_caches()` [481], light-cycle block [709-949], room presets [6946-7619], ripples [6226-6391] | day/night, caustics, glass, god-rays, room — **read-only on sim** |
| **SpawnController** (most deps, last) | `_spawn_initial_fish()` [4772], `_spawn_fish_at()` [8363], `_spawn_plant()` [4399], floaters/lily/math [5336-5527], genome mutation + habitat sampling [1592-2218] | every spawn calls `sim.register_*`; depends on EnvironmentBuilder queries |

### `fish.gd` (8,467) {#fishgd-8467}

**Owns today:** genome/anatomy fields + voxel body build; locomotion/hydrodynamics;
the ~25-tier behavior state machine; the mind glue (`_update_inner_life`); rendering/
animation; per-fish seeded RNG.

**Should own (after carve):** a thin `Fish` holding genome + node refs and a typed
sub-component set: `FishLocomotion`, `FishBody` (anatomy/render), a data-driven
`BehaviorTiers` table (ENGINEERING #7), and the existing mind (already external —
`fish.tick` just calls `CognitionKernel`/`MindCycle`).

**Public surface:** `tick(dt, neighbors, plants, algae, waste, baby_shrimp, world_bounds)
-> events: Dictionary` [fish.gd:3208] is *the* contract — it returns an events dict
(`die`, `lay_egg_with`, `eat_waste`, `kill_prey`, `release_*_fry`, …) that
`SimDriver` resolves. `init_genome()` [1761], `produce_offspring_genome()` [7525].
The mind reads/writes via `MindState` (the sanctioned bridge) but **dozens of `_mind_*`
/ felt-self scalar fields still live on `Fish`** [~196-379] for save-compat — the
mind-debt ledger (§7).

**Verified carve slices** (first carve = locomotion, OPUS_HANDOFF 0C):

| Slice | Entry symbols (file:line) | Notes |
|---|---|---|
| **FishLocomotion** (0C, first) | `_motion_substep()` [6094], `_boids()` [6779], `_wall_avoid()` [7070], `_local_clearance_push()` [7101], `_constrain_velocity_*()` [8314-8363], Y-band enforcement [4784-4826] | pattern: `static func step(f, dt, neighbors)`; RNG via `f._behavior_rng()` [1681] (`MindRng`/`SimRng` seeded — keep it) |
| **FishBody** (anatomy/render) | `_build_body()` [2224], `_add_voxel_to()` [2784], `_paint_lateral_pattern()` [7420], `_apply_stress_flush()` [2939], `_apply_render()` (~6000s) | voxel build + per-frame color/wag; touches `VoxelMat` (material churn → ENGINEERING #22) |
| **BehaviorTiers** (#7, hardest) | the if-ladder inside `tick()` [3208] — Tier 0 wall/clearance [3493] → egg-guard [3540] → territory [3583] → … → courtship [3909] → forage/predation [4082-4475] → school/boids [4646] | becomes a typed `{priority, guard, action}` table; do **after** locomotion+body are out |
| **(mind)** | already external; `_update_inner_life()` [1188] is the seam | do not re-carve — just stop scattering `_mind_*` fields (§7) |

### `sim_driver.gd` (6,281) {#sim_drivergd-6281}

**Owns today:** the 10 Hz tick sequencing; `time_scale`; `rng` (SimRng); water
chemistry + dissolved O₂ + trophic ledger; population (arrays, neighbor grid,
spawn/die/breed resolution); eco-events + story log; guardian hooks + away-recap;
`update_player_glance` (a **known fake** camera-position proxy [sim_driver.gd:580]).
`SimTopdown` is **already extracted** — the reference carve.

**Should own (after carve):** tick sequencing, `time_scale`, `rng`, signal
emission, and wiring — delegating chemistry/population/events to sub-modules, the
way it already delegates flocking to `topdown.tick(self, dt, …)` [sim_driver.gd:3112].

**Public surface — signals** (the integration backbone; ENGINEERING #16 = type
these payloads): `stats_changed(stats)`, `eco_event(kind,text,severity)`,
`creature_added/removed(creature)`, `favorites_changed()`, `guardian_spoke(text,speaker,action)`,
`guardian_recap_streaming(text)`, `fish_thought_spoke(speaker,text)`, `fish_voiced_wake(f)`.
**Methods:** `register_fish/shrimp/snail/plant()`, `query_*_in_radius()`,
`spawn_player_food()`, `school_pulse()`, `sync_turn_*()`, `density_wave_push_at()`,
`conduct_anchor_pull()` (these last delegate to `topdown`).

**Verified carve slices** (continue the `sim_topdown` pattern, one per session):

| Slice | Entry symbols (file:line) | Notes |
|---|---|---|
| **SimChemistryBridge** | `_tick_dissolved_o2()` [2064], O2 constants [1925-1970], trophic ledger `_record_trophic_*` [1748-1771], `water_chemistry.tick` call [3577] | keep `dissolved_o2`/`co2_level()` as thin accessors |
| **SimPopulation** | spatial grid [2740-2808], `_hatch()` [4424], `_lay_eggs()` [4322], `_release_*_fry()` [4255-4320], event resolution [3785-4046] | `register_*` stay on driver (creature-init callbacks) |
| **SimEcoEvents** | `emit_eco_event()` [1717], `log_story_event()` [5619] | driver keeps emitting the `eco_event` signal |

**RNG debt (blocks Tier 3 replay, OPUS_HANDOFF 3A):** SimRng is wired for the tick,
but raw `randf()`/`randi()` remain in genome/spawn paths that **must** be seeded for
reproducibility — sex assignment [4238, 4261, 4294, 4989], resilience/evo-burst
mutations [4905-5031], algae crash [3780], fish-thought roll [1335]. Cosmetic color
mutations (4242, 4899) may stay raw. Full list lives in the carve session 3A.

### Random-stream ownership (HOLISTIC #017)

| Stream | Owner | Used for | Must not |
|---|---|---|---|
| `SimRng.STREAM_SPAWN` | `SimDriver.rng` | Founding stock positions, counts, sex rolls that affect who exists | Be advanced by VFX / UI glitter |
| `SimRng.STREAM_GENETICS` | `SimDriver.rng` / `MindRng` entity streams | Offspring genomes, heritable rolls | Mix with presentation noise |
| `SimRng.STREAM_BEHAVIOR` | per-fish via `MindRng.for_fish(..., STREAM_BEHAVIOR)` / `Fish._behavior_rng()` | Behavioral replay, bout choices | Be consumed by cosmetics |
| `SimRng.STREAM_EVENTS` | `SimDriver.rng` | Eco events, feed scatter | Cross-contaminate spawn |
| `SimRng.STREAM_COGNITION` | `MindRng.for_fish` (default) | Mind / attention stochasticity | Alter founding stock |
| `SimRng.STREAM_COSMETIC` | `SimDriver.rng` (named) | Presentation-only draws (shimmer, non-sim VFX) | Alter spawn, genetics, or behavior sequences |
| `MindRng` | thin facade | Resolves per-entity stream names into `sim.rng` (fallback seed if no sim) | Invent a second master seed |

**Contract:** drawing from `STREAM_COSMETIC` (or any non-spawn/behavior stream) must
leave founding stock and behavioral replay sequences unchanged for the same master
seed. Demonstrated by `scripts/smoke_sim_rng.gd` (`_cosmetic_isolation`).

---

## 5. The mind-as-host opportunity (why the fish carve matters most)

`CognitionKernel.tick(host, state, percept)` already takes a `host: Node`. The only
reason the mind is "the fish's mind" and not "a mind that drives anything" is the
~40 `_mind_*`/felt-self scalar fields still sitting on `Fish` for save-compat, and
`MindState.sync_from_fish/apply_to_fish` reaching into them by name. Finish #14/#15
(route everything through `MindState`) and the mind becomes portable to shrimp,
snails, or the `TankMind` for free. **That is the highest-value structural payoff of
the whole carve**, which is why locomotion/body come out of `fish.gd` first (to
shrink it and expose the mind seam cleanly) — not the mind itself.

---

## 6. The carve order

Dependency-ordered. Each step sits **behind the PR smoke gate** (`test.yml`, already
shipped) and adds a targeted smoke. Never big-bang.

```
0A  ARCHITECTURE.md ........................ this doc (done)
        │
0B  main.gd  → CameraController ............ most orthogonal; smoke press/drag/release
        │       (FeedingSystem can follow — depends only on Camera ray + Input trigger)
        ▼
0C  fish.gd  → FishLocomotion .............. shrinks the biggest brain-adjacent file;
        │       no new Fish fields; smoke = 3 fish, 50 ticks, no NaN
        ▼
0E  fish.gd  → MindState as sole channel ... phase 1: mind_cycle path MindState-clean;
        │       smoke = sync→mutate→apply round-trip stable; log residual debt (§7)
        ▼
3A  sim_driver → finish SimRng sweep ....... unblocks replay; world/plants/spawn randf
        ▼
sim_driver → SimChemistryBridge / SimPopulation / SimEcoEvents   (one per session,
        │     mirroring the shipped sim_topdown extraction)
        ▼
world.gd → EnvironmentBuilder → MicrofaunaController → VisualsController → SpawnController
        ▼
fish.gd  → FishBody → BehaviorTiers (#7, data-driven table — last & hardest)
        ▼
main.gd  → FollowController → KeeperChatUI → HudController (most-coupled, last)
```

**Within-file ordering rules of thumb:**
- **CameraController before HudController** (`main`): camera is leaf; HUD touches
  every panel + the idle/screensaver loop.
- **Locomotion/Body before BehaviorTiers** (`fish`): the tiers *call* locomotion;
  extract the callee first so the table can reference a stable surface.
- **EnvironmentBuilder before SpawnController** (`world`): spawn queries hardscape
  occupancy + habitat sites the builder owns.
- **Chemistry/Population before EcoEvents** (`sim`): events narrate population/chem
  outcomes; extract the producers first.

---

## 7. Import rules — keep cycles out

The giants currently reach into each other's internals. Define narrow surfaces and
forbid these import/`preload` edges (privatize the rest, ENGINEERING #9/#13):

- **`fish.gd` must not `preload` `world.gd` or `main.gd`.** Fish talks to the world
  only through the `sim` ref it's given and `sim.get_parent()` query methods (§4
  world public surface). Formalize that into a typed `HabitatQuery` interface rather
  than `has_method()` probes.
- **`fish.gd` must not reach `SimDriver` internals.** Communicate *up* via the
  `events: Dictionary` return of `tick()`; `SimDriver` resolves. Never let a fish
  mutate `sim.fish[]`/`sim.eggs[]` directly.
- **`world.gd` / `sim_driver.gd` must not import `main.gd`.** The view layer is a
  *subscriber*. Sim/World expose signals + read-only getters; `Main` connects. A
  sim module importing the UI is the cycle to never create.
- **Render/UI modules must not write sim state.** `VisualsController`,
  `HudController`, `CameraController` read `sim.day_phase`, `sim.bloom_intensity`,
  stats — never assign them. (The data-flow arrow in §1 is a rule, not a diagram.)
- **Mind modules touch the fish only via `MindState`.** No `f.get("_field")` from a
  `mind_*`/`fish_*` cognition module — that's the debt below.
- **Autoloads are leaves.** Reach them through cached typed refs; autoloads must not
  reach back into scene-specific nodes by path.

---

## 8. Mind-debt ledger (the remaining stringly-typed coupling)

Tracked here per OPUS_HANDOFF 0E so the carve has an honest backlog. Baseline
(ENGINEERING Lever 2): **4,383 `.get("…")`**, **916 `has_method()`**, **255
`get_node_or_null("/root/X")`**. Hotspots:

- **Mind ↔ Fish by string.** `MindState.sync_from_fish/apply_to_fish`
  ([mind_state.gd:75-157]) is the *sanctioned* bridge, but cognition modules and
  `fish.gd` still read/write `_mind_*`, `_felt_self`, `_world_model`, `_keeper_pending`
  scalar fields directly. **Target:** route 100% through `MindState`; #14/#15 phase 1
  fixes the `mind_cycle` path first.
  - **0E audit (2026-06-28).** The cycle is a *dual-write* today, by design:
    `GlobalWorkspace.broadcast(f, result, ms)` ([global_workspace.gd:162]) writes
    BOTH `ms.workspace/.workspace_ignited` AND `f._mind_workspace/.attention_focus/
    ._workspace_ignited`, and `_apply_behavior_bias(f, ...)` reads `f.attention_focus`
    back **within the same call**. The felt-self ticks (`FishFeltNow/Binding/…`) and
    the rest of `fish.tick()` likewise read `f.*` directly all frame. So MindState is
    a *parallel view*, not yet the source of truth. Making it the **sole** channel is
    therefore not a local edit to `broadcast` — it requires rerouting every `f.*`
    *reader* across `tick()` to read `ms` (or commit `ms→f` before the readers run).
    That's a behavior-sensitive XL step; do it deliberately, not opportunistically.
  - **Guard rail landed:** [`smoke_mind_state_roundtrip.gd`] pins the contract —
    `sync_from_fish` copies all tracked fields; `apply_to_fish` writes the writable
    subset back byte-stably and does **not** clobber sync-only fields (hunger,
    neuromodulators); dict fields are deep-copied. This is the golden test that lets
    the eventual single-channel flip proceed without silently corrupting the mind.
  - **0E step 1 landed (2026-06-28).** `broadcast` is now **MindState-authoritative**
    for the workspace triplet: it writes `ms.workspace/.attention_focus/.workspace_ignited`
    and mirrors them onto the fish through one typed method `MindState.commit_workspace_to(f)`
    — the read-back of `f.attention_focus` inside `broadcast` is gone. This also **fixed
    a latent revert bug**: `broadcast` set `ms.workspace` but not `ms.attention_focus`,
    so `MindChannel.commit`'s `apply_to_fish` reverted `attention_focus` to its stale
    cycle-start value each frame while the workspace persisted. Guarded by
    [`smoke_workspace_channel.gd`] (sync→broadcast→commit keeps the focus) and the 9
    cognition smokes (no regression). **Remaining:** the felt-self ticks + the rest of
    `tick()` still read `f.*` directly — the full reader-side migration (and the
    non-workspace `tick_attention` path, which has the same revert) is the next step.
- **Cross-god `has_method()` probes.** `main.gd` guards ~all `SimDriver`/`World`
  calls; `fish.gd` probes `world`/`sim`. **Target:** typed `Creature`/`Mind`/
  `HabitatQuery` interfaces (#13).
- **`get_node_or_null("/root/X")` per call.** Replace with cached typed autoload
  refs in `_ready()` (#11/#12).
- **Stringly stats/situations/moods.** `"food"`, `"calm"`, `"keeper_reply"` as bare
  strings across the bid/mood/situation paths → enums/consts (#17).

Each carve session should **shrink one row of this ledger and note the new count**
in the source idea doc's checkbox line — measurement is the point (ENGINEERING §J).

---

## 9. Carve checklist template (copy per extraction)

```
### Carve: <Slice> out of <god-object>.gd   (ENGINEERING #__ / OPUS_HANDOFF __)
- [ ] 1. Pin behavior: identify/extend the smoke that exercises this slice today.
- [ ] 2. New file scripts/<slice>.gd — RefCounted (helpers) or Node (owns subtree).
         Static `func step(host, dt, …)` if stateless; else hold typed state.
- [ ] 3. MOVE code behind the SAME call site — god-object keeps a thin delegate
         (e.g. `func _drop_food(...): feeding.drop(self, ...)`). No call-site churn.
- [ ] 4. Pass deps explicitly (sim, world, config refs). No new global lookups.
         Migrate any randf/randi to the seeded stream (SimRng/MindRng/_behavior_rng).
- [ ] 5. Respect §7 import rules — no new cycle; render/UI slices read-only on sim.
- [ ] 6. Add scripts/smoke_<slice>.gd (extends SceneTree) asserting the pinned
         behavior in isolation; discoverable by `scripts/run_smokes.sh`.
- [ ] 7. Verify headless:
         ./scripts/run_smokes.sh --include <your_smoke_needle>
- [ ] 8. Confirm ZERO behavior change (pixel-identical feel / identical sim trace).
- [ ] 9. Shrink one mind-debt row (§8) if applicable; record the new count.
- [ ] 10. Mark the idea-doc item [x]/partial with a one-line shipped note + commit.
```

---

## 10. Acceptance self-check

- **"Where does feeding live?"** → §TL;DR table + [main.gd carve](#maingd-9428):
  input/UI in `main.gd` (`_drop_food_at_cursor` [2116]), entity in `sim_driver`,
  splash in `world` (`spawn_feeding_boil` [6289]), reaction in `fish`
  (`_alert_fish_to_feed` [2207]). ✓
- **"What's safe to extract first?"** → `CameraController` from `main.gd`; full
  dependency-ordered plan in §6. ✓
- **Map, not listing:** ownership-today vs should-own, public surfaces, verified
  line-anchored slices, carve order with dependency rationale, import/no-cycle
  rules, mind-debt ledger, reusable checklist. ✓

*Line numbers verified against HEAD on 2026-06-28; treat as navigational hints and
follow the symbol. Update this map as slices land — it is the destination, keep it
true.*

---

## 11. Motion architecture (fish)

*Added 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #80.
Verified by reading `fish.gd` at `5ad6dd3` (the Phase 0 commit). Line numbers
are from that commit.*

This section records who writes each transform channel on a fish, in what
order, and on which clock, so the next motion pass doesn't reintroduce the
overwrites that Phase 0 removed (#2–#7). Line numbers are from `5ad6dd3`; the
Phase 1 changes (one stroke clock, the per-draw shader phase, motion profiles as
data, the expression layer) are folded into the clock and shader tables and
listed under [Phase 1 changes](#phase-1-changes).

### The rig

```
Fish (fish.gd root, Node3D)    basis: look_at(heading)  position: the motor
└── BankPivot                  roll, yaw, pitch and scale layers (table below)
    ├── Head                   at the BankPivot origin; head voxels sit ahead of it
    ├── BodyMid                z = -1.5 v
    │   ├── DorsalPivot, Dorsal2 (Dorsal2 has no writer), AnalPivot
    │   └── PecRight, PecLeft
    └── TailPivot              z = +1.5 v
```

Built in `_build_body`: `BankPivot`
([fish.gd:2893](../shaders-godot/godot-project/scripts/fish.gd:2893)), `Head`
(2906), `BodyMid` (3029), `DorsalPivot` (3248), `AnalPivot` (3284), `PecRight`
(3308), `PecLeft` (3314), `TailPivot` (3340). `v` is `adult_voxel_scale`. Head,
BodyMid and TailPivot are siblings, so rotating BodyMid does not carry the tail
(lever 1 in the backlog). The mouthbrood bulge is parented to Head (#8).

### Frame order

`Fish._process` ([fish.gd:6805](../shaders-godot/godot-project/scripts/fish.gd:6805))
runs these steps each rendered frame, with `dt` already multiplied by
`sim.time_scale`:

1. The gravid bulge sets `_body_mid_rest_scale` (6912). The mouthbrood bulge
   updates.
2. **Death is exclusive.** A dying fish runs `_animate_death` (7097) and
   returns. Nothing below runs.
3. **Integration substeps.** The frame is split into 1–20 substeps (6936).
   Each `_motion_substep` (7300) steers, advances `_motor_phase`, integrates
   thrust and drag, moves, and faces the heading. Every substep except the last
   gets `pose_dt == 0` and returns after updating the yaw rate (7679). **Only
   the last substep poses the body**, using the whole frame's `dt`.
4. **Pose pass** (the rest of the last substep). It checks frustum visibility
   (`do_body_anim`, 7684). For a visible fish it writes bank, yaw and pitch,
   then the swim animation: tail, mid-body, the livebearer S, head, gill and
   gape, dorsal, anal, pectorals, fidgets and the BankPivot scale. Then it
   updates the shader quiet level and clamps the pivots (8092–8096).
5. `_tick_fauna_body_color` (colour, not transforms).
6. `_apply_posture_overlays` (6956) updates `_posture_roll` (read by the
   *next* frame's pose pass) and applies fin nicks.
7. `_tick_gill_flush` (6997) may override `Head.scale` for 0.5 s.

**Off-frustum fish write no pose at all.** Their pivots keep the last drawn
pose, and `_swim_phase`, `_pec_phase` and `_gill_phase` stop, because they
advance inside the pose pass. Only `_motor_phase` (physics) keeps running.

### Who writes which channel

| Channel | Writer (line) | Composition | Notes |
|---|---|---|---|
| Fish root basis | `_face_direction(heading)` every substep while speed > 0.04 (7677) | Single | The whole body is tied to the path; there is no head lead (#69) |
| Fish root position | `_motion_substep`: the move, buoyancy, the breath delta (7559–7561), the current carry | Additive deltas | Death moves `position.y` in `_animate_death` |
| Fish root scale | `tick()` growth lerp at 10 Hz (6795); repair paths | Single | Maturity × growth |
| BankPivot.rotation.z (roll) | Pose pass: `_bank + _posture_roll` (7716), then `+=` the shimmy or flash fidget (8062, 8064) | Sum | `_bank` is the turn bank (7713). `_posture_roll` is set by `_apply_posture_overlays` *after* the pose pass, so sleep and cleaning roll arrive one frame late. Death lerps toward π/2 instead (7120). `MotionSchool.bank_correlation` reads neighbours' *drawn* roll ([motion_school.gd:230](../shaders-godot/godot-project/scripts/motion_school.gd:230)), so their posture and fidgets leak into this fish's bank target |
| BankPivot.rotation.y (yaw) | Pose pass: `_bump_yaw` (7718) | Single | The wall-redirect yaw, eased out at rate 14 (#14) |
| BankPivot.rotation.x (pitch) | Pose pass: lerp toward `pitch_target` (7751) | Single, first match | One `if/elif` ladder: cleaning, sift, brake, forage dive, forage rise, courting male, receptive female, senescent, stressed. Death lerps it to 0 (7123). Uses `clampf(dt * 4)`, which depends on frame rate |
| BankPivot.scale | Pose pass: `_body_proportions * _display_scale * _affect_scale` (8090); the same formula at build (3489) | Product | `_body_proportions` are the width, depth and length genes; `_display_scale` is the courtship puff, written just before (8084); `_affect_scale` is tweened by `answer_affect_cue` (1219). Death writes `_body_proportions * shrink` (7128, and 9684 on reload), dropping the display and affect layers on purpose |
| BodyMid.rotation.y | Pose pass: `sin(_swim_phase + body_phase) * (body_amp + 0.4 * wag_amp_extra) + clamp(_turn_lean) * body_flex` (7931), then blended toward the livebearer S by `lb_sig` (7950) | Sum, then blend | `body_phase = π` by default: a standing counter-wag (7793) |
| BodyMid.scale | Pose pass: `_body_mid_rest_scale` × the music kick, eased (7937–7940) | Product | The rest scale is the gravid bulge (#6) |
| TailPivot.rotation.y | Pose pass: `sin(_swim_phase) * amplitude * _gait_amp_bias` + snare flick (7921), `+=` brake (7924), `+=` music trail (7926), then blended toward the S (7948) | Sum, then blend | — |
| TailPivot.scale.z | Pose pass: music trail stretch to 1.06 (7927–7929) | Single | #683 |
| TailPivot.scale.y, rotation.z | `FishAlive.apply_fin_nicks_visual` ([fish_alive.gd:248](../shaders-godot/godot-project/scripts/fish_alive.gd:248)), called from `_apply_posture_overlays` (6960) | Single | A torn caudal. Lerps 0.2–0.25 per frame, so it depends on frame rate |
| Head.rotation.y | Pose pass: lerp toward the head wave + the S head + `tail_recoil_yaw` + saccade + eye look (7989) | Sum, smoothed | No eye pivots; gaze is a head micro-yaw |
| Head.scale | Pose pass: `(breath * eye_pulse, 1, gape_z)` (8013); **also** `_tick_gill_flush` (7007) | **Two writers** | The gill flush runs after the pose pass and wins for its 0.5 s. This is the one remaining two-writer channel on a living fish |
| DorsalPivot.rotation.x, .z; AnalPivot.rotation.x | Pose pass: functions of `_swim_phase` (8016–8019) | Single | Stateless |
| PecRight / PecLeft.rotation.z | Pose pass: `±sin(_pec_phase [+ π/2]) * pec_amp * (1 ± turn_load) ± pec_spread` (8053, 8055) | Single | The brake flare is a term inside `pec_amp` and `pec_spread` (#3) |
| Dorsal2, adipose, veil streamers | None | — | Rigid (#236, #223) |
| All four main pivots | `_sanitize_posture_pivot` (7186) at the end of the pose pass | Clamp | Scale 0.08–2.2; rotation x ±0.55π, y ±π, z ±0.65π. It is the last writer: a layer outside these limits is silently clipped |

### Layer variables

Systems that want to change a channel they don't own set one of these, and the
owner composes it. These are the hooks that replaced Phase 0's overwrites.

| Variable | Set by | Read by | Meaning |
|---|---|---|---|
| `_bank` | Pose pass (7713) | Roll | Turn bank: `−yaw_rate·0.35` plus `centripetal_bank`, same sign (#1) |
| `_posture_roll` | `_apply_posture_overlays` (6967, 6988) | Roll | Cleaning tilt or sleep roll (#4, #5) |
| `_bump_yaw` | `_note_wall_bump` (7285) | Yaw | Visual yaw held through a wall redirect (#14) |
| `_turn_lean` | Pose pass (7700) | BodyMid yaw | Lean that follows the realised yaw rate (#2, #16) |
| `_body_proportions` | `_build_body` (3488) | BankPivot scale | Genes; never written after build |
| `_display_scale` | Pose pass (8084) | BankPivot scale | Courtship puff |
| `_affect_scale` | `answer_affect_cue` tweens (1219) | BankPivot scale | Keeper-answer body cue |
| `_body_mid_rest_scale` | `_process` (6912) | BodyMid scale | Gravid bulge |
| `_brake_pose` | `_motion_substep` (7538–7541) | Pitch, tail, pectorals | Brake amount from the speed gap or a wall bump |

### The clocks

| Clock | Advanced by | Rate | Drives |
|---|---|---|---|
| `_motor_phase` | `_advance_motor_phase`, every substep, visible or not | `locomotion_tailbeat_rate(speed, L, type) × _wag_freq_jitter × _beat_rate_mult` rad/s; the multiplier is effort (`Hydrodynamics.effort_beat_mult`) × glide × courtship × `_beat_mood_mult` (cached at the 10 Hz brain tick). Wraps at 100·2π | Stroke and pectoral thrust, burst-and-glide pace, the visible tail (below), and several slow wander and gulp sines in `tick()` |
| `_swim_phase` | Pose pass: `_motor_phase − π/2 + _visual_phase_offset` | The stroke clock's rate; dancing adds its tempo difference to `_visual_phase_offset`, which otherwise eases to a whole cycle (rate 0.8). The offset starts at π/2 so a new fish keeps its spawn phase | Tail, mid-body, head wave, dorsal and anal fins, tail recoil, `station_keep_pec`, and the shader ripple (`fauna_wave_phase`) |
| `_pec_phase` | Pose pass (8040) | `pec_freq_base × _wag_freq_jitter`: 4.5 + 3.0·speed rad/s, labriform 5.5 + 4.5·speed | Pectorals |
| `_gill_phase` | Pose pass (8006) | `2.2 × _breath_load × _wag_freq_jitter` rad/s | Head-width breath pulse |
| `_breath_phase` | `_breath_motion_delta` (7253), every substep | 0.7–1.55 cycles/s, from `_breath_load` | The root's vertical breath bob |

All four phase clocks start from the same random value at spawn
(`apply_spawn_variation`,
[fish.gd:2197](../shaders-godot/godot-project/scripts/fish.gd:2197)) and then
drift apart, except that `_swim_phase` is derived from `_motor_phase`: the tail
crosses the midline as `max(0, sin(_motor_phase))` thrust peaks (#13, #49).
Everything in the stroke rate is state every fish keeps, so a culled fish
strokes exactly as a drawn one (`smoke_swimming_continuity`).
`_breath_phase` and `_gill_phase` are two breath clocks with unrelated rates.
Smaller clocks: `_courtship_pulse_phase` (7 rad/s), `_lb_quiver` (19 rad/s),
`_buoy_bob_t` (0.55 rad/s) and the shader's own `TIME`.

### The shader contract (`INSTANCE_CUSTOM`)

The header comment of
[voxel_fauna_mm.gdshader:127](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:127)
is the contract. Each component packs two things:

| Component | Integer part | Fraction | Written by |
|---|---|---|---|
| `r` | Bioluminescence × 32 (per fish) | Bone bend weight (static) | `FaunaVoxelBuilder.pack_custom_r` ([fauna_voxel_builder.gd:112](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd:112)) at build; `Fish._push_fauna_inst_custom` (3746) re-packs it with the glow |
| `g` | — | Belly flash | `_push_fauna_inst_custom` |
| `b` | — | Display vibrancy | `_push_fauna_inst_custom` |
| `a` | Motion quiet level (per fish) | Iridescence (static, from the material) | Builder (fraction); `_update_motion_quiet` (3772) through `_push_fauna_inst_custom` (integer) |

- **Bend weight** comes from the pivot the voxel is built on
  (`_bone_bend_weight`,
  [fauna_voxel_builder.gd:116](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd:116)):
  Head 0.08, BodyMid 0.42, TailPivot 1.0, fins 0.72, anything else 0.22.
  Crustacean builders set `lateral_body_wave = false`, which writes 0 (#12).
- **Quiet level:** 0–6 for an awake fish, from `_fin_tail_activity`, with 0.75
  of hysteresis; 14 asleep; 15 dying. The shader reads levels of 8 and above
  as "fins still" and maps the remainder to body-ripple strength
  (`body_act = 1 − (q − 8·fin_still)/7`). Asleep keeps 1/7 of the ripple;
  dying keeps none.
- **What the shader draws:** a body ripple `sin(phase − along·5)` scaled by
  bend weight², where `phase` is the instance uniform `fauna_wave_phase` that
  each fish sets on its pivot MultiMeshes from `_swim_phase` (Phase 1, #11).
  A shared species batch (36 or more of a kind) can't carry a per-fish value,
  leaves it at −1, and falls back to `TIME·6.2`. Fin flutter on weight ≈ 0.72
  runs at `TIME·10.5` and a vertical `cos(TIME·5.3)` term stays on `TIME`.
- **Uploads:** the quiet level only re-uploads a fish's voxels when its
  quantised level changes. The `fauna_vertex_bend` uniform (line 38) is not
  written by game code; only two dev probes set it.

### The rules

1. **One writer per channel.** Each node-property component (for example
   `BankPivot.rotation.z`) is assigned by exactly one function in a frame.
   Anything else that wants to affect it sets a layer variable that the owner
   composes. Don't add a second assignment.
2. **Layers compose; they don't overwrite.** Angles add. Scales multiply. A
   new effect means a new layer variable and one new term in the owner's sum
   or product.
3. **Mode switches are exclusive and declared.** Death (`_animate_death`) and
   save restore (9682–9684) are the only places allowed to take a channel
   over completely, and they are listed in the table above.
4. **Pose once per frame, for visible fish only.** Pose writes belong in the
   pose pass of the last substep. Integration substeps don't touch pivots.
5. **Pose doesn't steer.** Cosmetic layers must not change steering forces
   (#696); `smoke_motion_mind_parity` and
   `smoke_schooling_force_equivalence` check this.
6. **Smoothing uses `1 − exp(−k·dt)` or `MotionEase.damp()`, not `dt·k`.**
   The pose pass was converted in Phase 1 (#48). Brain and mood lerps keep
   `dt·k` so mind-replay parity holds; `scripts/check_motion_lint.sh` stops
   the count from growing anywhere.

Known exceptions in `5ad6dd3`: `Head.scale` has two writers (pose pass and gill
flush); the posture roll arrives one frame late; the school bank correlation
reads neighbours' drawn roll rather than their `_bank`.

### Phase 1 changes

- **One stroke clock** (#13, #49): see the clock table.
- **Per-draw wave phase** (#11, #50): see the shader contract.
- **Motion profiles as data** (#63): the per-locomotion tail, body, head and
  pectoral constants come from `FishMotionProfiles.get_profile()`
  ([fish_motion_profiles.gd](../shaders-godot/godot-project/scripts/fish_motion_profiles.gd)),
  with optional overrides in `data/motion/locomotion_profiles.json`
  (`reload_data()`; note `ClassName.reload()` would hit Godot's own
  `Script.reload()`).
- **Expression layer** (#17): the sim refreshes `_spark_motion` at the brain
  tick for visible fish; the pose eases `_spark_tail`, `_spark_fins` and
  `_spark_still` into tail amplitude, pectoral spread and stillness. Its
  speed, turn and wander scales are not read: pose doesn't steer.
- **Toolkit** for later phases: `MotionSpring`, `MotionChain`,
  `MotionPoseComposer` (rule 1 as code, with a foreign-write check),
  `MotionPoseLibrary`, `MotionEnvelope`, `MotionGaze`, `MotionBreath`,
  `MotionLod`, `MotionEvents`, `MotionMetrics` and others in `scripts/motion_*.gd`.
  The fish pose moves onto the composer with the spine (Phase 2).
