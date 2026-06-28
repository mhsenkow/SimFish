# Onboarding & Legibility — 100 Deep Ideas

*Drafted 2026-06-26. Director's brief for "depth made felt."*

The brief: the game has **300+ shipped systems** and an invisible chemistry /
nutrient / O₂ / population engine, plus inner-life, bond, music, hydrodynamic,
and Guardian pillars. The risk is brutal and specific: **a new player sees "fish
swimming" and never perceives any of it.** Depth the player can't read is depth
that doesn't exist for them.

This pillar is the cheapest multiplier on everything already built. It splits
into four jobs:
1. **The first ten minutes** — a complete, confident first-run that ends with the
   player *wanting* to watch.
2. **Reading the invisible engine** — surface the chemistry, the cycle, the
   trophic loop so the simulation's depth becomes legible.
3. **Every stressor has a tell — and the tell is explained** — H10 #91 shipped the
   *cues*; this makes a newcomer *understand* them.
4. **UI / menu / systems polish** — discoverability, consistency, good defaults,
   feedback, glossary, accessibility.

Format follows [GOALS.md](GOALS.md) / [the plants doc](PLANT_IMPROVEMENT_IDEAS.md):
**Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S (polish) /
M (noticeable) / L (transforms how understandable the game is). File/line
pointers are navigational hints — match by symbol if lines have drifted.

---

## What already exists (build on it; don't rebuild)

> **Entry flow is already wired.** Know it cold before adding anything:
> - **Tank shelf** — [`tank_menu.gd`](../shaders-godot/godot-project/scripts/tank_menu.gd)
>   (`_refresh()` ~95, empty-state label ~104, `_on_new_pressed()` ~316,
>   `_add_info_button()` ~59) + `tank_menu.tscn`. Entry scene per `project.godot`.
> - **Scenario picker** — [`scenario_picker.gd`](../shaders-godot/godot-project/scripts/scenario_picker.gd):
>   `SCENARIOS` (~46–331, **11 scenarios + Surprise Me**), `_build_card()` (~483)
>   with a **tagline + body + equilibrium hint** ("settles around ~12 fish",
>   ~529), `apply_scenario()` (~748), `random_wildcard_config()` (~350).
> - **Guided walkthrough** — [`walkthrough.gd`](../shaders-godot/godot-project/scripts/walkthrough.gd):
>   `_build_steps()` (~51–88, **7 steps**: intro → hardscape → plants → snails →
>   shrimp → fish → done), `_build_ui()` (~91). Pauses the sim. Triggered via
>   `cfg.walkthrough_pending` → `main._maybe_start_walkthrough()` (~3062).
> - **Welcome overlay + coachmarks** — [`main.gd`](../shaders-godot/godot-project/scripts/main.gd):
>   `_maybe_show_tutorial()` (~7710, platform-adaptive, sets `tutorial_seen`),
>   `_maybe_show_coachmarks()` / `_show_coachmark_step()` (~7582, **3 tips**).
> - **Help / cheat sheet** — `main._toggle_cheat_sheet()` (~7528), `?` key. Copy is
>   **hardcoded** (~7562) and can drift from real bindings.
> - **HUD chips** — `main._build_hud_chips()` (~3856, 9 chips), `_chip_tooltip()`
>   (~3896). Tappable → water-detail popup (`_show_water_chemistry_popup` ~5687,
>   lines from `hud_controller.water_detail_lines` ~97), story log
>   (`_show_story_popup` ~5465), sparklines (`_show_history_popup` ~5892).
> - **Creature inspect** — `main._pick_creature_at_click()` (~3006), residents
>   panel ([`residents_panel.gd`](../shaders-godot/godot-project/scripts/residents_panel.gd)
>   `_make_card` ~447, `_sub_text` ~665), lineage tree
>   ([`lineage_tree_view.gd`](../shaders-godot/godot-project/scripts/lineage_tree_view.gd)),
>   species library ([`library_panel.gd`](../shaders-godot/godot-project/scripts/library_panel.gd)
>   `select_species` ~274).
> - **Good defaults exist** — `tank_config.gd`: `tank_preset` default
>   `"classic_community"` (~706), `TANK_PRESETS` (~1548), `cycle_start_mode "fresh"`
>   (~77), `SUBSTRATE_PROFILES` (~1864), `AERATION_PROFILES` (~1823). Walstad
>   Jungle (SCENARIOS[0]) is the intended beginner tank.
>
> **The five gaps this doc attacks:**
> 1. **The walkthrough teaches *stocking*, not *watching*.** It ends at "press
>    Finish to start the sim" — the player has placed animals but has never been
>    shown the cycle, the chips, the tells, or what to *look for*. The payoff
>    (the alive tank) is never framed.
> 2. **The invisible engine stays invisible.** Chemistry lives behind a chip-tap
>    most newcomers never make; the nitrogen cycle (the literal first-week story)
>    is never narrated as it happens.
> 3. **Cues exist; meaning doesn't.** Surface-gulping, hiding, gill-flush, pacing
>    all ship — but nothing tells a newcomer "that's hypoxia, open a vent." H10
>    #91 closed the *production* gap; this closes the *comprehension* gap.
> 4. **Controls aren't discoverable.** Gesture combos (Shift+LMB startle, RMB
>    dolly, Space+drag pan, pinch, edge-swipe, double-tap reset, 9/0 food) live
>    only in a hardcoded `?` sheet. No persistent legend; the sheet omits some
>    real bindings (e.g. Render `R`).
> 5. **Defaults under-explained.** "Fresh" cycle scenarios start with a
>    deliberate ammonia spike that *looks like* the game breaking — no scaffolding
>    tells the player it's intentional and survivable.

