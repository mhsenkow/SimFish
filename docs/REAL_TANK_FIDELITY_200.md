# 200 Steps to a Tank That Looks Like the Real One

Graded against photographs of the actual aquariums this game is based on — not
against aquascaping-competition photos, not against the style guide's ideal
frame. The reference set is three tanks:

- **Tank A — the snail bar.** Mixed pea gravel banked against one layered ochre
  stone, a fine-bubble airstone running a visible column, hazy water, and a
  large grazing snail population (pond snails, Malaysian trumpets). Almost no
  plants. Shot close, through the front corner, at gravel height.
- **Tank B — the vallisneria jungle.** Blades floor-to-surface and then bending
  over and lying along it. A ramshorn colony working the soil line with a drift
  of empty shells collecting in the low spot. Guppies and fry in the blades.
  Hair algae on the old leaves. Backlit warm-orange through the green.
- **Tank C — the counter nano.** Small rimless cube on a bathroom counter under
  a clip-on gooseneck LED, airline arcing in over the rim. One upright stone,
  one branch, moss over both, and a thick floating mat of duckweed and salvinia
  with a hyacinth rosette. Green dust on the glass. Tweezers on the mat.

These three now ship as scenarios (`snail_bar`, `valli_jungle`, `counter_nano`
in `scenario_picker.gd`, with matching entries in `TankConfig.TANK_PRESETS` and
a new `counter_mirror` room). This document is the backlog that makes those
scenarios actually *look* like their references.

Sibling document: [VISUAL_POLISH_200_IDEAS.md](VISUAL_POLISH_200_IDEAS.md),
which is about the frame and the post-process. This one is about the tank.

---

## What the photographs have that we don't

Eight observations dominate. Everything in sections A–M is downstream of one of
them.

1. **The substrate is a cross-section, not a surface.** In every photo the front
   glass shows the bed in *layers* — dark soil at the bottom, a gravel or sand
   cap on top — and the boundary between them is a wavy, mixed, disturbed line
   where snails and roots have ploughed the two together. That vertical band
   occupies 15–25% of the frame and does an enormous amount of the "this is a
   real tank" work. We render the substrate as a top surface with a flat side
   wall. This is the single biggest gap in the document.

2. **Nothing is clean.** Green dust on the glass, biofilm haze, hair algae on
   the old leaves, detritus caught between gravel grains, a drift of empty
   snail shells in the low spot. Our tanks read as scaped ten minutes ago and
   photographed immediately. A tank that somebody lives with has a patina, and
   the patina is *legible history* — it tells you the tank is six months old
   without a single UI element saying so.

3. **The water is a medium, not empty space.** Tanks A and C are visibly hazy —
   fine particulate and bacterial bloom scattering the light. Contrast falls off
   with depth, the back glass is milkier than the front, and the bubble column
   has a visible glow around it. We treat water as approximately free.

4. **Equipment is in shot and it is not shy.** Airline tubing arcs over the rim
   with a visible bend radius. The airstone is a physical object with a column
   above it. The clip-on LED has an arm, a clamp, a cable, and a hard-edged
   pool of light directly under it. Tweezers lie on the mat. Real tanks are
   plumbed and it reads as authenticity, not clutter.

5. **The photographs are photographs.** Handheld and slightly off-level. Focus
   falls off past the subject. The room reflects on the glass. The low-iron
   glass edge glows blue-green. There is chromatic fringing on high-contrast
   glass edges, and in one shot the photographer's phone is visible in the
   mirror. Our captures are rendered by a camera that is perfectly level,
   perfectly focused, and invisible.

6. **Plants are individuals with histories.** The valli blades in Tank B are
   different lengths, some torn, some with melted brown tips, some carrying
   algae, and the tallest ones do not stop at the surface — they bend over and
   lie *along* it, which is why the light comes through a green wall instead of
   down onto a scape.

7. **The surface is a busy interface, not a plane.** Duckweed clusters and
   drifts. Salvinia sits proud. A hyacinth rosette trails roots down the whole
   column. There's a scum line where the mat meets the glass, dimples from
   agitation, and bubbles trapped under the floating leaves.

8. **The snails are the population.** Not three decorative ones — dozens, of
   three species, at every size from 2 mm to 25 mm, on every surface including
   upside-down under the surface film, and they leave grazing tracks in the
   biofilm.

---

## A. The substrate as a cross-section (1–20)

The highest-value section in the document. Items 1–6 alone move the reference
tanks further than the whole of section J.

