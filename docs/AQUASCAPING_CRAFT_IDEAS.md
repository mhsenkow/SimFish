# Aquascaping as Craft — 100 Deep Ideas

*Drafted 2026-06-26. Director's brief for the build/creativity pillar.*

The dream: aquascaping that goes **almost Minecraft-deep** — free voxel building
in the water column, a library of buildable objects (castles, ruins, shipwrecks,
not just wood + stone), and a sharing loop so *who-knows-what* players invent ends
up in other people's tanks. **And** the base aquascape — terrain, hardscape,
plants — refined so the foundation is worthy of the sandbox on top of it.

Format follows [GOALS.md](GOALS.md) / [the plants doc](PLANT_IMPROVEMENT_IDEAS.md):
**Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S (polish) /
M (noticeable) / L (transforms the craft). File/line pointers are navigational
hints — match by symbol if lines have drifted.

---

## The headline finding (read this first)

**The voxel-object engine already exists — it just isn't player-facing.**

- **The renderer is built for this.** [`voxel_batch.gd`](../shaders-godot/godot-project/scripts/voxel_batch.gd)
  is a MultiMesh of unit boxes (`UNIT_BOX` ~19) drawn in **one draw call**, with
  per-instance color + a lightweight `Handle` (`add()` ~76) for later recolor/
  remove and dynamic capacity growth (`_ensure_capacity` ~111). `voxel_mat.gd`
  has a full material palette (`make`, `make_fauna`, `make_foliage`,
  `make_translucent`, `make_substrate_caustic`, `make_voxel_mm`), color-snapped to
  the 48-color palette (`palette_quantize.gdshader`, `palette_size` ~44), with a
  per-voxel `instance uniform vec4 tint` already in `voxel.gdshader`.
- **The engine already *authors arbitrary objects from voxels*.** `world.gd`
  procedurally builds a voxel **record player** (`_build_room_record_player`
  ~6618), **lava lamp** (~6668), **clock** (~6555), **mug** (~6506), **lamp**,
  **books**, **plant pot** — proof that complex, recognizable objects are just
  voxel recipes. They live *outside* the tank (room presets) and aren't
  player-editable. **That's the gap, not a missing capability.**
- **The build mode is already wired** in
  [`aquascape_controller.gd`](../shaders-godot/godot-project/scripts/aquascape_controller.gd):
  `toggle()` (~49) pauses the sim + shows a palette; `AQUASCAPE_TOOLS` (~9) =
  8 tools; `place()` (~183) dispatches; a 96-deep undo (`UNDO_MAX` ~7,
  `undo()` ~209); save/restore round-trips voxels & logs
  (`to_save_arr` ~238 / `restore_from_save` ~281); placement snaps to terrain via
  `column_top_y()` (~359) and registers `_mark_hardscape_occupancy()`
  (`world.gd` ~1859) so creatures avoid solids.
- **Terrain is a real voxel grid.** [`terrain_voxel_grid.gd`](../shaders-godot/godot-project/scripts/terrain_voxel_grid.gd):
  `CELL_SIZE 0.4` (~20), 6-material enum (~11), `place_brush`/`dig_brush` (~283/303),
  `settle_gravity()` (~325), `EXTRA_SCULPT_ROWS 14` (~21) of stacking headroom.

**The five structural levers:**

1. **Lever 1 — Building is welded to the substrate.** Everything places *on the
   terrain top* (`column_top_y`, `project_to_substrate` ~338). To build a castle or
   an arch you must place voxels **anywhere in the water volume**, at a chosen Y,
   on a real 3D build grid. This single change is the Minecraft leap (§B).
2. **Lever 2 — Hardscape is coarse and non-editable.** Stones are a *fixed*
   0.9³ box (`_place_stone` ~462); logs are random 5–7-segment splines
   (`_place_log` ~486); no rotate, no scale, no per-voxel control after placement.
   Refine the base into real, controllable pieces (§A).
3. **Lever 3 — The voxel is the atom; there's no *molecule*.** No way to group
   voxels into a reusable object, stamp it, or share it. Add objects, blueprints,
   and a share-code loop (reuse the genome share infra) so creations compound (§E, §H).
