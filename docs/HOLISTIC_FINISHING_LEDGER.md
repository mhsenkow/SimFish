# Holistic finishing plan — execution ledger

Companion to [HOLISTIC_FINISHING_PLAN_400.md](HOLISTIC_FINISHING_PLAN_400.md)
(task **016**). Checkbox count in the plan is never a completion claim; this
ledger is. Status vocabulary:

| Status | Meaning |
|---|---|
| `implemented` | Change landed; Done condition holds with evidence below |
| `verified-existing` | Behaviour already present; cited, no parallel system added |
| `deferred` | Intentionally postponed with reason |
| `rejected` | Proposal harmful or obsolete; replacement noted |

Newest batch first.

---

## Batch 2026-10-01j — scenario template QA / Iwagumi flash (#040)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 040 | implemented | Contact-sheet day fit/close/front for all 18 scenarios; aquarium MeshInstance fauna LOD never-cull (pond keeps distance LOD); silver flank flash + MultiMesh irid turn flash gated to metallic fauna (stops glassdart sunny strobe); stone_garden grade allows empty mid/upper + centred two-island focal; smoke exempts apply-hook keys (`film_stock`) | `fish.gd`, `voxel_fauna_mm.gdshader`, `smoke_scenario_templates.gd`, `scape_composition.gd`, `smoke_scape_composition.gd` | scenario_templates + scape_composition smokes; check_warnings 0 | Baseline `template_qa_20261002T031205Z` (18); postfix `template_qa_postfix_20261002T032229Z` (iwagumi/dutch/hex). Remaining FAILs are systemic stipple/shadow floors, not template-local. |

---

## Batch 2026-10-01i — individual fish motion (081 / 082 / 083 / 084 / 086 / 089)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 081 | implemented | One water-column contract: `FishDepthBands.y_from_frac` / `frac_from_y` (0=substrate top, 1=surface); removed compensating “centres set low” bias; world scale + `preferred_y_at` + probe share it; saves keep `preferred_y_frac` | `fish_depth_bands.gd`, `world.gd`, `dev/fish_behaviour_probe.gd` | `smoke_fish_life_bouts`; compile_check | Full probe soak not re-run; unit round-trip across column heights. |
| 082 | implemented | `emergency_interrupt` (hunger / hypoxia / flee / spawn / court / startle / aerial) soft-aborts hover/dart to cruise without dart-rate envelope spike | `fish_life_bouts.gd`, `fish.gd` | smoke | Continuous low-O2 tanks suppress decorative bouts while gulp is active. |
| 083 | implemented | Body-scaled yaw via `FishLocomotion.body_speed_turn_scale` + speed-gated turn floor (no spin-in-place at crawl) | `fish_locomotion.gd`, `fish_life_bouts.gd`, `fish.gd` | fish_locomotion + fish_life_bouts smokes | — |
| 084 | implemented | `Hydrodynamics.fin_effort_from_swim` drives tail/pec/wag for cruise / brake / station / flow-carried | `hydrodynamics.gd`, `fish.gd` | smoke | Procedural only; no new keyframes. |
| 086 | implemented | Soft school speed match via `MotionSchool.speed_match_weight`; personal bouts own pace; startle/burst still propagate | `motion_school.gd`, `fish.gd` | smoke | Probe lockstep correlation not re-measured this batch. |
| 089 | implemented | Peck stores surface normal + kind; approach/jab along normal; cancel when film/plant/glass unreachable | `fish_life_bouts.gd`, `fish.gd` | smoke | Head bias is via approach direction (no separate gaze override). |

---

