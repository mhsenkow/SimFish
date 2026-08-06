# 200 Things That Would Make It Look Better

A holistic visual pass over the shipped look, graded against `style-guide/STYLE_GUIDE.md`
and against the actual captures in `artifacts/` and `marketing/`.

Nothing here is a new feature. Every item is "the thing that is already on screen,
but better." Items are ordered by subsystem, not priority — the priority spine is at
the bottom.

## What the captures actually show

Read `marketing/Screenshot 2026-06-03 at 7.59.26 PM.png` and
`artifacts/water-fixed-crop.png` side by side and five problems dominate everything else:

1. **The room is louder than the tank.** Wall, floor and window occupy ~55% of frame
   and carry the *same* dither energy as the tank. The eye has nowhere to rest and no
   reason to look at the aquarium. The style guide asks for the tank at ~70% of frame
   (`STYLE_GUIDE.md` §1); we are nowhere near that.
2. **The tank is not a light source.** In a real dark-room aquarium photo the tank is
   the brightest thing by a wide margin and everything else is silhouette. Here the
   wall is often *brighter* than the water. That single inversion costs more beauty
   than every shader in `shaders/` combined.
3. **The dither is uniform-energy across the whole frame.** `palette_quantize.gdshader`
   does sophisticated region-aware work (saturation, luma, flatness, banks) but has no
   concept of *subject vs. background* — so the floor tiles stipple as hard as a fish.
4. **The floor pattern is producing magenta/pink speckle** that reads as a rendering
   bug, not as a rug. Any viewer's first read of that screenshot is "broken," not "style."
5. **Chrome sits on top of the picture.** Toasts stack three-deep over the tank's upper
   third, the keybind strip is 9px low-contrast text over the substrate, and the top bar
   is one undifferentiated 1400px run of chips.

Fixing 1–5 is worth more than items 6–200 put together.

---

## A. Frame & composition (1–14)

- [x] **1.** **Push the tank to 65–70% of frame width** at the default camera. Currently ~45%.
   This is the single highest-value change in the document and it costs one constant.
- [x] **2.** **Move the default orbit target to the tank's optical centre**, not its geometric
   centre — about 40% up the water column, where the fish traffic is.
- [x] **3.** **Kill the default camera roll.** The captures show a 2–4° tilt that reads as a
   mistake rather than a choice. Snap default yaw/pitch to a composed rest pose.
- [x] **4.** **Give the default view a designed pitch of ~8–12° down**, not the current near-level
   look. Slightly-above reads as "keeper looking into tank"; level reads as "screenshot."
- [x] **5.** **Add a soft camera-distance clamp** so the tank never crops at the left/right edge
   the way it does in `Screenshot ... 7.59.26 PM.png` — a cropped tank wall looks like
   a bug even when it is a legal camera position.
- [x] **6.** **Introduce a rule-of-thirds anchor**: bias the tank so the substrate line lands near
   the lower third and the waterline near the upper third.
- [x] **7.** **Add subtle depth-of-field** with focus locked to the tank centre. Even 1–2px of
   blur on the room instantly separates subject from background.
- [x] **8.** **Vignette should be tank-centred, not frame-centred.** `vignette_strength` in
   `palette_quantize.gdshader` darkens frame corners; if the tank is off-centre the
   vignette fights the composition instead of serving it.
- [x] **9.** **Widen the FOV floor.** 55° default (`main.gd`) at close range gives the strong
   perspective divergence visible on the tank's vertical edges. 40–45° reads calmer
   and more "photographed."
- [x] **10.** **Add a "hero" camera preset** that is the composed shot, and make it the state a
    fresh tank opens in and the state F12/photo mode snaps to.
- [x] **11.** **Letterbox photo mode** to 16:9 or 2:1 with the chrome fully gone — right now
    photo mode still carries HUD residue.
- [x] **12.** **Never let the room's back wall be parallel to the near clip plane.** A dead-flat
    wall filling the left third (as in the captures) is the most boring possible pixel
    budget.
- [x] **13.** **Add a foreground occluder** — the near edge of the tank stand, a plant leaf, a
    dark cabinet corner — in the bottom ~8% of frame. One dark shape in the foreground
    creates instant depth.
- [x] **14.** **Establish a canonical screenshot camera** used by `dev/capture.tscn` so every
    marketing image and store capsule shares one composition.

## B. The room (15–30)

