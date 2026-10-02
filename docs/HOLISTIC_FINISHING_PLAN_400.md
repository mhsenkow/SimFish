# walstad loom holistic finishing plan

This is a 400-task implementation plan for Cursor Composer. Its purpose is to make walstad loom more beautiful, more readable, more efficient, and more convincingly alive while preserving the ecological and cognitive systems already built. The strongest direction is a living aquarium whose history appears in its inhabitants, plants, water, surfaces, and sound. Care should have consequences the player can watch; quiet observation should remain rewarding.

This document proposes work. Unchecked tasks are not claims that their features are entirely absent or broken. Many extend existing implementations. Before changing anything, inspect the current path and its callers; when the acceptance condition already holds, record the evidence and close the task without adding a parallel system.

## Review basis

Reviewed against commit `8a324c6`, the v0.2.36 working tree, on October 1, 2026 local time. The review covered repository instructions, design creeds, architecture and historical backlogs; the script inventory; representative simulation, motion, chemistry, plant, mind, dialogue, rendering, UI, audio, performance, and persistence code; and three freshly rendered views of `valli_jungle` through the real `main.tscn` capture path. This is a broad design and source review, not an exhaustive line-by-line audit or a completed cross-platform playtest.

The capture used a temporary project copy, a separate user-data directory, Godot 4.6.2, Metal on Apple M2 Ultra, midday, and 360 settling frames. It did not use the player's tank saves. No gameplay implementation changes were made for this plan. Existing screenshots were treated as historical references, not current regression evidence. The full smoke suite and long balance soaks were not run during planning.

| Evidence from this review | Implication for the plan |
|---|---|
| 511 scripts under `scripts/`, including 212 `smoke_*.gd` files | Extend the substantial existing system and test coverage. Avoid another disconnected layer of helpers. |
| `main.gd`, `world.gd`, `fish.gd`, and `sim_driver.gd` total 41,185 lines | Extract bounded responsibilities when touching them; a wholesale rewrite would endanger working behavior. |
| New `fish_life_bouts.gd`, `fish_depth_bands.gd`, and continuous `fish_growth.gd` already exist | Refine interruptions, coordination, measurement, and persistence instead of re-adding idle bouts, species bands, or smooth growth. |
| `HudLayout.regions()` and the new UI capture harness already exist | Build on the shared layout system rather than proposing another UI framework. |
| Fresh fit view uses 31 unique colors; surface uses 36; photo uses 25 | Palette overflow is not reproduced here. Preserve the repaired final quantization. |
| Fit view passes the existing frame metrics; surface and photo fail the universal shadow-floor check; photo also exceeds the stipple-step threshold | Inspect scene regions and camera intent before changing global exposure. Whole-frame metrics need camera-specific interpretation. |
| Valli composition report has focal offset `+0.001`, against its generic `0.12–0.75` target | The scene is visually centered in this sample. Improve scenario-specific composition; do not force every aquarium into one compositional rule. |
| Fresh close views show dense stipple, a bright surface canopy, and weak subject/background separation | Prioritize local material hierarchy, depth, leaf silhouettes, and fish readability over extra effects. These are visual judgments from this sample. |
| `KeeperCare.mood_score()` uses fixed freshwater biomass/algae/waste denominators of 600/60/100 | Revisit scale and scenario semantics before using that score to drive more presentation or dialogue. |
| `fish_depth_bands.gd` explicitly compensates for an unresolved depth-reference offset | Resolve the coordinate contract before further band tuning. |
| Capture exit reports renderer resource leaks | Investigate reproducibility and ownership; this run alone does not establish an in-game memory leak or its cause. |
| README, style guide, architecture notes, and project version disagree in places | Reconcile documentation with runtime evidence. The old documents remain useful intent, not unquestionable current specifications. |

## Creative direction

**A composed picture at a glance, a discoverable ecosystem when watched, and a place with a memory when revisited.**

Beauty comes from a hierarchy: one legible focal area, supporting plant masses, useful negative space, a restrained water medium, and a quiet room. Keep the limited palette and procedural voxel identity. Preserve imperfections that communicate age and ecology: grazed glass, damaged leaves, uneven growth, settled detritus, and small generations of animals. Tune their density and placement so they read as history rather than uniform noise.

Aliveness comes from different rhythms, sustained intentions, interruptions, local interactions, and consequences that outlast the initiating action. One fish notices food; others learn from it; a shy individual waits; a flake reaches the bottom; shrimp gather; uneaten material enters the substrate loop. Each link should use real state. Constant random motion, globally synchronized reactions, and a stream of explanatory text would weaken this effect.

Complexity should be discoverable in layers. At first the player sees a beautiful tank and understands one useful action. Later they recognize an individual, notice a territory, connect shade to growth, and recognize the tank's long history. Chemistry graphs, cognition diagnostics, and tuning controls belong behind deliberate exploration. Existing memory, learning, and voice systems should explain what happens without claiming consciousness or inventing events; preserve `SOUL_CREED.md`.

## How Composer should execute this plan

Use the following as the initial Composer instruction:

```text
Read AGENTS.md and docs/HOLISTIC_FINISHING_PLAN_400.md. Implement the next
dependency-ready task in the current wave. First inspect its existing code,
call sites, related backlog, and tests. Reuse the current implementation.
Work in batches of at most 3 closely related tasks; do not attempt all 400
in one edit. Keep the aquarium's pixel-art direction, ecological causality,
behavioral diversity, grounded voice, save compatibility, and offline play.

For each task record: status, concrete change, files, relevant validation,
and remaining limitation. Check it off only when its Done condition holds.
If it already works, cite the evidence and close it as verified existing.
If a proposal proves harmful, document the reason and replacement decision;
do not silently implement it to satisfy the list. Split L work into bounded
commits while retaining its ID. Never rewrite working subsystems wholesale.

Use isolated user data for all game runs. Run the appropriate existing
smokes, compile/warning checks for code changes, and visual or audio review
where applicable. Use scripts/run_smokes.sh, not smoke_runner.gd. Do not
relax gates, add baseline failures, or call a helper smoke_*.gd. Use SimGate
at contracted sim/world boundaries. Preserve unrelated working-tree edits.
After each batch report evidence and continue to the next ready task.
Do not publish, release, or change external service settings under this plan.
```

Every task has a stable ID, priority, effort, an entry point, and a completion condition. Bare `.gd` filenames refer to `shaders-godot/godot-project/scripts/`; shader names refer to its `shaders/` directory; `dev/` refers to its development tools. These are starting points, not mandatory ownership decisions. New artifacts or modules are explicitly described as new. Prefer symbols over historical line numbers.