---

## A. The first ten minutes — make the walkthrough *complete*

The current walkthrough ends the moment stocking ends. The first session should
end with the player understanding *what they're looking at* and *why they'd come
back*. Extend `walkthrough.gd`'s step list and the post-finish flow.

- [x] **1. Add a "Now watch" closing chapter.** `walkthrough.gd:_build_steps()` ends at "Done → Finish." Add 2–3 post-stock steps that *unpause briefly* and point at live behavior: "See the school tighten? That's shoaling." "Tap the water to drop food — watch them converge." Convert the tutorial from *setup* to *seeing*. *M·L*
- [x] **2. Frame the nitrogen cycle before it scares them (opt-in path only).** Per #9, beginners now default to "established," so this card fires only when the player *chooses* the fresh/"watch it cycle" path. Then: "Your tank is *cycling* — like a new pond finding its balance. You'll see an ammonia bump for a few days. It's normal. Plants and bacteria will handle it." Turns the deliberate hard-mode start into a guided lesson rather than a "is it broken?" bounce. *S·L*
- [x] **3. Offer a 60-second "watch it breathe" demo.** After Finish, optionally run the sim at 8–16× for ~60s with a gentle voiceover-caption track ("day passes… plants pearl… fish settle to sleep…") so a newcomer sees the day/night arc and pearling *immediately*, not 20 minutes in. *M·L*
- [x] **4. Make the walkthrough skippable AND resumable.** It's all-or-nothing today (Skip kills it). Persist the current step index in `cfg`; a dismissed walkthrough should leave a re-entry affordance ("Resume setup tour") on the HUD until completed. *S·M*
- [x] **5. Pre-stock the empty tank with a sane starter so "Skip" isn't a barren box.** Guided mode uses `tank_preset = "empty"` (`tank_menu.gd:495`). If the player skips mid-walkthrough they're left with bare substrate. On skip, auto-apply the scenario's intended preset so they always land in a living tank. *S·M*
- [x] **6. Show the *consequence* of each stocking step live.** When the player adds plants in the walkthrough, flash a tiny "+O₂ / shade" readout; when they add snails, "+cleanup crew." Tie each step to the stat it moves so the systems are introduced *as causes*, not menu items. *M·L*
- [x] **7. A "first feeding" milestone with payoff.** The walkthrough/coachmarks mention feeding; make the *first* tap-to-feed trigger a small celebratory beat (fish converge, a story-log line "First feeding — they came right up"). First successful interaction = retention. *S·M*
- [x] **8. Day-1 / Day-3 / Day-7 scheduled "check-in" cards.** Tie short optional cards to `sim.tank_age_s` milestones that narrate what's happening ("Day 3: ammonia peaking — watch for surface gulping") so the *first week* is a guided story, not a silent grind. Reuses the existing milestone infra (GOALS H8 #71). *M·L*
- [x] **9. ✅ DECIDED — default new players to "established"; fresh is opt-in.** Fresh cycling is a great *advanced* lesson but a rough *first* impression. **Direction set:** flip the beginner default to `cycle_start_mode "established"` (`tank_config.gd:77` + per-scenario in `scenario_picker.apply_scenario()` ~748) so a newcomer's first tank is stable from minute one. Surface "Start from scratch (watch it cycle)" as a deliberate, clearly-labeled opt-in with a one-line tradeoff ("harder — you'll manage an ammonia spike as it matures"). The cycle becomes a chosen lesson, never an ambush. *S·L*
- [x] **10. End-of-tour summary: "Here's your tank, here's how to read it."** A final card that names the 3 chips that matter (mood, water, alert), the feed gesture, and "we'll nudge you if it needs you." Replaces the disconnected 3 coachmarks (`main.gd:7582`) with one coherent close. *M·M*