- [x] **1.** **Render the substrate as stratified layers, not one material.**
   `substrate_opaque.gdshader` needs a depth-parameterised colour ramp so the
   bed is dark soil at the bottom and cap material on top. Everything else in
   this section depends on item 1 landing first.
- [x] **2.** **Make the layer boundary wavy, not flat.** Sample a low-frequency
   noise into the layer-split depth so the soil/cap interface undulates by
   ±15% of the cap thickness. A ruler-straight boundary reads as a diagram.
- [x] **3.** **Mix the two layers at the boundary** over a band ~30% of the cap
   thickness — gravel grains sunk into soil, soil pushed up between grains.
   Real substrate interfaces are a zone, not a line.
- [x] **4.** **Expose cap depth and soil colour as substrate-profile fields** so
   `inert_gravel` (Tank A: thick pale cap) and `aquasoil` (Tank B: thin cap over
   near-black soil) read as different tanks at the glass.
- [x] **5.** **Deepen the substrate on the reference presets.** The photos run
   25–30% of tank height in substrate. Our default 23% with the camera above
   the bed hides the cross-section entirely.
- [x] **6.** **Make the front-glass substrate band a deliberate composition
   element** — the default camera for these scenarios should place the bed line
   low enough that the layered band is visible along the bottom of frame.
- [x] **7.** **Individual grains at the glass.** The cap in the photos resolves
   to discrete pebbles at the contact surface — mixed sizes, mixed colours,
   distinct outlines. A noise texture doesn't do this; a scattered-disc
   impostor layer on the inside face of the substrate wall does.
- [x] **8.** **Give grains a colour population, not a tint.** Tank A's gravel is
   maybe 8 distinguishable pebble colours — cream, tan, slate, rust, near-black,
   one translucent quartz. Sample from a small palette per grain, not a
   continuous ramp.
- [x] **9.** **Vary grain size with depth.** Fines settle. The bottom of the cap
   should be visibly finer-grained than the top.
- [x] **10.** **Darken the substrate with depth** independent of lighting — the
   deep bed is anoxic and near-black even where light reaches the glass.
- [x] **11.** **Add root penetration into the cross-section.** Pale hair-roots
   visible against dark soil at the front glass is one of the most convincing
   details a planted tank has, and it directly rewards the plant sim we already
   run.
- [x] **12.** **Root density should track the plant above it** so the valli wall
   in Tank B shows a dense root mat and Tank A's bare gravel shows none.
- [x] **13.** **Malaysian trumpet snail tunnels.** MTS burrow, and their tunnels
   are visible against the front glass as pale voids. We already spawn
   `trumpet_snail.gd` — give it a persistent trace in the substrate grid.
- [x] **14.** **Let the snails actually disturb the layer boundary over time.**
   A tank with MTS mixes its cap into its soil over months. Make that a slow
   drift in the boundary noise amplitude, seeded from live MTS count.
- [x] **15.** **Detritus accumulating between grains.** Dark fines settling into
   the interstices of the cap, densest where flow is lowest. Ties into the mulm
   system already in `world.gd`.
- [x] **16.** **Substrate slope must be visible at the glass.** Tank A banks
   gravel against the stone and thins it to nearly nothing at the front — the
   changing band height across the frame is what makes it read as a real
   deposit rather than a fill level.
- [x] **17.** **Sharpen the substrate-to-glass contact.** In the photos there's a
   hard line where grains press against glass, with a faint wet-dark ring
   around each contact point. We currently fade the substrate into the wall.
- [x] **18.** **A gas pocket or two.** Established soil substrates trap gas; the
   bubbles sit against the glass as small bright lenses and occasionally
   release. Rare, cheap, and enormously convincing.
- [x] **19.** **Substrate colour should shift when wet vs. at the waterline** —
   the few millimetres of cap above the waterline in a low-fill tank are
   visibly paler and drier.
- [x] **20.** **Age the cap.** A one-week-old gravel cap is bright and sorted; a
   one-year-old cap is dulled, biofilmed and colour-shifted toward olive. Drive
   from tank age.

## B. Glass — the thing you're actually looking through (21–38)

- [x] **21.** **Green dust algae on the glass as a real, growing layer.** Present
   on all three reference tanks and completely absent from ours. It should
   accumulate with light and nutrients, and be *cleared by the player wiping
   it* — a maintenance action with a visible result.
- [x] **22.** **Grazing tracks through the dust.** Snails eat radiating clean
   paths through green dust. This is the single most distinctive real-tank
   detail in the whole reference set, and it makes the snail population legible
   as *behaviour* rather than decoration.
- [x] **23.** **Tracks should fade and regrow** over hours, so an active tank
   shows a shifting map of where the snails have been.