4. **Lever 4 — "Craft" has no scaffolding.** Real aquascaping is composition
   (thirds, golden ratio, the Iwagumi triangle, depth layering, focal points).
   Give the builder gentle craft guides + feedback so freedom produces *good*
   scapes, not mush (§G).
5. **Lever 5 — Builds must stay cheap and persistent.** Thousands of player
   voxels need MultiMesh batching, LOD, an occupancy story, and a versioned save
   that round-trips perfectly (§I).

---

## A. Refine the base aquascape (earn the right to a sandbox)

Fix the rough edges of what's already there before piling features on top.

- [x] **1. Variable stone size + shape.** `_place_stone()` (~456) hard-codes a 0.9³ box. Add size presets (pebble → boulder) and 3–4 stone *silhouettes* (slab, shard, rounded, stacked) built as small voxel clusters, not one cube. The Iwagumi authored stones (`_build_iwagumi_clusters` ~2540) already prove multi-voxel rocks look good. *M·L* — brush-radius size presets + multi-voxel cluster at r≥3.
- [x] **2. Rotate & scale placed hardscape.** Drag only moves XZ (`drag_hardscape` ~161); Y snaps to terrain. Add yaw rotation (and pitch for driftwood) + a scale handle on the selected piece. The data already stores per-segment offsets — extend the transform. *M·L* — Q/E yaw rotate selected/dragged hardscape; scale handle still open.
- [x] **3. Free-rotating, controllable driftwood.** `_place_log()` (~486) spits a random spline with no control. Let the player pick a driftwood *form* (spider wood, manzanita, stump, root-ball) and orient it. Keep procedural variation as a "randomize" button, not the only option. *M·L* — palette picks drift/spider/stump/root; Q/E rotate after place.
- [x] **4. Snap-to-grid toggle.** Placement is freeform XZ today. Offer an optional 0.4-cell snap (matching `CELL_SIZE`) so precise builders can align pieces, with free-place still available. *S·M*
- [x] **5. Redo, not just undo.** `undo()` (~209) is one-directional with a 96-deep stack. Add a redo stack so experimentation is fully reversible — essential for a creative tool. *M·M* — Shift+Z redo; build strokes/objects fully reversible; terrain/hardscape redo still one-way.
- [x] **6. Multi-select + group move/delete.** Today you drag one piece (`_pick_hardscape_piece` ~644). Add box-select / shift-click to grab several and move/rotate/delete them as a set. *M·M* — Shift+click select; group drag + Q/E rotate; box-select still open.
- [x] **7. Better terrain brush: smooth, raise/lower, slope.** Beyond paint/dig (`place_brush`/`dig_brush`), add a *smooth* brush and a *raise/lower* (additive height) brush so hills and valleys sculpt naturally instead of stair-stepping. `settle_gravity()` already handles collapse. *M·L*
- [x] **8. Substrate "scape" depth slopes by default.** Real scapes slope up to the back. Add a one-tap "back-slope" terrain preset (front low, back high) as a starting canvas — extends `_apply_scenario_terrain_relief()` (~2090). *S·M*
- [x] **9. More terrain materials + blending.** The enum has 6 (`CellMaterial` ~11). Add lava rock, white sand, dark soil, clay, crushed coral; and blend boundaries (a sand path through soil) rather than hard cell edges. *M·M* — 5 new materials + nutrient/color boundary blend in `terrain_voxel_grid.gd`.
- [x] **10. Trim/prune as a first-class sculpting tool.** `_trim_at()` (~433) removes 25% of a plant. Add directional trimming (top vs sides), a "shape this bush" brush, and carpet mowing so planted scapes can be *gardened*, not just thinned. *M·M* — trim modes all/top/sides/mow in palette + `trim_for_aquascape(mode)`.

---

## B. The voxel builder core — the Minecraft leap

The defining change: place and remove individual voxels **anywhere in the water
volume**, on a real 3D grid, in any palette color. Everything else builds on this.

