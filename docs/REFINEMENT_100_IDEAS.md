# The Refinement Pass — 100 items. Nothing new. Everything better.

*Drafted 2026-07-01. Replaces the "Spark" doc, which failed its own test: roughly a
third of it was new features wearing a polish costume (photo mode, god-ray motes,
seasonal drift, snail trails, lens droplets, "moments"). All of that is cut. The
rule for every item below: **it must make something that already exists look right,
move right, or cost less — with zero loss of behavior, style, or life.** If an item
can be described as "add X," it didn't make the list.*

> **The proof this pass is needed — the plants aren't green.** Verified against the
> shipped palette on 2026-07-01: `planted_48.png` contains a beautiful 8-step green
> ramp at indices 8–15, in the **cool** bank. But `classify_bank()` in
> [`palette_quantize.gdshader`](../shaders-godot/godot-project/shaders/palette_quantize.gdshader)
> routes green-dominant pixels to the **neutral** bank (`if (g > b * 1.15) return 1;`)
> — and the neutral bank (16–31) contains **zero greens**: browns 16–23, bluish grays
> 24–31. With `palette_bank_lock` defaulting to 1.0, every saturated leaf pixel is
> quantized to mud or gray. The greens the palette was built around are unreachable.
> That is a one-line-class bug that has been silently degrading every planted tank —
> and it's exactly the kind of thing this doc hunts: not missing features,
> **existing beauty being lost in the pipeline.**

**Format:** house style. **Effort** S (≤2h) / M (half-day) / L (full day+).
**Impact** S / M / L. Every visual item should be verified by eye against a
reference tank save *and*, where possible, pinned by a headless smoke so it can't
regress again. Perf items are **lossless by definition**: same sim results, same
picture, fewer milliseconds.

---

## A. Color fidelity — things must look like what they are

*The quantize pipeline is the last thing every pixel passes through. Bugs here
degrade everything upstream. Verified findings first.*

1. **Fix the green misroute (THE bug).** In `classify_bank()`, the final
   green-dominant rule returns bank 1 (neutral — no greens) instead of bank 0
   (where greens 8–15 live). Saturated greens (sat ≥ ~0.25) must go to bank 0;
   only truly desaturated olives belong in neutral. Plants become plants again.
   *Effort S, Impact L.*
2. **Re-audit the bank layout against the classifier's contract.** The comment
   says cool/neutral/warm, but index 38 (emerald green) and 39 (blue) sit in the
   *warm* bank, and 33–34 are icy blues also in warm — unreachable by any pixel
   the classifier sends there. Either move them home or teach the classifier the
   truth. *Effort M, Impact M.*
3. **Reclaim the warm bank's wasted slots.** Warm holds white (32), two icy blues
   (33–34), four browns (42–45) that duplicate the neutral ramp, and black (46) —
   leaving fauna exactly **one** slot each for red/orange/yellow/blue/purple/pink.
   Fish posterize to ~7 hues. Rebuild the bank as 2–3 value steps per fauna hue
   using the reclaimed slots. Same 48 colors total, same style, far more faithful
   fish. *Effort M, Impact L.*
4. **Pin plant-green with a smoke.** Headless test: push a set of leaf-green
   swatches through the quantize path (bank classify + nearest-pair) and assert
   the output hue stays in 90–165°. The regression that shipped can never ship
   again. *Effort S, Impact L.*
5. **Neutralize the "gray" ramp.** Grays 24–31 are all hue-240 (blue-tinted), so
   every shadow and stone cools toward steel. Pull them to true neutral or a
   barely-warm gray so substrate shadow reads earthen, not lunar. *Effort S,
   Impact M.*
6. **De-duplicate the two brown ramps.** Neutral 16–23 and warm 42–45 are nearly
   the same browns. Eight slots doing four slots' work — collapse and hand the
   freed slots to #3. *Effort S, Impact M.*
7. **Stop double-touching saturation in the post pass.** The quantizer bakes a
   global `sat 1.08` + `brightness 1.04` on every frame (lines ~181–182) *on top
   of* the palette LUT that was authored for the final look. Fold it into the LUT
   and delete the per-fragment math — one source of color truth. *Effort S,
   Impact S.*
8. **Verify midday tint is identity.** `palette_tint` multiplies the source
   before quantize, driven from day-phase in main.gd. Assert it hits exactly
   (1,1,1) at midday so the "neutral" hour actually is — any residual tint biases
   every bank decision. *Effort S, Impact S.*