**Priority:** P0 protects evidence, state, and trustworthy execution; P1 produces the largest immediate improvement; P2 deepens the experience once foundations hold; P3 is later polish or an optional capability. **Effort:** S is a focused change, M is roughly one implementation session, L requires several bounded sessions. These are relative sizing estimates, not delivery promises. Acceptance numbers introduced below are proposed project targets, not measured current performance or biological facts.

**Dependencies:** The table gives hard prerequisites for each track. Specific task dependencies override it. Within a track, proceed numerically when tasks share data or build on a previous row; independent tasks can be pulled forward. Cross-track links are written as task IDs. Do not postpone a small P1 improvement behind an unrelated P3 item just because its ID is lower.

| Track | IDs | Hard prerequisites | Existing work to extend |
|---|---|---|---|
| 1 Evidence and execution | 001–020 | None | `BROAD_DIRECTIONS_20.md`, existing dev probes |
| 2 Composition and camera | 021–040 | 001–004 | `VISUAL_DIRECTIONS_20.md`, `scape_composition.gd` |
| 3 Palette lighting and water | 041–060 | 002–004 | `REFINEMENT_100_IDEAS.md`, `VISUAL_DIRECTIONS_20.md` |
| 4 Habitat and material detail | 061–080 | 002–004 | `REAL_TANK_FIDELITY_200.md`, `VISUAL_POLISH_200_IDEAS.md` |
| 5 Individual fish motion | 081–100 | 001, 005, 010 | `FISH_ALIVE_1000_IDEAS.md`, `LIVING_MOTION_IDEAS.md` |
| 6 Social behavior and life cycles | 101–120 | 005, 010, 081 | `GOALS.md` A–B and H4, existing social and breeding systems |
| 7 Invertebrates and food web | 121–140 | 005–006, 010 | `GOALS.md` C and H5, `REAL_TANK_FIDELITY_200.md` |
| 8 Plant growth and succession | 141–160 | 004, 006, 010 | `PLANT_SYSTEMS_50_IDEAS.md`, `PLANT_NATURALISM_1000_IDEAS.md` |
| 9 Surface and shared flow | 161–180 | 004–006, 010 | `HYDRODYNAMIC_LIFE_IDEAS.md`, `LIVING_MOTION_IDEAS.md` |
| 10 Chemistry and resilience | 181–200 | 006, 010, 011 | `CHEMISTRY_ORACLE.md`, `GOALS.md` H |
| 11 Memory and visible agency | 201–220 | 005, 010, 012 | Mind campaign documents and `SOUL_CREED.md` |
| 12 Dialogue and keeper bond | 221–240 | 012, 201, 205 | Conversation, keeper, and tank dialogue systems |
| 13 Care and aquascaping | 241–260 | 004, 007, 010 | `AQUASCAPING_CRAFT_IDEAS.md`, `care_feedback.gd` |
| 14 Interface and accessibility | 261–280 | 007–008 | `hud_layout.gd`, `panel_theme.gd`, onboarding backlog |
| 15 Discovery and long play | 281–300 | 007, 012, 261 | `ONBOARDING_LEGIBILITY_IDEAS.md`, chronicles and milestones |
| 16 Sound and atmosphere | 301–320 | 009–010 | `MUSIC_DANCE_IDEAS.md`, `MUSIC_DANCE_PLAYBOOK.md` |
| 17 Rendering performance | 321–340 | 002–005, 009, 013 | Performance campaign documents and current batching |
| 18 Simulation architecture | 341–360 | 005–006, 010, 013 | `ARCHITECTURE.md`, `OPUS_HANDOFF_DETAILED.md` |
| 19 Persistence and platforms | 361–380 | 001, 010–011, 013 | Existing migrations, platform matrix, smoke gates |
| 20 Integration and release readiness | 381–400 | 014–020 for setup; affected tracks for final gates | `INDEX.md`, CI, Steam and landing-page source |

## Delivery waves

These are slices through the tracks, not six more task lists. Start with one complete, visible improvement and carry it through validation before opening many fronts.

| Wave | Scope and exit |
|---|---|
| A Establish trust | 001–020. Reuse this review's evidence, finish missing baselines, and establish isolated reproducible runs. |
| B Make the existing tank read beautifully | P1 tasks in 021–100 and 261–280; 181–184, 321–326, 338–339, 361–364. Exit with improved fixed captures, readable animals, coherent status, and no behavior or save regression. |
| C Connect the living system | 101–200 plus remaining 081–100; prioritize causal gaps and existing partial hooks. Exit with a traceable feeding loop, day/night transitions, recovery, and bounded populations. |
| D Make care and relationships meaningful | 201–300, respecting cross-links. Exit with grounded individual continuity, understandable tools, and a satisfying return visit. |
| E Sustain the experience | 301–380 and remaining P2/P3 refinements. Pull measured performance and persistence fixes forward whenever earlier work needs them. |
| F Integrate and hand off | 381–400. Review the combined result across scenarios, speeds, devices, and long sessions. External publishing remains a separate decision. |

For a small first Composer batch, do **001, 002, and 003**. The first visible batch after baseline work should target **021, 041, and 047** using the same Valli capture seed. Preserve an improvement only when it helps the frame as a whole.

**Execution evidence:** [HOLISTIC_FINISHING_LEDGER.md](HOLISTIC_FINISHING_LEDGER.md). Checkboxes below are claims only when the ledger records matching evidence.

## Plan coverage note

This file currently authors tracks **1–8** (tasks **001–160**). Tracks **9–20** (161–400) are named in the delivery table above and remain to be expanded in a follow-on edit; do not invent checkbox rows without the same entry-point and Done-condition rigor used here.

## 1 Evidence and execution

