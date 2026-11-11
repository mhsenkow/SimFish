# Engineering creed

One-page definition of done for walstad loom changes. (SYSTEMIC #78)

## Grounded

Every narrated line and mind state references facts from `MindContext` / sim vitals — no invented events.

## Never blocks

LLM, I/O, and network paths fail soft. Template voice fills gaps; saves refuse oversize JSON instead of OOM-crashing.

## Offline degrades

Steam/desktop bundles the Guardian model; slim builds opt in. Web/Android use template voice only.

## Tested

Subsystem changes get a headless `smoke_*.gd` or extend an existing one.
**Preferred:** `./scripts/run_smokes.sh` (parallelism, per-script timeout,
`scripts/smoke_baseline.txt`). Example: `./scripts/run_smokes.sh --include save_fixtures`.
Do **not** use `smoke_runner.gd` for unattended runs — it has no timeout
(AGENTS.md). Single-script debug:
`./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_<name>.gd`.

Operational facts (version, scenario count, autoload count, render defaults,
script counts) live in [`docs/INDEX.md`](INDEX.md) “Operational facts” and
must match `project.godot` + `scenario_picker.gd` (Holistic #014).

## Ablatable

Features toggle via `TankConfig` / Settings without ripping code out. Battery saver and reduced-motion trim cost paths.

## Documented

Shipped idea-doc items flip `- [x]`. Releases: [`CHANGELOG.md`](../CHANGELOG.md).
Backlog map: [`docs/INDEX.md`](INDEX.md). ADRs: `docs/adr/`. Historical pass notes:
`docs/archive/passes/` only — do not start new work there. Non-normative code
(`sim-rust/`, `data-schemas/`) says so in README.