- [x] **11. Free voxel placement in the water column.** Add a `block` tool that places a single unit voxel at the cursor's 3D position — not snapped to terrain top. Raycast to the nearest existing voxel face (like Minecraft block-on-block) OR to a depth plane the player sets. The core verb. *L·L*
- [x] **12. Face-adjacent placement.** When the cursor is over an existing voxel, place the new one on the *face* the ray hits (above/beside/in-front). This is what makes stacking towers and walls feel natural. Reuse `voxel_batch` Handles for the target voxel's neighbors. *L·L*
- [x] **13. A voxel-remove tool.** Mirror of place: delete the voxel under the cursor (`Handle`-based removal already exists in `voxel_batch.add()`'s return). Bind to the existing dig/erase ergonomics. *M·L*
- [x] **14. A unified build grid + coordinate snap.** Introduce a logical build grid (0.4 unit, matching `CELL_SIZE`) spanning the tank volume so placed voxels align across sessions and pieces. Store builds in grid coords, render via a dedicated player-build `VoxelBatch`. *L·L*
- [x] **15. Per-voxel color from the palette.** A color picker constrained to the active 48-color palette (`palette_quantize.gdshader`) — `voxel_mat` already snaps colors to 0.04 (~24). Builders paint in the game's real palette so creations always look in-world. *M·L*
- [x] **16. Build-plane control (the "altitude" slider).** A draggable horizontal plane (or scroll-to-raise) sets the Y where free voxels land when not face-adjacent — so a player can build a floating arch or a mid-water platform deliberately. *M·L*
- [x] **17. Variable voxel size in builds.** The batch supports per-instance scale (`add()` bakes scale into the basis). Offer half-blocks and 2× blocks so detail (a window) and bulk (a wall) are both efficient. *M·M* — 1/2 and 2× toggles on `build_scale`.
- [x] **18. Eyedropper / clone tool.** Pick the color+material of an existing voxel to keep building in it. Tiny ergonomic win that creative tools live or die by. *S·M*
- [x] **19. Build with the simulation paused AND a live preview.** `toggle()` already pauses the sim. Ensure the build preview (`_ensure_preview` ~596) shows the exact voxel (color, size, position) before commit, with a ghost outline on the target face. *S·M*
- [x] **20. Bounds + buildable-volume validation.** Voxels must stay inside the vessel (`project_to_substrate` validates tank bounds; `is_inside_tank_volume` exists). Extend bounds-checking to full-volume placement across all tank shapes (box/hex/cylinder/sphere). *M·M*

---

## C. Building tools & ergonomics — beyond one-voxel-at-a-time

Single placement is the atom; these are the power tools that make big builds
feasible and fun.

- [x] **21. Line tool.** Click start, click end → fill a straight run of voxels. The bread-and-butter of walls and pillars. *M·M*
- [x] **22. Rectangle / box tool.** Drag a footprint, set a height → a hollow or solid box. Castle walls in two clicks. *M·M* — two-click box + shell toggle.
- [x] **23. Flood-fill (bounded).** Fill an enclosed region or a flat plane with the current color, capped at a sane voxel budget with a warning (§I #87). *M·M* — fill tool; 400-cell cap via `AquascapeCraft.flood_fill`.
- [x] **24. Mirror / symmetry mode.** A toggleable mirror plane (X and/or Z) so a castle's two halves build at once. Aquascapes and architecture both lean symmetric — huge time-saver. *M·L*
- [x] **25. Copy / paste a selection.** Box-select a region, copy, paste elsewhere. Build one tower, paste three more. Foundation for blueprints (§H). *M·L* — copy full build + paste tool / ⌘V.
- [x] **26. Move/rotate a selection as a rigid group.** Once selected (§A #6), translate and rotate the whole cluster in 90° steps. Needed for arranging built objects. *M·M* — multi-select drag + Q/E rotate.
- [x] **27. Brush shapes for voxel building.** Extend `brush_radius` (1–4, ~20) with sphere/cube/disc brush *shapes* so the block tool can lay volume, not just single cells. *M·M*
- [x] **28. Undo/redo that batches a stroke.** A drag that lays 40 voxels should undo as *one* action, not 40. Group continuous strokes into a single undo record (extends `_push_undo` ~529). *S·M*
- [x] **29. Hide/show layers while building.** Temporarily hide plants/fauna/water tint so the builder can see what they're doing inside a dense scape. *M·M*
- [x] **30. A "hollow" / "shell" operation.** Turn a solid selection into its outer shell (carve the interior) — instant rooms, caves, and lighter voxel counts. *M·M* — shell toggle on box tool.

---

## D. Materials, colors & surface finish

The look of built objects. The material factory is rich already — expose it to
the builder and extend it.

- [x] **31. Expose the full material set to the builder.** `voxel_mat` has matte, fauna-glossy, foliage, translucent, caustic. Let builders choose a *finish* per voxel: matte, glass, glow, metal, wet-stone. Same palette, different surface. *M·L* — matte/glass/glow/metal finish picker; per-voxel finish in save v2.
- [x] **32. Glass / translucent build blocks.** `make_translucent()` already exists (used for fish veil tails). Translucent colored blocks = stained-glass windows, ice, jelly sculptures. *M·M*
- [x] **33. Emissive / glow blocks.** Wire `instance uniform vec4 tint` + an emission path so a built lighthouse, lantern, or bioluminescent ruin actually glows (and casts an OmniLight like `_build_heater` ~6113 does). *M·L* — glow finish + `sync_build_glow_lights` OmniLight anchors.
- [x] **34. Metallic / treasure blocks.** Gold, copper, rusted iron finishes for shipwrecks and sunken chests. A specular tweak on the voxel shader, palette-constrained. *M·M* — metal finish in build grid.
- [x] **35. Per-object palette themes.** A "recolor this build" action that maps a build's voxels onto a chosen palette bank (`palette_bank_lock` ~tank_config) — instant variants (stone castle → coral castle → obsidian castle). *M·M*
- [x] **36. Patina & aging on built objects.** Built stone/wood should accept the existing biofilm/algae/mineral colonization (driftwood biofilm, GOALS D#40) so player builds *age into the tank* instead of looking pasted-on. *M·L*
- [x] **37. Texture variation within one color.** The room props use 4-shade hash-noise wood/brick grain. Offer the same auto-variation so a built wall isn't a flat color slab. *S·M*
- [x] **38. Surface caustics on builds.** `make_substrate_caustic()` gives hardscape moving light. Apply it to player builds so they catch the same underwater shimmer as the rock and wood. *S·M*
- [x] **39. Gradient / dither-aware fill.** Let a fill ramp between two palette colors using the existing Bayer dither so a built dome can fade sky→deep. *M·M*
- [x] **40. Custom palette swatches per tank.** A small per-tank set of "favorite" build colors saved alongside the scape, so a builder's chosen scheme is one tap away. *S·S* — 16-color build swatch row in palette.

---

## E. The object library — buildable & placeable things

The headline ask: castles and more. Ship a library of pre-made voxel objects
(the engine already authors complex props — generalize that), placeable like
hardscape, then editable like builds.

- [x] **41. Generalize prop-building into a placeable object system.** The room props (`_build_room_record_player` ~6618, `_build_room_lava_lamp` ~6668, etc.) are proof complex voxel objects work. Refactor that into a generic "voxel object" = a list of `{offset, size, color, finish}` that can be instantiated, placed, dragged, saved, and dropped *in the tank*. The keystone item. *L·L*
- [x] **42. Classic aquarium ornaments.** The genre staples: **castle**, **sunken ship/shipwreck**, **treasure chest** (openable bubble emitter), **amphora/clay pots** (fish swim through), **Greek columns/ruins**, **pirate skull**, **diver**, **bridge**, **pagoda/torii gate**. Author them as voxel objects. *L·L* — castle, shipwreck, treasure, arch, torii, ruin column + pebble/boulder natural set.
- [x] **43. Natural hardscape objects.** Beyond loose wood/stone: **stone arch**, **cave mouth**, **boulder pile**, **rock wall/cliff**, **driftwood stump**, **root tangle**, **slate ledge** — pre-composed so a beginner gets a good scape without voxel-by-voxel work. *L·L* — arch, pebble, boulder shipped; cave/cliff/stump still open.
- [x] **44. Themed decoration sets.** Curated kits so a tank reads as a *place*: **Zen** (lanterns, stepping stones, torii), **Fantasy** (castle, crystals, dragon skull), **Sci-fi** (dome, neon arch, wreck), **Ruins** (broken columns, statues, urns), **Reef** (anchor, porthole, treasure). *L·L* — zen/fantasy/ruins/reef kit stamp buttons + new objects.
- [x] **45. An object browser/palette.** A scrollable, categorized picker (Natural / Ornaments / Themed / My Builds) inside build mode — extends `_build_palette()` (~548) into a real asset browser with thumbnails. *M·L* — category tabs + horizontal scroll browser; thumbnail renders still open.
- [x] **46. Parametric object variants.** Author key objects parametrically (castle: # towers, height, color) so one recipe yields endless variants — the way driftwood already varies. *L·M* — castle towers/height toggles + `voxels_for(id, params)`.
- [x] **47. Objects snap sensibly on placement.** New objects land on terrain via `column_top_y()` and register `_mark_hardscape_occupancy()` (~1859) so fish avoid solids and biofilm/contact-AO apply. Wire every library object through that path. *M·M*
- [x] **48. Objects are editable after placement.** A placed castle is just a voxel group — let the player enter it and add/remove/recolor voxels (§B/§C). Pre-mades become *starting points*, not fixed decals. *M·L*
- [x] **49. Scale & "ruin-ify" objects.** Place a pristine castle or a half-collapsed one; scale from nano-tank ornament to centerpiece. Procedural damage (knock out random voxels) gives instant ancient-ruins. *M·M* — ruin tool + `AquascapeCraft.ruinify_region`; object scale via build_scale.
- [x] **50. Seasonal / novelty objects.** A small rotating set (pumpkin, tiny tree, gift box) for delight and reasons to return — cheap to author once the object system (#41) exists. *S·M* — month-gated pumpkin/gift/blossom in object library.

---

## F. Functional & interactive objects — builds the sim cares about

The magic multiplier: built objects that the ecosystem *reacts to*, so building
changes how the tank lives — not just how it looks.

- [x] **51. Caves & hides that fish actually use.** A built cave or amphora interior should register as shelter so timid fish hide there (ties to GOALS A#2 hide-in-plants — extend "hideable" to built hollows via the occupancy + a shelter tag). *M·L*
- [x] **52. Spawning caves & territories.** Cave-spawners (cichlids, plecos) claim a built cave as a breeding/territory site, defended (GOALS B#17 clutch guarding). Building a cave literally enables behaviors. *M·L* — territorial species anchor home at `query_build_territory_near`.
- [x] **53. Fry refuge structures.** Tight-gap builds (a voxel lattice, a pile of pebbles) shelter fry like dense plants do (GOALS H4 #33). Reward thoughtful aquascaping with measurable recruitment. *M·M*
- [x] **54. Bubble & ornament emitters.** A built "bubbler" ornament (treasure chest, diver, clam) emits a bubble stream reusing the aerator emitter code (`_build_*_aerator` ~5744+). Classic kitsch, real effect on local O₂/flow. *M·M* — glow-finish build voxels spawn rising bubbles.
- [x] **55. Flow-shaping builds.** Solid builds should deflect the filter flow field so a wall creates a calm corner (low-flow species seek it) and a gap creates a current (rheophilic fish play in it). Couples building to the hydrodynamic pillar. *L·L* — `build_flow_calm_factor` + pleco shelter on build geometry; full flow-field deflection still open.
- [x] **56. Light-shaping builds.** Tall builds cast shade (like floaters/tall plants in light penetration); a built overhang creates a shaded grotto where shade-loving plants/fish gather. *M·M* — `build_shade_factor` eases stress for hover/cruise fish.
- [x] **57. Biofilm & grazing surfaces.** Built surfaces accrue biofilm/algae over time (GOALS F#30 aufwuchs) that otos/shrimp/snails graze — so a big build adds grazeable area and feeds the web. *M·M* — graze cell count + snail hunger relief on build hardscape.
- [x] **58. Epiphyte attachment on builds.** Java fern / anubias / moss attach to built hardscape, not just procedural wood (`fractal_moss` spawns from hardscape voxels). A built arch can be planted. *M·M* — `compute_epiphyte_anchors` + `_find_nearest_hardscape_anchor`.
- [x] **59. Climbable / perchable geometry.** Snails climb built walls, shrimp graze built ledges, sit-and-wait predators perch on built outcrops — extend existing climb/perch logic to player geometry. *M·M* — snail/shrimp/fish hooks on build shelter points.
- [x] **60. Hazard & micro-current honesty.** A fully-enclosed built box traps low-O₂ water (extends GOALS H3 #23 stagnant corners) — so sealing a space has a consequence, teaching flow through play. *M·M* — `query_stagnant_build_pocket` raises fish stress.

---

## G. Composition & craft scaffolding — make freedom produce *good* scapes

This is the "as Craft" half. Aquascaping is a real discipline; give players the
guides masters use, optionally and gently.

- [x] **61. Composition overlay: rule of thirds + golden ratio.** A toggleable guide grid (thirds lines, golden spiral, focal-point markers) over the tank during build, so the player can place the main stone on a power point. *M·M* — thirds grid overlay; golden spiral still open.
- [x] **62. The Iwagumi triangle guide.** When building stone layouts, show the classic main/secondary/tertiary stone relationship (the authored `_build_iwagumi_clusters` ~2540 already encodes it) as an optional placement guide. *M·M*
- [x] **63. Depth zones (FG/MG/BG) made explicit.** `apply_aquascape_template()` (~3847) already thinks in fg/mg/bg/epi zones. Surface those as visible bands in build mode so players plant carpets front, stems back — teaching layered depth. *M·M*
- [x] **64. Focal-point feedback.** A light analysis that reads the scape and notes "no clear focal point" / "nice asymmetry" / "the center is crowded" — gentle, optional craft coaching, never a score gate. *L·M* — `AquascapeCraft.analyze_scape` tips in palette.
- [x] **65. A scape "reading" with style match.** Detect whether a build leans Iwagumi/Dutch/Nature/Jungle/Biotope and reflect it back ("this is reading Dutch — dense, colorful, terraced"). Names the player's instinct; teaches the vocabulary. *M·M*
- [x] **66. Negative-space awareness.** Highlight open swimming space — over-building is the #1 beginner mistake. A subtle "open water" readout encourages restraint. *M·M* — open-water % in craft readout.
- [x] **67. Richer one-tap templates as *starting canvases*.** `apply_aquascape_template` places plants only. Extend templates to also lay terrain slope + hardscape so "Nature Aquarium" gives a complete, editable starting scape, not bare plants. *M·L* — `_apply_template_canvas` back-slope + style-specific substrate.
- [x] **68. Style-coherent palettes & material suggestions.** When a style is detected/chosen, suggest fitting build materials (Zen → muted stone; Fantasy → glow + crystal). Soft nudges, not rules. *M·M* — `style_palette_hint` in craft readout.
- [x] **69. Scale & proportion guides.** Show a fish-silhouette or hand reference so builders gauge whether a cave fits the stock or a castle dwarfs the tank. Proportion is half of "looks right." *S·M* — fish-silhouette band in depth-zone overlay.
- [x] **70. Before/after & A-B scape compare.** Snapshot the scape, try a change, flip between them. Lets players iterate like a designer instead of fearing the undo limit. *M·M*

---

## H. Blueprints, sharing & UGC — who knows what they'll build

The compounding loop: turn a build into a reusable, shareable object so the
community's creativity flows between tanks. The genome share-code infra already
exists to copy.

> **✅ DECIDED — sharing is CORE, build it early.** Blueprints + share-codes
> (#71–73) ship *alongside* the core build tools, not after. "Who knows what users
> build" only pays off if creations spread, so the save format (§I #77) must carry
> the v2 object/blueprint schema from day one — design it once, correctly, before
> the local-only format calcifies. Reuse `library_panel.gd`'s genome share/import
> UX so it's familiar and cheap.

- [x] **71. Save a selection as a reusable blueprint.** Box-select (§C #25) → "Save as object." Stores the voxel list as a named build in a local library, instantly re-placeable. The molecule above the atom. *M·L* — saves full build grid + local library entry.
- [x] **72. Share builds as a compact code.** `library_panel.gd` already shares/imports *fish genomes* as compact codes. Mirror it for builds: serialize the voxel list (positions delta-encoded + palette indices) into a paste-able string. *M·L* — `WLBP2:` gzip+base64 + palette-index compression.
- [x] **73. Import a build from a code.** Paste a code → preview → place. The other half of #72; reuses the genome-import UX pattern so it's familiar. *M·M* — clipboard import button.
- [x] **74. A "My Builds" library with thumbnails.** Render a small preview per saved build (reuse the tank thumbnail capture path). Browse, rename, delete, duplicate — the creative inventory. *M·M* — lib panel loads merged library; thumbnail renders still open.
- [x] **75. Bundled starter blueprints.** Ship the §E objects *as* blueprints in the same format players use, so the library is seeded and players can crack open a castle to learn how it's built. *M·M*
- [x] **76. Stamp/repeat placement.** With a blueprint selected, place multiple copies (a row of columns, a reef of the same coral-rock). Drop-and-drop without re-selecting. *S·M* — stamp toggle on object tool.
- [x] **77. Versioned, forward-compatible build format.** Bump the save format (today `to_save_arr` ~238 stores `{kind,tool,pos,size,color}` + log segments). Define a richer v2 object/blueprint schema with finishes, groups, and metadata — and keep old saves loading. *M·L*
- [x] **78. A curated showcase gallery (later).** If/when cloud sharing lands (ties to the broader Sharing pillar), a browsable gallery of community scapes/objects to import — the UGC flywheel. *L·L* — local showcase dialog + `showcase_blueprints()`; cloud gallery still future.
- [x] **79. Attribution & remix lineage.** A shared build remembers its author/name so remixing credits the original (mirrors the genome lineage ethos). Encourages sharing without erasure. *S·M* — author + lineage fields in WLBP2 payload.
- [x] **80. Export a build/scape as an image or turntable.** One-tap beauty shot of a finished scape (reuse the photo/F12 path) so players can show off off-platform — the cheapest growth loop. *M·M* — photo button in build palette.

---

## I. Performance, persistence & technical foundation

Player builds can be huge. Keep them cheap, correct, and permanent.

- [x] **81. All player voxels go through MultiMesh batches.** Route free-placed voxels into a dedicated player-build `VoxelBatch` (~one draw call per material) instead of per-voxel `MeshInstance3D` (which `_place_stone` currently spawns). Non-negotiable for big builds. *M·L*
- [x] **82. LOD on built objects.** Apply the existing `visibility_range_end` LOD (fish.gd ~2303, tiny@22u/small@32u) so distant builds drop fine detail. Builds in a multi-tank/wallpaper view especially need this. *M·M*
- [x] **83. A voxel budget with a live meter.** Show "build voxels: 3,200 / 20,000" so players self-regulate before the frame budget (there's already a frame-budget sparkline). Warn, don't hard-block. *M·M*
- [x] **84. Chunked rebuilds.** Editing one voxel shouldn't rebuild the whole batch. Chunk the build space so only the touched region's MultiMesh updates (the terrain mesh already debounces at `MESH_REBUILD_INTERVAL` ~0.12). *L·M* — debounced `sync_world_features` / `request_sync_deferred`.
- [x] **85. Occupancy & spawn-avoidance scales to builds.** `_mark_hardscape_occupancy` / `_is_hardscape_occupied` (~1859/1876) must cover player builds so fish don't swim through a solid castle. Update on every edit (debounced). *M·M*
- [x] **86. Deterministic save/restore round-trip.** Guarantee a built scape reloads voxel-identical (extend `restore_from_save` ~281 to the v2 schema). Add a round-trip unit check — a creative tool that loses work is dead. *M·L* — `smoke_aquascape.gd` round-trip check.
- [x] **87. Per-tank build cap + graceful degradation.** Define a hard ceiling tied to render tier; when approached, prevent new placement with a clear message rather than tanking FPS. *S·M*
- [x] **88. ✅ DECIDED — build physics is float OR gravity, toggleable.** Free-placed voxels default to **float** (Minecraft-creative: arches, platforms, overhangs all work), with a per-build/per-session **"gravity" toggle** that routes them through `settle_gravity()` like terrain. Persist the chosen mode in the build's save metadata (§I #77 v2 schema) so a reloaded build behaves as authored. Make the active mode legible in the build HUD (a small "✈ float / ⬇ gravity" indicator) so the rule is never a surprise. Terrain always obeys gravity regardless. *M·M*
- [x] **89. Background bake for big imports.** Pasting a 5,000-voxel shared build shouldn't hitch. Stream placement across frames with a progress indicator. *M·M* — `import_blueprint_async` + `_aquascape_import_continue`.
- [x] **90. Memory-safe blueprint storage.** Delta-encode + palette-index blueprints (not raw colors) so the library and share codes stay small (the genome codes are already compact — match that discipline). *M·M*

---

## J. UX, discoverability, camera & polish

The build experience itself — make it feel like a real editor, on desktop and
touch, and teach it.

- [x] **91. A real build-mode HUD.** `_build_palette()` (~548) is a single button row. Grow it into a proper editor panel: tool groups, object browser, color picker, finish picker, symmetry toggle, grid toggle, voxel counter. *M·L* — multi-row palette with tools, swatches, finishes, objects, budget; full editor panel still open.
- [x] **92. Build-mode camera that helps.** In build, allow free orbit/zoom/pan without fighting placement (RMB already orbits in aquascape). Add a "frame selection" and quick top/front/side snaps for precise alignment. *M·M* — top/front/side palette buttons → `apply_camera_preset`.
- [x] **93. Placement gizmos.** A translate/rotate/scale gizmo on the selected piece/group (standard 3-axis handles) so manipulation is direct, not keyboard-only. *L·M* — RGB axis handles on multi-select / dragged hardscape.
- [x] **94. Touch building that actually works.** Mobile has no keyboard shortcuts. Design a touch build flow: tap-to-place, long-press-to-remove, two-finger to orbit, on-screen tool/altitude controls. The sandbox must be mobile-first-class. *L·L* — build tool row + plane ▲/▼ + long-press radial; long-press erase via eraser tool.
- [x] **95. A ghost/preview that reads clearly.** Extend `_ensure_preview()` (~596) to show the exact voxel + a face-highlight on the target + an out-of-bounds red state. Confidence before commit. *M·M*
- [x] **96. Onboard the builder.** First entry to build mode: a 4-step coachmark (place a block, change color, place an object, save it). Ties to the onboarding pillar — the most creative surface needs the most teaching. *M·M*
- [x] **97. "Build with the lights on" toggle.** Temporarily bump ambient light + hide caustics/tint while building so colors read true; restore on exit. *S·M* — lights toggle via screenshot boost; restores on build exit.
- [x] **98. Quick-test: unpause to watch fish use the build.** A "preview life" button that briefly runs the sim so the builder sees fish explore the new cave/arch before committing. Closes the create→see-it-matter loop. *M·M*
- [x] **99. Keybinding + radial quick-menu for tools.** Surface tool switching via number keys (already partly wired, main.gd ~1779+) *and* a radial/long-press quick menu, with the cheat sheet kept in sync (onboarding pillar #41). *M·M* — 1–8 terrain/hardscape, 9 block, 0 eraser, Shift+Z redo, scroll build plane; radial menu still open.
- [x] **100. A "scape gallery" entry point on the tank shelf.** Make building discoverable from the menu, not just an in-tank mode — a "design a scape" affordance that invites the creative player in before they even stock fish. *M·M*

---

## If Cursor only does five (the spine of the whole pillar)

1. **#41** — generalize the existing prop-builder into a placeable, saveable
   **voxel-object system**. Everything in §E/§F/§H hangs off this.
2. **#11 + #12 + #13** — **free voxel place/remove in the water column** with
   face-adjacent stacking. The Minecraft leap; without it the rest is decoration.
3. **#81 + #86** — **MultiMesh-batched builds + deterministic save round-trip**.
   The non-negotiable foundation; build it once, correctly, early.
4. **#42 + #45** — ship **castles/shipwreck/ruins as a browsable object library**.
   The visible payoff that makes players *say* "I can build that?"
5. **#71 + #72 + #73** — **blueprints + share codes** (reuse the genome infra).
   Turns one player's castle into everyone's — the compounding loop.

Then layer §A (refine the base), §C (power tools), §G (craft guides), §J (polish).

---

## Manual QA checklist

- Enter build, place a free-floating voxel arch mid-water, save, reload → it
  returns voxel-identical and the fish swim *around* it, not through it.
- Build a castle from the library, edit it (recolor a tower, knock out voxels),
  save as a blueprint, export a code, import it into a *second* tank.
- Lay a 3,000-voxel build at 16× sim speed → frame budget holds (batched + LOD).
- Build a cave; a timid/cave-spawning fish hides/claims it; biofilm grows on it
  and a shrimp grazes it over time.
- Toggle the composition overlay; main stone snaps to a thirds power-point; the
  scape reads as the intended style.
- Mobile: build, recolor, place an object, and orbit — all by touch, no keyboard.
- Voxel budget meter warns near the cap and blocks placement gracefully (no crash,
  no silent FPS collapse).
