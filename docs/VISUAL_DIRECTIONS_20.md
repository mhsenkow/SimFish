# Visual Directions — 20 Tracks With Frame-Level Impact

*Drafted 2026-09-13 from a full-repo pass plus a **live frame captured from
`main.tscn` this session** and measured pixel-by-pixel. Companion to
[BROAD_DIRECTIONS_20.md](BROAD_DIRECTIONS_20.md), which maps the engineering
directions; this one maps the twenty directions that change **what the player
actually sees**.*

Format matches the other idea docs: **Effort** S (≤2h) / M (half-day) / L (full
day+) / **XL** (multi-day), **Impact** S / M / L.

---

## Method — how the measurements below were taken

The numbers in this document are not impressions. A throwaway harness
instantiated `res://main.tscn` inside a host scene, let it settle 1,100 frames
(≈18 s of real boot + sim), and saved `get_viewport().get_texture()` to PNG.
The user's saved tank had `duotone_mode` on, so the harness cleared it and
called `main._apply_biotope_palette()` before the second shot. The frame is
1536×864 (window) over a 512×288 internal render.

Reproduce with:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path shaders-godot/godot-project res://dev/visual_capture.tscn
```

That harness is direction #20 and was built in this session. Note it is **not**
`--headless`: the dummy renderer produces no image, so it opens a window for a
few seconds and quits itself. Frames and a diffable `metrics.txt` land in
`user://visual_capture/`.

The two harnesses that were already in the tree — `dev/capture.tscn` and
`dev/capture_pass.tscn` — both instantiate `world.gd` *without* `main.gd`, so
none of the per-frame uniform driving runs and both render a frame that looks
nothing like the shipped game. They are what the visual idea docs had been
graded against.

---

## The measured baseline

### A correction to the first draft

The first version of this document measured **one frame of the author's own
saved tank**, captured by a hand-written harness. That tank turned out to be a
crashed reef — total fish extirpation, shrimp collapse, algae 32, heavy
turbidity — and its flatness was substantially *the sim being correct about a
dying tank*, not the renderer being wrong.