- [x] **24.** **Uneven dust distribution** — heaviest on the light-facing panel,
   thin at the front where the keeper wipes, near-total at the back.
- [x] **25.** **Low-iron glass edge glow.** The blue-green luminous edge visible
   on every rimless tank in the photos. `glass.gdshader` should carry an
   edge-thickness term that emits toward cyan.
- [x] **26.** **Silicone seam lines** in the corners — a dark few-pixel bead the
   full height of each vertical joint, and along the base.
- [x] **27.** **The black base trim.** Tanks A and C sit on a black plastic or
   painted base band that reads as a hard dark stripe under the substrate.
- [x] **28.** **Room reflections on the front glass** — a low-opacity, blurred,
   *vertically flipped* reflection of the room, strongest where the water
   behind is darkest. This is what makes glass read as glass.
- [x] **29.** **Reflection strength should follow view angle**, near-invisible
   head-on and strong at grazing incidence, which is exactly the geometry of
   the corner shots in the reference set.
- [x] **30.** **Water-line refraction offset.** Objects crossing the waterline
   break sideways. The airline tube in Tank C does this visibly.
- [x] **31.** **Double-image at the corner.** Looking through two panes at an
   oblique angle gives a faint offset ghost — visible along the right edge of
   both Tank A shots.
- [x] **32.** **Salt creep / hard-water spots** above the waterline on the inside
   glass — pale crusty speckle where evaporation left minerals.
- [x] **33.** **A visible waterline ring** on the inside glass: a thin dark line
   with a slightly brighter meniscus just above it.
- [x] **34.** **Fingerprints and wipe smears** on the outside glass, low opacity,
   only visible against dark water.
- [x] **35.** **Chromatic fringing on high-contrast glass edges** — a 1px warm/cool
   split. Currently only the post-process CRT mode does anything like this;
   it belongs on the glass specifically.
- [x] **36.** **Snails on the inside of the glass, seen from the foot side.**
   The reference photos show the muscular foot pressed flat against glass with
   the radula visibly rasping. That's a distinct render case from a snail seen
   from outside and it deserves its own treatment.
- [x] **37.** **Condensation on the outside** for a cool-room tank — soft,
   low-frequency, only on the lower third.
- [x] **38.** **Let the glass get in the way sometimes.** A slightly-too-close
   camera should produce the exact corner distortion the photos have, not a
   clean clip. Currently the camera clamp treats that as a bug to prevent.

## C. Water as a medium (39–54)

- [x] **39.** **Add turbidity as a first-class water property.** Tanks A and C
   are visibly hazy. Drive it from bacterial bloom, disturbed substrate, and
   recent feeding; decay it over hours.
- [x] **40.** **Depth-dependent contrast falloff.** The back glass in every photo
   is milkier and lower-contrast than the front. This is one uniform in
   `water.gdshader` and it buys more realism than any other single line here.
- [x] **41.** **Colour shift with depth**, not just fog density — long
   wavelengths go first, so distant objects drift green-blue even in a warm-lit
   tank.
- [x] **42.** **Suspended particulate.** Slow-drifting motes catching the light,
   densest just after feeding or a substrate disturbance.
- [x] **43.** **Particulate should follow the flow field** we already simulate in
   `tank_flow_field.gd` — free realism from an existing system.
- [x] **44.** **Visible glow around the bubble column.** Light scattering through
   the dense bubble stream in Tank A produces a soft halo. Cheap additive
   billboard, big payoff.
- [x] **45.** **Tannin staining as a colour ramp on the water volume**, not a
   post-process tint, so it deepens with depth the way tea does.
- [x] **46.** **Surface-to-substrate light attenuation** should visibly darken
   the bed in a tall tank. Tank B's floor is much darker than its surface.
- [x] **47.** **Bacterial bloom should look like milk, not fog** — it scatters
   forward and washes contrast rather than adding grey.
- [x] **48.** **Let the water settle visibly after a disturbance** — turbidity
   spikes when the player plants or moves hardscape, then clears over minutes.
- [x] **49.** **Micro-bubbles clinging to surfaces** after a water change: a
   dusting of tiny bright dots on glass, leaves and hardscape that slowly
   releases.
- [x] **50.** **Convection shimmer near the heater** — a subtle vertical
   refraction distortion column.
- [x] **51.** **Thermal layering.** A faint horizontal refraction seam where warm
   surface water meets cooler deep water in an unstirred tank.
- [x] **52.** **The water should have a colour of its own** in the reference
   tanks — Tank B's is faintly green-gold from the light through the valli
   before it's anything else.