- [x] **001 [P0 S] Isolate every development run.** Extend the dev launch workflow around `scripts/godot.sh` to use a scratch project/user-data directory and distinct output paths. **Done:** a capture and smoke run leave a before/after hash inventory of the real tank directory unchanged; existing overrides are preserved.
- [x] **002 [P0 M] Establish a small visual baseline matrix.** Use `dev/visual_capture.gd` for beginner, Valli, blackwater, reef, and a nonrectangular tank at day and night. **Done:** fixed seed, tier, resolution, clock, build, and settled-state metadata accompany comparable fit and close images.
- [x] **003 [P1 S] Make visual metrics respect camera intent.** Extend `frame_metrics.gd` with named scene regions and per-view expectations. **Done:** a close-up lacking the dark room is not failed solely by the hero-view shadow floor; washed-out subjects still produce useful evidence.
- [x] **004 [P0 M] Replace guessed build waits with observable readiness.** Expose completion of staged world construction to `dev/visual_capture.gd` and `dev/ui_capture.gd`, then retain a bounded cosmetic settle. **Done:** slow and fast machines capture the same completed content, with a timeout naming unfinished stages.
- [x] **005 [P1 M] Save a behavioral baseline by species.** Extend `dev/fish_behaviour_probe.gd` reports with seed, population, time scale, tier, and scenario. **Done:** depth, speed variance, hover/dart share, turns, pecking, and neighbor correlation are reproducible across several seeds, with sample counts reported.
- [x] **006 [P1 M] Establish ecological trajectories.** Use `dev/balance_soak.gd` to record representative fresh, established, sparse, dense, and reef tanks. **Done:** reports include nitrogen, oxygen minima, births, deaths, biomass, and recovery after one feed pulse; conclusions distinguish sampled seeds from universal guarantees.
- [x] **007 [P1 S] Preserve the new UI layout baseline.** Run `dev/ui_capture.gd` against wide and narrow logical viewports and save overlap/focus/Escape reports. **Done:** existing region-system fixes are documented as present, with remaining failures tied to a specific state and image.
- [x] **008 [P1 M] Expand layout evidence to difficult content.** Extend the UI harness with enlarged text, pseudolocale, long creature names, and a controller-only path. **Done:** each state is navigable and its primary action visible; reported intentional overlaps are narrowly identified.
- [x] **009 [P1 S] Record an audio reference set.** Use `dev/audio_probe.gd` for healthy, stressed, day, night, full, and simple beds. **Done:** short listenable files and peak/RMS/silence measurements establish current behavior without deriving sound quality from numbers alone.
- [x] **010 [P0 M] Map authoritative state and clocks.** Update the relevant part of `ARCHITECTURE.md` from current call sites, including render-time locomotion, mind timing, ecology, and wall-time dialogue cooldowns. **Done:** every cross-system change below can identify its state owner, clock, and save owner.
- [x] **011 [P0 M] Create representative save fixtures.** Derive small synthetic fixtures for an old tank, a breeding tank, a learned fish, a custom scape, and a reef. **Done:** fixtures contain no private player text and load through normal migration/repair paths without silent data loss.
- [x] **012 [P0 M] Inventory grounded player-facing claims.** Trace status, care hints, fish headlines, tank dialogue, and chronicle statements to their inputs. **Done:** an evidence map identifies supported facts, inferences, and missing context; speculative internal names do not become factual claims to players.
- [x] **013 [P1 M] Record a performance budget by workload.** Extend existing `PerfGovernor` reporting for default, dense, mature, and interaction-heavy tanks. **Done:** p50/p95/p99, hardware, cap, tier, draw calls, entities, and main-thread spikes are recorded without claiming the review machine represents low-end devices.
- [x] **014 [P1 S] Reconcile the documentation baseline.** Update version, scenario counts, render-resolution descriptions, autoload count, and test-runner guidance from the current tree. **Done:** README, architecture, style guide, and engineering creed no longer disagree on those operational facts.
- [x] **015 [P1 M] Connect this plan to existing backlog ownership.** Add a compact cross-reference ledger in `docs/INDEX.md` or an adjacent planning ledger. **Done:** each completed batch cites its older overlapping campaign items, preventing two agents from implementing the same capability independently.
- [x] **016 [P0 S] Establish completion evidence for Composer.** Add an execution-log section or companion ledger using task ID, status, files, checks, and artifact paths. **Done:** implemented, verified-existing, deferred, and rejected proposals are distinguishable; checkbox count alone is never a completion claim.
- [x] **017 [P1 S] Pin deterministic random-stream ownership.** Document the existing `SimRng` and `MindRng` streams used by founders, decisions, plants, and cosmetics. **Done:** adding a cosmetic draw cannot alter founding stock or a behavioral replay; demonstrated with one targeted comparison.
- [x] **018 [P1 M] Define the minimum observation contract.** Build a fixture-driven checklist for food response, rest, shelter, schooling, grazing, growth, and decay. **Done:** each behavior has a trigger, a visible sign, and a measurable state transition; no requirement forces every event into every minute.
- [x] **019 [P1 S] Set scenario-specific visual intent.** Extend scenario metadata or design documentation with focal subject, quiet region, dominant plant form, and intended water character. **Done:** sparse stone gardens and dense jungles receive different composition expectations instead of one universal density score.
- [x] **020 [P0 S] Make task selection dependency-aware.** Add a lightweight validator for this plan's IDs and execution ledger, using existing repository tooling where practical. **Done:** it catches duplicate/missing IDs and completed tasks whose explicit prerequisites lack evidence, without becoming a separate project-management application.

## 2 Composition and camera