- [x] **15.** **Cut the room's dither strength to ~35% of the tank's.** Add a per-material
    `post_dither_scale` and let the quantize pass read it, so the room quantizes to a
    calmer, flatter, larger-cluster stipple than the water.
- [x] **16.** **Fix the magenta/pink speckle in the floor pattern.** Whatever hue is landing in
    the warm bank on those tiles (`classify_bank` returning 2 on a neutral brown) is
    the single most damaging artifact in the whole capture set.
- [x] **17.** **Desaturate the room by ~30%** relative to the tank. Warm-neutral, low-chroma room
    + saturated tank is the entire "lit aquarium in a dim room" effect.
- [x] **18.** **Darken the room's ambient floor** so the tank's own light is the dominant light in
    the frame. `world.gd` has `ambient_floor` wired — the default is too generous.
- [x] **19.** **Add light spill from the tank onto the room** — a warm/cool pool on the floor and
    a soft rectangle on the wall behind. `_room_tank_spill` and `_room_wall_bounce`
    exist in `world.gd`; they need to be much more visible.
- [x] **20.** **Make the floor pattern larger and lower-contrast.** The current tile scale
    interacts with the dither to produce moiré at typical camera distance.
- [x] **21.** **Break up the back wall** with one large soft gradient (light falloff from the
    window) instead of flat fill.
- [x] **22.** **The window should not be a flat cyan rectangle.** Give it a value gradient,
    a bloom shoulder at the frame edge, and a hint of outside content.
- [x] **23.** **Add a warm bounce on the wall directly behind the tank** so the tank silhouette
    reads against a gradient, not a constant.
- [x] **24.** **Fix the diagonal dark streaks on the left wall** visible in
    `Screenshot ... 7.59.26 PM.png` — these read as shadow acne or a light leak, not
    as architecture.
- [ ] **25.** **Reduce room geometry complexity in the periphery.** Detail near the frame edge
    competes; detail near the tank supports.
- [ ] **26.** **Add a shelf/desk surface with one or two silhouette props** (a bottle, a book) as
    dark shapes only. Silhouettes cost nothing and sell "a room."
- [x] **27.** **Never render the room brighter than the tank's mid-water value.** Enforce this as
    a hard clamp in the lighting update, not a tuning hope.
- [ ] **28.** **Give the room its own palette bank** — a narrow neutral ramp — so it can never
    borrow the fauna accent colors that make the tank special.
- [x] **29.** **Add contact shadow / ambient occlusion under the tank stand.** The tank currently
    floats; a dark contact band grounds it instantly.
- [x] **30.** **Dim the room further at night** so the day/night cycle reads as a change in the
    *room*, not just a tint on the water.

## C. Water volume (31–44)

- [x] **31.** **Increase the top-to-bottom value range of the water column.** Current
    `shallow_color` → `deep_color` spread reads flat at typical camera distance.
- [x] **32.** **Make `depth_absorption` visibly stronger.** Red-first absorption is the most
    legible "this is water" cue and it is currently subtle enough to miss.
- [x] **33.** **Add a horizontal depth gradient too** — the far side of the tank should sit
    deeper in the fog than the near side. `aerial_haze` exists; wire it to actual
    view-depth rather than only column depth.
- [ ] **34.** **Reduce `depth_fog_band_count` from 6 to 4** near the surface and increase it in
    the deep — banding should tighten with depth, not stay uniform.
- [x] **35.** **Add a very slight cyan-shift to the mid-column** so the water reads as a medium
    rather than as a tinted glass sheet.
- [x] **36.** **Give the water a faint volumetric shaft where the fixture beam enters.**
    `god_ray.gdshader` exists — it is barely visible in every capture.
- [x] **37.** **Add depth-scaled contrast reduction on everything seen through water**, not just
    the water itself. Distant plants should lose contrast, not just get bluer.
- [x] **38.** **Make the deep corners of the tank genuinely dark.** Corners are where depth is
    sold; currently they are the same value as mid-water.
- [x] **39.** **Add gentle large-scale flow distortion** — a very low-frequency warp so the
    column feels like moving fluid rather than static tint.
- [x] **40.** **Increase turbidity's visual consequence.** A cloudy tank should be immediately
    legible as cloudy at a glance, not readable only from the chemistry chip.
- [x] **41.** **Add a scatter halo around bright objects underwater.** `murk_glow` exists but is
    gated at 0.16 strength — too shy to register.