- [x] **53.** **Reduce the caustics' authority.** In the real photos caustics are
   subtle and only present where the surface is calm and the light is direct.
   Under a floating mat there are none at all.
- [x] **54.** **Caustics must be occluded by floating plants.** Tank C's floor is
   caustic-free under the duckweed mat and bright in the one open patch — that
   contrast is most of the shot's depth.

## D. The surface interface (55–72)

- [x] **55.** **Floating plants should cluster and drift, not distribute evenly.**
   Duckweed piles against downwind glass and leaves open water elsewhere.
- [x] **56.** **Coverage should be genuinely high.** Tank C is ~70% covered. Our
   floater cap and spacing rules top out far below what a real floating garden
   looks like.
- [x] **57.** **Multiple floating species at different scales** in the same mat —
   duckweed (tiny), salvinia (medium, proud of the surface), hyacinth (large
   rosette). The size hierarchy is what makes the mat read as a community.
- [x] **58.** **Hanging roots as a real vertical element.** The hyacinth in Tank C
   trails roots most of the way down the column. Currently floater roots are
   token.
- [x] **59.** **Roots should sway on the flow field** independently of the leaf
   above them.
- [x] **60.** **Root biofilm.** Fuzzy pale accumulation on older roots, which the
   microfauna sim already models — surface it visually.
- [x] **61.** **A scum line at the glass** where the floating mat meets the pane —
   a compressed, slightly discoloured band.
- [x] **62.** **Protein film on open water** in a low-agitation tank: a faint
   iridescent sheen that breaks up where the surface is disturbed.
- [x] **63.** **Surface dimples from agitation.** The Tank C photos show a
   distinct field of small circular depressions where the airline outflow hits
   the surface.
- [x] **64.** **Bubbles trapped under floating leaves** — bright lenses on the
   underside, visible when the camera is below the waterline.
- [x] **65.** **Bubbles bursting at the surface** with a brief ring ripple, not
   just disappearing.
- [x] **66.** **The bubble column should widen and slow as it rises**, and drift
   with the flow field rather than going straight up.
- [x] **67.** **Bubble size variation** — a fine-bubble airstone makes a
   distribution, not a single size.
- [x] **68.** **The surface as seen from below.** Total internal reflection turns
   most of the underside of the surface into a mirror. From a low camera in
   Tank B you should see the tank reflected in its own surface.
- [x] **69.** **Emergent growth breaking the surface.** Valli blades that reach
   the top bend and lie along it — see item 113, the single biggest plant item
   in the document.
- [x] **70.** **A meniscus climb** where the water meets the glass, a few pixels
   of upward curve with a bright edge.
- [x] **71.** **Floating plants should shade what's under them** and that shading
   should feed the light model the plants below are growing in.
- [x] **72.** **Let the mat get pushed around by feeding and by the player's
   hand** — a physical response to interaction makes the surface feel material.

## E. Algae, biofilm and the patina of time (73–92)

- [x] **73.** **Hair algae on old leaves.** Present throughout Tank B, absent from
   our render. Should attach preferentially to the oldest, slowest-growing
   leaves and to hardscape edges in the flow.
- [x] **74.** **Hair algae should sway** on the flow field — static algae reads as
   a texture, moving algae reads as alive.
- [x] **75.** **Green dust algae on glass** — see item 21; it belongs in this
   section too because it should share one algae-growth model.
- [x] **76.** **Green spot algae** as discrete hard dots on glass and on the
   oldest anubias-type leaves. Different organism, different look, doesn't wipe
   off as easily.
- [x] **77.** **Black brush algae** on hardscape edges facing the flow — dark,
   tufted, and the visual signal of an established but slightly-off tank.
- [x] **78.** **Diatom film** (brown dust) as the *early* algae of a new tank,
   which then gives way to green as the tank matures. This gives the tank a
   visible age.
- [x] **79.** **Biofilm sheen on hardscape.** Every submerged surface in a mature
   tank has a slightly slick, light-catching film.
- [x] **80.** **Algae should respond to the light gradient.** Heavy directly
   under the fixture, near-absent in the shadow behind the stone.
- [x] **81.** **Algae should respond to grazing.** Snail and otocinclus presence
   should visibly hold it back — an ecology the player can *see* working.
- [x] **82.** **Detritus drifts in the low spots.** Every tank accumulates mulm
   in its dead flow zones; the map of where it lands is the map of the flow.
- [x] **83.** **Empty snail shells accumulating.** Tank B's front trough is full
   of them. They should persist, bleach over time, and pile.
- [x] **84.** **Shells should half-bury** — the ones that have been there longest
   sit deeper in the substrate.
