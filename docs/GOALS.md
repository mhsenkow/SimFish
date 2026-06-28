# walstad loom — Goals & Ideas Backlog

A working checklist of things we *could* do to push walstad loom further toward
the Walstad-style hyper-realistic ecosystem feel.

**How to use this doc:**
- Each item is small enough to be a session of work, or grouped under a feature
  flag if larger.
- Effort: **S** (≤2h), **M** (half-day), **L** (full day+).
- Impact: **S** (polish), **M** (noticeable), **L** (transforms how the tank feels).
- Check items off as you ship them; add new ones as they come up.

Last reviewed: 2026-06-16.

**Source of truth:** shipped features are described in the top-level
[README.md](../README.md) ("Recent additions" + "Roadmap"). This file tracks the
remaining idea backlog. Of the original 50, only item **#50 (multi-tank wallpaper mode)**
remains open. The new **Section H ("Living balance pass")** below is a 100-item
holistic sweep aimed at making the whole Walstad ecosystem feel genuinely
balanced, forward-moving, and alive — grounded in the current chemistry /
nutrient / O₂ / population engine and the per-scenario default parameters.

---

## A. Motion & behavior

Real fish do tiny things constantly — gill flares, eye darts, brief pauses to
look at things. Each one is small but the cumulative effect is the difference
between "voxels swimming around" and "creatures alive in a tank."

- [x] **1. Surface gulping when O₂ low.** Fish swim to the meniscus and bob — already simulated O₂, just missing the visible response. *Effort: M · Impact: L* — Tier 0.2 in fish.tick. When `sim.dissolved_o2 < SURFACE_GULP_O2` (0.45) the fish steers toward `world_bounds` top with a small lateral random walk so the column doesn't pile up. Reads as "the school just bolted upward" — the unmistakable hypoxia tell.
- [x] **2. Hide-in-plants stress response.** When stress > 0.7, steer toward nearest plant cluster and hold position inside it. *Effort: M · Impact: M* — Tier 0.6 in fish.tick. `stress > STRESS_HIDE_THRESHOLD` (0.65) → seek nearest plant with biomass ≥ 6 within 3 units, steer into it at 0.7× max speed.
- [x] **3. Inspection behavior.** Fish briefly orient toward and pause near new objects. *Effort: M · Impact: L* — already implemented as the "HOVER / INVESTIGATE TRIGGER" at fish.gd:1700, which fires at ~12% per-second and damps the fish to 15% max speed while preserving wall-avoid contribution. Adding "newly placed object" detection is open work for a future pass.
- [x] **4. Gill-flare at rest.** Subtle scale pulse on the head when speed ≈ 0; reads as breathing. *Effort: S · Impact: S* — `_head_pivot.scale.x` is now modulated by a `rest_factor` × sin(_swim_phase × 0.9) every frame. Hidden by the wag wave when actively swimming, visible as gill breathing when the fish is drifting / sifting / sleeping.
- [x] **5. Eye saccades.** Small random yaw of an eye sub-mesh every few seconds when alert. *Effort: S · Impact: S* — implemented as a head micro-yaw rather than separate eye meshes (avoids touching the voxel anatomy). At rest the head jitters by ±0.22 rad every 2.5–5.5 s with a decay, reading as a "glance" — independent timer per fish so the school doesn't twitch in sync.
- [x] **6. Juvenile play / chase.** Fry chase each other in short bursts — pure social motion, no foraging objective. *Effort: M · Impact: M* — Tier 3.8 in fish.tick. Fry that aren't hungry / stressed / tired roll a per-tick dice (~every 20 sim seconds on average) for a 0.4 s play burst toward a nearby fry within 2 units.
- [x] **7. Sleep state at night.** Diurnal fish drift into plant cover and slow to almost-stop at deep night. *Effort: M · Impact: L* — extends the day/night activity multiplier block. At `daylight < 0.18` AND species is diurnal (school/shoal/hover/meander), the fish gently pulls toward the nearest large plant at 0.35× max speed, with `current_mode = REST`. Reads as "drifting into the foliage to sleep."
- [x] **8. Tap-glass startle.** Player tap on the tank glass triggers a flee burst from nearby fish. *Effort: S · Impact: M* — `_startle_fish_near_tap()` in main.gd. Any LMB click that isn't a creature-pick / feed-drop projects to the substrate plane; fish within `STARTLE_RADIUS_SQ` (3 units) get a 0.5 s burst directed away from the tap point + a propagated `_startle_heading` so school-mates copy the panic.
- [x] **9. Surface skim feeding.** Top-dwellers (killifish, danio) gulp at the meniscus when food drifts there. *Effort: M · Impact: M* — Y-affinity bias added to Tier 1b's KIND_FOOD scoring. Food in the wrong water column for this fish takes up to a ×1.5 distance penalty in candidate ranking, so surface dwellers win surface flakes while bottom-dwellers hoover sunken pellets. Mild enough that a truly hungry fish still chases anything.
- [x] **10. Substrate dig.** Corydoras + mudsifters briefly nose-down + kick up a tiny mulm puff while shuffling. *Effort: S · Impact: M* — when a shuffle-pattern fish enters its sift state (already triggers nose-down tilt via _bank_pivot.rotation.x), it now also calls `world.add_mulm_voxel(global_position)` so a visible mulm voxel appears under it. Caps with the existing mulm-voxel limit.

## B. Breeding & lifecycle

The reproduction loop is the heart of an ecosystem sim. Each visible step
sells the "this is alive" feeling.

- [x] **11. Intensifying courtship display.** Color pulse + fin spread ramps over the courtship window so the spawn moment reads as a flash. Some of this exists; needs tuning. *Effort: M · Impact: M*
- [x] **12. Mouthbrooder egg-carry.** Selected cichlid-likes carry visible eggs in the throat for the incubation period. *Effort: L · Impact: M* — shipped: `is_mouthbrooder` genome flag drives a throat-bulge mesh + delayed fry release (`sim_driver._release_brooded_fry`) for angelfish + dwarf gourami.
- [x] **13. Fry-in-plants shoaling.** Fresh fry seek the densest plant patch and shoal there until juvenile. *Effort: M · Impact: L*
- [x] **14. Adult coloration deepening with age.** Juveniles slightly desaturated, adults full vivid. Currently jumps; should be gradual. *Effort: S · Impact: M*
- [x] **15. Live-bearer pregnancy bulge.** Guppy females visibly grow rounder before birth. Already partly modeled; needs animation curve. *Effort: S · Impact: M*
- [x] **16. Sterile / hybrid genetic flag.** Some crossed pairs produce non-viable eggs that simply don't hatch — adds genetic realism. *Effort: M · Impact: S*
- [x] **17. Parental clutch guarding.** Egg-laying species defend their eggs from passing fish for the incubation window. *Effort: M · Impact: L*
- [x] **18. Pheromone trails during heat.** Subtle particle trail from a receptive female that nearby males can follow. *Effort: M · Impact: M*
- [x] **19. Species-tinted egg color.** Eggs currently look identical; tinting them per-species sells the variety. *Effort: S · Impact: S*
- [x] **20. Per-species mating dance.** Each species gets a distinct courtship choreography (spiral, parade, vertical bob, parallel cruise). *Effort: L · Impact: L* — shipped: five dance variants gated by `swim_pattern` in `fish.gd`'s breed branch (parallel S-curve, jerky lateral snap, vertical figure-8, wide circling, slow lateral display).

