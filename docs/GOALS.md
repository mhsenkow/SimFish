# Vivarium — Goals & Ideas Backlog

A working checklist of things we *could* do to push Vivarium further toward
the Walstad-style hyper-realistic ecosystem feel.

**How to use this doc:**
- Each item is small enough to be a session of work, or grouped under a feature
  flag if larger.
- Effort: **S** (≤2h), **M** (half-day), **L** (full day+).
- Impact: **S** (polish), **M** (noticeable), **L** (transforms how the tank feels).
- Check items off as you ship them; add new ones as they come up.

Last reviewed: see git log on this file.

---

## A. Motion & behavior

Real fish do tiny things constantly — gill flares, eye darts, brief pauses to
look at things. Each one is small but the cumulative effect is the difference
between "voxels swimming around" and "creatures alive in a tank."

- [ ] **1. Surface gulping when O₂ low.** Fish swim to the meniscus and bob — already simulated O₂, just missing the visible response. *Effort: M · Impact: L*
- [ ] **2. Hide-in-plants stress response.** When stress > 0.7, steer toward nearest plant cluster and hold position inside it. *Effort: M · Impact: M*
- [ ] **3. Inspection behavior.** Fish briefly orient toward and pause near new objects (a newly placed stone, dropped food, the camera if it gets close). *Effort: M · Impact: L*
- [ ] **4. Gill-flare at rest.** Subtle scale pulse on the head when speed ≈ 0; reads as breathing. *Effort: S · Impact: S*
- [ ] **5. Eye saccades.** Small random yaw of an eye sub-mesh every few seconds when alert. *Effort: S · Impact: S*
- [ ] **6. Juvenile play / chase.** Fry chase each other in short bursts — pure social motion, no foraging objective. *Effort: M · Impact: M*
- [ ] **7. Sleep state at night.** Diurnal fish drift into plant cover and slow to almost-stop at deep night. Already partly handled by the day/night activity multiplier; needs the "find shelter first" step. *Effort: M · Impact: L*
- [ ] **8. Tap-glass startle.** Player tap on the tank glass triggers a flee burst from nearby fish. *Effort: S · Impact: M*
- [ ] **9. Surface skim feeding.** Top-dwellers (killifish, danio) gulp at the meniscus when food drifts there. *Effort: M · Impact: M*
- [ ] **10. Substrate dig.** Corydoras + mudsifters briefly nose-down + kick up a tiny mulm puff while shuffling. *Effort: S · Impact: M*

## B. Breeding & lifecycle

The reproduction loop is the heart of an ecosystem sim. Each visible step
sells the "this is alive" feeling.

- [ ] **11. Intensifying courtship display.** Color pulse + fin spread ramps over the courtship window so the spawn moment reads as a flash. Some of this exists; needs tuning. *Effort: M · Impact: M*
- [ ] **12. Mouthbrooder egg-carry.** Selected cichlid-likes carry visible eggs in the throat for the incubation period. *Effort: L · Impact: M*
- [ ] **13. Fry-in-plants shoaling.** Fresh fry seek the densest plant patch and shoal there until juvenile. *Effort: M · Impact: L*
- [ ] **14. Adult coloration deepening with age.** Juveniles slightly desaturated, adults full vivid. Currently jumps; should be gradual. *Effort: S · Impact: M*
- [ ] **15. Live-bearer pregnancy bulge.** Guppy females visibly grow rounder before birth. Already partly modeled; needs animation curve. *Effort: S · Impact: M*
- [ ] **16. Sterile / hybrid genetic flag.** Some crossed pairs produce non-viable eggs that simply don't hatch — adds genetic realism. *Effort: M · Impact: S*
- [ ] **17. Parental clutch guarding.** Egg-laying species defend their eggs from passing fish for the incubation window. *Effort: M · Impact: L*
- [ ] **18. Pheromone trails during heat.** Subtle particle trail from a receptive female that nearby males can follow. *Effort: M · Impact: M*
- [ ] **19. Species-tinted egg color.** Eggs currently look identical; tinting them per-species sells the variety. *Effort: S · Impact: S*
- [ ] **20. Per-species mating dance.** Each species gets a distinct courtship choreography (spiral, parade, vertical bob, parallel cruise). *Effort: L · Impact: L*

## C. Food web & ecology

The trophic loop is already wired — these add visibility and dynamics.