## Batch 2026-10-01h — food web / snail corners / plant budget (121 / 126 / 141 / 142 / 158)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 121 | implemented | `FoodWebTrace` diagnostic chain (spawn→consume→absorb→metabolic_waste→settle_deposit→plant_uptake→documented_loss); fixed trophic leftover double-book into `produced` and whole-meal `lost` on tiny heat | `food_web_trace.gd`, `sim_driver.gd`, `waste_particle.gd`, `plant_ecology_adapter.gd`, `smoke_food_web_trace.gd` | compile_check; `food_web_trace` smoke | Uptake attribution uses last deposit chain; not per-cell meal tags |
| 126 | implemented | Box+hex wall-to-wall corner transfer; glass-path wrap; continuous slime anchors (no interior chord); soft normal blend on polygon reclamp | `snail_surface.gd`, `snail.gd`, `aquarium_visuals.gd`, `smoke_snail_surface.gd` | `snail_surface` smoke | Hardscape/plant attaches unchanged |
| 141 | implemented | `ecology_*` on `Plant` + `FloatingPlant`; adapter falls back to `biomass()`; floaters enter surface biomass budget once; floaters skip substrate double-debit | `plant.gd`, `floating_plant.gd`, `plant_ecology_adapter.gd`, `world.gd`, `smoke_plant_ecology_adapter.gd` | ecology adapter smoke | Floater nitrate still via water-column path |
| 142 | implemented | Valli tip length/bend/age/style variation (stable hashes); tips stay attached | `plant.gd`, `smoke_plant_ribbon_blades.gd` | ribbon blades smoke | Variation is per-blade serial, not frame noise |
| 158 | implemented | Form-aware leaf LOD keepers (ribbon tip/base, rosette radial, carpet denser); far-batch skips tiny/carpet/short ribbons | `plant.gd`, `plant_far_foliage_batch.gd`, ribbon smoke LOD assert | ribbon + compile | Moss/floaters remain private Node3D forms |

---

## Batch 2026-10-01g — composition / camera (022 / 023 / 027 / 030 / 035)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 022 | implemented | `HudLayout.AVAILABLE_CENTER` + bias/aspect helpers; main stashes framing on side-panel open, biases target into free centre, restores on close (manual orbit/pan abandons restore) | `hud_layout.gd`, `main.gd`, `camera_controller.gd`, `smoke_hud_layout.gd` | hud_layout + camera_controller smokes | Overlay panels only — SubViewport stays full-bleed; restrained radius scale ≤1.28 |
| 023 | implemented | `CameraController.hero_fit_radius` + `stand_allowed_in_frame` cap (~1.6u / 20% of tank_h); hero defaults use it instead of uncapped stand | `camera_controller.gd`, `main.gd`, `smoke_camera_controller.gd` | camera_controller smoke | User-authored / saved views keep their own radius |
| 027 | implemented | Pixel-snap only when eye settled; orbit/zoom damp hard-zeros below rest; follow deadzone hysteresis | `camera_controller.gd`, `main.gd`, `smoke_camera_controller.gd` | camera_controller smoke | Sim motion unchanged; snap still optional via `pixel_snap_camera` |
| 030 | implemented | Coarse XZ swim-corridor flood-fill; optional grade row; items carry z/r; visual_capture reports corridor; dense_jungle `corridor_min` 0.12 | `scape_composition.gd`, `visual_capture.gd`, `smoke_scape_composition.gd` | scape_composition smoke | Measurement only — does not delete plants |
| 035 | implemented | `vessel_speed_scale(fit_radius, footprint)` drives orbit/pan/dolly/WASD; anchored to vessel fit not live zoom | `camera_controller.gd`, `main.gd`, `smoke_camera_controller.gd` | camera_controller smoke | Scale clamped 0.65–1.5 |

---

## Batch 2026-10-01f — palette / resolution / blackwater / close shadows (042–044, 046, 048, 050)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 042 | implemented | Mode profiles for day/night/care/outline/photo vs UI; photo grade keeps `palette_lock=1`; smokes assert contract | `frame_metrics.gd`, `aesthetics_runtime.gd`, `smoke_aesthetics.gd`, `smoke_frame_metrics.gd` | aesthetics + frame_metrics smokes | UI/duotone remain out of aquarium lock grading |
| 043 | implemented | Fidelity tiers potato→desktop in audit; STYLE_GUIDE table; nearest-upscale helper; smoke rejects non-tiers + linear filter | `render_resolution_audit.gd`, `STYLE_GUIDE.md`, `tank_config.gd`, `main.gd`, `smoke_shader_perf.gd` | shader_perf smoke | Shipping default remains 1024×576; beauty first-launch mid 512×288 |
| 044 | implemented | Material-region dither budgets (water/glass/plant/fauna) on top of room/substrate | `palette_quantize.gdshader` | aesthetics smoke (source pins) | Bounded multipliers; fauna ~0.30×, glass ~0.20× |
| 046 | implemented | `protect_color_identity` + soft sat×val compound in tint include; CPU mirror + compose helper | `palette_tint.gdshaderinc`, `aesthetics_runtime.gd`, `smoke_aesthetics.gd` | aesthetics smoke | Does not rewrite day-phase path; caps stacked sat |
| 048 | implemented | `blackwater_contrast_bundle` (extinction↓, depth↑, tannin floor); scenario→`blackwater_den` + film stock; fauna sat 1.26 | `aesthetics_runtime.gd`, `world.gd`, `world_atmosphere.gd`, `scenario_picker.gd`, `tank_config.gd`, `smoke_water_column.gd` | water_column + aesthetics | Healthy tea ≠ murk; near transmittance still >0.70 in smoke |
| 050 | implemented | Close-view `shadow_structure` (p50−p05) grade; deeper underside/side/blade-margin ramps | `frame_metrics.gd`, `voxel.gdshader`, `foliage.gdshader`, `foliage_light.gdshaderinc`, `foliage_senescent_mm.gdshader`, `smoke_frame_metrics.gd` | frame_metrics smoke; `polish_042_050` | Valli close **shadow_structure 30.1 ok**. Blackwater close still compressed (7.0 FAIL) — tea midtone wash, not a hero-floor false fail; further BW close structure is residual. |

