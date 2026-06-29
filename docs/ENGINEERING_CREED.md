# Engineering creed

One-page definition of done for walstad loom changes. (SYSTEMIC #78)

## Grounded

Every narrated line and mind state references facts from `MindContext` / sim vitals — no invented events.

## Never blocks

LLM, I/O, and network paths fail soft. Template voice fills gaps; saves refuse oversize JSON instead of OOM-crashing.

## Offline degrades

Steam/desktop bundles the Guardian model; slim builds opt in. Web/Android use template voice only.

## Tested

Subsystem changes get a headless `smoke_*.gd` or extend an existing one. Run `./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_runner.gd` before claiming done.

## Ablatable

Features toggle via `TankConfig` / Settings without ripping code out. Battery saver and reduced-motion trim cost paths.

## Documented

Shipped idea-doc items flip `- [x]`. ADRs capture big forks (`docs/adr/`). Non-normative code (`sim-rust/`, `data-schemas/`) says so in README.