- [x] **021 [P1 M] Improve the Valli default frame.** Tune `scenario_picker.gd`, `camera_controller.gd`, and `scape_composition.gd` so the jungle has a readable passage, supporting blade masses, and a clear animal viewing area. **Done:** before/after fit and photo captures improve subject separation without removing its dense-jungle identity.
- [x] **022 [P1 M] Fit the tank into the usable viewing region.** Feed `HudLayout`'s available center area into camera framing. **Done:** opening a side panel keeps the relevant tank area visible through a restrained transition, and closing it restores the player's previous framing rather than resetting the camera.
- [x] **023 [P1 S] Bound how much stand enters the hero view.** Adjust camera fit against tank and stand bounds in `camera_controller.gd`. **Done:** substrate, waterline, and fixture remain visible while the stand no longer dominates short or wide tanks; user-authored camera views stay intact.
- [ ] **024 [P1 M] Preserve subjects in close follow.** Refine follow offsets and minimum distance around `camera_controller.gd` and `main.gd`. **Done:** newborn, adult, and large centerpiece fish remain readable without clipping glass, crossing the near plane, or occupying the entire screen.
- [ ] **025 [P1 M] Add an occlusion-aware follow adjustment.** Reuse hardscape/plant occupancy when the followed animal is hidden for a sustained interval. **Done:** the camera makes a small bounded correction, never constantly dodges foliage, and allows intentional hiding to remain visible as hiding.
- [ ] **026 [P2 S] Keep a remembered observation perch.** Extend `camera_views_panel.gd` with a simple return-to-last-manual-view action. **Done:** following a creature or inspecting an event can end at the previous pose, including zoom, without spawning duplicate saved presets.
- [x] **027 [P1 M] Remove camera threshold chatter.** Review pixel snap, orbit damping, and follow deadzones together. **Done:** slow pans have stable screen-space stepping, resting fish do not shake the camera, and the underlying simulation remains continuous.
- [ ] **028 [P2 M] Make surface and underside views intentional.** Refine the existing `surface`, `photo`, and `photo_up` capture/camera concepts into useful presets. **Done:** floaters, hanging roots, and surface reflections are visible without the camera residing inside an opaque pane or plant mass.
- [ ] **029 [P2 S] Give each vessel a considered starting angle.** Add per-shape framing hints through `tank_spec.gd` and scenario metadata. **Done:** hex, sphere, cylinder, and box each show recognizable volume and usable swim space at all offered sizes.
- [x] **030 [P1 M] Compose negative space in three dimensions.** Extend `scape_composition.gd` beyond mass-center checks with a coarse swim-corridor measurement. **Done:** dense planting can score well while retaining connected open water; avoid deleting established growth just to satisfy a score.
- [ ] **031 [P2 M] Vary plant mass by region.** Refine procedural placement in `world.gd` using existing scenario styles. **Done:** seeded layouts show deliberate foreground, midground, and background masses with controlled irregularity, instead of uniformly sprinkling every species everywhere.
- [ ] **032 [P2 S] Give focal hardscape supporting space.** Adjust `driftwood_form.gd` and placement rules so a chosen branch, stone, or stump has a readable silhouette. **Done:** supporting plants frame its contour from the default angle without imposing a bare halo from every angle.
- [ ] **033 [P2 M] Compose alternate sides of the aquarium.** Add a few camera-sampled checks to procedural scape evaluation. **Done:** rotating a tank does not reveal an accidental wall of identical stems or an unsupported hardscape backside; repair rules remain seed-stable.
- [ ] **034 [P2 S] Keep near-glass animals visible.** Review camera near clipping and glass edge behavior for snails, shrimp, and fish. **Done:** organisms on the front pane remain readable in close views without applying a global through-wall outline.
- [x] **035 [P1 S] Unify camera speed across vessel sizes.** Derive orbit, pan, and dolly sensitivity from viewing distance and footprint scale. **Done:** Compact and Grand tanks take comparable input effort to inspect, with no abrupt sensitivity change after selecting a saved view.
- [ ] **036 [P2 M] Make focus transitions interruptible.** Refine camera transitions initiated by residents, chronicle, and inspection controls. **Done:** manual input immediately takes control; a deleted or departed target ends gracefully; rapid selections never queue a tour of obsolete targets.
- [ ] **037 [P2 S] Improve thumbnails as compositions.** Use the established fit logic in `tank_menu.gd` thumbnail capture. **Done:** every vessel fits, the tank is distinguishable at card size, and thumbnail generation neither advances care actions nor overwrites a manual camera pose.
- [ ] **038 [P3 M] Add an optional quiet observation tour.** Extend existing auto-orbit with a few scenario-aware stopping points and long dwell times. **Done:** it is opt-in, stops on input, respects reduced motion, and never chases every event or exposes unfinished geometry.
- [ ] **039 [P2 S] Show framing intent while aquascaping.** Reuse the composition model in `aquascape_controller.gd` for optional guide overlays. **Done:** guides distinguish focal mass, negative space, and blocked views without grading a natural jungle as an error.
- [x] **040 [P1 M] Regrade the scenario contact sheet.** After 021–039 as applicable, compare identical seeded views across all shipped scenarios. **Done:** record a small set of scenario-specific corrections; default camera and scape decisions are judged together, not by individual screenshots alone.

## 3 Palette lighting and water

- [x] **041 [P1 M] Separate near subjects from distant water.** Tune `world_water_visuals.gd`, `water.gdshader`, and the quantizer using the fresh Valli close view. **Done:** near fish and leaves recover local contrast while the back of the tank retains depth haze and the final palette remains bounded.
- [x] **042 [P1 S] Preserve the final palette lock.** Extend existing palette checks to day/night transitions, care effects, outlines, and photo presets. **Done:** palette limits are applied to the aquarium render at the intended stage, with UI and explicitly documented alternate modes evaluated separately.
- [x] **043 [P1 M] Clarify the supported render resolutions.** Reconcile `render_resolution_audit.gd`, render settings, and the style guide. **Done:** each fidelity tier has an explicit internal grid and nearest-neighbor scaling behavior; resized windows do not silently blur pixel edges.
- [x] **044 [P1 M] Tune regional dither strength.** Refine `palette_quantize.gdshader` so room, water, glass, substrate, plants, and fauna spend different texture budgets. **Done:** large quiet areas stay quiet, while soft water gradients survive; hard animal contours do not gain crawling stipple.
- [ ] **045 [P2 S] Stabilize dither during slow camera movement.** Audit pattern anchoring against camera snap and material coordinates. **Done:** a recorded slow orbit avoids distracting pattern swimming on stationary glass and rocks without freezing legitimate subpixel animal movement.
- [x] **046 [P1 M] Protect color identity under tint stacks.** Trace biotope, day phase, health, depth, and material tint composition through `palette_tint.gdshaderinc`. **Done:** representative red, blue, yellow, and green subjects remain distinguishable in each biotope without double-applying saturation or value loss.
- [x] **047 [P1 M] Reduce the dominant bright canopy in close views.** Tune floater, surface, and foliage lighting together. **Done:** Valli underside views retain luminous surface light but reveal leaf overlap and gaps; fixing the canopy does not globally darken fish or the room.
- [x] **048 [P1 S] Give blackwater its own contrast strategy.** Adjust its absorption and highlight allocation through scenario palette settings. **Done:** water reads as tea-colored depth while near eyes, fins, and wood edges stay legible; healthy blackwater is not presented as universal poor clarity.
- [ ] **049 [P2 M] Localize fixture emphasis.** Refine `lighting_rig.gd` and shared beam sampling so a moved lamp changes a bounded lit region. **Done:** surfaces, plants, water shafts, and fish agree on the light's location without brightening the entire tank uniformly.
- [x] **050 [P1 S] Preserve shadow structure at close range.** Use camera-aware metrics from 003 to tune material shadow ramps. **Done:** cavities, leaf overlaps, and wood undersides have readable dark steps in close views without manufacturing black pixels merely to pass a histogram test.
- [ ] **051 [P2 M] Separate bloom, silt, and tannin appearance.** Refine existing water inputs rather than one generic murk scalar. **Done:** controlled fixtures for suspended detritus, algal bloom, and stained water are visibly different and settle or persist according to their source state.
- [ ] **052 [P2 S] Make caustics follow the medium.** Connect existing caustic intensity to surface agitation, canopy cover, and turbidity consistently. **Done:** patterns weaken under dense floaters and opaque water, and stay subordinate to creature silhouettes.
- [ ] **053 [P2 M] Align shafts with actual openings.** Use `hardscape_occluders.gd` and canopy density to limit light shafts. **Done:** a large leaf mat or solid rock does not visibly transmit a full-strength shaft; coarse approximations remain stable while the camera moves.
- [ ] **054 [P2 S] Keep night illumination biologically legible.** Tune existing night light and bioluminescence settings by scenario. **Done:** sleeping fish, active nocturnal residents, and dark water remain distinguishable without making every organism glow or turning night into tinted daytime.
- [ ] **055 [P1 M] Unify glass contribution across vessels.** Compare `glass.gdshader` and `glass_panel.gdshader` on box, hex, cylinder, and sphere. **Done:** pane overlap and curved geometry do not multiply haze or highlights into opaque walls at common viewing angles.
- [ ] **056 [P2 S] Give the room a supporting value range.** Refine `world_room_builder.gd` and `world_atmosphere.gd`. **Done:** the tank draws the first glance in every room preset while fixtures, stand contact, and room depth remain readable.
- [ ] **057 [P2 M] Make health-related grading gradual and honest.** Trace visual health inputs back to corrected care semantics in 181–184. **Done:** a localized or temporary issue does not desaturate every inhabitant instantly; severe sustained stress remains recognizable. **Depends:** 181–184.
- [ ] **058 [P2 S] Preserve waterline readability.** Tune meniscus thickness and contrast across views and internal resolutions. **Done:** the line remains crisp at the intended grid without appearing as a thick luminous frame or escaping nonrectangular footprints.
- [ ] **059 [P3 S] Harmonize optional CRT and outline modes.** Audit their ordering, contrast, and saved settings in `render_panel.gd`. **Done:** toggling either preserves intended palette behavior and text clarity; the default look does not require either to repair weak silhouettes.
- [ ] **060 [P1 M] Compare lighting in motion.** Record short fixed-path clips at dawn, noon, dusk, and night for representative biotopes. **Done:** palette transitions, highlights, haze, and dither change smoothly; freeze-frame improvements that introduce temporal shimmer are rejected.