- [x] **42.** **Vary the water tint by biotope more aggressively.** Blackwater should be
    unmistakably tea-brown; the current palettes are too close to each other.
- [x] **43.** **Add a subtle warm floor bounce** — light reflecting off the substrate back up into
    the lower water column.
- [ ] **44.** **Make water alpha depth-aware at the glass boundary** so the column doesn't
    visibly "end" at a plane where the mesh does.

## D. Water surface & meniscus (45–56)

- [x] **45.** **Enforce the 1-pixel meniscus line** from `STYLE_GUIDE.md` §1. In the captures the
    waterline is a soft 3–5px gradient, which loses the signature crispness.
- [x] **46.** **Brighten the day side of the meniscus** relative to the water below, per the
    style guide. Currently both sides are near-identical value.
- [x] **47.** **Add a proper above/below-water split** with the warmer, lighter palette above the
    line and cooler below — same value range so it reads as one image.
- [x] **48.** **Make surface reflection actually mirror the room.** `surface_reflection` at 0.24
    with a flat `room_sky_color` gives a tint, not a reflection.
- [ ] **49.** **Add drifting surface film/biofilm** as a slow low-contrast pattern on the top cap.
- [x] **50.** **Strengthen the underside-mirror effect** when the camera goes below the waterline
    — this is one of the most beautiful real-aquarium phenomena and it's nearly absent.
- [x] **51.** **Add ripple rings from feeding and from surface-breaking fish**, expanding and
    fading. `pond_dimple_points` supports 12 points and is underused.
- [x] **52.** **Give the surface a specular glint band** that tracks the light fixture position.
- [x] **53.** **Make wave amplitude respond to flow/filter output** so the surface tells you the
    pump is running.
- [x] **54.** **Add a bright rim where the water meets the glass** on all four sides, not just
    corners on polygon tanks.
- [ ] **55.** **Animate the meniscus subtly with the waves** so the waterline breathes rather than
    sitting perfectly level.
- [ ] **56.** **Fix the surface plane depth in the Metal/compat path** — `artifacts/smoke_window.png`
    shows the waterline at an obviously wrong height relative to the tank.

## E. Glass (57–66)

- [x] **57.** **Add a specular streak on the front glass** — a soft diagonal highlight. This is
    the cue that says "there is glass between you and this."
- [x] **58.** **Add a dark glass edge/frame line** at the tank's silhouette so the tank reads as
    a contained object rather than an open box.
- [x] **59.** **Add faint fingerprints/water spots** on the front pane, very low contrast, static.
- [x] **60.** **Give the glass a Fresnel rim** that brightens at grazing angles as you orbit.
- [x] **61.** **Add a subtle green edge tint** on the glass thickness where you see it edge-on —
    real aquarium glass is green in section.
- [ ] **62.** **Add a soft reflection of the room** in the front glass at low opacity, so orbiting
    the camera changes what the glass shows.
- [x] **63.** **Make the silicone seams visible** as thin dark lines in the tank corners.
- [x] **64.** **Add a bright caustic band on the glass at the waterline** where surface light
    concentrates.
- [ ] **65.** **Ensure glass never fully hides fauna.** Right now `glass.gdshader` + the quantize
    pass together can wash a fish's silhouette out — creature outline should win.
- [ ] **66.** **Add condensation on the inside of the lid** as a dim scatter, especially at night.

## F. Light & time of day (67–80)

- [x] **67.** **Make the fixture a visible light source** — a bright emissive bar with a bloom
    shoulder, not the dark strip visible in the captures.
- [x] **68.** **Add a cone of light from the fixture into the water** that is visible in the air
    gap above the waterline.
- [x] **69.** **Increase the day/night value swing.** The night captures are only marginally
    darker than day; night should be dramatic.
- [x] **70.** **Give dawn and dusk distinct color identities**, not just interpolated positions
    between day and night.
- [x] **71.** **Add a warm-to-cool shift across the fixture's throw** — warmer at the centre,
    cooler at the edges.
- [ ] **72.** **Make the night palette LUT do more work.** `palette_tex_night` exists; the current
    night blend is close enough to a uniform darken that the LUT's value is invisible.
- [x] **73.** **Add moonlight from the window at night** as a cool directional rim, giving the
    room a second light and the tank a silhouette edge.
- [ ] **74.** **Ramp lighting changes over minutes, not seconds** — the transition itself should
    be a thing worth watching.
