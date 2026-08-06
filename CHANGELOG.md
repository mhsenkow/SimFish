# Changelog

All notable releases of **walstad loom** (GitHub: [SimFish](https://github.com/mhsenkow/SimFish/releases)).

Format: version → highlights. For full diffs, see git tags and GitHub release notes.

## Unreleased

- **Docs:** `CONTRIBUTING.md`, `docs/INDEX.md`, `docs/ENGINEERING_CREED.md`.

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