- [x] **85.** **Leaf litter breaking down in stages** rather than vanishing:
   whole → skeletonised → fragments → mulm.
- [x] **86.** **A visible biofilm bloom on new wood** in the first weeks — the
   white fuzzy phase every real driftwood goes through, then recedes.
- [x] **87.** **Mineral crust at the old waterline** when the tank has been run
   at a lower fill.
- [x] **88.** **Stain the hardscape over time.** Tannins darken pale stone. A
   year-old rock is not the colour it went in.
- [x] **89.** **Give tank age a visible signature** so a screenshot alone tells
   you roughly how old the tank is — currently every tank looks the same age.
- [x] **90.** **Make maintenance visible in the result.** Wiping the glass,
   siphoning the substrate, trimming plants should each leave an obviously
   changed tank for a while.
- [x] **91.** **Let the patina come back.** The value of cleaning is that the
   grime returns; a permanent clean state removes the whole loop.
- [x] **92.** **Surface the patina state in the tank's own language** — the
   Guardian noticing the glass needs a wipe is worth more than a meter.

## F. Snails as a real population (93–110)

- [x] **93.** **Raise the snail population an order of magnitude** on the
   reference presets. Tank B's photos show 40+ ramshorns in a single frame; we
   spawn a handful. (This is exactly what the new hard ceilings in
   `TankConfig.POP_CAP_DEFAULTS` exist to make safe — see section M.)
- [x] **94.** **Three distinct species, visually distinct.** Pond/bladder snail
   (tall spiral, amber, translucent), ramshorn (flat coil, red or brown),
   Malaysian trumpet (long cone, banded, burrowing). The photos have all three
   and they read instantly apart.
- [x] **95.** **A real size distribution.** From 2 mm juveniles to 25 mm adults in
   the same frame, weighted toward small.
- [x] **96.** **Shell colour variation within a species**, including the
   translucent-with-visible-body look the big pond snails have.
- [x] **97.** **Snails on every surface** — glass, substrate, hardscape, leaves,
   and upside-down under the surface film. The last one is very distinctive and
   we don't do it at all.
- [x] **98.** **Correct foot contact.** The foot flattens and conforms to whatever
   it's on; a snail floating a millimetre off a leaf destroys the illusion.
- [x] **99.** **Radula rasping animation** when grazing — a small rhythmic motion
   at the mouth, visible on the glass shots.
- [x] **100.** **Grazing should leave the tracks** from item 22.
- [x] **101.** **Tentacle motion** — independent, slow, exploratory sweeps.
- [x] **102.** **Snails should right themselves** after falling, with the slow
   twisting recovery that's so recognisable.
- [x] **103.** **Snail egg clutches on glass and hardscape** — gelatinous
   translucent blobs with visible dots, which mature and hatch.
- [x] **104.** **Ramshorn clutches look different from pond snail clutches** —
   flat discs vs. elongated sausages.
- [x] **105.** **A population that responds to food.** A dropped wafer should pull
   a visible convergence of snails over minutes. This is real snail behaviour
   and it is very satisfying to watch.
- [x] **106.** **MTS emerge at night** and bury by day — we already model this;
   make the emergence visible as a population shift rather than a spawn.
- [x] **107.** **Snail speed should be genuinely slow** but never stationary. The
   test is whether a still frame and a frame ten seconds later differ.
- [x] **108.** **Snails should climb toward the surface for air** (pond snails are
   pulmonate) — an occasional trip up the glass to the film and back.
- [x] **109.** **Dead snails should leave a shell**, which then joins the drift in
   item 83.
- [x] **110.** **Snail population should visibly track food supply**, booming after
   overfeeding and crashing after — the classic real-tank lesson, told
   entirely through what's on the glass.

## G. Plants with histories (111–132)

- [x] **111.** **Blade-length variation within a stand.** Tank B's valli runs from
   3 cm juveniles to full-height blades in the same clump. Uniform height reads
   as instanced geometry, which it is.
- [x] **112.** **Blade width variation** too, and a slight twist along the length.
- [x] **113.** **Surface-bending emergent growth.** The most important plant item
   here. A valli blade that reaches the surface does not stop — it bends at the
   waterline and lies flat along the surface for 10–30 cm. Tank B's whole
   character comes from this. `plant.gd` already has `_at_surface_cap()`; it
   needs a bend-and-lie mode instead of a growth stop.
- [x] **114.** **Surface-lying blades should tangle with the floating mat.**
- [x] **115.** **Melted and browning tips** on older blades — the brown, thinning
   distal few centimetres that every real valli has.