- [x] **75.** **Make `selective_glow` on by default at a modest value.** Emissive coral and
    biofilm shimmer are among the prettiest things in the build and they are gated off.
- [x] **76.** **Bloom should have colour, not just brightness.** `hot_white` at
    `vec3(1.0, 0.97, 0.90)` neutralises everything hot to the same cream.
- [ ] **77.** **Add light flicker on the fixture** at very low amplitude — a fluorescent tell.
- [x] **78.** **Add caustic projection onto the room floor** in front of the tank when the fixture
    is on. Enormous payoff for a small effect.
- [ ] **79.** **Shadow the substrate under dense plant cover** so planting density is legible as
    light rather than only as geometry.
- [ ] **80.** **Make the "lights out" moment a designed beat** — a short dim ramp with the tank
    holding its glow last.

## G. Substrate (81–92)

- [x] **81.** **Kill the horizontal banding on the substrate** visible in
    `artifacts/smoke_window.png` — hard value steps across the whole floor read as a
    z-fighting bug.
- [x] **82.** **Add grain-scale variation** so the substrate isn't one uniform noise field —
    coarser near the front glass, finer at depth.
- [x] **83.** **Add a darker band where substrate meets glass** — real tanks show a dark
    compaction line there.
- [ ] **84.** **Feather the angle-of-repose slope with 50% dither** per `STYLE_GUIDE.md` §4.
    Currently the slope edge is hard.
- [ ] **85.** **Give the substrate a colour ramp with depth**, darker below, so digging and
    contouring reads.
- [x] **86.** **Add scattered lighter grains** — a few 1px bright specks — to give the surface
    micro-texture at the pixel scale.
- [x] **87.** **Reduce substrate saturation.** It currently competes with the plants for the
    warm bank.
- [ ] **88.** **Add detritus accumulation as a visible dark dusting** in low-flow corners.
- [ ] **89.** **Make plant root zones visibly darker/richer** than open substrate.
- [ ] **90.** **Add a subtle specular sheen on wet sand** near the front glass.
- [ ] **91.** **Make substrate caustics track the surface waves** rather than running on their own
    independent time (`substrate_caustic.gdshader` vs. `water.gdshader` phase).
- [ ] **92.** **Vary substrate colour by biotope** with the same conviction as the water tint.

## H. Hardscape (93–100)

- [x] **93.** **Give rock and wood a real value range.** In the captures the driftwood is one
    flat dark shape with no form.
- [x] **94.** **Add moss/algae growth in crevices** as a colour break on hardscape.
- [x] **95.** **Add a hard dark outline on hardscape silhouettes** — per style guide §3, hard
    edges should not dither.
- [ ] **96.** **Add wet specular on hardscape near the waterline.**
- [ ] **97.** **Vary rock hue slightly per instance** so a pile of stones isn't one colour blob.
- [ ] **98.** **Add ambient occlusion where hardscape meets substrate.**
- [ ] **99.** **Make driftwood tannin-stain the water locally** — a warm gradient near the wood.
- [ ] **100.** **Add a contact shadow beneath every hardscape piece.**

## I. Plants (101–114)

- [x] **101.** **Increase leaf-to-leaf value variation.** Current foliage reads as a single green
     mass; depth within a plant is what makes planted tanks beautiful.
- [x] **102.** **Add translucency on backlit leaves.** `stem_subsurface.gdshader` exists at 16
     lines — this deserves far more.
- [x] **103.** **Vary green hue across species** more aggressively — the palette has 8 green
     slots and the plants use maybe 3.
- [ ] **104.** **Add new-growth colour** — lighter, yellower tips on actively growing stems.
- [x] **105.** **Make sway amplitude scale with height above substrate**, so tall stems move and
     rosettes at the base stay put.
- [x] **106.** **Desynchronise sway phase per plant.** Any visible synchrony instantly reads fake.
- [ ] **107.** **Add pearling bubbles on leaf surfaces** during high photosynthesis — the single
     most iconic planted-tank visual.
- [ ] **108.** **Add leaf-edge highlight** where light hits the leaf silhouette.
- [ ] **109.** **Give floating plants visible root trails** hanging into the column.
- [ ] **110.** **Add algae as a visual state on old leaves**, not just a stat.
- [ ] **111.** **Make plant density read as depth** — reduce contrast on plants further from
     camera so the planting has layers.