## 4 Habitat and material detail

- [ ] **061 [P1 M] Make substrate layers match the actual bed.** Trace `TankFidelityRuntime.strata_from_profile()` into terrain rendering. **Done:** sloped beds show soil and cap thickness consistent with local geometry rather than a decorative horizontal band unrelated to the surface.
- [ ] **062 [P1 S] Reduce repetitive gravel patterns at the glass.** Refine the existing grain population shader using stable per-grain variation. **Done:** close views retain distinct grains and fines without obvious tiling or sparkly frame-to-frame re-randomization.
- [ ] **063 [P2 M] Connect substrate scars to disturbances.** Extend existing dig and sift effects with bounded persistent local marks. **Done:** digging leaves a small change that settles gradually, survives a save where appropriate, and never accumulates unlimited decals or terrain edits.
- [ ] **064 [P2 S] Make root exposure use living roots.** Link front-glass root marks to nearby plant root state. **Done:** a planted region develops plausible root presence; removing or relocating a plant does not leave a permanent unrelated root curtain.
- [ ] **065 [P1 M] Concentrate patina where it has a cause.** Refine `tank_fidelity_runtime.gd` glass dust distribution using light, age, and surface access. **Done:** film varies meaningfully by pane and height; all glass does not receive the same noise mask.
- [ ] **066 [P2 M] Make grazing trails cumulative and bounded.** Extend existing snail track storage with stable pane coordinates and controlled decay. **Done:** a snail produces a continuous cleaned trail across a pane, track limits degrade gracefully, and corners do not cause long diagonal scratches.
- [ ] **067 [P1 S] Separate inside film from outside reflection.** Refine glass material layering and parameter names. **Done:** wiping algae does not erase room reflection, and changing room brightness does not alter the simulated amount of glass film.
- [ ] **068 [P2 S] Age wood by local contact and exposure.** Tune biofilm and algae masks on existing driftwood forms. **Done:** submerged crevices and lit surfaces differ without turning each log uniformly white or green at one global timer threshold.
- [ ] **069 [P2 M] Preserve wood's silhouette while adding detail.** Refine branch thickness, taper, fork transitions, and endpoint treatment in `driftwood_form.gd`. **Done:** forms remain readable at hero resolution and look joined at close range without a large increase in voxel count.
- [ ] **070 [P2 S] Give stone clusters a consistent material family.** Refine procedural stone color and facet selection. **Done:** one formation shares strata direction and a restrained ramp, while different formations can vary; random color does not erase shape.
- [ ] **071 [P2 M] Make resting objects visibly contact their support.** Extend substrate contact shading and placement checks to shells, stones, wood, and equipment. **Done:** close views show neither floating bases nor broad dark halos detached from the contact point.
- [ ] **072 [P1 S] Quiet the stand and wall textures.** Tune `world_room_builder.gd` and associated material parameters against the current capture. **Done:** background texture contrast supports the aquarium instead of competing with small fish, while retaining enough variation to avoid a flat void.
- [ ] **073 [P2 S] Improve equipment joins.** Review clamp, neck, cable, airline, intake, and heater attachments in `gooseneck.gd` and `world.gd`. **Done:** all offered vessel shapes show connected components with no cable crossing open tank water unintentionally.
- [ ] **074 [P2 M] Reflect equipment operating state.** Reuse heater/filter state to drive small indicators and outflow appearance. **Done:** an inactive pump does not emit a full-strength stream, and a decorative glow never falsely reports heating or filtration.
- [ ] **075 [P2 S] Make mineral marks follow changing water level.** Refine existing mineral-spot placement and persistence. **Done:** evaporation leaves a bounded historical line, refill changes the live meniscus, and cleaning affects the intended marks only.
- [ ] **076 [P2 M] Let detritus settle in plausible pockets.** Connect existing mulm visuals to substrate depressions and reduced flow. **Done:** a controlled pulse accumulates unevenly around shelter and low spots without simply spawning equal particles across the floor.
- [ ] **077 [P2 S] Vary shell remains by history.** Refine `snail_shell.gd` appearance using age and condition already represented by the simulation. **Done:** recent and weathered remains differ subtly while shell count, decay, and nutrient contribution remain consistent.
- [ ] **078 [P3 M] Add a restrained scale reference to rooms.** Reuse existing room props or add one small procedural prop per relevant setting. **Done:** a nano tank and large tank feel different in size; props do not block controls, dominate the frame, or introduce external art dependencies.
- [ ] **079 [P2 S] Audit decorative effects at the footprint edge.** Extend the real-vertex footprint probe to patina, roots, gravel, ripples, and equipment effects. **Done:** intentional exterior equipment is identified separately, while tank-bound material geometry stays inside each vessel.
- [ ] **080 [P1 M] Review mature habitat appearance.** Capture fresh, established, grazed, recently disturbed, and old versions of one fixture. **Done:** history is readable through accumulated differences, and the oldest state still leaves useful views of its residents.

## 5 Individual fish motion

