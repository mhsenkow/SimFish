# Motion From Above — 100 Deep Ideas (the Guppy-Pond View)

*Drafted 2026-06-26. Director's brief for motion + dance read from the top-down camera.*

The frame: one camera view looks straight **down** into the tank — like standing
over a **guppy pond** or a koi pond. From up there the Y axis collapses and the
**XZ plane becomes the canvas**. The school stops being "fish in a box" and
becomes a *pattern on water*: spirals, mandalas, density waves, the silver flash
of a synchronized turn, ripples spreading from a dart, floaters parting as the
shoal passes beneath. This doc improves **general motion** *and* the
**dance-to-music** system specifically for how they read **from above**.

Format follows [GOALS.md](GOALS.md) /
[the hydrodynamics doc](HYDRODYNAMIC_LIFE_IDEAS.md) /
[the music-dance doc](MUSIC_DANCE_IDEAS.md): **Effort** S (≤2h) / M (half-day) /
L (full day+), **Impact** S (polish) / M (noticeable) / L (transforms the feel).
File/line pointers are navigational hints — match by symbol if lines have drifted.

---

## What already exists (build on it; don't rebuild)

> **The top-down camera is real.** `main.gd` `apply_camera_preset("top")` (~318):
> pitch `_TOPDOWN_PITCH 1.40` (~412), yaw 0, radius `max(hw,hd)*3.4`.
> `apply_camera_projection("top_down_ortho")` (~455) switches to orthographic with
> `_ortho_size_from_tank()*1.2`. Surfaced in
> [`camera_views_panel.gd`](../shaders-godot/godot-project/scripts/camera_views_panel.gd):
> `PRESET_TOP` (~24), `PROJECTION_TOP_DOWN` (~32), the projection OptionButton (~95).
>
> **The motion model** ([`fish.gd`](../shaders-godot/godot-project/scripts/fish.gd)):
> `_motion_substep()` (~5364), `heading`+`speed` (~1154–1157), `max_turn_rate 2.6`
> (hover 1.1 / dasher 3.2), `linear_accel 2.5`. **Hydrodynamics now exists** —
> `Hydrodynamics.integrate_speed()` (~5515), `drag_coeff` (~5503), `coasting` flag
> (~5513), `centripetal_bank` (~5632), banking via `_bank_pivot` (~5627–5641),
> `burst_remaining`/`dart_speed_mult 1.6` (~995/466). Boids: `_boids()` (~6018),
> `separation_radius 0.55`, `LOOKAHEAD 0.4`, rear blind-spot `VIEW_DOT_THRESHOLD
> -0.4`, alignment `1.15`, cohesion `0.82` with density softening + leader tracking
> (`lead_score`). **Shared school rhythm**: `school_pulse_phase()` /
> `school_pulse()` (~5808/4056, `pulse_amp 0.15`), per-fish `_school_phase_offset`
> ±0.1 (~1123) — the "breathing school." Vertical band: `preferred_y 3.5`,
> `home_y_radius 0.8`, night tightening (~4184). XZ territory: `home_x/z`,
> `home_radius 2.5`, `heading_offset` wander (~4713), home drift (~4739).
>
> **The dance system is deep already** (Cursor built it):
> - [`music_context.gd`](../shaders-godot/godot-project/scripts/music_context.gd) —
>   `MusicContext`: unified clock, `fauna_behavior_mods()` (~100),
>   `compute_dance_target()` (~271), `conduct(move, formation)` (~76). Reads both the
>   generative `ambient_audio` *and* external `music_reactive` drive.
> - [`music_choreography.gd`](../shaders-godot/godot-project/scripts/music_choreography.gd) —
>   `MusicChoreography`: **12 MOVES** (~5: sweep, spiral, vortex, wave, starburst,
>   breathe, sway, carousel, curtain, cascade, fountain, kickline), **8 FORMATIONS**
>   (~10: scatter, line, v, circle, mirror, heart, star, ring), 6 `GENRE_PROFILES`,
>   `formation_offset()` slot-based 0–23 (~204), `dance_target()` (~493),
>   `assign_music_role()` band casting (~361), `choir` antiphonal (~142),
>   `is_soloist` (~151), `universal_locomotion_mods` (~429), `arc_intensity` (~54).
> - Fish consume it: `_music_mods()` (~2510), `_apply_music_beat_surge()` (~2617),
>   `_apply_music_groove_steering()` (~2638), `_music_cross_tank_target()` (~2573).
> - **5 mating dances** gated by `swim_pattern` (~3371–3394).
>
> **Surface & shadows (the top-down extras):** `world.spawn_burst_ripple()` (~5482)
> + `spawn_glass_tap_ripples()` (~5520) on the meniscus; `_drift_floaters()` (~1084)
> with `ripple_bob`; `water.gdshader` dual waves; `caustics.gdshader` Worley web;
> fish **blob shadows on the sandbed** (`substrate_caustic.gdshader`
> `blob_shadow_points[8]` ~42, `compute_blob_shadow` ~84, refreshed by
> `world.update_substrate_blob_shadows` ~923) — **capped at 8 fish**; floater
> shadows (`aquarium_visuals.gd` `FLOATER_SHADOW_CAP 64`, `sync_floater_shadows` ~660).

