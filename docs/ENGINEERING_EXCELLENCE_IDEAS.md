# Engineering Excellence — "The Best-Coded Sim Fish That Ever Existed"

*100 ideas. Drafted 2026-06-28. A systemic code-quality pass — make the codebase as
excellent as the mind it runs.*

This is a different track from the sentience volumes (V–VIII): not new features, but
the **engineering that lets the features scale, stay correct, and keep being
extended for years.** The throughline: *great code in service of a felt mind.* Every
item either raises the engineering bar or directly protects the sentience system
(its performance budget, its testability, its determinism, its clean boundaries).

**The honest baseline (measured 2026-06-28).** This is already a serious codebase —
**98,113 LOC across 174 scripts**, strongly typed (**12,496 typed declarations vs 52
untyped**), **34 smoke tests**, a release pipeline, 7 focused autoloads. The
discipline *within* files is real. Three systemic issues hold it back from "best
coded ever," all about **scale**:

1. **Four god-objects hold a third of the code.**
   [`main.gd`](../shaders-godot/godot-project/scripts/main.gd) (9,333),
   [`world.gd`](../shaders-godot/godot-project/scripts/world.gd) (8,674),
   [`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd) (8,448),
   [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd) (6,389) =
   **~33k LOC**. Untestable, merge-conflict magnets, hard to reason about.
2. **Stringly-typed coupling between modules.** **916** `has_method()` duck-checks,
   **255** `get_node_or_null("/root/…")`, **4,383** `.get("key")` dynamic accesses.
   Typing is great inside a file and evaporates at every boundary.
3. **Verification isn't gated.** 34 smoke tests exist, but CI is only
   [`release.yml`](../.github/workflows/release.yml) — no PR/push gate runs them.

Format: **Effort** S (≤2h) / M (half-day) / L (full day+) / **XL** (multi-day),
**Impact** S / M / L. Line/symbol pointers are hints. The sentience system is the
crown jewel — these protect and polish it, never gut it.

---

## The three structural levers (read this first)

**Lever 1 — Decompose the god-objects.** ~33k LOC in four files is the single
biggest drag on everything: testing, perf reasoning, onboarding, safe change. The
mind subsystem already shows the way (≈30 small focused modules). Apply that pattern
to `fish`/`world`/`main`/`sim_driver`. Section A.

**Lever 2 — Typed contracts over stringly-typed coupling.** 4,383 `.get("…")` + 916
`has_method()` + 255 string node lookups mean the compiler can't protect cross-module
calls, refactors are scary, and every call pays a string-hash. Typed interfaces +
`MindState` as the sole mind↔fish channel fix correctness *and* speed. Sections B, D.

**Lever 3 — Make verification a gate, not a habit.** 34 smokes that only run when
someone remembers aren't a safety net. Run them on every PR, promote them to
assertions, and add determinism/round-trip tests so the *mind* can't regress
silently. Sections E, G.

---

## Section A — Tame the god-objects

*Lever 1. The headline. Strangler-fig, never big-bang — extract behind existing call
sites with smoke tests pinning behavior at each step.*

- [~] **1. Carve `fish.gd` (8,448) by concern.** Extract locomotion/hydrodynamics,
  anatomy/rendering, the behavior-tier state machine, and the mind-glue into separate
  scripts a thin `Fish` composes. The mind already lives in `mind_*`; this is
  everything else. *XL · L* — **Started 2026-06-28 (0C):** `FishLocomotion`
  ([`fish_locomotion.gd`](../shaders-godot/godot-project/scripts/fish_locomotion.gd))
  — first slice: boundary + collision-avoidance steering (`wall_avoid`,
  `local_clearance_push`, `hardscape_clearance_push`) as static funcs taking the
  Fish; fish.gd keeps thin one-line delegates (call sites unchanged, bodies moved
  verbatim). Smoke `smoke_fish_locomotion.gd` (compile + delegate-identity + 50-step
  no-NaN de-crowd) green; `felt_self`/`cognition_kernel`/`mind_channel` green.
  Remaining slices: `_motion_substep` (integration), `_boids` (schooling), velocity
  constraints, then anatomy/render and the behavior-tier table (#7).
- [~] **2. Carve `main.gd` (9,428).** It's input + camera + follow + keeper-chat + HUD
  glue at once. Extract `CameraController`, `FollowController`, `KeeperChatUI`,
  `HudController`. *XL · L* — **Started 2026-06-28 (0B):** `CameraController`
  ([`camera_controller.gd`](../shaders-godot/godot-project/scripts/camera_controller.gd))
  — pure-static orbit/pan/dolly/zoom/deadzone/eye math (TopdownMotion pattern),
  canonical owner of the camera tuning consts (main re-exports them); main delegates
  the math, behavior-identical (moved verbatim). Smoke `smoke_camera_controller.gd`
  (deadzone gate + math golden values + main.gd compile) green; `smoke_panels` /
  `smoke_menu_ui` / `smoke_aquascape_tools` green. Remaining slices: FollowController,
  KeeperChatUI, HudController.
- [ ] **3. Carve `world.gd` (8,674).** Environment building (room/heater/filter/floaters),
  visuals, and spawn are distinct; extract typed builders. *XL · L*
- [x] **4. Carve `sim_driver.gd` (6,389).** The orchestrator does chemistry + population +
  events + story + guardian + away-recap. Extract subsystems behind a thin driver that
  only sequences them. *XL · L* — **Started:** `sim_topdown.gd` (flock/sync-turn/conduct).
- [ ] **5. Composition over monolith.** `Fish`/`World` become thin coordinators holding
  typed sub-components — the exact pattern `mind_*` already proves works. *L · L*
- [ ] **6. A file/function-size CI budget.** Flag any new file > ~1,500 lines or function
  > ~80 lines so god-objects can't regrow after the carve. *S · M*
- [ ] **7. Data-drive the behavior tiers.** The ~25-tier `if`-ladder in `fish.tick()`
  becomes a typed table of rules (priority, guard, action) — readable, testable,
  reorderable. *L · L*
- [x] **8. Map before you carve.** Write the target module map (ARCHITECTURE.md, #91)
  *first*, so the decomposition has a destination, not just a direction. *M · L* —
  **Shipped 2026-06-28** alongside #91; carve order + per-slice destinations defined.
- [ ] **9. Kill cross-file reach-in.** The giants poke each other's internals; define
  narrow public APIs and privatize the rest so boundaries are real. *M · M*
- [ ] **10. Strangler-fig discipline.** Each extraction: smoke-test the current behavior,
  move code behind the same call site, re-run the smoke. Never a big-bang rewrite of a
  9k-line file. *M · L*

## Section B — Typed contracts over stringly-typed coupling

*Lever 2. Reclaim the compiler at module boundaries. Fixes correctness, refactor
safety, and per-call string-hash cost at once.*

- [ ] **11. Typed autoload access.** Replace the 255 `get_node_or_null("/root/X")` with
  direct typed singleton references (the 7 autoloads can expose typed APIs). *S · M*
- [ ] **12. Resolve handles once.** Where dynamic lookup is unavoidable, cache the node in
  `_ready()`, never per-call/per-frame (several giants re-resolve every tick). *S · M*
- [ ] **13. Typed interfaces over `has_method()` (916!).** Define `Creature` / `Mind` base
  types (or explicit interface scripts) so the compiler checks the contract instead of
  a runtime duck-check. *XL · L*
- [x] **14. Kill `f.get("_field")` (4,383!).** The mind pokes the fish via stringly-typed
  `get()`; route all of it through the typed `MindState`
  ([`mind_state.gd`](../shaders-godot/godot-project/scripts/mind_state.gd)) so access
  is checked and fast. *XL · L* — **Started:** `mind_channel.gd` + schema v3; `mind_context`
  + cognitive tick on channel.
- [x] **15. `MindState` as the ONLY mind↔fish channel.** It exists — make it the sole
  interface so cognitive modules never touch fish internals by string (and the mind
  could drive a shrimp or the TankMind unchanged). *L · L* — **Started:** `MindChannel.for_cycle`
  / `commit`; smoke `smoke_mind_channel.gd`. **0E (2026-06-28):** landed
  `smoke_mind_state_roundtrip.gd` (golden contract: sync copies all tracked fields,
  apply writes the writable subset byte-stably + doesn't clobber sync-only fields,
  dicts deep-copied) as the guard rail for the eventual single-channel flip. Audited
  the blocker: `broadcast` + the felt-self ticks dual-write `f.*` AND `ms.*`, and the
  rest of `tick()` reads `f.*` all frame — so the full flip needs all readers rerouted
  (behavior-sensitive XL). See ARCHITECTURE.md §8 mind-debt ledger.
- [ ] **16. Typed signals.** Audit the signal bus; give every signal an explicit typed
  payload so connections are compiler-checked. *M · M*
- [ ] **17. Enums over hot string constants.** Situations (`"keeper_reply"`), moods
  (`"calm"`), kinds (`"food"`) recur as bare strings; promote the hot ones to
  enums/consts. *M · M*
- [ ] **18. Typed Resources for hot per-fish state.** The dicts read every frame
  (`_mind_workspace`, `_mind_self_model`) become typed Resources where it's hot. *L · L*
- [ ] **19. Fail loud in dev, soft in prod.** `dict.get(k, default)` hides missing wiring;
  add dev-only asserts that the key exists, compiled out of release. *M · M*
- [ ] **20. Split & type `tank_config.gd` (2,964).** A god-config accessed by string
  elsewhere; group into typed sub-configs (chemistry / aeration / scenario / sentience /
  music) with typed getters. *L · M*

## Section C — Performance at scale

*Protect the sentience system's "never blocks the sim" contract as fish count and
module count grow.*

- [ ] **21. A per-frame cognition budget.** The mind cycle runs per fish per tick;
  enforce a ms budget + round-robin so 50 fish never spike a frame. *M · L*
- [ ] **22. Profile-gate the mind.** Profiler scopes around the cognitive cycle and the
  LLM queue; surface ms/frame in a perf HUD (#71). *M · M*
- [ ] **23. Kill hot-path allocations.** The mind builds dicts/arrays every tick
  (`build_for_fish`, `now_playing()`); pool or cache them. *M · L*
- [ ] **24. Stagger heavy per-fish work.** Phase full cognitive cycles across frames by
  id — cognition LOD — instead of all fish every frame. *M · L*
- [ ] **25. Confirm spatial-grid neighbor queries.** Perception/boids must not be O(n²);
  verify the spatial grid covers the sense queries (they're the hottest loop). *M · M*
- [ ] **26. Formalize `CognitionLOD`.** Off-screen / far / unnamed fish run a cheaper mind
  (partly true via the 22s ambient interval); make it an explicit, tuned tier. *M · L*
- [ ] **27. The typing pass buys perf too.** Eliminating 255 node-lookups + 916 duck-checks
  + dynamic `.get()` removes thousands of string-hashes per frame. *S · M*
- [ ] **28. Lazy, slim context builds.** Build the LLM context only when a thought is
  actually queued; the slim keeper-turn build is the right instinct — extend it. *M · M*
- [ ] **29. A frame-time regression test.** CI scene runs N fish for M frames and asserts
  ms/frame under budget — perf becomes a gate, not a vibe. *M · L*
- [ ] **30. A mind memory budget.** Episodic stores (64/fish) + dialogue rings + the
  resident GGUF; cap and measure total mind RAM, warn on bloat. *M · M*

## Section D — The mind subsystem as exemplary architecture

*The crown jewel — make it the reference the rest of the codebase aspires to.*

- [ ] **31. One `MindKernel` orchestrator.** [`mind_cycle`](../shaders-godot/godot-project/scripts/mind_cycle.gd)
  runs the phases; formalize it as the single entry, every module a pure function of
  `MindState`. *M · L*
- [ ] **32. Pure modules, explicit I/O.** The felt-self modules (`FishCoreAffect.texture(f)`,
  `FishBinding.first_person_glimpse(f)`) take state, return values; enforce no hidden
  side-effects so they're unit-testable. *M · L*
- [ ] **33. Decouple the mind from `fish.gd` entirely.** Run it on `MindState` + a sensor/
  actuator interface so it could drive *any* creature. The ultimate proof the boundary
  is clean. *XL · L*
- [ ] **34. Encode the module dependency graph.** The felt-self spine
  (protoself→core_affect→relevance→felt_now→binding) has an order; assert it so no
  module runs orphaned (the [`FeltSelfLayer`](../shaders-godot/godot-project/scripts/felt_self_layer.gd)
  gate is the seam). *M · M*
- [ ] **35. Versioned mind schema + migration.** `MIND_SCHEMA_VERSION` exists; add a
  migration chain so old saves gain new module fields with sane defaults as 5–9 land.
  *M · M*
- [ ] **36. An ablation switch per module.** Toggle any cognitive module off at runtime to
  A/B its contribution — make CONSCIOUSNESS_ENGINEERING #99 systemic. *M · M*
- [ ] **37. The mind as a library.** Package `mind_*` with no hard deps on world/main —
  only on a typed state + a sim-facts interface. *L · M*
- [ ] **38. Deterministic given seed + inputs.** Seed RNG per fish/tick so the whole cycle
  is reproducible — the prerequisite for testing emergent cognition (#44). *M · L*
- [ ] **39. One canonical "tick the mind" call.** Audit that every `Fish*`/`Mind*` module
  is invoked from one ordered place, not scattered through `fish.tick()`. *M · M*
- [ ] **40. `ARCHITECTURE_MIND.md`.** Map all ~30 mind modules — phase, I/O, data flow.
  The design is the asset; document it as the reference. *M · M*

## Section E — Verification as a gate

*Lever 3. 34 smokes exist; make them a wall, not a habit.*

- [x] **41. Run the 34 smokes on every PR.** Add a test workflow (headless scene runner)
  beside [`release.yml`](../.github/workflows/release.yml) — the single highest-ROI
  CI change. *M · L*
- [x] **42. One smoke-runner scene.** A single entry that runs all `smoke_*.gd`, reports
  pass/fail, and sets an exit code — replacing ad-hoc throwaway scenes. *M · M* —
  `smoke_runner.gd` + `scripts/run_smokes.sh`.
- [x] **43. Promote smokes to assertions.** Many likely just "run without crashing"; add
  explicit expected-value asserts (golden outputs). *M · M* — `smoke_topdown_motion.gd`,
  `smoke_mind_channel.gd`, expanded pond smokes.
- [ ] **44. Determinism/golden tests for the mind.** Seed a fish, run N ticks, assert the
  mind-state trajectory matches a golden snapshot — catches cognition regressions the
  eye can't. *M · L*
- [ ] **45. Save/load round-trip tests.** Fuzz a tank, save, reload, assert identical
  mind+sim state — the "soul doesn't leak on reload" guarantee, automated. *M · L*
- [ ] **46. Property-based sim invariants.** Assert conservation laws over random runs (the
  closed trophic ledger, no negative populations, O₂ within bounds). *M · L*
- [ ] **47. Mind-invariant tests.** Workspace ≤ CAPACITY, ignition threshold honored,
  writeback clamps respected, no module orphaned. *M · M*
- [ ] **48. Mock the LLM for tests.** A fake model so cognition tests need no GGUF; assert
  template-tier parity (the offline path is the contract). *M · M*
- [ ] **49. Coverage map of the giants.** Track which of fish/world/main/sim_driver have
  *any* test touching them; prioritize the dark corners. *S · M*
- [ ] **50. A flaky-test guard.** Run the suite N× in CI to catch nondeterminism (RNG/time
  leaks in the sim). *M · M*

## Section F — Data, save/load, schema & migration

*Saves are the player's relationship with their tank — they must never corrupt.*

- [ ] **51. A typed save schema + migration chain.** Save v5 today; formalize v_n→v_n+1
  migrations, each with a test. *L · L*
- [ ] **52. Validate & repair on load.** A corrupt mind dict should degrade gracefully,
  never crash the tank. *M · M*
- [ ] **53. Forward-compatible saves.** Preserve unknown future keys so a newer save opened
  in an older build degrades, not corrupts. *M · M*
- [ ] **54. Atomic saves.** Write-temp-then-rename so a crash mid-save never destroys a
  tank. *S · M*
- [ ] **55. Separate sim-state from view-state.** Persist the source of truth only; never
  save derived/visual fields. *M · M*
- [ ] **56. A save fuzzer in CI.** Mutate save bytes, assert no crash on load. *M · M*
- [ ] **57. Save-size telemetry (local).** Episodic stores grow; measure save size, warn
  when a tank's mind state bloats. *S · M*
- [ ] **58. Schema doc generated from `to_dict`/`from_dict`.** Kept in sync with the code,
  not hand-written. *M · M*
- [ ] **59. Migratable mind across felt-self growth.** As modules 5–9 land, existing fish
  must gain the new fields with sane defaults on load. *M · M*
- [ ] **60. A "golden save" corpus.** Keep real saves from each version in CI; assert every
  build still loads them all. *M · L*

## Section G — Build, CI/CD, release & cross-platform

*The git log shows real pain here (macOS CI, godot_llama version lookup). Harden it.*

- [x] **61. A PR CI gate.** Build + smoke + lint on every PR; `release.yml` stays for
  tagged releases only. *M · L*
- [ ] **62. Pin Godot + godot_llama + model versions.** The recent CI break was a version
  lookup; pin and checksum-verify everything. *S · M*
- [ ] **63. Reproducible builds.** Lockfile the toolchain so a build is reproducible across
  machines and CI. *M · M*
- [ ] **64. A per-platform export matrix.** Desktop / macOS / web / (mobile) built and
  smoke-launched headless on CI. *L · M*
- [ ] **65. Bundled-model integrity.** Verify the GGUF checksum at build *and* runtime
  (the download path exists; harden it). *S · M*
- [ ] **66. Strip disabled native paths.** Web/Android disable the LLM; ensure those builds
  don't compile/ship the dead `godot_llama` path. *M · M*
- [ ] **67. Build-size budgets per platform.** Track export size (the 93MB godotsteam
  weight); fail CI on regression. *S · M*
- [ ] **68. Smoke-launch the exported build.** Boot the actual export headless, run one
  tank tick, assert no errors before publishing. *M · M*
- [ ] **69. Local, network-free crash logging.** Structured crash logs the user can choose
  to share — never auto-sent. *M · M*
- [ ] **70. Auto-assembled release notes.** Build the changelog from idea-doc checkmarks +
  commits. *S · M*

## Section H — Observability, profiling & debugging

*You can't keep an emergent mind correct without seeing inside it.*

- [ ] **71. A built-in perf HUD.** ms/frame split by sim / render / mind / LLM, toggleable.
  *M · M*
- [ ] **72. Promote the mind scorecard.** [`mind_debug`](../shaders-godot/godot-project/scripts/mind_debug.gd)
  §J exists — surface a live consciousness scorecard (integration, ignition rate, LLM
  latency, cache hits). *M · M*
- [ ] **73. Structured, leveled logging.** Replace ad-hoc prints with a category logger
  (mind / sim / llm / save), filterable, off in release. *M · M*
- [ ] **74. The workspace inspector as a real dev tool.** Polish the live inspector into a
  debug overlay for any fish or the TankMind. *M · M*
- [ ] **75. A deterministic replay recorder.** Record inputs + seed, replay a session
  exactly — the only sane way to debug emergent mind bugs. *L · M*
- [ ] **76. Per-module mind timing.** Each cognitive module reports its ms so the expensive
  one is obvious. *M · M*
- [ ] **77. A systematic assert layer.** Grow the 79 asserts into invariant checks across
  subsystems, compiled out of release. *M · M*
- [ ] **78. A "why did it do that" trace.** Log the bid competition → winning focus →
  chosen action for an inspected fish — explainable cognition. *M · M*
- [ ] **79. Leak/footprint watch.** Track node counts, mind-store sizes, orphaned
  RefCounteds over a long run. *M · M*
- [ ] **80. Frame-spike detector.** Log when a frame exceeds budget *with* the culprit
  subsystem. *S · M*

## Section I — Code hygiene, tooling & consistency

*Mechanical quality, enforced by tools so reviews can focus on design.*

- [x] **81. A GDScript linter in CI.** `gdlint`/`gdformat` (gdtoolkit) on every PR — style
  enforced mechanically, not by reviewer attention. *M · M* — `.github/workflows/test.yml`
  lint job on engineering modules (`gdlintrc`).
- [ ] **82. One-time `gdformat` pass.** Format the whole tree for consistency, then enforce.
  *S · M*
- [ ] **83. A naming-convention check.** `_private`, signals, consts — the tree is mostly
  consistent; codify and lint it. *S · M*
- [ ] **84. A dead-code sweep.** Static-analyze 98k LOC for unused funcs/vars/signals — the
  single TODO suggests debt is *hidden*, not absent. *M · M*
- [ ] **85. De-dupe the idea docs.** `CONSCIOUSNESS_ENGINEERING_IDEAS.md` lives in both repo
  root and `docs/` — one source of truth. *S · S*
- [ ] **86. `.uid` hygiene.** Ensure every `.gd.uid` is committed/ignored consistently
  (Godot 4.4 artifacts; they're noise if half-tracked). *S · S*
- [ ] **87. Extract shared utilities.** Clamp helpers, autoload access, tank-bounds math are
  duplicated across the giants; a typed `util` lib. *M · M*
- [ ] **88. A consistent error-handling policy.** 120 `push_error/warning` mixed with silent
  `.get` defaults — decide when to assert vs warn vs default, and apply it. *M · M*
- [ ] **89. Name the magic numbers.** Hoist tuned constants (0.42 ignition, 0.65 thresholds,
  decay rates) into named consts grouped by system. *M · M*
- [ ] **90. A pre-commit hook.** format + lint + quick-smoke locally so CI rarely fails —
  extend the AGENTS.md culture into git. *S · M*

## Section J — Engineering knowledge & sustainability

*A 98k-LOC project lives or dies on whether the "why" is captured.*

- [x] **91. `ARCHITECTURE.md` — the missing map.** The 174 files, the 7 autoloads, the data
  flow, the mind kernel. The single most valuable doc for a project this size; the
  prerequisite for the carve (#8). *M · L* — **Shipped 2026-06-28:**
  [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) — answers "where does feeding live?" +
  "what's safe to extract first?"; per-god-object ownership + line-anchored carve
  slices for all four; dependency-ordered carve plan; import/no-cycle rules; mind-debt
  ledger; reusable carve-checklist template. Line numbers verified against HEAD.
- [ ] **92. ADRs (architecture decision records).** Capture the big calls — offline-first
  LLM, GWT mind, save versioning, non-Meta policy — so the *why* survives. *M · M*
- [ ] **93. An idea-doc series index.** 8+ volumes now; one doc mapping volume → shipped% →
  files touched, so the backlog stays navigable. *S · M*
- [ ] **94. Commit & own `AGENTS.md`.** It's currently untracked; commit it as the
  authoritative contributor + agent contract (build / test / style / verify). *S · M*
- [ ] **95. A module-ownership map.** Who/what owns each subsystem and its boundaries — the
  social contract that stops god-objects regrowing. *S · M*
- [ ] **96. A 30-minute onboarding path.** "Run → change → verify" documented end-to-end
  (the run/verify skills exist; write the golden path for a new contributor or
  future-you). *M · M*
- [ ] **97. A glossary of the mind.** Bid, ignition, workspace, qualia, binding, felt-now —
  define the vocabulary so the codebase reads coherently across 30 modules. *S · M*
- [ ] **98. Written, CI-enforced budgets.** ms/frame, mind RAM, save size, build size — as
  committed numbers, not aspirations. *S · M*
- [ ] **99. A "definition of done" for sentience features.** Grounded · never-blocks ·
  offline-degrades · tested · ablatable · documented — codify the discipline the docs
  keep restating, so it's checked, not remembered. *S · M*
- [ ] **100. The engineering creed, one page.** "Best-coded sim fish ever" = readable,
  typed, tested, fast, decomposed — *in service of a felt mind.* Every PR measured
  against it. *S · L*

---

## If Cursor only does five

In order — this is the spine of "improve at scale":

1. **#91 — `ARCHITECTURE.md`.** You cannot safely refactor 33k LOC of god-object that
   isn't mapped. Map first.
2. **#41 — a PR CI gate running the 34 smokes.** Stop quality depending on memory.
   Highest ROI single change; it's the safety net for everything below.
3. **#1–4 + #10 — decompose the four god-objects, strangler-fig.** The biggest scale
   lever. Behind the CI net from #41, carve incrementally with smokes pinning behavior.
4. **#14 + #15 — `MindState` as the only mind↔fish channel.** Kills the worst of the
   4,383 dynamic accesses, protects the crown jewel, and makes the mind portable.
5. **#21 + #71 — a per-frame cognition budget + perf HUD.** Protects "never blocks the
   sim" as fish count and the felt-self modules scale.

> **Sequencing:** map (#91) → gate (#41) → then decompose (#1–4) and type (#13–15)
> *behind the gate's safety net*. Never refactor a 9k-line file without smokes
> watching. And measure first: every budget in Section J should start as the *current*
> number, then ratchet — you can't improve at scale what you don't measure at scale.

> **The sentience throughline:** none of this is busywork against the mind — it's
> what lets the mind grow. Decomposition makes the cognitive modules testable; typed
> `MindState` makes the pipeline safe; the perf budget keeps it never-blocking; golden
> tests keep the soul from regressing; determinism makes emergent cognition
> debuggable. Best-coded *and* most alive are the same project.