### Metric snapshot (`output/visual_baselines/polish_042_050/`, settle 180)

| View | uniq / excess | Notes |
|---|---|---|
| blackwater fit | 28 / 0.58× | palette lock ok; p05 28.7; tea depth readable |
| blackwater close | 20 / 0.42× | lock ok; midtone_mass + shadow_structure still fail (tea wash) |
| valli fit | 30 / 0.62× | lock ok |
| valli close | 23 / 0.48× | **shadow_structure 30.1 ok**; midtone_mass 0.462 still soft |

---

## Batch 2026-10-01e — first visible polish (021 / 041 / 047)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 021 | implemented | Valli `passage_clear` ridge_strip (deterministic mass-side blade wall + mid corridor); scenario camera wired through `CameraController.scenario_hero_orbit`; `dense_jungle` composition expectations via `visual_intent.composition_profile` (#019) | `world.gd`, `tank_config.gd`, `scenario_picker.gd`, `camera_controller.gd`, `main.gd`, `scape_composition.gd`, `visual_capture.gd`, `smoke_scape_composition.gd` | `scape_composition` smoke green; capture | Before `improve_demo_001` focal **0.017 FAIL**; after `polish_021_041_047` focal **0.052 ok** under dense_jungle (0.03–0.80). Fit stipple-step ~27–28 still fails hero ceiling. |
| 041 | implemented | Fixed inverted Z aerial haze (front was hazed more than back); stronger back-weighted contrast loss; local floater shade lean in `WorldWaterVisuals` | `water.gdshader`, `world_water_visuals.gd`, `world_atmosphere.gd` | compile_check; Valli capture | Palette stays bounded (uniq ≤36). Close still dense; not a full camera-relative fog. |
| 047 | implemented | Softer underside mirror / surface spec; higher canopy_shade floor; near-surface blade margin/gap shading; transmission slightly reduced | `world_atmosphere.gd`, `world.gd`, `aquarium_visuals.gd`, `foliage_mm.gdshader`, `foliage_light.gdshaderinc`, `water.gdshader` | Valli close/photo/photo_up | Close midtone **0.472 → ~0.45** (borderline); photo_up retains hilite ~0.11. Over-darkening the canopy sheet into midtones was rejected — keep luminous surface + gap structure. |

### Metric snapshot (Valli day, settle 240)

| View / check | Before (`improve_demo_001`) | After (`polish_021_041_047`) |
|---|---|---|
| composition focal | 0.017 FAIL (0.12–0.75) | 0.052 ok (dense_jungle 0.03–0.80) |
| close midtone_mass | 0.472 FAIL | 0.453 FAIL (improved; still soft) |
| photo midtone / hilite | 0.388 / 0.097 | 0.433 / 0.077 |
| photo_up hilite | (not shot) | 0.113 luminous retained |
| palette uniq (fit/close) | 35 / 25 | 36 / 25 |

Artifacts: `output/visual_baselines/improve_demo_001/` (before), `output/visual_baselines/polish_021_041_047/` (after).

---