- [ ] **112.** **Add occasional leaf detachment and slow drift** to the substrate.
- [ ] **113.** **Vary leaf shapes more within a species** (`leaf_shapes.gd` supports it) so no two
     plants are stamped identical.
- [ ] **114.** **Make the plant's response to the light cycle visible** — leaves opening and
     closing across day/night.

## J. Creatures (115–130)

- [x] **115.** **Increase fish size on screen at the default camera.** At the composed distance
     they are 4–6px, which is the style-guide minimum, not a target. Either bring the
     camera in or bump body scale.
- [x] **116.** **Guarantee the single-pixel eye** at all zoom levels (`STYLE_GUIDE.md` §4).
     The eye is what makes a 6px sprite read as alive.
- [x] **117.** **Boost fish silhouette contrast against the substrate.** In the captures, mid-tone
     fish over mid-tone sand disappear.
- [x] **118.** **Turn `creature_outline_strength` on by default at a modest value.** It exists
     precisely for this and defaults to 0.
- [x] **119.** **Add a bright belly / dark back countershade** on every species — it is what makes
     fish read as three-dimensional at tiny sizes.
- [x] **120.** **Add iridescent flash** when a fish turns broadside to the light — a one-frame
     bright band. This is the prettiest possible 3-pixel effect.
- [x] **121.** **Vary fish colour slightly per individual** so a shoal isn't one repeated sprite.
- [x] **122.** **Make fins semi-transparent** with a slightly different hue from the body.
- [x] **123.** **Add motion-driven body bend** so turning is visible in silhouette, not just in
     heading.
- [ ] **124.** **Add a subtle drop shadow / caustic interaction on fish** passing near the
     substrate.
- [ ] **125.** **Make shrimp and snails visually distinct at a glance** — currently they read as
     substrate speckle.
- [ ] **126.** **Add antennae twitch on shrimp** as a 1px animated detail.
- [ ] **127.** **Give juveniles a distinct paler colouring** so growth is visible.
- [ ] **128.** **Add a stress/health visual** — colour desaturation and fin clamping — so a sick
     fish looks sick.
- [ ] **129.** **Add a spawning colouration state** for breeding fish.
- [ ] **130.** **Make the focused/selected creature visually unmistakable** — a soft halo or a
     brightened palette bank, not just a UI card appearing.

## K. Particulate, scale & atmosphere (131–140)

- [x] **131.** **Add suspended detritus motes** drifting in the column with slow parallax — the
     cheapest possible "this is a volume of water" cue.
- [x] **132.** **Scale mote density with turbidity** so water quality is visible as particles.
- [x] **133.** **Add micro-bubbles from the filter outflow** rising in a visible stream.
- [x] **134.** **Add bubble size classes per `STYLE_GUIDE.md` §4** — 1px, 2×2, 3×3 cross, 4×4 with
     highlight. Current bubbles are one size.
- [x] **135.** **Add ±1px lateral bubble wobble** per style guide — bubbles currently rise dead
     straight.
- [ ] **136.** **Add dust motes in the room's window light shaft.**
- [ ] **137.** **Add a slow convection drift** in the water so even a still tank is never static.
- [ ] **138.** **Add surface-skimming particles** that collect at the waterline in low flow.
- [ ] **139.** **Give particles depth-appropriate contrast** — far motes dimmer, near motes sharper.
- [ ] **140.** **Add a rare bubble burst at the surface** with a 2-frame pop.

## L. The quantize / post pass (141–156)

- [x] **141.** **Add a subject/background dither split.** The pass has saturation, luma, flatness
     and bank awareness but no notion of "this pixel is the tank." A depth or stencil
     input driving a `dither_scale` would fix the frame's biggest problem in one uniform.
- [x] **142.** **Lower overall `dither_strength` from 0.85.** At the current internal resolution
     the stipple is at the edge of reading as noise rather than as gradient.
- [x] **143.** **Raise `internal_resolution` above 384×216 for large displays.** At 4K the
     upscale factor is 10× and every dither dot is a 10px block.
- [x] **144.** **Make dither cell size resolution-independent** so the look is identical at 1080p
     and 4K rather than getting chunkier as the window grows.
- [x] **145.** **Turn on `dither_world_lock` by default.** Camera pans currently make the entire
     stipple field crawl, which is the most fatiguing artifact in motion.
- [ ] **146.** **Reduce `blue_noise_amount` on the substrate** — IGN noise on a large flat brown
     field is exactly where it looks most like film grain and least like art.
