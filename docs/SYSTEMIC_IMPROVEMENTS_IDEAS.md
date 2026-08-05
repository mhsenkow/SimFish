# Systemic Improvements — Security, Surface & Sustainability

*100 ideas. Drafted 2026-06-28. The **complement** to
[ENGINEERING_EXCELLENCE_IDEAS.md](ENGINEERING_EXCELLENCE_IDEAS.md): that volume
owns code architecture, typed contracts, the god-object carve, the test gate, and
mind-subsystem polish. This one owns everything **around** the code — the trust
surface, the GPU pipeline, the non-Godot code, the build/release machine, the docs,
and the player's first hour.*

The throughline is the same as the engineering volume: *make it easier to keep
changing this for years without losing anything.* Every item here either closes a
hole, removes a footgun, makes the project legible to the next contributor (or
future-you), or makes the thing look/run better — grounded in a real file, not a
platitude.

**The honest baseline (measured 2026-06-28).** This is a mature, disciplined
codebase — ~99k LOC of GDScript, 24 shaders, a release pipeline that ships to 3
desktop platforms + Steam, an in-process LLM, 7 autoloads, and a freshly-landed PR
smoke gate. The gaps are not sloppiness; they're the predictable edges of a fast-
moving solo/AI-paired project: **untrusted inputs reach the LLM and the save loader
without a guard, the non-Godot code (Rust sim, Python tooling, data-schemas) has
drifted toward rot, the build relies on fragile shell scripts and uncached 250MB
downloads, the docs are depth-rich but un-navigable, and accessibility is mostly
absent.** None are crises. All are cheap to close now and expensive to close later.

Format mirrors the engineering volume: **Effort** S (≤2h) / M (half-day) / L (full
day+) / **XL** (multi-day), **Impact** S / M / L. Line/symbol pointers are hints
from a 2026-06-28 read — verify before acting.

---

## The five structural levers (read this first)

1. **Guard the two untrusted inputs.** Player keeper-chat text flows into LLM prompts
   (`mind_narrator.gd`), and save files flow into an unbounded JSON parser
   (`tank_saves.gd`). Both are trivially hardened and currently aren't. Section A.
2. **Decide the fate of the non-Godot code.** `sim-rust/` (1.3k LOC, zero tests,
   "not wired in"), `data-schemas/` ("not consumed yet"), and duplicated palette
   tables are *ambiguous* — neither alive nor archived. Ambiguity is the rot. Pick
   live-or-retire for each. Sections F, G, H.
3. **Harden the release machine.** A 250MB model re-downloads every CI run uncached,
   shell scripts broke macOS CI last week, and nothing checksums what it downloads.
   Sections A, I.
4. **Make the docs navigable, not just deep.** 22 idea docs, no index, no
   CONTRIBUTING, no CHANGELOG, no glossary surfaced in-game. Section K.
5. **Give the pipeline a "look better" and an "everyone can play" pass.** Cheap
   shader wins (dither-crawl lock, living water surface, alive scales) and the
   missing accessibility floor (reduced-motion, font scale, remap, captions).
   Sections D, M.

---

## Section A — Security & trust hardening

*The two untrusted inputs (keeper chat, save files) plus the supply chain (model +
plugin downloads). All grounded; most are S-effort.*

- [x] **1. Checksum-verify the Guardian model download.** `scripts/fetch_guardian_model.sh:18`
  `curl`s a 250MB GGUF that `godot_llama` loads as native-backed weights — a swapped
  binary is a code-execution vector. Pin a SHA256, verify after download, delete on
  mismatch. *S · L*
- [x] **2. Checksum-verify the `godot_llama` plugin ZIP.** Same exposure at
  `scripts/install_godot_llama.sh` — the plugin is a GDExtension (native code). Pin +
  verify its hash too. *S · L*
