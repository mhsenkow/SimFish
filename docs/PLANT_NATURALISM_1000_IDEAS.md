# Plants — 1000 Naturalism Ideas

*Drafted 2026-09-10. Director's mega-backlog for the "plants like the wild" pass.*

The brief: make plants read as **wild living things** — they grow the way real
aquatic plants grow, multiply the way wild populations multiply, and mutate so
no two tanks ever converge. Aesthetically: arguably beautiful, never tidy.

This doc extends (never rebuilds) the shipped system. Ground truth lives in:
[`plant.gd`](../shaders-godot/godot-project/scripts/plant.gd) (growth, tick,
limiters), [`plant_genome.gd`](../shaders-godot/godot-project/scripts/plant_genome.gd)
(trait schema: phyllotaxis, `ls_angle`/`ls_ratio`/`ls_depth`, `repro_mode`,
dormancy, variegation, `red_potential`, `asymmetry_seed`),
[`plant_fragment.gd`](../shaders-godot/godot-project/scripts/plant_fragment.gd),
[`lily_pad.gd`](../shaders-godot/godot-project/scripts/lily_pad.gd),
[`floating_plant.gd`](../shaders-godot/godot-project/scripts/floating_plant.gd),
the shape plants (`branch_plant.gd`, `spiral_plant.gd`, `cattail_plant.gd`,
`nautilus_plant.gd`), and
[`foliage.gdshader`](../shaders-godot/godot-project/shaders/foliage.gdshader).
See also [PLANT_IMPROVEMENT_IDEAS.md](PLANT_IMPROVEMENT_IDEAS.md) (the 50-item
tuning pass), [PLANT_SYSTEMS_50_IDEAS.md](PLANT_SYSTEMS_50_IDEAS.md) (the
render-scale, generative-growth, and ecology campaign), and GOALS.md sections
D/F/G/H — **do not re-ship what's there.**

**Format note:** with 1000 items, per-item effort tags would drown the signal.
Assume S–M effort unless an item is flagged **(L)**. Sections carry the code
grounding; items are one-line specs. Mark items `- [x]` as they ship, one
commit per item, referencing this doc + item number.

## If this doc only does ten (the substrate — do these first)

1. **#1 Tropism vector field** — shipped (`Plant._tropism` / `_refresh_tropism`).
2. **#41 Leaf lifecycle state machine** — shipped (`LeafPhase` + `_advance_leaf_phase`).
3. **#201 Unified flow coupling** — already shipped (`TankFlowField`); fragments now sample it too.
4. **#281 Pigment response layer** — still open (blush/red_potential exist; needs shared service).
5. **#361 Mutation-on-propagation pipeline** — shipped (`PlantGenome.mutate(mode)`).
6. **#441 Lineage bookkeeping** — shipped (`PlantLineageRegistry` + `drift_distance`).
7. **#601 Propagation economy caps** — already shipped (`plants_at_capacity` / volume soft cap).
8. **#761 Micro-variation material service** — shipped (`Plant._micro_vary_color`).
9. **#841 Composition sampler** — still open.
10. **#961 Rare-event scheduler** — still open.

**Sequencing:** substrate items first, then their dependents inside each
section (sections are ordered roughly stem→leaf→root→motion→color→death→
reproduction→genetics→community→render→wonder). One idea at a time.

---

## Section 1 — Stem & branching architecture (1–40)

*Grounding: `branch_plant.gd`, `plant.gd` voxel stacking, genome `ls_angle`/`ls_ratio`/`ls_depth`.*

- [x] **1. Tropism vector field.** Give every plant a persistent `_tropism: Vector3` (light dir + anti-gravity + flow bias) that all new voxel placement leans toward. **(L)** — `_refresh_tropism` / `_tropism_lateral_offset` in `plant.gd`; growth uses it instead of photo-only lean.
- [ ] **2. Sympodial vs monopodial flag.** Genome bit: main stem either keeps its apex or hands off to a side branch each internode cycle — two totally different silhouettes for free.
- [ ] **3. Internode length gradient.** Internodes lengthen under low light (etiolation you can *see*), shorten under strong light — read `_light_avg` at placement time.
- [ ] **4. Apical dominance decay.** Side branches stay suppressed near the tip and release with distance from apex, so bushiness starts low and old.
- [ ] **5. Branch angle from `ls_angle` with noise.** Jitter every real branch ±15% around the genome angle using `asymmetry_seed` so no two branchings match.
- [ ] **6. Basal shoots.** Old healthy plants occasionally push a new shoot from the substrate line, thickening the clump from below like real crypts.
- [ ] **7. Stem thickening with age.** Base voxels widen (or darken as pseudo-thickness) as total height grows — old stems look load-bearing.
- [ ] **8. Decumbent creep.** Stems that outgrow their light budget flop and grow horizontally along the substrate a few voxels before turning up again.
- [ ] **9. Broken-apex recovery fork.** If the top voxel is lost (nip, melt), two laterals release and race — the classic topped-plant "V".
- [ ] **10. Stem scarring.** Where a leaf or branch was shed, leave a one-voxel darker node scar that persists — history written on the stem.
- [ ] **11. Zig-zag distichous stems.** When phyllotaxis is distichous, offset alternate internodes slightly for the real zig-zag axis.
- [ ] **12. Genome `branch_prob` trait.** Continuous 0..1 branching tendency, mutable, replacing any hard-coded per-shape constants.
- [ ] **13. Lean into open water.** Plants near a wall or hardscape bias `_tropism` away from the obstruction — canopy leans into the free volume.
- [ ] **14. Stem curvature memory.** Store the bend the stem grew with; sway animates *around* the grown curve instead of a straight rest pose.
- [ ] **15. Prostrate juvenile phase.** Some species run 3–5 voxels along the ground before turning upright — believable carpet-to-stem transitions.
- [ ] **16. Overtopping race.** When shaded by a taller neighbor, spend growth on height (longer internodes, fewer leaves) until clear — visible competition.
- [ ] **17. Branch shedding.** A branch whose leaves are all senescent is dropped whole as one fragment — self-pruning like wild stem plants.
- [ ] **18. Second-order branching.** Let branches branch (depth from `ls_depth`) with strictly decaying probability so crowns stay airy, not fractal-dense.
- [ ] **19. Nodal roots on lower stem.** Stem voxels near the substrate sprout tiny adventitious root nubs — the hallmark of real stem plants.
- [ ] **20. Stem color gradient.** Older basal stem shifts brown-green; new tip stays bright — one gradient sells time.
- [ ] **21. Weeping habit gene.** Rare trait: branch tips arc downward once past a length threshold (willow moss / weeping mode).
- [ ] **22. Fasciation rarity.** Ultra-rare mutation: a flattened, fan-shaped crested stem section — collector's oddity, purely cosmetic.
- [ ] **23. Internode-count flowering gate.** Flowering only after N internodes, so a plant's *shape* tells you if it can bloom yet.
- [ ] **24. Stolon arcs.** Runner-type species send an arched stolon that touches down 2–4 voxels away and roots — the arc itself renders.
- [ ] **25. Torsion.** Slight cumulative twist per internode (genome `twist_per_node`), giving spiral stems like vallisneria's gentle corkscrew.
- [ ] **26. Wind-load pruning.** In strong flow zones, over-long unsupported branches snap into fragments — flow shapes architecture.
- [ ] **27. Reiteration after damage.** A badly damaged plant restarts a miniature copy of its whole architecture from a surviving node.
- [ ] **28. Stem hollowing read.** Very old tall stems get a subtle darker core line — visual age without new geometry.
- [ ] **29. Layering.** A decumbent stem touching substrate roots at the contact node and can later separate into an independent plant.
- [ ] **30. Crown asymmetry from history.** Branch density remembers where light *was* — moving the lamp leaves a lopsided crown that slowly rebalances.
- [ ] **31. Genome `internode_len` trait.** Base internode spacing as a mutable trait; tall wispy vs compact bushy from one number.
- [ ] **32. Bolting.** Pre-flower stage: sudden fast thin vertical growth spike toward the surface, distinct from normal growth.
- [ ] **33. Self-shading feedback.** Interior branches of a dense crown senesce first, hollowing the middle like a real old bush. 
- [ ] **34. Terminal vs axillary flowering flag.** Blooms either cap the stem or dot the leaf axils — two distinct flowering silhouettes.
- [ ] **35. Nutrient-luxury bushiness.** Sustained rich water raises branch release probability — lush tanks *look* lush structurally.
- [ ] **36. Contact avoidance.** New branch placement rejects positions inside a neighbor's crown envelope — crown shyness, subtle gaps between plants.
- [ ] **37. Kinked recovery joints.** A stem that resumed growth after dormancy keeps a visible kink at the resume point.
- [ ] **38. Ground-hugging rosette gene.** Zero internode variant: leaves all from one basal point (echinodorus/crypt rosette), reusing leaf code with stacked origin.
- [ ] **39. Branch age ordering.** Render/animate older branches with slower, heavier sway than young whips — one crown, many ages.
- [ ] **40. Architectural smoke test.** `scripts/smoke_plant_wildform.gd`: grow 50 random genomes headless, assert silhouettes differ (pairwise voxel-set distance above threshold).

## Section 2 — Leaf morphology & the leaf lifecycle (41–80)

*Grounding: leaf builders in `plant.gd`, genome `leaf_form`/`leaf_length`/`leaf_size_mult`/`wavy_edges`/`quilted`.*

- [x] **41. Leaf lifecycle state machine.** Per-leaf state: BUD → EXPANDING → MATURE → SENESCENT → SHED, each with its own scale/color/sway params. **(L)** — `LeafPhase` on `_leaf_states`; tip-first senescence paint; shed via `_shed_leaf_at`.
- [ ] **42. Bud unfurling.** New leaves start as a tight 1-voxel curl and unroll over ~20 s — the single strongest "it's growing" cue.
- [ ] **43. Size-up sequence.** Successive leaves on a young plant get progressively larger, so juveniles have visibly smaller foliage low down.
- [ ] **44. Marginal wave amplitude from `wavy_edges`.** Make the bool a float; crinkle amplitude becomes mutable and heritable (crispus-style ruffles).
- [ ] **45. Leaf tip drip point.** Slight elongated droop at each leaf tip — the classic drip-tip read, even underwater it reads "tropical".
- [ ] **46. Heterophylly by depth.** Leaves built near the surface use the emersed form; deep leaves use submersed form — one plant, two foliages.
- [ ] **47. Petiole vs sessile trait.** Leaves either sit on a small stalk voxel or clasp the stem directly — big silhouette difference, one bit.
- [ ] **48. Leaf aspect-ratio trait.** Continuous strap↔round trait, mutable, blending between existing leaf builders instead of discrete forms.
- [ ] **49. Midrib highlight.** One-voxel lighter line down big leaves; venation at voxel scale.
- [ ] **50. Quilting depth from `quilted`.** Convert to float; puckered bullate surfaces get per-leaf random pucker phase.
- [ ] **51. Juvenile vs adult leaf form.** Genome pair of forms with an age crossfade — real aroids/hygros switch shape as they mature.
- [ ] **52. Leaf torn edges.** Old MATURE leaves accumulate small edge notches (flow damage) before senescing — never pristine for long.
- [ ] **53. Hole feeding windows.** Herbivore nibbles punch 1-voxel holes *inside* the leaf blade, not just edges — madagascar-lace aesthetic when heavy.
- [ ] **54. Senescent color ramp.** SENESCENT leaves run green → yellow → amber → brown translucent over minutes, per-leaf desynced.
- [ ] **55. Shed as detritus.** SHED leaves detach as drifting fragments that settle into the litter layer (feeds Section 21).
- [ ] **56. Leaf lifespan trait.** Genome `leaf_life`: crypts hold leaves for ages, stem weeds churn them fast — turnover defines character.
- [ ] **57. Downturned old leaves.** MATURE→SENESCENT leaves droop their pitch angle a few degrees per minute — age you can read in posture.
- [ ] **58. New-growth tip color.** EXPANDING leaves render brighter/yellower (low chlorophyll) then darken to mature tone — glowing tips on healthy plants.
- [ ] **59. Leaf twist along length.** Long strap leaves get a gentle half-twist (vallisneria contortionist trait, mutable amplitude).
- [ ] **60. Pinnate split trait.** Rare form: leaf renders as paired leaflets along a rachis — fern/milfoil texture class.
- [ ] **61. Leaf overlap avoidance.** New leaf azimuth nudges away from the nearest existing leaf's angle — natural even spacing without perfect symmetry.
- [ ] **62. Water-line burn.** Emersed leaf voxels right at the waterline develop a tan scorch band when humidity (surface agitation) is low.
- [ ] **63. Curl under stress.** Nutrient-stressed leaves curl their edge voxels upward slightly — the aquarist's classic deficiency read.
- [ ] **64. Interveinal chlorosis.** Iron-poor water yellows leaf bodies while midrib stays green — teaches chemistry through appearance.
- [ ] **65. Old-leaf algae seeding.** Only MATURE+ leaves can host epiphytic algae specks; new growth stays clean — exactly like real tanks.
- [ ] **66. Leaf scale sway coupling.** Bigger leaves sway slower (mass), small leaves flutter — per-leaf sway frequency from size.
- [ ] **67. Translucency by age.** SENESCENT leaves go slightly translucent (alpha or value lift) before shedding — light through dying leaves is beautiful.
- [ ] **68. Bite-recovery regrowth.** A leaf losing >50% of voxels is aborted and a replacement bud starts at the same node.
- [ ] **69. Cotyledon stage.** Seed-sprouted plants open with two tiny round starter leaves that later shed — seedlings look like seedlings.
- [ ] **70. Leaf whorl droop cascade.** In whorled species, lower whorls droop more than upper — a fountain profile per stem.
- [ ] **71. Sun vs shade leaves.** Leaves built under high `_light_avg` are smaller/thicker-toned; shade leaves larger/darker — one plant maps its own light field.
- [ ] **72. Perforation gene.** Rare heritable trait: healthy leaves grow with regular holes (fenestration) — a prized mutation line.
- [ ] **73. Red underside from `underside_tone`.** Ensure underside tone shows during sway when leaves tilt past the camera — flicker of wine-red under green.
- [ ] **74. Leaf armor trait.** High `leaf_thickness` leaves resist nibbles and tears but expand slower — visible strategy tradeoff.
- [ ] **75. Damaged-leaf asymmetric sway.** Torn leaves sway with a slight flutter irregularity — damage changes motion, not just look.
- [ ] **76. Bud scale litter.** Each unfurl drops a 1-voxel husk that drifts down — growth leaves evidence.
- [ ] **77. Bolting leaf reduction.** During flowering bolt, new leaves shrink up the stem (bracts) — the stem visibly commits to the bloom.
- [ ] **78. Bronze new-growth trait.** Some lineages open leaves bronze-red then green up (real ludwigia behavior); ties into `red_potential`.
- [ ] **79. Leaf count carrying capacity.** Per-plant max live leaves from energy budget; new buds force oldest leaf into senescence — steady wild churn.
- [ ] **80. Leaf lifecycle smoke.** `scripts/smoke_leaf_lifecycle.gd`: fast-tick one plant, assert every leaf state transition fires and shed leaves become fragments.

## Section 3 — Phyllotaxis & arrangement (81–120)

*Grounding: genome `phyllotaxis`/`whorl_count`, `Plant._resolve_phyllotaxis`.*

- [ ] **81. Golden-angle spiral default.** Spiral mode places leaves at 137.5° ± genome jitter — instantly reads organic vs the current even spacing.
- [ ] **82. Mutable divergence angle.** Genome `divergence_deg` (mutates ±2°) so lineages drift toward looser or tighter spirals over generations.
- [ ] **83. Whorl count mutation.** `whorl_count` 3↔4↔5↔6 steps as a rare mutation — a 6-whorl sport in a 4-whorl species is a find.
- [ ] **84. Decussate 90° cross pairs.** True opposite-pair placement rotating 90° per node, with ±5° developmental noise.
- [ ] **85. Phyllotaxis transition with age.** Juvenile spiral → adult whorled crossover at a node threshold (real hygrophila does this).
- [ ] **86. Pseudo-whorl crowding.** Under high growth rate, spiral internodes compress until leaves *look* whorled at the tip — density from vigor.
- [ ] **87. Rosette golden spiral.** Rosette plants place leaves in the true sunflower spiral seen from above — top-down camera reward.
- [ ] **88. Phyllotaxis noise trait.** `phyllo_noise` 0..1: crystal-perfect at 0, drunken at 1 — most wild plants sit around 0.15.
- [ ] **89. Light-biased azimuth.** Leaf azimuth selection weights toward the bright side by up to 20° — arrangement responds to the lamp.
- [ ] **90. Node skip mutation.** Rare: a node produces no leaf, leaving a bare gap in the sequence — believable imperfection.
- [ ] **91. Double-leaf node sport.** Rare: two leaves from one spiral node at ~60° — twinning defect that can breed true.
- [ ] **92. Distichous plane rotation.** The 2-ranked plane slowly rotates up the stem (a few degrees per node) so tall distichous stems present all sides.
- [ ] **93. Whorl phase offset per node.** Successive whorls rotate half a leaf-angle — the classic anti-shading offset stack.
- [ ] **94. Anisophylly.** In decussate pairs near horizontal stems, the down-facing leaf grows smaller — gravity-aware pairs.
- [ ] **95. Phyllotaxis in the inspector.** Tap-a-plant shows the arrangement name + divergence angle — makes the system legible and collectible.
- [ ] **96. Carpet runner spacing angle.** Carpet species place successive runners at golden angle around the parent — radial wild spread, no grids.
- [ ] **97. Secondary spiral visibility.** At high leaf counts, tune sizes so parastichy spirals (5/8/13 families) actually read on rosettes.
- [ ] **98. Arrangement-driven sway phase.** Seed each leaf's sway phase from its phyllotactic index — spiral plants ripple in spiral order under current.
- [ ] **99. Bract spiral on flower stalks.** Flowering bolts carry their reduced bracts in the same spiral — coherence up the whole plant.
- [ ] **100. Phyllo drift heat check.** Debug overlay: color leaves by divergence error from ideal — verify noise stays wild-plausible, not broken.
- [ ] **101. Opposite→alternate stress switch.** Chronic low light shifts new nodes from decussate to alternate spiral (maximizes capture) — arrangement as stress display.
- [ ] **102. Internode/angle covariance.** Mutations that shorten internodes slightly raise divergence noise — traits co-vary like real development.
- [ ] **103. Basal vs cauline arrangement.** Rosette species that bolt switch to sparse alternate leaves on the flower stem — two arrangements, one plant.
- [ ] **104. Whorl droop by index.** Within one whorl, leaves droop identically; between whorls, droop increases downward — clean vertical rhythm.
- [ ] **105. Phyllotaxis-aware nibbling.** Fish prefer the most accessible leaf by arrangement geometry (outermost azimuth gap) — grazing follows structure.
- [ ] **106. Spiral handedness.** 50/50 left/right spiral chirality per plant from `asymmetry_seed`; heritable with 5% flip — clumps mix handedness.
- [ ] **107. Fibonacci checker smoke.** Headless: assert long-run spiral leaf angular gaps approach golden-angle distribution within tolerance.
- [ ] **108. Arrangement rarity table.** Weight species defaults: spiral common, distichous uncommon, true whorls rare — tank diversity has texture.
- [ ] **109. Leaf axil bud rendering.** Tiny 1-voxel bud dot in each axil of mature nodes — the promise of branching, visible before it happens.
- [ ] **110. Axil bud activation order.** Released branches follow phyllotactic order, not random — watch the spiral wake up after topping.
- [ ] **111. Crowded-node abort.** If two leaves would overlap >60% at placement, abort the younger — arrangement self-corrects like real meristems.
- [ ] **112. Divergence angle inheritance blend.** Child divergence = parent ± mutation, but fragments keep parent exactly — sexual vs clonal variation visible in geometry.
- [ ] **113. Tristichous rarity.** Three-ranked arrangement (1/3 phyllotaxis) as a rare class for sedge-like species — vertical stripes of leaves.
- [ ] **114. Arrangement disruption on damage.** After apex loss, the first few recovery leaves place with doubled noise before settling — visible healing wobble.
- [ ] **115. Floating rosette packing.** Surface rosettes (frogbit-like) pack leaves by golden angle in the plane — pond-surface mandalas.
- [ ] **116. Angle-of-insertion trait.** Genome `leaf_pitch_deg`: erect (20°) ↔ horizontal (85°) ↔ recurved (110°), mutable — posture as heritable style.
- [ ] **117. Pitch relax with age.** Whatever the insertion pitch, add graded relaxation per leaf age — everything softens as it ages.
- [ ] **118. Phyllotaxis morph on emersion.** Leaves built above waterline tighten divergence noise (air is calmer than current) — subtle but honest.
- [ ] **119. Whorl symmetry break under flow.** Persistent strong current compresses downstream leaf angles a few degrees — wind-training, underwater.
- [ ] **120. Arrangement gallery capture.** Dev scene: grid of one plant per arrangement class for marketing/screenshot verification.