- [x] **116.** **Torn and holed leaves.** Snail damage, fish damage, age. Cheap as
   an alpha-cutout variation, enormous as a realism signal.
- [x] **117.** **Algae carried on individual old leaves**, not on the species as a
   whole — one leaf furred and its neighbour clean.
- [x] **118.** **Per-leaf age.** A leaf should track how long it's existed and
   change colour, translucency and damage accordingly.
- [x] **119.** **Runners visible in the substrate.** Valli spreads by stolons; the
   pale horizontal runner between parent and daughter should be visible at the
   substrate surface and against the front glass.
- [x] **120.** **Daughter plants at visibly different ages** along a runner —
   the classic descending sequence.
- [x] **121.** **Backlit leaf translucency.** Tank B is backlit and the blades
   glow — the veins darker than the blade, the thin parts luminous. This is a
   subsurface term in `foliage_mm.gdshader` and it is most of why the reference
   photo is beautiful.
- [x] **122.** **Leaf colour should vary with light history**, not just species —
   the shaded lower blades yellower and thinner than the lit tops.
- [x] **123.** **Bend under flow, not just sway.** Long blades should take a
   persistent set from the flow direction, with the sway on top of it.
- [x] **124.** **Pearling.** Oxygen bubbles forming on leaf surfaces under strong
   light, growing, then releasing. Directly ties to the O₂ sim we already run.
- [x] **125.** **Moss should be genuinely fuzzy at the silhouette** — the
   reference wood is furred, not smooth-shelled.
- [x] **126.** **Moss should grow *around* what it's attached to** over time,
   thickening and eventually obscuring the wood's texture.
- [x] **127.** **Crypts should melt and recover** — the real-world behaviour after
   any change, and a beautiful piece of storytelling.
- [x] **128.** **Dead leaves should detach and drift** to the substrate rather
   than disappearing.
- [x] **129.** **Plant density should be able to reach genuinely obstructive
   levels** — Tank B's midground is not visible through the valli, and that
   opacity is the point.
- [x] **130.** **Let plants touch and interpenetrate.** Our spacing rules keep an
   unnaturally polite gap between clumps.
- [x] **131.** **Root flare at the substrate line** — the visible thickening and
   pale colour where a stem enters the bed.
- [x] **132.** **Trimming should leave cut ends** that visibly heal over days.

## H. Hardscape that has been underwater (133–146)

- [x] **133.** **Layered, bedded stone.** Tank A's rock is a stratified ochre
   stone with visible bedding planes and a chalky, porous face. Our hardscape
   reads as uniform mass.
- [x] **134.** **Stone colour variation across a single rock** — iron staining,
   darker in the recesses, pale on the exposed faces.
- [x] **135.** **Sharp broken edges vs. weathered faces** on the same rock.
- [x] **136.** **Deep shadow in the stone's crevices**, which is where the shrimp
   and the small fish actually hide.
- [x] **137.** **The rock should sit *in* the substrate**, not on it — gravel
   banked up around the base, and the base itself buried.
- [x] **138.** **Driftwood grain and fibre.** Tank B's wood is visibly fibrous
   with the softer material eroded away between harder grain lines.
- [x] **139.** **Wood should be darker and wetter-looking than stone**, and darken
   further with time submerged.
- [x] **140.** **Wood should have holes and hollows** that things live in.
- [x] **141.** **Wood-to-substrate junction** should be buried and mossy, not a
   clean contact.
- [x] **142.** **Epiphytes attached where they'd actually be** — java fern and
   moss on the wood's upper and outward faces, not on its shaded underside.
- [x] **143.** **Hardscape should cast the tank's strongest shadows**, and those
   shadows should be where the algae isn't (item 80).
- [x] **144.** **Asymmetric, un-composed placement.** The reference tanks are not
   golden-ratio scapes — the rock is where it fitted. Our hardscape styles are
   all *designed*, and it shows.
- [x] **145.** **Let hardscape be partly out of frame.** Tank A's stone is cut off
   by the left edge. Composition that acknowledges the tank continues past the
   frame reads as photography.
- [x] **146.** **Small stones and gravel accents** scattered around the base of
   the main piece, the way real substrate settles.

## I. Equipment in frame (147–162)

- [x] **147.** **Airline tubing as visible geometry**, arcing over the rim with a
   real bend radius and a slight sag. Present in three of the six photos.
- [x] **148.** **Tubing should refract at the waterline** (item 30) and pick up a
   bright specular highlight along its top.
- [x] **149.** **The airstone as a physical object** on or in the substrate, with
   the bubble column originating from its surface rather than a point.
