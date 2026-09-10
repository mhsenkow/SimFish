# Plant Systems — 50 Campaign

*Drafted 2026-09-10. Technical game-design backlog for the plant systems campaign.*

The brief: make aquarium plants visually alive, computationally scalable,
generatively distinct, and ecologically consequential. This document reconciles
the focused 50-item pass with `PLANT_NATURALISM_1000_IDEAS.md`,
`PLANT_IMPROVEMENT_IDEAS.md`, and shipped work in `GOALS.md`; items extend those
systems rather than rebuilding them.

**Format:** **Effort** S (≤2h), M (half-day), L (full day+). **Impact** S
(polish), M (noticeable), L (system-changing). Mark one item complete only after
its targeted smoke, `dev/compile_check.gd`, and `smoke_tank_shapes.gd` pass.
Use one focused commit per item: `PLANT_SYSTEMS_50 #N`.

## If this campaign only does ten

1. **#26 Foliage material lifetime** — fixes a silent correctness bug above 96 plants.
2. **#21 Dynamic foliage bounds** — makes existing frustum culling useful.
3. **#14 Rooted-plant visibility ranges** — bounds distant rendering cost.
4. **#16 Batched stems** — removes the largest rooted-plant draw-call source.
5. **#24 Distance-bucketed plant ticks** — creates CPU room for richer ecology.
6. **#42 Honest iron and CO₂ fields** — replaces inferred deficiencies with causes.
7. **#40 Structured seed bank** — substrate for real dispersal, crossing, and succession.
8. **#29 Visible etiolation** — makes light competition readable in plant form.
9. **#41 Runtime outcrossing** — activates the shipped but unused genome blend.
10. **#1 Foliage caustics** — visually seats plants in the same water as the tank.

**Sequencing:** technical scale → ecological substrate → generative growth →
reproduction → visuals. The numbered categories remain stable for design
reference; implementation follows dependency order, not numeric order.

---

## Artistic & Visuals (1–13)

*Grounding: `foliage.gdshader`, `foliage_mm.gdshader`, `voxel_mat.gd`,
`plant.gd`, `world.gd`, and the existing palette/caustic pipeline.*

- [x] **1. Foliage caustic shimmer.** Port the existing lightweight aquatic
  caustic term from `voxel.gdshader` into both foliage shaders and update it
  through the current throttled global-uniform path. Keep it palette-stable and
  disable it at the lowest shader tier. — Shipped with the bounded two-wave
  voxel term, shared throttled updates, and a zero-cost low-tier gate. *Effort: M · Impact: L*
- [x] **2. Per-instance leaf thickness.** Enable MultiMesh custom data and pack
  a normalized thickness value while baking each leaf voxel; use it to attenuate
  backlight and the fake SSS rim on petioles and thick leaf centers. — Shipped
  in custom-data R with deterministic center weighting and no extra materials. *M · M*
- [x] **3. Resolve the dormant stem shader.** Measure the existing unused
  `stem_subsurface.gdshader` against the foliage material after stems are
  batched; wire it in if it improves stem readability without excess material
  churn, otherwise remove the dead shader factory and asset. — Removed after
  confirming zero callers; reuse saves one material per plant and keeps stems
  on the registered palette/lighting path. *S · M*
- [x] **4. Waterline wet-sheen band.** Use the existing water-surface uniform to
  add a narrow, view-dependent highlight around foliage crossing the waterline,
  with reduced intensity under the palette potato tier. — Shipped as a 13 cm
  bounded band with a 0.10 potato-tier cap. *S · M*
- [x] **5. Per-leaf sway desynchronization.** Add a stable phase value to baked
  leaf instances so leaves within one crown ripple independently while
  preserving the existing per-plant sway personality. Extends Naturalism #204.
  — Shipped in custom-data G using a deterministic geometry/order hash; material
  count remains one per plant. *M · M*