**The five structural levers (for the top-down view specifically):**

1. **Lever 1 — Half the dance is invisible from above.** `curtain`, `cascade`,
   `fountain`, and the `hover` figure-8 mating dance are *vertical* — they vanish in
   plan view. Cast/select moves by camera angle so the overhead viewer always gets
   *horizontal* choreography (spirals, rings, mandalas) (§F).
2. **Lever 2 — The water surface is an unused canvas that ONLY reads from above.**
   Ripples, wakes, interference rings, floaters parting — these are *the* top-down
   spectacle and are barely coupled to motion (§B, §I).
3. **Lever 3 — Turning is the readable verb from above; make it beautiful.** A turn
   is a *curve* in plan view. Banking arcs, momentum trails, and especially
   **synchronized turns** (the guppy-pond "flash") are the signature read (§C, §E).
4. **Lever 4 — The school is a 2D organism up there.** Density waves, polarization,
   split/merge, edge shimmer — flock dynamics that only resolve as a shape from
   above (§D).
5. **Lever 5 — Shadows on the sandbed are the second pattern.** With the camera
   overhead you see *two* choreographies — the fish and their shadows. The 8-shadow
   cap throttles it; lift it and choreograph the floor (§I, §J).

---

## A. The top-down camera itself — make the plan view first-class

A guppy-pond view deserves more than a tilted preset. Tune the overhead camera so
the surface and the pattern are the subject.

- [x] **1. A dedicated "Pond" / overhead mode.** Beyond the `top` preset (~318) + `top_down_ortho` (~455), add a one-tap **Pond Mode** that combines: top-down ortho, surface-focused framing, raised ambient light, surface reflections on, and dance-friendly defaults. The whole feature gets a front door. *M·L*
- [x] **2. Frame to the water surface, not the tank center.** `top` targets `y=tank_h*0.5` (~320). For a true pond read, target the **surface plane** (`WATER_HEIGHT`) so the meniscus, floaters, and ripples are the focal plane. *S·M*
- [x] **3. Pure orthographic plan view by default in pond mode.** Ortho (`top_down_ortho` ~455) removes perspective foreshortening so formations read as true geometry. Make it the default projection when entering pond mode. *S·M*
- [x] **4. Smooth zoom that keeps the pattern centered.** `set_camera_ortho_size()` (~400, clamp 2–80) should zoom about the school's centroid, not the tank center, so the kaleidoscope stays framed as you pull in/out. *M·M*
- [x] **5. Gentle overhead drift instead of orbit.** Auto-orbit is disabled for ortho (~457). Replace with an optional slow **vertical-axis spin** (rotate yaw only) so the mandala turns slowly under a still camera — mesmerizing, and only meaningful from above. *S·M*
- [x] **6. Square the viewport / vignette for the "looking into a bowl" feel.** An optional circular/rounded mask + soft vignette frames the tank like a pond seen through its rim — sells the metaphor. *S·M*
- [x] **7. Top-down light rig.** Push key light from straight above in pond mode so fish are lit on their dorsal surface (how you actually see pond fish) and cast crisp shadows down (feeds §I). *M·M*
- [x] **8. Surface reflection pass for plan view.** From above you'd see sky/room reflected on the water. Add a light reflective term to the surface shader in pond mode so the water reads as a *mirror* the fish swim under. *L·M*
- [x] **9. Auto-pick the prettiest moment for an overhead "establishing" beat.** On entering pond mode, ease to the framing where the school is most polarized/grouped. Ties to the cinematography idea but cheap here. *M·M*
- [x] **10. Per-tank-shape overhead framing.** Cylinder/sphere/hex tanks read very differently from above. Tune the ortho size + center per `tank_shape` so a round tank fills the circular frame. *S·M*

