# Broad Directions — 20 Improvement Tracks

*Drafted 2026-09-10 from a full-repo deep dive. Unlike the numbered campaign docs
(PLANT_SYSTEMS_50, REFINEMENT_100, …), this is not a feature backlog — it is a
**map of the 20 broad directions** the project could push in, each grounded in a
measurement taken from the tree at `d25da42`.*

Format matches the other idea docs: **Effort** S (≤2h) / M (half-day) / L (full
day+) / **XL** (multi-day), **Impact** S / M / L.

---

## The honest baseline (measured 2026-09-10, commit `d25da42`)

**This is a strong codebase, and the list below is deliberately not "clean up the
code."** The things that are usually wrong here are right:

| Metric | Value | Read |
|---|---|---|
| GDScript | 136,537 LOC / 390 scripts | Large but coherent |
| Typed function returns | 3,830 / 3,943 | **Excellent** |
| Typed vs untyped vars | 9,250 / 43 | **Excellent** |
| Smoke scripts / assertions | 148 / 1,164 | Real coverage, real assertions |
| Sim loop | fixed timestep, accumulator clamp, spatial query grid, throttled decay | Well-engineered |
| Perf governor | rolling p95, allocation-free `record_frame`, budget follows `Engine.max_fps` | Well-engineered |

The gaps are **at the seams, at the platform edge, and in the feedback loop** —
not in the craft of individual files.

### Drift against the 2026-06-28 engineering audit

`ENGINEERING_EXCELLENCE_IDEAS.md` independently identified the god-objects and the
stringly-typed boundary ten weeks ago. Both have **grown since**:

| Measure | 2026-06-28 | 2026-09-10 | Δ |
|---|---|---|---|
| LOC | 98,113 | 136,537 | +39% |
| Scripts | 174 | 390 | +124% |
| `has_method()` duck-checks | 916 | 1,077 | +18% |
| Four god-objects, combined LOC | ~33,000 | ~38,172 | +16% |

The diagnosis was correct and the trend is the wrong way. That is the core
argument of directions #7, #8, and #20.