- [x] **147.** **Cap outline generation on the room.** `outline_subject_bias` at 0.65 still lets
     the wall and floor generate edges.
- [ ] **148.** **Fix the false outlines on caustic edges.** The `caustic_false` suppression at
     0.78 is not enough — moving caustics still ink themselves.
- [ ] **149.** **Make `bloom_threshold` day/night aware** so highlights burn through at night
     without blowing out at noon.
- [x] **150.** **Reduce `hdr_lift` maximum from 0.85.** Emissives currently clip to near-white and
     lose all hue.
- [x] **151.** **Turn `film_grain_strength` off by default.** Grain on top of dither is two noise
     fields fighting.
- [x] **152.** **Ship CRT off by default.** In every capture it costs more legibility than it buys
     character; make it an opt-in flavour.
- [x] **153.** **Make `health_grade` desaturation more visible.** A stressed tank should look
     visibly sick; the current 0.18 luma pull is imperceptible.
- [x] **154.** **Add an explicit palette-count debug overlay** per `STYLE_GUIDE.md` §8 so the
     ≤48-colour rule is verifiable rather than assumed.
- [ ] **155.** **Cheapen the outline pass** — it currently costs 8 texture taps per fragment
     across two blocks that sample the same neighbours. Share the taps.
- [ ] **156.** **Guarantee nearest-neighbour upscale at all window sizes.** Non-integer scale
     factors are producing the soft, slightly-wrong pixels visible in the marketing
     shots.

## M. Palette discipline (157–166)

- [ ] **157.** **Audit the actual on-screen colour count.** The captures look like far more than
     48 colours, mostly because the room and UI are outside the palette system.
- [x] **158.** **Bring the UI into the palette.** `panel_theme.gd` uses hand-picked blues
     (`Color(0.22, 0.58, 0.88)`) that appear nowhere in the 48-colour palettes.
- [x] **159.** **Fix `classify_bank`'s brown handling.** The heuristic at
     `palette_quantize.gdshader:158` is the likely source of the magenta floor speckle.
- [ ] **160.** **Give the neutral bank more slots.** With a third of the palette on neutrals and
     the room, substrate, stone and wood all competing, the neutral ramp is starved.
- [x] **161.** **Make the three biotope palettes visibly different at a glance.** Blackwater
     currently reads as "planted, slightly browner."
- [ ] **162.** **Reserve 3–4 accent slots exclusively for fauna** so nothing in the environment can
     ever borrow a fish's colour.
- [ ] **163.** **Build the night LUT by hand**, not by darkening the day LUT — the whole point of
     a second LUT is a different hue relationship.
- [ ] **164.** **Add a warm/cool split within the neutral ramp** so the room can be warm-neutral
     and the tank cool-neutral without leaving the palette.
- [ ] **165.** **Verify all palette PNGs are 48×1 with no interpolation** and `filter_nearest`
     everywhere (already set in the shader, worth asserting at load).
- [x] **166.** **Document the palette index layout** so future work knows which indices are which
     bank without reading `classify_bank`.

## N. HUD & stat chips (167–178)

- [x] **167.** **Break the top bar into visual groups with real gaps**, not just dividers. Nine
     chips in one 1400px run is unscannable.
- [ ] **168.** **Give primary chips visibly more weight than tertiary.** The current 3px vs 2px
     left border is not a hierarchy anyone perceives.
- [x] **169.** **Shrink the top bar's footprint.** It currently spans nearly the full width for
     information that would fit in half.
- [x] **170.** **Replace the raw numeric sublabels** (`29 14A 15J · 29/69`) with something a
     player can parse. This is opaque even to someone who knows the sim.
- [x] **171.** **Move the top bar off the tank.** It overlaps the tank's upper edge in every
     capture.
- [x] **172.** **Make the idle-dim more aggressive.** `HUD_DIM_MODULATE` at 0.45 alpha after 6s
     is good instinct — take it to 0.2 and 4s.
- [ ] **173.** **Add a units row or tooltip legend** so `18A 0F · 29/21` is decodable without
     opening a panel.
- [x] **174.** **Align chip baselines.** Emoji and text currently sit on different baselines,
     giving the bar a visible wobble.
- [ ] **175.** **Give the chip accent colours meaning.** Three chips currently share
     `Color8(214, 176, 112)`, which defeats the "eye can find each category" intent
     stated in the code comment.