---

## B. Good defaults & the scenario picker — choose without fear

A new player faces 11 scenario cards (`scenario_picker.gd:SCENARIOS`). The cards
are good (tagline + body + equilibrium hint) but give no sense of *difficulty* or
*which one is for me*. Reduce choice paralysis; make the safe path obvious.

- [x] **11. Badge a "Recommended for your first tank."** Walstad Jungle (SCENARIOS[0]) is the intended beginner tank but nothing says so. Add a "★ Best for beginners" ribbon on its `_build_card()` (~483) and float it to the top. *S·L*
- [x] **12. Surface a difficulty tier on every card.** The data exists implicitly (stocking density, substrate algae-risk, predators, fresh vs established). Compute and show "Easy / Moderate / Hard" + a one-line *why* ("rich substrate — watch algae"). Newcomers self-select. *M·M*
- [x] **13. Add a true "Easiest possible" sandbox scenario.** A forgiving tank: established cycle, aquasoil, light stocking, hardy species, gentle aeration, no predators — explicitly "nothing here will crash on you." A safe place to learn the verbs. *M·M*
- [x] **14. Collapse the picker into a 2-tier view.** Show 3 curated picks first (Beginner / Balanced / Showpiece) with a "More scenarios ▾" expander for the other 8. Eleven equal cards is a wall; a recommended trio is a doorway. *M·M*
- [x] **15. Preview the *feel*, not just the stats.** Each card's accent band is nice but abstract. Add a tiny animated/looping silhouette or a representative still per scenario so the player sees Iwagumi-minimal vs Walstad-jungle at a glance. *L·M*
- [x] **16. Explain the equilibrium hint.** "Settles around ~12 fish" (~529) is great but cryptic to a newcomer — *settles from what?* One tooltip: "Tanks self-balance — this one wants about this many residents once mature." Teaches carrying capacity in one line. *S·M*
- [x] **17. Warn (gently) on known-spicy defaults.** Apex Den (`eco_complete` + sparse plants) and Dutch (CO₂ 0.7) are bloom/work-prone (per GOALS H7). On their cards: "Higher-maintenance — best once you've kept a tank." Honest, not gatekeeping. *S·M*
- [x] **18. "Surprise Me" needs a safety + a preview.** `random_wildcard_config()` (~350) can still feel arbitrary. Show the rolled combo as a readable summary before commit ("Hex tank · sand · cherry shrimp · bright light") with a re-roll button, so it's a delight, not a dice-gamble. *M·M*
- [x] **19. Let the picker say what each axis *does*.** Substrate/aeration/CO₂/shape are locked per scenario but invisible. A collapsible "What's in this tank" row that plain-language-labels each ("aquasoil — rich, plant-friendly") teaches the vocabulary through the choice. *M·M*
- [x] **20. Audit & retune every default against its capacity (legibility-grade).** GOALS H7 retuned balance; this is the *legibility* pass: confirm no recommended/beginner scenario produces a scary reading (red mood, alert chip) in the first 10 minutes of normal play. The first impression must never *look* like failure. *M·L*

---

## C. Reading the invisible engine — surface the simulation's depth

The chemistry, cycle, trophic loop, and stability arc are the game's soul and are
almost entirely hidden behind one chip-tap. Make the depth *visible* and
*self-explaining*.