- [x] **150.** **A suction cup or two** holding the line to the glass.
- [x] **151.** **Tubing should discolour over time** — clear silicone goes cloudy
   and then algae-green inside.
- [x] **152.** **The clip-on gooseneck LED.** Tank C's whole look comes from this
   fixture: a clamp on the rim, a flexible arm, a small hooded head. Our
   `light_fixture` options are a bar and a pendant; this is a third.
- [x] **153.** **A hard-edged light pool** directly under the clip lamp with
   sharp falloff — not the even wash a bar gives.
- [x] **154.** **The fixture's own cable** running down and off-frame.
- [x] **155.** **A heater rod** on the back glass with its cable and its
   indicator LED.
- [x] **156.** **Filter intake and outflow** as visible objects, with the outflow
   producing the surface disturbance it should.
- [x] **157.** **Equipment should be grimy.** Suction cups yellow, intakes furred
   with algae, the heater's lower half biofilmed.
- [x] **158.** **Let equipment be slightly crooked.** Nothing in the reference
   photos is perfectly plumb.
- [x] **159.** **The lid or lack of one.** Tanks A and C are open-top with the
   rim edge clearly visible; this changes the whole silhouette.
- [x] **160.** **Props beside the tank** — the tweezers on the mat, the food
   container, the white mat itself. These are what say "somebody keeps this."
- [x] **161.** **A visible power strip / cable run** behind or below.
- [x] **162.** **Make equipment an aesthetic choice, not a fixed set** — the
   player should be able to hide it or leave it proudly in shot.

## J. Light: the tank as the light source (163–176)

- [x] **163.** **The tank must be the brightest thing in frame.** Already the
   headline finding in `VISUAL_POLISH_200_IDEAS.md`; the counter-nano photos
   prove it — the room is dim and the water glows.
- [x] **164.** **Backlighting as a supported look.** Tanks B and C are lit from
   behind and the plants are translucent against it. This is a fundamentally
   different and more beautiful lighting mode than our top-down default.
- [x] **165.** **Warm orange bounce from the room** entering the tank from behind
   and below, as in the Tank B photos.
- [x] **166.** **Light through the floating mat.** Duckweed transmits a green
   glow and casts a dappled, moving shadow map on everything below.
- [x] **167.** **Hard shadow under dense planting** — Tank B's substrate is nearly
   black under the valli.
- [x] **168.** **The fixture should be visible as a source**, with a bloom around
   it and a visible reflection on the water surface.
- [x] **169.** **Specular glints on wet surfaces near the waterline.**
- [x] **170.** **Light scattering in the bubble column** (item 44).
- [x] **171.** **A colder colour temperature for the LED** than the room, so the
   tank's light and the room's light are visibly different colours. This
   separation does a lot of the compositional work in the Tank C photos.
- [x] **172.** **Sharp light-to-shadow transitions** at the edge of the clip-lamp
   pool.
- [x] **173.** **The light should reveal the water's turbidity** — a visible cone
   from fixture to substrate in a hazy tank.
- [x] **174.** **No caustics under the floating mat** (item 54).
- [x] **175.** **Let the tank light spill onto the counter** and the wall behind,
   as the only real illumination in the counter-nano shots.
- [x] **176.** **Reflections of the fixture on the front glass**, offset by the
   glass thickness.

## K. The room around it (177–186)

- [x] **177.** **A counter room preset.** Shipped as `counter_mirror` — speckled
   stone counter, pale wall, clip lamp, no window. Items 178–186 are the polish
   pass on it.
- [x] **178.** **Speckled stone counter material** rather than flat colour — the
   granite in the photos has visible grain at this distance.
- [x] **179.** **A mirror behind the tank.** The reference shots are dominated by
   it: you see the tank's back, the room, and the photographer. This is the
   most characterful room element in the whole set and we have no support for
   it.
- [x] **180.** **The mirror should reflect the tank as a light source**, doubling
   the glow.
- [x] **181.** **The white mat under the tank** with its slightly-off-square
   placement.
- [x] **182.** **Room surfaces should be lower-contrast and cooler** than the
   tank so the eye goes where it should.
- [x] **183.** **A wall texture with real subtlety** — the plaster in the photos
   has orange-peel texture catching raking light.
- [x] **184.** **The room should be dim.** These are not sunlit rooms; the tank
   dominates because everything else is underexposed.
- [x] **185.** **Let the room be cropped and partial.** We see a corner of
   counter, a slice of wall, part of a towel ring. Nothing is fully in frame.