---

## B. The water surface as a canvas (only reads from above)

The surface is the single biggest under-used top-down spectacle. Couple it tightly
to motion so the pattern on the water *is* the fish.

- [x] **11. Persistent V-wakes behind moving fish.** `spawn_burst_ripple()` (~5482) only fires on darts. Add a continuous **wake trail** — a faint V opening behind any near-surface fish, scaled by speed — so from above you read trajectories as wakes. *M·L*
- [x] **12. Ripple intensity ∝ speed + turn.** A hard turn or a burst should throw a bigger ring than a cruise. Drive `spawn_burst_ripple` intensity from `speed` and yaw-rate (both already computed ~5627). *S·M*
- [x] **13. Interference patterns from multiple fish.** When several fish ripple near each other, let rings overlap/add (the surface_ripple shader already layers). A busy school becomes a shimmering interference field from above. *M·M*
- [x] **14. Surface dimples that track sub-surface fish.** Even fish a little below the surface should pull a subtle dimple/bulge directly above them (pressure wake), so the surface *betrays* the school's position from above even when they're not breaking it. *M·L*
- [x] **15. Floaters part and bob as the shoal passes beneath.** `_drift_floaters()` (~1084) has `ripple_bob`; add a downward-current shove when fish pass under, so duckweed visibly *opens a lane* — gorgeous from above and physically true. *M·L*
- [x] **16. Feeding-frenzy surface boil.** At a tap-feed, the converging school should churn the surface (dense overlapping rings + floater scatter). The frenzy reads as a *boil* on the water — the classic pond-feeding shot. *M·M*
- [x] **17. Calm-water glass when the tank is at rest.** When motion is low (night/rest), let the surface settle to near-mirror so stillness is visible as *flat water* — the contrast makes the active moments pop. *S·M* — `TopdownMotion.surface_calm_factor` → `water.gdshader` `pond_calm` damps waves; wired from `world._tick_topdown_surface`.
- [x] **18. Rain-style surface tap feedback.** Player taps on the water (in pond mode) ripple out (`spawn_glass_tap_ripples` ~5520 already does concentric rings) and fish react beneath — direct, satisfying overhead interaction. *S·M*
- [x] **19. Wind ripples drifting across the whole surface.** A slow directional micro-ripple field (reuse the floater `surface_drift_vec`) so the water always has gentle life from above, even with no fish near the top. *M·M*
- [x] **20. Surface tint/sheen reacts to tank health.** From above, a thriving tank's surface is clear and bright; a stressed one duller/filmed (ties to the legibility pillar — the surface becomes a glanceable health read in pond mode). *M·M* — `health_surface_tint` → `pond_health_gloss` + reflection mix.

---

## C. General motion realism in the XZ plane (read from above)

From above, the *path* is everything. Make trajectories curve, carry momentum, and
breathe — the base motion that every other section rides on.