- [x] **3. Verify the bundled model at runtime, not just build.** The build path can be
  hardened (#1) but a tampered `user://guardian/*.gguf` (opt-in download path) is loaded
  unchecked in `guardian_llm.gd` `_resolve_model_path`. Hash-gate before `load_model`. *S · M*
- [x] **4. Escape keeper text before it enters any prompt.** `mind_narrator.gd:614-620`
  interpolates player text into a prompt string; `sanitize_keeper_input` truncates +
  filters profanity but doesn't neutralize injection ("Ignore previous instructions…").
  Strip newlines/quotes and wrap player text in a clearly delimited block. *S · M*
- [x] **5. Bound the save-file read.** `tank_saves.gd` `read_json` calls `get_as_text()`
  with no size limit, then `JSON.parse_string` — a multi-GB or pathological save OOM-crashes
  on load. Add a `get_length()` ceiling (~50MB) and bail with a warning. *S · M*
- [x] **6. Validate-and-repair the save dict, never crash.** After parse, walk the dict
  through a typed validator that clamps/defaults missing or out-of-range fields so a
  corrupt mind dict degrades to a healthy tank instead of a crash. Pairs with
  ENGINEERING #52. *M · M*
- [x] **7. Cap the Guardian LLM queue.** `guardian_llm.gd` `queue_generate` appends with
  no max length; a caller loop (same inspected fish, many frames) grows `_queue`
  unbounded. Add `QUEUE_MAX` and drop-oldest. *S · M*
- [x] **8. Validate the custom GGUF path.** `guardian_llm.gd` `_resolve_model_path` accepts
  any user path; check extension == `gguf` and a sane size ceiling before `load_model`,
  else clear the setting and warn. *S · S*
- [x] **9. Warn on non-localhost plaintext LLM endpoints.** `ai_director.gd` accepts an
  `ai_endpoint`; if it's `http://` and not loopback, prompts travel in cleartext. Warn
  (don't block — localhost http is legitimate). *S · S*
- [x] **10. Sanitize LLM output with word-boundaries + repetition guard.**
  `guardian_llm.gd` `_sanitize_output` does substring profanity match (misses variants,
  mangles compounds) and has no anti-spam. Use word-boundary matching and reject
  `(.)\1{10,}` runs. *S · S*
- [x] **11. Move `STEAM_USERNAME` and any IDs out of tracked scripts.** A developer
  username defaulted in `steam/upload.sh` and `steam/depot_ids.env` leak identity/config;
  require them from env, ship only `*.example`. *S · S*

## Section B — Robustness & graceful failure

*The mind "never blocks the sim" — extend that contract to I/O and degradation.*

- [x] **12. Atomic saves (write-temp-then-rename).** A crash mid-write currently corrupts
  the live save; write to `state.json.tmp`, `fsync`, rename over. (Also ENGINEERING #54.) *S · M*
- [x] **13. Rotating save backups.** `tank_saves.gd` keeps a single `.bak`; a load-then-
  corrupt overwrites the only backup. Keep N rotating backups. *M · M*
- [x] **14. Centralize + bound all HTTP timeouts.** `ai_director.gd` mixes 6s/8s/default
  timeouts; a slow local Ollama can stall a request longer than intended. One const block,
  one helper. *S · S*
- [ ] **15. Never block the main thread on the LLM.** Audit that every LLM call path is
  queued/async (the queue exists) — assert no synchronous `generate` on the sim/render
  thread, even on the keeper-reply fast path. *M · M*
- [x] **16. Degrade-to-template is a tested contract, not a hope.** The template voice is
  the offline fallback; add a smoke that forces "no model" and asserts every voice surface
  still produces text. (Pairs with ENGINEERING #48.) *M · M*
- [x] **17. Pre-flight the install scripts.** `install_godot_llama.sh` discovers a missing
  `cmake` only midway; check `cmake git curl` up front and fail with a clear message. *S · M*
- [x] **18. Document + guard minimum RAM for the embedded LLM.** `run_embedded_llm.sh`
  loads the full GGUF; on low-RAM machines llama-server dies silently. Warn on low free RAM,
  document the floor. *S · S*

## Section C — Rendering performance

*Protect frame budget on integrated GPUs and any future web/mobile export. The post
chain is already lean (one pass) — these are the specific hotspots.*

- [x] **19. A "potato" fidelity preset.** `render_panel.gd` presets exist; add one that
  caps the `palette_quantize` candidate loop, simplifies caustics, and drops resolution —
  the single switch that makes the game playable on Intel HD / web. *M · L*
- [x] **20. Cap the palette search loop on low tiers.** `palette_quantize.gdshader:220-252`
  iterates up to 64 candidates × 2 texture fetches per pixel at full-screen — ~300M frag
  ops/s. Gate to 24–32 on the potato tier. *M · M*
- [x] **21. Reduce the substrate blob-shadow loop on low tiers.** `substrate_caustic.gdshader:92-110`
  loops 32 occluders per top-face fragment; expose a 16-occluder low tier. *S · M*
- [ ] **22. Verify perception/boids use the spatial grid, not O(n²).** The hottest sim loop;
  confirm sense queries go through the grid as fish count climbs. (Also ENGINEERING #25.) *M · M*
- [ ] **23. Per-frame cognition budget + round-robin.** The mind ticks per-fish-per-tick;
  a ms ceiling with id-phased scheduling stops 50 fish spiking a frame. (ENGINEERING #21/#24 —
  flagged here as it's also a *perceived-perf* win.) *M · L*
- [ ] **24. Audit per-frame uniform pushes.** `aquarium_visuals.gd:330-338` syncs aquatic
  uniforms across ~100-200 materials; confirm it stays on the ~10Hz tick, never per-frame,
  as material count grows. *S · M*
- [ ] **25. A CI frame-time regression scene.** Boot N fish for M frames headless, assert
  ms/frame under budget — perf becomes a gate. (Mirrors ENGINEERING #29; listed because the
  *number* should also cover render, not just mind.) *M · L*

## Section D — Visual quality ("look better")

*Cheap, high-payoff shader wins grounded in the current pipeline. Most are 1-3 lines.*

- [x] **26. World-space dither lock to kill dither-crawl.** `palette_quantize.gdshader`
  indexes Bayer/IGN in screen space, so the pattern slides across geometry on camera pans —
  the last big shimmer artifact. Add a toggle to index in world space. *M · L*
- [x] **27. Couple caustics to sim time, not wall-clock.** `caustics.gdshader:57` uses raw
  `TIME`, so caustics keep moving when paused and desync at non-1× time scale. Add
  `day_phase_offset` like `voxel.gdshader`. *S · M*
- [x] **28. Dampen caustic shimmer at the water surface.** Thin plant stems flicker where
  high-freq caustics meet the surface in `water.gdshader`; one `smoothstep` falloff near
  `water_surface_y` fixes it. *S · M*
- [x] **29. Apply depth absorption to caustics.** `water.gdshader:165-167` adds caustics
  *after* the depth color shift, so deep caustics stay warm instead of blue-shifting. Reorder. *S · M*
- [x] **30. Animate the meniscus ring.** `glass.gdshader:194` undulation is static (frozen
  unless the camera moves); add `+ TIME * 0.3` to the phase so the surface breathes. *S · M*
- [ ] **31. Make metallic fauna scales shimmer.** `voxel.gdshader:136-143` metallic spec is
  static; a cheap `sin(TIME…)` pulse makes scales read alive. *S · M*
- [x] **32. Lower the SSS-rim night floor.** `foliage.gdshader:91` floors subsurface rim at
  0.25 even at true night; drop the floor so plants stop glowing in the dark. *S · S*
- [x] **33. Smooth iridescence banding.** `voxel.gdshader:128` quantizes iridescence to 4
  hue bands (visible stepping); 6 bands is smoother and still palette-friendly. *S · S*
- [ ] **34. Soften screen-space reflections on glass.** `glass.gdshader:71` samples a sharp
  mirror reflection; a low-mip sample reads as real glass. *M · M*
- [x] **35. Make the Chunky preset deliver its promise.** `render_panel.gd` comments "extra
  dither" for Chunky but doesn't raise `dither_strength` or force integer upscale — wire
  both so the preset looks intentional. *S · M*
- [x] **36. Expose `blue_noise_amount` in the UI.** The shader supports it
  (`palette_quantize.gdshader`) but it's not surfaced; a slider lets players tune grid-vs-
  smooth dither taste. *S · S*
- [ ] **37. Route god-rays through the shared palette tint.** `god_ray.gdshader:103-104`
  hardcodes warmth instead of using `palette_tint.gdshaderinc`; unify so global warmth is
  consistent. *S · S*

## Section E — Shader maintainability

*The shaders are the visual identity — keep them legible.*

- [x] **38. Delete dead shaders.** `voxel_caustic.gdshader` (sine caustics, superseded) and
  `glass_panel.gdshader` (no GDScript references found) appear dead — confirm and remove. *S · S*
  *(2026-06-28: removed `voxel_caustic.gdshader`; `glass_panel.gdshader` is live in `main.gd`.)*
- [ ] **39. Name the shader magic numbers.** Caustic sharpness `1.6`, meniscus freq
  `(2.4, 2.1)`, ripple maps — hoist to named `const` at file top. *S · S*
- [ ] **40. One-line every shader's main().** Several (`voxel`, `foliage` vertex sway,
  flow-zone gain) carry undocumented formulas; a comment header per pass. *S · S*
- [ ] **41. Consistent uniform prefixes.** Mix of prefixed (`aquatic_`, `palette_`) and bare
  (`color_vibrancy`) uniforms makes the inspector hard to scan; prefix by system. *M · S*
- [ ] **42. Document the palette single-source contract.** Note where CPU color-boost
  (`voxel_mat.gd`) and shader hue-bank classification must stay in sync so they can't
  silently diverge. *S · M*

## Section F — The Rust sim: decide live-or-retire

*`sim-rust/` is 1.3k LOC, zero `#[test]`, "not wired into the game," with chemistry
that has drifted from the GDScript truth. Ambiguity is the cost — resolve it.*

- [x] **43. Make the live-or-retire call explicitly.** Three honest options: **archive**
  (move to `archived/`, stop maintaining), **revive** (CI tests + reconcile constants +
  plan a gdext binding), or **keep-as-reference** (add a disclaimer + a compile check). Pick
  one in a one-paragraph ADR. *S · M*
- [x] **44. If kept: commit `Cargo.lock`.** `.gitignore` excludes it, so even the reference
  build is non-reproducible. *S · S*
- [x] **45. If kept: a CI `cargo test` + `cargo run --example cycle`.** Today nothing
  validates it; a single job stops silent rot. *S · M*
- [x] **46. Resolve `vivarium_serve`.** The 597-line HTTP telemetry server isn't built,
  referenced, or documented as used — archive or wire it, don't leave it orphaned. *S · S*

## Section G — Python tooling & the single-source palette

- [ ] **47. One palette source of truth.** The `planted_48` hex table is duplicated in
  `tools/render_preview.py` and `shaders-godot/make_palette.py`; extract to a shared
  `data/palettes.json` both load. Silent divergence today. *M · M*
- [ ] **48. Pin Python deps.** `steam/store/` uses Pillow/Playwright/requests with no
  `requirements.txt` — unreproducible across machines. Add pinned files per tool. *S · M*
- [ ] **49. A Python smoke in CI.** Run `make_palette.py` + `render_preview.py` and assert a
  stable output hash so palette/preview breakage is caught. *M · M*
- [x] **50. Document the asset-gen setup.** No instructions for the `.venv` Steam store
  pipeline; a few lines in CONTRIBUTING (see #69). *S · S*
- [ ] **51. Lint/format the Python.** A `ruff`/`black` pass + CI check on the 9 tracked `.py`
  files for consistency with the GDScript discipline. *S · S*

## Section H — Data-schemas: live contract or dead spec

*`data-schemas/` documents a moddable JSON format the game doesn't consume, with a
`validate.py` CI never runs. Same ambiguity problem as the Rust sim.*

- [x] **52. Decide: activate or label-as-reference.** Either wire a GDScript loader +
  CI-enforced validation, or rename to `_reference-schemas/` and mark non-normative so
  nobody trusts a dead spec. *M · M*
- [x] **53. If activated: run `validate.py` in CI.** It already exists; one job makes the
  examples a checked contract. *S · M*
- [ ] **54. Reconcile schema examples with `species_library.gd`.** Example species
  (mudsifter, riverblade…) may not match the in-game roster; assert or document the mapping. *M · M*

## Section I — Build, release & CI hardening

*The git log shows real pain here (macOS CI, version lookup). Make it boring.*

- [x] **55. Cache the Guardian model in CI.** The 250MB GGUF re-downloads every release run;
  an `actions/cache` keyed on model version saves minutes and removes a HuggingFace-outage
  dependency. *S · M*
- [ ] **56. Pin + checksum Godot, godot_llama, GodotSteam, model.** Last week's break was a
  version lookup; pin every external version and verify hashes (ties to #1/#2). *S · M*
  *(2026-06-28: model + godot_llama ZIP + Godot version pinned in `scripts/supply_chain/manifest.env`; GodotSteam checksum still open.)*
- [ ] **57. Replace version `case` ladders with a data file.** `install_godot_llama.sh`
  maps versions in brittle `case` statements; a `versions.txt` lookup scales without editing
  control flow. *S · S*
- [ ] **58. Smoke-launch the *exported* build headless.** CI tests source smokes but never
  boots the actual export; boot it, tick one tank, assert no errors before publishing. *M · M*
- [ ] **59. Per-platform build-size budget.** Track export size (the ~93MB GodotSteam
  weight, the 250MB model); fail CI on regression. *S · M*
- [ ] **60. Strip disabled native paths from web/Android builds.** Those targets disable the
  LLM; ensure they don't ship the dead `godot_llama` path. *M · M*
- [ ] **61. Auto-assembled release notes / CHANGELOG.** Build the changelog from idea-doc
  checkmarks + commits so release notes aren't hand-written prose. *S · M*
- [ ] **62. `set -euo pipefail` + shellcheck on every script.** The `scripts/*.sh` are the
  fragile layer; lint them in CI and fail on unset vars. *S · M*
- [ ] **63. A pre-commit hook (format + lint + quick smoke).** Extend the AGENTS.md culture
  into git so CI rarely fails. (Mirrors ENGINEERING #90.) *S · M*

## Section J — Repo hygiene

- [x] **64. Stop tracking the Steam store `.venv/`.** `steam/store/.venv/` (Python 3.14
  site-packages, tens of MB) is committed; add to `.gitignore` and untrack. *S · M*
- [ ] **65. Decide `.uid` policy and apply it once.** Godot `*.gd.uid` files are tracked and
  cause merge noise; pick track-all or ignore-all and make it consistent. *S · S*
- [x] **66. Add a `.gitattributes`.** Enforce LF on text (`.sh/.gd/.py/.rs/.vdf/.json`) and
  mark binaries, so Windows contributors can't introduce CRLF churn. *S · S*
- [ ] **67. Remove the committed root `.DS_Store`.** Ignored by pattern but one is tracked
  from before the rule; delete it. *S · S*
- [ ] **68. De-dupe the idea docs + reconcile shipped items.** Some idea docs list features
  already shipped (e.g., colorblind palettes are live in `render_panel.gd`); check items off
  and ensure no doc lives in two places. (Mirrors ENGINEERING #85.) *S · S*

## Section K — Documentation & knowledge

*Depth-rich, navigation-poor. The fastest multipliers for "easier to keep changing."*

- [x] **69. `CONTRIBUTING.md`.** Setup (Godot 4.6.3, cmake on macOS, Python), the smoke-test
  command, the strangler-fig carve rule, commit/PR conventions. The missing front door. *M · M*
- [x] **70. `docs/INDEX.md` mapping the 22 idea docs.** Category → file → shipped% so the
  backlog is navigable; today there's no map. (Pairs with the idea-doc-series index,
  ENGINEERING #93.) *S · M*
- [x] **71. `CHANGELOG.md`.** Version → shipped features, generated where possible (#61).
  Users + future-you currently reconstruct this from git. *S · M*
- [ ] **72. `ARCHITECTURE_MIND.md`.** Map the ~30 mind modules — phase, I/O, data flow; the
  design is the asset. (ENGINEERING #40, restated as the single highest-value missing doc.) *M · M*
- [ ] **73. Per-subsystem reference doc.** One file with deep dives: fauna intelligence,
  flora/food-web, chemistry/cycling, render pipeline, UI/panels — what it does, how it's
  wired, where config lives. *L · L*
- [ ] **74. A surfaced glossary.** Bid/ignition/workspace/qualia/felt-now plus game terms
  (Guardian, bond tier, stocking preset, Walstad, mouthbrooder) — define once, link from
  code and surface in-game (#80). *S · M*
- [ ] **75. ADRs for the big calls.** Offline-first LLM, GWT mind, non-Meta model policy,
  save versioning, Rust-sim fate (#43), data-schema fate (#52). Capture the *why*. *M · M*
- [ ] **76. A module-ownership / boundary map.** Who owns each subsystem and its public
  surface — the social contract that stops god-objects regrowing. *S · M*
- [ ] **77. A 30-minute onboarding path.** "Clone → run → change one thing → verify" end to
  end for a new contributor or future-you. *M · M*
- [x] **78. A "definition of done" + one-page engineering creed.** Grounded · never-blocks ·
  offline-degrades · tested · ablatable · documented — committed, not remembered. (ENGINEERING
  #99/#100, anchored here as a doc artifact.) *S · M*

## Section L — Onboarding & legibility

*New players stock a tank, then stall — unsure what to watch. Close that gap.*

- [ ] **79. A post-walkthrough "now watch for…" frame.** `walkthrough.gd` ends at stocking
  with no "here's the cycle, the pearling, the tells" handoff; add a closing card set. *M · L*
- [ ] **80. Surface the `TANK_TELLS` table in-game.** `onboarding_legibility.gd:26-35` maps
  gulping→O₂, hiding→stress, gill-flush→NH₃ but it's hardcoded, never shown; render it in
  the help overlay. *M · M*
- [ ] **81. Explain the Fresh-cycle ammonia spike up front.** The intentional spike reads as
  a bug to newcomers; a one-time modal ("this is how real tanks cycle") before creating a
  Fresh tank. *S · M*
- [ ] **82. Narrate the nitrogen cycle as it happens.** NH₃→NO₂→NO₃ is invisible until a chip
  tap (`main.gd` water popup); surface lightweight progress beats during week 1. *M · M*
- [ ] **83. A canonical, complete controls legend.** The cheat sheet (`main.gd`
  `_toggle_cheat_sheet`) omits real bindings (T=timelapse, 1/2/3=timescale); drive it from
  one `CONTROLS` dict so it can't drift. *S · M*
- [ ] **84. Mobile-aware scenario picker.** `scenario_picker.gd` `_build_card` is modal-first
  with no touch-target sizing; add a narrow-screen layout. *M · M*
- [ ] **85. A non-destructive settings preview.** `settings_panel.gd` Apply reloads the scene
  and can invalidate saves with no warning; add a "this will reset/affect your tank" notice
  and a revert. *M · M*

## Section M — Accessibility

*Today: colorblind palettes + partial captions exist; almost everything else is
missing. This is both an ethics floor and a market expander.*

- [x] **86. Reduced-motion mode.** Zero matches for `reduced_motion` today; gate fish jitter,
  plant sway, UI tweens, and auto-orbit behind a setting (honor the OS preference where
  Godot exposes it). *M · L*
- [x] **87. UI font scaling.** Fonts are hardcoded via `PanelTheme.SIZE_*`; multiply by a
  user scale (0.8×–1.5×) for low-vision players. *M · M*
- [ ] **88. Input remapping.** Controls are hardcoded across `main.gd` + panels; a rebind
  panel via Godot `InputMap` persisted to `user://bindings.cfg`. *L · M*
  — **Partial 2026-08-04:** DualSense / Steam Deck couch controls ship shared
  InputMap actions (`gamepad_bindings.gd` + `GamepadInput` autoload), stick
  camera, center reticle, menu focus, aquascape pad tools, Options controller
  menu, and aquascape escape (○ clear/exit, △ toggle, Esc, Options → Exit).
  Remap UI still open.
- [ ] **89. Complete the caption coverage.** Caption infra exists in `onboarding_runtime.gd`
  but sound cues (filter column, snail crawl, splashes) and key eco-events aren't all
  captioned; audit + fill. *M · M*
- [ ] **90. Screen-reader names on UI.** HUD chips/panels lack `accessible_name`/
  `accessible_description`; a chip should read "Fish: 12, 8 adult, 4 juvenile," not "control." *M · M*
- [x] **91. A dedicated Accessibility settings section.** Today a11y options are scattered
  (colorblind under Render); group reduced-motion/font/remap/captions in one discoverable
  place. *S · M*
- [ ] **92. High-contrast / large-target UI option.** For the chip-dense HUD, an option that
  enlarges hit targets and boosts contrast. *M · M*
- [ ] **93. Publish an accessibility statement.** List what's supported (colorblind palettes,
  captions, remap, reduced-motion) on the landing page and in-game so players can find it. *S · S*

## Section N — Settings & UX polish

- [x] **94. Legend the frame-budget sparkline.** `render_panel.gd` draws a sparkline with no
  scale/legend; players can't tell good from bad. *S · S*
- [ ] **95. Surface chemistry (CO₂/light) out of the Advanced tab.** They're critical to
  plant growth but buried with fauna-behavior sliders; promote them. *S · M*
- [ ] **96. Tooltips that teach, not just label.** Many sliders affect the sim in non-obvious
  ways; a one-line "what this does to your tank" per control. *M · M*
- [ ] **97. Consistent keyboard-shortcut hints in panel titles.** "(O)", "(R)", "(F11)" live
  in tooltips only; show them in panel chrome for discoverability. *S · S*

## Section O — Web landing & marketing surface

- [ ] **98. Auto-update the landing version pill.** `docs/index.html` hardcodes `v0.2.22`; a
  small Actions job (or client fetch of the GitHub Releases API) keeps it current. *S · S*
- [ ] **99. Add SEO + structured data.** Missing `keywords`/`author` meta and a JSON-LD
  `SoftwareApplication`/`VideoGame` schema with per-platform download URLs for richer social
  cards + search. *S · M*
- [ ] **100. Audit the landing for mobile + no-CSS resilience.** The scenario-card grid can
  collapse awkwardly on narrow screens, and text-only cards have no fallback structure;
  test + harden. *S · S*

---

## If you only do five

In order — the spine of "more secure, more sustainable, easier to change":

1. **#1 + #5 — checksum the model download and bound the save reader.** The two
   real holes (code-exec vector, OOM-on-load), both S-effort. Close them this week.
2. **#43 + #52 — decide the fate of `sim-rust/` and `data-schemas/`.** Stop carrying
   ambiguous code. One ADR each; archive or commit to keeping alive in CI.
3. **#55 + #56 — cache + pin + checksum the release supply chain.** The build broke
   last week; make it boring and reproducible.
4. **#69 + #70 + #71 — CONTRIBUTING, doc INDEX, CHANGELOG.** Three small files that
   turn a depth-rich but un-navigable doc set into an actual front door.
5. **#26 + #86 — world-space dither lock and reduced-motion.** One "look better" win
   the eye notices immediately, one "everyone can play" floor the project currently lacks.

> **Sequencing:** these run *behind* the engineering volume's CI gate (#41 there).
> Land the security guards and the live-or-retire decisions first (they're cheap and
> stop bleeding), then the supply-chain hardening, then the docs that make every future
> change cheaper, then the polish. Security + sustainability are the foundation; the
> "look better / everyone can play" wins sit on top and are what players actually feel.

> **The throughline:** none of this competes with the sentience work or the engineering
> carve — it protects them. A guarded save loader keeps the soul from corrupting; a
> reproducible build keeps the mind shippable; navigable docs keep the next contributor
> from re-deriving the architecture; accessibility lets more people meet the fish.
> *Best-coded, most-alive, and most-trustworthy are the same project.*