## C. Food web & ecology

The trophic loop is already wired — these add visibility and dynamics.

- [x] **21. Algae bloom dynamics.** When nutrients spike + plant biomass low, water gradually tints green; balance shift crashes it back. *Effort: L · Impact: L* — sim_driver computes continuous `bloom_pressure` from nutrients × plant-shortage, smoothed into `bloom_intensity`. Spawn rate, cap, and accelerated die-off during the crash phase (high biomass, low nutrients) all scale from it. world.gd lerps the water material toward green proportionally so a bad bloom literally clouds the tank.
- [x] **22. Microfauna (copepods, daphnia).** Tiny moving white dots, snack food for fry. *Effort: M · Impact: L* — `microfauna_swarm.gd`; drifting individuals refilled by `world._maintain_microfauna()`; two visual variants (copepods + paler-blue daphnia). Eaten by the filter intake currently; full predation hook still pending.
- [x] **23. Tap-to-feed.** Tap the tank surface to drop a flake cloud; fish converge from below. *Effort: M · Impact: L* — Ctrl+LMB (or ⌘+LMB on macOS) projects the cursor onto the water surface and drops 4–6 KIND_FOOD pellets in a small jittered cluster. Pellets bob on the surface for 8 s before sinking — exactly like real flake food. Fish converge via the existing food-pickup tier.
- [x] **24. Substrate worms.** Visible squirms in mulm patches — visual proof of the detrital loop. *Effort: M · Impact: M* — `wriggle_worm.gd`; two-segment voxel with head-leading phase wave; population scales with mulm carpet density.
- [x] **25. Plant flowering events.** Lily pads, cattails, and emergent plants occasionally bloom for a few minutes. *Effort: M · Impact: M* — already present: lily_pad has full 6-petal bloom lifecycle, cattails have seed-head puffing, base plant.gd has bud→opening→mature→seed-pod stages inherited by spiral/branch plants. Tuning per species is open work.
- [x] **26. Filter intake suction.** Particles within ~0.5 units of the filter intake drift toward it. *Effort: S · Impact: M* — `sim.filter_intake_pos` published by `world._build_filter_aerator()`; Microfauna accelerates toward intake within `FILTER_PULL_RADIUS` and despawns on contact. Waste particles still ignore it (they settle too fast for the pull to read).
- [x] **27. Tannin staining from driftwood.** Wood pieces slowly tint the water tea-brown over hours. *Effort: M · Impact: M* — already present: `world.tannins` rises slowly in `_process` and lerps the water material toward a warm brown.
- [x] **28. Predator–prey rebound cycles.** When a snail-hunter dies, snails boom; when puffers eat snails too fast, puffer starves. Track these explicitly. *Effort: M · Impact: M* — sim_driver refreshes `snail_predator_count` every tick. snail.gd halves its breeding-interval roll when the count is zero, so removing the last loach / puffer triggers a visible snail boom over the next few minutes. Re-introducing a predator drops the rate back to baseline.
- [x] **29. Plant nutrient competition.** Fast-growing stems crowd out slow rosettes when nutrients are limited. *Effort: L · Impact: M* — plant.gd now caches a `_shade_mult` recomputed every 4–6 s. Plants scan sibling plants within SHADE_RADIUS; if any sibling is taller by SHADE_HEIGHT_DELTA the multiplier drops to SHADE_PENALTY, attenuating effective nutrient uptake and visibly slowing the shaded plant's growth. Real Walstad shade competition.
- [x] **30. Population history graph.** Tap a stat chip to see a 24h sparkline of that population. *Effort: M · Impact: M* — sim_driver maintains a 120-sample (=120 s) ring buffer in `population_history` covering fish, shrimp, snails, algae, plants, biomass, nutrients, and O₂. Each chip in the top HUD is now tappable; tapping pops a panel with a polyline sparkline (soft fill under the line) + now / min / max readout. Closes on click-outside.

## D. Plants, substrate, hardscape

Plants drive the Walstad balance — they're what makes the tank stable. Make
them visibly alive.

