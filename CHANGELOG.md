# Changelog

All notable releases of **walstad loom** (GitHub: [SimFish](https://github.com/mhsenkow/SimFish/releases)).

Format: version → highlights. For full diffs, see git tags and GitHub release notes.

## Unreleased

- **Security:** SHA256-verified model/plugin downloads; runtime GGUF hash gate; bounded save reads; keeper prompt hardening; LLM queue cap; rotating save backups; `SaveRepair` sanitizes corrupt saves.
- **Performance:** Potato fidelity preset (256×144, shader tier 2); palette search cap + blob-shadow cap on low tiers.
- **Water:** Caustics damped at surface; depth absorption tints deep caustics.
- **Accessibility:** UI font scale slider (0.8×–1.5×) via `PanelTheme.scaled_size()`.
- **Visual polish:** Caustics tied to sim day phase; meniscus animation; foliage night SSS floor; 6-band iridescence; Chunky preset dither + integer upscale.
- **CI / reference:** Guardian model cache; `data-schemas/validate.py` + `sim-rust` compile job; `.gitattributes`.
- **Docs:** `CONTRIBUTING.md`, `docs/INDEX.md`, `docs/ENGINEERING_CREED.md`, ADRs for `sim-rust/` and `data-schemas/`.

## v0.2.23

- **Cognition:** Active inference (expected free energy bids), GRU-lite world model, predictive theory of mind, inter-fish signal bus, emotional contagion, multi-goal motor blending, cognition LOD tiers, bid-generator registry, cognitive spine DAG.
- **MindState:** Schema migration ladder, sleep consolidation (episodic → semantic), sentience eval harness with per-module ablation.
- **UI:** Panel focus stacking, keeper input vs notification toast layout, HUD click-through fixes.
- Binaries: [GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.23) (macOS / Windows / Linux / Android).

## v0.2.22

Keeper care loop, Guardian advisor, aquascaping craft, pond view. See
[GitHub Releases](https://github.com/mhsenkow/SimFish/releases/tag/v0.2.22).

## Earlier

See [releases](https://github.com/mhsenkow/SimFish/releases) for v0.2.x history.

> **Note:** This file is maintained manually for now. Automated assembly from idea-doc
> checkmarks is tracked in SYSTEMIC_IMPROVEMENTS #61.
