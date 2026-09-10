# Changelog

All notable releases of **walstad loom** (GitHub: [SimFish](https://github.com/mhsenkow/SimFish/releases)).

Format: version → highlights. For full diffs, see git tags and GitHub release notes.

## Unreleased

## v0.2.31

- **Plant Systems 50:** foliage caustics, canopy blob shadows, spatial gusts, desync leaf sway, golden-hour rim, senescence batching, flowering tip stability.
- **Fish alive:** body-first fear/habit kits (`fish_alive.gd`) — readable motion before LLM voice.
- **Comms inbox:** toast policy, quiet mute, death window, kind filters (`comms_inbox.gd`).
- **Spawn settle:** new fish ease into position instead of hard teleports.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.31) (macOS / Windows / Linux / Android).

## v0.2.30

- **Frame budget follows the fps cap.** `PerfGovernor` measured every frame
  against a hardcoded 16.6 ms. Mobile ships `fps_cap = 30`, so a device hitting
  its target exactly read as a 100% budget overrun: `budget_pressure` pinned at
  1.0, MindLOD demoted every fish to its lowest cognition tier, and the adaptive
  scaler ratcheted shader cost to maximum — permanently, on healthy hardware.
  The budget now tracks `Engine.max_fps`, and the adaptive resolution target is
  clamped to the cap so it cannot chase a frame rate the cap forbids.
- **Safe-area insets (`scripts/safe_area.gd`).** Only `mobile_hud.gd` knew about
  notches; the stats bar, menu cluster, footer, right rail and side panels all
  laid out against the raw viewport and slid under the cutout / home indicator.
  One shared module now feeds every edge, and the footer re-lays on rotation.
- **Physically-sized touch targets.** Rail and HUD buttons were 48 render pixels
  on a 1536-wide viewport — about 27 pt once stretched onto a phone, well under
  the 44 pt floor. `PanelTheme.min_touch_px()` converts a ~7 mm finger into
  viewport pixels for the actual screen; the rail widens to match.
- **First-launch render budget** seeded from the detected `device_tier` instead
  of booting every handheld at the desktop default and stuttering down.
- **Generative coats:** four new heritable flank motifs — rosette, chevron,
  countershaded ramp, and a hash-scattered constellation speckle that gives each
  individual its own star-map. Reachable from breeding, the reef/store rolls and
  the creature creator.
- **Per-individual asymmetry:** pectorals, eye catchlight and an occasional
  healed caudal nick deviate per fish, deterministically, so a shoal stops
  reading as one mesh repeated.
- **Panel motion:** side panels fade and settle instead of popping, with
  `PanelTheme.is_panel_open()` so a second Escape can't re-open a closing panel.
  Reduced motion collapses it to instant.
- **Hot-path allocations:** `PerfGovernor.record_frame()` no longer allocates or
  sorts every frame; ~90 per-frame `"/root/TankConfig"` path resolutions in
  `main.gd`, `fish.gd`, `sim_driver.gd` and `accessibility_runtime.gd` are
  memoised.
- **Steam client icon:** added `steam/store/assets/icons/clienticon.ico` (16–256 px,
  multi-resolution). The exported Windows `.exe` and macOS `.app` already carried
  the game icon, but Linux ELF binaries carry none and Steamworks' *Client Icon*
  field rejects PNG — so the only icon Steam had was a placeholder. The asset
  generator now emits the `.ico`, the uploader globs `.ico` as well as `.png`,
  and `STEAMWORKS.md` documents the (manual, publish-gated) upload step.
- **GDScript warnings cleared:** 43 `const X = preload(...)` declarations that
  shadowed a global `class_name` (`TankFidelityRuntime`, `PerfGovernor`,
  `MindContext`, …) removed — the global already binds the identifier, so the
  const only produced SHADOWED_GLOBAL_IDENTIFIER. Also fixed the remaining
  shadowed locals (`show` vs `Node3D.show()`, `size` vs `Control.size`, a
  parameter shadowing `SafeArea.insets()`), unused parameters/locals, and made
  the deliberate integer divisions explicit.
- **Generative plants:** real phyllotaxis (golden-angle spiral, distichous,
  decussate, whorled) replaces the two-plane `% 2` leaf alternation, with a
  per-individual phase so a bed of one species no longer lines up leaf-for-leaf
  and each stem leans its own way. Leaves now record the conditions they grew
  in — shade leaves are larger and held flatter, the biggest leaves sit
  mid-stem, and each blade twists part-way toward the lamp. Arrangement is
  heritable, re-derives on a leaf-form mutation, and has a rare architecture
  sport. Offspring also get their own asymmetry seed (they used to inherit the
  parent's verbatim and grow as clones).
- **Epiphytes grow sideways:** rhizomes creep one segment along their host
  every third growth node instead of stacking leaves in place, and
  scatter-spawned epiphytes finally attach to driftwood/rock — that placement
  rule existed but only ran on the library-spawn path, so moss and java fern
  spawned on open sand.
- **Snail shells dissolve in soft water.** KH and pH were simulated and unread;
  now they erode shells apex-first — chalky, then pitted, then holed — at a rate
  set by the heritable `shell_thickness` (derived per shell shape, so trochus
  outlasts ramshorn). Damage is near one-way: good water lets a snail
  re-deposit, but the scar caps the recovery. Eroded snails will not breed, and
  a story-log line tells the player why their snails went white.
- **The carbonate loop closes.** Shells now *draw* carbonate
  (`WaterChemistry.draw_carbonate`) in proportion to size, so a heavy colony
  softens its own tank, the crash erodes those shells, and the population
  self-limits instead of growing without a brake.
- **Snails aggregate on food** — with nothing to eat they follow a neighbour
  that is mid-rasp, which piles them onto a wafer the way real snails do.
- **Trackpad zoom rebuilt.** Wheel/trackpad/pinch now feed one log-zoom budget
  drained at a bounded rate. The old code switched between three different step
  formulas inside a single flick (12% → 4.7% → 0.85% per event), which is why it
  felt jumpy and hit the clamp instantly. Zoom is also cursor-anchored now.
- **Water actually behaves like water.** Added per-channel Beer–Lambert
  extinction to every in-tank surface (`apply_water_column` in
  `palette_tint.gdshaderinc`): light loses red first, so depth and distance
  desaturate toward the water's own colour. That single change gives the tank
  atmospheric perspective — near fish read warm and close, the back wall
  recedes — and it makes planted tanks read *green* instead of tan, because the
  red the plants were reflecting is exactly what the water eats. Tannins invert
  the curve to amber (blackwater); turbidity adds broadband haze so a murky tank
  reads milky rather than dark. Exposed as **Render → Water depth colour**.
- **Trackpad two-finger scroll works.** Godot's macOS backend routes a precise
  scrolling device to `InputEventPanGesture`, not to wheel buttons, and nothing
  consumed it — which is why two fingers up/down did nothing on a MacBook while
  the same motion on a mouse zoomed. Now: vertical = zoom, horizontal = orbit
  yaw, Shift + two fingers = pan.
- **Shift + drag pans.** It was already wired as a pan modifier but could never
  fire: Shift + press startled the fish and set `_suppress_drag_until_release`,
  killing the drag before it started. The startle now fires on *release* and
  only if the pointer stayed inside the deadzone, so Shift + drag pans and
  Shift + click still startles.
- **Fixed the smoke runner hanging.** Four *helper* files were named `smoke_*`
  (`smoke_aquascape_stub`, `smoke_aquascape_ui_host`, `smoke_night_watch_stub`,
  `smoke_sim_stub`), so `run_smokes.sh` / `smoke_runner.gd` executed them as
  smokes; with no `SceneTree` MainLoop each booted the whole game and never
  exited. Renamed to `*_test_stub` / `*_test_ui_host`, taking the suite from
  five hangs to one (the `tank_balance` soak).
- **New smokes:** `smoke_frame_budget`, `smoke_mobile_chrome`,
  `smoke_panel_motion`, `smoke_fauna_patterns`, `smoke_plant_architecture`,
  `smoke_snail_shell`, `smoke_water_column`.
- **Docs:** `CONTRIBUTING.md`, `docs/INDEX.md`, `docs/ENGINEERING_CREED.md`.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.30) (macOS / Windows / Linux / Android).

## v0.2.29

- **Real-tank fidelity:** Stratified substrate at the glass, valli surface-lie, green dust + graze tracks, turbidity, floater mat, gooseneck LED, airline, counter mirror; reference scenarios `snail_bar` / `valli_jungle` / `counter_nano`.
- **Lived-in tank:** Translucent pond shells, hair on old leaves, empty-shell trough, backlight jungle preset, scum line, equipment-in-frame toggle.
- **HUD:** Clear gutters so feed/speed and creature card/rail stop overlapping; shorter feed chips.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.29) (macOS / Windows / Linux / Android).