- [x] **081 [P1 M] Resolve the species depth-reference mismatch.** Trace `fish_depth_bands.gd`, substrate height, founding placement, and probe normalization to one water-column definition. **Done:** measured target depth matches configured depth across tank heights without compensating constants; existing saved preferences retain their intended position.
- [x] **082 [P1 M] Give emergency behavior explicit precedence over bouts.** Refine `fish_life_bouts.gd` eligibility and return paths. **Done:** hunger, hypoxia, escape, and breeding can interrupt a hover or decorative dart, and interrupted fish resume a sensible state without a speed spike.
- [x] **083 [P1 S] Bound turns by body and current speed.** Tune the existing yaw-inertia implementation in `fish.gd` and `fish_locomotion.gd`. **Done:** large cruising fish turn in broader arcs than tiny darting fish, with no spin-in-place failure at near-zero speed.
- [x] **084 [P1 M] Link fin effort to swimming effort.** Refine existing procedural fin/tail motion using acceleration and motion relative to flow. **Done:** cruising, braking, station-holding, and being carried by water read differently without a new keyframed animation system.
- [ ] **085 [P2 S] Vary recovery after a dart.** Use bounded per-fish stamina or existing fatigue state to taper bursts. **Done:** repeated bursts have a visible recovery period, while healthy animals still respond promptly to real threats.
- [x] **086 [P1 M] Remove neighbor speed lockstep without breaking schools.** Tune personal bout phases against schooling speed matching. **Done:** probe correlation declines where previously excessive, while school cohesion and response propagation remain within the baseline's accepted range.
- [ ] **087 [P2 M] Give hovering a local purpose.** Connect existing hover/investigate choices to an actual target or safe station. **Done:** selected fish hold near food, cover, glass, or a novel object and terminate the hover when its target disappears or the situation changes.
- [ ] **088 [P2 S] Tune braking before interactions.** Refine approach speed near food, peck surfaces, eggs, and resting nooks. **Done:** fish do not orbit their target repeatedly or brake only after passing through it; compare short clips at 1× and 4×.
- [x] **089 [P1 M] Keep pecks on reachable surfaces.** Refine the current peck target search and surface normals in `fish_life_bouts.gd`. **Done:** head orientation and contact point agree for glass, plants, and film; occluded or removed targets cancel cleanly.
- [ ] **090 [P2 S] Make bottom foraging traverse patches.** Tune existing cory/mudsifter sift loops. **Done:** an animal searches a short irregular patch, pauses, and moves on as local yield drops, rather than repeating a stationary nose-down loop indefinitely.
- [ ] **091 [P2 M] Express station-holding in the shared current.** Refine `hydrodynamics.gd` and fish locomotion around the existing flow field. **Done:** fish orient and work against meaningful flow while sheltered individuals expend less effort; this response scales smoothly with pump strength.
- [ ] **092 [P2 M] Let individuals retain characteristic pace.** Persist or derive stable personal motion parameters from identity. **Done:** a familiar slow cruiser remains recognizable after save/load and LOD changes, without every member of its species sharing the same rhythm.
- [ ] **093 [P1 S] Make resting breathing readable but restrained.** Tune existing gill/head pulses by effort and oxygen stress. **Done:** close observation distinguishes ordinary rest from labored breathing, while hero views do not show whole-body inflatable pulsing.
- [ ] **094 [P2 S] Reduce mechanical head scanning.** Refine eye/head saccade cadence around actual attention changes. **Done:** repeated clips show asynchronous small glances and sustained attention, with no periodic whole-school twitch.
- [ ] **095 [P2 M] Give new-object inspection a novelty lifetime.** Connect aquascape placement events to existing curiosity and memory. **Done:** nearby eligible fish inspect once or revisit with decaying interest; moving the camera or reloading does not recreate a novel object.
- [ ] **096 [P1 M] Preserve depth preferences under competing drives.** Tune priority blending after 081. **Done:** surface feeding and escape can leave a preferred band temporarily, followed by a gradual return; species do not collapse into one shared layer under ordinary care.
- [ ] **097 [P2 S] Vary settlement before sleep.** Refine `night_watch.gd` nook selection and final locomotion. **Done:** fish slow and find valid resting places on individual schedules, with emergency wake behavior still effective and no abrupt nightly teleport.
- [ ] **098 [P2 M] Keep continuous growth consistent with collision and picking.** Trace `FishGrowth.scale_for()` through geometry, neighbor spacing, reach, and selection. **Done:** newborns use appropriately small bounds and adults expand smoothly without invisible oversized hit areas or overlapping school spacing.
- [ ] **099 [P1 M] Compare locomotion across frame rates.** Extend the behavioral probe with matched simulation-time runs at several render caps and speeds. **Done:** describe tolerated differences explicitly; low FPS does not erase darts, multiply motion distance, or produce extra biological aging.
- [ ] **100 [P1 M] Judge species recognition in motion.** Capture short unlabeled examples of major movement types at the normal viewing scale. **Done:** reviewers can distinguish schooling, hovering, surface, and bottom species by motion; tune only the types that remain visually interchangeable.

## 6 Social behavior and life cycles