9. **Check the chronic-health drain.** `health_grade < 1` desaturates and cools
   the whole frame (stress·0.28 desat). If typical tanks idle at 0.8–0.9, the
   entire game is living 3–6% duller than authored. Log the live value; if it
   never reaches 1.0 in a healthy tank, recalibrate the mapping. *Effort S,
   Impact M.*
10. **Warm fixture wash yellows the greens.** `tank_fixture_glow` adds
    (1.0, 0.94, 0.82) and multiplies up to ~2× on foliage tops
    ([foliage.gdshader:93–99](../shaders-godot/godot-project/shaders/foliage.gdshader)) —
    high glow turns leaf green toward chartreuse. Rebalance the wash on high-sat
    green pixels (tint the *light* less, lift the *value* more). *Effort S,
    Impact M.*
11. **SSS rim color reads as dead leaf on plants.** The rim mixes toward
    (1.0, 0.92, 0.68) — warm straw — at up to 0.55. Real leaf transmission is
    yellow-*green*. Shift `sss_color` on foliage toward (0.85, 1.0, 0.55) and the
    backlit edge reads alive instead of dried. *Effort S, Impact M.*
12. **Retune bacterial-bloom green vs plant green.** The water-column bloom tint
    lerps toward green, which perceptually *steals* green from the plants behind
    it. Pull bloom toward a grayed pea-soup so plant foliage stays the greenest
    thing in frame. *Effort S, Impact S.*
13. **Tannin ceiling check.** Tannins clamp at 0.65 and only accumulate from
    driftwood leach — verify an old established tank doesn't sit permanently near
    the clamp, tea-staining everything forever. If it does, add the slow decay the
    chemistry already implies (water changes should pull tannins down). *Effort S,
    Impact M.*
14. **Delete or wire the dead vibrancy path.** `apply_vibrancy()` early-returns at
    vib ≤ 1.001 and foliage defaults to exactly 1.0 — the uniform is dead weight
    on every leaf fragment. Either drive it (healthy plants slightly > 1) or
    remove it. *Effort S, Impact S.*
15. **Night greens: verify the handoff.** `planted_48_night` has proper moonlit
    sea-greens at 8–15 (verified) — but they're only reachable after #1 lands.
    Confirm the night tank's plant mass reads deep-green, not gray, once the bank
    fix is in. *Effort S, Impact M.*

## B. Quantize & dither — the pass itself, made invisible

*The post pass should read as a style, never as an artifact.*