## Section 4 — Roots & substrate anchoring (121–160)

*Grounding: `max_roots` in genome, root builders in `plant.gd`, substrate boost in tick.*

- [ ] **121. Visible surface roots.** The top 1–2 voxels of major roots show above substrate as pale arcs — plants grip the ground visibly.
- [ ] **122. Root flare with age.** Old plants raise a small substrate mound at the base — buried growth pushing up.
- [ ] **123. White new root tips.** Actively growing roots render a bright tip voxel; stalled plants' roots are uniformly dull — health readable at the base.
- [ ] **124. Water-column feeder roots.** Floating and stem plants dangle fine roots into open water, drifting with current (extend `floating_plant.gd` roots to stem species near-surface nodes).
- [ ] **125. Root run toward nutrients.** Roots grow directionally toward high-substrate-nutrient cells if the sim tracks them — silent foraging.
- [ ] **126. Uprooting resistance from roots.** Anchor strength scales with root count/age; new plants can be knocked loose by large fish, old ones can't.
- [ ] **127. Runner root-down animation.** Stolon touchdown visibly pushes 2–3 root voxels over a second — planting itself while you watch.
- [ ] **128. Root senescence.** Very old roots darken and slough, replaced by new ones — turnover below matches turnover above.
- [ ] **129. Epiphyte holdfast.** `is_epiphyte` species grow gripping root pads over hardscape surface voxels instead of into substrate — anubias on wood done honestly.
- [ ] **130. Exposed roots after disturbance.** Substrate displacement (fish digging) exposes root arcs that re-bury slowly — the tank floor has history.
- [ ] **131. Root:shoot balance.** Poor substrate shifts energy to root growth (more/longer roots, slower top) — struggle has a visible strategy.
- [ ] **132. Adventitious water roots on trimmed stems.** Replanted fragment stems push visible roots from buried nodes within a minute — propagation feels real.
- [ ] **133. Root competition spacing.** Root systems of neighbors avoid overlap; dense plantings visibly stunt root spread — below-ground crowding.
- [ ] **134. Tuber rendering for dormancy.** `DORMANCY_TUBER` species show a bulb voxel at the crown that swells before dormancy — the pantry is visible.
- [ ] **135. Root hair fuzz pass.** Near-camera shader fuzz on root voxels — soft halo, not geometry.
- [ ] **136. Substrate type affects root form.** Sand: long shallow runners; soil: deep compact mass — same genome, different underground body.
- [ ] **137. Root-bound stunting.** A plant hitting tank glass with roots caps its size below genome max — jar tanks grow bonsai.
- [ ] **138. Floating plant root length = nutrient gauge.** Long trailing roots in lean water, short stubs in rich — the classic duckweed diagnostic, automated.
- [ ] **139. Root grazing.** Bottom-feeders occasionally tug exposed roots, triggering a plant shudder — interaction between layers.
- [ ] **140. Buttress asymmetry.** Root flare biases toward the prevailing current direction (upstream anchor) — flow shapes even the base.
- [ ] **141. Root voxel palette.** Dedicated pale-cream/tan root tones in the palette so roots never read as stems.
- [ ] **142. Crown rot risk.** Rosettes buried too deep (planted low) develop base browning unless replanted — punishes and teaches placement.
- [ ] **143. Runner severing.** Cutting/breaking a stolon (fish bite, player trim) makes the daughter independent — visible lineage separation moment.
- [ ] **144. Root glow in inspector.** Tap-a-plant x-rays its root extent as a faint overlay — reveal the hidden half.
- [ ] **145. Nutrient plume drawdown.** Substrate cells near hungry roots visibly deplete (debug layer) and recover — the invisible economy, inspectable.
- [ ] **146. Root anastomosis in clumps.** Same-lineage neighbors' root zones merge, sharing a nutrient pool — clonal colonies act as one organism.
- [ ] **147. Pull-up resistance minigame feel.** Uprooting an old plant lifts a substrate cloud + root ball voxels — weight and consequence.
- [ ] **148. Aerial root browning.** Water roots that end up above waterline (level drop) brown and stub off — the tank notices its own water level.
- [ ] **149. Root max from `max_roots` mutation.** Make `max_roots` mutable ±1 per generation — lineages drift toward anchor-heavy or light.
- [ ] **150. Bare-bottom adaptation.** On bare glass zones, only epiphytes and floaters thrive; rooted plants visibly fail to anchor — substrate matters absolutely.
- [ ] **151. Root fragment viability.** A severed root chunk of runner species has a small chance to sprout a new crown — weeds gonna weed.
- [ ] **152. Frost-heave analog.** Big temperature swings loosen anchors slightly (creaking substrate) — stability is earned by steady conditions.
- [ ] **153. Root depth vs dormancy survival.** Deeper-rooted individuals survive dormancy triggers better — selection pressure on an invisible trait made real.
- [ ] **154. Mycorrhiza flavor layer.** Old established substrate grants a small root efficiency aura that new substrate lacks — mature tanks feel mature.
- [ ] **155. Root-zone bubbles.** Healthy dense root zones occasionally release a substrate bubble — the floor breathes.
- [ ] **156. Washout event.** Strong flow across loose sand progressively exposes shallow roots until plants keel — a slow-motion hazard, visible early.
- [ ] **157. Replant recovery arc.** Any uproot+replant causes a droop-then-recover posture over two minutes — transplant shock, readable and forgiving.
- [ ] **158. Root palette dirtying.** Roots stain slightly toward substrate color over weeks — old roots belong to their ground.
- [ ] **159. Holdfast creep for epiphytes.** Epiphyte root pads extend one voxel across hardscape per day, slowly claiming the rock — patience rewarded.
- [ ] **160. Root systems smoke.** `scripts/smoke_root_anchor.gd`: assert anchor strength ordering (old>young), epiphyte pads only on hardscape, no roots in glass.

## Section 5 — Growth dynamics & tropisms (161–200)

*Grounding: `plant.gd` tick/`effective_rate`, etiolation/starch/`_light_avg`, PLANT_IMPROVEMENT_IDEAS Section 2.*

- [ ] **161. Growth in pulses, not creep.** Accumulate growth silently, then place 2–3 voxels in a brief visible spurt every ~30–60 s — plants "move" when you glance away and occasionally when you don't.
- [ ] **162. Dawn growth burst.** First 10 minutes after lights-on carries a growth multiplier — mornings are when the tank stretches.
- [ ] **163. Night rest.** Growth (not health) drops near zero in darkness; tips resume with a small unfurl at dawn — a day rhythm you can feel.
- [ ] **164. Phototropic tip curve.** The top 3 voxels of each stem lerp their offset toward the brightest direction hourly — crowns aim at the lamp.
- [ ] **165. Gravitropic recovery.** A plant knocked sideways re-verticalizes new growth within minutes while old stem stays bent — the classic J-curve of fallen stems.
- [ ] **166. Thigmotropism on contact.** Stems touching hardscape curve along the surface for a few voxels before growing away — plants negotiate rocks.
- [ ] **167. Growth ring memory.** Store per-voxel birth timestamp; debug view plays a plant's life as a color wave from base to tip.
- [ ] **168. Compensatory regrowth.** After heavy grazing, surviving meristems get a temporary rate boost — plants fight back like grass.
- [ ] **169. Determinate vs indeterminate flag.** Some species stop at genome height forever; others creep past `max_height` at 10% rate — hard caps read artificial.
- [ ] **170. Surface-tracking growth.** Stems reaching the waterline turn horizontal and run along the surface (real ambulia/cabomba behavior) instead of stopping.
- [ ] **171. Nutrient spike flush.** A fertilizer event triggers visible new-growth color at every tip within a minute — cause and effect at tank scale.
- [ ] **172. Growth rate inheritance noise.** `growth_rate` mutates ±8% per generation — some children are simply faster; you notice the strong ones.
- [ ] **173. Old-plant slowdown.** Rate decays gently past 80% of max size — plants asymptote instead of slamming into their cap.
- [ ] **174. Stress memory.** A badly stressed plant grows 20% slower for minutes after recovery — history matters briefly.
- [ ] **175. Light-flicker tolerance.** Average light over minutes for growth decisions so shadows of passing fish don't jitter the sim — calm beneath the dance.
- [ ] **176. Reaching behavior legibility.** Etiolated stems don't just stretch — they visibly *pale* + drop leaf density, the honest look of reaching.
- [ ] **177. Growth front glow.** Optional subtle emissive on voxels placed in the last 10 s — "watch it grow" mode for the patient observer.
- [ ] **178. CO₂ pearling threshold.** Photosynthesis surplus over threshold spawns tiny O₂ pearls on leaf tips that grow and detach — the planted-tank money shot. **(L)**
- [ ] **179. Pearling follows light field.** Pearls form first on the brightest leaves — the phenomenon maps the light for you.
- [ ] **180. Circadian leaf angle.** Leaves rise ~10° by midday and settle at night (nyctinasty) — the whole tank breathes on a day cycle.
- [ ] **181. Temperature growth window curve.** Replace linear temp factor with a proper asymmetric optimum curve per `temp_opt` — cold slows, heat *kills*, like life.
- [ ] **182. Drought analog (low water level).** Emersed growth above a dropping waterline wilts within minutes — the sim notices evaporation.
- [ ] **183. Growth spurt after trim.** Trimming a stem triggers the two nearest axil buds within 30 s — pruning visibly redirects energy.
- [ ] **184. Allelopathy zone legibility.** Plants inside a strong allelopath's radius show a faint yellow cast — chemical warfare made visible.
- [ ] **185. Starch reserve display.** Inspector shows the `_starch` reserve as a seed/tuber icon fill — the pantry as UI.
- [ ] **186. Age-staged max height.** `max_height` unlocks in stages (juvenile 40% → adult 100%) gated by total energy — no juvenile skyscrapers.
- [ ] **187. Downstream lean accumulation.** Constant current permanently biases growth a few degrees downstream — old tanks show their flow history in trunk angles.
- [ ] **188. Fast species, fragile leaves.** Couple high `growth_rate` to low `leaf_thickness` in defaults — speed vs durability as a real axis.
- [ ] **189. Recovery green wave.** When a sick plant recovers, color returns base-to-tip as a visible wave over a minute — healing is a moment.
- [ ] **190. Micro-sway during growth pulse.** Voxel placement adds a tiny 1 s shiver in the crown — growth has motion, not just addition.
- [ ] **191. Meristem count budget.** Total active tips capped by plant energy — big crowns trade tip count for tip speed, wild economics.
- [ ] **192. Growth anticipation lean.** Six seconds before a growth pulse, the tip leans 2° toward placement direction — telegraphing, like animation anticipation.
- [ ] **193. Shade-death honesty.** A fully overshadowed plant declines over many minutes with a legible sequence (pale → drop leaves → shrink), never a silent despawn.
- [ ] **194. Per-tip growth desync.** Multi-tip plants pulse tips independently — no plant-wide simultaneous pop.
- [ ] **195. Water-change surge.** Fresh water triggers a modest hours-long vigor bump — maintenance visibly pays.
- [ ] **196. Growth sound grain.** Optional near-silent creak/tick when a pulse places voxels close to camera — texture for headphone players.
- [ ] **197. Etiolation reversal arc.** Restored light doesn't fix stretched internodes — the plant top-fills with compact growth above them; history stays in the stem.
- [ ] **198. Rate inspector graph.** Tap-a-plant sparkline of `effective_rate` over the last 5 minutes — tuning tool and player education in one.
- [ ] **199. Sibling rivalry stat.** Track and expose which of two adjacent siblings is winning (growth delta) — players will name them and pick favorites.
- [ ] **200. Growth dynamics smoke.** `scripts/smoke_growth_wild.gd`: assert dawn burst > night rate, trim → axil release, pearling only above surplus threshold.

## Section 6 — Motion: current, eddies & the living sway (201–240)

*Grounding: `foliage.gdshader`, floaters' `surface_drift_vec`, ripple bursts in world.*