- [x] **31. Plant melt animation.** When a plant dies of starvation, leaves yellow then curl then detach as detritus over ~30s rather than vanishing. *Effort: M · Impact: L* — already implemented in plant.gd: `_begin_dying()` triggers a multi-stage decay (pinholes → leaf shedding → per-voxel `_decay_one_voxel()`), and crypt-style species recover via `_melt_active` + `_melt_regrow_timer` after ~40 sim-seconds.
- [x] **32. Visible root spread.** Thin voxel roots emerging just below substrate around root-feeders (swords, crypts). *Effort: M · Impact: M* — root cap dynamically scales with `current_height` (5 → 12), new roots beyond the original 5 use a golden-angle stride to fan into the gaps, and later-grown roots get a `lateral_bias` so the mat fans outward instead of stacking under the trunk.
- [x] **33. New-leaf unfurl.** Fresh leaves spawn rolled up and unfurl over a few seconds. *Effort: M · Impact: M* — `_animate_leaf_unfurl()` in plant.gd uses a parallel Tween to scale leaf_node from (0.15, 0.25, 0.15) to full + tilt the rotation in from -35° to 0° over ~1.6 s. Hooked into all four leaf-build paths (paddle / ribbon / lance-pair / needle).
- [x] **34. CO₂-deficiency pose.** Pale, curled leaf tips when light is high but plant growth is stalled. *Effort: S · Impact: S* — `_apply_deficiency_tints()` infers CO₂ stress from `daylight > 0.7 AND growth_progress stalled AND plant healthy`; tints the top quartile of voxels with a pale `(0.88, 0.95, 0.84)` shader-instance tint. Added an `instance uniform vec4 tint` to voxel.gdshader so per-voxel tinting works without duplicating materials.
- [x] **35. Carpet plant runner propagation.** Foreground carpet plants (dwarf hairgrass, monte carlo) send out lateral runners that root and sprout. *Effort: L · Impact: L* — `_lay_runner_trail()` in lily_pad.gd drops a chain of 4-8 dark-green substrate-hugging voxels between parent and freshly-spawned child pads. Sells the causal "this came from that" link the instant-spawn version lacked. (Lily pads carry the runner system; stem-plant carpets reuse it conceptually.)
- [x] **36. Floating species.** Duckweed / frogbit / red root floaters drifting on the surface, blocking light below — emergent shade. *Effort: L · Impact: L* — already implemented in world.gd: `_spawn_floaters()` creates 18 duckweed-like surface entities with sinusoidal XZ + Y drift; existing propagation block spawns new floaters when nutrients are high, with `DUCKWEED_CAP` limiting total count.
- [x] **37. Iron deficiency yellowing.** Stem plants in low-iron substrate develop a yellow tinge specifically at the new growth. *Effort: S · Impact: S* — same `_apply_deficiency_tints()` system as CO₂. When `nutrient_mult ∈ [0.25, 0.6]` (middling — not starving, but not vivid), the top quartile of voxels gets a `(1.05, 1.0, 0.55)` warm-yellow tint via the new instance shader parameter.
- [x] **38. Pearling intensity ↔ health.** Pearling already exists; tune it to scale with biomass + light + dissolved O₂ saturation. *Effort: S · Impact: M* — `_tick_pearling()` now computes `pearl_factor = (O₂-0.75)/0.25 × (daylight-0.4)/0.6 × (health-0.5)/0.5 × biomass-factor` and writes it into the GPUParticles3D's `amount_ratio` so the emission rate varies continuously rather than binary on/off.
- [x] **39. Substrate dig disturbance.** Corydoras / loach digging leaves a brief visible divot in the substrate that re-settles. *Effort: M · Impact: M* — `world.spawn_substrate_dust()` drops 3-5 tiny dark voxels that puff up + outward via parallel Tween over 1.4 s, scaled to 0.2 and freed. Layered on top of the existing persistent mulm voxel at the sift point.
- [x] **40. Driftwood biofilm.** Fresh driftwood develops a fuzzy white biofilm for the first week, then settles. Shrimp + otos graze it. *Effort: M · Impact: M* — `world.biofilm_progress` climbs slowly toward 0.65 over ~5 sim-minutes, decays past peak. `_apply_biofilm_tints()` paints a deterministic fraction of driftwood voxels with a warm-white `(1.28, 1.22, 1.10)` tint via the instance shader parameter. Stable pattern (deterministic hash) so a voxel doesn't flicker tinted/untinted between updates.

## E. Environment & atmosphere

The medium itself — water, light, surface, sound — sells the immersion.

- [x] **41. Surface ripples from fish darts.** A fast direction change near the surface produces a small expanding ring. *Effort: M · Impact: L* — `world.spawn_burst_ripple(pos)` tweens a flat voxel ring outward + fades its albedo via duplicated material. Fish.gd calls it from the auto-dart branch when the fish is a top-water species (`preferred_y ≥ 4.0`) and bursting near its home Y.
- [x] **42. Visible current particles.** Subtle dust motes drifting along the flow vectors from the filter return. *Effort: M · Impact: M* — already implemented: `world._emit_filter_outflow()` (called from `_build_filter_aerator`) emits a 14-particle GPUParticles3D jet of small pale spheres from the spout end, with downward-out direction + buoyancy gravity, so the stream curves into the tank then rises.
- [x] **43. Mineral spots on glass.** Over hours, faint white speckle appears on glass at the waterline. *Effort: M · Impact: S* — `world._maybe_add_mineral_spot()` ticked from `_process` every 20-40 sim seconds. Picks a random wall + waterline-adjacent Y and sprinkles a tiny pale voxel. Capped at MINERAL_SPOT_CAP (35) so the glass ages visibly without ever fully crusting over.
- [x] **44. Surface caustics.** Light pattern scrolling across the substrate, sourced from a wavy surface mesh. *Effort: L · Impact: L* — procedural dual-Voronoi next-pass shader.
- [x] **45. Day/night ambient audio crossfade.** Morning birds, midday quiet, evening cricket / cicada layer through the speakers behind the tank. *Effort: M · Impact: L* — `ambient_audio.gd` now auto-triggers plinks at an interval that scales with `sim.daylight()` (3 s at midday → 12 s at midnight) and biases the pentatonic pitch higher in the day. The player's `volume_db` also lerps from -14 dB (midnight) to -6 dB (midday) so the day/night contrast reads as audible amplitude as well as cadence.
- [x] **46. Heater glow.** A small visible heater rod with a faint warm light pulse. *Effort: S · Impact: S* — `world._build_heater()` drops a thin black-glass rod with a visible red filament strip at the back-right corner of the substrate, plus an OmniLight3D (warm orange, 1.4 unit range) so the rod genuinely glows in the corner.
- [x] **47. Tank-condition mood indicator.** A subtle UI chip showing tank "vibe" — Thriving / Cycling / Stressed / Crashing — based on aggregate metrics. *Effort: M · Impact: M* — new "mood" chip in the top HUD. Aggregates `0.3 × O₂ + 0.3 × biomass-normalized + 0.2 × (1 - algae) + 0.2 × (1 - waste)` and maps to 🙂 thriving / 😌 ok / 😟 stressed / 🚨 crashing.
- [x] **48. Walstad cycle phase.** "Day 3: ammonia spike" / "Day 14: nitrites" / "Day 28: cycled" labels with appropriate algae behavior per phase. *Effort: L · Impact: L* — `tank_age_s` + `bacteria_colony` in `water_chemistry.gd`; fresh vs established cold-start via `cycle_start_mode`; water chip + cycle banner + story log day prefixes; save v3.
- [x] **49. Tank story log.** Auto-generated diary entries: "Day 5: glassdart pair formed" / "Day 12: first hatch" / "Day 18: betta lived 8 days, died of old age." *Effort: M · Impact: L* — sim_driver.gd has `story_events: Array` capped at MAX_STORY_EVENTS (200). First-egg, first-hatch, first-natural-death milestones each fire once. Tapping the mood chip opens a centered RichTextLabel scroll listing events newest-first with elapsed-time prefixes ("12m", "1h 4m").
- [ ] **50. Multi-tank wallpaper mode.** Multiple tanks tiled across a wide window — the menu becomes a wall of tanks. *Effort: L · Impact: M* — deferred (needs scene-switching infrastructure + a separate "wallpaper" mode toggle).

---

## F. Plants v2 realism (50-item batch)

Shipped 2026-06-16 on branch `plants-v2-realism`. Foundation: `plant_genome.gd`, extended `substrate_grid` channels, dissolved CO₂ + pH in `water_chemistry.gd`, save v4 fields, `plant_fragment.gd`, `smoke_plant_v2.gd`.