- [x] **186.** **Room dither strength should stay well below the tank's** — this
   is already item 15 in the sibling document and it matters doubly here.

## L. The photograph itself (187–194)

- [x] **187.** **A handheld camera mode.** Slight, slow, low-amplitude drift in
   position and rotation. Not a shake — a hand.
- [x] **188.** **Let the horizon be slightly off-level** in photo mode, by a
   degree or two, deliberately.
- [x] **189.** **Shallow depth of field with the focus plane inside the tank** —
   the front glass slightly soft, the subject sharp, the back glass soft.
- [x] **190.** **Focus falloff should be strong at close range**, as in the snail
   macro shots where only one snail is sharp.
- [x] **191.** **Highlight rolloff rather than clipping** — the bright water in
   the photos rolls off warm, it doesn't blow to white.
- [x] **192.** **Sensor noise in the shadows**, scaled with scene darkness the way
   a phone camera does.
- [x] **193.** **A macro camera preset** for the close snail-and-gravel shots,
   with a much lower minimum orbit distance than the current clamp allows.
- [x] **194.** **A "photo taken by a person" preset bundle** that combines items
   187–192 into one toggle, so players can shoot the tank the way the reference
   photos were shot.

## M. Making it reachable — presets, caps and the density budget (195–200)

- [x] **195.** **Ship the three reference tanks as scenarios.** Done —
   `snail_bar`, `valli_jungle`, `counter_nano` in `scenario_picker.gd`, with
   matching `TankConfig.TANK_PRESETS` entries and the `counter_mirror` room.
- [x] **196.** **A density budget dial** that scales the soft carrying capacities
   the ecology derives from plant biomass, aeration and volume — so "how full
   should a healthy tank be" is a player choice rather than a tuning constant.
   Done: `TankConfig.density_budget`, Settings → Stocking → Density & limits.
- [x] **197.** **Hard per-kind population ceilings** so raising the snail and
   plant populations toward reference levels (items 93 and 129) can never
   become a frame-rate cliff. Done: `TankConfig.POP_CAP_DEFAULTS`, enforced
   through `population_cap()` in `sim_driver.fish_carrying_capacity()` and
   `world.gd`'s snail / shrimp / plant / floater / microfauna capacities.
- [x] **198.** **Ceilings scale with tank volume** so a nano cube cannot hold a
   75-gallon's population. Done: `pop_scale_with_tank` + `tank_volume_ratio()`,
   with a per-kind floor so small tanks stay playable.
- [x] **199.** **Surface the ceiling in-game when it binds.** When plant
   propagation or snail breeding is being held back by the cap rather than by
   the ecology, the player should be told — otherwise a tank that has stopped
   growing looks like a bug.
- [x] **200.** **Auto-tune the ceilings from measured frame time.** `PerfGovernor`
   already tracks p95 frame time and exposes `budget_pressure`; a slow decay of
   the effective ceilings under sustained pressure would let a strong machine
   run the reference-density tanks and a weak one degrade gracefully instead of
   stuttering.

---

## Priority spine

If only ten of these get done, do these ten, in this order. They are chosen
because each one is visible in every single reference photograph.

1. **Item 1** — stratified substrate at the front glass. Nothing else in the
   document changes the read as much.
2. **Item 113** — valli bending over at the surface and lying along it. This is
   Tank B's entire character.
3. **Item 21 + 22** — green dust on the glass, and snail grazing tracks through
   it. One system, two of the most distinctive details in the set.
4. **Item 39 + 40** — turbidity and depth-dependent contrast falloff. Two
   uniforms; the water stops being free space.
5. **Item 93** — an order-of-magnitude more snails, now safe to attempt because
   of items 197–198.
6. **Item 121** — backlit leaf translucency. Most of why the reference photos
   are beautiful.
7. **Item 56 + 57** — a real floating mat with a species size hierarchy.
8. **Item 152 + 153** — the clip-on gooseneck LED and its hard light pool.
9. **Item 147** — airline tubing arcing over the rim. One piece of geometry,
   and the tank instantly reads as plumbed and lived-with.
10. **Item 179** — the mirror behind the counter nano. The single most
    characterful thing in the reference set.

## Things deliberately not in this document

- **Anything that makes the tank prettier than the reference.** The photos have
  algae, haze and pest snails. Reproducing that faithfully is the goal; a
  cleaner result is a different goal.
- **New species, new mechanics, new UI.** Every item above is "something already
  on screen, but truer," or a small addition that a photo demonstrably contains.
- **Frame and post-process work**, which lives in
  [VISUAL_POLISH_200_IDEAS.md](VISUAL_POLISH_200_IDEAS.md).