## Batch 2026-10-01d — Wave A 006/008/009/013/017–020

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 006 | implemented | Trajectory cases (fresh/established/sparse/dense/reef) on `balance_soak`; N/O2/births/deaths/biomass + feed-pulse recovery; disclaimer; `scripts/ecological_baseline.sh` → `output/ecological_baselines/` | `dev/balance_soak.gd`, `scripts/ecological_baseline.sh` | compile_check; optional short soak | Full multi-day matrix is long; wrapper defaults `BALANCE_DAYS=2`. Sampled seeds ≠ universal guarantees. |
| 008 | implemented | UI passes `enlarged_text` / `pseudolocale` / `controller`; states `long_names` / `controller_path`; navigable + primary_action reporting | `dev/ui_capture.gd` | compile_check | Use `UI_CAPTURE_DIFFICULT=1` or pass filter. Windowed capture. |
| 009 | implemented | `scripts/audio_baseline.sh` matrix (healthy/stressed/day/night/full/simple); silence_frac; `AUDIO_PROBE_OUT` + `simplebed` | `dev/audio_probe.gd`, `scripts/audio_baseline.sh` | compile_check; short probe | Peak/RMS/silence are levels, not sound-quality scores. |
| 013 | implemented | `PerfGovernor.frame_percentiles` / `hardware_snapshot` / `workload_report` + spike log; `dev/perf_workload_probe` + wrapper for default/dense/mature/interaction | `perf_governor.gd`, `dev/perf_workload_probe.gd/.tscn`, `scripts/perf_workload_baseline.sh` | compile_check | Review-machine sample — not low-end. Windowed probe. |
| 017 | implemented | Documented SimRng/MindRng ownership; `STREAM_COSMETIC`; smoke proves cosmetic draws leave spawn/behavior streams intact | `docs/ARCHITECTURE.md`, `ARCHITECTURE.md`, `sim_rng.gd`, `smoke_sim_rng.gd` | `run_smokes.sh --include sim_rng` | — |
| 018 | implemented | Fixture-driven observation contract checklist | `docs/OBSERVATION_CONTRACT.md`, `docs/INDEX.md` | — | Does not require every event every minute. |
| 019 | implemented | `visual_intent` dict (`focal_subject`, `quiet_region`, `dominant_plant_form`, `water_character`) on beginner_sandbox, iwagumi, blackwater, reef, valli_jungle, hex_jungle | `scenario_picker.gd` | compile_check | Valli keeps `composition_profile: dense_jungle` for #021. |
| 020 | implemented | Plan ID duplicate/missing + checked→ledger validator | `scripts/validate_holistic_plan.sh` | script self-check | Authored range 001–160. |

---

## Batch 2026-10-01c — Wave A 010/011/012/014/015

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 010 | implemented | Authoritative state/clocks table: sim 10 Hz, mind ⊂ fish.tick, locomotion in `Fish._process`, wall-time dialogue cooldowns | `ARCHITECTURE.md`, `docs/ARCHITECTURE.md` | call-site audit (`SIM_HZ`, `_motion_substep`, `TankDialogue._unix`, `MindNarrator` cooldown) | Line numbers in older carve notes may drift; table uses symbols |
| 011 | implemented | Five synthetic fixtures + headless migrate/repair loader | `dev/fixtures/saves/*.json`, `smoke_save_fixtures.gd` | `run_smokes.sh --include save_fixtures` | No private keeper text; full `load_state` into live World not required for Done |
| 012 | implemented | Player claim → input evidence map (F/I/M/X) | `docs/PLAYER_CLAIM_EVIDENCE.md` | traced `OnboardingLegibility`, `KeeperCare`, dialogue, chronicle, activity labels | Speculative mind module names marked **X** |
| 014 | implemented | Reconciled version **0.2.36**, **18** scenarios, **11** autoloads, render default **1024×576**, `run_smokes.sh` guidance | `project.godot`, `README.md`, architecture docs, `STYLE_GUIDE.md`, `ENGINEERING_CREED.md`, `AGENTS.md` | measured from `project.godot` / `scenario_picker.gd` / `smoke_autoload_contract.gd` | Style-guide 384×216 kept as design-intent note only |
| 015 | implemented | Cross-ref Holistic IDs ↔ older campaigns | `docs/HOLISTIC_CROSSREF.md`, `docs/INDEX.md` | — | Tracks 9–20 rows are stubs until plan authors those checkboxes |

---