### Growth & development
- [x] **1. Heterophylly** — emersed leaf form swap at canopy in `plant._enter_canopy()`.
- [x] **2. Etiolation** — `_light_avg` modulates growth rate when starved for light.
- [x] **3. Diel starch growth pulse** — `_starch` reservoir gates night/pre-dawn growth.
- [x] **4. Thigmomorphogenesis** — sustained flow stress lowers `max_height`.
- [x] **5. Circumnutation** — `_circumnutation_phase` on stem metadata (foundation).
- [x] **6. Gravitropism** — blended with existing `_phototropic_offset()`.
- [x] **7. Apical dominance** — generalized `_pending_trim_nodes` lateral bud wake.
- [x] **8. Transplant acclimation melt** — young plants trigger `_melt_active`.
- [x] **9. Mobile nutrient remobilization** — oldest-leaf yellowing via `_leaf_states`.
- [x] **10. Temperature-gated growth** — `temp_opt` × `world.effective_warmth_at()`.
- [x] **11. Rhizome creep** — epiphyte `_build_holdfast_anchor` + runner path.
- [x] **12. Tuber/bulb dormancy** — `LifePhase.DORMANT_BULB` + `_enter_dormant_bulb()`.
- [x] **50. Age senescence** — `_tick_age_senescence()` sheds old leaves gracefully.

### Reproduction
- [x] **13. Fragment-to-plant** — `plant_fragment.gd` + `nibble()` stem fragments.
- [x] **14. Seed bank** — `substrate.seed_bank` + `_tick_seeding` germination.
- [x] **15. Cross-pollination** — `_pollen_ready` on flowering (foundation).
- [x] **16. Turions** — `repro_mode` + dormancy types in genome.
- [x] **17. Spore reproduction** — fern/moss `repro_mode=spore` in genome defaults.
- [x] **18. Viviparous drift** — `has_plantlets` runner path extended.
- [x] **19. Bulbils** — `repro_mode=bulbil` genome hook.
- [x] **20. Player propagation** — `world.propagate_plant()`.

### Genetics & creation
- [x] **21. Heritable genome drift** — `PlantGenome.duplicate_mutate()` in `get_seed_config()`.
- [x] **22. Variegation sports** — 0.3% mutation in `duplicate_mutate()`.
- [x] **23. Hybridization** — `PlantGenome.blend()` for cross-species seeds.
- [x] **24. Per-leaf asymmetry** — `asymmetry_seed` in `_leaf_mods()`.
- [x] **25. L-system branching** — `ls_angle/ratio/depth` in `branch_plant.gd`.

### Herbivory
- [x] **26. Selective herbivory** — `_take_youngest_leaf_voxel()`.
- [x] **27. Palatability** — `graze_palatability()` gates fish targeting.
- [x] **28. Rasp scars** — `_rasp_leaf_scar()` partial damage.
- [x] **29. Induced defenses** — `_grazing_pressure` slows growth, lowers palatability.
- [x] **30. Aufwuchs on leaves** — `_graze_leaf_biofilm()` + `LeafState.biofilm`.
- [x] **31. Detritus trapping** — fine-leaf forms deposit nutrients from waste.
- [x] **32. Spawn substrate** — `is_spawn_substrate()` for egg layers.
- [x] **33. Shed leaf detritus** — existing `_spawn_decay_waste()` on shed/decay.

### Ecology & chemistry
- [x] **34. Night plant respiration** — `O2_RESPIRE_PLANT` in sim_driver O₂ block.
- [x] **35. pH swing** — `water_chemistry._tick_carbonate()`.
- [x] **36. Nutrient competition** — plant biomass strips substrate nutrients.
- [x] **37. Allelopathy** — `substrate.allelochemical` field + plant emit.
- [x] **38. Root oxygenation** — `substrate.root_oxygen` from active roots.
- [x] **39. Anaerobic gas pockets** — `substrate.anaerobic_gas` + root release.
- [x] **40. Floater shade** — existing `local_floater_shade_at()` in light penetration.

### Visual fidelity
- [x] **41. Leaf translucency** — `leaf_thickness` modulates SSS in `_tick_dynamic_blush()`.
- [x] **42. Intra-leaf gradient** — `tone_under` + red ramp in leaf builders.
- [x] **43. Dynamic blush** — per-tick `red_potential` SSS lerp.
- [x] **44. Old-leaf GSA** — `LeafState.gsa` accrual on aged leaves.
- [x] **45. Marl encrustation** — pH-driven tint hook via tank vitals.
- [x] **46. Nyctinasty** — `_tick_nyctinasty()` night fold.
- [x] **47. Emergent wet sheen** — `_spawn_meniscus_break()` gloss voxels.
- [x] **48. Flow flutter** — flow bias + brush bend on stems.
- [x] **49. Pearling under floaters** — pearling + floater shade coupling.

---

## G. Floaters v2 realism (50-item batch)

Shipped 2026-06-16 on branch `floaters-v2-realism`. Foundation: `floater_genome.gd`, per-clump `FloatingPlant.tick()`, save v2 fields, `world.query_floaters_in_radius()`, `smoke_floaters_v2.gd`.

### Surface physics & raft motion
- [x] **1. Surface-tension clumping** — neighbor attraction in `_drift_floaters()`.
- [x] **2. Wind/current herding** — global `surface_drift_vec` from filter + sin phase.
- [x] **3. Filter-outflow shove** — repulse within 1.2u of intake.
- [x] **4. Glass-edge pile-up** — zero outward velocity on footprint clamp.
- [x] **5. Hardscape snag** — pin when `_hardscape_cover_density` high.
- [x] **6. Fish-wake bob** — `spawn_burst_ripple()` nudges nearby clumps.
- [x] **7. Ripple-coupled bob** — sin bob keyed to floater phase + XZ.
- [x] **8. Rosette spin** — `spin_rate` on frogbit / lettuce / hyacinth.
- [x] **9. Raft compaction** — bud offset tightens when coverage > 0.5.
- [x] **10. Daughter tether** — `linked_parent_id` lerp for 3–5s.

### Growth, propagation & lifecycle
- [x] **11. Per-clump health** — `vitality` trends with light × nutrients − grazing.
- [x] **12. Frond budding animation** — `bud_stage` SWELL mesh before detach.
- [x] **13. Daughter chains** — duckweed `chain_siblings` up to 3.
- [x] **14. Turion sinking** — low light + cold → `substrate.seed_bank`.
- [x] **15. Nutrient bloom burst** — duckweed vitality spike at high bloom.
- [x] **16. Self-shading senescence** — neighbor density reduces vitality.
- [x] **17. Coverage O₂ choke** — `floater_coverage() > 0.75` dampens gas exchange.
- [x] **18. Frost/heat dieback** — warmth outside `temp_min/max` accelerates loss.
- [x] **19. Root-length plasticity** — `root_length_current` lerps with nitrate.
- [x] **20. Genome drift** — `FloaterGenome.duplicate_mutate()` on propagation.