## v0.2.28

- **macOS Metal:** Force MSAA Off, skip screen-texture water/glass (black-slab fix), safe MultiMesh uploads, skip GPU boids.
- **Look polish:** Soft waterline, warmer room lamp, softer god rays, dusk dither ease, display FXAA/deband, **Mac Safe** render preset.
- **Icons:** Wire `res://icon.png` into macOS/Windows/web/Android export presets (no more Godot robot in Steam).
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.28) (macOS / Windows / Linux / Android).

## v0.2.26

- **Scenario balance:** Iwagumi gets a discreet sponge filter so dawn O2 holds; pico reef uses new `nano_reef` preset (3 fish, not 16).
- **Established tanks:** Founding plants mature to 70–100% height on cold start — real biofilter biomass from frame one.
- **Ambient audio:** Richer layered bed synthesis and music-context sync.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.26) (macOS / Windows / Linux / Android).

## v0.2.25

- **macOS:** Disable volumetric fog on Metal (fence-timeout fix); shader-based light beams.
- **Spawn:** Body-radius-aware fish placement; chemistry visuals flush on load.
- **Keeper UI:** Feed dock status, time-pause stack, governor-driven shader tier steps.
- **Atmosphere:** Filter-jet flow lanes, foliage shimmer, room lighting sync.
- **Docs:** README status table + new gameplay screenshots.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.25) (macOS / Windows / Linux / Android).

## v0.2.24

- **Performance:** `mind_kernel` unified tick, perf governor, GPU boids, batched fauna/waste, potato shader tier.
- **Soul / spark:** Three-pass soul mind, fish spark behavior + expression, ΔG felt-self curves.
- **Visual:** Eight biome palettes with per-band shader globals.
- **macOS:** Developer ID signed + notarized release pipeline in CI.
- See [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.24).

## v0.2.23

- **Cognition:** Active inference, GRU-lite world model, inter-fish signal bus, emotional contagion, sentience eval harness.
- **UI:** Panel focus stacking, keeper input vs notification toast layout.
- See [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.23).

## v0.2.22

Keeper care loop, Guardian advisor, aquascaping craft, pond view. See
[GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.22).

## Earlier

See [releases](https://github.com/mhsenkow/SimFish/releases) for v0.2.x history.

> **Note:** This file is maintained manually for now. Automated assembly from idea-doc
> checkmarks is tracked in SYSTEMIC_IMPROVEMENTS #61.
