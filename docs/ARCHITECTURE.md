# ARCHITECTURE — module map for the carve

*Drafted 2026-06-28 (ENGINEERING #91 / OPUS_HANDOFF Tier 0A). The map that must
exist **before** any god-object decomposition. Wrong map → wrong extraction.*

This is a map a principal engineer can trust, not a folder listing. It answers
the two acceptance questions up front, then gives per-god-object ownership,
public surfaces, verified carve slices (with line numbers as navigational
hints — **follow the symbol, line numbers drift**), the dependency-ordered carve
plan, the import rules that keep cycles out, and a copy-paste carve checklist.

> **Scope.** Four god-objects = ~32.9k LOC = a third of the codebase:
> [`main.gd`](../shaders-godot/godot-project/scripts/main.gd) (9,428),
> [`world.gd`](../shaders-godot/godot-project/scripts/world.gd) (8,713),
> [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) (8,467),
> [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd) (6,281).
> The **mind subsystem** (~30 small modules) is already decomposed — it is the
> *destination pattern*, not a carve target.

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
├── /root/  (7 autoloads — process-wide singletons, see §2)
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

There are **two clocks**:

- **Sim clock — authoritative, 10 Hz fixed.** `SimDriver._physics_process()`
  [sim_driver.gd:2483] accumulates scaled delta and drains `_tick(dt)`
  [sim_driver.gd:3083] at `SIM_DT = 0.1s`. The **mind tick is nested inside the
  sim tick**: `_tick` loops fish and calls `f.tick(...)` [sim_driver.gd:~3290 →
  fish.gd:3208], and `fish.tick` runs cognition via `_update_inner_life()`
  [fish.gd:1188] → `CognitionKernel` / `MindCycle`. So: **mind tick ⊂ fish tick ⊂
  sim tick.**
- **Render/UI clock — per-frame `_process`.** `World._process()` [world.gd:495]
  (visuals, lights, caustics, room) and `Main._process()` [main.gd:1642] (camera,
  follow-cam, HUD, keeper chat) both **read** sim state and **must not mutate** it.

```
        ┌─────────────── 10 Hz fixed (authoritative) ───────────────┐
        │  SimDriver._tick(dt)                                       │
        │    chemistry → plants → FISH BRAINS(mind tick) → waste/eggs│
        │    → algae → water_chemistry.tick → event resolution       │
        └───────────────────────────┬────────────────────────────────┘
                                     │ writes sim state (positions, chem, stats)
                  read-only          ▼            read-only
   World._process() ───────► (sim state) ◄─────── Main._process()
   visuals/lights/caustics                        camera/HUD/follow/chat
```

When you carve, **preserve this direction.** A `VisualsController` or
`HudController` reading `sim.day_phase` is fine; one *writing* a sim field is a bug
the current god-objects can hide and a clean module makes obvious.

---

## 2. Autoloads & shared singletons

**7 autoloads** (`project.godot [autoload]`) — the only legitimate globals. Reach
them with a cached typed ref in `_ready()`, **not** `get_node_or_null("/root/X")`
per call (ENGINEERING #11/#12 — there are 255 such lookups today):

| Autoload | Script | Owns |
|---|---|---|
| `TankConfig` | `tank_config.gd` (2,964 — itself a god-config, ENGINEERING #20) | All tank/scenario/lighting/sentience/music settings, `SPECIES_LIBRARY` |
| `TankSaves` | `tank_saves.gd` | Per-slot save/load, compatibility checks |
| `SpeciesLibrary` | `species_library.gd` | Discovery state, real-species genomes |
| `SteamService` | `steam_service.gd` | Steam integration |
| `AIDirector` | `ai_director.gd` | Offline-first LLM tier ladder + `chronicle_line` |
| `GuardianLlm` | `guardian_llm.gd` | In-process SmolLM2-360M, 3-tier fallback |
| `MusicContext` | `music_context.gd` | Music clock, dance choreography, `now_playing` |

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
         behavior in isolation; wire it into smoke_runner.gd.
- [ ] 7. Verify headless:
         ./scripts/godot.sh --headless --path shaders-godot/godot-project \
           --script res://scripts/smoke_runner.gd
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