- [x] **21. A first-run "what to watch" legend.** A one-time dismissible overlay that labels the 3 key chips in place (callout arrows to mood/water/alert) and the feed gesture. Distinct from the welcome wall-of-text — this points at *real UI*. *M·L*
- [x] **22. The water-detail panel needs plain-language, not just numbers.** `hud_controller.water_detail_lines()` (~97) lists NH₃/NO₂/NO₃/KH/GH/pH as raw values. Add a status word + one-line meaning per row ("NH₃ 0.4 — *elevated, mildly toxic; plants are working on it*"). Numbers teach nobody; framed numbers teach everybody. *M·L*
- [x] **23. Color-code chemistry rows green/amber/red.** Same panel. A newcomer can't tell if "NO₃ 20" is fine or alarming. Per-row health tint with a thresholds key turns a data dump into a glanceable diagnosis. *S·M*
- [x] **24. Narrate the nitrogen cycle as a live banner during week one.** GOALS H1 models the cycle; the player never *sees* it unfold. A slim, dismissible cycle-progress strip ("Cycling: ammonia → nitrite → safe · Day 4 of ~14") makes the invisible first-week the visible *plot*. *M·L*
- [x] **25. Make the mood chip explain itself.** `_render_header()` (~3755) shows 🙂/😌/😟/🚨 with no *why*. Tapping mood opens the story log (good), but the chip should also show the dominant driver on hover/expand ("stressed — low O₂"). Connect the symptom to the cause. *S·L*
- [x] **26. Surface the "recycle %" and "stability" as a teaching arc, not buried lines.** They sit in `water_detail_lines` today. Promote stability to a visible first-session arc ("watch this climb as your tank matures") — it's the literal payoff of the genre (GOALS H8 #76). *M·M*
- [x] **27. A "limiting factor" one-liner for plants.** GOALS H6 #54 models Liebig's minimum; expose it in plain words when the player inspects a plant or the flora chip: "These plants want more *light* right now." Teaches the single most useful planted-tank concept. *M·M*
- [x] **28. Trophic-loop "follow the energy" visual.** A one-time animated diagram (or a toggle overlay) showing waste→bacteria→microfauna→fry→fish→waste — the closed-loop metaphor (GOALS H10 #100) made literally visible once, so the player *gets* the Walstad idea. *L·L*
- [x] **29. Inline definitions on first appearance of any metric.** The first time NH₃, KH, pearling, biofilm, etc. appears in any panel, attach a tap-for-definition affordance (ⓘ) that doesn't nag on subsequent views. Progressive disclosure of the vocabulary. *M·M*
- [x] **30. "Why is my mood/water that color?" deep-link.** Any red/amber state should be one tap from an explanation that names the cause, the tell to look for, and the optional fix (ties to the nudge work, §I). Turn every warning into a micro-lesson. *M·L*

---

## D. Every stressor has a tell — and the tell is *explained*

H10 #91 shipped the visible cues (gulping, hiding, gill flush, pacing). The
remaining job is **comprehension**: a newcomer sees the behavior but can't decode
it. Bridge cue → meaning → (optional) action.

- [x] **31. A "What's wrong?" reader on the alert chip.** The alert chip (`main.gd:4727`) already fires for low O₂ / algae / waste / ammonia / nitrite / bleach. Each alert's popup should follow one template: *what's happening · the tell to look for in the tank · what helps (optional)*. Make alerts teach. *M·L*
- [x] **32. Caption the cue the first time it occurs.** First time fish surface-gulp, a small unobtrusive caption near them: "Gulping at the surface — oxygen is low." Once per cue type, persisted, so the player learns the visual vocabulary of distress. *M·L*
- [x] **33. A "tank tells" reference card.** A browsable legend (in Help) pairing each behavior with its meaning: gulping→low O₂, hiding→stress, gill-flush→ammonia, pacing/glass-surfing→crowding or boredom, clamped fins→illness. The decoder ring for the whole sentience layer. *M·M*
- [x] **34. Stressor→tell coverage audit (legibility grade).** Re-walk GOALS H10 #91's list and confirm *every* hidden stressor (low O₂, NH₃, crowding, loneliness, chronic bad water, rest debt) has a cue that is (a) visible at default camera distance and (b) decodable via #32/#33. Fix any that are too subtle to read. *M·L*
- [x] **35. Distinguish "fine" idle from "distressed" idle.** Sleeping at night vs sluggish-from-rest-debt vs listless-from-boredom can look identical to a newcomer. Give each a subtly distinct read + a hover/inspect label so stillness isn't ambiguously alarming. *M·M*
- [x] **36. Individual inspect: state the feeling in words.** `residents_panel._sub_text()` (~665) shows activity + bio + thought. Add an explicit affect line: "Stressed (crowded)", "Content", "Hungry", "Tired" so the inner-life pillar is *readable*, not just simulated. *S·M*
- [x] **37. Escalation legibility.** A minor, recoverable scare and a chronic grind should *look* different in aggregate (one fish darting vs the whole tank tense and dim). Make severity legible at the tank level, not just per-fish. *M·M*
- [x] **38. "It's recovering" is as important as "it's wrong."** When a stressor clears, show the positive turn (mood ticks up, a story line "O₂ recovered — the school relaxed"). The care→recovery loop only teaches if the recovery is *seen*. *S·M*
- [x] **39. Pearling as the trust signal, explained.** GOALS H6 #60 makes pearling an honest health gauge. Tell the player once: "Those bubbles on the leaves mean your plants are thriving — the tank is breathing well." Turn a pretty effect into a readable instrument. *S·M*
- [x] **40. A gentle "first death" explainer.** The first natural death already logs a story line. Wrap it with care-framed context ("Fish don't live forever — this one lived a full life. Its body will feed the tank.") so mortality reads as part of the loop (GOALS H10 #97), not a failure. *S·M*

---

## E. Controls & input discoverability

Rich input (gesture combos, 9/0 food cycle, edge-swipe, pinch) lives almost
entirely in a hardcoded `?` sheet that omits some real bindings. Make controls
discoverable *in context*.

- [x] **41. Generate the cheat sheet from the real bindings.** `_toggle_cheat_sheet()` (~7528) hardcodes its text (~7562) and already misses Render `R` and the aquascape `[`/`]` brush keys. Drive it from the actual `_handle_shortcut()` table (~1498–1545) so it can never drift. *M·M*
- [x] **42. Add gesture combos to the help, with pictures.** The sheet omits Shift+LMB (startle), RMB dolly, Space+drag pan, two-finger pinch, edge-swipe-for-Settings, double-tap-reset. List them with tiny glyph diagrams, not just text. *S·M*
- [x] **43. A persistent, minimal control hint.** `controls_hint` only shows in motion-debug. Replace with a slim, fade-on-idle hint of the 2–3 most useful actions for the current mode ("Drag to look · Tap water to feed · ? for help"). *M·M*
- [x] **44. Context-sensitive hints per mode.** Entering aquascape should show *its* controls (paint, [/] brush, undo); entering follow should show *its* controls (←/→ cycle, Esc release). The hint adapts to what the player is doing. *M·M*
- [x] **45. First-use coachmark per major mode, not just per app.** The 3 global coachmarks (`main.gd:7582`) fire once ever. Add a tiny first-entry hint the first time the player opens Aquascape, the Creature Creator, the Sound Studio, etc. Teach each surface when it's first relevant. *M·M*
- [x] **46. Tooltip the right-rail icons with verbs, not nouns.** The rail is icon-only (gear/palette/note…). Hover/long-press tooltips should say what you *do* ("Build & plant your tank"), not just name the panel. *S·M*
- [x] **47. Mobile: surface the hidden gestures.** Pinch-zoom, edge-swipe-Settings, double-tap-reset are undiscoverable on touch (no cheat sheet). Add a one-time gesture coachmark sequence on mobile first-run. *M·M*
- [x] **48. A "controls" entry in a visible place.** `?` is a desktop keypress; mobile has no equivalent surfaced. Add a Help/❓ button to the rail and the menu so the legend is reachable without knowing the secret key. *S·M*
- [x] **49. Confirm-free, reversible exploration.** Make sure every "scary" verb (delete tank, reset camera, undo aquascape) is either reversible or confirmed, so a newcomer can poke at everything without fear. Audit destructive actions for an undo/confirm. *M·M*
- [x] **50. Optional keybinding remap + "show shortcuts" in Settings.** Surface the shortcut table inside `settings_panel.gd` (it has 6 tabs already) as a read-only list at minimum — many players never press `?`. Remapping is a bonus. *M·S*

---

## F. HUD, chips & information-design polish

The chip row is dense (9 chips) and assumes the player knows what each glyph
means. Tighten the hierarchy so the *important* state is unmissable and the rest
is progressive.

- [x] **51. Establish a clear chip hierarchy.** `_build_hud_chips()` (~3856) renders 9 equal chips. A newcomer can't tell mood (critical) from morphs (trivia). Visually tier them: mood + water + alert prominent; population chips secondary; morphs/state tertiary. *M·M*
- [x] **52. Hide advanced chips until earned.** Show only mood + water + fish on first run; reveal flora/shrimp/snails/morphs as those populations matter or as the player completes the tour. Progressive disclosure of the HUD itself. *M·M*
- [x] **53. Animate the chip that just changed.** When mood drops or an alert fires, a brief pulse/flash draws the eye. A static row of numbers is ignorable; a chip that *reacts* gets read. *S·M*
- [x] **54. Make "tap me" obvious on tappable chips.** Tappability (history, water detail, story) is invisible. A subtle affordance (underline, ⓘ, or a one-time "tap for details" hint) on first run unlocks the entire detail layer. *S·M*
- [x] **55. Units and ranges on every readout.** "O₂ 62%" of *what*? A tiny "(safe ≥ 50%)" range turns an abstract number into a judgment the player can make. Apply across the water panel and chips. *M·M*
- [x] **56. Consolidate the alert experience.** Alerts surface via a chip that only appears when active (good) but compete with the static row. Consider a dedicated, unmissable alert toast for *new* alerts, with the chip as the persistent re-open. *M·M*
- [x] **57. A single "tank status" glance line.** One plain-English sentence at rest ("Thriving · cycling, day 4 · all calm") that summarizes the whole HUD for someone who doesn't want to parse chips. The TL;DR of the tank. *M·M*
- [x] **58. Sparkline popups need a baseline/target.** `_show_history_popup()` (~5892) shows now/min/max. Add the healthy band as a shaded region so the trend reads as "good/bad," not just "a wiggly line." *S·M*
- [x] **59. Consistent iconography + a key.** Audit emoji/glyph usage across chips, residents (🐟🦐🐌🦪), and panels for consistency, and add a one-screen icon key in Help. *S·S*
- [x] **60. Idle/immersive mode shouldn't hide the lifeline.** When the HUD dims (mobile idle / immersive), ensure a *new* critical alert still breaks through. Calm by default, never silent in a crisis. *S·M*

---

## G. Glossary, tooltips & just-in-time teaching

The domain is jargon-dense (Walstad, aquascape, hardscape, substrate, KH/GH,
pearling, cycling, biofilm, Iwagumi, mouthbrooder). Teach terms *when first seen*,
and keep a reference.

- [x] **61. A built-in glossary.** One browsable screen (in Help) defining every domain term in one warm sentence each, with a "see it" link where applicable. The manual nobody reads, available the moment somebody wants it. *M·M*
- [x] **62. First-appearance ⓘ chips on jargon.** The first time a term shows in any panel, render it with a tappable definition; suppress thereafter (persist seen-terms). Reuses the §C #29 pattern app-wide. *M·M*
- [x] **63. Rename or gloss insider scenario/preset names.** "Iwagumi," "Dutch," "Walstad," "polyp_lab" mean nothing to a newcomer. Pair each with a plain subtitle ("Iwagumi — minimalist stone garden"). *S·M*
- [x] **64. Tooltip the settings sliders with consequences.** `settings_panel.gd` exposes CO₂, light spectrum, schooling intensity, separation, etc. Each slider needs a one-line "what happens when I move this" so the deep config is approachable, not intimidating. *M·M*
- [x] **65. Plain-language substrate/aeration descriptions in the picker AND settings.** `SUBSTRATE_PROFILES`/`AERATION_PROFILES` have descriptions; ensure they're shown wherever the choice is made, in beginner terms ("disk — lots of bubbles, but strips the CO₂ plants want"). *S·M*
- [x] **66. A "what is a Walstad tank?" one-pager.** The game's entire thesis. A short, beautifully-written explainer (the closed loop, low-tech, self-balancing) reachable from the menu — it's the *why* behind everything. *S·M*
- [x] **67. Just-in-time tips tied to events, not timers.** Instead of front-loading everything, fire a single contextual tip when the relevant thing first happens (first algae → "algae is normal in a young tank; your plants will outcompete it"). Teaching at the teachable moment. *M·L*
- [x] **68. A dismissible "did you know" rotating hint in calm moments.** When the tank is stable and the player is idle, occasionally surface one bite-size insight ("Tap a fish to read its story"). Never during stress. *S·M*
- [x] **69. Species detail as a learning surface.** `library_panel.select_species()` (~274) shows traits; enrich with care notes ("peaceful · needs a group of 6+ · top-dweller") so the library doubles as a fishkeeping primer. *M·M*
- [x] **70. Searchable Help.** Once glossary + controls + tells + tips exist, give Help a search box. A newcomer with a specific question ("why are my fish at the top?") should find the answer in two taps. *M·M*

---

## H. Menus, navigation & systems polish

The shell around the sim — tank shelf, panels, transitions — sets the tone of
"this is a finished, understandable game." Tighten consistency and feedback.

- [x] **71. Warm up the empty state.** `tank_menu` shows "No tanks yet. Tap + New tank" (~104). Replace with an inviting first-run hero ("Start your first living world →") and route straight into the recommended scenario. The empty shelf is the literal first screen. *S·M*
- [x] **72. The very first launch should skip the shelf.** A brand-new player has no tanks; landing on an empty shelf is a dead end. On true first run, jump directly to a streamlined "create your first tank" flow. *M·M*
- [x] **73. Richer tank cards on the shelf.** Cards show a thumbnail + name. Add glanceable state (mood glyph, age, "needs attention" dot) so the shelf becomes a status board for someone keeping multiple tanks. *M·M*
- [x] **74. Consistent panel chrome.** Settings/Render/Sound/Light/Camera/Residents panels were built at different times. Audit for consistent headers, close affordances, spacing, and back behavior so the app feels of one piece. *M·M*
- [x] **75. Every panel reachable AND escapable the same way.** Confirm Esc/back and the rail toggle close every panel; no dead-ends. Mobile edge-swipe-for-Settings should have a visible equivalent. *S·M*
- [x] **76. Smooth scene transitions.** Menu→tank and tank→menu via `change_scene_to_file` can feel abrupt. A brief fade + a "your tank lived while away" beat (reuses `_emit_away_recap`) makes returns feel continuous. *M·M*
- [x] **77. Loading/first-frame polish.** Ensure the tank fades in composed (camera framed, not mid-build) so the first thing a newcomer sees is beautiful, not a half-spawned scene. *M·M*
- [x] **78. Settings "Apply needs reload" clarity.** Some settings need a scene reload (per the settings map). Mark those clearly and confirm before a disruptive reload, so changing a slider never feels like it broke something. *S·M*
- [x] **79. Sensible Settings defaults + a "reset to recommended."** Six tabs of sliders is intimidating. Ensure defaults are great out of the box and add a per-tab "reset to recommended" so experimentation is safe. *S·M*
- [x] **80. Naming & save feedback.** Creating/duplicating/deleting tanks should give clear, reassuring feedback (toast: "Saved," "Duplicated 'Reef Cube'"). Silent state changes feel buggy to newcomers. *S·S*

---

## I. Nudges, feedback & the care loop made legible

GOALS H10 #92 specced "nudges, never nags" but the search found **no live nudge
system** — only alert popups and 3 one-time coachmarks. This is the connective
tissue between "something's drifting" and "here's the gentle, optional thing you
can do." It's the heart of making care legible.

- [x] **81. Build the nudge system (it's specced, not shipped).** A throttled, opt-out channel that, when the tank drifts, surfaces *one* soft suggestion framed as the tank asking ("The water's getting heavy — a small water change would help"). Never a failure popup. The missing care-loop spine. *M·L*
- [x] **82. Wire nudges to callable care actions.** GOALS H8/H10 mention water change / filter rinse / root tab as sim methods. A nudge should offer the action inline ("Do a water change") so suggestion→action is one tap, and the player *sees* it help. *M·L*
- [x] **83. Make every care action visibly *do* something.** Feeding, pruning, water change, adding a plant must each produce an immediate, legible positive change (a stat ticks, a story line, mood lifts). The "care helps" loop (GOALS H10 #93) only teaches if cause→effect is instant and seen. *M·L*
- [x] **84. Nudge frequency that respects calm.** Nudges must never fire during a thriving tank, never stack, and back off if ignored. The reward for a balanced tank is *silence*. Tune hard against nagging. *S·M*
- [x] **85. A "your tank while you were away" recap on return.** `sim._emit_away_recap()` (~5049) + `last_quit_unix` exist; surface it as a warm, readable card on re-entry ("3 fry hatched · a brief O₂ dip self-corrected · all calm now"). Makes the tank feel alive and independent (GOALS H10 #94). *M·M*
- [x] **86. Positive reinforcement, not just warnings.** Occasionally acknowledge good keeping ("Your tank has been thriving for 5 days") so feedback isn't exclusively problem-shaped. Balance the loop emotionally. *S·M*
- [x] **87. A "needs attention" digest.** One place that aggregates anything the tank could use, ranked, optional. So a returning player has a single glanceable to-do instead of hunting chips. *M·M*
- [x] **88. Teach that absence is forgiven.** Make legible (in copy + behavior) that the tank can self-sustain — presence helps, absence doesn't punish (GOALS H10 #93). Removes the anxiety that scares casual players off life-sims. *S·M*
- [x] **89. Undo/forgiveness on care mistakes.** Overfed? A gentle recovery path + a one-line "a bit much — skip the next feeding" rather than a punishing spike. Mistakes should teach, not crash. *M·M*
- [x] **90. The care loop, visualized over days.** A simple "attention you gave ↔ how the tank responded" readback (ties to GOALS H10 #98) so the core fantasy — you get back the care you put in — becomes legible across a week. *L·M*

---

## J. Deeper systems, accessibility & first-session feel

Onboarding for the creative/advanced surfaces, plus the accessibility and
polish that make the whole thing feel like a kind, finished product.

- [x] **91. Onboard Aquascape mode.** Entering build (`B` / `aquascape_controller.toggle()`) drops the player into tools with no guidance. A first-entry overlay: paint substrate, place hardscape, [/] brush, undo, "tap to plant." The most creative surface needs the most teaching. *M·M*
- [x] **92. Onboard the Creature Creator.** It's a deep modal (`creature_creator.gd` ~45k). A guided "design your first fish" path (pick a base → tweak color → name → add) so the headline creative feature isn't a wall of sliders. *M·L*
- [x] **93. Onboard breeding/lineage.** Players won't discover that fish pair, spawn, and form lineages. A just-in-time card on the first courtship/first egg ("a pair is forming — tap them to follow the family") opens the entire genetics pillar. *M·M*
- [x] **94. Make the Guardian introduce itself.** The Guardian companion (`guardian_fish.gd`) is a marquee emotional feature a newcomer would never know exists. A gentle first-meeting beat ("One of your fish has taken to you…") with a pointer to its diary. *M·L*
- [x] **95. Onboard the Sound Studio lightly.** `sound_panel.gd` is a ~50-slider control surface. For newcomers, lead with 3 vibe presets and a "the tank makes its own music" one-liner; hide the deep controls behind "Advanced." *M·M*
- [x] **96. Accessibility: colorblind-safe states.** Mood/chemistry/health lean on red/amber/green. Add shape/glyph redundancy and a colorblind palette option so the legibility work reaches everyone. *M·M*
- [x] **97. Accessibility: text scale & reduced-motion.** Offer a UI text-size control and a reduce-motion toggle (calmer camera, fewer particles) — this audience includes people seeking a *calm* experience. *M·M*
- [x] **98. Readable typography & contrast pass.** Audit all HUD/panel text for size and contrast against the busy tank background (drop shadows / scrims behind text). Legibility is literal here. *M·M*
- [x] **99. A "calm mode" framing for the whole product.** Lean into the genre's real draw: a setting/preset that maximizes serenity (soft nudges off, ambient focus, gentle pacing) and is offered up front. Tells the anxious newcomer "this can just be peaceful." *M·M*
- [x] **100. The closing message, made legible at the right moment.** GOALS H10 #100 — somewhere quiet, after the player has *seen* the loop work, make explicit that nothing is added or removed: waste→food, death→soil, light→growth. Don't say it in the tutorial (too early); say it the first time their tank visibly self-corrects. That's the moment the metaphor lands — and the whole game becomes understood. *M·L*

---

## Suggested first slice (highest legibility-per-hour)

If Cursor implements in waves, this order front-loads comprehension:

1. **#2, #9, #20, #11** — defuse the fresh-cycle scare, default beginners to a
   stable start, badge the recommended tank. Stops the "is it broken?" bounce.
2. **#22, #23, #55, #25** — make the water panel + mood self-explaining (words,
   color, ranges, the *why*). Unlocks the existing depth with copy, not systems.
3. **#31, #32, #33** — cue→meaning bridge. The sentience layer becomes readable.
4. **#81, #82, #83, #85** — build the nudge/care loop spine. The return reason.
5. **#1, #10, #21** — close the walkthrough into "now watch" + a live legend.

These five waves are mostly **copy, framing, and small UI** on top of systems that
already exist — the cheapest possible multiplier on the whole codebase.

---

## Manual QA checklist

- Fresh install → first launch lands the player in a living, calm tank within ~2
  minutes, never on a dead-end empty shelf or a red/alarming reading.
- A newcomer who taps nothing still understands "thriving / needs me / feed them"
  from the glance line + mood chip alone.
- Trigger a low-O₂ event: the cue (gulping) appears, a one-time caption explains
  it, the alert chip offers the fix, and clearing it shows a visible recovery.
- Every domain term that appears in a panel has a first-appearance definition.
- `?` / Help legend matches the *actual* key bindings (no drift, no omissions).
- Nudges never fire on a thriving tank, never stack, and back off when ignored.
- Colorblind mode: no state is conveyed by color alone.
- Returning after a day shows a warm, accurate "while you were away" recap.