## Batch 2026-10-01b — static camera + Wave A 004/005/007

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| — (player ask) | implemented | Click/tap selects PIP only — never inherits cinematic zoom; DOF cinematic-only; idle screensaver defaults to gentle auto-orbit (`idle_cinema_tour=false`) | `main.gd`, `tank_config.gd`, `config_curation.gd` | compile_check 0 fail; 0 warnings | Explicit 🎬 portal / cinema / favorite shortcuts still zoom. Opt back into idle cinema via Settings camera knob. |
| 004 | implemented | `World.build_stage` + `CaptureReadiness.await_world`; visual/ui captures wait on `build_complete` then cosmetic settle; timeout names stuck stage | `world.gd`, `capture_readiness.gd`, `visual_capture.gd`, `ui_capture.gd`, `smoke_capture_readiness.gd` | smoke green; capture logged `world ready stage=complete waited=0.98s` | Cosmetic settle defaults lowered (120 / 90 frames). |
| 005 | implemented | Probe report header: seed, population JSON, time_scale, tier, scenario, sample counts | `fish_behaviour_probe.gd` | compile_check | Full multi-seed soak not re-run this batch; header contract is in place. |
| 007 | implemented | `scripts/ui_baseline_capture.sh`; readiness-gated ui_capture; wide+narrow baseline reports | `ui_baseline_capture.sh`, `ui_capture.gd` | `output/ui_baselines/wave_a_007/` | Narrow pass notes known FooterBar×RightRail overlap (`new` inter overlap). Full 37-state matrix available via same script without `UI_CAPTURE_STATES=baseline`. |

---

## Batch 2026-10-01 — Wave A start (001–003)

| ID | Status | Change | Files | Checks | Artifacts / limits |
|---|---|---|---|---|---|
| 001 | implemented | Isolated dev runs via scratch `custom_user_dir_name`; real tanks hashed before/after; existing `override.cfg` preserved/restored; distinct `GODOT_DEV_OUT_ROOT` / `VISUAL_CAPTURE_OUT` | `scripts/dev_run.sh`, `scripts/godot.sh` (opt-in `GODOT_ISOLATE=1`), `.gitignore` | Isolated `compile_check`: tanks inventory unchanged; temporary override removed | CI `run_smokes.sh` stays on live user-data unless callers opt in. Captures/probes should use `scripts/dev_run.sh`. |
| 002 | implemented | Five-scenario × day/night baseline matrix through real `visual_capture.tscn`; writes `meta.json` (seed, tier, resolution, clock, build, settle) beside fit/close PNGs | `scripts/visual_baseline_matrix.sh`, `dev/visual_capture.gd` (`_write_metadata`) | Demo cell `output/visual_baselines/improve_demo_001/valli_jungle/day/` | Full 5×2 matrix is a long windowed run; demo used settle 240. Scenarios: `beginner_sandbox`, `valli_jungle`, `blackwater`, `reef`, `hex_jungle`. |
| 003 | implemented | Named fractional regions + per-view grade profiles; close/surface/photo waive hero shadow-floor hard-fail; washed-out subjects still fail `tonal_spread` / midtone | `scripts/frame_metrics.gd`, `dev/visual_capture.gd`, `scripts/smoke_frame_metrics.gd` | `run_smokes.sh --include frame_metrics` green | **Improved examples vs `holistic_review_20261001`:** surface/photo no longer false-fail on p05 shadow or photo stipple-step; close correctly flags midtone_mass 0.472 (real canopy wash). Composition focal offset remains a scenario composition issue (→ 021). |
| 016 | implemented | Companion execution ledger | `docs/HOLISTIC_FINISHING_LEDGER.md`, `docs/INDEX.md` link | — | Checkbox count alone is never completion. |

### Example improvement (same Valli seed path)

| View | Review sample (universal grade) | After #003 (view-aware) |
|---|---|---|
| surface | p05 shadow **FAIL** | shadow info-only **ok**; grades pass |
| photo | p05 shadow **FAIL**, stipple step **FAIL** | both **ok** under photo profile |
| close | (not shot) | midtone_mass **FAIL** — useful evidence for 041/047 |
| fit | pass | pass + tonal_spread |

### Notes

- Plan doc currently authors tasks **001–160** of the advertised 400; tracks 9–20 remain to expand.
- Prefer `scripts/dev_run.sh` for any `visual_capture` / `inspect` / probe that boots `main.tscn`.
- Visible polish batch **021 / 041 / 047** recorded above (`polish_021_041_047`).
- Pre-existing: `smoke_scenario_layouts` apex corner check fails on this tree unrelated to ridge_strip changes.