`dev/visual_capture.tscn` (direction #20, now built) fixes that: it boots a
named scenario with a pinned clock and a fixed seed, so the numbers below are
reproducible and comparable between commits. Both sets are kept — the crashed
tank is still a real state the game can be in, and the gap between them is
itself the subject of direction #14.

**What the correction changed:** the headline "subject, background and floor
inside four luminance levels" was a property of that crashed tank, not of every
frame. **What it did not change:** every code-level finding below. The palette
excess, the unshaded pipeline, the light model reaching 2 shaders out of 15
with a floor of 1.0, the room haze arithmetic and the unreachable refraction
branch are all scenario-independent, and each was confirmed on the
deterministic capture.

### Deterministic capture — `beginner_sandbox`, midday, hero angle

Run: `Godot --path shaders-godot/godot-project res://dev/visual_capture.tscn`

| Metric | Before this session | After | Contract |
|---|---|---|---|
| Unique colours (48-entry palette) | **15,535** | **40** | ≤ 192 (4×) |
| `palette_excess` | **324×** | **0.83×** | ≤ 4× |
| Tonal spread (p95−p05) | 162.9 | 143.8 | — |
| `midtone_mass` | 0.179 | 0.309 | ≤ 0.45 |
| p05 (shadow) | 17.8 | 26.6 | ≤ 40 |
| p99 (highlight) | 191 | 191 | **≥ 200 — still failing** |

The palette contract is the headline: **the render emitted 324 colours for
every colour the palette declares, and now emits fewer colours than the palette
has.** The highlight end is the one grade still red, and it is honest that it
is: see #3.

### The crashed-reef frame (2026-09-13, the author's save)

Kept because it is a real state and because #14 is about it. Luminance
percentiles of the three largest surfaces:

| Surface | p05 | **p50** | p95 |
|---|---|---|---|
| Room wall | 29 | **143** | 149 |
| Tank mid-water | 93 | **147** | 155 |
| Substrate | 90 | **144** | 150 |

Four luminance levels between subject, background and floor. The room-haze
arithmetic that produced the 143 is diagnosed in #2 and is now fixed and
smoke-pinned; the rest of that frame's flatness is the tank dying, which the
render does not currently say (#14).

### Subject size

24 adult fish plus 10 morphs occupy **0.96%** of the tank region — about 246 px
each at window resolution, i.e. roughly **22×11 px on screen and 7×4 px at the
512×288 internal render**. That is the on-screen footprint of the thing 200+
`fish_*` and `mind_*` scripts exist to animate. Unchanged by this session.

### Lighting

| Fact | Before | After |
|---|---|---|
| Spatial shaders in `shaders/` | 15 | 15 |
| …declaring `render_mode … unshaded` | 15 | 15 |
| …that sample the fixture cone | **2** | **8** (all that render surfaces) |
| Out-of-cone floor at `room_darkness 0` | **1.0** (a no-op) | 0.74 |
| Bar fixture modelled as | its leftmost of 4 spots | a line segment |
| Directional key from the surface normal | none | N·L + hot core |
| Emissive fixtures dimmed by their own cone | yes | no |
| `shadow_enabled` in `main.tscn` | `false` | `false` |
| `tonemap_mode` | `0` (Linear) | `0` (Linear) |

---

### Status legend

- ✅ **done** — shipped and verified (smoke green / measured in a capture)
- 🟡 **partial** — landed, but a named part remains (say which, in "What changed")
- ⏸ **blocked** — cannot proceed; name the blocker
- ❌ **rejected** — deliberately not doing it; say why

### Direction roll-up

| # | Direction | Effort | Impact | Status |
|---|---|---|---|---|
| 1 | Give the tank a light model | XL | L | ✅ |
| 2 | Stop room haze erasing the room's value ladder | S | L | ✅ |
| 3 | Reclaim the palette's dark and bright ends | M | L | ✅ |
| 4 | Ground everything that sits on something | M | L | ✅ |
| 5 | Re-snap to the palette after the post chain | S | L | ✅ |
| 6 | Give the room its own narrow ramp | M | M | ✅ |
| 7 | Spend the dither budget where it earns | M | M | ✅ |
| 8 | Make the close-up the default read | M | L | 🟡 |
| 9 | A silhouette budget for 7-pixel creatures | L | L | ⏸ |
| 10 | Reconcile the two resolutions | M | M | ⏸ |
| 11 | Give the medium a visible dynamic range | M | L | ✅ |
| 12 | Kill or ship the dead refraction path | S | M | ✅ |
| 13 | Get caustics and god rays into the default frame | M | M | 🟡 |
| 14 | A collapsing tank must not look healthy | M | L | ✅ |
| 15 | Let time of day restage the picture | M | L | ✅ |
| 16 | Make care land visually | M | M | ✅ |
| 17 | Compose the water volume, not just the substrate | L | L | 🟡 |
| 18 | Fewer chips, bigger reads | M | M | 🟡 |
| 19 | Cut the notification flood at the source | S | M | ✅ |
| 20 | A visual regression capture of the *shipped* look | M | L | ✅ |

---

## Cluster A — Light (the root cause under half this list)

### 1. Give the tank a light model
*Effort: XL · Impact: L*

**Every one of the 15 spatial shaders is `render_mode … unshaded`. Not one
exception.** `voxel.gdshader:78-88` computes its own shading from the face
normal alone:

```glsl
if (n.y > 0.7)        f = 1.00;
else if (n.y < -0.7)  f = 0.58 + belly_flash * 0.35;
else if (abs(n.x) > 0.7) f = 0.88;
else                  f = 0.76;
```

Four constants. A fish tucked under the driftwood is exactly as bright as a fish
in open water. A plant at the back of the tank is exactly as bright as one
pressed against the front glass. Depth, occlusion, proximity to the fixture,
canopy shade — none of it reaches a pixel.

Meanwhile `world.gd` constructs **sixteen** lights: the fixture spots, moonlight,
backlight, two accents, heater glow, room spill, wall bounce. `lighting_rig.gd`
is 343 careful lines of aimable cone geometry with head position, tilt, yaw and
attenuation. `TankConfig.spot_shadows` exists. **All of it is a control surface
with no output path** — Godot renders those lights, and no surface samples them.
The only lit materials in the project are the two editor previews, which build
their own key+fill rigs precisely because the game shaders won't respond to the
world's.

The direction is not "switch to `shader_type spatial` lit" — that surrenders the
palette control the whole look depends on, and mobile-renderer light counts would
bite. It is: **publish a cheap light field the unshaded shaders sample.** A small
3D texture or a handful of global uniforms carrying (a) distance/occlusion from
the fixture cone, (b) canopy shade — `canopy_density.gd` already builds a 16×8
`FORMAT_RF` image every 3 s and hands it *only* to the god-ray material, and (c)
hardscape occlusion, for which `hardscape_occluders.gd` already synthesises
conservative boxes. Three producers exist. Nothing consumes them for surface
shading.

This is the direction that makes #3, #4, #14, #15 and #17 possible. Do it first
or accept that the rest are cosmetics on a flat image.

### 2. Stop the room haze from erasing the room's value ladder
*Effort: S · Impact: L*

`world.gd:8714-8718` authors a deliberate value ladder, with a comment that
diagnoses the exact failure it is preventing:

```gdscript
const ROOM_VALUE_DESK: float = 0.16
const ROOM_VALUE_WALL: float = 0.44
...
# Below one palette step apart, two surfaces render as the same colour no
# matter what you set.
```

The wall is authored at roughly luma **87** after `_room_calm_color(…, 0.44, 0.42)`
and `palette_value 0.82`. It renders at **143**.

The culprit is `VoxelMat.make_room()`, which sets `room_haze_strength = 0.65`
with `room_haze_color` derived from the fixture colour — a warm near-white at
luma ≈ 229. `voxel.gdshader:127-131` then does
`mix(col, room_haze_color, smoothstep(8, 28, view_z) * 0.65)`. At the wall's view
distance that factor lands near 0.42, giving `87 + 0.42 × (229 − 87) ≈ 147`.
Measured: 143.

**An aerial-perspective term added for depth is adding ~60 luminance levels to
the single largest background surface in the frame, and it is doing so
*after* the ladder that exists to stop precisely this.** VISUAL_POLISH #27
("never render the room brighter than the tank's mid-water value") is ticked
done — and it *is* satisfied, by four levels. The rule was written as an
inequality; the eye needs a separation.

Two fixes, both small: make the haze target a *dark* colour (real aerial
perspective in a dim room recedes toward the room's own shadow, not toward the
lamp), and enforce the ladder as a post-haze clamp with a stated minimum gap —
say 40 luma below mid-water — rather than a pre-haze authored value.

### 3. Reclaim the palette's dark and bright ends
*Effort: M · Impact: L*

`p99 = 158`, `p01 = 15`, with 50% of pixels inside 135–158. The palettes ship
`ffffff`, `f8f4e0` and `000000`; they are never selected. There is no specular
anywhere (all shaders unshaded, `tonemap_mode = 0` so nothing rolls off a
highlight either), and the only true blacks in the frame are the *unbuilt* void
outside the room.

Concretely: a wet-surface glint on the meniscus, a hot rung where the fixture
hits the water line, a genuinely dark shadow side on hardscape. This is the
cheapest way to make the frame stop looking like fog. Depends on #1 for anything
position-aware, but the fixture glint band already exists as
`water.gdshader:72` `fixture_glint_center/width` and can be pushed harder today.

### 4. Ground everything that sits on something
*Effort: M · Impact: L*

Contact shading exists, in two places, both narrow:

- `substrate_caustic.gdshader:41` — `contact_ao_points[8]`, hardscape only, substrate only.
- `voxel_mat.gd:814 update_substrate_blob_shadows()` — capped at 16 points (32 below perf tier 2), fish only, substrate only.

Nothing casts onto a plant, onto hardscape, onto another fish, onto the glass, or
onto the desk. `shadow_audit.gd` is 22 lines asserting exactly this ("verify
gameplay uses blob shadows only") — the constraint is documented and enforced,
which is good discipline, but it means **the tank floats**. In the captured
frame the driftwood mass has no darkening beneath it at all; it reads as a decal
on the sand.

The blob-shadow machinery generalises: it is already a packed data texture
(`_blob_shadow_texture`, 16×1). Feeding the same buffer to `foliage_mm`,
`voxel_mm` and the glass would ground the whole scene without a shadow map.

---

## Cluster B — Keep the palette's promise

### 5. Re-snap to the palette after the post chain
*Effort: S · Impact: L*

Measured **19,618 unique colours** in a nominally 48-colour render — and that is
at internal resolution, since `RenderResolutionAudit` guarantees the post pass
matches the 3D pass at 512×288. Roughly 20k distinct colours in a 147k-pixel
frame.

The cause is visible in `palette_quantize.gdshader`. Palette selection happens
around line 290. Then, *after* it:

| Stage | Line | What it does to the colour |
|---|---|---|
| outline darken | ~447 | `result *= darken` |
| creature ink | ~473 | `result *= mix(...)` |
| vignette | ~483 | `result *= …` |
| CRT / grille / mask | ~490 | multiplies, three modes |
| film grain | ~520 | `result + grain` |
| highlight rolloff | ~525 | warm shoulder |
| sensor noise | ~533 | `result + n` |
| FXAA-lite | ~542 | **blends between neighbouring pixels** |
| deband | ~555 | `result + triangular noise` |

Every one of these produces off-palette values, and FXAA explicitly interpolates
between them.

**The fix is already written, for the other mode.** The duotone work in the
current working tree ends with:

```glsl
// Duotone re-projection — last word on hue.
if (duotone_amount > 0.001) {
    result = mix(result, duotone_project(result), duotone_amount);
}
```

with a comment that names exactly the problem: grain and FXAA "cannot
reintroduce off-ramp color." The normal palette path has no equivalent. Add a
final nearest-palette snap (dither-free, or dithered against the same Bayer cell)
for the non-duotone path and the 48-colour claim becomes true. `pixel_purity`
should be what turns it on hard; the default can keep a partial mix.

### 6. Give the room its own narrow ramp
*Effort: M · Impact: M*

VISUAL_POLISH #28 is still open and is the right call: the room borrows the same
48-entry biotope palette as the tank, including the fauna accent bank
(`c33b3b`, `d97e2c`, `e6c92a`, `872cb0`, `c44a8e`). `make_room()` softens this
with `palette_global_scale 0.35 / palette_saturation 0.72`, but softening is not
exclusion. A room that literally *cannot* reach the accent rungs makes every
accent in frame belong to a living thing. Pairs directly with #2 — same
surfaces, same pass.

### 7. Spend the dither budget where it earns
*Effort: M · Impact: M*

The substrate is the **noisiest surface in the frame**: 8,135 unique colours in
130k pixels, against 4,915 in the 195k-pixel water crop — about 2.5× the colour
entropy per pixel, on the largest single surface, which is also the least
interesting one.

It is getting `dither_substrate_coarse` (0.35) *plus* `grain_variation` (0.45 in
`substrate_caustic`) *plus* `ripple_strength` *plus* scattered detritus voxels
*plus* the global region-aware dither. Each was a good idea alone. Together they
make sand louder than fish.

The wall, by contrast, has only 615 unique colours — `room_dither_scale = 0.35`
is doing its job there. The direction is to state a per-region entropy budget the
way `room_dither_scale` already states one, and hold the substrate to it.

---

## Cluster C — The subject is too small to carry the simulation

### 8. Make the close-up the default read
*Effort: M · Impact: L*

A fish is **~22×11 px on screen, ~7×4 px at internal resolution**, and all fish
together are under 1% of the tank region. Everything the mind stack computes —
`fish_qualia`, `fish_felt_now`, `fish_core_affect`, `mind_daring`,
`global_workspace`, the whole `SENTIENCE_*` doc series — has to express itself
through seven pixels.

The machinery to fix this already exists and is opt-in: `_follow_target`,
`_release_cinematic_follow`, the Portal PiP (`main.gd:1497` — "PiP zooms the main
tank render, no second 3D camera needed"), camera view slots, camera presets.

The direction is to invert the default. The tank-wide hero shot is the *context*
view; the reading distance for a creature-driven game is the one where a fish is
80 px tall. Options worth pushing on: an idle camera that drifts into a
close-up on whichever fish is doing something (the `global_workspace` broadcast
is exactly the signal for "who is interesting right now"); the Portal open by
default; or a hero-framing pass that pushes `DEFAULT_RADIUS` in and lets the
orbit shell pull out.

### 9. A silhouette budget for 7-pixel creatures
*Effort: L · Impact: L*

`voxel.gdshader` carries `sss_strength`, `irid_strength`, `metallic_strength`,
`fin_translucency`, `bioluminescence`, `belly_flash`, `fauna_rim` — seven
per-fauna appearance channels. At 7×4 px, the fresnel terms driving most of them
(`pow(1 - dot(n, VIEW), 2.5)`) span less than one pixel of rim.

Two questions worth answering with a capture, not an argument: which of these
channels survive quantization at the shipped internal resolution, and what
*would* read at that size? Silhouette, one accent rung, and motion are usually
the answer. `creature_outline_strength` (0.38 in `BEAUTY_DEFAULTS`) is the one
channel that provably works at this scale — that is where the budget should go.
Pairs with #8: if the default read gets closer, the fresnel work starts paying.

### 10. Reconcile the two resolutions
*Effort: M · Impact: M*

The world renders at 512×288 and upscales 3× with nearest filtering. The HUD is
a sibling `Control` tree rendered at native 1536×864 with IBM Plex hinted at 11–20 px.
In the captured frame the top bar is razor-sharp vector text sitting directly on
top of chunky 3-px world pixels. It reads as a debug overlay on a pixel-art game
rather than as one image.

Three coherent answers, and the project should pick one deliberately: render the
chrome into the same internal viewport (full commitment, costs legibility);
keep chrome sharp but give it a pixel-derived grid so its rhythm matches
(cheapest, largest coherence win per hour); or lean into the split as an explicit
"instrument panel over a screen" conceit and design it that way. Right now it is
none of the three — it is an accident.

---

## Cluster D — Water that reads as water

### 11. Give the medium a visible dynamic range
*Effort: M · Impact: L*

`palette_tint.gdshaderinc` implements real per-channel Beer–Lambert extinction
with in-scatter, and the comment explaining why is the best writing in the
codebase. Then the constants make it invisible.

With `WATER_ABSORB_CLEAR = (0.0300, 0.0095, 0.0050)`, `strength = 0.62`,
`WATER_VIEW_WEIGHT = 0.35`, a 7-unit tank (water surface 6.51, substrate top
1.61) and the default camera radius of 15.5:

| | at the surface | at the substrate | **gradient** |
|---|---|---|---|
| red transmittance | 0.904 | 0.825 | **−8.7%** |
| blue transmittance | 0.983 | 0.968 | **−1.5%** |

**The entire sense of depth the water column contributes, top to bottom, is a
9% shift in red and 1.5% in blue** — while the room haze in #2 is moving the
background by 60 luminance levels. The physics is right and the signal is an
order of magnitude below the noise.

The honest response is not to fake it: real 45 cm of water genuinely does not eat
much red. It is to decide that this frame is a *stylised* aquarium and that depth
must be legible, then dial extinction (or a separate, explicitly artistic depth
grade) until the substrate is visibly further away than the front glass — and
put the number behind a named "depth legibility" knob rather than pretending
0.62 is physical.

### 12. Kill or ship the dead refraction path
*Effort: S · Impact: M*

`water.gdshader:49-54` calls refraction "the single biggest 'this is real water'
lever." `world_atmosphere.gd:163-167` decides whether to use it:

```gdscript
var method := String(RenderingServer.get_current_rendering_method())
var want_refr: float = 0.0
if OS.get_name() != "macOS" and method == "forward_plus":
    want_refr = 0.013
```

`project.godot:48` sets `renderer/rendering_method="mobile"`, and line 49 sets
the web override to mobile too. **`method == "forward_plus"` is never true in any
shipped build on any platform.** Refraction is 0 everywhere, always. The
uniform, the shader branch, the screen-texture sampler and the platform check are
all dead.

Either delete the path and reclaim the sampler, or get the effect by a route the
mobile renderer supports — a vertex-slope UV wobble on the geometry behind the
water plane costs no screen texture and reads at 512×288 better than a true
refraction would.

### 13. Get caustics and god rays into the default frame
*Effort: M · Impact: M*

`caustics.gdshader`, `substrate_caustic.gdshader`, `god_ray.gdshader` +
`beam_cone.gdshaderinc`, `baked_caustics.gd`, and the canopy attenuation feed are
all real, all careful (the god ray does Henyey-Greenstein forward scatter and
per-fish soft occlusion). **None of them are visible in the captured frame.**

Worth an hour just to find out why before designing anything: `light_volumetric`
and `light_caustics` are TankConfig flags — `BEAUTY_DEFAULTS` sets
`light_caustics: true` but says nothing about `light_volumetric`, and the beam is
only built when `cfg.light_volumetric` is set at fixture-build time
(`world.gd:5881`), so a config change afterwards never adds one. This may be a
one-line default rather than a visual problem at all — which is exactly why it
deserves a capture-based check rather than a guess.

---

## Cluster E — The tank's state should be legible at a glance

### 14. A collapsing tank must not look like a healthy one
*Effort: M · Impact: L*

The captured tank had suffered a **total fish extirpation and a shrimp colony
collapse**, with algae at 32 and two "Population collapse" toasts on screen. The
render looks identical to a healthy tank.

The whole visual response to tank health is `health_grade`, computed in
`aesthetics_runtime.gd:111` from water transmittance alone and applied in
`palette_quantize.gdshader:217-219`:

```glsl
float stress = 1.0 - health_grade;
src = mix(src, src * vec3(0.92, 0.96, 1.04), stress * 0.55);
src = mix(vec3(luma_of(src)), src, 1.0 - stress * 0.38);
```

Maximum possible effect: a 4% cool shift and 38% desaturation. On a frame whose
median saturation is already 0.054, 38% of nearly nothing is nothing.

Two things are wrong and both are worth pushing on. The *input* is too narrow —
transmittance only; population collapse, algae load and bleaching don't reach
it. And the *output* is too gentle — the state of the tank should be readable
from across the room, which means it should reach value structure and palette
bank, not just saturation. A dying tank should get darker, flatter and greener;
a thriving one should get its highlights back.

### 15. Let time of day restage the picture
*Effort: M · Impact: L*

The day/night machinery is genuinely good: a second night palette LUT
(`planted_48_night.png`), `palette_night_blend` driven smoothly from
`SimDriver.daylight()`, and a highlight-burnthrough term so emissive content
stays bright against the moonlit field. `world_atmosphere.gd` computes
`sunset_warmth`, `moonlight`, `day_phase_offset`.

It is all *tint*. Because of #1, nothing about the composition changes between
noon and midnight — the same surfaces are lit the same way in the same places,
in different colours. In a real room the difference between day and night is
that at night **the room disappears and the tank becomes the only light source**.
`LightingRig.DARK_GLOBAL_FLOOR` / `DARK_AMBIENT_FLOOR` and `room_darkness` exist
for exactly this and are the lever; the missing half is that the tank has to
actually get brighter than the room for the effect to invert, which is #2 and #3.

### 16. Make care land visually
*Effort: M · Impact: M*

Feed, water change, filter clean, glass wipe, substrate disturb — `world.gd` has
`wipe_glass_dust()` and `disturb_substrate()`, and `transient_particle_pool.gd`
exists to spend particles on moments like these. What is missing is a consistent
grammar: every player action should produce a change in the *frame* that is
visible for several seconds, at the place the player touched, at a magnitude
proportional to the effect on the sim.

Right now the strongest visual feedback in the app is the toast that tells you
what happened in words. In a game whose entire pitch is a living picture, words
are the fallback, not the channel.

---

## Cluster F — Frame, chrome, and attention

### 17. Compose the water volume, not just the substrate
*Effort: L · Impact: L*

`aquascape_craft.gd` is "composition coaching, flood-fill, scape analysis,
guides" — golden-ratio and focal-point craft, for the **player-built** editor.
The tank that actually boots is assembled by procedural placement in `world.gd`,
and in the captured frame every piece of structure sits in the bottom third
while the upper half of the water column is empty grey.

Real aquascaping composes a volume: a focal mass off-centre, a mid-ground that
steps back, background stems that reach the surface, negative space that is
*chosen*. The analysis code to score a scape on those terms already exists in
`aquascape_craft.gd` — pointing it at the generated scape and rejecting layouts
that score badly is the direction, and it is the one that most directly serves
what the game is about.

### 18. Fewer chips, bigger reads
*Effort: M · Impact: M*

The captured HUD carries eight stat chips across the top (`content — reef
stable`, `warmth 52% O₂ 117%`, `32 algae`, `day`, `16 16A · 16/40`, `vigor 89%`,
`0 —`, `24 adults · 0 babies`, `+10 morphs`), ten near-identical right-rail
icons, and a bottom bar reading `Feed  Fl  Pt  Wm  Wf  |  Care  H₂O  Fil`.

`Fl`, `Pt`, `Wm`, `Wf`, `Fil` are unglossed two-letter abbreviations for the
primary verbs of the game. `panel_theme.gd` has real typography (IBM Plex at
three weights, a caption/body/title scale) and `PanelTheme.transition_panel` does
a proper eased fade — the components are good. The *information architecture* is
a debug readout that grew.

The direction is editorial, not technical: decide the three numbers that belong
on screen always, put everything else one click away, and let the verbs use
words. The `config_curation.gd` tier system (COMMON / ADVANCED) already
demonstrates the project can make this kind of cut — apply the same discipline to
the HUD.

### 19. Cut the notification flood at the source
*Effort: S · Impact: M*

The notification badge read **53** on one capture and 27–38 on the others, within
the first ~20 seconds of a boot. `comms_inbox.gd` already rate-limits well at the
*presentation* layer — `TOAST_MAX_VISIBLE = 2`, `TOAST_QUEUE_SOFT_CAP = 8`,
`CAPTION_MIN_INTERVAL_S = 20.0`, death-summary batching. The throttle is correct
and the badge still hits 53, which means the throttle is downstream of the
problem: the sim is *generating* dozens of notification-worthy events per minute.

Two toasts on screen both saying "Population collapse" is the tell. Merge at the
source by event class, and let severity — not arrival order — decide what earns
a badge at all.

---

## Cluster G — Being able to see what we changed

### 20. A visual regression capture of the *shipped* look
*Effort: M · Impact: L*

This is the direction that makes the other nineteen verifiable, and it is
currently broken in a way nobody would notice without running it.

`dev/capture.tscn` and `dev/capture_pass.tscn` both build their own scene tree
around `world.gd` and never instantiate `main.gd`. Everything `main.gd` drives
per frame — palette tint, day phase, night blend, health grade, murk, water
column, biotope palette selection, the entire post-uniform chain — is left at
shader defaults. `dev/capture.tscn` also still declares `internal_resolution
Vector2(384, 216)` and no night palette, both stale.

Run today, they produce frames that look nothing like the game: `capture.tscn`
renders the camera partway inside the substrate, and `capture_pass.tscn` renders
a desaturated grey box. Both were presumably accurate when written.

VISUAL_POLISH_200 says it is "graded against the capture set". **The capture set
does not show the shipped renderer.** Every visual item ticked `[x]` on the
strength of those images deserves a re-check — #27 in that doc is a worked
example: ticked done, and the measurement in this document's baseline shows the
separation it promises is four luminance levels.

What is needed is small: instantiate `main.tscn`, force a known tank + scenario +
clock so the frame is deterministic, disable the HUD (`_set_hud_visible_for_photo`
already exists), settle N frames, write a fixed set of angles. Then a smoke can
assert the numbers in this document's baseline table directly — *room wall p50
must be at least 40 below mid-water p50* is a one-line assertion, and it is the
kind of assertion that would have caught #2 the day it regressed.

---

## If only three

*Updated after the second pass. Twelve of twenty are now shipped or advanced;
these are the three that buy the most from here.*

**#17 (compose the water volume)** has become the top item, because two other
directions now point at it. The hero and front angles fail the highlight grade
not for want of a shader but because **no surface in that composition faces
both the lamp and the camera** — nothing reaches the upper third of the water,
so nothing up there catches light. The `close` angle fails `midtone_mass` and
the shadow grade for the same reason from the inside: at reading distance the
frame is undifferentiated mid-water. `aquascape_craft.gd` already scores a
scape on composition; it just is not pointed at the generated one.

**#7 (the dither budget)** is the loudest remaining defect by eye. The palette
lock made every surface honest and thereby made the substrate's noise
undeniable — it was measured as the frame's highest colour-entropy surface, and
lowering the grain helped without settling it. This is now a tuning pass with a
measurement attached rather than an open question.

**#18 (fewer chips, bigger reads)** is untouched and is the most player-visible
chrome left: eight stat chips, ten near-identical rail icons, and the primary
verbs of the game rendered as unglossed two-letter abbreviations (`Fl`, `Pt`,
`Wm`, `Wf`, `Fil`). Editorial work, not technical — the components are good.

Behind them, **#11** is the last cheap physical one: the water column still
moves the picture by about 9% top to bottom, an order of magnitude under the
things competing with it.

---

## Application log

*Append-only. One entry per session that pushes on a direction: what changed,
what was measured, what remains.*

### 2026-09-13 — document drafted

Full-repo visual pass. Live frame captured from `main.tscn` and measured;
baseline tables above are from that frame. No code changed. All twenty
directions open.

### 2026-09-13 — first tranche: #20, #5, #2, #12 shipped; #1, #3, #6, #7 partial

**#20 — the capture harness. ✅**
`dev/visual_capture.gd` + `.tscn` boot `res://main.tscn` itself, apply a named
scenario over reset defaults, pin the sim clock, hide the chrome, hold three
camera angles and write PNGs plus a diffable `metrics.txt` to
`user://visual_capture/`. `scripts/frame_metrics.gd` turns a frame into
numbers with four thresholds; `smoke_frame_metrics.gd` asserts the maths
against synthetic images, including one built to reproduce the flat baseline
and fail, and one built to pass. `TankConfig.capture_mode` suspends config
saves and blocks `SaveManager.try_load`/`save_active` so a capture neither
reads nor writes the player's tank.

Three traps found and documented in the harness header, each of which had
silently produced a wrong "capture" first:
- a window that never takes focus makes main.gd set `time_scale = 0` and both
  SubViewports to `UPDATE_DISABLED` — every angle then returns the same frozen
  frame, with no error anywhere;
- past 45 s of idle the favourites tour re-arms every frame and owns the
  camera, so setting an angle once is a suggestion;
- the sim clock is not pinned by default, so a run at one settle length shows
  a warm daylit room and a run at another shows a black one.

`dev/capture.tscn` and `dev/capture_pass.tscn` are left in place but are still
the stale harnesses this direction was written about; the new one supersedes
them.

**#5 — palette re-snap. ✅** `snap_to_palette()` runs as the genuine last word
in `palette_quantize.gdshader`, ordered-dithered against the same cell and
scaled by the same region-aware strength as the main pass. Driven by
`TankConfig.palette_lock` (default 1.0, exposed in the Render panel).
Measured: **15,535 unique colours → 39**, palette_excess **324× → 0.81×**.

Two follow-on defects the lock exposed, both fixed here, both invisible before
it:
- plain RGB distance is hue-blind, and the first locked frame rendered a beige
  plaster wall as 74% tan and 12.6% *chartreuse* because the palette has no tan
  rung above `cdb088`. `pal_dist()` now weights chroma error 3× luma error, so
  dither walks along value rather than across hue. Wall is now 74% `b18f6a` +
  15.5% `95714e`, two adjacent browns.
- the room's plaster grain (0.55) and the substrate's (0.45) were amplitudes
  tuned to be smeared by the post chain. Snapped, a ±24% wobble is a whole
  rung, and flat surfaces came out as salt-and-pepper. Lowered to 0.18 / 0.22 —
  sub-rung grain is grain, supra-rung grain is noise.

**#2 — room haze vs the value ladder. ✅** `WorldRoomBuilder.haze_target()`
builds the aerial-perspective target from the room's own shadow plus a trace of
lamp warmth instead of from the fixture, and `clamp_luma()` caps it at
`ROOM_HAZE_LUMA_CEILING = 0.41`. The cap is enforced inside
`VoxelMat.update_room_haze()` — the one place the uniform is written — so the
night path, which lerps the haze toward the fixture colour, cannot lift it
either. `hazed_luma()` mirrors the shader so the ceiling is assertable
headlessly. `smoke_room_value_ladder.gd` pins the **gap** (≥ 40 luma below
mid-water) rather than the ordering VISUAL_POLISH #27 asked for and satisfied
by four levels, checks every shipped room preset, asserts haze can only darken,
and keeps the pre-fix formula as a regression that must stay over the ceiling.

**#12 — dead refraction path. ✅** Deleted. `world_atmosphere.gd` enabled it
only under `rendering_method == "forward_plus"`, and `project.godot` ships
`mobile` (web override also mobile), so the branch was unreachable in every
build on every platform while being described in the shader header as "the
single biggest 'this is real water' lever". Removed the uniform, the branch and
the `hint_screen_texture` sampler rather than switching it on: the macOS
exclusion it carried is real and is the platform this is developed on. The
mobile-safe substitute is named in the shader header as follow-up.

**#1 — light model. 🟡** The analytic cone was already there and reached
`foliage` and `foliage_mm` only, with an out-of-cone floor of exactly 1.0
unless the player raised `room_darkness` — sixteen lights and 343 lines of rig
multiplying by one. Now:
- `CONE_SHAPING_FLOOR = 0.74` shapes a normally-lit room;
  `TankConfig.light_shaping` (Render panel) is the opt-out back to flat.
- `LightingRig.beam_segment()` collapses a fixture's spots into a segment, so a
  bar light is a bar rather than its leftmost of four spots.
- `iaq_beam_light_n()` adds a directional key from the surface normal plus a
  broad hot core, which is the difference between a pool of light on the floor
  and lighting.
- The include now reaches all eight shaders that render surfaces;
  `smoke_light_model.gd` asserts that coverage by reading the shader sources,
  and fails on any new spatial shader that is neither lit nor listed exempt
  with a reason.
- `VoxelMat.make_emissive` sets `light_exempt` — a lamp is not lit by itself.

Remaining for #1: nothing consumes `canopy_density.gd` or
`hardscape_occluders.gd` for surface shading, so plants and hardscape still do
not shade what is under them. That is the other half, and it is #4's half too.

**#3 — palette ends. 🟡** The dark end is reached (p05 17.5, and the palette's
black rungs are now in use). The bright end is not: p99 sits at ~180 against a
contract of 200. The frame does touch `f8f4e0` (luma 243) but only on 0.09% of
pixels; everything ≥ 198 is 0.74%, just short of the top percentile. The hot
core was widened from `pow(ndl, 6)` to `pow(ndl, 3)` on the reasoning that a
bar fixture is a wide source, which helped the lit faces but not the count.
Remaining: a genuine specular somewhere — the wet glass rim, the water line
under the fixture. **This grade is deliberately left failing rather than
tuned to pass.**

**#6 — the room's own ramp. 🟡** Room pixels now carry a `neutral_bias` into
the snap (driven by the existing `room_like` heuristic), which penalises
saturated candidates so plaster cannot spend the palette's accent rungs. Not
yet a hard bank restriction, which is what VISUAL_POLISH #28 actually asks for.

**#7 — dither budget. 🟡** The snap respects the region-aware strength (the
first version did not, and dithered at full amplitude everywhere, undoing the
quiet room, the light touch on fauna and the flat-area clustering). The
`room_like` luma gate started at 0.38, which assumed the room was *brighter*
than the tank; once #2 put it where it belongs the gate stopped firing and the
room got the full budget it exists to be spared — now 0.08. Grain lowered as
above. Remaining: the substrate is still the noisiest surface in the frame.

**#4 — grounding. 🟡** `canopy_density.gd`'s 16x8 shade map now reaches the
substrate as well as the god rays: `VoxelMat.update_substrate_canopy()` pushes
it into both substrate materials, and plants darken the floor beneath them
(caustics squared, since a leaf blocks arriving light harder than it blocks the
diffuse floor). The map's build was also ungated from `_god_ray_materials` — it
had been built only when volumetric beams existed, because the beams were its
only consumer.

Remaining for #4: still nothing casts onto a plant, onto hardscape, onto
another fish, or onto the glass. `hardscape_occluders.gd` synthesises boxes
that nobody reads. The blob-shadow buffer is already a packed 16x1 data texture
and would generalise, but it needs to become a global uniform before shaders
other than the substrate's can sample it.

**Not started:** #8, #9, #10, #11, #13, #14, #15, #16, #17, #18, #19.

### 2026-09-13 (second pass) — #1, #4, #14, #15, #19 shipped; #3, #8, #13 advanced

**#4 — grounding, completed. ✅** The blob-shadow buffer was already the right
shape — packed (position, radius) spheres in an Nx1 data texture — it was just
a per-material uniform on two substrate materials. Promoted to the shader
globals `iaq_occluder_tex` / `iaq_occluder_info` and sampled from
`beam_cone.gdshaderinc`, so every surface that samples the light now samples
what blocks it. Fish, plant crowns and hardscape footprints merge into one
16-slot field (`VoxelMat.merge_occluders`, most legible first, because the cap
IS the budget).

Two details that matter more than the loop: a **self-shadow guard** — a
fragment inside an occluder sphere IS that object, and without it every fish's
top half went dark — and **contact hardening**, so a leaf resting on the sand
casts a sharp dark shadow and the same leaf near the lamp casts a wide faint
one. Without the second, every shadow has identical weight and the depth cue
they exist to give is lost.

**#1 — light model, completed. ✅** With occlusion in, the analytic cone is a
real light: position, direction, a line source for bar fixtures, a normal-driven
key, a hot core, and now shadows. Residue: `hardscape_occluders.gd` still
synthesises box occluders nobody reads — the field uses the contact-AO spheres
instead.

**#14 — tank state. ✅** `health_grade_from_state()` blends clarity, stock,
algae and plant vigour, with the **worst axis leading** (`HEALTH_WORST_PULL`
0.55) rather than a weighted mean — one catastrophic axis must not be diluted
by three healthy ones. That is the actual bug: a tank can die perfectly clear,
and the captured crashed reef had lost every fish while its water was fine.
The output was widened too: the old response was a 4% cool shift and ≤38%
desaturation, which on a frame whose median saturation is 0.13 is nothing.
Stress now collapses contrast toward a sick midtone and casts green-grey murk,
strongest in the shadows. Cool-shift-as-illness was backwards anyway — a cool
cast reads as evening.

**#15 — night restages. ✅** `LightingRig.effective_room_darkness()` takes the
max of the player's `room_darkness` and what the clock implies
(`NIGHT_ROOM_DARKNESS` 0.72). The day/night machinery was excellent and entirely
tint: same composition at midnight as at noon, different colour. The room now
falls away on the clock and the tank becomes the light source in it, without
the player finding a slider that defaults to 0. Max, not sum, so a player who
set 0.9 is not pushed to 1.0 at midnight.

Measured, same scenario and angle, `VISUAL_CAPTURE_DAY_PHASE` 0.25 vs 0.78:

| hero angle | midday | midnight |
|---|---|---|
| p05 | 26.6 | **7.9** |
| p50 | 92.2 | **53.6** |
| p95 | 148.9 | 100.8 |
| median saturation | 0.132 | **0.162** |
| unique colours | 37 | 32 |

The frame is genuinely half as bright with real blacks, and *more* saturated —
the tank's own colour is the only colour left. That is a restaging, not a tint.

**#19 — notification flood. ✅** `CommsInbox.coalesce_into()` folds a repeat of
the same kind+title into the row it repeats, with a count rendered as "(x3)".
The toast dedup key moved from kind|severity|**body** to kind|**title** —
"Fish extirpated" and "Shrimp colony collapsed" are two sentences under one
headline, and stacking them as two cards was the visible half of the problem.
Critical no longer bypasses dedup outright; it gets a shorter window (45 s vs
240 s), because an unbounded bypass is how the same alarm lands twice.

**#3 — the highlight. 🟡, and the metric changed.** Three attempts, and the
result is worth stating plainly:

- The water surface now has a real Blinn specular. It failed twice before
  working, for two instructive reasons. First it was a mirror (`pow(ndl, 190)`)
  — a rippled surface is not a mirror, and at a 512×288 internal render a lobe
  that tight falls between pixels. Second, and more fundamental, **a translucent
  surface cannot produce a highlight**: water writes `ALPHA` capped at 0.62, so
  however hot the colour got, a fragment contributed at most 62% of it over
  whatever was behind. The specular needed its own alpha escape. The same was
  true of the tank rim on the glass (capped at 0.30).
- Measured: the **surface** angle reaches p99 **242.9** with a highlight
  fraction of **0.0188**, 12× the threshold. It works.
- The **hero** and **front** angles still fail, at 0.0008. This is not a shader
  gap: at hero framing the water surface is nearly edge-on and no surface in
  the composition faces both the lamp and the camera. The fix is compositional
  (#17), not another effect.

**The threshold itself was replaced**, and that deserves to be on the record
rather than buried: it began as `p99 >= 200`, which is the wrong shape of test.
A specular is small by nature; demanding it occupy the top percentile demands a
*bright frame*, not a frame with a highlight. It is now a highlight *fraction*
(≥0.15% of pixels at luma ≥200). The replacement was checked for
goalpost-moving: the flat baseline scores 0.0, and `smoke_frame_metrics`
asserts that a merely-brighter flat frame still scores 0.0 while 40 blown
pixels in 14,400 pass.

**#8 — the close-up. 🟡** Cinematic follow moved the orbit *target* and never
the radius, so clicking a fish re-centred the same wide shot on a 0.6-unit
animal from 20 units away — pointed at the subject, exactly as far from it as
before. `CameraController.radius_for_subject()` answers "how close for this
subject to fill 16% of frame height", the follow tick eases toward it at half
the tracking rate, and `clear_follow()` gives the player their shot back. The
helper can only ever move the camera *in*. Still open: the *default*,
un-followed read is as wide as it was.

**#13 — beams. 🟡** God-ray alpha was gated on the raw `room_darkness` setting,
which defaults to 0, so the whole volumetric path stayed out of the default
frame. It now reads the same effective darkness #15 introduced, so shafts come
out at night on their own. Midday shafts remain subtle, which is correct — you
do not see light shafts in a bright room.

One thing the night capture left open: the highlight level resolves to 187 at
`day_phase` 0.78 (the day palette's 199 blended toward the night LUT's ceiling
by whatever `palette_night_blend` is at that hour), and the night frame tops out
at 154 — so all four angles score 0. Whether a moonlit tank under a soft bar
*should* carry a highlight is a design question, not a bug; it is recorded here
rather than tuned away.

**A harness bug worth recording.** The night capture graded against the *day*
palette's ceiling, because `dev/visual_capture.gd` read `Display.material` while
the quantize material actually lives on the post viewport's display —
`Display` is only main.gd's fallback. The wrong material had none of the driven
uniforms: `palette_size` fell back to a hardcoded 48 (right by luck, for these
palettes) and `palette_night_blend` read null. The harness now calls main.gd's
own `_quantize_material()` rather than reimplementing its fallback. Any future
tool reaching into the render should do the same.

**Verified:** eight new smokes (`frame_metrics`, `light_model`,
`room_value_ladder`, `tank_health_grade`, `night_restage`, `subject_framing`,
`notification_coalescing`, plus the updated `lighting_rig`), and a four-angle
capture set that now includes a top-down `surface` angle — added because the
hero angles cannot see the water surface at all, so nothing that happens on it
was assessable.

### 2026-09-13 (third pass) — #3, #6, #7, #11, #16 shipped; #17, #18 advanced

**#11 — the medium. ✅** `iaq_water_depth.x` stretches the DEPTH half of the
light path before extinction, separately from `strength`. Raising strength
deepens the vertical gradient and the horizontal wash together, and the
horizontal wash is what turned the tank cyan the last time someone tried it —
this scales only the term that creates vertical structure. At the shipped 2.6,
the surface-to-substrate red gradient goes from ~9% to ~20% and the in-scatter
wash from 6.5% to ~20%. Exposed as `TankConfig.depth_legibility`, declared as
an artistic control rather than a claim about water; 1.0 is physical scale.

**#7 — the dither budget. ✅, and the instrument was wrong.** Once the palette
lock landed, "unique colours" could no longer see this at all: a frame is 40
colours whether they are laid down in calm fields or as salt-and-pepper. Added
two spatial metrics instead —

- `stipple`: fraction of adjacent RENDER pixels that differ. Measures at the
  upscale stride, because at 3× nearest two of every three window neighbours
  are identical by construction and a naive read understates it threefold.
- `stipple_contrast`: the mean luminance step across those pairs — how loud
  each grain is, rather than how much of it there is.

And a discriminator both need: only ALTERNATING pairs count (A B A). A
silhouette edge is *supposed* to differ from its background, and the first
version scored a frame of clean hard-edged bands as 72 — pure noise — which
would have rewarded blurring the picture.

Measured: **stipple 0.22, step 17**, against budgets of 0.55 and 26. Both
inside. That is a correction to my own eye: I had called the substrate the
loudest defect in the frame twice, and with the grain fix from the second pass
it is within budget. The remaining perception is contrast between adjacent
palette rungs, which is a palette question, not a dither one.

**#3 — the highlight. ✅** All four angles now pass, hero included
(0.0016 / 0.0016 / 0.0043 / 0.0256 against a 0.0015 floor; surface p99 242.9).
What closed it was the third alpha escape — the tank rim on the glass, which
like the water surface wrote a capped alpha (0.30) and so could never blow out
however hot its colour got. The rim is the polished lip directly under the bar
and is the hardest specular in any photograph of a lit aquarium.

**#6 — the room's own ramp. ✅** The neutral bias became a hard exclusion: a
room pixel cannot select a palette rung above 0.35 saturation. Safe to make
hard because `room_like` only fires on low-saturation neutral-bank pixels in
the first place, so a red book or a warm mug is never flagged as room — only
the flat surfaces behind them. The accents are what make a living thing read as
a living thing; a wall that can reach them spends them on plaster.

**#16 — care lands visually. ✅** `CareFeedback` is a grammar rather than a
pile of effects: every action answers the same four questions — where (at the
place it touched), what (a burst whose kind and colour identify it), how big
(proportional to the sim effect, never a constant), how long. `world.play_care_feedback()`
spends it on the transient particle pool and the existing wipe/disturb hooks.
Water change and filter rinse are wired; the rinse fires at the filter intake,
not the tank centre. Before this, the strongest feedback any care action
produced was a flash on the button the player had just pressed.

**#18 — the HUD. 🟡** The footer read `Feed Fl Pt Wm Wf | Care H₂O Fil` on a
1536-wide window with room to spare. The strange part is that it was never
intended: `UiIcons.FEED` carries a readable `name` for every entry and a
comment saying buttons "always show a readable name" — the short form is a
`force_short` fallback for narrow layouts, and both call sites passed a
hardcoded `true`, so the readable path had never once been taken. Compact is
now what it claims to be, keyed to the breakpoint `hud_layout.gd` already
defines so the footer and the stats bar agree about when the window is narrow.
Still open: the eight stat chips and ten rail icons, which are an editorial
cut, not a bug.

**#17 — compose the volume. 🟡, and the diagnosis was wrong.** `ScapeComposition`
measures band occupancy, focal offset and negative space over the LIVE scape,
and the first report contradicted the hypothesis this document had been
carrying: bands **0.539 / 0.329 / 0.132**, every vertical check passing. The
tank was not bottom-heavy. The defect was the fourth axis — focal offset
**0.062**, mass sitting dead centre, which is the one placement every
aquascaping tradition agrees is wrong. The layouts are each a reasonable shape
(two opposite corners, a disc on the origin) whose sum is a centred blob.

Biasing helped, then ran into something better than a ceiling — a existing
test that was right. Measured: **0.062** (no bias) **→ 0.085** (height-weighted
plant pull, so carpets keep their spread) **→ 0.103** (hardscape shifted 0.6
toward the power-point). At that point `smoke_scenario_layouts` failed:
`apex_tank` had **1 corner plant out of 22** and `polyp_lab`'s carpet had drifted
past its contracted radius.

Sliding the wood does not just move the wood. Plants are placed against
`_is_hardscape_occupied`, so a displaced tangle *rejects* the plantings the
layouts are contracted to produce. Bisected to confirm: with the hardscape
shift at 0 and the plant bias untouched, the layout smoke passes. Hardscape and
planting are coupled through occupancy, and moving one without re-authoring the
other trades a composition metric for a layout guarantee.

**Shipped state: plant bias on (capped at 0.9 world units so a corner stays a
corner), hardscape shift wired but off at 0.** And an honest caveat about that
plant bias: across runs at this setting the measured offset came out **0.034
and 0.085**, against 0.062 with no bias at all. The run-to-run spread is as
large as the effect, so *the plant bias alone is not demonstrably moving the
aggregate* — it is a reasonable placement rule that the metric cannot yet
credit. Only the hardscape shift produced a change bigger than the noise, and
that is the one the layout smoke rejected.

Getting past 0.12 needs the layouts to compose *around* a focal mass — a
background stand set back in Z beside the wood — which is a layout change, not
another constant. The metric is in place to grade that work when it happens.

An earlier version of the plant bias was uncapped, and `smoke_scenario_layouts`
caught that too: a `corner_refuge` stem at x = −5.85 with a 0.7 pull toward
+3.0 landed at +2.6, out of the corner the layout exists to make. The cap is
now asserted in `smoke_scape_composition`.

The variance itself is the other finding: item counts range 91–104 between runs
of the *same seed*, because the layout spawn interleaves
`await get_tree().process_frame`. Any composition change smaller than ~0.05 of
measured offset cannot be distinguished from that. Making the scape build
frame-deterministic would be worth doing before tuning composition further —
it is a prerequisite for the metric to be useful at this resolution.

**Not attempted:** #9 (a silhouette budget needs per-fish material wiring
inside a 9.4k-line file, and the payoff is a judgement about apparent size that
wants an eye) and **#10** (reconciling the two resolutions means snapping
several dozen hardcoded geometry constants in `panel_theme.gd` to the render
grid — a large mechanical change whose only failure mode is layouts shifting,
which is exactly what I cannot see from here). Both are left open deliberately
rather than done blind.

**Three traps, all of which produced a silently wrong result rather than an
error**, now in the harness header and the project memory:
- A new `class_name` script is invisible to CLI runs until the editor
  reimports, so a consumer fails to *parse* — and the failure cascades:
  world.gd failed to load and the capture rendered a **single flat colour**
  with nothing in the output to say why. Preload newly-added classes.
- A malformed `%` format string throws inside the print helper, so `quit()`
  never runs and the smoke hangs instead of failing.
- `until ! pgrep -f run_smokes` waits on itself — the poller's own command line
  matches the pattern.

**Needs an eye, not a metric.** Shaders can only be parse-checked headlessly
and the capture harness measures distributions, not taste. The frames in this
tranche are legible and correctly 39 colours; whether the new light shaping and
the lowered grain are *right* is a judgement to make in the editor. The two
knobs to reach for are Render → Light shaping and Render → Palette lock, both
of which return to the old look at 0.
