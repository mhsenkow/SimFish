# Contributing to walstad loom

Thanks for helping. This repo is a Godot 4.6+ game (`shaders-godot/godot-project/`) with a
large idea-doc backlog that drives what gets built. Read [AGENTS.md](AGENTS.md) once for
layout and naming (walstad loom / SimFish / iAquarium are the same project).

## Setup

1. **Godot 4.6.3** — open `shaders-godot/godot-project/` in the editor, or run via
   `./scripts/godot.sh` (finds `/Applications/Godot.app` on macOS).
2. **Guardian in-process LLM (optional, desktop only)** — one-time install:
   ```bash
   ./scripts/install_godot_llama.sh   # cmake required on macOS: brew install cmake
   ./scripts/fetch_guardian_model.sh  # ~250MB GGUF for bundled/Steam builds
   ```
3. **Python tooling (optional)** — Steam store asset generator under
   `steam/store/` (uses a local `.venv`, git-ignored). Install deps only when
   that folder’s `requirements.txt` is present:
   ```bash
   cd steam/store && python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   python generate_assets.py
   ```

## Verify before you claim done

Use the shell suite (parallelism, per-script timeouts, isolated user dirs).
Do **not** use `smoke_runner.gd` as the suite entrypoint — it has no timeout
and can hang on soaks (see [AGENTS.md](AGENTS.md)).

```bash
bash scripts/run_smokes.sh
```

For a single subsystem, run one `extends SceneTree` smoke headless:

```bash
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --script res://scripts/smoke_tank_shapes.gd
```

If your change touches one subsystem, add or extend a `extends SceneTree` smoke under
`scripts/smoke_*.gd` and exercise it headless.

## How we pick work

- **Idea docs are the spec** — see [docs/INDEX.md](docs/INDEX.md). Releases:
  [CHANGELOG.md](CHANGELOG.md). Do foundations first;
  one idea at a time; read the cited `file:line` pointer before editing.
- **Extend, don't reinvent** — the project is mature; items marked shipped in docs stay
  shipped.
- **Match house style** — same naming, comment density, and idioms as surrounding code.

## Commits and PRs

- One focused commit per shipped idea; reference the doc + item number in the message.
- Mark shipped items in the idea doc (`- [ ]` → `- [x]`), mirroring [docs/GOALS.md](docs/GOALS.md).
- PRs should pass the GitHub **Smoke tests** workflow (headless smokes + targeted gdlint).

### Motion changes

A PR or commit that changes how a creature moves adds one line to its
description ([docs/CREATURE_MOTION_700.md](docs/CREATURE_MOTION_700.md) #116):

```
Motion: <principle tags> · <metric: name, before → after> · <clip: path or attachment>
```

That is: which principle it serves, which metric moved, and which clip shows it.
Capture clips through `scripts/dev_run.sh` and keep them under `output/` (not
committed). Pose and animation work must leave steering unchanged
(`smoke_motion_mind_parity`, `smoke_schooling_force_equivalence`); a deliberate
path change says so and names the re-baselined test. Details and examples are in
[docs/MOTION_REVIEW_PROTOCOL.md](docs/MOTION_REVIEW_PROTOCOL.md).

## Supply chain

Pinned versions and SHA256 hashes live in `scripts/supply_chain/manifest.env`. Update that
file when bumping Godot, godot_llama, or the Guardian GGUF.

## Non-Godot code (reference only)

- `sim-rust/` — chemistry **oracle** crate; **not wired into the game**. ADR 001
  (reference-only) is superseded by
  [docs/adr/003-sim-rust-as-oracle.md](docs/adr/003-sim-rust-as-oracle.md).
- `data-schemas/` — intended mod format; **not consumed by the game yet**. See
  [docs/adr/002-data-schemas-reference.md](docs/adr/002-data-schemas-reference.md).

## Big / architectural items

For `L`-effort ideas (decision-arbitration layer, webcam vision, local-LLM tiers), write a
short plan and confirm before large changes. Keep the base app under ~500MB; larger models
ship as opt-in downloads, not baked into every build.

## Definition of done

See [docs/ENGINEERING_CREED.md](docs/ENGINEERING_CREED.md). Archived point-in-time
pass notes live under [docs/archive/passes/](docs/archive/passes/) — historical
only, not a spec for new work.
