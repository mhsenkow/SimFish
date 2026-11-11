# Documentation index

Map of every durable doc in `docs/`. **Completion status** lives in each
doc’s own checkboxes or ledgers — this index does not track shipped%.

**Shipped progress** also lives in [GOALS.md](GOALS.md) (251 checkboxes,
sections A–H; one open: multi-tank wallpaper) and
[../CHANGELOG.md](../CHANGELOG.md) (release history through current).

Default agent work starts from the six pillar idea docs + GOALS (see
`.cursor/rules/idea-docs-workflow.mdc`). Holistic execution uses
[HOLISTIC_FINISHING_PLAN_400.md](HOLISTIC_FINISHING_PLAN_400.md) + ledger.
Full backlog map = this file.

## Operational facts (v0.2.53)

Reconcile these when they drift (Holistic #014). Idea-doc intros dated
2026-06-28 are historical snapshots — **do not treat those counts as current.**

| Fact | Value | Source |
|---|---|---|
| Game version | `0.2.53` | `project.godot` `config/version` |
| Godot (CI / CONTRIBUTING) | 4.6.3 | `scripts/supply_chain/manifest.env`, `.github/workflows/` |
| Autoloads | **11** (AppLog … GamepadInput) | `project.godot` `[autoload]`, `smoke_autoload_contract.gd` |
| Scenario templates | **18** | `scenario_picker.gd` `SCENARIOS` |
| Playable fish templates | **18** | `tank_config.gd` `SPECIES_LIBRARY` |
| Internal render default | **1024×576** (beauty / first-launch mid: 512×288) | `TankConfig.render_width/height`, [STYLE_GUIDE](../style-guide/STYLE_GUIDE.md) |
| Window | 1536×864, stretch `canvas_items` | `project.godot` |
| `scripts/*.gd` | **642** (~**295** `smoke_*`) | counted 2026-11-10 |
| Shaders | **26** `.gdshader` | `shaders-godot/godot-project/shaders/` |

## Start here

| Doc | What it is |
|---|---|
| [GOALS.md](GOALS.md) | Master shipped/backlog tracker |
| [BROAD_DIRECTIONS_20.md](BROAD_DIRECTIONS_20.md) | **20 broad improvement directions** + the append-only application log |
| [VISUAL_DIRECTIONS_20.md](VISUAL_DIRECTIONS_20.md) | **20 directions with frame-level impact** — measured 2026-09-13 capture pass; companion to BROAD_DIRECTIONS_20 |
| [HOLISTIC_FINISHING_PLAN_400.md](HOLISTIC_FINISHING_PLAN_400.md) | **400-task finishing plan** — beauty, aliveness, ecology, care, release readiness |
| [HOLISTIC_FINISHING_LEDGER.md](HOLISTIC_FINISHING_LEDGER.md) | Execution evidence for the finishing plan (status ≠ checkbox count) |
| [HOLISTIC_CROSSREF.md](HOLISTIC_CROSSREF.md) | Holistic task IDs ↔ older campaign docs |
| [PLAYER_CLAIM_EVIDENCE.md](PLAYER_CLAIM_EVIDENCE.md) | Player-facing claims → inputs (facts vs inferences vs forbidden internals) |
| [OBSERVATION_CONTRACT.md](OBSERVATION_CONTRACT.md) | Minimum visible/measurable behaviour checklist |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Setup, smokes, commit conventions |
| [../CHANGELOG.md](../CHANGELOG.md) | Release history (canonical through current) |
| [../AGENTS.md](../AGENTS.md) | Repo layout for agents/contributors |
| [adr/](adr/) | Architecture decision records |
| [ENGINEERING_CREED.md](ENGINEERING_CREED.md) | Definition of done / engineering values |

## Architecture

Two files, two audiences — both current:

| Doc | Read this if… |
|---|---|
| [../ARCHITECTURE.md](../ARCHITECTURE.md) | You need clocks, state ownership, RNG, mind-tick path (Holistic #010 reader doc) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | You need the god-object carve map — ownership, public surfaces, carve order, motion channels (§11) |

## Releases

Canonical narrative: [../CHANGELOG.md](../CHANGELOG.md).

Per-version stubs (short summary + link into CHANGELOG) remain at
`RELEASE_v0.2.38.md` … `RELEASE_v0.2.53.md` so GitHub Pages and older README
links keep working.

| Stub | Version |
|---|---|
| [RELEASE_v0.2.53.md](RELEASE_v0.2.53.md) | Latest — smoke + mind wiring |
| [RELEASE_v0.2.52.md](RELEASE_v0.2.52.md) | Living motion + GPU skinning |
| [RELEASE_v0.2.51.md](RELEASE_v0.2.51.md) | Room light, fluid, established look |
| [RELEASE_v0.2.50.md](RELEASE_v0.2.50.md) | Long-run ecology |
| [RELEASE_v0.2.41.md](RELEASE_v0.2.41.md) | Viewport fills the desktop window |
| [RELEASE_v0.2.40.md](RELEASE_v0.2.40.md) | Drawn nav icons |
| [RELEASE_v0.2.39.md](RELEASE_v0.2.39.md) | Color, habitats, long-session |
| [RELEASE_v0.2.38.md](RELEASE_v0.2.38.md) | First RELEASE-note series |

## Platform / store

| Doc | Focus |
|---|---|
| [IOS_APP_STORE.md](IOS_APP_STORE.md) | iOS App Store path |
| [ios/APP_STORE_CONNECT.md](ios/APP_STORE_CONNECT.md) | App Store Connect ops |
| [ANDROID_PLAY.md](ANDROID_PLAY.md) | Android Play track |

## Idea docs (director specs)

Each file is a code-grounded backlog. Pick **foundations / substrate** items
first; one idea at a time.

### Engineering & platform

| Doc | Focus |
|---|---|
| [ENGINEERING_EXCELLENCE_IDEAS.md](ENGINEERING_EXCELLENCE_IDEAS.md) | Code architecture, typed contracts, god-object carve, CI gate, mind polish |
| [SYSTEMIC_IMPROVEMENTS_IDEAS.md](SYSTEMIC_IMPROVEMENTS_IDEAS.md) | Security, supply chain, docs, accessibility, non-Godot code fate |
| [META_ENGINEERING_IDEAS.md](META_ENGINEERING_IDEAS.md) | Staff/principal swings: cognition framework, deterministic engine, perf 10×, content-as-data, LLM moat, moonshots |
| [PERFORMANCE_REALTIME_IDEAS.md](PERFORMANCE_REALTIME_IDEAS.md) | **The real-time mind perf pass** — 100 ways to make it faster without losing a thought |
| [PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md](PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md) | **Performance II — the unthrottled mind** — architectural follow-on after Perf I |
| [OPUS_HANDOFF.md](OPUS_HANDOFF.md) | **XL epics for Opus** — god-object carve, replay, GPU boids, LLM batching |
| [OPUS_HANDOFF_DETAILED.md](OPUS_HANDOFF_DETAILED.md) | Per-task execution brief + progress ledger for Opus carve sessions |
| [CHEMISTRY_ORACLE.md](CHEMISTRY_ORACLE.md) | Chemistry oracle / sim-rust comparison notes |

### Sentience & mind

| Doc | Focus |
|---|---|
| [SENTIENT_FISH_IDEAS.md](SENTIENT_FISH_IDEAS.md) | Fish agency, memory, behavior |
| [SENTIENCE_THE_FELT_SELF_IDEAS.md](SENTIENCE_THE_FELT_SELF_IDEAS.md) | Felt self / qualia layer |
| [SENTIENCE_THE_DARING_MIND_IDEAS.md](SENTIENCE_THE_DARING_MIND_IDEAS.md) | Daring mind, keeper dialogue |
| [SENTIENCE_THE_CONVERSATION_IDEAS.md](SENTIENCE_THE_CONVERSATION_IDEAS.md) | Keeper–fish conversation |
| [SENTIENCE_THE_NIGHT_WATCH_IDEAS.md](SENTIENCE_THE_NIGHT_WATCH_IDEAS.md) | Night watch / away presence |
| [SENTIENCE_EMBEDDED_MODEL_IDEAS.md](SENTIENCE_EMBEDDED_MODEL_IDEAS.md) | In-process SmolLM2 Guardian |
| [SENTIENCE_UNIVERSAL_DEPLOYMENT_IDEAS.md](SENTIENCE_UNIVERSAL_DEPLOYMENT_IDEAS.md) | Platform matrix, downloads |
| [SENTIENCE_DEEP_SCIENCE_IDEAS.md](SENTIENCE_DEEP_SCIENCE_IDEAS.md) | Science-facing mind features |
| [SENTIENCE_THE_LEARNING_MIND_IDEAS.md](SENTIENCE_THE_LEARNING_MIND_IDEAS.md) | IC8 pass: on-device learning, instruments, federation |
| [SENTIENCE_EVAL_HARNESS.md](SENTIENCE_EVAL_HARNESS.md) | **Falsifiable sentience eval** — behavioural + integration invariants |
| [ACTIVE_INFERENCE_CORE.md](ACTIVE_INFERENCE_CORE.md) | **META #1 capstone design** — expected-free-energy objective |
| [SENTIENCE_THE_PREOCCUPATION_IDEAS.md](SENTIENCE_THE_PREOCCUPATION_IDEAS.md) | **Felt sentience** — shared grounded concept / EFE prior |
| [SENTIENCE_THE_SOUL_WE_MAKE_IDEAS.md](SENTIENCE_THE_SOUL_WE_MAKE_IDEAS.md) | **Deepen the mechanism** — cognition more conscious |
| [SENTIENCE_THE_RISING_CURVE_IDEAS.md](SENTIENCE_THE_RISING_CURVE_IDEAS.md) | **Measurably becoming** — Compression-Dividend (ΔG) as aliveness meter |
| [SENTIENCE_THE_LOOM_THAT_THINKS_500.md](SENTIENCE_THE_LOOM_THAT_THINKS_500.md) | **Voice, awareness, tank as a mind** — 500 ideas at the mind’s edges |
| [SENTIENCE_THE_SPARK_IDEAS.md](SENTIENCE_THE_SPARK_IDEAS.md) | **Superseded** by [REFINEMENT_100_IDEAS.md](REFINEMENT_100_IDEAS.md) — do not start new work here |
| [SOUL_CREED.md](SOUL_CREED.md) | Honest one-page stance for the soul pass |
| [CONSCIOUSNESS_ENGINEERING_IDEAS.md](CONSCIOUSNESS_ENGINEERING_IDEAS.md) | GWT / workspace engineering |
| [GUARDIAN_COMPANION_IDEAS.md](GUARDIAN_COMPANION_IDEAS.md) | Guardian fish companion |
| [MAKE_IT_THERE_IDEAS.md](MAKE_IT_THERE_IDEAS.md) | Presence / “make it there” voice |
| [PLAYER_BOND_IDEAS.md](PLAYER_BOND_IDEAS.md) | Keeper bond, milestones |

### Simulation & life

| Doc | Focus |
|---|---|
| [PLANT_IMPROVEMENT_IDEAS.md](PLANT_IMPROVEMENT_IDEAS.md) | Flora growth, food web (pillar 50) |
| [PLANT_SYSTEMS_50_IDEAS.md](PLANT_SYSTEMS_50_IDEAS.md) | Plant systems bridge between pillar 50 and naturalism 1000 |
| [HYDRODYNAMIC_LIFE_IDEAS.md](HYDRODYNAMIC_LIFE_IDEAS.md) | Water flow, hydrodynamics |
| [TOPDOWN_MOTION_IDEAS.md](TOPDOWN_MOTION_IDEAS.md) | Top-down pond motion |
| [LIVING_MOTION_IDEAS.md](LIVING_MOTION_IDEAS.md) | **The murmuration pass** — topological schooling, shared flow, micro-motion |
| [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) | **The illusion of life** — 700 motion ideas graded on twelve animation principles |
| [MOTION_REFERENCE.md](MOTION_REFERENCE.md) | Real-animal motion reference + kinematics table |
| [MOTION_EXPOSURE_SHEETS.md](MOTION_EXPOSURE_SHEETS.md) | Key poses / frame counts for motion smokes |
| [MOTION_SCORECARD.md](MOTION_SCORECARD.md) | Twelve principles × creature families, graded A–F |
| [MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md) | Blind real-or-game review + per-PR motion line |
| [MOTION_BUDGET.md](MOTION_BUDGET.md) | Per-creature motion cost targets by LOD tier |
| [AQUASCAPING_CRAFT_IDEAS.md](AQUASCAPING_CRAFT_IDEAS.md) | Aquascape tools & objects |

### Look, feel, onboarding

| Doc | Focus |
|---|---|
| [AESTHETICS_IDEAS.md](AESTHETICS_IDEAS.md) | Render pipeline, visual polish |
| [VISUAL_POLISH_200_IDEAS.md](VISUAL_POLISH_200_IDEAS.md) | **200 things that would make it look better** |
| [REAL_TANK_FIDELITY_200.md](REAL_TANK_FIDELITY_200.md) | **200 steps to a tank that looks like the real one** |
| [REFINEMENT_100_IDEAS.md](REFINEMENT_100_IDEAS.md) | **The refinement pass** — 100 items, zero additions (replaces Spark) |
| [REFINEMENT_II_100_IDEAS.md](REFINEMENT_II_100_IDEAS.md) | **Refinement II** — harden fresh machinery; verified [V] and audit-then-fix [A] markers |
| [MUSIC_DANCE_IDEAS.md](MUSIC_DANCE_IDEAS.md) | Ambient audio, fish dance |
| [MUSIC_DANCE_PLAYBOOK.md](MUSIC_DANCE_PLAYBOOK.md) | How to ship music/dance items from the ideas doc |
| [ONBOARDING_LEGIBILITY_IDEAS.md](ONBOARDING_LEGIBILITY_IDEAS.md) | New-player legibility |

### Mega campaigns (1000-scale)

September/October vertical slices. Cross-link each other; Holistic crossref
cites several. Not the default agent shortlist — check INDEX / crossref before
starting.

| Doc | Focus |
|---|---|
| [FISH_ALIVE_1000_IDEAS.md](FISH_ALIVE_1000_IDEAS.md) | Body-first aliveness |
| [PLANT_NATURALISM_1000_IDEAS.md](PLANT_NATURALISM_1000_IDEAS.md) | Plant naturalism mega-campaign |
| [COMMS_AI_1000_IDEAS.md](COMMS_AI_1000_IDEAS.md) | Inbox / voice / toast campaign |
| [PLAYER_WISH_1000_IDEAS.md](PLAYER_WISH_1000_IDEAS.md) | UI / friction mega-campaign |
| [HOLISTIC_IMPROVEMENTS_1000.md](HOLISTIC_IMPROVEMENTS_1000.md) | Oct review: WL-0001–WL-1000 proposals (**no checkboxes** by design) |
| [HOLISTIC_IMPROVEMENTS_1000_LEDGER.md](HOLISTIC_IMPROVEMENTS_1000_LEDGER.md) | Thin execution notes for the Oct review pass |

## ADRs

Index: [adr/README.md](adr/README.md).

| ADR | Decision |
|---|---|
| [001-sim-rust-reference.md](adr/001-sim-rust-reference.md) | `sim-rust/` stays reference-only |
| [002-data-schemas-reference.md](adr/002-data-schemas-reference.md) | `data-schemas/` stays non-normative until wired |
| [003-sim-rust-as-oracle.md](adr/003-sim-rust-as-oracle.md) | `sim-rust/` kept and tested as a chemistry oracle (supersedes 001) |

## Archive

Point-in-time pass notes and incident write-ups. **Do not start new
implementation work from these.**

| Location | Contents |
|---|---|
| [archive/passes/](archive/passes/) | Dated `*_20261007`–`20261102` audits + save-isolation incident |

Thin stubs remain at the old `docs/<name>.md` paths (same filenames as the
archive table) and redirect here so GitHub Pages and older README links keep
resolving.

## Web landing

Static GitHub Pages site: [index.html](index.html), [style.css](style.css),
[site.js](site.js), [privacy.html](privacy.html).

## Adjacent repo docs (outside `docs/`)

| Doc | What it is |
|---|---|
| [../README.md](../README.md) | Player-facing project README |
| [../style-guide/STYLE_GUIDE.md](../style-guide/STYLE_GUIDE.md) | Palette, pixel grid, dither, fidelity tiers |
| [../shaders-godot/README.md](../shaders-godot/README.md) | Render-pipeline deep dive |
| [../steam/STEAMWORKS.md](../steam/STEAMWORKS.md) | Steamworks upload / depots |
| [../steam/store/STORE_PAGE.md](../steam/store/STORE_PAGE.md) | Store copy |
| [../extensions/mind_kernel/README.md](../extensions/mind_kernel/README.md) | Optional GDExtension mind kernel |
| [../sim-rust/README.md](../sim-rust/README.md) | Chemistry oracle crate (ADR 003) |
| [../data-schemas/README.md](../data-schemas/README.md) | Non-normative species/plant schemas |