- [ ] **176.** **Add a sparkline directly in the chip** for the primary three rather than
     requiring a click.
- [ ] **177.** **Make the alert chip visually escalate** — colour and pulse — rather than just
     counting.
- [x] **178.** **Drop the bottom keybind strip from the default view.** 9px low-contrast text over
     the substrate is unreadable and it dirties every screenshot.

## O. Rail & icons (179–186)

- [x] **179.** **Pick one icon language.** `ui_icons.gd` mixes colour emoji (🐟 🦐 🌿 💧 🔔 📚 🪨 💡)
     with monochrome geometric glyphs (◴ ♥ ✦ ⚠ ▦ ♪ ⚙ ≡ ⛶). This is the most visible
     inconsistency in the entire UI.
- [x] **180.** **Commission or draw a monochrome pixel icon set** at 16×16 in the palette. It
     removes the emoji font dependency that forced the ASCII mobile fallback entirely.
- [ ] **181.** **The two-letter mobile fallbacks** (`Pi`, `Sc`, `Cr`, `Ad`, `Lb`) are unreadable as
     icons — a real icon set makes them unnecessary.
- [ ] **182.** **Give the rail consistent icon optical sizing.** ⚙ and ♪ render much smaller than
     🐟 at the same font size.
- [x] **183.** **Add a clearer active state** on rail buttons — the current
     `RAIL_ACTIVE_BG` is barely distinguishable from hover.
- [ ] **184.** **Group the rail** with separators matching the top bar's grouping logic.
- [ ] **185.** **Move the notification badge** off the bell glyph's corner — it currently collides
     with the glyph at small sizes.
- [x] **186.** **Fade the rail with the HUD idle-dim** so focus mode is the natural resting state.

## P. Panels, toasts & type (187–194)

- [x] **187.** **Move the toast stack out of the tank's frame.** Three stacked cards over the
     upper-right of the tank is where the composition is best and the chrome is worst.
- [x] **188.** **Cap the toast stack at two** and collapse the rest into the bell count.
- [x] **189.** **Give toasts an entry/exit animation** — they currently pop.
- [x] **190.** **Reduce panel background opacity.** `BG` at 0.92 alpha is nearly opaque; 0.75 with
     a blur would let the tank stay present behind panels.
- [x] **191.** **Tie panel border colour to the biotope palette** so the UI belongs to the tank
     it's describing.
- [x] **192.** **Establish a real type scale.** Currently sizes are passed ad-hoc through
     `scaled_size()`; three or four fixed steps would read far more composed.
- [x] **193.** **Increase body text contrast.** `DIM_FG` at 0.75 alpha over a 0.92-alpha dark panel
     is below comfortable reading contrast.
- [x] **194.** **Round corners consistently.** The chips use 4px, panels use a different radius,
     rail buttons another.

## Q. Motion, transitions & first impression (195–200)

- [x] **195.** **Add a designed opening shot.** A tank should open on a slow push-in to the hero
     camera, not snap to the last camera position.
- [x] **196.** **Ease every camera move.** Orbit and zoom currently stop dead; a short ease-out
     transforms how the whole thing feels.
- [x] **197.** **Cross-fade the day/night palette transition** over a longer window so it is a
     mood shift rather than a state change.
- [x] **198.** **Add a photo-mode flash and shutter feel** — this is the moment players share.
- [x] **199.** **Make the tank menu previews use the hero camera** so the thumbnail sells the
     tank.
- [x] **200.** **Re-shoot the marketing screenshots** after items 1–5. Every current capsule image
     in `marketing/` shows the room-dominates-tank problem, and store art is the first
     visual anyone sees. *(Manual step — composition fixes ship in-engine; re-capture when ready.)*

---

## The spine — if only ten of these get done

In order. The first five are worth more than the rest of the document.

1. **#1** — tank at 65–70% of frame.
2. **#2, #27** — tank is the brightest thing; room clamped below mid-water value.
3. **#15, #141** — room dithers at a third of the tank's strength.
4. **#16, #159** — kill the magenta floor speckle.
5. **#171, #178, #187** — chrome off the picture: top bar, keybind strip, toast stack.
6. **#118, #117** — creature outlines on, fish readable against substrate.
7. **#45, #46** — the 1px meniscus, brighter above than below.
8. **#179, #180** — one icon language.
9. **#145** — world-locked dither, no crawl on pan.
10. **#67, #78** — the fixture as a visible light source, casting caustics into the room.
