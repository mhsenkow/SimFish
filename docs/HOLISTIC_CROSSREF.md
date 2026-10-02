# Holistic finishing — cross-reference ledger

Holistic task **015**. Compact map from `HOLISTIC_FINISHING_PLAN_400.md` task IDs
to overlapping older campaign docs so two agents do not re-implement the same
capability. Status and evidence still live in
[HOLISTIC_FINISHING_LEDGER.md](HOLISTIC_FINISHING_LEDGER.md).

Use: when starting a Holistic ID, skim the listed campaign rows and prefer
extending those entry points.

---

## Track 1 — Evidence and execution (001–020)

| Holistic ID | Overlapping older docs / systems |
|---|---|
| 001 isolate runs | `BROAD_DIRECTIONS_20`, `scripts/dev_run.sh` / `godot.sh` |
| 002 visual baseline | `VISUAL_DIRECTIONS_20`, `dev/visual_capture.gd` |
| 003 frame metrics | `VISUAL_DIRECTIONS_20`, `frame_metrics.gd` |
| 004 capture readiness | `VISUAL_DIRECTIONS_20`, `world.gd` build stages |
| 005 behavior probe | `FISH_ALIVE_1000_IDEAS`, `LIVING_MOTION_IDEAS`, `dev/fish_behaviour_probe.gd` |
| 006 ecology soak | `GOALS.md` H, `CHEMISTRY_ORACLE`, `dev/balance_soak.gd` |
| 007–008 UI baseline | `ONBOARDING_LEGIBILITY_IDEAS`, `hud_layout.gd` |
| 009 audio reference | `MUSIC_DANCE_IDEAS`, `MUSIC_DANCE_PLAYBOOK` |
| **010 clocks / state** | `ARCHITECTURE.md`, `OPUS_HANDOFF_DETAILED`, sim/mind carve notes |
| **011 save fixtures** | `BROAD_DIRECTIONS_20` #4, `save_migrations.gd`, `REFINEMENT_II` save items |
| **012 claim evidence** | `SOUL_CREED`, `ONBOARDING_LEGIBILITY_IDEAS`, `SENTIENCE_THE_CONVERSATION_IDEAS`, `PLAYER_BOND_IDEAS` |
| 013 perf budget | `PERFORMANCE_REALTIME_IDEAS`, `PERFORMANCE_UNTHROTTLED_MIND_IDEAS` |
| **014 docs baseline** | `README`, `STYLE_GUIDE`, `ENGINEERING_CREED`, `AGENTS.md` |
| **015 this ledger** | `INDEX.md`, all idea docs below |
| 016 execution ledger | (meta) `HOLISTIC_FINISHING_LEDGER.md` |
| 017 RNG streams | `SimRng` / `MindRng`, ENGINEERING excellence |
| 018 observation contract | `FISH_ALIVE_1000_IDEAS`, `GOALS.md` A–B |
| 019 scenario visual intent | `VISUAL_DIRECTIONS_20`, `scenario_picker.gd`, `REAL_TANK_FIDELITY_200` |
| 020 plan validator | repo tooling / CI |

## Track 2 — Composition and camera (021–040)

| Holistic IDs | Overlapping |
|---|---|
| 021–040 | `VISUAL_DIRECTIONS_20`, `scape_composition.gd`, `camera_controller.gd`, `AESTHETICS_IDEAS`, `VISUAL_POLISH_200_IDEAS` |

## Track 3 — Palette lighting water (041–060)

| Holistic IDs | Overlapping |
|---|---|
| 041–060 | `REFINEMENT_100_IDEAS`, `VISUAL_DIRECTIONS_20`, `REAL_TANK_FIDELITY_200`, water/glass shaders |

## Track 4 — Habitat material (061–080)

| Holistic IDs | Overlapping |
|---|---|
| 061–080 | `REAL_TANK_FIDELITY_200`, `VISUAL_POLISH_200_IDEAS`, `tank_fidelity_runtime.gd` |

## Track 5 — Individual fish motion (081–100)

| Holistic IDs | Overlapping |
|---|---|
| 081–100 | `FISH_ALIVE_1000_IDEAS`, `LIVING_MOTION_IDEAS`, `TOPDOWN_MOTION_IDEAS`, `fish.gd` locomotion |

## Track 6 — Social / life cycles (101–120)

| Holistic IDs | Overlapping |
|---|---|
| 101–120 | `GOALS.md` A–B, H4; social / breeding systems; `FISH_ALIVE_1000_IDEAS` |

## Track 7 — Invertebrates / food web (121–140)

| Holistic IDs | Overlapping |
|---|---|
| 121–140 | `GOALS.md` C, H5; `REAL_TANK_FIDELITY_200` |

## Track 8 — Plants (141–160)

| Holistic IDs | Overlapping |
|---|---|
| 141–160 | `PLANT_SYSTEMS_50_IDEAS`, `PLANT_NATURALISM_1000_IDEAS`, `PLANT_IMPROVEMENT_IDEAS` |

## Named later tracks (161–400, plan rows TBD)

| Track | Holistic IDs | Primary older docs |
|---|---|---|
| 9 Surface / flow | 161–180 | `HYDRODYNAMIC_LIFE_IDEAS`, `LIVING_MOTION_IDEAS` |
| 10 Chemistry | 181–200 | `CHEMISTRY_ORACLE`, `GOALS.md` H |
| 11 Memory / agency | 201–220 | Mind campaign docs, `SOUL_CREED`, **012** |
| 12 Dialogue / bond | 221–240 | Conversation / keeper docs, **012**, **201+** |
| 13 Care / aquascaping | 241–260 | `AQUASCAPING_CRAFT_IDEAS`, `care_feedback.gd` |
| 14 UI / a11y | 261–280 | `ONBOARDING_LEGIBILITY_IDEAS`, `hud_layout.gd` |
| 15 Discovery | 281–300 | Chronicles, milestones, onboarding |
| 16 Sound | 301–320 | `MUSIC_DANCE_*` |
| 17 Perf render | 321–340 | Performance campaign docs |
| 18 Sim architecture | 341–360 | `ARCHITECTURE.md`, `OPUS_HANDOFF*` |
| 19 Persistence | 361–380 | Saves / migrations / platforms; **010–011** |
| 20 Release | 381–400 | `INDEX.md`, CI, Steam / landing |

---

## Completed Wave A cross-cites (batches to date)

| Batch | Holistic IDs | Older items explicitly touched |
|---|---|---|
| 2026-10-01 | 001–003, 016 | `BROAD_DIRECTIONS_20`, `VISUAL_DIRECTIONS_20`, frame metrics |
| 2026-10-01b | 004, 005, 007 | Capture readiness, behavior probe, UI baseline |
| 2026-10-01c (this) | **010, 011, 012, 014, 015** | Architecture clocks, save fixtures, claim map, docs reconcile, this ledger |