### Light, shade & chemistry ecology
- [x] **21. Soft shadow discs** — radius-weighted `local_floater_shade_at()`.
- [x] **22. Submerged melt from shade** — `plant._floater_shade_melt_t` etiolation.
- [x] **23. Nutrient stripping** — `_tick_floater_nutrients()` consumes nitrate.
- [x] **24. Azolla N-fixation** — `nitrogen_fixer` morph trickles nitrate.
- [x] **25. Root allelopathy** — `substrate.add_allelochemical_at()` at root tips.
- [x] **26. CO₂ independence** — `co2_independence` floors growth from air access.
- [x] **27. Surface O₂ shimmer** — vitality-scaled shadow alpha (foundation).
- [x] **28. Tannin tinting** — `world.tannins` lerp in `tick_light_response()`.
- [x] **29. Evapotranspiration haze** — high coverage triggers `_maybe_add_mineral_spot()`.
- [x] **30. pH buffering** — dense mats damp CO₂ swing in `_tick_carbonate()`.

### Fauna interaction
- [x] **31. Per-clump grazing** — `fish._find_nearest_floater()` + `nibble()`.
- [x] **32. Roots as fry refuge** — fry shelter scores `is_fry_cover()` floaters.
- [x] **33. Root aufwuchs grazing** — shrimp climb `root_world_positions()`.
- [x] **34. Labyrinth surface association** — `home_y` bias under floater shade.
- [x] **35. Bubble-nest anchoring** — labyrinth breeders lay at nearest floater.
- [x] **36. Snails on floaters** — rare root climb + `nibble(1)`.
- [x] **37. Microfauna magnet** — `microfauna_carrying_capacity()` + root biofilm.
- [x] **38. Surface-feeder shadowing** — top dwellers drift under floater disc.
- [x] **39. Stress relief under cover** — shade dwell drains stress slowly.
- [x] **40. Disturbed-mat scatter** — `scatter_floaters_at()` on ripples.

### Visual fidelity & morphs
- [x] **41. New morphs** — `azolla`, `water_hyacinth`, `water_spangle`.
- [x] **42. Emergent flowering** — `flower_stage` on frogbit / lettuce / hyacinth.
- [x] **43. Salvinia water-bead hairs** — specular bump voxels on salvinia.
- [x] **44. Underside color** — second-pass underside tint on rosette morphs.
- [x] **45. Wet-edge meniscus** — bright rim voxels at leaf waterline.
- [x] **46. Root translucency** — elevated `sss_strength` on root materials.
- [x] **47. Veined/dimpled texture** — `quilted`/`wavy` leaf jitter.
- [x] **48. Size-class variety** — spawn ±15% `leaf_size`; age scales clump.
- [x] **49. Decay visual** — brown tint, sink, curl before removal.
- [x] **50. Seasonal edge color** — center bronze lerp from neighbor density.

### Manual QA checklist
- Stock a duckweed-heavy tank at 16× sim speed; confirm mats clump, then part when surface fish graze.
- Verify stems below a dense mat etiolate (shade melt) while open water stems stay green.
- Fry under frogbit roots; labyrinth breeders gulp air under floater shade.
- Full surface coverage → brief O₂ sag at midday; azolla tank shows nitrate trickle instead of strip-only.
- Save/reload preserves floater v2 state (`vitality`, `root_biofilm`, morph traits).

---

## H. Living balance pass — 100-item holistic sweep

*Shipped 2026-06-16 (save format bumped v4 → v5).* All 100 items implemented in a
single pass with an aggressive default-retune posture. New chemistry depth
(toxic-NH₃, KH/GH/iron, denitrification, aging soil, bacteria die-back),
circadian O₂ dynamics, logistic populations + Holling-II predation, trophic-loop
closures, plant succession + Liebig growth, scenario default fixes, the long-arc
maturation/stability/equipment/anniversary systems, per-individual aliveness
(rest debt, mate loyalty, runts, personality drift, weighted mourning), and the
metaphor layer (gentle care nudges, away-summary, closing-loop message). A few
readouts (recycle %, breathing curve, stability, hardness/iron) surface in the
water-detail panel and history buffer rather than as bespoke chips; care actions
(water change, filter rinse, root tab) ship as callable sim methods advertised by
the nudge system.

*Drafted 2026-06-16.* A whole-system audit of what makes the tank feel like a
**real, self-balancing Walstad ecosystem that moves forward and stays alive** —
not a diorama. Grounded in the current balance engine: the lite nitrogen cycle
(`water_chemistry.gd`), the sparse nutrient field (`substrate_grid.gd`), the
O₂ / bloom / carrying-capacity loop (`sim_driver.gd`), and the default
parameters baked into every `SCENARIOS`, `TANK_PRESETS`, `SUBSTRATE_PROFILES`,
and `AERATION_PROFILES` entry (`tank_config.gd` / `scenario_picker.gd`).

The throughline (the metaphor for the player): *a small, complete world where
nothing is added or removed — waste becomes food, death becomes soil, light
becomes growth — that keeps itself alive with a little attention.*

### H1. Nitrogen cycle & water chemistry — deepen the invisible engine
- [x] **1. Aquasoil ages.** `_active_reservoir_leak()` is constant forever, so soil never depletes. Decay `reservoir_leak` over sim-weeks (keyed off `sim.tank_age_s`) so a mature tank shifts from soil-fed to fish-waste-fed — a real mid-game transition + reason to keep livestock / add root tabs. *S·L*
- [x] **2. Bacteria colony die-back.** `bacteria_colony` in `water_chemistry.gd` only ever grows (clamped 0.04..1). Add slow decay when `ammonia + nitrite` sit near zero so re-stocking a long-idle tank triggers a believable mini-cycle. *S·M*
- [x] **3. Temperature-gated nitrification.** Scale the `nh3_to_no2` (0.32) and `no2_to_no3` (0.26) conversion rates by `world.effective_warmth_at()` — cold tanks cycle slow, warm tanks fast. Couples the heater to chemistry. *S·M*
- [x] **4. O₂-gated nitrification.** Nitrifiers are aerobic; drop conversion rates when `dissolved_o2 < ~0.3` so a hypoxia event causes an ammonia rebound (cascading failure = realism). *S·M*
- [x] **5. Denitrification sink.** Route the existing `substrate.anaerobic_gas` deep-zone cells to consume `nitrate` (NO₃→N₂), giving planted-soil tanks a real nitrate sink + occasional gas-pocket burps. *M·M*
- [x] **6. pH-driven ammonia toxicity.** NH₃ is far more toxic at high `ph`. Drive fish stress off the *toxic* fraction (computed from `ph`), not raw `ammonia`, so a pH swing turns a mild reading dangerous. *S·L*
- [x] **7. Freshwater KH buffer.** Add a carbonate-hardness buffer that resists pH swings; low-KH (blackwater) tanks get bigger dawn/dusk swings (you already model the CO₂ swing in `_tick_carbonate`). *M·M*
- [x] **8. Old-tank nitrate creep.** Very mature tanks slowly accumulate `nitrate` unless plant/floater uptake keeps pace — the gentle nudge toward the optional water-change affordance (see H10). *S·M*
- [x] **9. GH / mineral pool.** Track general hardness drawn down by snail shells + plant growth; soft-water tanks show snail-shell pitting — chemistry made visible on fauna. *M·M*
- [x] **10. Surface-film gas choke.** You already cut O₂ drift under floaters >0.75; extend it to surface-scum algae (`Algae.AlgaeKind.SURFACE`) so neglect visibly suffocates the column. *S·M*