**After the 2026-09-10 session (#1-#8, #10, #11, #17-#19):** 416 scripts / 160
smokes. Sixteen new modules, twelve new smoke suites, sharded CI.

| Measure | Session start | Now |
|---|---|---|
| `has_method()` guards | 1,077 | 1,021 |
| `has_method("daylight")` | 77 | 23 |
| Duplicate `_assert` definitions | 89 | 3 |
| Smoke suite wall-clock | >600 s, did not complete | 285 s, exit 0 |
| Four god-objects, combined | 38,240 | 38,383 |
| Panels referencing mind state | **0** | 1 (`mind_panel.gd`) |
| TankConfig knobs classified | 0 of 284 | **285 of 285** |
| `world.gd` has a `class_name` | no | **yes** |

The god-objects are essentially unmoved — #7 got one slice of many, and that
is the honest state of it. Two latent gate failures were found and fixed:
`dev/compile_check.gd` passed on scripts that did not compile, and
`smoke_perf_contract.gd` could never pass.

---

## Application log

Running record of work done against these directions. **Append-only** — newest
entry last. One row per work session; `Direction` cites the numbered track below.

| Date | Direction | Status | What changed | Evidence |
|---|---|---|---|---|
| 2026-09-10 | — | ✅ | Doc created from repo deep dive; baseline metrics captured at `d25da42` | this file |
| 2026-09-10 | 1 | 🟡 | De-purchased every internal identifier (`fish_store*`→`adopt*`, `MODAL_STORE`→`MODAL_ADOPT`, dropped dead `spawn_purchased_fish` alias); extracted `controller_menu.gd`; added headless `smoke_controller_coverage.gd` + CI step; wrote canonical AI Content Survey text. **Open:** Windows+pad retest, partner-side Features/Survey edits | `steam/REVIEW_FEEDBACK.md` resolution log; smoke passes 13 destinations |
| 2026-09-10 | 2 | 🟡 | Added `steam_stats.gd` (14-achievement contract + pure `evaluate()`), `steam_achievements.gd` (offline-safe unlock mirror, `getAchievement()` reconcile, rich presence), wired via `steam_service.gd`→`attach_sim`. Documented Auto-Cloud roots + presence token. **Open:** partner-site achievement/icon/Cloud/presence config; no Workshop | `smoke_steam_stats.gd` passes; `steam/STEAMWORKS.md` §Achievements |
| 2026-09-10 | 3 | 🟡 | Added `milestones.gd` — progression as a *view* of the #2 achievement contract (no second definition list), with grouped/ordered rows, per-milestone progress, `next_goal()` closest-unearned nudge, banked-stays-banked semantics. `milestone_earned` signal → existing `"milestone"` inbox kind, so progression works with no Steam. **Open:** no dedicated milestones panel yet (rows/labels are ready for one) | `smoke_milestones.gd` passes: 14 milestones, 5 groups |
| 2026-09-10 | 4 | ✅ | Added `save_migrations.gd`: every save now stamped (`save_version`), a newer-format save is **refused** instead of half-loaded (was silently dropping the newer build's fields, then writing the loss back on autosave), nonsense stamps refused, legacy unstamped saves still open unchanged. Dead `TankSaves.STATE_VERSION` now aliases the one source of truth; new `_show_incompatible_save_prompt` is non-destructive | `smoke_save_versioning.gd` passes; `smoke_save_roundtrip` + `smoke_mind_state_roundtrip` still green |
| 2026-09-10 | 5 | ✅ | Added `app_log.gd` autoload — the application log: bounded ring (400) + rotated on-disk sessions capped at 2 MiB, level counts, session header (build/OS/GPU/Godot), live tank context off the 1 Hz stats signal, `export_report()`, and a **Copy diagnostics** button in Settings → Advanced. Also added the missing `application/config/version` (`0.2.31`) — a log with no build id is near-useless. Save refusals from #4 now route through it | `smoke_app_log.gd` passes; 401 scripts compile; 6 existing smokes green |
| 2026-09-10 | 6 | 🟡 | Added `safe_json.gd` — bounded-before-parsed, typed-or-nothing, logged-but-non-fatal — generalising the posture `TankSaves.read_json`/`AIDirector` already had. Applied to the four readers that had none: blueprint library, global species library, achievement mirror, both Spotify HTTP bodies (network input was fully unbounded). **Open:** `guardian_llm` custom-GGUF path and `cognitive_schema` LLM output not yet routed through it | `smoke_safe_json.gd` passes; 403 scripts compile |
| 2026-09-10 | 7 | 🟡 | **First slice of an XL direction.** Extracted `pond_mode.gd` from main.gd: stroke gating, school centroid, startle falloff/duration/curiosity, camera framing, vignette — as pure typed statics, deliberately *not* the `host.get()`/`has_method()` shape `SaveManager`/`UiPanelManager` used, since that trades #7 for #8. main.gd 11,454→11,437 lines. **The win is reachability, not line count:** none of this logic could be tested headlessly before. **Open:** 38k lines still in four files; needs many more slices | `smoke_pond_mode.gd` (42 assertions) passes; 405 scripts compile; 20/20 smoke batch green |
| 2026-09-10 | 11 | ✅ | Added `test_support.gd` (Suite + drop-in statics, `approx`/`in_range`/`has_keys` that report expected-vs-actual, and **a zero-assertion suite now fails** — the old copy-pasted helper could not catch a skipped body). Migrated 86 files / 1145 call sites off duplicate `_assert`; unified 68 report blocks to one machine-parseable format. **Also fixed `dev/compile_check.gd`, which was silently unreliable:** it treated non-null `ResourceLoader.load()` as success, but Godot returns a non-null GDScript for a script that FAILED to compile — so a hard parse error reported "0 failed", exit 0. Now uses `can_instantiate()`; verified 1/407 flagged with a deliberate break, 0/406 clean | `smoke_test_support.gd` 30 checks pass; net −273 lines |
| 2026-09-10 | 10 | ✅ | Rewrote `scripts/run_smokes.sh`: parallel (8 jobs), **per-script timeout** via `perl alarm` (macOS has no `timeout`) reported separately from FAIL, `--shard i/n`, per-script logs printed only on failure, `--include` filter. Timing-sensitive perf smokes forced serial (they measure wall-clock; parallel starves them — `smoke_perf_contract` sits at ~460ms against a 490ms ceiling). CI now shards 4× with a real compile gate. **Suite: >600s serial → 284s, and it now completes.** | full run exit 0: 143 passed, 0 new, 7 known, 0 timed out |
| 2026-09-10 | 10 | 🟡 | **Discovered 7 pre-existing smoke failures nobody was seeing** — verified failing on pristine `d25da42`, so not introduced by this work. Parked in new `scripts/smoke_baseline.txt` (each with a reason) so the suite gates *regressions* again: a NEW failure exits 1, and so does a baselined smoke that starts passing, to drain the pen. Also fixed a real bug in `smoke_perf_contract.gd` — `quit(0)` does not return in Godot, so it fell through to `quit(1)` and **could never pass**. Swept for that shape: exactly 1 case. **Open:** the 7 need triage (several look renderer- or nondeterminism-dependent) | `scripts/smoke_baseline.txt`; pristine-worktree comparison |
| 2026-09-10 | 8 | 🟡 | Added `class_name World` to `world.gd` — **it had none**, which is the root cause: with no `World` type to annotate against, every one of 99 referencing scripts had to duck-type. Added `sim_gate.gd`: one guarded accessor per contract method (caller passes its own fallback, since they differ meaningfully — 1.0 "assume day" vs 0.5 "assume neutral"), with once-per-session violation logging so a rename is *loud*. Collapsed **56 of 79** `has_method("daylight")` guards; the other 23 gate conditional work rather than a fallback value, so rewriting them would change behaviour. **Open:** ~1,000 guards remain across other seams | `smoke_service_contracts.gd` 41 checks pass; 409 scripts compile; 145 passed / 0 new failures |
| 2026-09-10 | 8 | ✅ | **The gate is proven, not decorative.** Renamed `SimDriver.daylight()` → `daylight_RENAMED()` and confirmed the suite goes red with a precise message, where previously 77 call sites would have silently fallen back and the tank would just behave as permanently noon. This is the compile-time check GDScript cannot give, moved to CI | `SMOKE smoke_service_contracts FAIL ... "declared in SimGate.CONTRACT but does not exist"` |
| 2026-09-10 | 17 | ✅ | Added `mind_legible.gd` — the missing **translation** layer (pure, so the panel, fish journal, guardian diary and tooltips share one phrasing) — plus `mind_panel.gd`, rail button, `J` shortcut and pad-menu entry. Deliberately not a debug readout: the smoke asserts **no raw number ever reaches player-facing text**, sleep overrides need (a sleeping fish never reads as foraging), and faint drives go unmentioned. "Inner workings" (workspace ignition, prediction error, self-model, meta-states) is collapsed by default. Verified by rendering the real panel, not just assertions | `smoke_mind_legible.gd` 58 checks pass; rendered output reviewed; 412 scripts compile |
| 2026-09-10 | 18 | ✅ | Added `config_curation.gd`. **Reframed the direction:** the 284 count was misleading because three things share one bag — 27 persisted *state* (`camera_yaw`, `tutorial_seen`), 5 internal save bookkeeping, 19 expert/debug, **72 music/synth**, leaving ~161 real player knobs. Classified all 285 by tier + domain, with Simple/Advanced/Expert modes (simple = 20 knobs) and a mode selector in Settings. **The gate is what makes it stick:** every TankConfig property must be triaged or the build goes red — proven by adding `settings_mode` untriaged and watching it fail by name | `smoke_config_curation.gd` 1136 checks pass; nesting + no-state-leak asserted |
| 2026-09-10 | 19 | 🟡 | Added `tank_share.gd`: `WLTK1:` share codes (matching the existing `WLBP2:`/`WLST1:` convention) carrying seed + 10 look/stocking keys, and postcards — photos now get a **burned-in** provenance strip and a seed-bearing filename plus a `.txt` sidecar with the code. Burned pixels not PNG metadata, because every chat app strips metadata. Decode is allowlisted, so a stranger's code **cannot** set `ai_endpoint`, `guardian_custom_gguf_path` or debug flags. Wired to Settings + pad menu. **Open:** no "open a shared code" import flow yet | `smoke_tank_share.gd` 78 checks pass incl. hostile-key rejection |
| 2026-09-10 | 19 | ❌ | **Correction to the original #19 claim: timelapse already exists.** `T` toggles frame capture to `captures/timelapse_<ts>/` (`_toggle_timelapse`, `TIMELAPSE_INTERVAL`, `_save_timelapse_frame`). I reported it as missing; that was wrong. The genuine gaps were provenance and seed sharing, both now closed | `main.gd:2219`, `main.gd:2469` |
| 2026-09-10 | — | ✅ | **Cleared all 13 GDScript warnings** from the editor Errors panel (4 mine from #2/#5, 9 pre-existing): `load`/`wrap`/`name`/`ready`/`visible` shadowing built-ins and base-class members, two redundant `const FishAlive = preload()` that shadowed the real `class_name FishAlive`, and an intentional integer division now annotated. `_fear_peek_dir` was reported unused but is read cross-file by `fish_alive.gd` — deleting it would have broken fear-peek, so it carries a documented `@warning_ignore` instead | 0 `SHADOWED_*`/`INTEGER_DIVISION`/`UNUSED_*` across 417 scripts |
| 2026-09-10 | — | ✅ | **Flowers read as attached, and stopped jittering at range.** Rooted bloom was **3.2× the width of the stem holding it** (0.353 vs 0.112) — hence "detached blob"; now 1.24×, with body and a cupped silhouette so it reads as a bloom rather than a flat bar. Floater bloom was a 0.12 cube on a 0.165-wide leaf (**73% of the leaf**, taller than the leaf, hovering 0.075 clear of it) — now a leaf-relative petal plate + centre pip seated into the surface. Lily pads left alone: their bloom is ~13% of a 0.95 pad radius, already proportionate | rendered and judged at both close range and the real 512×288 target, not just measured |
| 2026-09-10 | — | ✅ | **Root cause of "at distance they move too much": sway had no distance attenuation.** At a 512×288 target with pixel snapping, a plant at range covers a few pixels, so full world-space sway made those pixels jump instead of reading as motion. Added `sway_fade_start/end/floor` to `foliage.gdshader` + `foliage_mm.gdshader`, damping sway, flutter **and** gust push past 6 units. New `smoke_foliage_sway.gd` is the **first gate on shader edits** — previously a renamed uniform failed nothing and rendered silently wrong | `smoke_foliage_sway.gd` 58 checks pass |
| 2026-09-10 | 10 | 🟡 | Baselined an 8th pre-existing failure, `smoke_tank_shapes.gd` ("triangle: floater cap 27 < 31"), verified failing on pristine `d25da42`. It read as passing earlier in the same session, then failed deterministically — the assertion's `min_cap` floors at 8 if `WorldFloaterManager.shape_capacity_multiplier` resolves small, making the suite class-cache sensitive. Both the assertion and that sensitivity need fixing | `scripts/smoke_baseline.txt` |
| 2026-09-11 | 9 | 🟡 | **Reversed the delete-it call on `sim-rust/` after you pushed back — and you were right.** First, my size worry was wrong: `target/` is gitignored, so it is 10 tracked files / ~56 KB, not 219 MB. Second, CI was running `cargo test --no-run` against a crate with **zero `#[test]` functions**, plus an example piped to `/dev/null` — it proved compilation and asserted nothing. Writing real tests found three defects, two of which meant the crate **did not reproduce the nitrogen cycle its own docs describe**: nitrobacter's growth break-even (0.047 mg/L) sat just above the tank's own nitrite equilibrium (0.038–0.046) so the colony could never establish; and diffusion was **45× under-integrated** at the example's own `dt=60` because the stability clamp discarded the rest of the timestep instead of sub-stepping. Also killed a linear 11-element scan in the innermost loop. Now 10 tests, `clippy -D warnings` and `fmt --check` in CI. [ADR 003](adr/003-sim-rust-as-oracle.md) supersedes 001 | `cargo test` 10/10; cycle now runs NH3 0.97→0.03, NO2 spike→0.006, NO3 0.49→1.56 |
| 2026-09-11 | 9 / 13 | ✅ | **Oracle coverage expanded and made two-sided.** New [docs/CHEMISTRY_ORACLE.md](CHEMISTRY_ORACLE.md) names 9 shared invariants (N1-N4 nitrogen, O1-O2 oxygen, P1-P2 pH/KH buffering, D1 denitrification); the same IDs are now asserted on **both** sides — 16 Rust tests and `smoke_chemistry_oracle.gd` (12 checks). Deliberately qualitative: the models are not numerically comparable (well-mixed vs 2D grid), so only curve *shape* is held jointly. Writing the GDScript half found the shipped chemistry has the **same dt-sensitivity the Rust diffusion had** — no sub-stepping, so a large `dt` saturates every rate in one tick and collapses the curve to steady state | Rust 16/16 + `clippy -D warnings`; `smoke_chemistry_oracle` 12/12 |
| 2026-09-11 | 14 | 🟡 | **Localization infrastructure + 40% of the UI wrapped.** Added `localization.gd` autoload, `locale` config (the #18 gate caught it untriaged, by name), a language selector, `dev/i18n_extract.gd`, and a CSV catalogue. Strategy is **English-as-key**, so the retrofit is mechanical and untranslated locales fall back to readable English. Wrapped **210 strings across 15 files**; `smoke_localization.gd` holds a **coverage ratchet** — 305 unwrapped literals may fall, never rise. **The centrepiece is a runtime pseudolocale** (`⟦Ådöpt fïšh···⟧`, +30% padding) which makes two invisible bug classes visible: unwrapped strings stay plain English on screen, and clipped layout cannot survive a real translation. **Open:** 305 literals, no real locale yet | `smoke_localization.gd` 38 checks; 150 passed / 0 new failures |
| 2026-09-11 | 14 | ✅ | **Caught a shipping bug by running it, not reading it:** Godot's `TranslationServer` matches locales by **prefix**, so the obvious `en_XA` pseudolocale counted as a match for `en` — every wrapped string rendered as `⟦…⟧` **for real English players**. Moved to `qps` (the reserved pseudo-locale range) and added a regression test asserting the pseudolocale shares no prefix with any shipping locale, end-to-end through a live TranslationServer | `smoke_localization.gd` leak test |
| 2026-09-11 | 18 | ✅ | Fixed a bug in my own #18/#14 work: `settings_mode` and `locale` were both reachable from Settings and called `request_save_to_disk()`, but **neither was in the read/write functions** — so both silently reset on every restart. Now persisted, and asserted | `smoke_localization.gd` persistence checks |
| 2026-09-11 | tank realism | ✅ | **Tank shapes and sizes now derive from real aquaria.** New `tank_spec.gd` holds a 16-vessel catalogue in true inches (5g nano → 120 gal, plus 60P, 30C cube, column, hex, bowl) with computed volume, dimensions and stocking guidance. Measured against reality, the old presets were wrong: **every box was exactly 1 : 0.50 deep** whatever tank it claimed to be (a real 75 is 0.375), and **neither "cube" was a cube** (1 : 1 : 0.56 — slabs with cube labels). `VESSEL_PRESETS` is now generated from the catalogue, so proportions are right by construction. Settings shows "75 gallon · 48 × 18 × 21 in · holds a community of 36+ small fish" instead of "half_w 8.0" | `smoke_tank_spec.gd` 392 checks; rendered all 16 silhouettes side by side |
| 2026-09-11 | tank realism | ✅ | **Scale had to become perceptual, not linear.** A linear 1 unit = 3 in put a 30 cm cube at 3.9 units while a fish is 1.8 — a fish half the width of its tank — and three presets fell below the size sliders' own minimums. That is the cost of drawing fish large for a 512×288 target. Units now follow `K · inches^0.7525`, solved from two anchors (5g nano → 7 u, 75 gal → its familiar 16 u): ordering survives, every vessel stays ≥3 fish-lengths across, and **volumes stay honest because they come from real inches, not from units** | `smoke_tank_spec.gd` monotonicity + round-trip + fits-the-sliders |
| 2026-09-11 | 14 | ✅ | **Corrected my own coverage figure.** The unwrapped-string counter flagged any `.text = "` line, including `"\n".join(...)` separators — so it reported 305 unwrapped. With a prose check (2+ consecutive letters, the same rule the wrapper used) the true figure is **105**, i.e. coverage was ~67%, not the ~40% I reported. Budget tightened to 105. The ratchet caught my own tank-spec work adding a string, then caught its own stale budget | `smoke_localization.gd` 38 checks |
| 2026-09-11 | UI patterns | ✅ | **Fixed a bug I shipped: the Mind panel could be opened and not closed.** It had no Close control, no `close_*` function and no entry in the Escape cascade — the only panel with none of them. Added the house footer pattern, `close_mind_panel()`, and an Escape entry. Then wrote `smoke_panel_contract.gd` so it cannot recur: every panel must offer a Close control, bespoke panels must have a close function reachable from Escape, and every rail panel must be pad-reachable. Verified by removing the footer again and watching it fail with the exact diagnosis | `smoke_panel_contract.gd` 30 checks |
| 2026-09-11 | tank realism | ✅ | **The tank was levitating.** The "desk" was a 1.2-thick slab with nothing beneath it and no floor. Added `_build_tank_stand`: a cabinet with an inset body, recessed toe-kick, two doors and handles, plus a room floor. **The stand is a constant ~30 in tall regardless of tank size** — a stand is furniture for a human, and holding it fixed while the tank varies is exactly what makes tank size read; scale it with the tank and every tank looks identical. **Open:** the room's materials are deliberately flattened so they never out-compete the tank, which also flattens the cabinet against the floor — separation is structural now but the tone still wants a deliberate palette pass | rendered the real post-quantize player view, not the raw SubViewport |
| 2026-09-11 | tank realism | ✅ | **Vessel picker replaces the dropdown.** `vessel_picker.gd` + `vessel_silhouette.gd`: 16 tanks as cards grouped by size band, each with a silhouette **drawn to a shared scale** (glass, water line, substrate wedge, and a one-fish reference bar), real dimensions, real volume and stocking. The shared scale is the point — aspect alone shows shape, a shared scale shows *size*, which a list of names never could. Reachable from Settings ("Browse tanks…"), the pad menu, and Escape-dismissable per the panel contract | rendered and iterated on the silhouette scale until legible |
| 2026-09-11 | tank realism | ✅ | **Room value ladder.** The room read as one flat beige even after the stand landed. The cause was not identical colours but *close* ones: the palette-quantize pass snaps near values into the same entry, so anything under one palette step apart renders identically. Surfaces are now spaced deliberately — desk 0.16, wall 0.44, cabinet 0.52, toe-kick 0.74, floor 0.80 — with the floor also cooled toward blue, since separating by hue as well as value survives the palette squeeze better | named constants `ROOM_VALUE_*`; 425 scripts compile |
| 2026-09-11 | UI patterns | ✅ | Panel contract extended to the picker; `smoke_panel_contract.gd` now covers Close control, Escape reachability, no-stacking on open, and pad reachability across every panel | 30 checks |
| 2026-09-11 | fauna motion | ✅ | **Shrimp now crawl instead of sliding tilted.** Two bugs: `look_at` used the full 3D heading, so gravity's pull pitched the whole body nose-down (the tilting in the screenshot); and legs were welded voxels, so a walking shrimp slid with its legs frozen. Legs now hang off pivots in an alternating tripod, and the cycle is **distance-driven** — it stops when the animal stops and quickens when it hurries, which is what makes the legs look like what moves it. Four distinct gaits by body plan: carideans scurry (9 steps/unit, low bob), lobsters lumber (3.2, heavy bob), mantids stalk, and **crabs walk sideways** | `smoke_shrimp_gait.gd` 49 checks |
| 2026-09-11 | messaging | ✅ | **One toast component replaces four.** main.gd held **1,289 lines** of notification/toast/popup code across ~25 functions, with four separate hand-built presenters (notification, feed, guardian, photo) each constructing its own `PanelContainer`/`StyleBoxFlat`, and ten bespoke styleboxes. New `toast.gd` + `toast_stack.gd` add what none of them had: **severity variants** (a critical low-O₂ warning used to render in the same blue as "photo saved"), click-to-dismiss, **pause-on-hover** (the old dwell ran while you were reading), a dwell that **scales with reading length** instead of a fixed 4.2 s, and an optional action button | `smoke_toast.gd` 39 checks; rendered all four variants |
| 2026-09-11 | messaging | ✅ | **Fixed a stacking bug and a sizing bug, both found by looking.** Stacking assumed a hardcoded 74 px per toast, so any wrapping body overlapped its neighbour — the stack now measures real heights. And toasts rendered ~700 px tall because the autowrap body measures its minimum height *before* it has a width; pinning the width was necessary but not sufficient, since at `_ready` the layout has not run. Only waiting a frame fixes it. This was masked because `relayout` re-hugged toasts two frames later — but a **trimmed** toast is skipped while dismissing, so it stayed stretched the whole way out | `smoke_toast.gd` pins both: no-overlap, and hugged-while-dismissing |
| 2026-09-11 | messaging | ✅ | Guardian streaming recap no longer walks the node tree for "the Label at child index 1" — a lookup that worked only because every toast happened to have a title above its body, and would have silently found the wrong node for a titleless toast or one with an action button. `Toast.body_label()` and `Toast.hold()` replace it, and streamed text now holds the toast open instead of letting it fade mid-sentence | 428 scripts compile |
| 2026-09-11 | messaging / #7 | ✅ | **Notification centre carved out of main.gd.** ~407 lines / 18 functions became `notifications_panel.gd`, split so main keeps the STORE (push, cap, dedup, badge — where messages arrive) and the panel owns PRESENTATION plus its own filter/sort. Filtering is pure, so it is directly testable. Rows now carry the same severity stripe as the toasts, so a message reads the same urgency wherever it is seen, and the empty state distinguishes "nothing has happened" from "your filter hides it" | `smoke_notifications_panel.gd` 26 checks |
| 2026-09-11 | messaging | ✅ | **Found a bug the extraction would have created.** `_mark_visible_notifications_read` re-implemented the panel's filtering against main's own copy of the filter state — once the panel owned that state, main's copy went stale and "mark visible read" would have marked the wrong rows. It now asks the panel what it is actually showing. Eight dead fields and four orphaned constants removed with it | asserted in the smoke: main must not keep its own filter state |
| 2026-09-11 | messaging | ✅ | **Four chip popups share one shell.** History, story, water and alert each rebuilt an identical container by hand (PanelContainer, MOUSE_FILTER_STOP, z_index 220, stylebox, VBox, header). `chip_popup.gd` owns the shell and hands each caller its `body`, since only the bodies genuinely differ (a wrapped label, a sparkline, a tabbed list). Also removes two more `header.get_child(0) as Label` index-walks — the same fragile pattern found in the toast | chip/popup code 586 → 529 lines |
| 2026-09-11 | UI patterns | ✅ | Panel contract extended to the notifications panel and vessel picker. The gate immediately flagged the notifications panel as stacking — a **false positive**: it avoids stacking by delegating to `UiPanelManager.open_side()`, which closes every other side panel. Widened the heuristic rather than changing correct code | `smoke_panel_contract.gd` 40 checks |
| 2026-09-11 | 10 | ✅ | Baseline drained by one: `smoke_tank_shapes` now passes — the tank-spec geometry fixed the triangle floater-cap assertion it was failing. The runner flagged it as "baselined but now passing" and I removed it, which is the ratchet working in the direction it was built for | 7 known failures, down from 8 |
| 2026-09-11 | 5, 14 | ✅ | **Two autoloads were silently disabled and nothing noticed.** A comment I put above `AppLog` and `Localization` in `project.godot` survived a Godot re-save, but the ConfigFile writer strips whitespace and folds a comment onto the following line — what shipped was `#AppLogfirst:...AppLog="*res://scripts/app_log.gd"`, one commented-out line, twice. The game booted with no logger and no translations. Nothing failed to compile; the first symptom was an out-of-bounds crash three panels away in `settings_panel._sync_locale_option()`, because the Language dropdown was filled from a service resolving to null. Restored both, added `smoke_autoload_contract.gd` (block is comment-free, all 11 declared, singleton-prefixed, paths exist, AppLog first / Localization second) | Scene probe: 11/11 autoloads mount, `locales=2 current=en`. Gate verified by reintroducing the exact bug — fails 3 ways |
| 2026-09-11 | messaging | ✅ | Fixed 4× `Error calling deferred method: 'Control::queue_sort': Method not found` per toast. `toast_stack.present()` had a leftover `layer.call_deferred("call_deferred", "queue_sort")` — doubly wrong: `queue_sort` is a `Container` method and the layer is a plain `Control`, and `_deferred_relayout` was already doing the two-frame settle that actually places the toast | toast smokes green; no deferred-call errors |
| 2026-09-11 | 8 | ✅ | Cleared the 7 remaining shipped-code warnings. Six `SHADOWED_GLOBAL_IDENTIFIER` on `seed` (shadows the built-in `seed()`) renamed in `tank_share.gd` ×3, `main.gd`, `procedural_plant_species.gd`, `creature_creator.gd` — the `"seed"` **dictionary keys** left alone, since those are share-code wire format. Dropped the redundant `const ProceduralPlantSpecies = preload(...)` in `creature_creator.gd`, which shadowed the global `class_name` (same pattern as the earlier `FishAlive` fix) | Editor rescan: 0 warnings. 433 scripts compile |
| 2026-09-11 | realism | ✅ | **Snails at the waterline.** Reference photos of real Walstad tanks all show the same thing: a dense band of snails at the surface, and several hanging upside-down from the underside of the film. The sim had glass, substrate, hardscape, plant-trunk and lily-pad attachment but **no surface film and no water-level awareness at all**. Added it as one more attachment surface (`wall_normal = DOWN`, which the existing tangent/bitangent basis already handles), plus a waterline band that makes a snail crawl *along* the surface rather than turning back down. Pulmonates really do glide inverted on surface tension, so this is behaviour, not decoration | `smoke_snail_surface.gd` 48 checks; `film_dwell` confirmed round-tripping in a real 12-snail save |
| 2026-09-11 | realism | ✅ | **Fish rendered as three rubber stamps.** `_maturity_scale()` switched on the maturity enum and returned one of four fixed numbers, so every fry in the tank was *exactly* 0.35 and every adult *exactly* 1.0. Real breeding tanks read as a continuum. Replaced with `FishGrowth.scale_for(age/max_age_s)` — piecewise-linear, much smaller newborn (0.22), full size held across the bulk of adult life so the average fish is unchanged | Measured on a real 29-fish population: **2 distinct rendered sizes → 22**, 1.5× spread. `smoke_fish_growth.gd` 220 checks incl. a no-visible-step assertion |
| 2026-09-11 | tooling | ⚠️ | `dev/capture.tscn` writes to a **real save slot** — it builds a live World, can call `clear_active_state()`, and autosaved a new 1.1 MB "Beginner Sandbox" slot during a render attempt. It also renders a bare tank unless a populated slot loads, so it cannot verify fauna. Documented in AGENTS.md; artifact moved aside, user's slots restored from backup | AGENTS.md gotcha |
| 2026-09-11 | templates | ✅ | **All 16 base templates enlarged and given their own camera.** Volumes up 1.2×–3.1× (median ~2×), sized against the real Settings slider limits rather than arbitrary numbers, each keeping its character — iwagumi and dutch stay long-and-shallow at the 24-unit width max, blackwater stays a tall narrow column, counter nano stays the smallest. Every template now sets its own `camera_yaw/pitch/radius/target_y/fov`; previously only 3 of 16 had any camera at all and the other 13 shared one default | `smoke_scenario_templates.gd` 827 checks incl. all-cameras-distinct |
| 2026-09-11 | templates | ✅ | **Two templates had dead vessel ids.** Reef used `"reef_cube"` and Counter Nano `"nano_cube"`; neither exists in `VESSEL_PRESETS` (the real ids are `reef_cube_20`/`cube_30c`). `apply_vessel_preset()` sets the name, finds no preset and returns having applied **no dimensions**, so both tanks silently inherited whatever size the previous tank had — nothing logged, nothing crashed. Every template now carries explicit dimensions plus `vessel_preset: "custom"`, so nothing stale can carry over, and all 16 declare `cycle_start_mode: "established"` so a new player lands in a living tank | Gate verified by reinstating `"reef_cube"` — fails |
| 2026-09-11 | lighting | ✅ | **Lighting could change a light's colour, never its shape.** The machinery for a hard raking cone existed — `SpotLight3D` with angle/attenuation, `_add_god_ray_beam` for the shaft — but every number was a literal inside `world.gd`'s fixture builder, so no preset could reach it. Added `lighting_rig.gd` + 9 preset-drivable properties: `room_darkness`, cone angle/attenuation, head offset x/z, tilt/yaw, shadow casting, beam strength. All default to an INHERIT sentinel so existing tanks are untouched until a preset opts in | `smoke_lighting_rig.gd` 280 checks |
| 2026-09-11 | lighting | ✅ | **The shaft did not follow its light.** `_add_god_ray_beam` built a vertical cylinder under the spot regardless of aim, so a raked beam lit one wall while its visible shaft went straight down somewhere else. Beam now derives length along the aim direction (a 45° rake travels 1.41× further before it lands), orients the mesh onto that direction, and caps a near-horizontal beam instead of dividing toward infinity | Gate verified by reverting to `return drop` — fails |
| 2026-09-11 | lighting | ✅ | **Lighting presets were diffs, not looks.** `apply_lighting_preset` only set the keys a preset declared, so picking a dark spot preset and then "Window daylight" left `room_darkness` at 0.92 and rendered daylight as a black room. Added `LIGHTING_RIG_DEFAULTS`, reset before apply. Deliberately excludes `moonlight_enabled`, whose declared default is `true` — listing it would silently kill moonlight everywhere | Gate verified by removing the reset loop — fails 3 ways |
| 2026-09-11 | lighting | ✅ | New presets `clip_spot_night` (off-centre raking clip lamp, black room) and `pendant_pool` (centred hard pool — proves the rig is a system, not one hand-placed light), new `night_window` environment, new `night_lamp` tank preset, and a 17th template **Night Lamp** built from a reference photo | `smoke_scenario_templates.gd` 878 checks; `smoke_config_curation.gd` 1177 |
| 2026-09-11 | lighting | ✅ | **`room_darkness` missed five lights and the room stayed bright.** Side-by-side against the reference, the rendered room wall was the *brightest thing in frame* — the opposite of the intent. Cause: the room carries its own rig (`RoomSideFill`, `TankWallBounce`, `TankSpill`, `TankDeskRim`, `TankWindowGlow`) built in `world_room_builder.gd` and driven off the daylight curve (`0.28 + dl*0.32` etc.); darkness reached the sun and the ambient term but none of them. Split into `room_fill()` (ambient — crushed to zero) and `tank_spill()` (light thrown *by* the tank — trimmed to 45%, so a lit tank still glows on the desk instead of looking pasted into a void) | `smoke_lighting_rig.gd` 320 checks |
| 2026-09-11 | testing | ✅ | **The pure smoke passed while the feature did not work.** `room_darkness` was implemented, unit-tested and green, and simply was not *applied* to five lights — a pure test cannot see a missing call site. Added a source-inspection wiring gate: every `.light_energy =` in the room tick must route through a `LightingRig` darkness helper, and `world.gd` must be seen darkening the sun, the ambient term, and orienting the shaft. Verified by un-wiring one light — fails naming the exact line | 333 checks total |
| 2026-09-11 | templates | ✅ | Night Lamp reshaped to a **hex corner tank** (10×10×11) to match the reference's corner pentagon, camera dropped to look into the front vertex and tilted up into the beam, darkness deepened 0.92→0.97 and the bulb pushed to 1.15 with bloom threshold 0.44 so the head blows out | `smoke_scenario_templates.gd` 879 |
| 2026-09-11 | realism | ✅ | **"Established" grew the filter but not the plants.** Vallisneria's spec allows a mature height of 14–22 voxels and it was planted at `randi_range(2, 5)`, so a cycled tank opened with a mature biofilter over a lawn of 3-voxel stubs and the player had to wait out real growth time. `PlantEstablish` now spawns established plants at 72% of their *own* mature height ±26% jitter, so a valli stand reaches the surface on day one and is ragged rather than a hedge. Fresh/cycling tanks untouched — there the small starts are the point | `smoke_growth_and_morphs.gd` 304 checks; can only ever add height, never exceeds mature |
| 2026-09-11 | realism | ✅ | **A guppy colony rendered thirty identical charcoal fish.** `mixed_morphs` existed but rolled from one hardcoded *reef* palette baked into fish.gd and unreachable from a genome. Extracted to `FishMorphs` with a named-palette lookup; added a 10-entry fancy-guppy spread read off the reference photos (tangerine, half-black, snakeskin, drab olive female, blue, cream albino — the drab ones matter, they're what make the bright ones read as bright). Guppy morphs are **colour-only**: rerolling the reef path's body plan would turn half the colony into disc-shaped tangs | Reef behaviour byte-identical incl. the clownfish-bar special case |
| 2026-09-11 | determinism | ⚠️→✅ | The plant-height jitter first drew from `world._rng` inside `_spawn_plant`, which **shifted the whole RNG stream** and moved every plant placed afterwards — `smoke_scenario_layouts` caught it as `polyp_lab: carpet spread too wide`. Silently reshuffling every preset's hand-tuned composition to vary some heights is a bad trade, so the roll is hashed from spawn position instead. Gated by source inspection | Layout smoke green again |
| 2026-09-11 | templates | ✅ | Night Lamp stocking → guppy-dominant (16 guppy, 12 shrimp, cardinal tetras dropped): scarlet-and-neon-blue tetras read as magenta under a warm amber beam and fight the light | `smoke_scenario_templates.gd` green |
| 2026-09-11 | lighting | ✅ | **The spot lit the back wall, not the tank — the aim model was wrong.** `spot_tilt_deg`/`spot_yaw_deg` were *added* to whatever rake a fixture already had baked in; the gooseneck carries (−78, −18) tuned for its original fixed position. Moving the head to a corner and adding angles pointed the beam outward: computed landing point **(6.08, −6.72)** on a tank whose glass ends at 5.0, exiting the back wall after dropping only 4.5 of 8.8 units. A rotation offset cannot know where the lamp ended up. Replaced with `spot_aim_x`/`spot_aim_z` — point the lamp at a spot on the substrate, `look_rotation_deg` does the rest. Self-correcting for any head position, tank size or shape; tilt/yaw remain as the fallback | Now lands **(−1.10, 1.50)**, inside, raking 35° off vertical. `smoke_lighting_rig.gd` 415 checks incl. landing-inside from 15 head positions |
| 2026-09-11 | lighting | ✅ | God-ray shaft now reads the light's **real basis** (`spot_forward`) instead of rebuilding direction from euler. A look-at rotation can carry a non-zero Z that a tilt/yaw reconstruction silently drops, which would leave the visible beam pointing somewhere the light is not | `beam_span` takes a direction vector |
| 2026-09-11 | plants | ✅ | **Flowers thrashed because the bloom was assigned, not followed.** `_stabilize_flower_against_lean()` set the flower's whole transform from the live stem tip every frame, instantly. That anchor is the sum of stem lean, canopy layover, gust tilt, circumnutation, brush bend and a voxel re-lay on every growth step — each individually gentle, but a rigid bloom snapped onto their sum reproduces all of it at full amplitude with zero lag. Added `FlowerMotion`: exponential damped follow (220 ms position, 140 ms rotation), frame-rate independent, snapping only on creation | 514 checks incl. convergence-without-overshoot over 200 steps, and a wiring gate that the tick path passes `dt` |
| 2026-09-11 | lighting | ✅ | **The beam came from a phantom lamp.** `_add_god_ray_beam` computed the lamp height as `TANK_HEIGHT + height_above + spot.position.y`, which assumes every fixture root sits at `TANK_HEIGHT + height_above` — true for the pendant and bar, **false for the gooseneck**, whose clamp sits on the rim at `TANK_HEIGHT + 0.05`. With the default `light_height` of 1.4 the shaft was built from a lamp **1.35 units above the visible one**. Now reads the real fixture (`parent.position.y + spot.position.y`) | Gate verified by reinstating the old form — fails 2 ways |
| 2026-09-11 | lighting | ✅ | **Plants could not respond to the lamp at all — the whole pipeline is `render_mode unshaded`.** That is deliberate (the palette quantizer needs direct control of the colour reaching it), but it means nothing in the tank reacts to a light: a plant renders identically whether the beam points at it or at the far wall, and `spot_shadows = true` changed *nothing*. Added `shaders/beam_cone.gdshaderinc` — an analytic cone driven by four registered `global uniform`s (`iaq_beam_origin/dir/cone/tint`), pushed each frame from the live spot, consumed by `foliage.gdshader` + `foliage_mm.gdshader`. Leaves brighten inside the cone and fall toward an ambient floor outside, so the beam lands **on** the plants instead of only crossing the water in front of them | `smoke_lighting_rig.gd` 443 checks; gate verified by removing the shader call — fails |
| 2026-09-11 | testing | ⚠️ | `dev/shader_check.gd` reported **"21 shaders, 0 failed"** while printing `SHADER ERROR: Redefinition of 'albedo'` — the same false-negative class as the old `compile_check` bug (a non-null load counted as success). Not yet fixed; noted for triage | — |
| 2026-09-11 | lighting | ✅ | **The shaft rendered upside down.** `god_ray.gdshader` reads its gradient off `UV.y`, and `UV.y = 0` is the cylinder's **top** — the lamp end, where the shaft is brightest and sealed. Orienting the mesh mapped local **+Y** onto the aim direction, which put that bright sealed end on the gravel and faded it upward: the beam read as a shaft rising out of the bottom of the tank. Local **−Y** now runs along the beam so `UV.y = 0` stays at the lamp; extracted as `LightingRig.beam_basis()` | Bright end verified at the lamp head (3.08, 10.97, −3.15), faded end on the substrate. Gate verified by re-inverting — fails 9 ways |
| 2026-09-12 | lighting | ✅ | **The line on the hex tank was the beam drawing outside the glass.** Built `dev/footprint_probe.gd` to walk the live scene and report meshes escaping the footprint polygon — first pass tested AABB corners and flagged `/World/Water`, a **false positive** (the AABB of a correct hex prism *is* a rectangle); re-run against real `mesh.get_faces()` vertices named the culprit unambiguously: `CylinderMesh v=480` under `LightFixture`, reaching **1.18 units past the back wall**. Nothing ever constrained the shaft to the tank, so a wide or off-aim cone drew straight through the angled hex faces. Fixed in the shader: the footprint is passed as up to 8 inward half-planes and the shaft fades at the glass | `smoke_lighting_rig.gd` 480 checks, incl. winding-independence and the AABB-corner case |
| 2026-09-12 | UX | ✅ | **The tank light is now directly manipulable.** Hover it (emissive lifts), double-click to grab, drag to move the lamp across its mount plane, right-drag or shift-drag to move where it *aims* on the substrate, Escape to let go. Both halves are draggable because neither alone is expressive — a lamp that always points at the same spot is a gimbal, and an aim without a lamp position cannot say "clipped to the back-right corner". Dragging moves the live nodes and rebuilds only the shaft rather than the whole fixture; the placement is persisted on release | `smoke_light_handle.gd` 99 checks incl. handle/rig position agreement and aim-stays-in-bounds from 24 drag directions |
| 2026-09-12 | UX | ✅ | **Light manipulation redesigned — the first cut was bad and it was a model problem, not a polish one.** Double-click to enter a mode, drag, Escape to leave: four steps to nudge a lamp, nothing on screen suggesting any of it existed, an undiscoverable shift/right modifier for aiming, and no way to undo a bad drag. Replaced with **no modes**: two handles fade in as the cursor approaches (`reveal()`, 130→260px), both are directly draggable on press, right-click or Escape cancels the drag and restores the snapshot, release commits — and an unmoved drag writes no save. Handles are drawn as a crisp 2D overlay (`light_gizmo.gd`) rather than 3D meshes, because voxel geometry would be palette-quantized along with the tank and read as scenery instead of UI; the overlay is `MOUSE_FILTER_IGNORE` so it can never eat a click | `smoke_light_handle.gd` 155 checks incl. reveal monotonicity, overlapping-handle tie-break, and a gate on the overlay swallowing input — verified by flipping it to STOP |
| 2026-09-12 | render | ✅ | **The registered palette defaults were a "make everything grey" value.** `iaq_palette_*` defaulted to `Vector4(0,0,0,0)`, and the shader computes `global_pal.y * sat_mult` / `global_pal.w * val_mult` — so an unpushed palette collapses saturation AND value to zero. Only `main.gd` ever pushes real values, so any frame before that, and every dev/tool scene, rendered a desaturated dark world. Defaults are now neutral `(0,1,0,1)` so a missed push degrades to normal | Found while making the inspection harness trustworthy |
| 2026-09-12 | render | ✅ | **The stray line was `WaterlineTick`** — a `9.20 × 0.04` bar sized from `TANK_HALF_W` (the bounding box) and placed at `z = half_d`. On a hex the front pane is only 5 wide, so it jutted **2.1 units past the glass each side**. The code predicted this failure mode and guarded cylinder and sphere but not hex. Fixed the class rather than the case: sized from the footprint's actual front pane via `TankFootprint.front_edge_of()`. Tick 9.20 → 4.20; stray pixels 715 → 0 | `smoke_hex_footprint.gd` extended; gate verified by reinstating the bounding-box sizing |
| 2026-09-12 | audio | ✅ | **A GPU fidelity preset was silently turning the music off.** `_cached_potato_bed` was gated on `shader_perf_tier >= 2`, which the "potato" *graphics* preset sets — swapping the reactive synth for a stub that **hard-zeroes the drum bus** and ignores tank state. Measured over 5 s of generated audio: full bed drums −20.8 dBFS / synth −26.8; potato bed drums **SILENT** / synth −39.6, and byte-identical for a dead tank and a healthy one, which is what gave it away. Now its own audio setting (`music_simple_bed`, default off, auto only for `device_tier == "low"`), and the stub levelled ×3 so even it reads as "simple" not "broken" | `smoke_ambient_audio.gd` 20 checks; `dev/audio_probe.tscn` measures real samples |
| 2026-09-12 | audio | ✅ | `AmbientAudio` had no `_exit_tree`: a synth batch dispatched to `WorkerThreadPool` holds `_synth_mutex` and writes node state, and nothing awaited it on teardown — so a batch in flight when the node left the tree ran against a half-freed object | Now waits for task completion |
| 2026-09-12 | HUD | ✅ | **The menu and fullscreen buttons got covered by the stats bar.** `StatsBar.offset_left` was a literal `128` in the scene and `96/88` at runtime, while the menu cluster is a `PanelContainer` that sizes to its contents — nothing connected them. Any longer label, bigger UI scale or **translated string** slid the chips over the buttons; the pseudolocale alone renders labels ~40% wider, so localisation made this certain rather than likely. Inset is now derived from the measured cluster (`HudLayout.stats_left_inset`), with a floor for the unmeasured first frame and a cap so a runaway measurement cannot push chips off-screen | `smoke_hud_layout.gd` 70 checks incl. clearance across six cluster widths and monotonicity |
| 2026-09-12 | audio | ✅ | **Built a measurement harness before touching the music.** `dev/audio_probe.tscn` renders the bed to a WAV per bus at a chosen tank state and daylight, so the mix could be analysed (numpy: RMS, peak, octave bands, spectral centroid, note-onset rate) and *listened to* rather than guessed at. Two of my own early readings were wrong and the harness caught both: a magnitude-weighted centroid said "49% hiss above 4 kHz" when power-weighted it was a reasonable spectrum, and a first reactivity measurement showed nothing because the probe called `_refresh_thread_cfg_snapshot` instead of `_refresh_mix_cache` | — |
| 2026-09-12 | audio | ✅ | **The bed was ~26 dB too quiet, from compounded gain.** `_cached_vol = user_volume × complexity × energy-lerp × vitality-lerp` — four fractions multiplied (~0.22), then each voice multiplied its own small mix and gain on top, giving a mix peaking at −41.6 dBFS and averaging −57.8. Notably `complexity` is an **arrangement** control (how much is happening) and using it as a level multiplier cost 6 dB for nothing. Replaced with explicit `BUS_TRIM_*` constants as the single place absolute level is decided. Mix RMS **−57.8 → −30.6**, peak −41.6 → −17.2 | `smoke_music_reactivity.gd` 123 checks |
| 2026-09-12 | audio | ✅ | **The "reactive" soundtrack moved 0.6 dB between a dying tank and a thriving one.** Drums reacted (an aeration gate, 11 dB) but the synth — most of what you hear — was static to within 0.4 dB. Added `MusicReactivity`: health from vitality/O₂/clarity minus algae/nitrate drives a one-pole cutoff (700 Hz muffled → 7200 Hz open), a level bloom, and a wide swing on the air bus. Deliberately **timbral, not just level** — turning a bed down when the tank is sick fights the player, who raises system volume and is then deafened by the next UI sound. Now **6.1 dB level, 337 Hz brightness, air +15.3 dB** dead→thriving | Sick bed stays audible on purpose: it must sound wrong, not broken |
| 2026-09-12 | audio | ✅ | **No arc longer than a phrase**: over 45 s the level held within 3.3 dB on a ~6 second repeat. Rather than a free-running LFO, the macro arc now follows the tank's own **day cycle** — long form for free, and the music is about the thing the player is watching. Night is quieter, *emptier* (notes thinned by halving the rate — a quiet busy arp still sounds busy), and **more** reverberant. Measured night→day: 3.7 dB level, **6.7 → 24.5 notes/sec**, air inverted | `MusicReactivity.step_stride` |
| 2026-09-12 | lighting | ✅ | **The lamp switched itself off every morning — a regression from the darkness work.** The fixture and its shaft blend a *daytime* term driven by the sun against a *night* term driven by the lamp, mixed on `deep_night`. Correct in a normal room; wrong the moment `room_darkness` is up, because the daytime term reads `global_energy` — exactly what darkness had just crushed to 0.02. At dawn in a 0.97-dark room the beam read `alpha 0.003`. Added `LightingRig.lamp_dominance(deep_night, darkness)`: a blacked-out room **is** night as far as the tank is concerned, whatever the clock says. Dawn now gives `alpha 1.14`, spot energy `1.78 → 8.98` | `smoke_gooseneck.gd` 95 checks |
| 2026-09-12 | lighting | ✅ | **The lamp moved as one rigid piece, so dragging it carried the rim clamp out over open water with the cable trailing into the room.** A real gooseneck moves the other way round: the clamp stays bitten to the rim and the NECK bends. Restructured so the fixture root rides the **head**; `Gooseneck` derives the clamp as the nearest point on the footprint perimeter, rebuilds the neck as an upward-bowed Bezier between clamp and head, and hangs the cable from the clamp down the outside of the glass. Head is constrained to arm's length so the neck can't stretch across the room | Asserted: clamp lands ON an edge from 16 drag directions across hex and box, cable starts exactly at the clamp and only ever descends, neck meets both ends with no gap and always bows above the straight line |
| 2026-09-12 | plants | ✅ | **Nothing could reach the water surface, so the surface-layover code had never once run.** Plant heights were fixed voxel counts while tanks are any size the player picks: valli's 22-voxel ceiling is 7.04 units of blade against the Night Lamp hex's 8.25-unit water column — it finished growing **1.06 units short**, and `_apply_canopy_layover`, which bends ribbon blades at the waterline and runs them along it, was unreachable. Making tanks bigger had made it worse. Heights for `reaches_surface` species are now derived from the tank's own water column (`PlantEstablish.surface_height`) | Verified across 6.5/9/11/14-unit tanks: valli tops the surface in all of them, capped at 52 voxels |
| 2026-09-12 | plants | ✅ | **Vallisneria now pools on the surface.** Two further blocks: `_enter_canopy()` set `max_height = current_height`, freezing the blade the instant its tip touched the water so there was never surplus to lay down; and the layover ran **once**, so anything grown afterwards would have stuck straight up out of the tank. Added a `surface_pooling` flag — such plants enter the canopy (bend, meniscus break, flowering) but keep growing, and the layover re-applies per new voxel. Surplus is tied to `Plant.CANOPY_LAY_RIBBON` as one shared constant: drift either way and the blade tears from its stem or pokes a stub above the waterline | `smoke_growth_and_morphs.gd` 539 checks; both bugs verified caught by reintroduction |
| 2026-09-12 | bugs | ✅ | Three errors from the last two passes: `len` shadowing the built-in in `gooseneck.gd`; a dead `height_above` parameter on `_add_god_ray_beam` (removed rather than underscored — the shaft reads the lamp's real height off the fixture now); and a **runtime** `String→Script` assign in `spawn_seedling`. The last is a latent pre-existing bug my work exposed: `get_seed_config()` stores `base_g["script"] = get_script()` as a real Script, but a seed restored from the on-disk seed bank has been through JSON where a Script survives only as a path — and valli now reaching the canopy makes it flower and seed, so the path finally ran. Accepts either form | Editor rescan: 0 warnings |
| 2026-09-12 | UX | ✅ | **The stray line was my own gizmo.** Verified first that the beam's footprint clip was actually wired — the `vec4[8]` uniform round-trips intact — which ruled the shaft out. The culprit was the lamp→aim link line: a dashed run drawn clear across the tank, correct by design and reading as an artifact in practice. Removed. Also added a real bounds check: a handle whose world anchor is off to the side unprojects to a large **finite** screen position, so the old `!= Vector2.INF` guard let handles draw far outside the viewport | `smoke_light_handle.gd` 162 checks |
| 2026-09-12 | testing | ⚠️ | `smoke_app_log` failed once under the parallel runner ("session log must not be empty"), then passed in isolation and on a full re-run. AppLog writes to a single shared `user://logs/` path that all 8 parallel processes share and can rotate underneath it — it has passed by luck until now. Filed for triage; not a regression | Suite green on re-run |
| 2026-09-12 | lighting | ⚠️ | Probe also found smaller escapes not yet addressed: snail shells poke ~0.13–0.27 past the glass on a hex's angled faces (the clamp does not account for shell radius on non-box footprints), and one hardscape voxel by 0.23 | `dev/footprint_probe.gd` retained as a diagnostic |

### Status legend

- ✅ **done** — shipped and verified (smoke green / manually confirmed)
- 🟡 **partial** — landed, but a named part remains (say which, in "What changed")
- ⏸ **blocked** — cannot proceed; name the blocker
- ❌ **rejected** — deliberately not doing it; say why (a rejected direction is a
  *result*, not a gap)

### Direction roll-up

Mirrors the log; update the row when a direction's status changes.

| # | Direction | Status |
|---|---|---|
| 1 | Close out the Valve build review | 🟡 |
| 2 | Actually integrate Steamworks | 🟡 |
| 3 | Progression layer | 🟡 |
| 4 | Save version stamp + migrations | ✅ |
| 5 | Runtime diagnostics / application log | ✅ |
| 6 | Harden the loaded-data trust boundary | 🟡 |
| 7 | Carve the four god-objects | 🟡 |
| 8 | Typed service contracts at module seams | 🟡 |
| 9 | Decide the content-as-data fate | 🟡 |
| 10 | Smoke suite runtime | ✅ |
| 11 | Shared test framework | ✅ |
| 12 | Perf budget contracts in CI | ⏸ |
| 13 | Exploit the determinism already built | 🟡 |
| 14 | Localization | 🟡 |
| 15 | Accessibility: high-contrast + screen reader | ⏸ |
| 16 | Decide what Web and Android are | ⏸ |
| 17 | Make the mind legible | ✅ |
| 18 | Curate the 284 config knobs | ✅ |
| 19 | The share loop | 🟡 |
| 20 | Rebalance idea supply against validation | ⏸ |

---

## Cluster A — Ship-blocking / commercial

### 1. Close out the Valve build review
*Effort: M · Impact: L*

`steam/REVIEW_FEEDBACK.md` records three unresolved failures from BuildID
`#24083947`: Full Controller Support (four checklist items unticked), the AI
Content Survey mismatch, and the phantom-IAP reply. Review was **Windows-only**;
macOS and Linux have never been smoked *through the Steam client*. Highest
leverage item in the repo, and mostly verification rather than code.

Code-level residue: player-facing copy is already de-purchased ("Adopt fish",
"no purchases") but internals still read `FishStorePanel`, `FishStoreToggle`,
`MODAL_STORE`, `spawn_purchased_fish`, icon key `"store"`.

### 2. Actually integrate Steamworks
*Effort: L · Impact: L*

`steam_service.gd` is 15 lines and `steam_service_desktop.gd` only calls
`steamInitEx` + `run_callbacks`. No achievements, no Steam Cloud, no rich
presence, no Workshop. A generative aquarium with a 284-property config and an
emergent species library is unusually well-suited to Cloud and Workshop;
achievements are the cheapest retention surface available.

### 3. Progression layer
*Effort: L · Impact: L*

No achievements, quests, goals, unlocks, or milestones anywhere. The sim already
tracks ecological succession ledgers and `SpeciesLibrary` discoveries — the raw
material for long-horizon goals exists and nothing consumes it. Decide
deliberately whether "no progression" is a design stance (valid for an ambient
toy) or an omission.

---

## Cluster B — Correctness risks with player-visible blast radius

### 4. Save version stamp + migrations
*Effort: M · Impact: L*

`tank_saves.gd:21` declares `const STATE_VERSION := 1` and **never writes or
reads it**. Every save-schema change from here is unmigratable and
unrejectable; a stale save loads silently with missing fields. Pairs badly with
#5 — the failure is both invisible to the player and unreportable to us.

### 5. Runtime diagnostics / application log
*Effort: M · Impact: L*

Across ~136k non-test lines: **1** `push_error`, 30 `push_warning`, 0
`printerr`, 6 asserts. No crash reporting, no opt-in telemetry, no player-facing
bug-report path, no on-disk log. When a tank breaks we will hear "it broke" and
have nothing else.

### 6. Harden the loaded-data trust boundary
*Effort: M · Impact: M*

13 `FileAccess.open` sites, JSON saves, a `guardian_custom_gguf_path` config
knob, and an Ollama HTTP bridge. `read_json` already refuses oversize files and
sanitizes — extend that posture to every external input with explicit failure
modes instead of best-effort parsing.

---

## Cluster C — Architecture

### 7. Carve the four god-objects
*Effort: XL · Impact: L*

`main.gd` 11,385 (490 functions) · `world.gd` 10,199 · `fish.gd` 9,449 ·
`sim_driver.gd` 7,139 = **38,172 LOC, 28% of the codebase in four files**.
`world` is referenced by name in 99 of 390 scripts. The `mind_*` subsystem (48
focused modules) already demonstrates the target shape.

### 8. Typed service contracts at module seams
*Effort: L · Impact: L*

1,077 `has_method()` guards, 332 `get_node_or_null`. `has_method("daylight")`
alone appears **77 times** — the same defensive check copy-pasted because
`world`/`main` are typed as bare `Node`. Rename `daylight()` and nothing fails
at compile time; 77 call sites silently take their fallback branch. Extracting a
few typed interfaces (`DaylightSource`, `TankGeometry`, `FlowField`,
`PlantQuery`) converts a class of silent-fallback bugs into parse errors.

### 9. Decide the content-as-data fate
*Effort: L · Impact: M*

Six `.tscn` files and one JSON data file in the whole project; species tables
live inline in GDScript. `data-schemas/` holds schemas that ADR-002 confirms
nothing consumes; `sim-rust/` is 1,328 lines that ADR-001 confirms isn't wired
in. Either commit to data-driven content (unlocking modding, Workshop, and
non-programmer tuning) or delete both reference subprojects. Today we maintain
both paths and get neither.

---

## Cluster D — Test & release engineering

### 10. Smoke suite runtime
*Effort: M · Impact: M*

`run_smokes.sh` boots a full Godot process **148 times, serially**, no
parallelism. `AGENTS.md` documents that `smoke_runner.gd` has no per-script
timeout and that the `smoke_tank_balance.gd` soak can stall an unattended run.
Per-script timeouts, CI sharding, and a single-boot in-process runner.

### 11. Shared test framework
*Effort: S · Impact: M*

`_assert` is redefined **82 times** and `_fail` **24 times** across the smoke
scripts; every file reimplements its harness. One `test_support.gd` cuts the
boilerplate and makes failure output uniform.

### 12. Perf budget contracts in CI
*Effort: M · Impact: M*

`PerfGovernor` is genuinely good, but it **reacts** — demoting LOD under
pressure. There is no per-platform-tier perf contract asserted with real
numbers, so a regression surfaces as "the mind got dumber on mid hardware"
rather than a red build. `smoke_perf_realtime.gd` is the seed; make it a
ratchet.

### 13. Exploit the determinism already built
*Effort: M · Impact: M*

`sim_rng.gd`, `mind_rng.gd`, `mind_replay_parity.gd`, and
`data/golden_mind_replay.json` exist — and the golden replay is referenced by
exactly **one** smoke script. Deterministic replay is the right foundation for
balance regression testing, bug reproduction from player saves, and a shareable
seed feature. Built, barely used.

---

## Cluster E — Reach

### 14. Localization
*Effort: L · Impact: L*

**Zero `tr()` calls** in 390 files; ~1,400 hardcoded English strings. A largely
wordless ambient aquarium is a strong international product, and it currently
cannot ship in any other language. Retrofitting after another 1,400 strings is
strictly worse.

### 15. Accessibility: high-contrast + screen reader
*Effort: M · Impact: M*

Better than first assumed — `reduced_motion` (33 refs), `font_scale` (25),
colorblind (26), captions/subtitles (124/40) all exist, and the creed already
commits to reduced-motion cost trimming. The genuine gaps are **high-contrast**
(0 refs) and **screen-reader / TTS** (0 refs). Note the 512×288 upscaled render
target makes text scaling a design problem, not a toggle.

### 16. Decide what Web and Android are
*Effort: M · Impact: M*

Export presets exist for both; Guardian LLM is explicitly disabled on both per
the platform matrix; Android has a home-screen widget export path in
`sim_driver`. Whether either is a supported product, a demo funnel, or
aspirational is unclear — and that ambiguity taxes every platform branch (36
`_is_mobile`, 35 `OS.has_feature`).

---

## Cluster F — Product & design

### 17. Make the mind legible
*Effort: L · Impact: L*

**48 `mind_*.gd` modules** — active inference, global workspace, felt-self
layers, self-models, episodic memory — and **no UI panel surfaces any of it**
(zero `mind_state` / `MindState` references in any `*panel*.gd`).
`comms_inbox`, `fish_journal`, `guardian_journal`, and
`onboarding_legibility.gd` show the intent. The largest single investment in the
codebase is currently something the player can only infer. Probably the biggest
available *felt* improvement per unit of work, because the simulation already
exists.

### 18. Curate the 284 config knobs
*Effort: M · Impact: M*

`tank_config.gd` exposes **284 properties**; `settings_panel.gd` runs 85
functions over ~46 rows. That is an expert tool bolted to an ambient toy. A
curated preset layer *over* the raw knobs serves both audiences without removing
anything.

### 19. The share loop
*Effort: M · Impact: L*

`take_pond_photo()` exists in `main.gd`; `capture.gd` is dev-only.

**Corrected 2026-09-10:** timelapse **does** exist (`T` → frame sequence in
`captures/timelapse_<ts>/`); the original claim that it did not was wrong. The
real gaps were that a saved photo carried no provenance — no tank identity, no
seed, nothing tying the image to the tank that made it — and that
`SimDriver.tank_seed` was already persisted but unreachable from any UI. For a
game whose whole output is unique-looking emergent tanks, that is the cheapest
organic-growth mechanism available, left unbuilt.

---

## Cluster G — Process

### 20. Rebalance idea supply against validation
*Effort: M · Impact: L*

`docs/` holds **47 idea docs / ~19,841 lines**, and the last 60 commits are
almost entirely `feat(plants): … (PLANT_SYSTEMS_50 #N)` — one commit per
numbered item. The process ships volume. The cost shows as drift: `AGENTS.md`
says "~70 GDScript files" (actual **390**), `GOALS.md` says "Last reviewed:
2026-06-16", and 39 untracked PNGs sit in `artifacts/` un-gitignored.

More importantly, nothing in the loop asks *"did the last 50 items make the game
better?"* — no playtest feedback, no telemetry (#5), no balance dashboard beyond
the soak harness. Consider spending one campaign slot on a **validation**
campaign instead of a features campaign.

---

## If only three

1. **#1** — nothing else matters if it cannot ship.
2. **#17** — the largest built-but-unfelt investment in the project.
3. **#4 + #5 together** — today a player-side failure is neither visible to them
   nor diagnosable by us.