- [x] **201. Unified flow coupling.** One tank-wide flow field (base current + slow-varying eddies) that foliage sway, pads, floaters, fragments and pearls all sample — everything moves to the same water. **(L)** — `TankFlowField` + `sample_flow` already wired; fragments now sample it and tumble while drifting.
- [ ] **202. Gusting current.** Flow strength wanders on a ~20 s noise curve; the whole tank leans and relaxes together — wind through a meadow, underwater.
- [ ] **203. Sway amplitude by height.** Voxels sway proportionally to height above anchor — bases still, tips alive (verify the shader does this per-plant, not per-mesh).
- [ ] **204. Per-leaf phase from position.** Seed sway phase from world position so a wave of motion travels *across* the tank instead of everything ticking in sync.
- [ ] **205. Fish wake bending.** A fish passing within 2 voxels bends nearby foliage away for a second with spring-back — the water is one medium.
- [ ] **206. Flow shadow behind hardscape.** Plants downstream of rocks sway less — calm pockets read as real hydrodynamics and become visible "sheltered spots".
- [ ] **207. Stiffness by age.** Older stem sections sway with lower amplitude/frequency than green tips — one plant, a spectrum of stiffness.
- [ ] **208. Strap-leaf traveling wave.** Long vallisneria-type leaves carry a slow sine traveling base-to-tip instead of rigid-body sway — the single most hypnotic aquatic plant motion.
- [ ] **209. Moss breathing.** Moss clump surfaces undulate at very low amplitude/frequency — velvet in a breeze, never thrash.
- [ ] **210. Filter outflow jet.** A localized strong-flow cone near the filter where plants permanently stream sideways — placement gameplay from motion alone.
- [ ] **211. Sway settle after disturbance.** All disturbance responses (ripple, fish, trim) decay with damped-spring physics, never linear lerp — nothing stops abruptly.
- [ ] **212. Counter-phase understory.** Deep plants sway slightly out of phase with canopy above (flow lag with depth) — vertical parallax of motion.
- [ ] **213. Emersed stillness.** Leaf voxels above the waterline stop water-sway and pick up a rare tiny air tremble — crossing the surface changes physics.
- [ ] **214. Fragment tumble.** Drifting cut stems rotate slowly end-over-end following the flow field, catching on hardscape realistically.
- [ ] **215. Root tress swirl.** Floating-plant root bundles swirl and part in flow like hair — the tenderest motion in the tank.
- [ ] **216. Pad nudge chains.** One bumped lily pad nudges its raft neighbors with decaying momentum — surface billiards at 1% speed.
- [ ] **217. Sway amplitude trait honesty.** `sway_amplitude` mutates; stiff sports and floppy sports appear in lineages — motion itself is heritable.
- [ ] **218. Turbulence at the outflow surface.** Surface chop zone where floater rafts jostle visibly — quiet corners vs busy corners.
- [ ] **219. Thermal micro-lift.** Above the heater, a faint rising flow column that lifts leaf tips a degree or two — find the heater by watching plants.
- [ ] **220. Storm mode hook.** A rare high-flow minute (pump surge event) where the whole meadow streams one way — cinematic, and it prunes weak branches (#26).
- [ ] **221. Bushy-tip flutter.** Fine-leaved species (cabomba class) get higher-frequency lower-amplitude flutter than broadleaf — texture through motion frequency.
- [ ] **222. Motion LOD fairness.** Distant plants keep phase-correct sway at lower rate — no dead background, no popping when camera approaches.
- [ ] **223. Snail-crawl jiggle.** A snail crossing a leaf makes it dip under the weight, crawling a moving depression along the blade.
- [ ] **224. New-voxel floppiness.** Voxels placed in the last minute sway with doubled amplitude before stiffening — new growth is visibly tender.
- [ ] **225. Anchored vs loose contrast.** A partially uprooted plant sways from the root ball, whole-body — wrongness you can spot across the tank.
- [ ] **226. Current direction drift.** Base current direction slowly wanders ±20° over hours — no permanent metronome axis.
- [ ] **227. Two-band eddy spectrum.** Sum a ~7 s and a ~40 s eddy period so motion never resolves into a repeating loop the eye can catch.
- [ ] **228. Sway-to-shed coupling.** Senescent leaves detach preferentially during gusts — things fall when the wind blows, not on timers.
- [ ] **229. Bubble path bending.** Pearls and substrate bubbles follow the flow field on their way up, wobbling believably instead of rising straight.
- [ ] **230. Touch response.** Player tap/drag through foliage parts it with a spring wake — direct communion with the meadow.
- [ ] **231. Cattail surface pivot.** Emergent cattail stems pivot at the waterline (still below, breeze above) — the airline is a hinge, opposite of submerged plants.
- [ ] **232. Motion accessibility toggle.** Global sway scale slider (0.25–1.5×) for motion sensitivity and taste — naturalism includes comfort.
- [ ] **233. Sleeping motion.** At night, base current halves and eddies slow — the tank audibly-visibly rests; dawn brings motion back with the light.
- [ ] **234. Flow field debug view.** Dev overlay drawing the current + eddy vectors over the tank — tuning tool for every item above.
- [ ] **235. Leaf collision damping.** Overlapping neighbor leaves damp each other's sway slightly where they touch — dense clumps move as heavier masses.
- [ ] **236. Anchor creak events.** Big gusts on big plants trigger a one-frame root-zone substrate puff — strain made visible at the base.
- [ ] **237. Whip recovery overshoot.** After a strong bend, tips overshoot vertical once before settling — real elasticity, one extra half-cycle.
- [ ] **238. Raft rotation memory.** Floater rafts acquire slow net rotation from asymmetric flow — check back in an hour, the raft has turned.
- [ ] **239. Sway phase continuity on regrow.** Regrown leaf inherits its predecessor's phase slot — no popping discontinuity where a leaf was replaced.
- [ ] **240. Motion smoke.** `scripts/smoke_flow_field.gd`: assert flow field continuity, flow-shadow attenuation behind hardscape, and emersed voxels excluded from water sway.

## Section 7 — Aging, senescence & beautiful decay (241–280)

*Grounding: health lerp in `plant.gd` tick, melt susceptibility, detritus hooks.*

- [ ] **241. Plant age stages.** SEEDLING → JUVENILE → PRIME → MATURE → DECLINING lifecycle enum with per-stage growth/repro/color modifiers — every plant is somewhere in a life.
- [ ] **242. Graceful species lifespan.** Genome `lifespan` (some effectively immortal clonal, some 2-hour ephemerals) — turnover is the engine of a wild look.
- [ ] **243. Declining crown thinning.** DECLINING plants shed leaves faster than they bud — silhouettes thin from the inside out over minutes.
- [ ] **244. Standing dead stems.** Dead stem plants persist as brown skeletons for minutes before collapsing voxel by voxel — death has a body, not a despawn.
- [ ] **245. Collapse physics.** Final collapse tips the skeleton over slowly, breaking into fragments where it lands — deadfall becomes litter becomes soil.
- [ ] **246. Melt done beautifully.** Crypt-melt (`melt_susceptibility`) dissolves leaves from the edges inward with translucency — devastating and gorgeous, then the crown resprouts.
- [ ] **247. Post-melt resprout promise.** Melted crowns keep a green center voxel pulsing faintly — the player knows to wait, like a real crypt.
- [ ] **248. Yellow flag leaf.** Each plant's single oldest leaf is always the yellowest — a moving marker of turnover you can track.
- [ ] **249. Senescence under stress accelerates oldest-first.** Stress never greys the whole plant uniformly — it eats the old leaves first, exactly like nutrient reallocation.
- [ ] **250. Death from darkness sequence.** Shade-killed plants: pale → stretch → drop leaves → topple, over many minutes — every death tells its cause.
- [ ] **251. Heat death sequence.** Cooked plants brown from the tips down with edge curl — distinct from shade death; players learn to autopsy.
- [ ] **252. Nutrient death sequence.** Starved plants translucent-yellow from old leaves up, veins last — third distinct autopsy signature.
- [ ] **253. Half-dead survivors.** A plant can lose one whole side and live lopsided for its remaining life — the veteran look, scars permanent.
- [ ] **254. Decay hosts life.** Decaying leaf voxels host visible infusoria specks that fry fish nibble — death immediately feeds the food web.
- [ ] **255. Brown-edge ring on old rosettes.** Old rosette outer leaves brown from the tip inward while center stays vital — target-ring of age, like real echinodorus.
- [ ] **256. Detached-leaf drift beauty.** Shed leaves flutter down with per-leaf tumble seeds, occasionally catching an eddy back upward once — the falling-leaf moment, underwater.
- [ ] **257. Skeleton leaf rarity.** Rarely a dying leaf decays to a translucent vein lattice for a minute before dissolving — macro-photo beauty as a random event.
- [ ] **258. Age-appropriate repro.** SEEDLING/JUVENILE can't reproduce; DECLINING plants get a last-gasp seed/fragment burst — life histories, not flat probability.
- [ ] **259. Monocarpic finale.** `monocarpic` species die *magnificently* after flowering — bloom, mass seed release, gold-out, collapse, in one visible arc.
- [ ] **260. Perennial crown persistence.** Dormancy-capable species retreat to crown/tuber instead of dying under seasonal triggers — leave brown, return green.
- [ ] **261. Litter half-life by leaf thickness.** Thick leaves persist as litter longer than thin ones — the floor's texture reflects the community above.
- [ ] **262. Old-plant sway dignity.** MATURE+ plants sway slower regardless of size (#207 tie-in) — age reads in motion at a glance.
- [ ] **263. Nurse log behavior.** Collapsed dead stems become spawn-priority sites for moss and epiphyte fragments — decay drives the next generation's geography.
- [ ] **264. Terminal bloom color.** DECLINING plants that flower do so slightly duller — even beauty ages.
- [ ] **265. Death notification restraint.** No popup on plant death — the tank tells you through the skeleton; the log records it quietly for those who check.
- [ ] **266. Age in the inspector.** Tap-a-plant shows age, stage, and expected span — mortality as ambient information.
- [ ] **267. Necrosis spot spread.** Local damage can seed a slow-spreading brown patch that healthy plants wall off (dark ring) and weak ones don't — infection dynamics in two tones.
- [ ] **268. Winter-brown survivors.** Cold-stressed-but-alive plants hold a bronze cast until warmth returns — chronic stress as a palette, not a bar.
- [ ] **269. Ephemeral species class.** A ditch-weed archetype: sprout, race, seed, die within a session — chaos ribbon through the stable tank.
- [ ] **270. Old moss browning core.** Moss clumps brown at the center as they thicken, staying green at the growing rim — real moss ball behavior.
- [ ] **271. Shed synchrony under shock.** A sudden parameter shock (big water change gone wrong) triggers coordinated leaf drop across sensitive species — dramatic, legible, recoverable.
- [ ] **272. Corpse nutrient pulse.** A decayed plant measurably enriches its substrate cell — die where your children will feed.
- [ ] **273. Fragment senescence.** Unrooted drifting fragments slowly pale and die after minutes if they never anchor — propagation pressure with a clock.
- [ ] **274. Lifespan mutation.** `lifespan` drifts ±10% per generation — lineages slide toward annual or perennial strategies over play-hours.
- [ ] **275. Beautiful algae takeover of the dead.** Dead standing stems green over with algae film before collapse — even the skeleton gets reclaimed.
- [ ] **276. Death sound.** A single soft low tick when a plant finally collapses near camera — punctuation, not alarm.
- [ ] **277. Memorial stumps.** Rosette deaths leave a 1-voxel crown stump for an hour — places where plants were remain places for a while.
- [ ] **278. Population age histogram.** Debug/inspector chart of tank age structure — a wild tank shows a pyramid, a dying tank shows a spike; instant ecosystem read.
- [ ] **279. Season of a leaf timelapse.** Photo-mode option: record one leaf bud-to-shed as an onion-skinned strip — the lifecycle as art.
- [ ] **280. Senescence smoke.** `scripts/smoke_senescence.gd`: fast-tick assert stage transitions, distinct death sequences by cause, skeleton→fragment→litter chain intact.

## Section 8 — Color, pigment & light response (281–320)

*Grounding: `red_potential`, `variegation`, `iridescence`, `underside_tone` in genome; palette rules in `style-guide/`.*

- [ ] **281. Pigment response layer.** A shared per-plant pigment state (chlorophyll, anthocyanin, carotenoid proxies) updated from light/stress/age, feeding every color decision — one system, all species. **(L)**
- [ ] **282. Red under high light.** `red_potential` expresses proportionally to accumulated light: tops of tall reds blush first — the aquascaper's sun-tan, earned not painted.
- [ ] **283. Red under nitrogen leanness.** Low-N water pushes reds deeper (real ludwigia trick) — pro players can *drive* color chemically.
- [ ] **284. Green-up in shade.** Shaded parts of a red plant revert green — one plant showing its own light gradient in two hues.
- [ ] **285. Variegation as sectors.** `variegation` renders as coherent cream sectors/stripes per leaf (seeded per leaf), not noise — real chimera geometry.
- [ ] **286. Variegation instability.** Variegated lineages occasionally throw an all-green reverted shoot that grows faster — cull it or lose the pattern; a real variegata keeper's dilemma.
- [ ] **287. Iridescence at grazing angles.** `iridescence` shows only at glancing camera angles as a blue sheen sweep — found beauty, not constant bling.
- [ ] **288. Depth color honesty.** Deeper foliage shifts subtly blue-green from water column filtering — free depth cue, one shader term.
- [ ] **289. Morning gold hour.** Lights-on ramp tints the tank warm for two minutes; plant greens glow amber-edged — a daily ritual worth watching.
- [ ] **290. Pigment lag.** Color changes trail conditions by minutes (pigments are chemistry, not switches) — moving a plant leaves it wearing its old home's colors briefly.
- [ ] **291. Anthocyanin stress flush.** Sudden cold or intense light briefly purples sensitive tips within a minute — fast stress signal before growth even reacts.
- [ ] **292. Carotenoid autumn reveal.** Senescing leaves don't "turn" yellow — green *drains*, revealing underlying yellow — the real mechanism, and it looks better.
- [ ] **293. Per-lineage hue identity.** Each lineage carries a tiny heritable hue offset (±4°) — with generations, one species becomes a family of tints across the tank.
- [ ] **294. Olive-to-emerald health axis.** Health expresses as saturation, not value — sick plants go olive/grey-green, never cartoon-brown-instantly.
- [ ] **295. Newest-leaf gradient anchor.** The color gradient along a stem always anchors brightest at the newest node — growth direction readable in pure color.
- [ ] **296. Red intensity inheritance.** `red_potential` mutates ±0.05; selective keeping of the reddest children is a whole meta-game with zero new UI.
- [ ] **297. Pink lineage jackpot.** Ultra-rare mutation: red + high variegation = pink-white tips (real "pink" cultivar mechanics) — the rarest natural pull.
- [ ] **298. Underside flash tuning.** Ensure `underside_tone` contrast is strongest on large paddle leaves and during gusts (#202) — choreograph the flash.
- [ ] **299. Golden-form mutation.** Rare low-chlorophyll gold morph: gorgeous, but 30% slower growth — beauty with a biological price tag.
- [ ] **300. Palette guard.** All pigment math quantizes through the established palette (`style-guide/`) — naturalism must never break the pixel-art contract. 
- [ ] **301. Bronze juvenile pass.** Young leaves of `red_potential` species open bronze (#78 tie-in) even when the adult expresses green — age gradient in a second hue.
- [ ] **302. Chlorosis maps deficiency.** Yellowing pattern differs by cause: old-leaf-first (N), new-leaf-first (Fe), edge-first (K) — three deficiencies, three legible patterns.
- [ ] **303. Light-spectrum response.** Warmer lamp settings favor red expression; cooler favor lush green — the light menu becomes an artistic instrument.
- [ ] **304. Iridescence heritability.** `iridescence` mutates up rarely; a naturally-arisen high-sheen clone is a keepable treasure.
- [ ] **305. Color at distance composure.** Verify pigment variation survives palette quantization at far zoom — micro-variation must sum to richness, not noise.
- [ ] **306. Nighttime desaturation.** Moonlight mode renders plants in believable blue-grey scotopic tones — night looks like *night*, not dimmed day.
- [ ] **307. Red canopy shadow play.** Red canopies cast warmer-tinted shade on plants below (one cheap term) — color interacts vertically.
- [ ] **308. Algae-tint honesty.** Leaves under algae film shift toward the algae's hue rather than darkening — occlusion with character.
- [ ] **309. Season tint drift.** If seasons ship (Section 19), the whole community's base hue drifts a few degrees across the cycle — the year has a palette.
- [ ] **310. Stress bleach event.** Severe light shock white-bleaches exposed tips within a minute (recoverable) — overexposure as a visible sunburn.
- [ ] **311. Color inspector swatch.** Tap-a-plant shows its current pigment mix as three small bars — the chemistry of its beauty, quantified.
- [ ] **312. Complementary bloom color.** Flower hue defaults near-complementary to the lineage's leaf hue — blooms pop *because of* genetics, not despite.
- [ ] **313. Melanistic sport.** Ultra-rare near-black foliage mutation (max anthocyanin) — the goth plant; grows slow, photographs incredible.
- [ ] **314. Wet-sheen on emersed leaves.** Above-water leaves carry a specular sheen absent underwater — crossing the surface changes material, not just motion.
- [ ] **315. Color memory in fragments.** Cuttings keep the parent's expressed pigment for their first minutes, then adapt to their new spot — you can see where a cutting came from.
- [ ] **316. Tannin water interplay.** In tannin-stained water, all plant color warms and darkens — blackwater tanks get their moody look automatically.
- [ ] **317. UV-viewing mode toy.** Photo-mode filter approximating how fish see the plants (shifted hues) — perspective empathy as a feature.
- [ ] **318. Dither-aware gradients.** Long color gradients along stems use the style guide's dither patterns — smoothness within pixel-art law.
- [ ] **319. Two-tone moss tips.** Moss growth tips render one palette step lighter than the body — the classic fresh-moss glow, one rule.
- [ ] **320. Pigment smoke.** `scripts/smoke_pigment.gd`: assert red expression follows light, chlorosis patterns match deficiency causes, palette quantization holds.

## Section 9 — Damage, herbivory & repair (321–360)

*Grounding: `palatability` in genome, fish nibble hooks, `plant_fragment.gd`.*

- [ ] **321. Bite mechanics by mouth size.** Small fish take 1-voxel edge nips; big grazers take 2–3-voxel arcs — damage shape identifies the culprit.
- [ ] **322. Palatability-driven salad bar.** Fish visibly prefer high-`palatability` species and only eat tough ones when hungry — grazing pressure sculpts the community composition.
- [ ] **323. Fresh wound tone.** New bite edges show a pale wound color for a minute before browning — you can tell fresh grazing from old.
- [ ] **324. Wound sealing.** Browned bite edges stabilize (callus) and stop spreading in healthy plants — damage is contained, not fatal by default.
- [ ] **325. Snail rasp trails.** Snails leave meandering 1-voxel-wide translucent grazing trails on broad leaves — the tank writes calligraphy.
- [ ] **326. Grazing halo around fish homes.** Territory centers accumulate a grazed-down zone — fish behavior mapped in plant biomass.
- [ ] **327. Induced defense.** Repeatedly grazed plants drop palatability temporarily (bitterness response) and fish move on — plants fight back invisibly, herds rotate naturally.
- [ ] **328. Chemical alarm to neighbors.** Heavy grazing slightly raises defense in same-species neighbors for minutes — the wood-wide-web, tank edition.
- [ ] **329. Uproot by digger.** Digging cichlid-type fish can uproot young plants entirely (fragment + substrate cloud) — natural enemies of the freshly planted.
- [ ] **330. Torn-leaf streamers.** Partially torn strap leaves trail their distal half at an angle, still swaying — damage that's beautiful in motion.
- [ ] **331. Regrowth from stump.** Any stem cut above one live node regrows within minutes with a visible fork (#9 tie-in) — the trim-and-recover loop that planted tanks live on.
- [ ] **332. Fragment from bite.** Big bites on stem plants can sever the top, launching a viable drifting cutting — grazing literally propagates the meadow.
- [ ] **333. Trample paths.** Bottom-dwellers' habitual routes keep carpet height mowed along their lanes — desire paths through the foreground lawn.
- [ ] **334. Leaf-rolling shelter damage.** Shrimp/fry hiding inside curled damaged leaves — damage creates microhabitat and gets *used*.
- [ ] **335. Selective tip-grazing stunts height.** Fish that nip tips keep a species bushy-short in their range — the grazer as unpaid aquascaper.
- [ ] **336. Damage-triggered pigment.** Wound margins flush anthocyanin red in high-`red_potential` lineages — even injury is on-palette.
- [ ] **337. Overgrazing collapse.** A plant below 30% leaves enters emergency: drops palatability hard, spends starch, and either recovers visibly or dies honestly.
- [ ] **338. Herbivore satiation.** Grazing pressure scales with fish hunger, so feeding the fish *visibly* spares the plants — systems touching systems.
- [ ] **339. Tough-species refuge.** Low-palatability plants become fry cover in heavily grazed tanks — grazing pressure shifts which plants shelter life.
- [ ] **340. Bite sounds.** Tiny plink when a nibble lands near camera; grazing becomes ambient percussion.
- [ ] **341. Mechanical damage from hardscape.** Leaves chronically slapping rock in strong flow abrade at the contact point — placement mistakes show up as honest wear.
- [ ] **342. Repair prioritization.** Plants heal youngest damage first and abandon old wounds — repair budget with visible triage.
- [ ] **343. Crush damage under dropped hardscape.** Player-moved rocks crush plants beneath (flatten + fragment) — consequence for careless landscaping.
- [ ] **344. Epiphyte tear-off.** Strong current can peel a weakly-attached epiphyte off its rock, sending it drifting to re-attach elsewhere — even accidents relocate life.
- [ ] **345. Grazer dental record.** Inspector on a damaged leaf names the likely species from bite pattern — forensics as flavor text.
- [ ] **346. Palatability mutation.** `palatability` drifts per generation; heavily-grazed tanks *select* for tougher lineages over hours — evolution by your own fish, observable.
- [ ] **347. Sacrificial outer leaves.** Rosettes route grazers to outer leaves by keeping them more palatable than the crown — the plant's own defensive architecture.
- [ ] **348. Wound infection chance.** Untended wounds in poor water can seed necrosis (#267) — water quality decides whether bites matter.
- [ ] **349. Herbivory pressure dial.** Scenario-level grazing intensity setting — from display-tank pristine to wild-pond chewed.
- [ ] **350. Shed-on-damage threshold.** A leaf over 60% damaged is shed proactively — plants cut their losses; litter records the battle.
- [ ] **351. Fragment nibbling.** Fish also nibble drifting cuttings — propagation runs the same gauntlet everything else does.
- [ ] **352. Regrown-leaf mismatch.** Replacement leaves grow one size smaller with slightly different tone — a healed plant is a readable patchwork, like a lizard's regrown tail.
- [ ] **353. Root grazing stunt.** Persistent root grazing (#139) slows the whole plant subtly — hidden damage with visible consequence.
- [ ] **354. Damage-driven allelopathy spike.** Injured allelopathic species briefly widen their suppression radius — wounds make them meaner.
- [ ] **355. Community grazing succession.** Sustained heavy grazing shifts the tank toward tough/low species over an hour — a visible alternate stable state, reversible by feeding.
- [ ] **356. Bite-hole aging.** Holes brown-ring at the margin over minutes then stabilize — every hole has an age you can estimate.
- [ ] **357. Player trim tool honesty.** Player trims use the same wound/regrow pipeline as bites — one system, no special cases.
- [ ] **358. Anti-fragile moss.** Moss grazing *spreads* it — nibbles detach viable micro-fragments that seed nearby (real-tank moss chaos as a feature).
- [ ] **359. Damage history overlay.** Debug view heat-mapping accumulated damage locations across the tank — where the herd feeds, at a glance.
- [ ] **360. Herbivory smoke.** `scripts/smoke_grazing.gd`: assert palatability preference ordering, stump regrowth, bite-severed fragments remain viable.

## Section 10 — Mutation & heredity (361–400)

*Grounding: genome `enrich()/to_dict()/from_dict()`, `generation`, `parent_lineage`, `asymmetry_seed`.*

- [x] **361. Mutation-on-propagation pipeline.** A single `PlantGenome.mutate(rng, mode)` applied at every reproduction event, with per-trait sigma table and mode-dependent strength — the one gate all variation flows through. **(L)** — `PlantGenome.mutate(mode)`; seed/spore full sigma, fragment/plantlet/bulbil ×0.15; `spawn_seedling` + fragment rooting wired.
- [ ] **362. Sexual vs clonal variance.** Seeds/spores mutate at full sigma; fragments/runners/plantlets at ~15% — clones conserve, seeds explore; both visible over generations.
- [ ] **363. Per-trait sigma table.** Continuous traits get tuned sigmas (color drifts fast, `max_height` slow, phyllotaxis class almost never) — evolution has texture, not uniform noise.
- [ ] **364. Trait clamping with soft walls.** Mutations approach trait bounds asymptotically rather than clipping — no lineage slams into a wall and stays pinned.
- [ ] **365. Rare macro-mutations.** ~0.5% of seeds roll one *category* change (leaf form swap, phyllotaxis change, fenestration #72, fasciation #22) — the gasp moments.
- [ ] **366. Two-parent seeds.** When two flowering conspecifics are close, seeds blend parents' traits (per-trait pick + noise) — cross-pollination makes proximity matter.
- [ ] **367. Selfing fallback.** A lone flowering plant selfs with reduced seed count and slightly higher mutation — isolation has consequences and possibilities.
- [ ] **368. Hybridization near-species.** Same-genus species can rarely hybridize into an intermediate genome flagged `hybrid` — the forbidden cross, occasionally spectacular.
- [ ] **369. Hybrid vigor.** First-gen hybrids get +10% growth rate — the biology bonus that makes players *try* for crosses.
- [ ] **370. Hybrid sterility roll.** Some hybrids can only propagate clonally — beautiful dead-ends you must keep alive by cutting, like real cultivars.
- [ ] **371. Inbreeding depression.** Lineages selfing for many generations accumulate a small vigor penalty until outcrossed — genetic hygiene as gentle pressure.
- [ ] **372. Mutation events are announced by the plant.** No popup: a macro-mutant seedling simply *looks different from its first leaves* — discovery through observation.
- [ ] **373. Asymmetry seed inheritance.** Children derive `asymmetry_seed` from parent's (hashed) — family resemblance in the *irregularities*, siblings similar-but-not-same.
- [ ] **374. Trait correlation matrix.** Mutations respect biological couplings (fast growth ↔ thin leaves #188; red ↔ light demand) — no free lunches in the genome.
- [ ] **375. Environmental mutagenesis.** Chronic stress slightly raises mutation rate in that plant's offspring — hard times breed variety, as in life.
- [ ] **376. Founder effect on new tanks.** Importing one cutting to a fresh tank forks its lineage genetically forever — every tank becomes an island population.
- [ ] **377. Genetic drift in small populations.** Under ~5 individuals, per-generation drift doubles — small colonies wander, big meadows stabilize; population size is a slider on evolution.
- [ ] **378. Beneficial mutation table.** A small pool of strictly-positive rare rolls (+temp tolerance, +shade tolerance, +anchor grip) — evolution occasionally hands you a gift lineage.
- [ ] **379. Deleterious mutation load.** Equally rare negative rolls (brittle stems, pale pigment) that persist in the line — culling decisions with feelings attached.
- [ ] **380. Atavism.** Rare reversion of a derived trait to the species ancestral value — grandma's leaf shape reappearing two generations later.
- [ ] **381. Somatic mutation on one branch.** Ultra-rare: a single branch of an old plant mutates (bud sport) — take a cutting of *that branch* to found the new line, exactly like real horticulture. **(L)**
- [ ] **382. Mutation log.** Quiet journal recording every macro-mutation and hybrid with timestamp and parentage — the tank's natural history, self-writing.
- [ ] **383. Genome diff viewer.** Inspector compares any plant against its species baseline — see exactly what your lineage has become.
- [ ] **384. Seed batch variance display.** A seed cluster shows subtle per-seed size/tone differences hinting at their rolled genomes — variation visible before germination.
- [ ] **385. Grandparent memory.** Store two generations of `parent_keys` — pedigree charts become possible from data already flowing.
- [ ] **386. Convergent evolution watch.** Two independent lineages mutating toward the same trait combo get a log note — the sim notices its own stories.
- [ ] **387. Mutation rate as species trait.** Some species are genomically volatile (hygro-like), others frozen (anubias-like) — choose your chaos when stocking.
- [ ] **388. Epigenetic priming.** Offspring get a small head start in the *parent's* stress condition (temp-hardened parents → temp-tolerant-ish seedlings, fading after one generation) — soft inheritance, honestly temporary.
- [ ] **389. Polyploidy jackpot.** Ultra-rare whole-plant scale-up mutation: +30% leaf size, −15% growth rate, thicker everything — the giant form, instantly recognizable.
- [ ] **390. Dwarfism jackpot.** The opposite roll: 60% scale, compact internodes — the bonsai form; both breed true.
- [ ] **391. Mutable sway.** `sway_amplitude` in the sigma table (#217 tie-in) — even how a lineage *dances* evolves.
- [ ] **392. Trait heatmap over tank.** Debug overlay coloring all plants by any chosen trait value — watch selection gradients form across light zones in real time.
- [ ] **393. Seed bank genetics.** Dormant seeds in substrate (Section 11) preserve old genomes; disturbing old substrate resurrects past generations — the tank remembers what it used to grow.
- [ ] **394. Mutation preview honesty.** No UI ever predicts a child's traits — you learn lineages by growing them; the sim keeps its secrets like nature does.
- [ ] **395. Named mutation moments.** When a macro-mutation expresses, the journal suggests a strain name (editable) — "walstad loom, cv. 'First Light'".
- [ ] **396. Genetics sandbox scenario.** A scenario preset with boosted mutation rates for players who want fast-forward evolution — the lab tank.
- [ ] **397. Cross-tank pollen event.** Rare: a flowering plant sets one seed carrying a random *other* save-file lineage's genome fragment (local only, no network) — mysterious gifts from your own past tanks.
- [ ] **398. Fitness is emergent only.** No fitness number anywhere — selection happens through the actual sim (light, grazing, competition); the genome system stays purely descriptive.
- [ ] **399. Deterministic replay of lineages.** Genome + seed fully determine a plant's development — same cutting, same conditions, same plant; determinism keeps mutation honest and debuggable.
- [ ] **400. Heredity smoke.** `scripts/smoke_genome_mutation.gd`: assert clone sigma < seed sigma, trait bounds respected, two-parent blends within parental ranges, `from_dict(to_dict())` round-trips mutants.

## Section 11 — Seeds, spores & dispersal (401–440)

*Grounding: `REPRO_SEED`/`REPRO_SPORE` in genome, world spawn hooks.*

- [ ] **401. Seed objects in the world.** Seeds are tiny visible voxel motes that drop, drift, settle, and *persist* — reproduction happens in space, not in code.
- [ ] **402. Buoyant vs sinking seeds.** Genome flag: sinkers drop near the parent; floaters ride the surface current and beach far away — two dispersal maps from one bit.
- [ ] **403. Germination conditions.** Seeds sprout only when their landing cell has light + substrate contact — most seeds die, exactly like the wild; the survivors feel earned.
- [ ] **404. Substrate seed bank.** Unsprouted viable seeds persist buried for tank-hours; disturbance (digging, uprooting) brings them up to germinate — weeding never quite ends. **(L)**
- [ ] **405. Seed rain visual.** A seeding plant releases motes over a minute in pulses synced to gusts (#202) — dispersal as weather.
- [ ] **406. Spore clouds.** `REPRO_SPORE` species (moss/fern class) puff faint spore mist instead of motes; spores settle on *hardscape* preferentially — different physics, different geography.
- [ ] **407. Fish-vector dispersal.** Seeds brushing a fish stick briefly and drop off wherever it swims — zoochory; your fish plant your tank.
- [ ] **408. Snail-vector spores.** Snails crossing sporulating moss carry spores in their trail — the slowest gardener.
- [ ] **409. Germination flush after disturbance.** Uprooting a big plant triggers nearby seed-bank germination within minutes (light gap + disturbance) — gap dynamics, the forest edition.
- [ ] **410. Seed predation.** Fish and shrimp eat exposed seeds off the substrate — dispersal runs a survival gauntlet; buried beats eaten.
- [ ] **411. Dormancy depth.** Seeds carry a dormancy timer (some sprout at once, some wait hours) — one seeding event echoes across a whole session.
- [ ] **412. Cold-stratification analog.** Some species' seeds require a temperature dip before germinating — heaters accidentally suppress them; discovery through chemistry.
- [ ] **413. Seedling thinning.** Dense germination patches self-thin (strongest survives, neighbors yellow out) over minutes — natural spacing without placement rules.
- [ ] **414. Distance-from-parent survival curve.** Seedlings too close to the parent get shaded/allelopathy-suppressed — the Janzen-Connell donut; recruitment rings around mothers.
- [ ] **415. Seed size tradeoff.** Genome `seed_size`: few big seeds (strong seedlings) vs many small (lottery tickets) — r/K strategy visible in the mote sizes.
- [ ] **416. Waterline strand line.** Floating seeds beach in a visible line along the glass at surface height — the tank draws its own high-water mark in future plants.
- [ ] **417. Explosive dehiscence.** One rare species flings seeds ballistically a few voxels with a tiny pop — the touch-me-not moment.
- [ ] **418. Seeds in filter intake.** Some floaters' seeds collect at the filter — cleaning the intake scatters them; maintenance is dispersal.
- [ ] **419. Germination micro-animation.** Sprouting: seed coat splits, radicle down, cotyledon loop up over ~15 s (#69 tie-in) — the oldest show on earth, in voxels.
- [ ] **420. Sporeling protonema stage.** Moss spores grow a faint green fuzz film before leafy shoots — hardscape "greening up" precedes moss, like real tanks.
- [ ] **421. Seed viability from parent health.** Stressed parents shed fewer/weaker seeds — reproduction budgets flow from actual vigor.
- [ ] **422. Mast seeding.** Clonal groups occasionally sync a heavy seed year (tank-hours cadence) then rest — pulse-and-famine, the oak strategy.
- [ ] **423. Seed float duration trait.** How long a floating seed rides before waterlogging and sinking — mutable; lineages evolve their dispersal range.
- [ ] **424. Glass-corner nurseries.** Low-flow corners accumulate floating seeds into germination rafts — the tank develops natural nursery zones.
- [ ] **425. Seed inspector.** Tap a settled seed: species, parent, viability, dormancy remaining — the future, inspectable.
- [ ] **426. Carpet gap seeding.** Carpet species preferentially germinate in their own carpet's gaps — lawns self-repair through seed, not just runners.
- [ ] **427. Epiphyte seed niche.** Epiphyte seeds only germinate on hardscape ledges where detritus has settled — pockets of litter become plantable real estate.
- [ ] **428. Season-gated germination.** With seasons (Section 19), most germination clusters in "spring" — the tank gets a visible cohort rhythm.
- [ ] **429. Seed coat colors.** Species-distinct mote tints so a mixed seed rain is readable to the trained eye.
- [ ] **430. Failed sprout melt.** Seeds that germinate in bad spots produce a 3-voxel seedling that visibly fails — small tragedies that make survivors matter.
- [ ] **431. Bulbil drops.** `REPRO_BULBIL` species drop pre-formed plantlets that skip the seedling stage but inherit clonally — the shortcut strategy, visible as chunky motes.
- [ ] **432. Seed count economy.** Seed production draws real starch (#185) — a heavy seed year visibly slows the parent's growth; nothing is free.
- [ ] **433. Cross-tank seed import.** Player can collect seeds into inventory and sow them in another tank — lineages travel by hand, founder effects included (#376).
- [ ] **434. Ancient seed event.** Ultra-rare: disturbing old substrate wakes a seed from a species not currently in the tank (from the seed bank's history) — resurrection ecology.
- [ ] **435. Seed rain sound.** Soft granular patter when heavy seeding happens near camera — the quietest weather.
- [ ] **436. Dispersal debug arcs.** Dev overlay tracing each seed's path from parent to rest — tune dispersal kernels visually.
- [ ] **437. Recruitment heatmap.** Debug layer showing where germination succeeds over time — the tank's own suitability map, emergent.
- [ ] **438. Sterile showpiece flag.** Scenario option: disable seeding for players who want a fixed aquascape — naturalism with an off switch.
- [ ] **439. First-seed achievement moment.** The first successful wild-set seedling in a tank gets a journal entry — the moment a garden becomes an ecosystem.
- [ ] **440. Dispersal smoke.** `scripts/smoke_seed_dispersal.gd`: assert floaters travel farther than sinkers, germination requires light+substrate, seed bank survives save/load.

## Section 12 — Lineage identity, naming & the living collection (441–480)

*Grounding: `generation`, `parent_lineage`, `parent_keys`, `species_id`, `plant_name` in genome.*

- [x] **441. Lineage bookkeeping service.** Central registry: every genome registers lineage id, generation, parentage, birth time; drift distance from species baseline computed on demand — the memory that makes evolution *matter*. **(L)** — `PlantLineageRegistry` on `World`; `PlantGenome.drift_distance`; plants register on `init`.
- [ ] **442. Generation counter surfacing.** Inspector shows "Gen 7" with parent chain — depth of a lineage as a stat players brag about.
- [ ] **443. Drift distance metric.** Scalar "wildness" = normalized genome distance from baseline — watch a lineage walk away from its species over hours.
- [ ] **444. Strain naming rights.** Any lineage past drift threshold can be named by the player; name propagates to all descendants — "Jo's Crimson" in every future inspector.
- [ ] **445. Family tree view.** Pedigree graph from `parent_keys` (#385) rendered as a simple tree — three generations of your tank's history in one screen. **(L)**
- [ ] **446. Founders honored.** Original stock plants tagged "Founder" (already `parent_lineage: "Founders"`) — the ancestors, findable forever.
- [ ] **447. Lineage extinction notice.** When the last plant of a named lineage dies, one quiet journal line — loss you only feel if you cared.
- [ ] **448. Living heirloom export.** Export a lineage genome as a small share file; import into any save — cultivars travel between players by hand, like real plant swaps. **(L)**
- [ ] **449. Lineage portrait.** Auto-captured thumbnail of each named strain's best specimen — a herbarium of your own making.
- [ ] **450. Sibling registry.** All children of one seeding event linked as a cohort — "the spring batch" as a browsable group.
- [ ] **451. Trait provenance.** Inspector traces which ancestor a notable trait value first appeared in — "the red came in at Gen 3."
- [ ] **452. Clone group identity.** All ramets of one clonal spread share a group id and show as one organism in stats — the aspen-grove truth of runner plants.
- [ ] **453. Oldest living plant tracker.** Tank stat: eldest individual + eldest lineage — the elder tree of your aquarium.
- [ ] **454. Lineage map overlay.** Color every plant by lineage — territory of families across the tank, drift visible as color spread.
- [ ] **455. Wild-type reversion detection.** A lineage drifting back within baseline distance gets flagged "reverted" — nature un-doing your selection.
- [ ] **456. Cultivar stability rating.** How true a strain breeds (variance of children) — stable cultivars vs wild swarms, quantified from real data.
- [ ] **457. Naming suggestions from traits.** Suggested strain names derived from expressed traits ("Broadblade", "Emberline") — flavor from data, always editable.
- [ ] **458. Lineage journal chapters.** The mutation log (#382) groups by lineage — each family's story reads as a chapter.
- [ ] **459. Census panel.** Species/lineage population counts over time as a small chart — booms and busts of your ecosystem, at a glance.
- [ ] **460. Rarity grading.** Lineages carrying rare mutations (#365, #389–390) auto-grade (uncommon/rare/exceptional) — the pull-rate excitement, honestly earned.
- [ ] **461. Progenitor plaque.** Photo-mode caption option: strain name + generation + founder date — museum labels for your best plants.
- [ ] **462. Lineage-aware inspector color.** Inspector header tinted with the lineage's hue identity (#293) — families recognizable before reading.
- [ ] **463. Death cause statistics per lineage.** Which lineages die of what — discover your shade-tolerant family because they're the ones that never shade-die.
- [ ] **464. Gift cutting ritual.** Taking a cutting from a named strain prompts a one-line dedication stored in the child's record — plants as letters.
- [ ] **465. Tank origin memory.** Imported lineages remember their source tank name — "from the old jar tank" in the record.
- [ ] **466. Lineage achievements.** Quiet milestones: Gen 10 reached, 100 descendants, survived a crash — the lineage's résumé.
- [ ] **467. Convergence detection surfacing.** #386's convergent-evolution notes appear in both lineages' records — parallel stories linked.
- [ ] **468. Herbarium mode.** Flat catalog view of every distinct leaf form/color combo ever grown in the save — your personal flora, assembled by playing.
- [ ] **469. Registry save robustness.** Registry serialization versioned + forward-compatible — lineage history must survive every update (this is the crown jewels).
- [ ] **470. Lineage search.** Find-by-name/trait across the tank with camera fly-to — locate one plant among five hundred.
- [ ] **471. Anonymous wild plants stay anonymous.** Unnamed lineages show only species + generation — naming is opt-in curation; most of the wild stays wild.
- [ ] **472. Lineage swap fairs (local).** A save-file "swap shelf": exported strains from all local saves visible in-game to import — the club table, offline (#397 tie-in).
- [ ] **473. Aging registry pruning.** Extinct unnamed lineages compress to statistics after hours — memory bounded, stories kept.
- [ ] **474. Generation-gap visual check.** Debug: render Gen-1 and Gen-N of a lineage side by side — QA for whether drift is *visible* (the whole point).
- [ ] **475. Species baseline drift (meta).** If a species' entire tank population drifts one way, the tank-local baseline slowly follows — speciation's first step, logged when it happens.
- [ ] **476. Lineage-locked scenario seeds.** Scenario mode that starts from a specific exported strain — challenges built around famous cultivars.
- [ ] **477. Inspector lineage breadcrumbs.** One-tap walk: plant → parent → grandparent, camera hopping if ancestors live — genealogy as navigation.
- [ ] **478. Data export for nerds.** CSV/JSON dump of the registry — let spreadsheet players do population genetics on their own tank.
- [ ] **479. Registry performance budget.** Registry ops off the hot tick path (event-driven writes only) — a thousand plants must not cost a frame.
- [ ] **480. Lineage smoke.** `scripts/smoke_lineage_registry.gd`: assert parentage chains intact across save/load, drift metric monotonic under forced mutation, extinct compression lossless for named strains.

## Section 13 — Runners, fragments & clonal spread (481–520)

*Grounding: `REPRO_FRAGMENT`/`REPRO_PLANTLET`, `plant_fragment.gd`, `has_plantlets`, runner logic in `lily_pad.gd`.*

- [ ] **481. Runner pacing rhythm.** Runners extend in visible episodes (grow arc → pause → touch down → root #127) rather than continuous creep — you can *watch* a carpet decide where to go.
- [ ] **482. Runner direction intelligence.** Touchdown points prefer open, lit substrate cells — carpets flow around rocks and pool in clearings like water.
- [ ] **483. Daughter spacing trait.** Genome `runner_length` (mutable) sets parent-daughter distance — tight mats vs leggy pioneers from one number.
- [ ] **484. Umbilical nutrition.** Daughters share parent nutrients through the stolon until established, visibly greener than seed-born peers — clonal privilege, then independence (#143).
- [ ] **485. Runner senescence.** Old connecting stolons brown and dissolve after daughter independence — clone groups visually disband while staying linked in the registry (#452).
- [ ] **486. Fragment viability window.** Cut stems are viable minutes only (#273); viability shown as slow paling — race the clock to see them root.
- [ ] **487. Fragment settle-and-root.** A drifting fragment that lodges against substrate/hardscape for 30 s roots there — jams and eddies decide the next generation's map.
- [ ] **488. Adventitious plantlets on leaves.** `has_plantlets` species sprout mini-plants on old leaves that drop when touched (real watersprite behavior) — leaves as nurseries.
- [ ] **489. Flower-stalk plantlets.** Rosette species occasionally convert a bloom stalk into an aerial plantlet chain (real echinodorus trick) — arcs of babies over the meadow.
- [ ] **490. Turion drop.** `DORMANCY_TURION` species pinch off dense over-winter buds that sink, sit dark, and sprout on warmth — the escape-pod strategy, fully visible.
- [ ] **491. Moss fragmentation spread.** Any moss disturbance detaches viable micro-tufts (#358) that colonize where they land — moss goes where chaos goes.
- [ ] **492. Carpet edge sprint.** Carpet perimeter cells run faster than interior — lawns expand from the rim with a visible growth front.
- [ ] **493. Carpet mounding.** Old dense carpet interior mounds upward and detaches turf patches under gust load (real HC behavior) — even lawns have age dynamics.
- [ ] **494. Clonal senescence pressure.** Very old clone groups accumulate a small vigor debt (mutational load #379) fixable only by seed reproduction — clones aren't forever; sex resets the clock.
- [ ] **495. Runner redirection on block.** A runner hitting glass/rock turns along the obstacle within one episode — watch it feel its way.
- [ ] **496. Fragment source memory.** Rooted fragments record cut-point + parent (#315) — the registry knows every cutting's story.
- [ ] **497. Guerrilla vs phalanx strategies.** Genome axis: long-runner sparse invaders vs short-runner dense holders — two occupation styles, one trait, visible geography.
- [ ] **498. Daughter emancipation event.** The severing of a stolon gets a tiny visual tick (both plants shiver once) — independence day, blink and you miss it.
- [ ] **499. Floating fragment flotillas.** Multiple cuttings drifting together tangle into a raft that roots as a group when it beaches — mass colonization events.
- [ ] **500. Player cutting tool.** Scissors interaction: cut → fragment with full pipeline (wound #357, drift, root) — propagate on purpose with the systems that run the wild.
- [ ] **501. Replant snapping.** Player-planted fragments snap to substrate with a small dig animation + shock arc (#157) — planting feels physical.
- [ ] **502. Runner tangle mats.** Crossing runners from different plants weave into visible mats that resist uprooting — the sod effect; old carpets are one fabric.
- [ ] **503. Layering propagation.** (#29 tie-in) Decumbent stem contact-rooting counts as clonal reproduction in the registry — every path to a new plant is bookkept.
- [ ] **504. Plantlet drop timing.** Leaf plantlets release preferentially during gusts and grazing — hitchhiking on disturbance.
- [ ] **505. Clone group blooming sync.** All ramets of one clone flower simultaneously (same genome, same trigger) — a family announces itself in one color, tank-wide.
- [ ] **506. Fragment orientation memory.** Rooted cuttings briefly grow at their landing angle before gravitropic correction (#165) — every wild cutting has a signature kink at the base.
- [ ] **507. Runner sound.** Sub-audible soft creep tick for near-camera touchdowns — texture, not notification.
- [ ] **508. Density-dependent runner throttle.** Runner production drops as local clone density rises — carpets self-regulate; no infinite lawn spam (feeds #601).
- [ ] **509. Edge-of-tank runner climb.** Carpet runners reaching glass occasionally climb one voxel up it before failing — the endearing futile ambition of ground cover.
- [ ] **510. Fragment inspector.** Tap a drifting cutting: species, parent, viability countdown, rooted-probability estimate — hope, quantified.
- [ ] **511. Emergency fragmentation.** A dying stem plant sheds all viable tops at once as a last act — death as a dispersal event; the meadow survives its members.
- [ ] **512. Runner network debug view.** Overlay drawing all active stolons + clone group boundaries — the underground city, revealed.
- [ ] **513. Cut-point healing on parent.** Parent stems callus (#324) at cut points and re-branch below within minutes — taking cuttings *shapes* the parent, like real pruning.
- [ ] **514. Bulbil beaching.** Floating bulbils (#431) beach and root at the strand line (#416) — the waterline plants its own margin garden.
- [ ] **515. Bareroot drift beauty.** Uprooted whole plants drift with root ball trailing, plantable by the player or self-lodging — even accidents are recoverable stories.
- [ ] **516. Clonal identity in the inspector.** Ramets show "one of 14" with group age — the organism behind the individuals.
- [ ] **517. Runner direction inheritance.** Daughters bias their own first runner away from the parent line — radial escape encoded simply; clones spiral outward over generations.
- [ ] **518. Winter runner pause.** Cold triggers runner dormancy before growth dormancy — spread stops first, holding ground continues; subtle, seasonal, real.
- [ ] **519. Propagation method statistics.** Census (#459) splits population by origin (seed/fragment/runner/plantlet) — watch your tank's reproductive economy shift over hours.
- [ ] **520. Clonal spread smoke.** `scripts/smoke_clonal_spread.gd`: assert runner touchdown site validity, fragment viability decay, clone group registry consistency after severing.

## Section 14 — Flowering & bloom display (521–560)

*Grounding: `uses_flowering`, flower stage logic in `lily_pad.gd`, bolting (#32, #77).*

- [ ] **521. Bud-to-bloom arc.** Flowers develop through visible stages: bud swell → sepal split → open → full → fade, each minutes long — a bloom is an event with a timeline, not a toggle.
- [ ] **522. Bloom triggers from conditions.** Flowering requires a health streak + species trigger (light hours, temp band, crowding) — blooms certify that you're doing well.
- [ ] **523. Anthesis hour.** Each species opens at a characteristic time of day (dawn openers, dusk openers) — the tank has a floral schedule worth learning.
- [ ] **524. One-day flowers.** Most blooms last a single day cycle then fold — beauty with urgency; screenshot now.
- [ ] **525. Night-closing blooms.** Open flowers close for the night and reopen — nyctinasty (#180) at its showiest.
- [ ] **526. Surface-breaking flower spikes.** Submerged species send emergent bloom spikes that break the waterline (real aponogeton/val behavior) — flowers live in air; the tank reaches out of itself. **(L)**
- [ ] **527. Underwater cleistogamous blooms.** Some species self-pollinate in tiny closed underwater flowers — humble parallel path; both strategies bookkept (#367).
- [ ] **528. Flower color from genetics.** Bloom hue derived from lineage pigment identity (#312, #293) — your strain's flowers are *its own* color.
- [ ] **529. Petal drop litter.** Fading blooms shed petal voxels that drift and settle — after the flower, the petal rain; litter with a happy origin.
- [ ] **530. Pollinator stand-ins.** Surface flowers attract visible micro-fauna specks (springtail-like) that hop between blooms — pollination made watchable, cross-pollination (#366) made physical.
- [ ] **531. Pollen film on water.** Heavy flowering dusts a faint pollen sheen on the surface downstream of blooms — reproduction leaves a trace on the water itself.
- [ ] **532. Vallisneria surface pollination drama.** The real spectacle: female flower on a spiral stalk at the surface, male flowers released to *sail to it* — a rare scripted-feeling event, fully simulated. **(L)**
- [ ] **533. First-bloom journal moment.** Any lineage's first-ever flower gets a journal entry + auto-photo — the debut, recorded.
- [ ] **534. Bloom scent radius (fish behavior).** Open flowers slightly attract fish transits — blooms become social hubs, framing them for the camera.
- [ ] **535. Flower stalk sway distinction.** Bloom spikes sway with lower damping than foliage — flags above the meadow.
- [ ] **536. Bud abortion under stress.** Stress during bud stage drops the bud (visible tiny fall) — almost-blooms hurt; conditions matter until the end.
- [ ] **537. Sequential raceme opening.** Multi-flower spikes open bottom-to-top over a day — one stalk tells a week-long story in miniature.
- [ ] **538. Post-bloom seed head.** Pollinated flowers visibly swell into seed heads before release (#401) — cause and consequence in one object.
- [ ] **539. Unpollinated fade.** Unvisited flowers fade without seed set — the difference between pretty and *fertile*, visible.
- [ ] **540. Bloom energy cost.** Flowering visibly pauses growth (#432) — the plant chooses; you see the choice.
- [ ] **541. Crowd-triggered flowering.** Overcrowding raises flowering probability (escape-in-time strategy) — dense stands go to seed exactly when a gardener would expect.
- [ ] **542. Lily flower day-count honesty.** Lily blooms follow the real 3-day open/close cycle then sink below to develop seed — the pad's crown jewel behaving like the real jewel.
- [ ] **543. Petal count per lineage.** Slight heritable petal-count variation (5–8) — count petals to know families; nerd joy.
- [ ] **544. Doubled-flower mutation.** Rare macro-mutation (#365 pool): extra petal whorls, sterile, gorgeous — clone-only cultivar bait (#370).
- [ ] **545. Bloom-time photo prompt.** Photo mode gently badges when a first-open flower is in frame — the game knows when it's worth a picture, and says so once.
- [ ] **546. Moss/fern non-flowering integrity.** Spore species *never* flower — their moment is the spore puff (#406) with its own beauty pass — botanical honesty over uniform features.
- [ ] **547. Flower voxel palette.** Dedicated bloom palette entries (whites, pinks, yellows, one violet) with quantize rules — flowers pop within pixel-art law (#300).
- [ ] **548. Anther detail dot.** One contrasting center voxel per open flower — at this scale, that dot *is* the stamen, and it reads.
- [ ] **549. Bloom reflection on surface.** Surface-breaking flowers reflect on the underside of the water plane — doubled beauty at the interface.
- [ ] **550. Flowering suppresses nearby flowering.** A just-bloomed plant slightly delays same-species neighbors (resource signaling) — blooms space themselves in time; the tank never dumps all its fireworks at once.
- [ ] **551. Dried standing seed heads.** Emergent seed heads persist as brown standing structure after release (cattail class especially) — winter texture above the waterline.
- [ ] **552. Bloom-triggered pearl halo.** Peak-photosynthesis flowering plants pearl (#178) around the bloom hour — halos for the deserving.
- [ ] **553. Failed-first-bloom learning.** A lineage's first flowering attempt has elevated abort odds, improving with generations — even flowering gets better with heritage.
- [ ] **554. Flower inspector.** Tap a bloom: stage, hours open remaining, pollination status, expected seeds — the flower's diary.
- [ ] **555. Blooming census layer.** Calendar heat-strip of blooms per day across the save — your tank's phenology chart, self-drawn.
- [ ] **556. Cut-flower mourning.** A grazed/cut bloom drops all petals at once in a small sad burst — loss with punctuation.
- [ ] **557. Twin-bloom rarity.** Rare: two flowers from one bud point — small wonder, journal-noted (#382).
- [ ] **558. Bloom LOD dignity.** Distant blooms keep their color identity even when reduced to 2–3 voxels — flowers must never grey out at range.
- [ ] **559. Flowering scenario dial.** Scenario flag: lush-bloom mode (raised trigger rates) for players here for the garden, not the struggle.
- [ ] **560. Flowering smoke.** `scripts/smoke_flowering.gd`: assert stage sequence, condition gating, pollination→seed-set chain, spore species never enter bloom pipeline.

## Section 15 — Floating plants & surface rafts (561–600)

*Grounding: `floating_plant.gd`, floaters v2 (GOALS G), surface drift, lily pad runners.*

- [ ] **561. Raft cohesion physics.** Floaters gently attract at close range (surface tension analog) and form rafts that move as loose bodies — the duckweed *continent*, not confetti. **(L)**
- [ ] **562. Raft edge scatter.** Gusts (#202) tear singles off raft edges into open water — colonization pressure comes off the rim, endlessly.
- [ ] **563. Windward pile-up.** Persistent drift piles floaters against one glass edge in a crescent — every real pond's signature shape, self-assembling.
- [ ] **564. Frogbit rosette class.** A larger floater archetype: golden-angle rosette (#115), trailing root tress (#215), runner daughters at the rim — the queen of the surface.
- [ ] **565. Floater overlap shading kill.** Rafts stacking two-deep yellow the under-layer within minutes — self-limiting density with a visible mechanism (feeds #601).
- [ ] **566. Daughter budding visible.** Duckweed-class reproduction: a daughter frond visibly buds from the mother's pocket, then splits — multiplication you can actually witness at zoom.
- [ ] **567. Root length nutrient gauge.** (#138 surfaced) Raft-wide average root length as the tank's live trophic-state indicator — glance at the roots, know the water.
- [ ] **568. Under-raft twilight ecology.** Beneath big rafts: measurably dimmer light, cooler tone grading, shade-species refuge — the raft creates a biome under itself. **(L)**
- [ ] **569. Raft hole maintenance.** Fish surfacing through rafts punch temporary holes that heal by drift — breathing holes; the raft records traffic.
- [ ] **570. Floater flowering.** Tiny surface blooms on mature floaters (real duckweed flowers are near-invisible; make them 1 bright voxel) — the smallest flowers in the game, for those who look.
- [ ] **571. Turion sinking season.** Cold triggers floater turions (#490) sinking en masse — the surface *clears itself* for winter and reseeds in spring; the boldest seasonal statement possible.
- [ ] **572. Salvinia hair texture.** A water-repellent floater class with visible fuzz voxel texture and higher drift response — texture diversity on the surface plane.
- [ ] **573. Floater eating pressure.** Surface-feeding fish graze raft edges (#322) — floater population balanced by fish choice, not constants.
- [ ] **574. Raft rotation in gyres.** Corner eddies spin small rafts slowly (#238) — the surface has weather systems.
- [ ] **575. Floater genetics visible at raft scale.** Lineage hue identity (#293) makes clonal patches within a raft read as subtle color territories — a genetics map floating on the water.
- [ ] **576. Beaching on emergents.** Floaters snag on emergent stems (cattail class) and accumulate in tails downstream — every vertical stem becomes a comb.
- [ ] **577. Raft shadow dapple animation.** Under-raft light dapple moves with the raft — the shade below is alive because the ceiling is.
- [ ] **578. Overwintering fraction.** Not all turions survive; spring return is proportional with noise — populations breathe across seasons instead of snapping back.
- [ ] **579. Floater collection tool.** Player net-skim interaction removing raft area with satisfying drag — population control as tactile maintenance.
- [ ] **580. Skimmed-floater compost.** Skimmed floaters can be dropped onto substrate as mulch that enriches cells (#272) — the Walstad move, honored by name.
- [ ] **581. Surface tension dimples.** Each floater sits in a tiny meniscus dimple (shader) — the surface visibly *carries* them.
- [ ] **582. Raft-dampened ripples.** Ripples crossing under a raft attenuate — big rafts calm their water; visible physics coupling.
- [ ] **583. Floater die-off film.** Dead floaters waterlog, pale, and sink after a day — surface mortality feeds the bottom (#272); nothing vanishes.
- [ ] **584. New-frond gloss.** Day-old fronds render one step brighter — raft age structure readable as surface sparkle.
- [ ] **585. Mixed-species raft layering.** Bigger floaters shade out duckweed beneath them within rafts — surface succession in miniature (#565 generalized).
- [ ] **586. Raft anchoring by lily pads.** Rafts lodge against pads and stay while pads hold — pads as breakwaters structuring the whole surface.
- [ ] **587. Population boom legibility.** Doubling-time readout in census (#459) for floaters — the exponential curve, watchable and slightly terrifying.
- [ ] **588. Boom-bust crash.** Unchecked total coverage triggers nutrient crash + mass die-off (#583 at scale) — the algae-bloom parable told with plants.
- [ ] **589. Under-lid condensation drip.** Occasional drops from the tank lid punch floaters down briefly — the world above exists.
- [ ] **590. Floater fragment rescue.** A sinking damaged floater caught by a player before bottoming can be re-floated — small mercies, tactile.
- [ ] **591. Raft outline map.** Debug/inspector: raft footprint outlines with area stats — surface geography, quantified.
- [ ] **592. Emergency surface access.** Rafts always leave slivers of open water near heavy fish traffic (#569 pressure) — the sim self-preserves fish access honestly.
- [ ] **593. Floater drift trails.** Optional faint wake lines behind fast-drifting singles — surface motion made composable in screenshots.
- [ ] **594. Golden-hour raft silhouette.** Dawn light (#289) renders raft undersides as glowing amber edges from below — the daily reward for keeping floaters.
- [ ] **595. Sinking-leaf pass-through.** Shed foliage from tall plants (#55) can lodge in root tresses on the way down — the surface catches what the meadow drops.
- [ ] **596. Raft splitting event.** Strong gust splits an over-large raft along a weak line into two — raft mitosis; surface history keeps moving.
- [ ] **597. Floater lineage islands.** Isolated corner colonies drift genetically (#377) — one tank, multiple island populations, visible via #575.
- [ ] **598. Pad–floater runner interplay.** Lily runners surfacing through dense raft push floaters aside in a ring — the two surface systems negotiate space visibly.
- [ ] **599. Surface census in inspector.** Coverage %, raft count, dominant lineage — the surface as a managed commons, at a glance.
- [ ] **600. Floater smoke.** `scripts/smoke_floater_rafts.gd`: assert raft cohesion bounds, shading kill under stacks, turion sink/return cycle across a forced season tick.

## Section 16 — Propagation economy & population dynamics (601–640)

*Grounding: sim_driver tick budgets, tank capacity logic (GOALS H retune), census hooks.*

- [x] **601. Propagation economy caps.** Global + per-species reproduction budgets funded by actual plant energy — wild multiplying that *cannot* become spam; scarcity is what makes every seedling matter. **(L)** — already shipped via `plants_at_capacity()` / `plant_carrying_capacity()` volume soft cap; autonomous spread respects it.
- [ ] **602. Carrying capacity from light budget.** Tank-wide photosynthesis ceiling from lamp output — total biomass asymptotes honestly; the lamp is the sun and the sun is finite.
- [ ] **603. Logistic growth curves.** Population growth follows logistic S-curves per species (fast when sparse, saturating when dense) — booms that *bend*, never walls.
- [ ] **604. Density-dependent mortality.** Overcrowded cells raise senescence odds (#249) — thinning emerges from the crowd itself, no reaper needed.
- [ ] **605. Reproductive maturity gates.** Minimum age + size for any propagation (#258) — populations have realistic lag before booms.
- [ ] **606. Per-species population floors.** Last-3-individuals of a species get slight vigor protection — extinction stays possible but never cheap or accidental.
- [ ] **607. Boom-bust oscillation damping.** Population controllers tuned so cycles ring 2–3 times then settle — dynamic but not chaotic; a wild pond, not a sine wave.
- [ ] **608. Reproduction event queue.** All propagation events flow through one budgeted queue (spread across ticks) — a mass seeding never spikes a frame. 
- [ ] **609. Voxel biomass accounting.** Total plant voxels as the tank's biomass metric, charted (#459) — one number that means something ecological.
- [ ] **610. Population viability warnings (quiet).** Journal-only note when a species trends to extinction within the hour — informed rescue, never a nag popup.
- [ ] **611. Fast-species tax.** High `growth_rate` lineages pay proportionally more starch per propagule — r-strategists stay honest inside the economy.
- [ ] **612. Territory saturation signals.** Carpets at local cap redirect runner budget to seed budget (#541 logic generalized) — strategy switching at saturation, visible as a bloom wave at the lawn's edge.
- [ ] **613. Empty-niche colonization bonus.** Propagules landing in genuinely empty zones get an establishment bonus — the frontier advantage; tanks fill from the edges of life outward.
- [ ] **614. Disturbance-mediated coexistence.** Periodic small disturbances (grazing, gusts, digging) measurably raise species diversity vs sterile tanks — the intermediate disturbance hypothesis, playable.
- [ ] **615. Seed/clone budget split trait.** Genome allocation ratio between sexual and clonal budgets, mutable — strategies evolve under *your* tank's conditions (#519 shows the drift).
- [ ] **616. Population pyramid health read.** Age histogram (#278) summarized as one glyph (pyramid/column/spike) in the census — demography for glancers.
- [ ] **617. Local density sensing.** Plants read neighbor density via existing shade sampling (no new queries) — crowding responses built on plumbing already paid for.
- [ ] **618. Rescue effect between clone islands.** Connected clone groups (#452) share a survival buffer; isolated ramets are more fragile — connectivity matters like it does in real metapopulations.
- [ ] **619. Sterile-tank drift guard.** With reproduction disabled (#438), aging still runs — display tanks age gracefully instead of freezing.
- [ ] **620. Culling tool with dignity.** Player removal of plants routes through death pipeline (skeleton→litter #244) not deletion — even management is part of the ecology.
- [ ] **621. Population history scrubber.** Census charts scrubbable across the save's whole life — replay your ecosystem's story in curves.
- [ ] **622. Invasion event scenario.** A scenario where one aggressive species arrives as a single fragment — watch (or fight) a real invasion curve with the tools the sim already gives you.
- [ ] **623. Equilibrium detection.** The sim notices when populations have been stable for an hour and logs "the tank has settled" — a wild tank's proudest quiet milestone.
- [ ] **624. Perturbation response metric.** After any big event, time-to-equilibrium is logged — resilience as an emergent, trackable property of *your* tank.
- [ ] **625. Biomass turnover rate.** Chart voxels born vs voxels died per minute — a mature wild tank shows high turnover at stable biomass; the definitive "alive" statistic.
- [ ] **626. Priority effects.** First-established species in a zone resists later arrivals beyond its raw stats — history matters; two identical tanks diverge from planting order alone.
- [ ] **627. Alternative stable states.** Shaded-moss-dominated vs bright-carpet-dominated basins that resist flipping — big changes need big pushes; the tank has moods that persist.
- [ ] **628. Press vs pulse disturbance handling.** Chronic stress (press) shifts composition; one-off events (pulse) recover — the sim distinguishes them because life does.
- [ ] **629. Metacommunity between player tanks.** Optional slow propagule exchange among a player's own tanks (#433 automated, opt-in) — an archipelago of your making.
- [ ] **630. Rarity begets rarity.** Rare-mutation lineages (#460) get no survival favoritism — treasures can die; keep cuttings or lose them; the economy refuses to coddle beauty.
- [ ] **631. Population genetics summary.** Per-species: mean drift distance, variance, dominant lineage share (#443) — evolution dashboard from registry data.
- [ ] **632. Sustainable harvest indicator.** Census marks per-species harvestable surplus (growth above replacement) — trim guilt-free within the number; overharvest and watch the curve answer.
- [ ] **633. Tick-budget honesty test.** 500-plant benchmark scene must hold frame budget with all Section 16 systems on — naturalism that costs the framerate is a regression. **(L)**
- [ ] **634. Propagule pressure dial.** One scenario slider scaling all reproduction budgets (0.25–2×) — from contemplative garden to teeming ditch.
- [ ] **635. Death/birth event bus.** All population events on one observable bus — future systems (achievements, guardian voice, audio) subscribe without touching plant code.
- [ ] **636. Long-run drift snapshot.** Auto-save a genome census snapshot every hour — enables #621, #631 and future "your tank, one year ago" features cheaply.
- [ ] **637. Species reintroduction ritual.** Re-adding an extinct-in-tank species from inventory logs a reintroduction note with founder tag (#446) — second chances have paper trails.
- [ ] **638. Population sound layer.** Total-biomass-scaled ambient rustle bed (barely audible) — a full tank *sounds* fuller; ears confirm eyes.
- [ ] **639. Guardian narrating milestones.** Feed #623/#610/#447 events to the guardian voice as optional one-liners — the tank's keeper mentions what matters, sparingly.
- [ ] **640. Population dynamics smoke.** `scripts/smoke_population.gd`: assert logistic saturation, budget conservation (no propagation without starch spend), 500-plant tick within budget.

## Section 17 — Epiphytes, mosses & carpets (641–680)

*Grounding: `is_epiphyte`, `is_carpet` in genome, moss/carpet builders, hardscape surface data.*

- [ ] **641. Hardscape surface graph.** Precompute attachable surface cells on rocks/wood (normals, light exposure, flow) — the substrate for everything epiphytic; every item below reads it. **(L)**
- [ ] **642. Moss growth fronts.** Moss spreads cell-to-cell along the surface graph with a bright growing rim (#319) — watching a rock green over is the slowest, best show.
- [ ] **643. Moss thickness accumulation.** Occupied moss cells deepen (1→3 voxels) over time with the aging core (#270) — pile, not paint.
- [ ] **644. Aspect-driven moss.** Moss favors flow-facing, light-appropriate surfaces per species — north-side-of-the-tree logic; rocks develop natural green geographies.
- [ ] **645. Anubias pace honesty.** Epiphyte rosettes grow *one leaf per long while*, each unfurl (#42) an event — slowness as identity; the plant you check on like a friend.
- [ ] **646. Rhizome creep.** Epiphyte rhizomes visibly extend along surfaces, leaving leaf nodes behind — the plant is a path, written on the rock.
- [ ] **647. Rhizome division.** Old rhizomes fork; player can split at the fork into two plants (#500 tool) — the real way anubias multiplies in hobby tanks.
- [ ] **648. Buce patina class.** A slow epiphyte with iridescence (#287) that intensifies with leaf age — the jewel-box plant; collectors' corner material.
- [ ] **649. Fern plantlet leaf-tips.** Java-fern class: plantlets form on *old leaf tips* (#488 variant), detach, drift, attach — the canonical fern lifecycle, complete.
- [ ] **650. Black fern spore dots.** Fern leaf undersides develop the classic dark sori rows before plantlet events — the tell that babies are coming, botanically honest.
- [ ] **651. Moss trimming response.** Trimmed moss regrows denser (doubled front activation at cut cells) — the topiary loop that moss keepers know.
- [ ] **652. Carpet height by light.** Carpet cell height varies with local light (tall in shade, tight in bright) — a lawn that maps the light field in relief. 
- [ ] **653. Carpet species tiers.** Three carpet archetypes: fast/tall (weed), medium (standard), slow/tight (HC-class) with distinct cell textures — foreground identity choices.
- [ ] **654. Moss-on-wood vs rock tint.** Substrate material tints moss slightly (tannic warm on wood) — the mount shows through the moss.
- [ ] **655. Epiphyte waterline dwellers.** Epiphytes attached above waterline (emersed on hardscape tops) grow the emersed leaf form (#46) with wet-sheen (#314) — the paludarium fringe, free.
- [ ] **656. Moss detritus capture.** Moss cells trap drifting detritus (#55) — dirty moss in dirty tanks, self-cleaning under shrimp grazing; a whole loop.
- [ ] **657. Shrimp lawn interaction.** Shrimp visibly work moss/carpet surfaces, marginally boosting their health (cleaning) — the classic symbiosis, rewarded.
- [ ] **658. Moss curtain habit.** Moss on vertical faces grows downward streamers under low flow (weeping mode #21 for moss) — waterfalls of green.
- [ ] **659. Attachment strength progression.** New epiphyte attachments are weak (#344-vulnerable) and strengthen over an hour (#159) — establishment is a story, not an instant.
- [ ] **660. Carpet transition edges.** Where two carpet species meet, a mixed-stubble contested strip (#681's border war made visible at lawn scale).
- [ ] **661. Moss spore rain from mature clumps.** Thick old moss sporulates (#406) onto downstream hardscape — moss geography flows with the current.
- [ ] **662. Epiphytes refuse substrate.** Epiphyte propagules landing on open substrate visibly fail (#430) — niche honesty; rocks-only means rocks-only.
- [ ] **663. Riccia float/sink duality.** A liverwort class that thrives tied-down but escapes upward as floating fragments when neglected — the plant that leaves if you stop weaving it.
- [ ] **664. Moss ball (marimo) roller.** A novelty spherical moss that bottom currents slowly roll — tumbleweed of the tank floor; children will name it.
- [ ] **665. Carpet root mat visual.** Established carpets show a thin root-mat line at substrate contact (#502) — turf you could lift, visibly.
- [ ] **666. Epiphyte crown clearance.** Epiphyte leaf placement respects overhang clearance from the surface graph — no leaves clipping into their own rock, ever.
- [ ] **667. Moss winter bronzing.** Cold shifts moss toward bronze-green (#268 for moss) — seasons touch even the humblest layer.
- [ ] **668. Old-wood softening.** Hardscape wood surfaces host progressively richer epiphyte establishment as biofilm ages (#154 analog) — old wood becomes fertile ground.
- [ ] **669. Moss micro-fauna.** Mature moss hosts visible micro-organism specks that fry hunt (#254 tie-in) — moss as the nursery it really is.
- [ ] **670. Carpet mowing tool.** Player hedge-trim across carpets: uniform height cut, clippings become fragments (#491 for carpet species) — maintenance that propagates.
- [ ] **671. Epiphyte shadow moss.** Moss colonizes preferentially in epiphyte shade zones — layered epiphytic communities self-assemble on one rock.
- [ ] **672. Moss dormancy crust.** Dried-out emersed moss browns into a crust that revives green within minutes of rewetting — the resurrection trick, honestly earned by real moss.
- [ ] **673. Surface graph inspector.** Tap hardscape: colonizable cells, current occupants, light/flow per face — the rock as real estate listing.
- [ ] **674. Weeping-moss lineage trait.** The curtain habit (#658) as a mutable trait — moss lineages drift toward weeping or upright forms under your tank's flow.
- [ ] **675. Epiphyte fragment reattachment.** Torn epiphytes (#344) drifting against fresh hardscape can re-grip (#487 for epiphytes) — the tank replants its own walls.
- [ ] **676. Carpet-under-canopy dieback.** Carpets thin honestly under heavy shade (#193) — canopy management is lawn management; systems teach placement.
- [ ] **677. Moss age mosaic.** One old clump shows all ages at once (bright rim → mature body → bronze core) — moss as a tree-ring diagram, always on display.
- [ ] **678. Java fern black-out recovery.** Fern melts under sudden change but rhizome survives and re-leafs (#246 for epiphytes) — hardy things prove their hardiness through recovery, not immunity.
- [ ] **679. Hardscape composition metric.** Census: % hardscape colonized, by species — the taming of the rocks, quantified across the save.
- [ ] **680. Epiphyte/carpet smoke.** `scripts/smoke_epiphyte_moss.gd`: assert surface-graph-only attachment, moss front spread bounds, carpet height responds to light, fern plantlet chain completes.

## Section 18 — Competition, allelopathy & succession (681–720)

*Grounding: allelopathy in `plant.gd`, succession factor (GOALS H6), shade recompute.*

- [ ] **681. Border wars made visible.** Where two spreading species meet, a contested strip of interleaved stunted growth — front lines you can find and follow. 
- [ ] **682. Light-layer guilds.** Canopy / midwater / carpet / epiphyte guild tags — competition strongest within guilds, structure emerges between them; the tank self-organizes into strata.
- [ ] **683. Succession stages named.** Pioneer → establishment → mature phases per tank zone (extend H6) with visible community shifts — your tank has an age, per corner.
- [ ] **684. Pioneer species privilege.** Fast species get establishment bonus (#613) in disturbed/new zones but lose to climax species in stable ones — the classic relay, running on real rules.
- [ ] **685. Climax stability bonus.** Long-stable zones favor slow species (crypts, anubias) via the priority effect (#626) — patience literally changes which plants win.
- [ ] **686. Allelopathy specificity.** Allelopathic suppression hits some target species harder (susceptibility trait) — chemical warfare with a target list, discoverable by observation.
- [ ] **687. Allelopathy decay plume.** Suppression strength follows flow direction (downstream plume, not radius) — chemistry obeys the current; placement upstream matters.
- [ ] **688. Carbon competition.** Heavy pearling plants (#178) locally deplete CO₂, visibly slowing neighbors that afternoon — even success casts a shadow.
- [ ] **689. Shade as strategy.** Tall species that overtop (#16) actively win by darkening rivals (#193) — the light war fought with architecture, all systems already in place.
- [ ] **690. Root-zone competition rings.** Nutrient drawdown rings (#145) overlap and contest — underground war made inspectable (#144).
- [ ] **691. Facilitation, not just war.** Moss mats improve fern establishment; carpet stabilizes substrate against washout (#156) — neighbors also *help*; community isn't only combat.
- [ ] **692. Nurse plant effect.** Delicate species establish better in a hardy plant's flow shadow (#206) — shelter ecology; plant the tough one first.
- [ ] **693. Competitive release event.** Removing a dominant triggers visible neighbor surge within minutes (#183 at community scale) — absence as a force.
- [ ] **694. Succession clock per zone.** Inspector shows each tank zone's successional age + trajectory — read where every corner is headed.
- [ ] **695. Old-growth character.** Mature-phase zones unlock character details: thickened stems (#7), moss on plant bases, deep litter (#801s) — old parts of the tank *look* old, richly.
- [ ] **696. Gap dynamics loop.** Death of a large plant opens a light gap → seed-bank flush (#409) → pioneer race → succession recap — the forest cycle, in a glass box, in an hour. **(L)**
- [ ] **697. Competitive exclusion honesty.** Two same-guild species with big fitness gaps *will* exclude in stable tanks — coexistence needs disturbance (#614) or niche splits; the sim never fakes balance.
- [ ] **698. Niche axis visualization.** Debug plot: species scattered by light-demand × flow-preference × guild — see why your community coexists (or won't).
- [ ] **699. Allelopathic warning read.** Susceptible plants near an allelopath show the yellow cast (#184) *before* declining — telegraphed, counterable, fair.
- [ ] **700. Community-weighted tank color.** The tank's overall hue trends with dominant species' pigment identity — succession changes the *palette*; you feel the shift before you count it.
- [ ] **701. Legacy effects of past occupants.** A zone that hosted heavy allelopaths keeps a fading suppression memory in substrate for a while — ghosts of gardens past.
- [ ] **702. Invasion resistance from diversity.** Species-rich zones resist newcomer establishment (all niches drawn down) — diversity as armor, emergent from resource math.
- [ ] **703. Monoculture fragility.** Single-species zones amplify any species-targeted stress (melt events sweep them) — the sim quietly argues against lawns of one thing.
- [ ] **704. Succession rewind on disturbance.** Major disturbance resets a zone's successional clock (#683) visibly — catastrophe as renewal; the tank can begin again, locally.
- [ ] **705. Dominance index in census.** Simpson-style dominance number per guild (#459) — one statistic that says "balanced meadow" or "hygro empire."
- [ ] **706. Edge habitat richness.** Zone boundaries (carpet/midwater edges, hardscape margins) get establishment bonuses — edges are where life concentrates; the tank rewards ecotones.
- [ ] **707. Allelopathy arms race.** Chronic exposure selects (via #346-style drift) for resistance in victim lineages over generations — co-evolution in the chemistry war, logged (#386).
- [ ] **708. Guild succession sounds.** The ambient bed (#638) subtly re-voices as guild dominance shifts (carpet rustle vs canopy sway tones) — hear the succession.
- [ ] **709. Keystone removal experiment.** Sandbox tool: flag-and-remove one species entirely, watch cascade with census overlays — your tank as an ecology lesson you run yourself.
- [ ] **710. Refuge microsites.** Small no-competition pockets (hardscape crevices, filter shadow) where weak species persist at low density — the reason rare things don't vanish; realistic mercy.
- [ ] **711. Succession scenario presets.** Start tanks at chosen stages (fresh disturbance / establishing / old-growth) — players pick their chapter of the story.
- [ ] **712. Competition inspector panel.** Tap-a-plant lists its current top three pressures (shade from X, allelopathy from Y, root contest with Z) — the invisible war, itemized.
- [ ] **713. Facilitation inspector too.** Same panel lists who's *helping* (nurse shelter, moss mat, clone share) — the invisible peace, also itemized.
- [ ] **714. Priority-effect seeding order tool.** Scenario editor exposes planting order explicitly — because #626 makes order gameplay.
- [ ] **715. Long-transient honesty.** Some community trajectories take real hours to resolve — the sim resists the urge to converge fast; wild time is slow time.
- [ ] **716. Succession achievements (quiet).** Journal milestones: first climax zone, first full gap-cycle witnessed, coexistence-for-an-hour of five same-guild species.
- [ ] **717. Zonation from flow gradient.** Distinct community bands assemble along the tank's flow gradient without any scripting — check by census: species sorted by flow preference.
- [ ] **718. Competition-driven plasticity.** Contested-zone plants express taller/thinner (fight posture #16, #176); refuge plants relax to broad forms — one genome, two silhouettes by neighborhood.
- [ ] **719. The meadow test.** Acceptance criterion scene: 8 species seeded randomly must self-organize into legible strata + edges within 2 hours, no interventions — naturalism's integration test. **(L)**
- [ ] **720. Community smoke.** `scripts/smoke_succession.gd`: assert guild layering forms, gap cycle completes, allelopathy plume follows flow vector, diversity ↑ under pulsed disturbance.

## Section 19 — Seasonality, dormancy & rhythms (721–760)

*Grounding: `dormancy_type` in genome, day/night light cycle, temp system.*

- [ ] **721. Optional season cycle.** A slow ambient cycle (default: gentle, ~2 real hours per "season"; off-switch for pure-display tanks) modulating light hours, temp band, and spawn weights — the metronome behind every item here. **(L)**
- [ ] **722. Photoperiod as the season signal.** Plants read day-length trend, not a season enum — mechanistic seasonality; hack the lamp schedule and the plants believe you.
- [ ] **723. Spring flush.** Lengthening days trigger tank-wide budburst: dormancy exits (#490, #571), germination cohort (#428), bright new-growth everywhere (#58) — the year's loudest visual chord.
- [ ] **724. Summer thickening.** Peak season: maximum biomass, flower season (#523), pearling afternoons (#178) — the lush chapter.
- [ ] **725. Autumn turn.** Shortening days: senescence accelerates oldest-first (#249), reds deepen (#282 + carotenoid reveal #292), seed set completes (#538) — the tank's most beautiful decline.
- [ ] **726. Winter rest.** Short days: growth near-dormant, evergreen species carry the look (crypts, anubias, moss in bronze #667), turions sleep in the substrate — quiet, not dead; the contemplative chapter.
- [ ] **727. Species phenology strategies.** Each species owns a phenology profile (evergreen / deciduous-analog / ephemeral #269 / dormancy-type) — winter reveals who's what.
- [ ] **728. Tuber dormancy cycle.** `DORMANCY_TUBER` species (aponogeton class) die back to the visible tuber (#134) after flowering and rest before re-sprouting — the classic hobbyist mystery ("is it dead?") answered by patience.
- [ ] **729. Dormancy exit staggering.** Individuals exit dormancy over a spread of minutes (per-plant noise) — spring arrives as a wave, not a switch-flip.
- [ ] **730. Phenology calendar.** The bloom census (#555) generalizes to a full phenology wheel: germination, flowering, seed, dormancy events by season — your tank's almanac, self-written.
- [ ] **731. Off-season flowering rarity.** A confused out-of-season bloom happens rarely (warm winter spell) — anomalies keep the calendar from feeling scripted.
- [ ] **732. Season-aware propagation budgets.** The economy (#601) re-weights by season (spring: seeds; summer: runners; autumn: storage; winter: near-zero) — the year has a metabolic shape.
- [ ] **733. Storage organ swelling.** Autumn: visible starch translocation — tubers/turions swell as leaves pale, the plant visibly *packing for winter* (#134, #185).
- [ ] **734. Daylength-driven leaf posture.** The circadian leaf cycle (#180) amplitude tracks season — summer noon reaches high, winter days barely lift.
- [ ] **735. Season palette grading.** Global grade drifts subtly with season (#309): spring yellow-green cast, autumn amber warmth, winter cool clarity — the year in color temperature.
- [ ] **736. Water temp seasonal drift.** Unheated-tank scenarios let water temp follow season, driving all temp responses honestly (#181) — heaters become a *choice* against the year.
- [ ] **737. Snowmelt water change.** A big cool water change in "spring" triggers spawn/germination responses (real aquarist trick) — player ritual meets sim mechanism.
- [ ] **738. Seasonal fish–plant coupling.** Fish behavior seasons (spawning in spring plants, sheltering in winter thickets) — the layers agree on what time of year it is.
- [ ] **739. Ephemeral season window.** Ephemeral species (#269) run their whole lifecycle inside one season window then vanish to seed bank — annual wildflowers of the tank; miss them, wait a year.
- [ ] **740. Evergreen winter dignity.** Evergreens get a slight winter vigor edge (less competition) — why the tank never goes fully bare, and why crypt corners feel eternal.
- [ ] **741. Season length settings.** Player-tunable season duration (30 min – real-month sync) including "real calendar" mode — the tank keeps your actual seasons if you let it.
- [ ] **742. Hemisphere flip.** Real-calendar mode offers southern-hemisphere phase — small kindness, global players.
- [ ] **743. Dawn chorus lighting.** Seasonal dawn/dusk hour shifts with daylength — long summer evenings and early winter dusks change *when* the golden hour (#289) happens.
- [ ] **744. Winter clarity.** Reduced growth + settled particulates raise winter water clarity a touch — cold water *looks* cold; photographers' season.
- [ ] **745. Season memory in wood.** Perennial stems record season bands subtly (internode length cycles #3) — count a stem's winters like tree rings, if you look close.
- [ ] **746. First-frost analog event.** The season's first cold snap triggers coordinated autumn responses within minutes — a *date* the tank remembers each cycle, never quite the same day.
- [ ] **747. Dormancy survival stakes.** Dormant organs are vulnerable to digging fish and anoxic substrate — winter is a gauntlet; spring's returners are survivors, counted (#578).
- [ ] **748. Season-aware guardian lines.** The guardian voice (#639) references season events ("the crypts are waking") from the phenology bus — narration synced to the year.
- [ ] **749. Photo-mode season album.** Auto-curated one-photo-per-season album per tank year — the year in four images, kept forever.
- [ ] **750. Anniversary bloom.** A tank's founding date gets a small spring bloom bias on its anniversary — sentimental, invisible unless noticed, unforgettable once noticed.
- [ ] **751. Seasonal scenario starts.** New tanks can begin in any season — starting in winter and earning spring is the connoisseur's opening.
- [ ] **752. Mid-season save/load integrity.** Season phase, dormancy states, and phenology history survive save/load exactly — the year must never skip or stutter across sessions.
- [ ] **753. Season debug fast-forward.** Dev command to run a full year in minutes with census recording — tuning tool for every rhythm above.
- [ ] **754. Seasonal light spectrum shift.** Lamp color temperature drifts warmer in "autumn" if player enables it — even the sun changes with the year (#303 interplay).
- [ ] **755. Winter thinning of floaters.** Surface cover minimum in winter (#571) opens the light for evergreens below — the seasons rebalance the guilds without a single scripted rule.
- [ ] **756. Spring turbidity bloom.** Brief green-water tint at spring flush (suspended growth) that clears within minutes — the year's messiness, tastefully brief.
- [ ] **757. Season-linked mutation timing.** Seed mutation rolls (#361) happen at germination, concentrating novelty into spring cohorts — new things arrive when new things should.
- [ ] **758. Long-year mode.** Ultra-slow seasons (real months) for the permanent-desk-tank player — a year that actually takes a year; patience as a lifestyle.
- [ ] **759. Season indicator restraint.** No season UI badge by default — the tank *is* the indicator; the phenology wheel (#730) is there for those who ask.
- [ ] **760. Seasonality smoke.** `scripts/smoke_seasons.gd`: fast-forward a year, assert phenology event ordering, dormancy round-trips, budget re-weighting, save/load mid-winter.

## Section 20 — Materials & micro-variation rendering (761–800)

*Grounding: `VoxelMat`, palette quantize pipeline, `foliage.gdshader`, style-guide dither rules.*

- [x] **761. Micro-variation material service.** One service supplying per-voxel hue/value jitter (±1 palette step) keyed off `asymmetry_seed` + voxel position — kills flat-color banding everywhere, one system, all plants. **(L)** — `Plant._micro_vary_color`; column growth uses it (extend to leaf bakers next).
- [ ] **762. Two-tone leaf voxels.** Leaf voxels blend blade tone with a per-leaf secondary (vein/edge) tone — depth inside a single voxel's read, palette-legal (#300).
- [ ] **763. Ambient occlusion in clumps.** Cheap voxel AO: interior clump voxels darken one step — density reads as depth, not noise.
- [ ] **764. Subsurface glow on thin leaves.** Backlit thin leaves (low `leaf_thickness`) lift toward yellow-green when between camera and light — the translucent-leaf glow that makes underwater gardens luminous. **(L)**
- [ ] **765. Specular restraint law.** Underwater foliage never speculars; only emersed (#314) and wet-top pads (#8) may — one rule that keeps everything looking *submerged*.
- [ ] **766. Depth fog grading.** Distance + depth fog tuned so background plants recede in cool haze (#288) — free composition; every screenshot gets atmosphere.
- [ ] **767. Caustic dapple on leaves.** Surface-light caustics play across upper foliage, strength fading with depth — the signature underwater light, dancing on the plants that earn it (top of canopy).
- [ ] **768. Shadow dapple under floaters.** (#577) Raft shadows as soft moving dapple, not hard cutouts — shade with life in it.
- [ ] **769. Palette-step growth shimmer.** The growth-front glow (#177) implemented as a one-step palette lift, never bloom/emissive overdrive — restraint keeps it pixel-art.
- [ ] **770. Voxel bevel illusion.** One-pixel corner highlights on camera-facing voxel edges (shader trick) — voxels read rounded-organic, not minecraft-cubic, at zero geometry cost.
- [ ] **771. Wet meniscus line.** Emergent stems carry a one-voxel darker wet band at the waterline — the interface marked on everything that crosses it.
- [ ] **772. Age patina channel.** Per-voxel age (from #167) drives a subtle desaturation channel — old growth literally wears its time in the material.
- [ ] **773. Damage material state.** Wound/callus/necrosis (#323–324, #267) as material states with distinct dither textures — damage readable at a glance without geometry edits.
- [ ] **774. Iridescence implementation.** (#287) View-angle hue shift via cheap fresnel term quantized to palette neighbors — jewel effect inside pixel-art law.
- [ ] **775. Variegation masks.** (#285) Per-leaf procedural sector masks stored as small textures, seeded — chimera geometry stable across frames and saves.
- [ ] **776. Distance dither crossfade.** LOD transitions dissolve through the style guide's dither patterns — nothing pops; things *resolve*, like eyes adjusting.
- [ ] **777. Night material mode.** Scotopic grade (#306) as a material switch, not post-only — night plants keep silhouette detail while losing hue honestly.
- [ ] **778. Tannin water tint integration.** (#316) Water color multiplies foliage through one shared uniform — blackwater grades the whole flora coherently.
- [ ] **779. Pearl material.** O₂ pearls (#178) as bright specular micro-spheres with one animated glint — the tank's diamonds, cheap and precious.
- [ ] **780. Litter material set.** Dead leaves get their own dither + tone ramp by decay stage (#261) — the floor reads as *layered time*, not brown noise.
- [ ] **781. Moss velvet shading.** Moss normal response softened (velvet BRDF approximation) — moss reads soft against hard rock; touchable.
- [ ] **782. Root translucency at edges.** Fine water roots (#124, #215) render semi-translucent at tips — delicacy without alpha-sorting pain (dither transparency).
- [ ] **783. Flower unlit boost.** Blooms get slight self-illumination compensation in shade — flowers never disappear into their own plant's shadow (#558's law, materially enforced).
- [ ] **784. Per-species roughness identity.** Broadleaf sheen vs fine-leaf matte vs moss velvet — three roughness families so guilds (#682) separate materially, too.
- [ ] **785. Glass-side color truth.** Foliage against glass picks up the faint double-reflection tint — the tank's edges feel like glass, plants included.
- [ ] **786. Palette audit tool.** Dev overlay flagging any rendered plant pixel outside the palette (#300's enforcement) — naturalism stays lawful, automatically.
- [ ] **787. Shader LOD budget.** All Section 20 features behind quality tiers with graceful low-end fallbacks — the beauty pass must run on the potato build.
- [ ] **788. Emersed vs submersed material split.** One material fork at the waterline (sheen, sway source, tint) — the single most load-bearing rendering distinction in a paludarium-leaning tank.
- [ ] **789. Voxel seam elimination.** Adjacent same-plant voxels share jitter continuity (#761's noise is 3D-continuous) — organic gradients, never checkerboard.
- [ ] **790. Bloom-hour lighting kiss.** During anthesis hour (#523), a barely-there warm key on open flowers — theater lighting the player will feel and never spot.
- [ ] **791. Detritus dust motes.** Near-camera suspended particle motes in light shafts — the water made visible; the tank breathes in the light.
- [ ] **792. Light shaft interaction.** God-ray shafts through surface gaps (raft holes #569, canopy gaps) reaching plants below — the composition gift that keeps giving.
- [ ] **793. Reflection restraint underwater.** Internal water-surface reflection shows canopy tops faintly from below — look up through the tank and see the garden mirrored.
- [ ] **794. Color-blind verification pass.** All health/damage/age color reads verified under CVD simulation; add pattern channels where hue alone carried meaning — natural beauty, accessible.
- [ ] **795. Screenshot-mode material bump.** Photo mode may raise material tier one notch beyond gameplay settings — stills deserve the full pass.
- [ ] **796. Material state save integrity.** All material-relevant states (age, damage, pigment) derive from sim data, never shader-local — screenshots reproduce after load, always.
- [ ] **797. Micro-variation strength dial.** Global 0–2× dial on #761 — from clean-graphic to weathered-wild as an aesthetic slider.
- [ ] **798. GPU cost regression guard.** Frame-time budget test on the 500-plant scene (#633) per quality tier, run in CI — beauty patches can't silently tax the sim.
- [ ] **799. Style-guide addendum.** Document every new material rule in `style-guide/` as it ships — the pixel-art law stays written, not tribal.
- [ ] **800. Materials smoke.** `scripts/smoke_plant_materials.gd`: assert palette compliance, emersed/submersed fork correctness, jitter continuity, quality-tier fallbacks compile headless.

## Section 21 — Detritus, litter & the substrate ecosystem (801–840)

*Grounding: detritus hooks in world, substrate nutrient cells, mulm from GOALS shipped items.*

- [ ] **801. The litter layer proper.** Shed leaves (#55), petals (#529), bud husks (#76) accumulate as a persistent, layered floor stratum with its own materials (#780) — the ground truth of a living tank. **(L)**
- [ ] **802. Litter drift and pooling.** Litter migrates with bottom flow into low-flow pockets — leaf drifts behind rocks, clean lanes in the current; the floor maps the water.
- [ ] **803. Decomposition stages.** Litter decays through stages (fresh → skeletal → mulm) over tank-hours, each visually distinct — time on the floor is legible.
- [ ] **804. Decomposer fauna specks.** Litter hosts visible micro-fauna activity (#254) that shrimp and fry patrol — the brown food web, watchable.
- [ ] **805. Litter → substrate fertility.** Fully decayed litter enriches its substrate cell (#272) — plants literally grow from their ancestors' leaves; the loop closes.
- [ ] **806. Mulm honesty with restraint.** Mulm accumulates believably but caps visually — wildness never becomes filth; the Walstad aesthetic, curated.
- [ ] **807. Leaf litter as spawning ground.** Certain fish prefer spawning over leaf litter zones — the floor's texture drives behavior above it.
- [ ] **808. Botanicals kinship.** Player-added botanicals (leaves, pods) enter the same litter/decay/tannin pipeline (#316) — one decay system for everything organic.
- [ ] **809. Litter disturbance puffs.** Fish rooting through litter kick up brief mulm clouds that resettle — the floor breathes when touched.
- [ ] **810. Biofilm bloom on fresh surfaces.** New hardscape/wood grows a faint biofilm sheen in its first hour that grazers visibly clear — the new-tank film, and its cleanup crew.
- [ ] **811. Litter depth by zone.** Depth varies with canopy above (#261) — deep litter under old stands, bare sand in open flow; succession writes the floor (#695).
- [ ] **812. Buried seed interactions.** Litter cover improves seed bank survival (#404) but deep litter blocks germination light — the floor is a filter on the future.
- [ ] **813. Anaerobic pocket risk.** Over-deep undisturbed litter can sour a substrate cell (visible dark stain, bubble release) until stirred — neglect has chemistry.
- [ ] **814. Litter line art.** Drifted litter forms natural curves along flow lines — the tank draws with its own debris; photograph the floor.
- [ ] **815. Skeletal leaf treasures.** (#257) Skeletal-stage litter leaves persist longest of all stages — the floor keeps lace for those who zoom.
- [ ] **816. Shrimp litter processing.** Shrimp visibly shred large litter into mulm faster — the cleanup crew has a job you can watch being done.
- [ ] **817. Litter in moss capture.** (#656) Moss-trapped litter decays in place, feeding the moss — epiphytes farm their own soil from the current.
- [ ] **818. Floor census.** Litter mass, decay-stage mix, and fertility trend in the census (#459) — the below-tank economy, accounted.
- [ ] **819. Litter removal tool tradeoff.** Vacuuming litter cleans the look but removes future fertility (#805) — tidiness has a price the sim states honestly.
- [ ] **820. Fallen bloom poignancy.** Spent flowers (#529) decay slower than leaves, holding color in the litter for a while — beauty lingers on the floor.
- [ ] **821. Litter-borne propagation.** Moss fragments and plantlets riding litter drifts (#491, #504) establish where litter pools — debris routes double as dispersal routes.
- [ ] **822. Bacterial cycling visibility.** Substrate fertility changes render as subtle substrate tone shifts (debug: exact values #145) — the invisible engine, faintly visible.
- [ ] **823. Detritivore population coupling.** Shrimp/snail populations track litter supply loosely — the cleanup crew sizes itself to the mess; ecology, not spawners.
- [ ] **824. New-tank sterility arc.** Fresh tanks have no litter/biofilm and visibly *feel* sterile until the first turnover builds the layer — maturity is earned floor by floor.
- [ ] **825. Litter freeze in winter.** Cold slows decomposition; autumn's litter persists through winter and composts in spring (#723) — the floor keeps seasonal time too.
- [ ] **826. Driftwood tannin bleed.** New wood bleeds visible tannin wisps for its first hour (#316 source) — materials arrive with chemistry.
- [ ] **827. Floor gradient composition.** Litter/mulm/bare-sand ratios per zone as a stacked chart — the floor's biome map, quantified.
- [ ] **828. Buried treasure events.** Rare: stirring old deep litter uncovers a viable ancient seed (#434) or a lost snail — the floor remembers, occasionally aloud.
- [ ] **829. Litter sound.** Soft papery tick when large litter lands or is disturbed near camera — the quietest foley in the game.
- [ ] **830. Fungal threads rarity.** Old undisturbed litter rarely shows brief white mycelium threads before mulming — decomposition's most beautiful secret, blink-rare.
- [ ] **831. Leaf-fall drift shot.** Photo-mode composition assist highlighting active leaf-fall + light shaft alignments (#792) — the tank's autumn postcard, findable.
- [ ] **832. Litter interaction for fry.** Fry hide *in* litter gaps from predators — the floor as nursery structure, closing the circle with #339.
- [ ] **833. Substrate stain history.** Long-term litter zones permanently darken substrate tone slightly — decades (hours) of forest floor, written in the sand.
- [ ] **834. Clean-corner contrast.** High-flow bare corners stay swept — the tank always shows both states; contrast makes each legible.
- [ ] **835. Litter conservation on load.** Full litter state (position, stage, provenance) survives save/load — the floor's history is history, not decoration.
- [ ] **836. Mulm fertility cap.** Substrate cells saturate; excess mulm stops adding fertility (visible only as depth) — no infinite compost exploit.
- [ ] **837. Litter-aware runner touchdown.** Runners avoid rooting through deep litter (#482) — spread respects the floor's texture.
- [ ] **838. Autumn litter palette moment.** Peak leaf-fall renders the floor briefly amber-dominant (#725) — the one week the ground outshines the canopy.
- [ ] **839. Detritus performance budget.** Litter particles pooled + instanced; the 500-plant scene (#633) includes full litter load — the floor can't cost the meadow.
- [ ] **840. Litter smoke.** `scripts/smoke_litter_cycle.gd`: assert shed→drift→decay→fertility chain, anaerobic trigger conditions, save/load fidelity, particle budget bounds.

## Section 22 — Wild composition & placement aesthetics (841–880)

*Grounding: spawn placement logic, tank zones, photo mode; the aquascaping eye, encoded.*

- [ ] **841. Composition sampler.** Natural placement via clumped point processes (Thomas/Poisson-cluster): offspring cluster near parents with outliers — wild spacing statistics instead of uniform random or grids, for every spawn path. **(L)**
- [ ] **842. Odd-number clumping.** Cluster sizes bias to 3/5/7 — the aquascaper's rule of odds, emerging from spawn statistics nobody sees.
- [ ] **843. Drift lines of species.** Clonal spread + flow dispersal naturally draw species in sweeping lines along current (#717) — the "flow of green" that judges score, self-assembling.
- [ ] **844. Negative space preservation.** The economy (#601) values open sand/water zones by keeping colonization pressure gradient-based — wild tanks keep their clearings; emptiness is composition.
- [ ] **845. Height sorting emergence.** Guild competition (#682, #689) sorts tall-back/short-front wherever light comes from the front-top — the classic layout as a *consequence*, never a rule.
- [ ] **846. Golden-ratio zone seeding.** Initial scenario plantings bias focal species near rule-of-thirds points — starts are composed; time makes them wild.
- [ ] **847. Focal specimen framing.** Rare/large plants get a slight establishment bonus in high-visibility zones (it's where light is best anyway) — heroes find their stages honestly.
- [ ] **848. Leading-line litter.** (#814) plus runner paths (#512 visuals) create ground lines converging on focal zones — the floor points at the beauty.
- [ ] **849. Texture contrast adjacency.** Establishment bonus at fine-leaf/broad-leaf boundaries (#706 refined) — contrast edges thrive; the tank composes its own textures.
- [ ] **850. Canopy window maintenance.** Self-shading (#33) plus gap dynamics (#696) keep light windows through tall stands — cathedral light, structurally guaranteed.
- [ ] **851. The Amano diagonal.** Scenario preset seeding along a diagonal energy line — homage preset; the sim then argues with it beautifully.
- [ ] **852. Wabi-sabi asymmetry guard.** Placement sampler *rejects* near-perfect symmetry when it occurs by chance — the wild never accidentally looks designed.
- [ ] **853. Depth layering by size gradient.** Perspective trick: back-zone establishment slightly favors small-leaf species — forced perspective from ecology; tanks look deeper than they are.
- [ ] **854. Seasonal composition shifts.** Phenology (#730) moves the visual weight around the tank across the year — the composition is a moving target; every season recomposes.
- [ ] **855. Hardscape hugging.** Establishment bonus within one voxel of hardscape bases (real seedling shelter #692) — plants gather at the feet of stones; every rock gets a skirt.
- [ ] **856. Meadow rhythm repetition.** Clonal clusters of one lineage repeat its hue identity (#293) across the midground — visual rhythm from genetics; the eye finds the beat.
- [ ] **857. Vertical accent rarity.** Tall solitary emergents (cattail class) self-limit density via strong same-species allelopathy — exclamation points stay rare enough to matter.
- [ ] **858. Foreground transparency law.** Front-zone species cap at low height via light competition from the viewing side — the window stays a window without an invisible wall.
- [ ] **859. Photo-mode composition grids.** Thirds/golden/diagonal overlays + horizon level in photo mode — teach the eye the tank already obeys.
- [ ] **860. Auto-frame suggestion.** Photo mode proposes three current best compositions (focal + light + bloom weighting) — the tank knows its angles; players learn by seeing them.
- [ ] **861. Dutch street preset.** Scenario seeding in contrasting species lanes (Dutch style) — the formal garden start that wildness slowly, deliciously erodes.
- [ ] **862. Biotope presets.** Region-accurate species-set scenarios (SE Asia blackwater, SA clearwater) — naturalism includes provenance; the wild has addresses.
- [ ] **863. Emptiness metric.** Census tracks open-space fraction with a gentle ideal band (30–45%) — quantified restraint, advisory only (#844's dial).
- [ ] **864. Viewpoint-aware beauty passes.** Micro-variation (#761) and caustics (#767) tuned strongest in the default camera cone — beauty budget spent where eyes actually are.
- [ ] **865. Silhouette hour.** Dusk backlight mode renders the meadow as layered silhouettes (#743) — the composition stripped to its shapes, daily.
- [ ] **866. Reflection composition.** Surface reflections (#793) double tall focal plants at the right angles — teach the angle in a loading tip; let players find the shot.
- [ ] **867. Growth anticipation in placement.** The sampler reserves clearance for known adult sizes (#186) — today's cute clump doesn't become tomorrow's wall; wild but structurally foresighted.
- [ ] **868. Iwagumi restraint mode.** Scenario limiting flora to one carpet + one accent species — composition through subtraction; the sim's minimalist étude.
- [ ] **869. Jungle abundance mode.** Scenario with raised budgets (#634) and tall species bias — maximalism as a legitimate aesthetic; controlled overgrowth.
- [ ] **870. Path-of-light gameplay.** Moving the lamp recomposes the tank over hours (all light-following systems in concert) — the player as sun, composition as consequence. **(L)**
- [ ] **871. Frame-the-fish coupling.** Fish shelter/transit preferences follow plant structure (#334, #534) — composing plants composes fish traffic; one art directs the other.
- [ ] **872. Aging composition dignity.** Old-growth zones (#695) gain visual weight (thickness, moss, litter depth) — time makes gravity; old corners anchor compositions naturally.
- [ ] **873. Trimming as sculpture.** All trim tools (#357, #500, #670) preview regrowth direction — pruning becomes deliberate composition with honest feedback.
- [ ] **874. The overgrown-and-loved look.** Acceptance target: a 10-hour untouched tank must look *wild-beautiful*, not abandoned — the doc's single most important aesthetic bar. **(L)**
- [ ] **875. Composition debug scoring.** Dev-only heuristic scoring (balance, thirds adherence, contrast edges) across preset saves — a tuning compass, never a player-facing grade.
- [ ] **876. Seed-catalog beauty shots.** Every species/archetype gets an idealized grown-form portrait in the catalog — aspiration imagery from the actual sim, no concept-art lies.
- [ ] **877. Community composition gallery.** Local gallery of the player's own photo-mode shots per tank — the tank's portfolio, assembled by play.
- [ ] **878. Long-exposure mode.** Photo mode option stacking seconds of sway into soft motion blur — silk-water photography for plant motion (#208 shines here).
- [ ] **879. Composition onboarding whispers.** Three total loading-screen tips on plant composition (odds, negative space, diagonals) — teach a little; let the tank teach the rest.
- [ ] **880. Composition smoke.** `scripts/smoke_composition.gd`: assert cluster statistics (Thomas-process fit), open-space band under default budgets, no accidental symmetry in 100 sampled layouts.

## Section 23 — Water chemistry & environment coupling (881–920)

*Grounding: GDScript chemistry sim, CO₂/nutrient factors in `plant.gd`, `tank_config.gd` params.*

- [ ] **881. Diurnal chemistry breathing.** Plants drive real O₂/CO₂ day-night curves (photosynthesis vs respiration) that fish and chemistry feel — the tank inhales at night, exhales at noon; the deepest coupling there is. **(L)**
- [ ] **882. pH swing from planted mass.** Heavy plant CO₂ draw lifts daytime pH visibly in dense tanks — the classic planted-tank pH curve, emergent.
- [ ] **883. Nutrient drawdown competition.** Water-column N/P/K/Fe pools drawn per-plant by demand — floaters vs rooted plants compete for the *column* while roots fight for substrate (#690); two economies, one water.
- [ ] **884. Deficiency forecasting.** Chemistry trends + plant biomass project deficiencies before symptoms (#302) show — the journal warns like an experienced keeper, once, quietly.
- [ ] **885. Fertilizer dosing verbs.** Liquid dose (column pulse), root tab (substrate cell charge), fish food (slow ambient) — three inputs, three visible plant response geographies.
- [ ] **886. Overdose consequences.** Excess column nutrients feed algae films (#65, #275) before plants — the classic mistake, taught by consequence not tooltip.
- [ ] **887. CO₂ injection option.** High-tech mode: CO₂ system with visible mist/reactor, dramatic pearling (#178), doubled growth ceiling (#602) — and a crash risk if botched; the hobby's biggest fork honored as a choice.
- [ ] **888. KH buffering behavior.** Carbonate hardness dampens pH swings honestly — hard-water tanks are stable-but-limiting; soft blackwater is fertile-but-twitchy; both playable truths.
- [ ] **889. Plant ammonia uptake.** Plants take ammonia first (faster than nitrifiers) proportional to growth rate — heavy planting visibly buffers new-tank spikes; the Walstad thesis, running live.
- [ ] **890. Nitrate as the slow accumulator.** Nitrate climbs slowly in fish-heavy planted-light tanks and draws down in meadows — the number that narrates your tank's balance across sessions.
- [ ] **891. Redfield-ish visual balance.** N:P ratio shifts nudge community composition (some species P-hungry) — dosing choices sculpt the flora over hours.
- [ ] **892. GH/calcium and snail interplay.** Soft water thins snail shells (visible) while some plants prefer it — every parameter serves two masters; chemistry is tradeoffs.
- [ ] **893. Temperature stratification.** Mild vertical temp gradient (heater position dependent) that plants read locally (#181) — tall plants cross *climates*; placement is microclimate design.
- [ ] **894. Surface agitation gas exchange.** Filter/outflow agitation drives O₂/CO₂ exchange rates — ripple the surface and watch pearling drop; every knob connects.
- [ ] **895. Evaporation and top-off.** Water level falls in real sessions (#182, #148); top-off is a ritual with a small chemistry pulse (mineral concentration) — even neglect has a curve.
- [ ] **896. Chemistry inspector honesty.** Test-kit interaction returns readings with realistic granularity and delay (not live decimals) — knowledge costs a gesture, like the hobby.
- [ ] **897. Continuous monitor unlock.** A late-game "controller" device shows live curves (#881's day wave) — earned omniscience; the reward is *seeing the breathing*.
- [ ] **898. Tannin chemistry effects.** Botanical tannins (#808, #826) mildly acidify + soften — blackwater as a buildable state with visible flora consequences (#316).
- [ ] **899. Water change verb depth.** Volume + temperature delta of changes matter (shock #271 vs refresh #195) — the hobby's core ritual, with technique.
- [ ] **900. Old tank syndrome.** Neglected long-run tanks drift (mineral accumulation, buffer exhaustion) into fragile stability that big changes shatter — the veteran-keeper trap, simulated gently.
- [ ] **901. Substrate exhaustion arc.** Soil substrate fertility depletes over many hours toward inert; root tabs (#885) or litter cycling (#805) sustain it — the Walstad endgame question, playable.
- [ ] **902. Species chemistry preferences.** Soft/acid vs hard/alkaline preference per species affecting vigor — water choice becomes flora choice; biotopes (#862) assemble themselves.
- [ ] **903. Osmotic shock events.** Big sudden parameter jumps hit thin-leaf species first (#188) with melt (#246) — fragility has an order; players learn it by heart.
- [ ] **904. Allelochemical accumulation.** Allelopathy compounds (#687) accumulate in low-flow, no-change tanks, strengthening suppression — water changes literally clear the air; another reason for the ritual.
- [ ] **905. Oxygen sag drama.** Overnight O₂ sag in overstocked low-plant tanks shows as dawn fish gasping — the plant deficit made visceral; plant more, breathe more.
- [ ] **906. Chemistry event bus.** All parameter crossings (thresholds, spikes) publish to the event bus (#635) — guardian narration, journal, and achievements subscribe cleanly.
- [ ] **907. Micro vs macro nutrient split.** Fe/trace pool distinct from NPK with distinct deficiency reads (#302) — two dosing decisions, two visual languages.
- [ ] **908. Duckweed sponge quantified.** Floater biomass drawdown rate shown in census (#567 formalized) — the surface as a nutrient device, measurable.
- [ ] **909. Emergent-plant nutrient export.** Emersed growth (#170, #526) exports nutrients *out* of the water (aerial advantage) — the refugium principle; tall reaches clean deep water.
- [ ] **910. Chemistry-driven pigment truth.** All Section 8 chemistry hooks (#283, #302–303) read *these* pools — one chemistry, every color honest to it.
- [ ] **911. Parameter drift seasonal overlay.** Seasonal cycle (#721) modulates baseline temp/photoperiod inputs to chemistry — the year reaches all the way down the stack.
- [ ] **912. Crash recovery arcs.** Post-crash (algae bloom, O₂ sag) recovery follows believable multi-hour arcs with visible succession (#704) — disasters are chapters, not resets.
- [ ] **913. Chemistry difficulty modes.** Presets from "forgiving pond" (wide bands, slow drift) to "rigorous" (real rates) — naturalism scaled to the player's appetite for truth.
- [ ] **914. Dosing history journal.** Every dose/change logged with before/after snapshots — the tank's medical chart, self-keeping.
- [ ] **915. Interdependence tooltip restraint.** No system diagram UI — knowledge arrives through the journal, the guardian, and consequence; the water keeps its mystery.
- [ ] **916. Real units everywhere.** ppm, dKH, °C in all chemistry surfaces — the sim speaks hobbyist; knowledge transfers *to real tanks* (the quiet superpower of this game).
- [ ] **917. Chemistry determinism.** All chemistry integration deterministic under fixed seeds (#399) — reproducible tanks for debugging and for the speedrun community that will inevitably exist.
- [ ] **918. Sim-rust cross-validation.** Validate GDScript chemistry curves against the reference `sim-rust/` implementation in CI where models overlap — two implementations, one truth (honors SYSTEMIC doc's sim-rust fate question).
- [ ] **919. The balanced-tank grail.** Achievement condition: 3 hours, zero interventions, all parameters in band, populations stable (#623) — the Walstad promise, certified by the sim itself.
- [ ] **920. Chemistry smoke.** `scripts/smoke_chemistry_coupling.gd`: assert diurnal O₂/CO₂ phase relationship, ammonia-uptake priority, dose→response chains, determinism under fixed seed.

## Section 24 — Imperfection, asymmetry & individuality (921–960)

*Grounding: `asymmetry_seed` in genome; the thesis that flaws are what read as "alive".*

- [ ] **921. No two leaves identical.** Every leaf build consults `asymmetry_seed`-derived jitter (size ±8%, angle ±5°, tone ±1 step) — the foundational law of this section; verify no plant path skips it. **(L)**
- [ ] **922. Handedness everywhere.** Spiral chirality (#106), lean bias, first-runner direction — each plant's coin-flips recorded and consistent for life; individuality is *consistency of quirks*.
- [ ] **923. The runt.** Each seed cohort (#450) contains a visibly smaller straggler that usually dies but sometimes, *gloriously*, doesn't — the underdog story, statistically guaranteed.
- [ ] **924. The giant.** Symmetrically, rare cohort members roll high on everything — vigor outliers players will notice, name (#444), and propagate.
- [ ] **925. Crooked charm law.** Perfectly straight stems are actively prevented (minimum wander amplitude in placement) — nothing in the wild is plumb; nothing here is either.
- [ ] **926. Scars persist forever.** All damage history (#10, #253, #352) is permanent on the individual — plants accumulate biography; an old plant is *legible as* an old plant.
- [ ] **927. Individual sway signature.** Per-plant sway phase/frequency offsets (#204, #217) — at stillness-threshold zoom, you can tell twins apart by how they move.
- [ ] **928. Failed-branch stubs.** Aborted branches (#111, #536) leave permanent tiny stubs — the paths not taken, kept on the body.
- [ ] **929. Personality in growth timing.** Per-plant growth-pulse rhythm offsets (#161) — the early riser and the night grower, side by side, forever slightly out of step.
- [ ] **930. Lopsided beauty preservation.** The half-dead survivor (#253), the wind-trained lean (#187), the grazed bonsai (#335) — ensure *no* system "heals" asymmetry back to ideal; recovery grows forward, never backward. 
- [ ] **931. Individual condition memory.** Each plant carries its stress history as small permanent tone/posture offsets (#174 made permanent at low magnitude) — where you've lived marks you.
- [ ] **932. The weird one.** Per-cohort chance of one plant with doubled developmental noise (#88 spiked) — every family has one; players will love it most.
- [ ] **933. Imperfect variegation.** Variegation sectors (#285) never balance; one side always carries more — chimera truth over pattern-design tidiness.
- [ ] **934. Error-bar phenology.** Individual bloom/dormancy timing varies ±15% around lineage means (#729) — the first crocus and the last, every season.
- [ ] **935. Wobbly carpet edges.** Carpet fronts (#492) advance with irregular fingers, never smooth arcs — coastlines, not circles.
- [ ] **936. Micro-asymmetric flowers.** Petal size jitter within each bloom (#543's counts plus per-petal noise) — even the showpieces are hand-made.
- [ ] **937. Off-center rosettes.** Rosette crowns (#38) sit slightly off their root center, biased by light history (#30) — even radial plants have a *facing*.
- [ ] **938. Individuality survives LOD.** Distance rendering (#776) preserves each plant's dominant quirk (lean, hue, scar mass) — individuality must not be a close-up-only feature.
- [ ] **939. Named-individual affordance.** Any single plant (not just lineages) can be named and tracked in the inspector — the crooked cattail by the rock deserves a name.
- [ ] **940. Twin divergence showcase.** Journal note when two clone-twins have measurably diverged (damage/plasticity #718) — nature *and* nurture, documented in your own tank.
- [ ] **941. Asymmetric root flares.** (#140) plus random buttress spacing — even the anchor is individual.
- [ ] **942. Determinism of quirks.** All individuality derives from seeds + history, zero per-frame randomness (#399) — quirks are *facts about the plant*, stable across save/load and replay.
- [ ] **943. Anti-uniformity audit tool.** Dev overlay flagging any group of plants whose pairwise visual distance falls below threshold (#40's metric, live) — clone-stamping detected automatically, forever.
- [ ] **944. Charming failure states.** The runner that climbed glass (#509), the seed sprouted in the filter (#418), the pad grown through a raft (#598) — audit that edge cases resolve to *stories*, not clipping.
- [ ] **945. Individual palatability variance.** Fish develop preferences for specific *individuals* (slight per-plant palatability jitter) — the one bush they always nibble; players will notice and wonder.
- [ ] **946. Posture at rest is personal.** Rest-pose droop/pitch per plant varies within lineage bands (#116–117 plus jitter) — a crowd of the same species stands like a *crowd*, not a formation.
- [ ] **947. First-leaf keepsake.** Each plant's first true leaf is flagged; if still alive when the plant matures, journal notes it — continuity of self, celebrated once.
- [ ] **948. Weathered vs sheltered contrast.** The same lineage grown in current vs shelter diverges visibly in posture and wear over an hour — environment writes on bodies; players *see* microclimates through individuals.
- [ ] **949. Imperfect propagation outcomes.** ~5% of cuttings root crooked, stunted, or double-crowned but viable — propagation has personality too; cull or cherish.
- [ ] **950. Odd growth season.** Rare individual-level "bad year" (one season of weak growth, no cause shown) — sometimes a plant just struggles; the sim keeps one mystery.
- [ ] **951. Beauty-in-age bias check.** Playtest metric: players asked to pick favorites should pick scarred/old/asymmetric individuals at meaningful rates — if everyone picks pristine, this section has failed; retune.
- [ ] **952. Snowflake shader guard.** Verify micro-variation (#761) + individuality never aliases into visual noise at any zoom (#305) — individual ≠ messy; the audit for taste.
- [ ] **953. Individual history export.** A named plant's full life record (growth curve, damage, blooms, offspring) exportable as a small text biography — obituaries for the ones that mattered.
- [ ] **954. The keeper's-eye tutorial.** One optional journal page teaching players to *read* individuals (scars, lean, flag leaf #248) — literacy in the language this whole section writes.
- [ ] **955. Quirk inheritance whisper.** Children inherit faint echoes of parental quirk magnitudes (#373) — families of weirdos; the crooked lineage stays lovably crooked.
- [ ] **956. Asymmetry in death.** Even death timing within synchronized events (#271) staggers per-individual — no mass simultaneous anything, ever, anywhere.
- [ ] **957. Identity performance guarantee.** All individuality is bake-at-build (seeds, offsets), zero per-frame cost — a thousand individuals run like a thousand clones.
- [ ] **958. Cross-section variety check.** Marketing-shot audit: any random 10-plant crop of a mature tank must show 10 distinguishable individuals — the box-art proof of the thesis.
- [ ] **959. The imperfect default.** Ship all Section 24 systems ON by default at tasteful magnitudes — imperfection is the aesthetic, not an option buried in menus (dial exists: #797).
- [ ] **960. Individuality smoke.** `scripts/smoke_individuality.gd`: assert pairwise distinctness thresholds, quirk determinism across save/load, zero per-frame RNG in identity paths.

## Section 25 — Rare wonders & emergent beauty moments (961–1000)

*Grounding: the event bus (#635), photo mode, guardian voice; the payoff layer for everything above.*

- [ ] **961. Rare-event scheduler.** A budgeted director that permits at most ~one wonder per hour, weighted by tank state readiness — scarcity engineering so miracles stay miraculous. **(L)**
- [ ] **962. The mass bloom.** When many plants near bloom-readiness, the scheduler may sync them (#505 tank-wide) — one dawn, the whole tank flowers; players will screenshot-reflex before breathing.
- [ ] **963. Pearl cascade evening.** Perfect CO₂/light afternoons culminate in tank-wide pearling with pearls streaming off leaf tips in chains (#178, #229) — the champagne tank.
- [ ] **964. Seed snow.** A synchronized mast event (#422) fills the water column with drifting motes backlit in the light shafts (#792) — underwater pollen-blizzard; grief and hope in one weather.
- [ ] **965. The vallisneria wedding.** (#532) staged by the scheduler when conditions align — male flowers sailing to the spiral-stalked female across the surface at dusk; the sim's love story.
- [ ] **966. Moonlight bloom.** One species blooms only at night under moonlight mode (#306) — the reward for players who visit after dark.
- [ ] **967. Fog of spores.** A mature moss wall's synchronized spore release fills a light shaft with drifting motes (#406 at scale) — the forest exhale.
- [ ] **968. The green flash of dawn.** Rare perfect-parameter mornings intensify the gold hour (#289) with a one-minute emerald cast through the meadow — weather luck, tank edition.
- [ ] **969. Skeleton leaf drift.** A perfect skeletal leaf (#257) detaches and drifts a full slow diagonal across the tank before settling — four seconds of accidental art the scheduler protects from interruption.
- [ ] **970. First root timelapse.** The inspector offers a recorded 10-second replay of any plant's germination (#419) after it matures — you can always rewatch a life's beginning.
- [ ] **971. Bubble nest garden.** If fish build bubble nests, floaters and fine plants get woven in visibly — two systems making one artifact neither owns.
- [ ] **972. The survivor's flower.** A plant that recovered from <10% health blooming for the first time gets a journal entry with its damage history — narrative payoff computed from data that's already there.
- [ ] **973. Underwater rainbow.** Rare caustic + particle + angle alignment casts a brief spectral band across the meadow (#767, #791) — unphotographable-in-time by design; a story players tell.
- [ ] **974. The old tree.** When a plant reaches triple its species' median lifespan, it earns permanent subtle presence upgrades (moss at base #695, deeper tone) — the tank builds its own landmark.
- [ ] **975. Migration morning.** After a mass turion wake (#571), the surface repopulates over one morning in visible waves — spring arriving as a *front* crossing the tank.
- [ ] **976. Guardian's favorite.** The guardian voice occasionally mentions one specific individual plant it "likes" (highest quirk magnitude #932) — the AI keeper has taste; players will agree or argue.
- [ ] **977. Convergence ceremony.** When #386 detects convergent evolution, the journal pairs both lineages' portraits (#449) — the sim celebrating its own science.
- [ ] **978. The hundredth generation.** Gen-100 of any lineage triggers a quiet lineage-tree fireworks view (#445 animated) — deep time, honored.
- [ ] **979. Perfect stillness event.** Rare dead-calm minutes (flow near zero #226) where the meadow stands almost still and the water clears (#744) — the held breath; then the current returns.
- [ ] **980. Storm and aftermath arc.** The pump-surge storm (#220) followed by litter redistribution (#802), fragment flotillas (#499), and a germination flush (#409) — one event, an hour of consequences; wildness as narrative.
- [ ] **981. Night pearl lanterns.** Rare warm nights, residual pearling holds on leaf tips into darkness, catching moonlight — the tank keeps candles lit.
- [ ] **982. The returning species.** An ancient-seed germination (#434) of a locally-extinct species gets full journal ceremony — resurrection is the rarest wonder; treat it so.
- [ ] **983. Fish-planted garden reveal.** When a zoochory seed (#407) matures to flowering, its journal shows the fish that carried it — credit where credit is due.
- [ ] **984. Anniversary portrait.** On the tank's founding anniversary (#750), photo mode auto-composes a then/now diptych from the season album (#749) — a year of growth in one image.
- [ ] **985. The commensal arch.** When an epiphyte, its moss skirt (#671), and a curtain (#658) fully colonize one hardscape piece, the journal names the formation — the tank grows monuments.
- [ ] **986. Rain on the roof.** Rare condensation-drip minutes (#589) patterning the surface while pads rock (#4) — indoor weather; melancholy, free.
- [ ] **987. Wonder witness bonus.** Wonders witnessed live (camera present) log as "witnessed" vs "found after" — no reward difference, just the record; being there matters to the record because it matters to people.
- [ ] **988. The quiet after crash.** Post-crash recovery (#912) completing triggers the tank's most saturated healthy-color grade for one hour — the sim's version of the clear light after a storm.
- [ ] **989. One-in-a-thousand seed.** A triple-jackpot genome roll (macro-mutation + beneficial + color sport) at ~1/1000 seeds — this doc's namesake; the scheduler guarantees nothing, the odds guarantee eventually.
- [ ] **990. Wonder gallery.** All witnessed wonders replayable as saved 10-second clips in a gallery — the tank's greatest-hits reel, self-curated.
- [ ] **991. No-repeat freshness.** The scheduler de-prioritizes recently-shown wonder types per save — a long-lived tank keeps surprising because the director remembers.
- [ ] **992. Wonder foreshadowing.** Every scheduled wonder has a 5-minute subtle tell (bud swell everywhere, gathering shimmer) — the observant get to *anticipate*; anticipation is half the wonder.
- [ ] **993. Do-not-disturb integrity.** Wonders never pause the sim or take camera control — they happen *in* the world whether or not you look; that's what makes them real.
- [ ] **994. Wonder accessibility.** Every visual wonder carries an audio signature and vice versa — no player misses the mass bloom because of how they perceive.
- [ ] **995. Streamer-safe determinism.** Wonder scheduling seeds derive from tank state, not wall clock — two players with identical tanks get identical wonders; speedrunners and scientists both served (#917).
- [ ] **996. The tank that grows without you.** Away-time simulation (existing recap systems) can include one wonder in the recap ("while you were gone, the crypts all flowered") — absence has stories too.
- [ ] **997. Wonder economy honesty.** Wonders emerge only from real sim states — the scheduler *permits* and *syncs*, never fabricates; audit every wonder path for this law. **(L)**
- [ ] **998. The long game reward curve.** Wonder frequency slightly rises with tank age/maturity metrics (#824, #695) — old tanks are wonder-rich because mature ecosystems genuinely have more going on.
- [ ] **999. The final acceptance test.** A blind viewer shown a 5-minute clip of a mature tank must describe it as "alive" unprompted — naturalism's Turing test; run it with real playtesters before calling this doc done. **(L)**
- [ ] **1000. Plant a seed, name it, wait.** The doc's closing ritual as a feature: a one-tap "plant one seed" gesture on any mature flower, with the child trackable from mote to bloom (#425, #442, #533) — the whole thousand items, experienced through one small life. 

---

## Coda

Everything above serves one sentence: **a tank left alone should become more
beautiful, more varied, and more itself.** Growth that visibly happens,
multiplication that must be earned, mutation that writes family stories, decay
that feeds the next generation, and — rarely, honestly — wonder.

Work the foundations shortlist first. One idea, one commit, one verification
(`./scripts/godot.sh --headless --path shaders-godot/godot-project --script
res://dev/compile_check.gd`, then the relevant `smoke_*.gd`). Mark items done
here as they ship, mirroring GOALS.md.