- [x] **6. Spatial gust wave.** Extend the shipped CPU gust tilt
  (Plant Improvement #30 / Naturalism #202) with a bounded shader wave driven
  by gust origin, radius, and age, so disturbances propagate across nearby
  foliage rather than rotating every leaf uniformly. — Shipped with an 8 m /
  3 s cap, distance-weighted CPU tilt, and reduced-motion hard disable. *M · L*
- [ ] **7. Plant canopy blob shadows.** Merge a budgeted set of plant crown
  spheres into the substrate shader's existing blob-shadow input, prioritizing
  nearby and high-biomass plants alongside fish. *M · L*
- [ ] **8. Baked crown self-occlusion.** During leaf baking, estimate local
  foliage density and darken only the instance base color of crowded interior
  voxels. This gives crowns depth without real-time AO or shadow maps. *M · M*
- [ ] **9. Light-history anthocyanin.** Extend the shipped dynamic blush and
  `red_potential` with a slowly accumulated per-leaf light dose, making exposed
  tops redden while shaded old leaves stay green. Completes the shared pigment
  intent of Naturalism #281–282. *M · L*
- [ ] **10. Translucent senescence batch.** Move late-senescent leaf handles
  into a small secondary batch using a palette-safe translucent foliage
  material, preserving the shipped leaf lifecycle while leaves thin to amber
  before shedding. Extends Naturalism #67/#292. *L · M*
- [ ] **11. Canopy-attenuated god rays.** Build a low-resolution canopy-density
  mask from crown summaries every few seconds and sample it in
  `god_ray.gdshader`, allowing dense planting to interrupt fake light shafts.
  *L · M*
- [ ] **12. Leaf-anchored pearling.** Choose living mature leaf handles as
  origins for the shared pearling pool and add a brief host-leaf highlight when
  a bubble detaches. Extends Naturalism #178/#779 without adding per-plant
  particle systems. *M · L*
- [ ] **13. Golden-hour foliage rim.** Feed the existing day phase and light
  direction into a restrained warm edge term during dawn and dusk, respecting
  accessibility and shader performance tiers. Extends Naturalism #289. *S · M*

## Technical Rendering (14–26)

*Grounding: rooted plants already batch leaves through `VoxelBatch`, while
stems remain individual `MeshInstance3D` nodes. Floaters have explicit LOD;
rooted plants do not.*

- [x] **14. Rooted-plant visibility ranges.** Apply height-scaled
  `visibility_range_end` and self-fade settings to rooted stem and foliage
  renderers, using the proven fish/floater LOD conventions. — Shipped with a
  mature-height bonus and render-registry smoke coverage. *S · L*
- [x] **15. Reversible leaf instance LOD.** At distance, zero-scale a stable
  subset of non-silhouette leaf handles and restore their original transforms
  when near; never delete handles or alter biological biomass. — Shipped with
  transition-only extrema preservation and damage-safe handle visibility.
  *M · M*
- [x] **16. Batched rooted stems.** Replace per-voxel stem `MeshInstance3D`
  nodes with a second per-plant `VoxelBatch`, retaining stable handles for
  grazing, aging, save restore, and color updates. — Shipped with reversible
  handle visibility, batched growth reveal, and subclass compatibility. *L · L*
- [x] **17. Tank-wide far-foliage batch.** For distant plants only, mirror
  simplified stem and leaf transforms into one world-owned MultiMesh and hide
  their private render batches. Gate the feature on profiling because transfer
  overhead can outweigh draw-call savings in small tanks. — Shipped behind
  12-plant/600-instance and 1.8 ms rebuild gates; 600 instances mirrored in
  1.4–1.7 ms while consolidating 23 draws in headless profiling. *L · M*
- [x] **18. Measured plant/fragment pooling.** Instrument spawn/free churn
  during trimming and die-offs; add bounded resettable pools only for node types
  shown to produce meaningful allocation spikes. Preserve `queue_free()` as the
  fallback for oversized or incompatible instances. — Shipped for measured
  `PlantFragment` churn only, after an eight-finish gate, with a 32-node cap
  and full mutable-state reset. *L · S*
- [x] **19. MultiMesh buffer compaction.** When live handles remain below one
  quarter of capacity for a sustained interval, rebuild into a smaller buffer
  and remap handles atomically. Never compact during an active bake. — Shipped
  with a five-second hold, 64-slot floor, and stable live-handle remapping.
  *M · M*
- [x] **20. Static-plant sleep state.** Skip nonessential visual/state work for
  plants with no growth, damage, deficiency, reproduction, or environment
  changes, and wake them through explicit dirty signals. Continue chemistry at
  the required coarse rate. — Shipped with five-second calm detection,
  two-second accumulated chemistry ticks, and explicit wake paths. *M · M*
- [x] **21. Dynamic foliage bounds.** Replace `VoxelBatch`'s oversized constant
  AABB with live instance bounds expanded by maximum sway, recomputed only when
  transforms change. — Shipped with configurable sway margins and render
  registry smoke coverage. *S · L*
- [x] **22. Amortized leaf baking.** Queue large leaf templates as bounded
  chunks consumed across frames under the existing tank-wide plant growth
  budget, with one final batch flush. — Shipped with stable up-front handles,
  12-instance upload chunks, and atomic final visibility. *M · M*
- [x] **23. Data-only leaf template cache.** Cache immutable
  transform/color descriptors for each quantized leaf form and size instead of
  allocating temporary `MeshInstance3D` trees before every bake. — Shipped for
  deterministic forms with a bounded 192-entry cache and parity smoke. *L · L*
- [x] **24. Distance-bucketed plant simulation.** Tick distant plants at lower
  frequency with accumulated elapsed time and deterministic scheduling, while
  keeping nearby, reproducing, or stressed plants responsive. Extends the
  motion-only intent of Naturalism #222. — Shipped with 1×/2×/4× distance
  buckets and complete elapsed-time integration. *M · L*
- [x] **25. Hardscape occluders.** Generate conservative occluder volumes for
  large opaque rocks and driftwood only, avoiding thin or moving geometry;
  enable them only when profiling proves a net win for typical tank cameras.
  — Shipped with 72%-inset box volumes, opaque/static/chunky eligibility,
  benefit scoring, and a potato-quality fallback. *L · S*
- [x] **26. Foliage material lifetime registry.** Replace the silent
  `FOLIAGE_MM_CAP = 96` refusal with weak-owner registration and stale-entry
  eviction, ensuring every living plant continues receiving daylight, flow,
  and palette uniforms. — Shipped via weak material references and
  `smoke_plant_render_registry.gd`. *S · L*

## Generative Growth (27–38)

*Grounding: `PlantGenome` already carries branching parameters and mutation;
`BranchPlant` is L-system-inspired but has no rule rewriting.*

- [x] **27. Bounded L-system grammar.** Add optional axiom and production-rule
  traits with a small interpreter for forward, turn, push, and pop commands.
  Derive incrementally under depth, symbol, voxel, and per-tick limits, falling
  back to current probabilistic branching for old genomes. — Shipped with
  sanitized F/+/-/[/] commands and strict derivation/runtime caps. *L · L*
- [x] **28. Auxin apical dominance.** Compute a cheap apex hormone value that
  decays down nodes and suppresses lateral release; apex loss immediately
  removes the source and frees nearby buds. — Shipped with architecture-only
  O(nodes) profiles and immediate cut-triggered release. Implements Naturalism #4. *M · L*
- [x] **29. Visible etiolation.** Convert accumulated low-light history into
  longer internodes and temporarily reduced leaf investment at placement time,
  while bright growth remains compact. — Shipped with future-only internode
  extension, bounded leaf investment, and legacy-zero sensitivity. Implements Naturalism #3/#176/#197.
  *M · L*
- [x] **30. Stem growth-history samples.** Store a compact limiting-factor code
  on each new stem handle and expose the vertical history in the plant
  inspector. — Shipped as one integer per handle with save/load and an
  on-demand inspector history; old conditions are never recomputed. *M · M*
- [x] **31. Root/shoot resource reservoirs.** Split plant reserves into root
  uptake and shoot demand pools connected by a genome-defined transport rate,
  producing tip-first starvation when vascular capacity is insufficient. —
  Shipped with bounded conserving pools and a legacy single-charge path. *L · L*
- [x] **32. Juvenile/adult heteroblasty.** Add juvenile and adult leaf forms to
  the genome and transition by node age, independently from the shipped
  submerged/emergent heterophylly. — Shipped with a persistent node threshold
  and independent emersed morphology. Implements Naturalism #51. *L · L*
- [x] **33. Space-colonized crown fill.** Offer branch species a bounded set of
  attraction points in lit free volume and steer tips toward unclaimed points,
  yielding asymmetrical airy crowns without replacing the base growth budget. —
  Shipped with 24-point deterministic crowns and nearest-tip claiming.
  *L · L*
- [x] **34. Species growth curves.** Add genome-defined establishment,
  acceleration, and plateau parameters and use a sigmoid multiplier around the
  existing soft-min resource rate. — Shipped as a bounded sigmoid multiplier;
  zero acceleration preserves the legacy rate. *M · M*
- [x] **35. Architectural reiteration after damage.** When biomass loss exceeds
  a configurable fraction, restart a scaled copy of the growth program from a
  surviving node rather than merely resuming the severed axis. — Shipped once
  per bounded damage episode from a surviving mid-axis node. Completes Naturalism #27. *L · L*
- [x] **36. Nutrient-seeking roots.** Grow visible root tips incrementally
  toward richer neighboring substrate cells while preserving the current
  golden-angle fallback in uniform soil. — Shipped with eight-cell coarse
  sampling under the existing root-growth cadence. Implements Naturalism #125. *M · L*
- [x] **37. Seasonal bulb wake gates.** Add photoperiod and temperature windows
  to the shipped timed/rich-substrate bulb resprout path, with a maximum dormant
  duration safety valve. — Shipped with opt-in windows, maximum dormancy, and
  unchanged legacy rich-substrate fallback. Extends Naturalism #260/#490. *M · M*
- [x] **38. Constrained procedural species.** Sample new genomes from correlated
  ecological archetypes and reject implausible trait combinations before
  mutation, keeping hand-authored `RealSpeciesLibrary` entries as anchors. —
  Shipped with fixed-seed sampling, eight-attempt rejection, and anchored fallback.
  *L · L*

## Reproduction & Ecology (39–50)

*Grounding: the substrate has scalar seed/allelopathy/root-oxygen channels,
runtime reproduction mutates clones, and `PlantGenome.blend()` is not used by
normal flowering.*

- [x] **39. Flow-integrated seed landing.** Simulate the visible seed mote
  against `TankFlowField` first and deposit into the seed bank at its actual
  final cell, rather than selecting a destination before the drift animation.
  — Shipped with bounded flow-integrated motes, tank/floor clamping, final-cell
  deposition, and a no-flow settling fallback. Extends Plant Improvement #47 /
  Naturalism #440. *M · L*
- [x] **40. Structured seed bank.** Replace each scalar cell with a bounded set
  of seed lots containing genome identity, quantity, age, viability, and
  dormancy requirements, while migrating old scalar saves into anonymous lots.
  — Shipped with eight-lot/one-unit cell bounds, genome-bearing germination,
  JSON roundtrip coverage, and anonymous scalar migration. Implements
  Naturalism #404. *L · L*
- [x] **41. Runtime outcrossing.** Pair compatible mature flowers within a
  pollination radius and produce offspring through the shipped
  `PlantGenome.blend()` function; self or clonal mutation remains the fallback
  when no partner exists. — Shipped with bounded nearest-partner lookup,
  compatibility/cooldown gates, blended mutation, and both-parent lineage
  retention. Implements Naturalism #366. *M · L*
- [x] **42. Honest iron and CO₂ fields.** Add bounded dirty-cell availability
  channels fed by water chemistry and substrate processes, and make roots
  consume them so deficiency visuals reflect a cause the player can change.
  — Shipped with sparse bounded pore-water exchange, root uptake, grounded
  deficiency cues, and legacy-safe defaults. Extends GOALS H #58 /
  Naturalism #907. *L · L*
- [x] **43. Mulm mineralization loop.** Route shed/dead plant biomass into a
  per-cell litter/mulm reservoir that settles and releases nutrients over time
  instead of returning a flat amount instantly. — Shipped with bounded
  plant-detritus settling, mass-conserving mineralization, and pre-reservoir
  save fallback. Extends Naturalism #272/#805. *L · L*
- [x] **44. Reproductive cattail puffs.** Turn `_puff_seed()` into bounded
  surface-flow seed motes that attempt rooting at valid shoreline cells, using
  the common capacity and seed-bank rules. Completes the existing stub and
  Naturalism #514. — Shipped with common bounded motes, surface-flow advection,
  shoreline/hardscape validation, and structured-bank/capacity gating. *M · M*
- [x] **45. Surface-plant ecology adapter.** Register lily pads, cattails,
  nautilus plants, and fractal moss through a small common ecological interface
  for biomass, nutrient demand, grazing, and death without forcing them to
  inherit `Plant`. — Shipped with capability adapters, coarse nutrient uptake,
  litter-returning death, grazing, and unified photosynthetic accounting.
  *L · L*
- [x] **46. Complete hardscape epiphyte placement.** Extend the shipped
  layout-time epiphyte placement to manual/library/autonomous spawn paths and
  validate attachment against rock/wood surfaces before substrate fallback.
  — Shipped with shared bounded rock/wood lookup across initial, library, and
  autonomous paths plus rooted substrate fallback. Extends Naturalism
  #129/#662. *M · M*
- [x] **47. Family-aware allelopathy.** Store a bounded emitter-family mix per
  affected cell and add heritable family resistance, preventing emitters and
  close kin from suffering the same penalty as competitors. Extends
  Naturalism #682/#699. — Shipped with four-family cell caps, decaying mixes,
  scalar-save migration, and bounded inherited kin resistance. *L · L*
- [x] **48. Root-footprint competition.** Register coarse per-plant root
  footprints and divide each cell's available uptake by overlapping active root
  mass, replacing the current large-plant halo strip. Extends GOALS F #36 /
  Naturalism #133/#146. — Shipped with bounded 13-cell footprints, proportional
  active-root sharing, and 2 Hz refresh/stale-root cleanup. *L · L*
- [x] **49. Grazing-driven selection.** Track lifetime grazing pressure and let
  survivors pass a bounded defense/palatability shift with an explicit growth
  cost through the existing mutation pipeline. Runtime acclimation remains
  nonheritable until reproduction. — Shipped with persistent lifetime pressure,
  reproduction-only bounded defense shifts, and explicit growth/nutrient costs.
  *M · L*
- [x] **50. Succession and establishment ledger.** Record germination,
  establishment, and local extinction in `PlantLineageRegistry`, then use
  recent disturbance and cell maturity to bias eligible seed lots without
  overriding environmental requirements. — Shipped with a 256-event persistent
  ledger, saved cell history, dormancy-safe eligibility, and succession bias.
  Extends Naturalism #409/#696. *L · L*

---

## Campaign verification

- Rendering items report before/after visible instances, draw calls or frame
  time under the Mobile renderer and macOS-safe MultiMesh path.
- Growth/genome items round-trip old and new genomes and remain deterministic
  under a fixed seed.
- Substrate/save items load legacy scalar saves, serialize the new format, and
  reload without losing total mass or viability.
- Ecology items run under population caps and cannot create unbounded nodes,
  records, shader materials, or per-frame work.