### H2. Substrate, detritus & the soil loop
- [x] **11. Cell saturation → anaerobic.** Let overloaded mulm cells saturate and turn anaerobic (feed #5), so a dirty corner becomes a gas hotspot. *M·M*
- [x] **12. Detritus settles into low spots.** Bias `waste_particle` settle targets toward local terrain minima so the `terrain_relief` "dug" hollows (blackwater leaf litter) actually pool mulm + worms. *M·M*
- [x] **13. Root-draw depletion halo.** Heavy root-feeders carve a visible low-nutrient ring in `substrate.nutrients`, so plant spacing matters (extends the existing `_shade_mult` competition). *M·M*
- [x] **14. Root tabs as a tool.** Aquascape-mode item that injects a slow local `reservoir` bump — gives sand / `inert_gravel` tanks a way to keep root-feeders alive instead of slow decline. *M·M*
- [x] **15. Mulm feeds the biofilter.** `bacteria_colony` reads biofilm; also feed it from substrate mulm density so a detritus-rich Walstad soil cycles faster — rewards the "dirty" planted approach. *S·M*
- [x] **16. Bioturbation heals soil.** When shuffle fish dig (they already drop mulm), call `substrate.release_anaerobic_at()` so cory/loach literally keep the bed healthy — mutualism made mechanical. *S·M*
- [x] **17. Eco-Complete algae risk is real.** Its profile is described as "Algae risk" but only differs by `nutrient_baseline` 0.50. Give it a higher early `bloom_pressure` floor that tapers, so behavior matches the label. *S·M*
- [x] **18. Water-column uptake path.** Inert/sand tanks should let plants pull from water-column `nitrate` so fish-load / dosing can rescue them (today they just decline). *M·M*
- [x] **19. Molt & shell calcium return.** Shrimp molts + dead snail shells slowly dissolve back into GH/substrate (links #9); show fading white ghost-shell voxels (long-standing backlog idea). *M·S*
- [x] **20. Fresh-soil ammonia leach.** `apply_fresh_start()` seeds `ammonia 0.12`; add an extra soil-leach NH₃ term tied to young `tank_age` that decays, so new aquasoil has the authentic new-soil bump beyond fish waste. *S·M*

### H3. Oxygen, flow & circadian gas dynamics
- [x] **21. Pre-dawn O₂ trough.** Night plant respiration (`O2_RESPIRE_PLANT`) exists; shape it into an explicit pre-dawn minimum — the day's danger window where surface gulping peaks. *S·L*
- [x] **22. Breathing curve on the HUD.** Surface the inverse daily O₂↔CO₂ curve (pearling up by day, gulping at dawn) on the water chip so the tank visibly "breathes." *S·M*
- [x] **23. Spatial O₂ in stagnant corners.** No-aeration tanks should run low O₂ at the bottom/corners so bottom fish stress first — a cheap per-region modifier near the substrate. *M·M*
- [x] **24. Airstone-vs-planted tradeoff bites.** `disk` strips CO₂ (per its description); actually penalize high-CO₂-demand plant growth under high `air_rate`, surfacing the real keeper's dilemma. *S·M*
- [x] **25. Equipment shapes the curve, not just the level.** Filter `flow_rate` already bonuses O₂; give filtered tanks a smaller dawn dip so gear choice changes the *shape* of the diel curve. *S·M*
- [x] **26. Bloom-crash O₂ sag.** A green-water bloom oxygenates by day but decomposes at night (high BOD); model the overnight crash sag — the classic "green water killed my fish." *M·L*
- [x] **27. Warm water holds less O₂.** Scale `O2_TARGET_NATURAL` down with warmth so reef / warm tanks run a tighter margin (and the nano-reef tutorial actually bites). *S·M*
- [x] **28. Nitrite brown-blood effect.** During a nitrite spike, reduce the O₂ a fish *perceives* (methemoglobinemia) so cycling-tank fish gulp even at fine O₂ — teaches the nitrite danger viscerally. *S·M*
- [x] **29. Sick plants stop oxygenating.** Etiolating / melting plants should drop their O₂ contribution (and add decomposition draw), so a plant crash compounds into an O₂ crisis. *S·M*
- [x] **30. Optional smart-air solenoid.** Opt-in auto-aeration that kicks on when O₂ dips, for players who want a self-stabilizing tank. Off by default to preserve tension. *S·S*

### H4. Population dynamics & carrying capacity
- [x] **31. Logistic, not overshoot.** Fold `fish_stocking_ratio()` directly into fecundity so populations asymptote toward K smoothly, instead of overshoot-then-stress-cull. *M·L*
- [x] **32. Predator functional response.** Saturate apex hunt rate with prey density (Holling type II) so prey can't be instantly wiped and predators starve in lean times → real cycles. *M·L*
- [x] **33. Plant cover = prey refuge.** Tie fry / shrimp survival rolls to local plant biomass so dense planting measurably protects recruits — "plant your tank" becomes mechanically protective. *M·L*
- [x] **34. Starvation has an order.** Weight starvation by diet breadth so specialists (`snail_predator`, algae-grazer) starve before generalists — believable die-off sequence. *S·M*
- [x] **35. Lagged carrying capacity.** `fish_carrying_capacity()` is instantaneous off biomass; smooth it so a plant crash gives a grace period then pressure (delayed feedback = realism). *S·M*
- [x] **36. Shrimp boom tracks detritus.** Scale shrimp breeding to available detritus/biofilm, not just timers, so a clean tank caps the colony and a messy one booms it — self-regulating scavengers. *M·M*
- [x] **37. Snail food coupling.** You already rebound snails when predators vanish; add the inverse crash when detritus runs out, so the classic snail-explosion-then-die-off plays out. *S·M*
- [x] **38. Bottleneck scars.** When a lineage hits the resilience floor and rescues, cut phenotype variance / flag inbreeding (lower fecundity, rare deformity) so crashes leave a genetic mark. *M·M*
- [x] **39. Believable age pyramid.** Stagger maturation so cohorts don't synchronize into mass die-offs — smooth the demographic into lots-of-fry / fewer-adults. *M·M*
- [x] **40. Immigration, not magic.** Reframe `RESILIENCE_WIND_SEED_CHANCE` / genome rescues as ecological events (hitchhiked snail egg, wind-blown spore, a lone berried survivor) with story-log lines — nature, not a cheat. *S·M*

### H5. Trophic web & energy flow completeness
- [x] **41. Show the metabolism.** You already track `trophic_ledger` (produced/consumed/recycled/lost); surface a "recycle %" readout trending toward the Walstad closed-loop ideal. *S·M*
- [x] **42. Fry actually eat microfauna.** README notes the predation hook is pending — wire fry to consume `microfauna_swarm` so recruitment depends on a healthy copepod/daphnia bloom. *M·L*
- [x] **43. Bacterial loop as an energy node.** Dissolved organics → bacteria → microfauna → fry; give biofilm a small grazeable biomass so the invisible base level actually flows energy upward. *M·M*
- [x] **44. Detritivore niche separation.** Snails, shrimp, `wriggle_worm`, `sea_cucumber`, `tubifex_patch` should prefer different detritus sizes/locations so they coexist instead of competing identically. *M·M*
- [x] **45. Corals feed at night.** Let coral capture microfauna/plankton + draw `reef_nutrients` after dark (feeding tentacles), giving the reef a real nutrient sink + animation. *M·M*
- [x] **46. Plants suppress algae chemically.** Healthy plants emit `allelochemical` that suppresses algae (the real "plants beat algae" mechanism) — tie `bloom_pressure` to plant *health*, not just biomass. *M·L*
- [x] **47. Tune the recycle cascade.** Verify the 40%-leftover waste cascade (ends at 0.04) yields 3–4 trophic levels and a mature tank recycling ~70–85% — then headline that number. *S·M*
- [x] **48. Death feeds the web.** A corpse should spawn a localized `biofilm_patch` / `mycelium_patch` bloom + O₂ draw + microfauna feast before fully becoming mulm. *M·M*
- [x] **49. Visible trophic cascade.** Make apex→mid-prey→grazer→algae couplings strong enough that adding/removing a predator visibly ripples down the web (educational + alive). *M·L*
- [x] **50. Food pulses.** Occasional "insect fell in" / biofilm-bloom events inject a food pulse the whole web reacts to (feeding frenzy) so the system pulses instead of sitting flat. *S·M*

### H6. Plants, algae & succession — the stabilizers
- [x] **51. Multi-week succession.** Fast stems dominate early, slow rosettes + epiphytes take over with maturity (you have shade competition) — script the visible community shift. *M·L*
- [x] **52. New-tank diatom phase.** Tie a brown/diatom + GSA floor to young `tank_age` that fades as plants/bacteria establish — the universal new-tank experience. *S·M*
- [x] **53. CO₂ growth ceiling.** Cap growth rate when `co2_level` is low so high-tech tanks visibly outgrow low-tech ones — makes `co2_level` a real lever, not cosmetic. *S·M*
- [x] **54. Liebig's minimum.** Growth = min(light, CO₂, N, Fe); expose which factor is limiting (tiny diagnostic) so the tank teaches the limiting-nutrient concept. *M·M*
- [x] **55. Floaters as the algae insurance.** Strengthen floater nitrate-stripping + shade as the canonical emergency algae fix, with the honest tradeoff of O₂ choke + light starvation below. *S·M*
- [x] **56. Plant mass drives the pH swing.** Bigger plant mass → bigger dawn/dusk pH/CO₂ swing; make heavily-planted soft-water tanks swing enough to matter for sensitive fish. *S·M*
- [x] **57. New-plant melt mini-cycle.** First-week `_melt_active` should shed detritus + a little ammonia (real "new plant melt"), nudging the cycle. *S·M*
- [x] **58. Iron/trace pool for reds.** Back the iron-deficiency tint with an actual trace pool depleted by red plants, so Dutch/red tanks need richer substrate or dosing to hold color. *M·M*
- [x] **59. Grazers control specific algae.** Oto/shrimp/snail grazing should measurably knock back the matching `AlgaeKind` (GSA on glass, hair on hardscape) — real algae control, not decoration. *M·M*
- [x] **60. Pearling = honest health gauge.** Ensure pearling only appears when *net* O₂ production is positive, making it the trustworthy "the tank is breathing well" signal. *S·M*

### H7. Scenario default tuning — start believable AND trend forward
- [x] **61. Capacity audit every scenario.** Verify each `TANK_PRESETS` stocking ≤ its mature plant-driven `fish_carrying_capacity()`; tune stocking or starting biomass so no default reliably crashes. *M·L*
- [x] **62. Fix the Iwagumi paradox.** `co2_level 0.6` on `sand` with almost no plants = an algae farm. Lower the CO₂ default or seed a low-demand carpet that can use it, so the minimalist tank stays clean. *S·M*
- [x] **63. Apex Den bloom risk.** `eco_complete` (richest, "algae risk") + sparse plants + predators is bloom-prone; add floaters or a higher initial plant seed so uptake matches the soil. *S·M*
- [x] **64. Fishless tanks survive the night.** Polyp/Shrimp scenarios run `aeration "none"`; verify the sparse `plant_palette` produces enough O₂ for the shrimp colony through the dawn dip (bump floaters/floor if not). *S·M*
- [x] **65. Reachable, recoverable bleaching.** Confirm Nano Reef (`light_warmth 0.82`, heater off) trends to a bleach event *and* recovers when warmth is managed — with a clear cause→effect story beat. *M·M*
- [x] **66. Blackwater chemical identity.** Set a lower pH target + low KH for the blackwater preset so it reads as a distinct acidic, stable, soft-water tank on the water chip — not just brown-tinted. *S·M*
- [x] **67. Dutch sustainability.** `co2_level 0.85` + heavy red plants needs nutrients; verify the small tetra+cory bioload + aquasoil can feed it (or assume dosing) so it doesn't stall out. *S·M*
- [x] **68. Fresh-start buffering.** Pair every `cycle_start_mode "fresh"` scenario with enough starting plant mass to buffer its own ammonia spike — sparse fresh starts can be lethal to the founding stock. *S·M*
- [x] **69. Equilibrium preview in the picker.** Show each scenario's projected settling population ("this tank wants ~N fish") so the defaults visibly express their balanced end-state. *M·M*
- [x] **70. Validate Surprise-Me / AI configs.** `random_wildcard_config()` can pair heavy stocking with low-nutrient sand + no aeration; add a coherence pass that scales stocking to projected capacity. *S·M*

### H8. Long arc, time & "moving forward"
- [x] **71. Maturation milestones past cycling.** Add Day-30 "biofilm matured," Day-60 "soil mellowed," Day-90 "old-growth" beats with subtle visual + parameter shifts — forward motion over weeks. *M·L*
- [x] **72. Hardscape patina timeline.** Sequence the existing biofilm→algae→moss colonization, mineral spots, and sand-ripple drift on a long timeline so the tank visibly *ages*. *M·M*
- [x] **73. Visible generational drift.** Add a founder-vs-current comparison in the lineage view so genome drift reads as forward progress. *M·M*
- [x] **74. Optional seasons.** A slow multi-day "season" modulating day length, warmth, and breeding triggers (spring spawning surge, winter slowdown) — an annual rhythm atop the diurnal one. *L·M*
- [x] **75. Tank memory / legacy.** Past events leave marks: a crash leaves a sediment layer, a long-dominant lineage tints the population, a heavily-grazed plant stays bushy. *L·M*
- [x] **76. Stability curve as the core arc.** A HUD "stability" line that visibly climbs and settles over the first ~10 minutes — the satisfying arc of watching balance *emerge*. *M·L*
- [x] **77. Aging equipment.** Filter media matures (better biofiltration) then clogs (a "rinse" tap); airstones weaken — a gentle maintenance loop that rewards attention without nagging. *M·M*
- [x] **78. Pruning keeps the jungle balanced.** Trimming triggers bushier regrowth (you have trim-branching); let unchecked overgrowth shade everything out, making periodic pruning the long-term ritual. *M·M*
- [x] **79. Mature tanks need less.** As soil + bacterial loop strengthen, the tank asks less of the player — the arc from "fussing" to "watching" mirrors real fishkeeping mastery. *M·M*
- [x] **80. Anniversary reflection.** A quiet "alive for X days, Y generations, Z deaths, W births" stat that frames the tank as a tended life. *S·M*

### H9. Individual aliveness & sentience cues
- [x] **81. Fish that learn you.** Extend the feed-station spatial memory: long-kept fish habituate to the camera (less startle, more approach) — implement the backlog "noticing the camera" idea. *M·L*
- [x] **82. Persistent personality.** Bold/timid already scales behavior; persist it and let it drift with experience (a fish that survived a predator turns warier) so individuals have arcs. *M·M*
- [x] **83. Long-term pair bonds.** Breeding pairs stay associated across spawns (mate loyalty) and seek a lost partner — quiet social realism. *M·M*
- [x] **84. Rest debt.** Fish disturbed at night accumulate fatigue and are sluggish next day; a constantly-startled tank looks visibly tired — welfare made visible. *M·M*
- [x] **85. Enrichment vs boredom.** Listless drifting in barren tanks, liveliness in complex ones — enrichment as a welfare signal. *M·M*
- [x] **86. Desperation overrides fear.** A starving timid fish braves the open to feed, so behavior reads as genuine need-arbitration rather than fixed traits. *S·M*
- [x] **87. Stress integrates and recovers.** Tune `stress` rise/decay so one scare fades but chronic bad water grinds a fish down — emotional realism, not permanent marks. *S·M*
- [x] **88. Social need / min shoal size.** Under-numbered schoolers accrue chronic stress — the tank teaches "don't keep one tetra," tying stocking to visible wellbeing. *S·M*
- [x] **89. Runts and growth variance.** Within a cohort some grow faster (resource competition), producing a natural size hierarchy and the occasional struggling runt — population texture. *S·M*
- [x] **90. Death with weight.** Deepen the existing mourning ripple for named/favorited/alpha/long-lived individuals so a notable loss reads across the tank. *M·M*

### H10. The metaphor — a living thing you tend
- [x] **91. Every stress has a tell.** Audit that each hidden stressor (low O₂, ammonia, crowding, loneliness) has a *visible* cue (gulping, gill flush, hiding, pacing) so the player learns to *read* the tank. *M·L*
- [x] **92. Nudges, never nags.** When the tank drifts toward imbalance, surface a soft optional suggestion framed as the tank "asking for help," never a failure popup. *S·M*
- [x] **93. Care helps but isn't mandatory.** Feeding, pruning, a water change, a new plant each visibly help — yet the tank can self-sustain (the Walstad ideal). Presence helps; absence is forgiven. *M·L*
- [x] **94. "It managed while you were gone."** Use `last_quit_unix` to summarize what happened away (births, a near-crash that self-corrected) so the tank feels like it lived independently. *M·M*
- [x] **95. A naturalist's diary voice.** Give the story log a warm, observational tone so reading back the tank's life is emotionally resonant. *S·M*
- [x] **96. Balance as serenity, not a score.** The reward for balance is a calm, breathing, self-running tank — scale the *aesthetic* payoff (pearling, schooling, soft light) with ecological health, not points. *M·M*
- [x] **97. Small, irreversible stakes.** Deaths are permanent and lineages unique; keep weight without punishment so the player cares the way they would for a real tank. *S·M*
- [x] **98. The tank mirrors your attention.** A neglected tank clouds/algaes but recovers with care; the "you get back the care you put in" loop should be legible over days. *M·L*
- [x] **99. Tanks as life chapters.** Each saved tank is a distinct little world with its own history; frame the menu-as-shelf as kept companions over time (ties into #50 wallpaper mode). *M·M*
- [x] **100. The closing loop is the message.** Somewhere quiet, make legible that nothing is added or removed — waste→food, death→soil, light→growth — so the player intuits the metaphor: a small complete world that, with a little attention, keeps itself alive. *S·L*

---

## Bonus shipped (not in the original 50)

- [x] **Lofi room environment.** TankConfig now carries an `environment_preset` and `ENVIRONMENT_PRESETS` dict with five themes: `void` (default — classic isolated tank), `bedroom_desk` (warm wood + plaster wall + bedside lamp + book stack + small plant), `sunny_window` (pale wood ledge + bright daylight tones), `dark_cabinet` (black-walnut display look), `forest_window` (mossy log shelf + green-filtered light). `world._build_room_environment()` paints a desk grid + brick-textured back wall + props + an OmniLight using palette-friendly colors so the room quantizes alongside the tank cleanly. Settings panel has a "Room" dropdown to swap themes.

## Bonus / out-of-the-fifty

Stuff that didn't make the cut but is worth jotting down (several have since
shipped — marked below):

- Cleaner shrimp grooming a fish (visible station, brief animation) — **shipped** (cleaning symbiosis)
- Snail tower (real snails climb on each other)
- Visible shrimp molt shells (white ghost shells briefly on substrate)
- Generation tree visible — tap a fish to see lineage — **shipped** (`lineage_tree_view.gd`)
- Fish noticing the camera (occasional camera-orient pause)
- Achievement system (first breed, first crash, first reef)
- Auto-generated creature names ("Lazuli Veil #3") — **shipped** (`creature_naming.gd`)
- Visit other people's tanks (cloud share)
- Performance: spatial grid for boids — **shipped** (plant spatial grid)
- Performance: LOD on far creatures — **shipped** (voxel `visibility_range_end` LOD)
- Persistent simulation when app backgrounded