- [x] **21. Banked turns that read as arcs.** Banking exists (`centripetal_bank` ~5632) but tune it so turns trace smooth **curved paths**, not polyline kinks — radius scales with speed (fast fish sweep wide, slow fish pivot tight). The core top-down beauty. *M·L*
- [x] **22. Momentum & coast tails.** `coasting` (~5513) + drag now exist; tune so a fish that stops *glides* to a halt and a fast fish *overshoots* slightly on a turn — paths get inertial weight instead of snapping. *M·L*
- [x] **23. Speed-dependent turn radius (no pivoting in place).** Cap `max_turn_rate` (~1156) more aggressively at high speed so a sprinting fish *can't* spin on a dime — it must carve. Reads as real fish physics from above. *M·M*
- [x] **24. Burst→glide rhythm in cruising.** Many fish swim in pulses (kick, glide, kick). Add a gentle burst→glide cadence to cruise speed so paths have a *pulse* visible as rhythmic spacing from above. *M·M*
- [x] **25. S-path wander instead of straight lines.** `heading_offset` wander (~4713) is fine but reads straight-ish. Bias it into gentle serpentine S-curves so idle swimming draws flowing lines, not rulers. *S·M*
- [x] **26. Wider, lazier home-drift loops.** `home` drift every 30–60s (~4739) — shape the patrol into smooth looping circuits around `home_x/z` so each fish traces a readable territory loop from above. *M·M*
- [x] **27. Turn anticipation lean.** Before a turn, a tiny counter-rotation (like a real fish loading the turn) makes direction changes read as *intentional* from above, not instant. *S·M*
- [x] **28. Differentiate locomotion types in plan view.** The taxonomy (anguilliform/thunniform/etc.) only changes the wag today. Make it change the *path*: eels weave tight sinusoids, tuna draw long straight runs with wide turns — legible signatures from above. *M·L*
- [x] **29. Speed variety across the school.** A monospeed school looks mechanical from above. Add per-fish speed personality (bold/timid, runt/alpha) so the flock has natural internal velocity spread. *S·M*
- [x] **30. Collision-graceful weaving.** When two paths cross, let fish *weave* (one dips, one rises, both bank) rather than hard-avoid — from above this reads as elegant traffic, not bumper cars. Builds on `_local_clearance_push` (~2939). *M·M*

---

## D. Schooling shapes & flock dynamics from above

The school is a 2D organism in plan view. Give it the murmuration behaviors that
only resolve as a *shape* from overhead.

- [x] **31. Polarization as a readable state.** When aligned, the school should form a tight oriented arrow; when relaxed, a loose blob. Surface alignment strength (`ali` ~6098) into a visible **polarization** that swings over time — the murmuration breathing. *M·L*
- [x] **32. Density waves through the shoal.** A disturbance at one edge should ripple as a *compression wave* across the school (neighbors propagate the squeeze). The hallmark of real flocks, stunning from above. *L·L*
- [x] **33. Split and merge.** Let the school occasionally **fission** into two sub-shoals that orbit and **re-merge** (an obstacle or predator splits them). Dynamic topology is the difference between "a school" and "a living school." *L·L*
- [x] **34. Edge shimmer / boundary churn.** Fish at the school's perimeter jockey inward (safer center) producing constant edge motion — the shimmering rim of a baitball, a pure top-down read. *M·M*
- [x] **35. The vacuole — open the center.** Use the formation slot ring (`slot_r` ~6129) to occasionally hollow the school into a torus/donut (predator-response shape) — instantly recognizable from above. *M·M*
- [x] **36. Leader-front, follower-fan.** `lead_score` leader tracking (~6145) — shape it so the school fans *behind* the leader into a teardrop/comet, the natural directional form seen from above. *M·M*
- [x] **37. Milling circle when idle.** With no goal, schools mill in a slow rotating ring (real fish do this). A self-organizing **mill** is the single most iconic top-down shoal shape. *M·L*
- [x] **38. Coordinated direction reversals as a group.** The whole shoal occasionally reverses its mill or sweep together — a satisfying group U-turn that reads as one organism flipping. *M·M*
- [x] **39. Mixed-species layering reads as color zones.** Different `preferred_y` species stack in depth; from above they overlap as translucent **color bands** — tune species spread so a community tank reads as a layered mandala. *M·M*
- [x] **40. Stress contracts, calm expands.** Tie school tightness to the affect layer: a stressed tank balls up tight; a serene one spreads loose and grazing. The flock's *shape* becomes a mood read from above (ties to legibility pillar). *M·M*

---

## E. Synchronized turns & "the flash" — the guppy-pond signature

The single most beautiful top-down event: the whole school turns at once and
*flashes*. This barely exists today. Make it a centerpiece.