- [ ] **101 [P1 M] Reconcile the social decision layers.** Trace schooling, `fish_social.gd`, livebearer bouts, workspace choices, and territorial drives. **Done:** one documented arbitration path resolves incompatible actions, so courtship is not simultaneously overridden by a different module's idle steering.
- [ ] **102 [P2 M] Make school joins and departures gradual.** Refine `motion_school.gd` membership transitions. **Done:** feeding, shelter, and threat can split a group temporarily; returning fish merge without teleporting allegiance or snapping heading to a centroid.
- [ ] **103 [P2 S] Preserve response delay across a school.** Tune `motion_wave.gd` propagation using local neighbors. **Done:** a startle visibly travels through nearby animals instead of broadcasting a simultaneous turn to the full tank; isolated animals are not affected by nonexistent contact.
- [ ] **104 [P2 M] Give mixed schools explicit compatibility rules.** Use species traits in the existing school and social systems. **Done:** compatible fish can associate under pressure while solitary or territorial species retain their identity; fallback species receive documented conservative behavior.
- [ ] **105 [P2 S] Add hysteresis to social spacing.** Refine proximity comfort and avoidance thresholds. **Done:** two neighbors settle into a loose spacing range instead of alternating attraction and repulsion at one exact distance.
- [ ] **106 [P2 M] Connect territory to useful habitat.** Refine existing territorial center selection with cover, access, and competing residents. **Done:** an owner defends a bounded usable area and can lose or relocate it when its shelter is removed.
- [ ] **107 [P2 S] Make retreat a valid outcome.** Tune existing chase/contest termination. **Done:** a yielding fish escapes to accessible space, the winner ends pursuit after separation, and neither becomes locked in a perpetual wall chase.
- [ ] **108 [P2 M] Make courtship respond to the recipient.** Extend the existing livebearer display and breeding branches. **Done:** acceptance, indifference, and withdrawal produce different bounded outcomes based on real state, with a cooldown that prevents immediate repeated harassment.
- [ ] **109 [P2 S] Separate courtship from successful reproduction.** Review breeding gates in `fish.gd` and `sim_driver.gd`. **Done:** display can occur without spawning; actual births require compatible life stage, resources, and capacity, avoiding a mandatory population spike whenever a display is seen.
- [ ] **110 [P2 M] Resolve mate loss cleanly.** Trace stable identity, references, social memory, and breeding state on death/removal. **Done:** the survivor's behavior changes within a bounded period, stale node references are released, and future pairing remains possible.
- [ ] **111 [P2 M] Validate species reproductive traits.** Audit `real_species_fauna.gd` and breeding flags against primary species references, distinguishing invented species from named real ones. **Done:** incorrect inherited modes are corrected with migration handling; educational copy states intentional abstractions rather than presenting them as zoological fact.
- [ ] **112 [P2 S] Make egg placement use real support.** Refine egg-laying positions against leaves, substrate, or shelter appropriate to the species mode. **Done:** clutches attach to valid surfaces and respond consistently when the supporting object is moved or removed.
- [ ] **113 [P2 M] Keep brood care interruptible.** Tune guarding and brooding against hunger, stress, and threats. **Done:** parents balance needs, abandon only for a grounded reason, and cannot remain stuck guarding an empty or destroyed clutch.
- [ ] **114 [P2 S] Stagger hatching within a clutch.** Refine existing incubation into a bounded hatch interval with stable randomization. **Done:** small releases feel organic, clutch counts remain conserved, and loading during hatching neither duplicates nor loses remaining fry.
- [ ] **115 [P2 M] Make fry refuge depend on accessible cover.** Refine current plant/floater shelter scoring using size and occupancy. **Done:** small fry use cover adults cannot exploit equally; opening a plant corridor changes refuge choices without granting invulnerability.
- [ ] **116 [P2 S] Tie juvenile play to spare capacity.** Refine the existing play bursts using safety, food, rest, and age. **Done:** play appears in comfortable juveniles and yields to survival behavior, with neither permanent hyperactivity nor a globally synchronized trigger.
- [ ] **117 [P2 M] Preserve cohort diversity as populations renew.** Tune founder age spread, breeding cadence, and lifespan variance. **Done:** a long soak produces overlapping sizes and generations instead of whole-tank birth/death waves caused solely by shared initialization.
- [ ] **118 [P2 S] Make old age visible before the death animation.** Coordinate existing color fade, growth taper, pace, and rest behavior. **Done:** changes develop gradually and remain individual; old fish still express their established preferences where their condition allows.
- [ ] **119 [P2 M] Keep death causes mutually consistent.** Reconcile predation, starvation, chemistry, and senescence reporting in simulation and chronicle. **Done:** one death produces one authoritative cause/event, the appropriate remains, and no duplicated lineage or population updates.
- [ ] **120 [P2 M] Demonstrate a complete generational story.** Build a bounded seeded fixture covering pairing, birth, refuge, growth, and eventual loss. **Done:** the same identities connect visible behavior, population totals, lineage, and chronicle across a midpoint save/load.

## 7 Invertebrates and food web

- [x] **121 [P1 M] Trace one meal through the whole food web.** Follow `spawn_player_food`, consumption, waste, substrate deposit, and plant uptake. **Done:** a diagnostic event chain names transfers and documented losses; no step silently duplicates food value or discards its entire consequence.
- [ ] **122 [P2 M] Make shrimp grazing deplete a local patch.** Refine `shrimp.gd`, biofilm, and leaf grazing hooks. **Done:** a group works a patch, gradually moves as yield falls, and returns after recovery; decorative pecking and nutrient transfer agree.
- [ ] **123 [P2 S] Improve shrimp attachment transitions.** Refine movement between substrate, wood, plants, and floater roots. **Done:** orientations and feet remain near the supporting surface, and a removed support leads to a controlled fall or swim instead of suspension in air.
- [ ] **124 [P2 M] Give shrimp escape a recovery arc.** Tune existing tail-flick behavior with threat distance and shelter. **Done:** an individual flicks, coasts, settles, and resumes activity; every nearby shrimp does not enter an identical repeating escape cycle.
- [ ] **125 [P2 S] Vary snail paths by resource and surface.** Refine `snail.gd` and `snail_surface.gd`. **Done:** glass, wood, and substrate offer different route choices; a snail moves toward an actual grazing opportunity without oscillating at pane boundaries.
- [x] **126 [P1 M] Preserve snail continuity across corners.** Reconcile surface normals, path length, shell pose, and trail position. **Done:** traversing box and hex corners neither jumps the snail nor paints a trail through the aquarium interior.
- [ ] **127 [P2 M] Connect shell condition to existing mineral state.** Tune snail growth/repair and `water_chemistry.gd` mineral use. **Done:** condition changes gradually, mineral debit occurs once, and water restoration can support recovery without instantly repainting every shell.
- [ ] **128 [P2 S] Make snail egg development inspectable.** Refine `snail_egg.gd` coloration and stage description. **Done:** eggs show a modest progression and a clear hatch outcome, with no adult shells appearing before the juvenile state is created.
- [ ] **129 [P2 M] Complete microfauna consumption where partial.** Trace `microfauna_swarm.gd` feeding consumers and existing ecology hooks before extending them. **Done:** eligible fry or filter feeders consume bounded local abundance and receive the intended benefit; visual dots correspond to available prey rather than infinite food.
- [ ] **130 [P2 S] Separate microfauna motion types.** Tune existing copepod/daphnia variants using different bounded movement cadence. **Done:** close observation distinguishes brief jumps from drifting movement without increasing normal-view visual noise or per-particle nodes.
- [ ] **131 [P2 M] Make clam filtration spatial and accountable.** Refine `clam.gd` against suspended material and flow access. **Done:** filtration removes a bounded amount from its actual source pool and produces consistent waste; inactive or buried clams do not filter at full rate.
- [ ] **132 [P2 S] Tie clam opening to sensed conditions.** Coordinate existing shell pose, disturbance, and feeding. **Done:** close approach can trigger closure, recovery is gradual, and the animation matches the active filtration state.
- [ ] **133 [P2 M] Keep detritivore abundance tied to habitat.** Review worms, tubifex, and related patch spawning against local food and substrate. **Done:** enriched areas attract or support more activity, but capped visuals do not silently alter the underlying resource budget.
- [ ] **134 [P2 S] Make scavenging arrivals staggered.** Refine reaction to food and remains for shrimp, snails, and worms. **Done:** nearby opportunists arrive before distant ones, species speeds matter, and a single event does not teleport a ring of consumers around itself.
- [ ] **135 [P2 M] Preserve food distinctions after sinking.** Trace flakes, pellets, worms, and wafers through decay and consumer selection. **Done:** intended buoyancy, duration, size, and eligibility remain distinct from drop to consumption; UI descriptions match the actual behavior.
- [ ] **136 [P2 S] Make partial consumption visible.** Refine existing food/waste amount-to-size mapping. **Done:** shared food shrinks or fragments consistently with remaining value; many eat events do not appear to consume the same full-sized pellet forever.
- [ ] **137 [P2 M] Stabilize predator and prey feedback.** Tune snail hunters and prey recruitment with refuge and resource limits. **Done:** multiple seeds show bounded coexistence or understandable loss, without relying on invisible periodic prey replacement to conceal an unstable loop.
- [ ] **138 [P2 M] Keep reef feeding and respiration coherent.** Review corals, anemones, clams, and reef detritivores against the existing proxy chemistry. **Done:** each organism's documented contribution is applied once, including at night; the interface calls the model a proxy where necessary.
- [ ] **139 [P2 S] Make colony summaries describe actual inhabitants.** Refine `colony_mind.gd` output and resident counts. **Done:** the tank can surface a grazing or sheltering colony event without pretending every invertebrate has the same fish cognition architecture.
- [ ] **140 [P2 M] Demonstrate food-web recovery after disturbance.** Extend an existing soak with overfeeding followed by a measured care response. **Done:** record consumption, waste, microfauna, algae, and oxygen trajectories; recovery arises from represented processes, not a hidden reset of tank health.

