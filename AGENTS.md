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
| `shaders-godot/godot-project/scripts/` | ~70 GDScript files (subsystem breakdown in README). |
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