16. **Turn on the world-locked dither that's already built.** `dither_world_lock`
    exists (#26 in the aesthetics pass) and defaults to 0 — so the dither pattern
    crawls across every surface on camera pan. Wire `dither_world_origin` from the
    camera and flip the default. Built, dark, one flip. *Effort S, Impact M.*
17. **Stop outlines flickering on caustics.** The outline detector fires on luma
    discontinuities; animated caustic webs *are* luma discontinuities, so substrate
    edges shimmer with false strokes. Mask outline strength where the caustic
    contribution is high — the uniform is already in the frame. *Effort M,
    Impact M.*
18. **Soften bank-boundary banding.** With bank lock on, a gradient that crosses a
    bank edge (green plant into brown substrate shadow) snaps between banks with no
    dither bridge. Allow the runner-up candidate to come from the adjacent bank when
    the best match sits within ε of the boundary. *Effort M, Impact M.*
19. **Integer-scale the internal resolution.** 384×216 upscaled to a non-integer
    multiple shimmer-aliases the dither grid. Snap the display scale to integer
    multiples (or scale internal res to the nearest divisor of the window) so every
    source pixel is N×N screen pixels, always. *Effort M, Impact M.*
20. **Compile out the dormant sub-passes.** CRT, film grain, and selective glow
    branch per fragment even at strength 0. Split them into shader feature variants
    so the default frame pays zero for features that are off. *Effort M, Impact S
    (visual), M (perf).*
21. **HDR lift should keep the emissive's hue.** The overbright shoulder lerps hot
    pixels toward warm *white*, so blue-green bioluminescence blooms cream. Lift
    toward the source hue at high value instead — same punch, no hue theft.
    *Effort S, Impact M.*
22. **Smooth the night-blend curve.** `palette_night_blend` tracks inverted
    daylight linearly, holding dusk in a long gray in-between. A smoothstep on the
    blend keeps dusk *warm* longer, then commits to night — same LUTs, better hour.
    *Effort S, Impact M.*

## C. Water, light, glass — tune what's shipped

23. **One wave formula, one source.** The surface-wave math is duplicated between
    `water.gdshader` and the caustics/substrate shaders (the audit matched them by
    eye). Extract it into `palette_tint.gdshaderinc`-style include so the coupling
    can never silently drift — desynced waves vs caustics is a subtle wrongness
    players feel but can't name. *Effort M, Impact M.*
24. **Fade god-ray occluders in and out.** The ray shader tracks the 8 closest fish;
    when the 9th displaces one, its soft shadow pops. Fade occluder weight by
    distance rank instead of hard-swapping the slot. *Effort S, Impact S.*
25. **Scale surface-wave frequency to tank size.** The same wave wavelength on a
    nano tank and a 200-liter reads toy-like on one of them. Normalize wave scale
    by tank dimensions so water always looks tank-sized. *Effort S, Impact M.*
26. **Fade ripple sprites, don't pop them.** Surface-ripple overlays appear and
    vanish at full alpha at their lifetime edges. One smoothstep on birth/death.
    *Effort S, Impact S.*
27. **Dither the depth-fog bands.** The 6-band posterized depth fog shows clean
    terrace lines through open water where the blue-noise doesn't fully cover.
    Nudge band edges with the existing IGN noise so terraces dissolve. *Effort S,
    Impact S.*
28. **Meniscus corners.** The meniscus band rides only the top cap; the vertical
    glass edges end bare. Extend the existing contact band down the corner seams —
    same technique, complete edge. *Effort M, Impact S.*
29. **Calm the glass mirror at grazing angles.** The flipped-framebuffer
    "reflection" is most obviously fake when the camera sweeps low; scale
    `surface_reflection`/mirror strength down at grazing view so the trick only
    plays where it convinces. *Effort S, Impact M.*
30. **Level the underside mirror.** The total-internal-reflection ceiling effect
    (`underside_mirror 0.34`) competes with the fixture wash at some angles and
    double-brightens the surface from below. Balance the two against a reference
    save at three camera heights. *Effort S, Impact S.*
31. **Verify caustic intensity under stained water.** `modulate_caustic_intensity`
    floors at 0.70 — in heavy tannin+bloom the substrate can still look
    sun-drenched while the column reads murky, a mismatch. Lower the floor
    proportionally to transmittance so light and water agree. *Effort S, Impact M.*
32. **Room presets: match black points.** Some lofi room presets sit visibly
    brighter behind the tank than the tank's own night, silhouetting the glass
    wrong after dusk. Normalize preset ambient against the palette night LUT.
    *Effort M, Impact S.*

## D. Motion — the sim is 10 Hz; the eye must never know

33. **Interpolate creature transforms in `_process`.** Fish positions update at
    10 Hz; render at display rate by lerping previous→current tick states. This is
    the single largest *perceived* smoothness win in the codebase, costs almost
    nothing, and changes zero behavior. *Effort M, Impact L.*
34. **Cap rotational snap.** Fast behavior-tier switches (startle, chase) can flip
    heading hard in one tick; slerp the *visual* orientation with a max angular
    rate while the sim keeps its instant turn. Bodies stop teleport-twisting.
    *Effort S, Impact M.*
35. **Vary flutter per plant instance.** All foliage shares one `flutter_speed`
    uniform, so distinct plants flutter in suspicious unison. Derive a per-instance
    phase/speed jitter from world position (already available in the vertex
    shader) — same motion budget, no metronome. *Effort S, Impact S.*
36. **Ease spawn/despawn.** Creatures and food currently appear/disappear in one
    frame. A 200 ms scale/alpha ease on entry and exit — this is transition
    refinement, not a feature: the objects already come and go, they just do it
    rudely. *Effort M, Impact M.*
37. **Tune the follow-cam lag constants.** The cinematic lerp overshoots on fast
    fish and lags on slow drift; retune stiffness by target speed so the follow
    frame breathes with the fish instead of chasing it. *Effort S, Impact M.*
38. **Scale wag frequency to body size.** Tail-beat rate is near-uniform across
    sizes; big fish should beat slower (they already swim slower). One
    genome-driven multiplier in the existing wag path. *Effort S, Impact M.*
39. **Smooth the off-frustum re-entry.** A fish ticking at 5 Hz off-screen can
    re-enter the frustum mid-interpolation with a visible position correction.
    Snap its interpolation buffer on visibility change so re-entry is seamless.
    *Effort S, Impact S.*
40. **Ripple-driven surface normals.** The surface's vertex waves and the ripple
    sprites don't share normals, so ripples don't disturb the specular. Feed ripple
    positions into the existing wave normal calc (a few uniforms) so a feeding boil
    visibly bends the light it sits in. *Effort M, Impact M.*

## E. UI — the existing surfaces, made coherent

41. **Draw the HUD from the tank's palette.** Panels, chips, and toasts use ad-hoc
    grays that ignore the 48-color LUT the whole world obeys. Re-skin the existing
    controls with LUT colors — the UI joins the same picture. *Effort M, Impact M.*
42. **One toast discipline.** Toasts stack in inconsistent positions and can sit on
    top of follow-mode moments. Single queue, single corner, auto-defer while
    follow mode is active. Refinement of an existing system's manners. *Effort M,
    Impact M.*
43. **Ease every panel that already opens.** Panels/chips currently snap
    open/closed. 100–150 ms eased fades on the *existing* transitions. *Effort S,
    Impact S.*
44. **Idle-dim curve.** The HUD idle-dim steps rather than breathes; replace with a
    slow ease and a faster wake. Constants only. *Effort S, Impact S.*
45. **Live-preview the light panel.** Light-panel sliders apply on release rather
    than continuously in some paths; make every lighting slider preview live while
    dragging — the panel already exists, it should feel like touching the light.
    *Effort M, Impact M.*
46. **Consistent list edge fades.** `list_edge_fade.gdshader` exists but is applied
    to some scrolling lists and not others. Apply uniformly. *Effort S, Impact S.*
47. **Save-slot thumbnails from the real tank.** The menu shows a placeholder
    shader; `capture.gd` already exists — capture on save so the slot shows *your*
    tank. Wiring two existing systems together, not a feature. *Effort M,
    Impact M.*
48. **Type scale audit.** Font sizes/weights across HUD, panels, and chat drifted
    across passes; one pass to a 4-step scale. *Effort M, Impact S.*

## F. Performance — render path (lossless, same picture)

49. **Per-instance color instead of per-color materials.** Move fauna albedo into
    `INSTANCE_CUSTOM` and read it in `voxel.gdshader` — the 800-entry
    `ShaderMaterial` cache in [`voxel_mat.gd`](../shaders-godot/godot-project/scripts/voxel_mat.gd)
    and its LRU eviction vanish; every fish color change becomes a float write.
    *Effort L, Impact L.*
50. **Fix the duplication churn.** [fish.gd:~3014–3024](../shaders-godot/godot-project/scripts/fish.gd)
    duplicates a ShaderMaterial on **every** biolum/belly-flash/stress toggle —
    exactly when the tank is most dramatic. Duplicate once per fish, cache, then
    only `set_shader_parameter`. *Effort S, Impact L.*
51. **Waste particles → one MultiMesh.** Up to 240 `MeshInstance3D` nodes for
    waste; collapse to a single MultiMesh with a packed position array. ~239 fewer
    nodes and draw calls, identical pixels. *Effort M, Impact M.*
52. **Bubbles → MultiMesh.** Same treatment. *Effort S, Impact S.*
53. **Blob-shadow array → data texture.** The 32-entry uniform array loop in
    `substrate_caustic.gdshader` is per-fragment cost on Metal; pack points into a
    small texture, one fetch. *Effort M, Impact M.*
54. **Bake the Worley caustics.** Cellular noise is computed per fragment in two
    shaders every frame; bake to a small tileable scrolling texture sampled twice.
    Visually identical (verify A/B), dramatically cheaper. *Effort M, Impact L.*
55. **Global shader uniforms for atmosphere.** [world.gd:~481–526](../shaders-godot/godot-project/scripts/world.gd)
    pushes ~15–30 uniforms per tick across materials; move shared atmosphere values
    (daylight, tint, transmittance, fixture glow) to RenderingServer global
    parameters — one write each, every shader reads. *Effort M, Impact M.*
56. **Dirty-flag the uniform pushes.** Most atmosphere values change slowly; skip
    writes when unchanged past epsilon. *Effort S, Impact S.*
57. **Shader precompile on load.** First bioluminescent fish / first ripple hitches
    on shader compile; warm all variants during the load screen. *Effort M,
    Impact M.*
58. **Adaptive internal resolution.** The quantize pass is the heaviest fragment
    work; auto-scale `internal_resolution` to hold frame budget — the pixel-art
    upscale makes the change literally invisible (it's already 384×216 by design).
    *Effort M, Impact M.*
59. **Tight AABBs on MultiMesh batches.** Verify custom AABBs so fauna/plant
    batches actually frustum-cull when zoomed in. *Effort S, Impact S.*
60. **Pool ripples and boils.** Pearling already pools 22 emitters; extend the same
    pool pattern to ripple/boil spawners so effects stop allocating nodes.
    *Effort S, Impact S.*
61. **Floater drift → vertex shader.** Floater bob/drift is CPU-maintained per
    frame in world.gd's microfauna cadence; the flow uniforms it needs already
    exist in the foliage shaders. Move it to GPU like the sway already is.
    *Effort M, Impact M.*
62. **One maintenance walk.** Biofilm, mineral spots, mulm, film, and microfauna
    each run their own timer scan in `world.gd`; merge into one scheduler pass on
    one cadence. *Effort M, Impact S.*

## G. Performance — sim path (lossless, same results)

63. **Grid the snail-predation search.** Hunters walk `snails_root.get_children()`
    per hungry tick ([fish.gd:~4450](../shaders-godot/godot-project/scripts/fish.gd)) —
    the first thing to fall over past ~50 snails. Use the existing spatial grid.
    *Effort M, Impact M.*
64. **Reuse neighbor-query buffers.** `_spatial_query` allocates a fresh Array per
    fish per tick ([sim_driver.gd:~3289](../shaders-godot/godot-project/scripts/sim_driver.gd));
    reuse a scratch buffer. Steady-state GC pressure → zero. *Effort M, Impact M.*
65. **Throttle waste/algae grids to 2 Hz.** They rebuild at 10 Hz; waste barely
    moves in 100 ms. Plants grid already proves the pattern at 2 Hz. *Effort S,
    Impact M.*
66. **Incremental neighbor grid.** Move entries between cells on position change
    instead of full rebuild per tick. *Effort M, Impact M.*
67. **Stagger brain ticks.** Round-robin fish cognition across sim ticks (each fish
    still minds at its full rate; the per-tick spike flattens). Wall-avoid stays
    every tick. *Effort M, Impact M.*
68. **Sleeping minds tick slow.** A sleeping fish runs full GWT competition every
    100 ms; 1 Hz is indistinguishable and frees real budget every night. *Effort S,
    Impact M.*
69. **Deepen mind LOD off-frustum.** 5 Hz off-screen brains already exist; also
    skip the felt-self/world-model sub-ticks for unseen fish, keeping drives +
    locomotion. No visible fish loses depth. *Effort M, Impact L.*
70. **Cache shared per-tick scalars.** Daylight, chemistry, O₂, `school_pulse`
    sin are recomputed per fish; compute once in `_tick`, pass down. *Effort S,
    Impact S.*
71. **Int-key the hot dicts.** `grudges`/`habituated` key by String id; entity ids
    are ints. The 5 s decay sweeps stop hashing strings. *Effort M, Impact S.*
72. **StringName the stringly paths.** Stats/situations/moods compare bare Strings
    across the bid/mood paths (ENGINEERING #17); `StringName` comparisons are
    pointer-fast. *Effort M, Impact M.*
73. **Cache the 255 autoload lookups.** `get_node_or_null("/root/X")` per call →
    typed refs in `_ready()` (ENGINEERING #11/#12 — already ledgered). *Effort M,
    Impact M.*
74. **Retire the 916 `has_method()` probes.** Typed interfaces per
    [ARCHITECTURE §7](ARCHITECTURE.md); dynamic probes in per-tick code are real
    cost and hide contract drift. *Effort L, Impact M.*
75. **Retire the 4,383 `.get("…")` reads.** Untyped property access is among
    GDScript's slowest ops and it's concentrated in the mind loop. Route through
    `MindState` fields (this *is* the 0E migration, measured in ms as well as
    hygiene). *Effort L, Impact L.*
76. **Static-type the hot functions.** Typed GDScript compiles to markedly faster
    bytecode; sweep `fish.tick`, `_motion_substep`, `_boids`, `SimDriver._tick`.
    Zero behavior change, free speed. *Effort L, Impact L.*
77. **Bucket the decay sweeps.** 30 fish decaying dicts on the same 5 s tick is a
    spike; stagger per-fish offsets. *Effort S, Impact S.*
78. **Per-species constants to flat arrays.** Diet gates, speed caps, thresholds
    resolved from dicts per tick → precompute at spawn into typed fields.
    *Effort M, Impact S.*
79. **Coalesce `stats_changed`.** Emit once per tick with a change mask instead of
    per-mutation; main.gd's HUD handler runs once. *Effort S, Impact S.*
80. **Analytic 16× fast-forward.** At high time-scale, integrate chemistry
    closed-form per batch instead of ticking 16× as often — identical curves,
    1/16 the work. *Effort L, Impact M.*
81. **Analytic away catch-up.** Same trick for the away-gap on load: integrate
    hours of chemistry/growth analytically instead of replaying ticks; the recap
    reads the same state either way. *Effort L, Impact M.*
82. **Thread the brains.** Fish cognition within a tick is independent by design;
    `WorkerThreadPool` with fixed fish order and post-join event merge keeps
    determinism. The single biggest CPU multiplier available in-engine.
    *Effort L, Impact L.*
83. **Async, double-buffered saves.** Snapshot state, serialize on a worker
    thread; autosave becomes unfeelable. *Effort M, Impact M.*
84. **Progressive load.** Build environment first frame, stream creature spawns
    over the next second — kills the load hitch, same tank. *Effort M, Impact S.*

## H. The impossible tier — same behavior, different engine underneath

*These are reimplementations, not features. The contract: bit-identical (or
eval-verified-identical) sim results, an order of magnitude in headroom.*

85. **Reactivate `sim-rust/` as a GDExtension core.** It's parked reference-only
    (ADR 001), but chemistry + locomotion inner loops behind the same `tick()`
    contract is GDScript→native on exactly the hot path. The ~60-fish ceiling
    becomes a memory question. *Effort XL, Impact L.*
86. **GPU boids.** Already an OPUS_HANDOFF epic: neighbor forces in a compute
    shader, one readback per tick. Schooling cost effectively vanishes.
    *Effort XL, Impact L.*
87. **Finish the seeded-RNG sweep.** Sex assignment, mutations, algae crash still
    call raw `randf()` ([ARCHITECTURE §4](ARCHITECTURE.md) has the line list).
    This is the gate to replay — and replay is the gate to proving every item in
    this doc changed nothing. *Effort L, Impact L.*
88. **Replay-diff harness.** Record seed + inputs → assert identical sim trace
    across a refactor. Run it before/after items 63–86; "lossless" becomes a
    checked property, not a promise. *Effort L, Impact L.*

## I. Guardrails — keep it fast, keep it green

89. **Perf HUD behind a flag.** Tick ms, brain ms, draw calls, allocs/s, live
    `health_grade`/tannin/transmittance readouts (the color-drain suspects from
    §A). Every item lands with its number. *Effort S, Impact M.*
90. **Frame-time histogram, not average.** The churn bugs (#50) present as spikes;
    spikes are what players feel. Track p95/p99 in the perf HUD. *Effort S,
    Impact S.*
91. **Zero-alloc steady-state smoke.** After 64/60 land, a smoke asserts no
    per-tick allocations in a settled tank. *Effort M, Impact M.*
92. **Budget smoke at 3× population.** A CI smoke runs 150 fish headless and
    asserts tick time under budget with LOD active — the headroom stays claimed.
    *Effort M, Impact M.*
93. **Palette-fidelity smoke suite.** Extend #4 beyond greens: assert fauna reds/
    oranges/blues survive quantize within a hue tolerance, day and night. The
    whole color pipeline gets a regression net. *Effort M, Impact M.*
94. **A/B screenshot harness.** `capture.gd` + a fixed seed + fixed camera = a
    golden-image set; every shader refinement in §A–C diffs against it so "tuned"
    never quietly means "changed." *Effort M, Impact L.*
95. **Uniform-push counter.** Assert the per-frame `set_shader_parameter` count
    stays at the post-#55/#56 floor. *Effort S, Impact S.*
96. **Draw-call budget assert.** Pin the ~20–50 draw-call range in a smoke; #49/
    #51/#52 each move the number down and the smoke ratchets. *Effort S,
    Impact S.*
97. **Material-count assert.** After #49, assert the fauna material cache stays
    empty at runtime — the churn class of bug becomes impossible, not just fixed.
    *Effort S, Impact S.*
98. **Node-count watch.** Settled reference tank pins its node count; a leak of
    per-effect nodes (the class #60 fixes) trips it. *Effort S, Impact S.*
99. **Color calibration scene.** A hidden dev scene rendering the full 48-palette,
    a green ramp, a fauna hue wheel, and gray steps through the *entire* pipeline
    (3D → atmosphere → quantize) — five seconds of looking answers "is anything
    eating a channel?" forever. *Effort M, Impact M.*
100. **The refinement creed, written down.** One paragraph in
    [ENGINEERING_CREED.md](ENGINEERING_CREED.md): *no per-tick allocations, no
    per-frame material creation, shared atmosphere goes through global uniforms,
    hot dicts are int-keyed, every visual tune ships with its A/B capture, and
    nothing "extra" lands while a shipped thing looks wrong.* The last clause is
    this doc's reason to exist. *Effort S, Impact M.*

---

## Order of operations

1. **#1 today.** The green misroute is a one-line-class fix with a smoke (#4) —
   the plants come back before anything else is discussed.
2. **#50 + #49** — the churn fix funds every dynamic-color refinement; the
   instance-color change deletes the whole material-cache problem class.
3. **#3 + #5 + #6** — one palette-rebalance session: fauna get value ramps, grays
   go neutral, dupes die. With #94's A/B harness up first so every slot change is
   diffed.
4. **#33** — transform interpolation; the sim instantly *feels* 6× smoother.
5. Then §G top-to-bottom, each behind #88's replay diff.

Cut from the previous list, for the record (they were additions, not refinement):
photo mode, god-ray motes, moonlight plankton, seasonal palette drift, snail
trails, lens droplets, chromatic aberration, follow vignette, new soundscape
layers, spatialized SFX, "moment" beats, accessibility variants (worthy — but it's
a feature; it goes in a feature doc). If it's not making a shipped thing more
itself, it's not in this pass.

---

## Shipped in this pass (2026-07-01)

| # | Item |
|---|------|
| 1 | Green `classify_bank()` misroute → cool bank for saturated foliage |
| 4 | `smoke_palette_green.gd` — leaf swatches stay 90–165° / cool bank |
| 7 | Quantizer sat/brightness lift skips high-sat fauna/plants |
| 9 | `health_grade_from_transmittance()` maps cycled tanks to ~1.0 |
| 10 | Fixture wash tames on leaf-green pixels |
| 11 | Foliage SSS rim → yellow-green transmission |
| 12 | Bacterial bloom tint → gray pea-soup (less green theft) |
| 26 | Ripple rings fade in before fade out |
| 27 | IGN noise softens depth-fog terrace bands |
| 29 | Glass SSR weaker at low camera angles |
| 30 | Underside mirror + surface reflection rebalanced |
| 16 | `dither_world_lock` + camera-locked origin pushed every quantize tick |
| 21 | HDR shoulder preserves emissive hue |
| 22 | Dusk/night `palette_night_blend` smoothstep commit |
| 24 | God-ray occluders lerp in/out (no slot pop) |
| 33 | `sim_tick_blend()` + brain target lerp (fish, shrimp, waste particles) |
| 3 | Warm-bank fauna value ramps in `planted_48.png` |
| 5 | Neutral gray ramp (indices 24–31) |
| 6 | Removed duplicate warm-bank browns; slots → fauna ramps |
| 17 | Outline suppressed on caustic shimmer false-edges |
| 18 | Adjacent-bank dither bridge at bank boundaries |
| 25 | `wave_scale` normalized to tank footprint span |
| 50 | Unified `fauna_mat_owned` — one duplicate per fish mesh |
| 34 | Visual heading capped at 6.5 rad/s — sim turn stays instant |
| 39 | Interp buffer snap on camera visibility change (fish/shrimp/waste) |
| 2 | Bank-layout comment + icy-blue classify path; `blackwater_48` fixed to 48 |
| 49 | Fauna voxels: shared `voxel_fauna_mm` + MultiMesh COLOR (no per-color batches) |
| — | **Creature clarity:** refraction confined to surface interface; wake/feed ripples toned down; deposit_wake no longer spawns surface rings every tick |
