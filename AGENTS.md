# Repo orientation

Quick map so you don't have to rediscover the layout. Fuller detail lives in
[README.md](README.md).

## Naming (one project, three names)

- **walstad loom** — the game's real name (Godot `config/name`, Steam store).
- **SimFish** — the GitHub repo name (clone URLs, `res://` references say `SimFish/`).
- **iAquarium** — the local working-copy folder name.

All the same project.

## Where things live

| Path | What it is |
|---|---|
| `shaders-godot/godot-project/` | **The actual game.** Open this in Godot 4.6+. Main scene: `tank_menu.tscn`. |
| `shaders-godot/godot-project/scripts/` | ~405 GDScript files, ~155 of them `smoke_*` tests (subsystem breakdown in README). |
| `shaders-godot/godot-project/shaders/` | Render pipeline (palette quantize + voxel/water/glass/etc). |
| `shaders-godot/godot-project/dev/` | Headless capture scenes (`capture.tscn`, `capture_pass.*`) — dev-only, not part of the game. |
| `shaders-godot/make_palette.py` | Palette PNG generator. |
| `sim-rust/` | Reference Rust chemistry sim. **Not wired into the game** (the game's chemistry is GDScript). |
| `data-schemas/` | JSON Schemas documenting an intended moddable data format. **Not consumed by the game yet.** |
| `steam/` | Steamworks depots, upload scripts, store copy. `depot_ids.env` is local-only. |
| `steam/store/` | Capsule/screenshot generator (`generate_assets.py`, needs `.venv`). |
| `marketing/` | Capsule art + gameplay screenshots + logos. `marketing/sources/` holds raw reference grabs. |
| `docs/` | GitHub Pages landing (`index.html`/`style.css`/`fonts`/`img`) + `GOALS.md` backlog. |
| `tools/render_preview.py` | Standalone Python pixel-art preview generator (writes to repo-root `output/`). |
| `style-guide/` | Palette + pixel/dither rules. |
| `output/` | Scratch render output — git-ignored, regenerated on demand. |
| `build/` | Exported binaries — git-ignored, distributed via GitHub Releases. |

## Gotchas

- **Fonts are intentionally duplicated.** `docs/fonts/` (IBM Plex woff2) feeds the
  web landing page via a relative `href`; `shaders-godot/godot-project/assets/fonts/`
  feeds the Godot theme via `res://`. Neither runtime can read the other's copy, so
  both must exist. Don't "dedupe" them.
- **`dev/capture.tscn` writes to a real save slot.** It builds a live `World`,
  which reads `TankSaves` for the active slot, can call
  `saves.clear_active_state()` on a substrate mismatch (`world.gd`), and
  autosaves what it builds — one run created a whole new "Beginner Sandbox"
  slot with a 1.1 MB `state.json`. It also renders a *bare* tank unless a
  populated slot loads, so it is nearly useless for checking fauna anyway.
  If you must run it, back up
  `~/Library/Application Support/Godot/app_userdata/walstad loom/tanks`
  first and restore afterwards.
- **Looking at the game: `dev/inspect.tscn`.** Renders the live World from
  four angles at 1152x648 into `inspect_*.png`, so visual work can be checked
  by looking rather than by assertion. `-- hide=NodeName` removes a node so a
  visual artifact can be bisected (`hide=WORLD` for everything), and
  `-- settle=N` changes the build wait. **It pushes the palette tints the way
  main.gd does** - without that the world renders desaturated, because the
  registered defaults multiply saturation and value by the global palette.
  Like `dev/capture.tscn` it builds a real World and therefore writes to a
  real save slot: back up
  `~/Library/Application Support/Godot/app_userdata/walstad loom/tanks` first.
  `dev/footprint_probe.gd` lists meshes escaping the tank footprint (use real
  `mesh.get_faces()` vertices, not the AABB - the AABB of a correct hex prism
  IS a rectangle), and `dev/audio_probe.tscn` measures generated audio levels
  per bus (`-- healthy` for a live-tank env, `-- fullbed` to force the full
  synth). Both need a long settle: much of the World is built over ~200 frames.
- **Never put comments in `project.godot`.** Godot's ConfigFile writer strips
  whitespace and folds a comment onto the line below it on the next re-save, so
  `# note` above `AppLog="*res://scripts/app_log.gd"` becomes one commented-out
  line and the autoload silently disappears. This happened to `AppLog` *and*
  `Localization`: the game booted with no logger and no translations, nothing
  failed to compile, and the first symptom was an out-of-bounds crash three
  panels away. `scripts/smoke_autoload_contract.gd` now gates the `[autoload]`
  block (comment-free, all 11 present, correct load order). Put the rationale in
  a doc, not in the ini.
- **Compile-check everything fast:** `dev/compile_check.gd` loads every script in
  `scripts/` and reports parse failures — a few seconds, versus minutes for the
  full smoke suite. (It used to under-report: a non-null `ResourceLoader.load()`
  counted as success, but Godot returns a non-null GDScript for a script that
  FAILED to compile, so hard parse errors read as "0 failed". It now checks
  `can_instantiate()`.) Run it after any broad edit:
  `./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://dev/compile_check.gd`.
  **New `class_name`s need a project rescan** before they resolve headlessly
  (`--headless --path <project> --editor --quit` rebuilds
  `.godot/global_script_class_cache.cfg`); without it you get
  `Identifier "Foo" not declared in the current scope` from `--script` runs only.
- **Never name a test helper `smoke_*`.** `run_smokes.sh` and `smoke_runner.gd`
  glob `scripts/smoke_*.gd` and *execute* every match. A helper with no
  `extends SceneTree` has no MainLoop, so Godot boots the main scene instead and
  the run hangs forever — that is why the aggregate runner used to never return.
  Helpers are named `*_test_stub.gd` / `*_test_ui_host.gd` instead. Audit with:
  `for f in scripts/smoke_*.gd; do grep -q "^extends SceneTree" "$f" || echo "$f"; done`
- **Use `scripts/run_smokes.sh`, not `smoke_runner.gd`.** The shell runner has
  parallelism (8 jobs), a **per-script timeout** reported separately from FAIL,
  `--shard i/n` for CI, `--include <substr>` filtering, and per-script logs
  under `.smoke-logs/` printed only on failure. Full suite ~285 s instead of
  >600 s. `smoke_runner.gd` still has no timeout, so a soak
  (`smoke_tank_balance.gd`) can stall it — that one is excluded by default and
  runs only with `--slow`.
  Timing-sensitive perf smokes are forced serial: they measure wall-clock, so a
  parallel run starves them into false failures (`smoke_perf_contract` sits at
  ~460 ms against a 490 ms ceiling).
- **`scripts/smoke_baseline.txt` holds 7 known failures.** The suite gates
  *regressions*: a NEW failure exits 1, and so does a baselined smoke that
  starts **passing** — delete its line when you fix it. `--strict` ignores the
  baseline. It is a holding pen, not a place to hide failures.
- **New smoke? Use `TestSupport`** (`scripts/test_support.gd`) instead of
  hand-rolling `_assert`. `TestSupport.Suite` counts checks, so a suite that
  runs *zero* assertions fails rather than exiting 0 having tested nothing.
  `approx`/`in_range`/`has_keys` report expected-vs-actual.
- **Crossing the sim/world seam? Use `SimGate`** (`scripts/sim_gate.gd`) rather
  than a fresh `has_method()` guard. It holds one guarded accessor per
  contracted method and logs a broken contract once per session;
  `smoke_service_contracts.gd` asserts the contract against the real sources,
  which is the compile-time check GDScript cannot give.
- **Smoke test:** `scripts/smoke_tank_shapes.gd` (`extends SceneTree`) validates that
  every tank shape builds. Run it headless, it's not referenced by the game:
  `./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_tank_shapes.gd`.
  **Guardian LLM:** install the in-process extension once with
  `./scripts/install_godot_llama.sh` (like GodotSteam). On **macOS** that script also
  builds matching llama.cpp dylibs from godot_llama's pinned submodule (`cmake` required —
  `brew install cmake`). Verify with
  `./scripts/godot.sh --headless --path shaders-godot/godot-project --script res://scripts/smoke_llama_macos.gd`.
  **Steam/release CI** also runs
  `./scripts/fetch_guardian_model.sh` so the ~250MB GGUF ships in the build — players
  see a one-time “Got it” modal, not a download. Slim/dev builds ask agree/decline first.
  **Agent shells:** Cursor often has no `godot` on PATH — use `./scripts/godot.sh`
  (finds `/Applications/Godot.app` automatically) or set `GODOT_BIN`.
