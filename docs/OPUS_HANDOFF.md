# Opus handoff — XL engineering epics

*2026-06-28.* What **cannot** be finished in a single Agent pass without
architecture review, multi-week scope, or native/GPU work. Bounce these to
**Opus 4.8** (or a dedicated principal sprint) with this doc as the brief.

**Already shipped (foundations — do not redo):**
- PR smoke gate (`.github/workflows/test.yml`, `scripts/run_smokes.sh`)
- SimRng + MindRng + CognitionKernel stub (#11, #15, #31 META)
- MultiMesh fauna via `fauna_voxel_builder` / `voxel_batch` (#21 META)
- Systemic security/saves/supply chain (~48/100 SYSTEMIC)
- Feed UX, alert dedup, META #2/#6/#7/#30 (partial sentience + perf hooks)

---

## Tier 0 — Map + gate before touching god-objects

| ID | Doc | Item | Why Opus |
|----|-----|------|----------|
| 91 | ENGINEERING | `ARCHITECTURE.md` module map | Required before any 33k-LOC carve; wrong map = wrong extraction |
| 1–4 | ENGINEERING | Decompose `fish.gd`, `main.gd`, `world.gd`, `sim_driver.gd` | XL strangler-fig; needs map + smoke pins per slice |
| 14–15 | ENGINEERING | `MindState` as sole mind↔fish channel | Touches 4k+ dynamic `.get()` calls; phased migration |

**Opus prompt seed:** *"Read ENGINEERING §A, write ARCHITECTURE.md with module boundaries, public surfaces, and carve order. Then extract `CameraController` from main.gd behind smokes."*

---

## Tier 1 — Sentience engine (META §A–B)

| ID | Item | Effort | Notes |
|----|------|--------|-------|
| 1 | Active inference as bid currency | XL | Rewires `global_workspace.gd` + `mind_world_model.gd`; needs eval harness |
| 3 | GRU-lite world model | L | Hand-rolled RNN in GDScript; save migration for `_world_model` |
| 4 | Theory-of-mind predictor | L | Bayesian neighbor model → motor bias |
| 5 | Inter-fish signal bus | L | New protocol + learning; schooling refactor |
| 8 | Sleep consolidation episodic→semantic | L | Night tick + schema store |
| 9 | Multi-goal motor blending | M | DDM → blended vector when coalitions co-ignite |
| 10 | Emotional contagion | M | School arousal field on `sim_driver` |
| 12–20 | Cognition framework | M–L | Plugin bids, DAG tick, addon package, cognition LOD |

**Opus prompt seed:** *"Implement META #9: when workspace co-ignites food+threat, synthesize skirt vector in fish locomotion; golden-trace test with MindRng."*

---

## Tier 2 — Performance & rendering (META §C)

| ID | Item | Effort | Notes |
|----|------|--------|-------|
| 22 | Shared material pool | M | `VoxelMat` pool; startup + stress-flush win |
| 23 | GPU compute boids | L | Compute shader; SoA buffers |
| 24–25 | Time-slice brain + SoA hot state | L–XL | Sim architecture change |
| 28 | WorkerThreadPool substrate/chemistry | M | Join before write-back |
| 62 | Frame-budget governor | M | Central scheduler + cognition LOD drop |

**Opus prompt seed:** *"META #24: round-robin mind ticks in sim_driver, 6 fish/frame, deferred event resolution; profile before/after."*

---

## Tier 3 — Deterministic engine (META §D)

| ID | Item | Effort | Notes |
|----|------|--------|-------|
| 32 | Fixed timestep + render interpolation | L | Authoritative 10Hz vs `_process` motion |
| 33–34 | Record/replay + time-travel scrubber | XL | Needs #31 complete (ambient randf sweep remaining) |
| 35 | Headless `--simulate days=N` soak | M | Promote `dev/balance_soak.gd` |
| 40 | Speculative what-if forks | XL | Hidden fork + Guardian narration |

**Opus prompt seed:** *"Finish SimRng migration: grep ambient randf in world/plants/shrimp; then META #33 input event log."*

---

## Tier 4 — Content & modding (META §E, SYSTEMIC §G–H)

| ID | Item | Effort |
|----|------|--------|
| 41–50 | JSON species, hot-reload mods, schema saves | L each |
| 47 | One palette source of truth | M |
| 52–54 | Activate or archive `data-schemas/` | M |

---

## Tier 5 — LLM moat (META §H, SYSTEMIC #15)

| ID | Item | Effort | Notes |
|----|------|--------|-------|
| 15 | SYSTEMIC LLM main-thread audit | M | Verify all paths async |
| 71 | Batched multi-fish inference | L | llama.cpp batch API |
| 72 | GBNF grammar decoding | M | Grounding guarantee |
| 76 | Distilled fish-voice adapter | XL | Training pipeline outside repo |
| 77 | Mock LLM for CI | S | **Quick win** — canned `GuardianLlm` stub keyed by context hash |

**Opus prompt seed:** *"META #77: GuardianLlm stub mode returning deterministic strings from prompt hash; wire smoke_guardian_plumbing.gd in CI."*

---

## Tier 6 — What Agent can still do without Opus

Low-risk, high-ROI picks for Composer/Auto:

- SYSTEMIC #22–25 (spatial grid audit, cognition round-robin spike)
- SYSTEMIC #62 shellcheck on `scripts/*.sh`
- SYSTEMIC #67 `.DS_Store` cleanup if tracked
- META #66 profiler scope labels in sim_driver subsystems
- META #67 golden-trace expansion (more mind scenarios)
- ENGINEERING #6 file-size CI budget
- Doc checkoffs + `docs/INDEX.md` percentage refresh

---

## Verification checklist for any Opus session

```bash
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://scripts/smoke_runner.gd
```

Add a targeted smoke for every behavioral change. Mark items `[x]` in the source idea doc with a one-line shipped note.