## 8 Plant growth and succession

- [x] **141 [P1 M] Reconcile visual plant mass with ecological biomass.** Trace `plant.gd`, special plant forms, and `plant_ecology_adapter.gd`. **Done:** growth, grazing, trimming, and death update the same authoritative biomass budget once, including nonstandard plant scripts.
- [x] **142 [P1 M] Replace identical blade terminations with growth variation.** Refine ribbon construction and existing canopy layover. **Done:** Valli tops vary in length, bend, and age while remaining attached; variation is stable and does not turn every tip into random voxel debris.
- [ ] **143 [P2 S] Make leaf age visually local.** Use existing per-leaf state for subtle value, edge wear, and algae distribution. **Done:** older outer leaves differ from new growth on the same plant; an entire stem does not change to one uniform age tint.
- [ ] **144 [P2 M] Reconcile growth with available light.** Trace canopy, floaters, hardscape shade, and leaf sampling. **Done:** shade removal changes growth over a plausible game-time interval, and the renderer's lit region broadly agrees with the region supporting growth.
- [ ] **145 [P2 S] Distinguish nutrient deficiency from old leaves.** Refine existing deficiency tints and inspectable reasons. **Done:** supported deficiencies affect the intended leaf cohort and recover gradually; absence of a modeled nutrient does not generate a precise unsupported diagnosis.
- [ ] **146 [P2 M] Make flow bending respect plant form.** Use existing genome stiffness and form traits in foliage motion. **Done:** ribbon plants, stiff rosettes, and fine stems respond differently to one flow pulse while roots remain fixed.
- [ ] **147 [P2 M] Give neighboring plants related but unequal motion.** Couple sway to shared local flow plus stable individual flexibility. **Done:** a passing disturbance moves a patch coherently without making every blade use the same phase and amplitude.
- [ ] **148 [P2 S] Preserve new-growth continuity.** Audit existing leaf unfurl and stem-extension paths across batched/unbatched plants. **Done:** new growth starts at its actual node and settles into the mature pose without a one-frame full-size flash or disconnected segment.
- [ ] **149 [P2 M] Make root competition spatially selective.** Refine `substrate_root_competition.gd` demand and uptake allocation. **Done:** close root feeders compete for a finite local pool while distant plants remain independent; a crowded patch cannot consume the same nutrient reserve multiple times.
- [ ] **150 [P2 S] Let trimming change future form.** Refine existing branch and regrowth hooks by plant type. **Done:** a clipped stem responds differently from a clipped ribbon leaf, and the new structure persists across save/load instead of resetting to the original silhouette.
- [ ] **151 [P2 M] Keep detached fragments ecologically accountable.** Trace `plant_fragment.gd` through drift, decay, and rooting. **Done:** a fragment either establishes under valid conditions or returns bounded material to the food web; neither outcome duplicates the parent's removed biomass.
- [ ] **152 [P2 M] Make runner establishment compete for space.** Refine existing runner and plantlet placement. **Done:** offspring spread into valid nearby substrate, stop at vessel boundaries and hardscape, and avoid unlimited growth by repeatedly failing and respawning at one coordinate.
- [ ] **153 [P2 S] Preserve lineage without identical clones.** Refine `plant_genome.gd` and `plant_lineage_registry.gd` display traits. **Done:** descendants retain recognizable family traits with bounded variation; mutation changes appearance without silently replacing species-specific ecological requirements.
- [ ] **154 [P2 M] Make canopy crowding lead to succession.** Tune existing self-shading, senescence, and recruitment together. **Done:** a mature dense stand opens occasional local gaps and renews them over time, without cyclic whole-tank defoliation caused by shared timers.
- [ ] **155 [P2 S] Keep flowering rare and condition-driven.** Review existing flower stages by species, age, and surface access. **Done:** blooms are noticeable events with grounded triggers and bounded duration, not simultaneous decorations added to every healthy plant.
- [ ] **156 [P2 M] Make seed-bank germination use a suitable window.** Refine `substrate_seed_bank.gd` checks for space, light, and substrate. **Done:** viable seeds wait and establish when conditions permit, and the bank remains bounded across long play and save cycles.
- [ ] **157 [P2 S] Make melt and recovery readable as one process.** Coordinate existing deficiency, leaf loss, dormant state, and regrowth. **Done:** a recovering plant remains identifiable rather than being deleted and replaced by an unrelated seedling with a reset history.
- [x] **158 [P1 M] Protect plant silhouette at lower fidelity.** Compare `plant_far_foliage_batch.gd` and skeleton/voxel forms. **Done:** stems, rosettes, moss, and floaters remain visually distinct as detail drops, while biomass, shade, and grazing state remain unchanged.
- [ ] **159 [P2 S] Surface one useful plant observation.** Extend existing inspect UI with growth trend, current limitation, and one grounded interaction when available. **Done:** selecting a plant explains a visible condition in plain language without exposing a wall of genome or shader parameters.
- [ ] **160 [P2 M] Review a complete planted succession sequence.** Capture identical viewpoints across establishment, crowding, trimming, and recovery. **Done:** the tank becomes visibly different for causal reasons, retains swim space, and remains stable in the accompanying chemistry trajectory.