- [x] **41. Propagating synchronized turns.** A turn initiated by one fish (or the leader) **propagates** through neighbors with a few-ms delay, so a turn sweeps across the school like a wave rather than all-at-once. The murmuration turn. *L·L*
- [x] **42. The silver flash.** When fish turn broadside to the overhead light at once, spike their dorsal/lateral specular for a frame — the school *flashes* silver on a synchronized turn. Iconic, and only visible from above. *M·L*
- [x] **43. Startle ripple → coordinated bolt.** `_startle` already propagates a heading (GOALS A#8). Shape it into a **radial bolt** outward from the scare point that then re-coheres — the panic-and-reform that defines a baitball from above. *M·L*
- [x] **44. Flash on the beat (dance hook).** During music, trigger the synchronized-flash turn *on the downbeat* so the school visibly "hits" the beat with a body-wide glint — the dance's biggest top-down payoff (links §H). *M·L*
- [x] **45. Tunable turn-sync tightness.** A school of disciplined tetras flashes crisply; loose guppies ripple raggedly. Expose a per-species/per-school sync tightness so different stock *flash* differently. *S·M*
- [x] **46. Direction-flip cascades.** Chain several propagating turns into a back-and-forth shimmer (left-flash, right-flash) — the hypnotic oscillation of a tight shoal under threat or excitement. *M·M*
- [x] **47. Predator-driven wave (if predators present).** A hunting fish entering the shoal triggers the bend-around-the-predator flow (the school parts and re-forms behind it) — the textbook predator-prey shape from above. *L·L*
- [x] **48. Edge-triggered turns at walls.** When the mill nears the glass, the turn-away propagates as a wave along the school edge, not a simultaneous bounce — natural boundary behavior overhead. *M·M*
- [x] **49. After-flash settle.** Post-flash, the school should briefly tighten then relax (adrenaline settle) so the event has a *shape over time*, not a single frame. *S·M*
- [x] **50. Flash intensity ∝ how synchronized.** The more polarized the turn, the brighter the flash — rewarding tight schooling with the prettiest payoff and teaching the player that calm, grouped fish look best. *S·M*

---

## F. Dancing: horizontal moves that read from above

The move library exists but is view-agnostic. Promote/adapt the moves that read
in plan view; quietly retire the ones that don't.

- [x] **51. Cast moves by camera angle.** When the camera is overhead, bias `pick_move()` (~89) toward **horizontal** moves (spiral, vortex, carousel, starburst, sweep, wave) and away from vertical ones (curtain, cascade, fountain). The single highest-leverage top-down dance fix. *M·L*
- [x] **52. Adapt vertical moves into planar twins.** `fountain` (vertical spray) → **radial bloom** on the XZ plane; `curtain` (rise/fall) → **expanding/contracting ring**; `cascade` → **rotating pinwheel**. Same musical trigger, top-down-legible geometry. *M·L*
- [x] **53. The mandala move.** A new move: fish arrange into a rotating radial-symmetry pattern (petals around a center) that morphs its petal count with energy. A kaleidoscope — the definitive top-down dance. *L·L*
- [x] **54. Spiral that visibly tightens and unwinds.** `spiral` (~542) already tightens with phrase; make the radius modulation dramatic so from above it reads as a clear winding/unwinding galaxy keyed to BUILD/DROP. *M·M*
- [x] **55. Counter-rotating rings.** Split the school into two concentric rings spinning opposite directions (use the `choir` halves ~142). Mesmerizing from above and impossible to read from the side. *M·L*
- [x] **56. Expanding/contracting "breathe" on the plane.** `breathe` (~575) is radial+vertical; make a pure-horizontal variant — the school inhales to a dot and exhales to a wide disc on the bar. Reads as a pulsing iris from above. *M·M*
- [x] **57. The sweep as a sheet across the pond.** `sweep` (the primary move) should read as a **band of fish gliding across the surface** L→R on the phrase — a clean horizontal wipe in plan view. *S·M*
- [x] **58. Vortex as a true top-down whirlpool.** `vortex` (~546) — emphasize the rotational XZ component over the vertical column so from above it's a spinning whirlpool with a clear eye. *M·M*
- [x] **59. Trails during dance moves.** Briefly enable motion trails (surface wake §B or a faint ribbon) during dance so the moves *draw* their geometry on the water — a spiral leaves a visible spiral. *M·L*
- [x] **60. Move legibility scoring.** A tiny helper that rates each move's top-down legibility and lets the conductor prefer high-scoring ones when overhead — so the system self-selects for the view. *M·M* — `MOVE_LEGIBILITY` + weighted `pick_move_overhead`.

---

## G. Dancing: formations & geometry on the XZ plane

The 8 formations are mostly 2D curves — they're *made* for top-down. Tune,
morph, and cast them so the overhead view gets clean, evolving geometry.

- [x] **61. Formations are top-down gold — feature them.** `heart`, `star`, `ring`, `circle`, `v` (`formation_offset` ~204) are XZ curves that read perfectly from above and poorly from the side. In pond mode, bias `pick_formation()` (~117) toward these. *S·L*
- [x] **62. Smooth morphing between formations.** Transition `scatter → circle → star` by lerping slot targets over a bar, so the school *flows* between shapes instead of teleporting — the formation change becomes the spectacle. *M·L*
- [x] **63. Symmetry-locked formations.** Snap formations to true radial/bilateral symmetry about the tank center so from above they're crisp geometry, not approximate blobs. Use more slots for bigger schools. *M·M*
- [x] **64. Scale formations to school size.** 24 slots (~204) is fixed; a 40-fish shoal should fill a bigger, denser star. Make slot count + radius scale with population so the pattern always fills the frame. *M·M*
- [x] **65. "Visual EQ" reads as a 2D pattern from above.** Band casting (`assign_music_role` ~361: bass/mid/treble by column + color) already exists. From above, place bass fish at the **center**, treble at the **rim**, so the frequency spectrum becomes a radial color map that pulses with the music (the playbook's visual-EQ idea, in plan view). *M·L*
- [x] **66. Color-sorted formations.** Sort slots by `base_color` hue so the formation reads as a **color wheel / gradient** from above — a school of mixed guppies becoming a literal color mandala. *M·M*
- [x] **67. Size-graded rings.** Big fish outer, small fish inner (or vice-versa) so formations have a clean size gradient — strong top-down structure from the existing size data. *S·M*
- [x] **68. Antiphonal formation halves.** The `choir` split (~142) — give each half its own sub-formation that answers the other (one rings clockwise as the other blooms), so the call-and-response is *spatial* and visible overhead. *M·M*
- [x] **69. Soloist takes the center spotlight.** `is_soloist` (~151) during CHORUS — pull the soloist to the formation's center and let the corps orbit it. From above the spotlight is literal and obvious. *M·M*
- [x] **70. Negative-space formations.** Some formations should be defined by the *gap* (a ring with an empty eye, a crescent) — open shapes read beautifully against the sandbed from above. *M·M*

---

## H. Beat / phrase / musical structure → top-down motion

The plumbing is rich (beat/bar/phrase) but the *musical structure* (key/scale,
bar-level timing) is computed and unused. Wire it to spatial pattern, optimized
for what the overhead viewer perceives.

- [x] **71. Beat-synced synchronized turns.** The biggest win: fire the propagating turn + flash (§E) on the **downbeat** (`downbeat` flag ~472). The school *hits* the beat with a body-wide glint — the top-down dance signature. *M·L*
- [x] **72. Phrase changes drive formation morphs.** On phrase transition (VERSE→BUILD→DROP, `arc_intensity` ~54), morph the formation (§62). DROP = explode `scatter`→`starburst` outward; BREAKDOWN = collapse to a tight `circle`. Phrase structure becomes visible geometry. *M·L*
- [x] **73. The DROP = radial burst (made for above).** A DROP currently scatters; make it a **synchronized radial explosion from the centroid** — every fish bolts outward then re-coheres. The most satisfying possible top-down drop. *M·L*
- [x] **74. BUILD = converge + tighten the spiral.** During BUILD, wind the school inward into a tightening spiral/ball so tension is *spatial* — the viewer feels the drop coming because the pattern is coiling. *M·M*
- [x] **75. Bar-level coordination (close the gap).** `phrase_bars_left` (~476) is available but unused. Use it so formation morphs *complete* exactly on the phrase boundary (a star fully formed on the downbeat of the drop) — tight, intentional choreography. *M·L* — `TopdownMotion.formation_morph_blend` in `music_context._update_phrase_choreography`.
- [x] **76. Key/scale → spatial pattern (the unused bridge).** `key`/`mode` (~529, ambient ~776) feed only color today. Map them to *geometry*: major → open expansive formations, minor → tight inward ones; key → rotation direction or symmetry order. Harmonic context finally moves the fish. *L·M*
- [x] **77. Tempo → mill speed & turn cadence.** Faster tempo = faster mill rotation and crisper, more frequent synchronized turns. The overhead pattern's *pace* should obviously track BPM. *S·M*
- [x] **78. Bass → expansion, treble → shimmer.** Bass pulses push the formation's radius (the disc throbs); treble drives edge-shimmer/flashes. From above, you *see* the frequency bands as size vs. sparkle. *M·M*
- [x] **79. Valence → formation choice.** Happy/major tracks → hearts, stars, blooms; dark/minor → vortex, tight rings. `valence`/`danceability` already classify genre (~69); route them to the top-down-legible formation set. *S·M*
- [x] **80. Swing/groove → path curvature.** Apply the existing swing offset (~141) to path shape so a grooving track makes the school *sway* in loose S-curves rather than march — groove you can read from above. *M·M*

---

## I. Surface, floater & shadow choreography (the pond extras)

Two more canvases the overhead viewer sees: the *surface* and the *shadows on the
floor*. Make them dance too.

- [x] **81. Lift the fish-shadow cap (8 → many).** `blob_shadow_points[8]` (~42, refreshed ~923) shows only 8 fish shadows — a hard limit on the top-down floor pattern. Move shadows to a MultiMesh/quad approach (like floater shadows, `FLOATER_SHADOW_CAP 64`) so the *whole* school casts a shadow mandala. *M·L*
- [x] **82. Choreograph the shadow layer.** With shadows uncapped, the sandbed shows a second, darker copy of the dance. Tune shadow softness/opacity by depth so the floor pattern is its own beautiful read beneath the fish. *M·M* — `blob_shadow_gain` + height penumbra in `substrate_caustic.gdshader`; motion-driven gain from `world._tick_topdown_surface`.
- [x] **83. Caustics pulse to the beat.** `caustics.gdshader` is coupled to surface waves; add a beat-driven brightness/scale pulse so the dancing light on the floor *throbs* with the music — the whole pond floor becomes a visualizer. *M·L*
- [x] **84. Surface ripples on the downbeat.** Spawn a tank-wide concentric ripple from the center on big downbeats/drops (reuse `spawn_glass_tap_ripples` ~5520) so the *water itself* hits the beat from above. *M·M*
- [x] **85. Floaters choreograph too.** Let dance moves nudge floaters into the pattern (a spiral of fish drags duckweed into a faint spiral). The surface plants become a slow, soft echo of the dance. *M·M*
- [x] **86. Bioluminescent wakes at night.** In a dark/night pond mode, fish leave glowing trails on the surface (night bioluminescence already exists) — a long-exposure light-painting of the dance from above. *L·L*
- [x] **87. Shadow-flash inversion.** When the school flashes silver (§42), their shadows briefly sharpen/darken in sync — the floor flashes dark as the fish flash bright. A two-layer top-down beat-hit. *M·M* — `blob_shadow_flash` driven by `sim.topdown_shadow_flash()`.
- [x] **88. Color spill onto the water.** Vivid schooling fish cast a faint color tint onto the surface/floor directly above/below them so a red shoal warms the water it's under — subtle, painterly, top-down-only. *M·M*
- [x] **89. Feeding ring on the surface.** A tap-feed in pond mode drops a visible food-cloud ring on the surface that the boil (§16) disperses — the interaction and the reaction both live on the top-down canvas. *S·M*
- [x] **90. Rest = still water, still shadows.** At night/rest, ripples flatten, shadows settle, caustics calm — the pond visibly sleeps from above, making the contrast with the dance dramatic. *S·M* — shared `pond_calm` / `shadow_calm` from motion energy + night.

---

## J. Performance, capture & the pond-mode experience

Make it cheap, make it shareable, make it discoverable.

- [x] **91. LOD tuned for the overhead distance.** The top camera sits far back (`radius *3.4` ~318). Ensure `visibility_range_end` LOD (fish.gd ~2303) keeps fish bodies readable as *silhouettes* at that distance — detail you can't see from above is wasted cost. *M·M*
- [x] **92. Batch the shadow + ripple layers.** Uncapped shadows (§81) and many wakes (§11) must be MultiMesh-batched so a 40-fish pond dance holds frame budget. Reuse the floater-shadow batching pattern. *M·M*
- [x] **93. Silhouette-first readability.** From above you mostly read the *outline* + color. Verify dorsal coloration and body silhouette are distinct per species so a top-down community tank is legible at a glance. *M·M*
- [x] **94. A top-down photo/postcard mode.** One-tap beauty capture of the overhead pattern (mandala, flash, formation) — the most shareable shots the game can produce. Reuse the F12 photo path. *M·M*
- [x] **95. Overhead time-lapse / dance recorder.** Capture a phrase of dancing from above as a short loop (the existing WAV/record infra + frame capture) — a guppy-pond mandala in motion is the hero marketing asset. *L·M*
- [x] **96. "Conduct" gestures from above.** In pond mode, let the player draw a path/shape on the surface that the school follows or forms — direct top-down choreography. Ties to `MusicContext.conduct()` (~76). *L·L*
- [x] **97. Mobile pond mode.** Pinch-zoom + one-finger pan over a top-down ortho view is a natural, gorgeous mobile experience — make pond mode a first-class touch layout. *M·M*
- [x] **98. Pond-mode lighting/ambient preset.** Pair pond mode with a calm ambient-audio bias + warm overhead light so entering it *feels* like sitting over a pond — multi-sensory, not just a camera angle. *S·M* — overhead key light in `_apply_pond_visuals` + `ambient_audio` pond volume lift.
- [x] **99. Onboard the view.** A one-time hint when the player first hits the top preset: "Try playing music — the school dances best from up here." Points players at the payoff (ties to the onboarding pillar). *S·M*
- [x] **100. Make calm beautiful from above too.** The reward for a balanced, well-stocked tank should be a serene, slowly-milling, gently-rippling overhead pattern even with no music — so pond mode is lovely at rest, not only during a drop. The serenity payoff, in plan view. *M·M*

---

## If Cursor only does five (the top-down spine)

1. **#51 + #52** — **cast/adapt dance moves by camera angle** so the overhead
   viewer always gets horizontal choreography. Instantly fixes the "the dance is
   invisible from above" problem with the move library that already exists.
2. **#41 + #42 + #71** — **propagating synchronized turns + the silver flash, on
   the beat.** The guppy-pond signature and the single most beautiful top-down event.
3. **#11 + #12 + #15** — **surface wakes + ripples scaled to motion + floaters
   parting.** Turns the water itself into the canvas that only reads from above.
4. **#81 + #82** — **lift the 8-shadow cap and choreograph the floor.** Unlocks the
   second pattern (shadows on the sandbed) that defines the overhead read.
5. **#73 + #72** — **the DROP as a radial burst + phrase-driven formation morphs.**
   Makes musical structure visible as evolving geometry from above.

Then layer §A (pond mode camera), §D (flock shapes), §G (formation geometry),
§I (caustics/shadow choreography), §J (capture + polish).

---

## Manual QA checklist

- Enter pond mode, play a track with a clear drop → the school morphs through
  formations, tightens on BUILD, **bursts radially + flashes on the DROP**, all
  legible from straight above.
- With no music, a healthy tank shows a slow milling ring, gentle wakes, and a
  calm rippling surface — serene from above.
- Trigger a startle → a radial bolt propagates outward and the school re-coheres
  (not an instant all-fish teleport).
- A 40-fish shoal in pond mode holds frame budget (shadows + wakes batched, LOD on).
- Synchronized turns produce a visible silver flash *and* a matching shadow-darken
  on the sandbed.
- Floaters visibly part into a lane as the shoal passes beneath them.
- Top-down photo capture produces a clean, symmetric mandala shot.