- **`capture_pass_*.png` / `capture_quantized.png` / `capture_raw.png`** are write-only
  outputs of the dev capture scenes and are git-ignored.

## Guardian voice platform matrix (SENTIENCE_EMBEDDED #14)

| Platform | In-process SmolLM2-360M (~250MB Q4_K_M) | Fallback |
|---|---|---|
| Steam desktop (macOS / Windows / Linux) | Bundled in depot (CI `fetch_guardian_model.sh`) | Template voice |
| Slim / dev builds | Opt-in download to `user://guardian/` after consent | Template voice |
| Web export | Disabled (`guardian_llm._platform_supported`) | Template only |
| Android | Disabled (bundle size + thermals) | Template only; Ollama N/A on device |
| Battery saver / low device tier | Load skipped; template-first (#94) | Player opts up in Settings |

Quantization: **Q4_K_M** on SmolLM2-360M-Instruct — tuned for ~35 tok/s on mid CPUs with
`num_predict` 48 (lines) / 80 (away recaps). See `mind_narrator.gd` (#15).

## Build / run

```bash
# Run the game
cd shaders-godot/godot-project && ../../scripts/godot.sh --path . tank_menu.tscn

# Regenerate the pixel-art preview art
python3 tools/render_preview.py

# Tag a release (CI builds mac/win/linux)
git tag v0.1.67 && git push origin v0.1.67
```