- [ ] **21. Algae bloom dynamics.** When nutrients spike + plant biomass low, water gradually tints green; balance shift crashes it back. *Effort: L · Impact: L*
- [x] **22. Microfauna (copepods, daphnia).** Tiny moving white dots, snack food for fry. *Effort: M · Impact: L* — `microfauna.gd`; 90 drifting individuals refilled by `world._maintain_microfauna()`; two visual variants (copepods + paler-blue daphnia). Eaten by the filter intake currently; full predation hook still pending.
- [ ] **23. Tap-to-feed.** Tap the tank surface to drop a flake cloud; fish converge from below. *Effort: M · Impact: L*
- [x] **24. Substrate worms.** Visible squirms in mulm patches — visual proof of the detrital loop. *Effort: M · Impact: M* — `wriggle_worm.gd`; two-segment voxel with head-leading phase wave; population scales with mulm carpet density.
- [x] **25. Plant flowering events.** Lily pads, cattails, and emergent plants occasionally bloom for a few minutes. *Effort: M · Impact: M* — already present: lily_pad has full 6-petal bloom lifecycle, cattails have seed-head puffing, base plant.gd has bud→opening→mature→seed-pod stages inherited by spiral/branch plants. Tuning per species is open work.
- [x] **26. Filter intake suction.** Particles within ~0.5 units of the filter intake drift toward it. *Effort: S · Impact: M* — `sim.filter_intake_pos` published by `world._build_filter_aerator()`; Microfauna accelerates toward intake within `FILTER_PULL_RADIUS` and despawns on contact. Waste particles still ignore it (they settle too fast for the pull to read).
- [x] **27. Tannin staining from driftwood.** Wood pieces slowly tint the water tea-brown over hours. *Effort: M · Impact: M* — already present: `world.tannins` rises slowly in `_process` and lerps the water material toward a warm brown.
- [ ] **28. Predator–prey rebound cycles.** When a snail-hunter dies, snails boom; when puffers eat snails too fast, puffer starves. Track these explicitly. *Effort: M · Impact: M*
- [ ] **29. Plant nutrient competition.** Fast-growing stems crowd out slow rosettes when nutrients are limited. *Effort: L · Impact: M*
- [ ] **30. Population history graph.** Tap a stat chip to see a 24h sparkline of that population. *Effort: M · Impact: M*

## D. Plants, substrate, hardscape

Plants drive the Walstad balance — they're what makes the tank stable. Make
them visibly alive.

- [ ] **31. Plant melt animation.** When a plant dies of starvation, leaves yellow then curl then detach as detritus over ~30s rather than vanishing. *Effort: M · Impact: L*
- [ ] **32. Visible root spread.** Thin voxel roots emerging just below substrate around root-feeders (swords, crypts). *Effort: M · Impact: M*
- [ ] **33. New-leaf unfurl.** Fresh leaves spawn rolled up and unfurl over a few seconds. *Effort: M · Impact: M*
- [ ] **34. CO₂-deficiency pose.** Pale, curled leaf tips when light is high but plant growth is stalled. *Effort: S · Impact: S*
- [ ] **35. Carpet plant runner propagation.** Foreground carpet plants (dwarf hairgrass, monte carlo) send out lateral runners that root and sprout. *Effort: L · Impact: L*
- [ ] **36. Floating species.** Duckweed / frogbit / red root floaters drifting on the surface, blocking light below — emergent shade. *Effort: L · Impact: L*
- [ ] **37. Iron deficiency yellowing.** Stem plants in low-iron substrate develop a yellow tinge specifically at the new growth. *Effort: S · Impact: S*
- [ ] **38. Pearling intensity ↔ health.** Pearling already exists; tune it to scale with biomass + light + dissolved O₂ saturation. *Effort: S · Impact: M*
- [ ] **39. Substrate dig disturbance.** Corydoras / loach digging leaves a brief visible divot in the substrate that re-settles. *Effort: M · Impact: M*
- [ ] **40. Driftwood biofilm.** Fresh driftwood develops a fuzzy white biofilm for the first week, then settles. Shrimp + otos graze it. *Effort: M · Impact: M*

## E. Environment & atmosphere

The medium itself — water, light, surface, sound — sells the immersion.

- [ ] **41. Surface ripples from fish darts.** A fast direction change near the surface produces a small expanding ripple. *Effort: M · Impact: L*
- [ ] **42. Visible current particles.** Subtle dust motes drifting along the flow vectors from the filter return. *Effort: M · Impact: M*
- [ ] **43. Mineral spots on glass.** Over hours, faint white speckle appears on glass at the waterline. Cleared by a manual "wipe" gesture. *Effort: M · Impact: S*
- [ ] **44. Surface caustics.** Light pattern scrolling across the substrate, sourced from a wavy surface mesh. *Effort: L · Impact: L*
- [ ] **45. Day/night ambient audio crossfade.** Morning birds, midday quiet, evening cricket / cicada layer through the speakers behind the tank. *Effort: M · Impact: L*
- [ ] **46. Heater glow.** A small visible heater rod with a faint warm light pulse. *Effort: S · Impact: S*
- [ ] **47. Tank-condition mood indicator.** A subtle UI chip showing tank "vibe" — Thriving / Cycling / Stressed / Crashing — based on aggregate metrics. *Effort: M · Impact: M*
- [ ] **48. Walstad cycle phase.** "Day 3: ammonia spike" / "Day 14: nitrites" / "Day 28: cycled" labels with appropriate algae behavior per phase. *Effort: L · Impact: L*
- [ ] **49. Tank story log.** Auto-generated diary entries: "Day 5: glassdart pair formed" / "Day 12: first hatch" / "Day 18: betta lived 8 days, died of old age." *Effort: M · Impact: L*
- [ ] **50. Multi-tank wallpaper mode.** Multiple tanks tiled across a wide window — the menu becomes a wall of tanks. *Effort: L · Impact: M*

---

## Bonus / out-of-the-fifty

Stuff that didn't make the cut but is worth jotting down:

- Cleaner shrimp grooming a fish (visible station, brief animation)
- Snail tower (real snails climb on each other)
- Visible shrimp molt shells (white ghost shells briefly on substrate)
- Generation tree visible — tap a fish to see lineage
- Fish noticing the camera (occasional camera-orient pause)
- Achievement system (first breed, first crash, first reef)
- Auto-generated creature names ("Lazuli Veil #3")
- Visit other people's tanks (cloud share)
- Performance: spatial grid for boids
- Performance: LOD on far creatures
- Persistent simulation when app backgrounded
