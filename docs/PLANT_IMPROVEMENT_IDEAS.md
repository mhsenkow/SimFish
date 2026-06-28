# Plants — 50 Improvement Ideas

*Drafted 2026-06-26. Director's brief for the plant pass.*

The brief: lily pads "just sit there" (keep the concept — it's good — but make
them **alive**), and overall plant growth feels off / "not growing well enough."

This doc is the idea backlog. Each item is grounded in the current code with
file/line pointers so it can be picked up directly. Format follows
[GOALS.md](GOALS.md): **Effort** S (≤2h) / M (half-day) / L (full day+),
**Impact** S (polish) / M (noticeable) / L (transforms the feel).

> **Note for the implementer:** the plant system is already *very* deep — see
> GOALS.md sections D, F (Plants v2, 50 items), G (Floaters v2, 50 items), and
> H6 (succession). Almost all of that shipped. So most of what's below is about
> **fixing regressions, retuning, and adding life/legibility** — not new
> subsystems. Don't rebuild what's there; tune and animate it.

---

## Diagnosis first — the two root causes I found

Before the 50, here's *why* it feels worse. These two findings explain both
complaints and several ideas below build directly on them.

### Cause A — Lily pads have literally zero animation code

[`lily_pad.gd`](../shaders-godot/godot-project/scripts/lily_pad.gd) is a
standalone `Node3D` (NOT a `Plant` subclass), and its
[`tick()`](../shaders-godot/godot-project/scripts/lily_pad.gd:114) only advances
growth / flower / runner timers. There is **no motion of any kind** — no bob, no
sway, no rotation, no surface coupling.

The smoking gun: `_t` ([line 27](../shaders-godot/godot-project/scripts/lily_pad.gd:27))
and `_phase` ([line 28](../shaders-godot/godot-project/scripts/lily_pad.gd:28),
seeded at [line 58](../shaders-godot/godot-project/scripts/lily_pad.gd:58)) are
both computed and **never read again**. They were clearly meant to drive
animation that never got wired. The pad voxels also use flat
`VoxelMat.make_foliage()` materials, so they don't even get the GPU
[`foliage.gdshader`](../shaders-godot/godot-project/shaders/foliage.gdshader)
sway that every other plant uses. So a lily pad is, by construction, a static
prop. **That's the whole complaint, and it's a quick win.**

### Cause B — Growth penalties stack multiplicatively into a crawl

In [`plant.gd` tick()](../shaders-godot/godot-project/scripts/plant.gd:1777),
`nutrient_mult` gets multiplied by ~9 separate factors (shade, floater-shade
melt, light penetration, vitals, substrate boost, CO₂, allelopathy, temperature…
[lines 1823–1911](../shaders-godot/godot-project/scripts/plant.gd:1823)). Then
`effective_rate` ([line 2063](../shaders-godot/godot-project/scripts/plant.gd:2063))
multiplies *again* by etiolation, starch, **and** a Liebig `minf(lim_light,
lim_co2)` ([line 2080](../shaders-godot/godot-project/scripts/plant.gd:2080)),
then succession.

The problem: Liebig's law says growth is capped by the **single** scarcest
resource (a `min`), but the code applies a `min` for {light, CO₂} *and then*
also multiplies in every other limiter. A moderately suboptimal tank easily
lands at `effective_rate ≈ growth_rate × 0.18` → ~30 s per voxel → 7–11 minutes
to grow one plant. Worse, `_light_avg`
([line 1914](../shaders-godot/godot-project/scripts/plant.gd:1914)) and `_starch`
([line 1917](../shaders-godot/godot-project/scripts/plant.gd:1917)) both *ramp up
from cold* via slow lerps, so a freshly-spawned plant is double-penalized by
etiolation + Liebig + low starch for its first ~30 s of life — exactly when the
player is watching for it to take off. Combined with `plant_youth_scale = 0.52`
([tank_config.gd](../shaders-godot/godot-project/scripts/tank_config.gd)), young
plants stay visibly tiny for a long time. **That's why "they aren't growing well
enough."**

If you only do two things: **#1 (lily pad motion)** and **#11 (collapse the
penalty stack to a soft-min)**.

---

## Step 0 — Verify the crawl before retuning (do this first)

The diagnosis above (Cause B) is a strong inference from reading the code, **not
a measured number**. Prove it with real data before touching any tuning in
Section 2, and capture before/after so the retune is measurable, not vibes.

- **0. Instrument `effective_rate` to confirm the crawl.** Add a debug toggle (a
  `DEBUG_GROWTH` const in `plant.gd`, or a `TankConfig` flag) that, in `tick()`
  right after `effective_rate` is finalized
  ([plant.gd:2090](../shaders-godot/godot-project/scripts/plant.gd:2090)),
  records per-plant `effective_rate`,
  `seconds_per_voxel = 1.0 / max(effective_rate, 1e-6)`, and the individual
  factor breakdown (`nutrient_mult`, `lim_light`, `lim_co2`, the etiolation
  factor, the starch factor, the succession factor). Surface it either way:
  - **Quick:** `sim_driver` logs tank-wide min / median / max seconds-per-voxel
    across all living plants every ~10 s.
  - **Better:** fold the breakdown into the tap-a-plant inspector (#21) so it
    stays useful *after* the retune as a live diagnostic.

  **Acceptance check:** in a default scenario, if median seconds-per-voxel is
  >15 s the crawl is confirmed and Section 2 is justified. Re-run the same
  readout after #11/#12 to confirm the fix. *Effort: S · Impact: M — gates all
  of Section 2.*

---

## Section 1 — Lily pads: keep the concept, make them alive

All of these live in
[`lily_pad.gd`](../shaders-godot/godot-project/scripts/lily_pad.gd). The goal is
gentle, surface-bound life — pads float, they don't thrash.

- [x] **1. Surface bob.** Use the already-present `_t` + `_phase` to drive a small
  vertical oscillation of the whole pad node in `tick()`:
  `position.y = base_y + sin(_t * 0.6 + _phase) * 0.02`. Cache `base_y` at init.
  This alone kills the "dead prop" read. *S · L*
- [x] **2. Slow yaw drift.** Real pads rotate slowly on the surface. Add
  `rotation.y += dt * _spin_rate` with a tiny per-pad `_spin_rate`
  (`randf_range(-0.05, 0.05)`), so a raft of pads turns lazily out of sync. *S · M*
- [x] **3. Tilt with current.** Lean the pad slightly toward the surface flow.
  Reuse the floaters' `surface_drift_vec` (see floaters v2 / G2) or
  `world.get("surface_drift_vec")`; set `rotation.x/z` from it with a slow lerp.
  Ties pads into the same current the duckweed already feels. *M · M*
- [x] **4. Ripple-coupled rock.** When a fish darts near the surface,
  `world.spawn_burst_ripple()` already fires (E41). Have nearby pads subscribe
  (or have `world` nudge them) so a passing fish makes the pad rock and settle —
  the single most "alive" surface cue. *M · L*
- **5. Edge undulation.** Give the rim voxels (the `t > 0.55` ring at
  [line 103](../shaders-godot/godot-project/scripts/lily_pad.gd:103)) a phase-
  offset vertical wiggle so the disc edge ripples like a real pad on water,
  while the center stays calmer. *M · M*
- **6. Flexible stem.** The stem is one rigid box
  ([`_build_stem`](../shaders-godot/godot-project/scripts/lily_pad.gd:66)). Let
  the pad drift a little laterally off the stem anchor and spring back, so it
  reads as tethered-but-floating rather than bolted to a pole. *M · M*
- **7. Apply the foliage sway shader.** Swap the pad-voxel
  `material_override` from flat `VoxelMat.make_foliage()` to the GPU
  [`foliage.gdshader`](../shaders-godot/godot-project/shaders/foliage.gdshader)
  so motion is free on the GPU and consistent with other plants. *M · M*
- **8. Dew / specular pop on the pad top.** A faint wet sheen highlight that
  shifts as the pad bobs — leans on the meniscus sheen work already done for
  emergent plants (Plants v2 #47). Sells "floating on water." *S · S*
- **9. Pad aging color.** Pads currently never change tone after growth. Let
  older pads (high `_t`) drift toward yellow-green / develop a brown edge fleck,
  and occasionally shed a pad voxel as detritus — a slow lifecycle instead of a
  fixed disc. *M · M*
- **10. Bloom that tracks the bob.** The flower
  ([`_tick_flower`](../shaders-godot/godot-project/scripts/lily_pad.gd:153)) is
  solid, but it sits rigidly above a now-moving pad. Parent the flower nodes to
  the pad's motion so the bloom rides the bob, and let petals flutter faintly at
  FULL stage. *S · M*

---

## Section 2 — Growth that actually progresses (fix the crawl)

These target Cause B. **Do Step 0 first** — confirm the numbers before you
retune. The aim: plants in a *decent* tank visibly put on size in a couple of
minutes, while bad tanks still punish — without the silent multiplicative
death-by-a-thousand-cuts.

- [x] **11. Collapse the penalty stack to a soft-min (Liebig, done right).**
  Compute each limiter as a clean 0..1 factor (light, CO₂, nutrient, temp,
  shade) and set `effective_rate = growth_rate × softmin(factors)` instead of
  multiplying all of them. One scarce resource caps growth; two scarce resources
  don't multiply into ~0. Rework
  [plant.gd:2063–2090](../shaders-godot/godot-project/scripts/plant.gd:2063).
  *Biggest single lever.* *M · L*
- [x] **12. Warm-start `_light_avg` and `_starch` on spawn.** Initialize
  `_light_avg` to the local light penetration and `_starch ≈ 0.4` at init so a
  new plant isn't crushed by etiolation + low-starch for its first 30 s. See
  [lines 1914–1921](../shaders-godot/godot-project/scripts/plant.gd:1914). *S · L*
- **13. Soften the starch cliff.** `_starch < 0.1 → ×0.25`
  ([line 2068](../shaders-godot/godot-project/scripts/plant.gd:2068)) is brutal
  and binary. Make it a smooth ramp (e.g. `lerp(0.5, 1.0, starch/0.2)`) so a dip
  slows growth instead of nearly halting it. *S · M*
- **14. Raise the etiolation floor a touch.** `lerpf(0.55, 1.0, …)`
  ([line 2066](../shaders-godot/godot-project/scripts/plant.gd:2066)) compounds
  with the Liebig `lim_light` ([line 2075](../shaders-godot/godot-project/scripts/plant.gd:2075))
  — you're paying the light penalty twice. Pick one (prefer the Liebig min from
  #11) and drop the other, or floor etiolation at ~0.7. *S · M*
- **15. Faster health recovery than decay.** `health` lerps at `dt * 0.03`
  ([line 1947](../shaders-godot/godot-project/scripts/plant.gd:1947)) — ~33 s
  timescale both ways, so a transient bad reading can tip a plant under the 0.2
  death threshold before conditions re-evaluate. Make recovery faster than
  decline (asymmetric lerp). *S · M*
- **16. Audit the default scenario light/CO₂/substrate combos.** Re-run the
  capacity logic with #11 in place; the "aggressive default-retune" (GOALS H)
  likely over-tuned for the *old* multiplicative model. Several presets may now
  be starving plants that should thrive. *M · M*
- **17. Decouple visual size from growth time.** `plant_youth_scale = 0.52`
  ([tank_config.gd](../shaders-godot/godot-project/scripts/tank_config.gd)) means
  a slow-growing plant looks stunted for minutes. Lerp leaf scale toward full
  faster than voxel count grows, so even an early plant reads as "small but
  thriving," not "stuck." *S · M*
- **18. Minimum perceptible growth rate.** Floor `effective_rate` at a small
  positive value whenever the plant is at least mildly healthy (health > 0.4),
  so a viable plant *always* visibly creeps upward instead of appearing frozen.
  *S · M*
- **19. Re-examine shade penalty radius/strength.** `_recompute_shade`
  ([line 1840](../shaders-godot/godot-project/scripts/plant.gd:1840)) can stack
  with floater-shade melt (down to 0.62, [line 1855](../shaders-godot/godot-project/scripts/plant.gd:1855))
  AND light penetration — triple light-debt. Cap total shade-related attenuation
  so a midground plant under tall neighbors slows but doesn't flatline. *S · M*
- **20. CO₂ low-end penalty review.** `co2_n < 0.25 → ×0.82`
  ([line 1880](../shaders-godot/godot-project/scripts/plant.gd:1880)) applies to
  `nutrient_mult` *and then* `lim_co2` caps `effective_rate` again — double CO₂
  tax for demanding species. Consolidate under #11. *S · M*

---

## Section 3 — Make growth legible (so you're never "unsure")

The player can't tell if plants are growing or why they're stalled. Fix the
*feedback*, not just the *rate*. Several of these expose state the engine already
computes (e.g. the Liebig limiting factor from GOALS H6 #54).

- [x] **21. Tap-a-plant inspector.** Tap a plant → small panel: species, health,
  growth %, and **the current limiting factor** ("light-limited" / "needs
  richer substrate" / "CO₂-starved"). The limiting-factor diagnostic already
  exists per H6 #54 — surface it per-plant. *M · L*
- **22. Per-plant growth meter on hover.** A thin radial/linear fill showing
  `growth_progress` toward the next voxel, fading in only on hover/selection, so
  the player can *see* it's alive even when slow. *S · M*
- **23. "New growth" sparkle.** A one-shot tiny particle pop when `_grow_one()`
  succeeds ([line 2095](../shaders-godot/godot-project/scripts/plant.gd:2095)).
  Cheap, and it turns invisible incremental growth into a noticeable beat. *S · M*
- **24. Daily growth digest in the story log.** The story log (E49) already
  exists. Add lines like "Day 4: the vallisneria reached the midwater" or "the
  carpet has covered a third of the floor" so growth registers as narrative. *S · M*
- **25. Tank-wide "flora vigor" chip.** A HUD chip aggregating average plant
  health + net growth rate, mirroring the existing mood chip (E47), so the
  player has one glanceable "are my plants happy" signal. *M · M*
- [x] **26. Limiting-factor heat tint (debug/learn toggle).** Optional overlay that
  tints each plant by its limiting factor (blue=light, red=CO₂, brown=nutrient).
  Doubles as a teaching tool and a balancing aid. *M · M*
- **27. Before/after height ghost.** Faint marker at the height a plant was N
  minutes ago, so slow vertical progress becomes visible against a reference.
  *M · S*
- **28. Pearling as the honest "thriving" signal — verify it reads.** Pearling
  intensity already scales with health/O₂/light (D38, H6 #60). Confirm it's
  actually visible on healthy plants at normal camera distance; if not, bump
  emission so it's the trustworthy "this plant is happy" tell. *S · M*

---

## Section 4 — Motion & life for all plants (not just lilies)

Sway is offloaded to [`foliage.gdshader`](../shaders-godot/godot-project/shaders/foliage.gdshader)
and CPU only applies slow flow lean + circumnutation
([plant.gd:1800–1815](../shaders-godot/godot-project/scripts/plant.gd:1800)).
Good foundation — these add variety and responsiveness.

- **29. Per-species sway personality.** Stiff swords barely move; fine-leaf
  stems and hairgrass shimmer. Drive `sway_amplitude` / `sway_frequency` from
  leaf form so the tank doesn't sway as one uniform mass. *M · M*
- **30. Gust events.** Occasional tank-wide flow pulses (filter surge,
  feeding-time stir) that ripple across all foliage and settle — the planted-tank
  equivalent of wind through grass. *M · L*
- **31. Stronger fish brush-bend.** `_brush_bend`
  ([line 1807](../shaders-godot/godot-project/scripts/plant.gd:1807)) springs
  back in ~1 s; make a big fish pushing through dense stems visibly part them
  more, so cover feels physical. *S · M*
- **32. Tip-weighted sway.** Tall stems should sway more at the tip than the
  base (already partly in `foliage_mm.gdshader` via `tip_sway_mult`) — verify
  it's pronounced enough to read on `valli` and `red_stem`. *S · M*
- **33. Carpet shimmer.** Hairgrass/carpet plants get a fast, low-amplitude
  high-frequency flutter distinct from tall-stem sway, so the foreground feels
  like a living lawn. *S · M*
- **34. Bubble release on stem flex.** When a healthy plant is brushed hard, pop
  a couple of trapped O₂ bubbles loose from the leaves — couples the pearling
  system to the brush-bend interaction. *S · M*
- **35. Floater drift coherence.** Make sure floaters (duckweed/frogbit) and the
  new lily-pad drift (#3) share the same `surface_drift_vec` so the whole
  surface layer moves as one coherent skin, not independent objects. *S · M*

---

## Section 5 — Fresh visual fidelity (beyond what's shipped)

Plants v2 covered a lot (translucency, blush, nyctinasty, etc.). These are
genuinely new angles.

- **36. Depth-tinted foliage.** Plants deeper in the tank / further from light
  render slightly cooler and desaturated (light attenuation through water),
  giving the planted scape real depth layering. *M · M*
- **37. Bubble-stream from substrate near dense roots.** Occasional fine O₂/gas
  bubble threads rising from the substrate around heavy root mats — visual proof
  of the root-oxygenation system (Plants v2 #38) already in the sim. *M · M*
- **38. Leaf-surface algae film progression.** Old, slow-growing leaves slowly
  accrue a faint green-brown film (GSA) that grazers clean off — the aufwuchs
  system exists (Plants v2 #30); make the *visual* accumulation more legible on
  broad leaves. *M · M*
- **39. Seasonal/maturity color shift.** Tie a slow whole-tank foliage palette
  drift to `tank_age` (richer, deeper greens as the scape matures) so an old
  tank *looks* established, not just statistically different. *M · M*
- **40. Red-plant color responds to light intensity.** Reds (`red_stem`) go
  greener in shade, blush deeper red under strong light — the real
  light-driven anthocyanin response, layered on the existing `red_potential`
  blush. *M · M*
- **41. Flower variety per species.** Lily blooms are great; give cattail,
  emergent stems, and crypts distinct flower silhouettes so flowering events
  (C25) read as "*that* species bloomed," not a generic pop. *M · M*
- **42. Backlight bloom at the surface.** Emergent leaves and pads catch a soft
  rim of light where they break the meniscus — extends the wet-sheen work and
  makes the waterline a visual feature. *M · S*
- **43. Detritus catch on fine leaves.** Fine-leaved plants visibly collect a
  little drifting mulm (the detritus-trapping mechanic, Plants v2 #31 / H2 #12,
  already in sim) — show a few caught flecks that shrimp then pick clean. *M · M*

---

## Section 6 — New mechanics & delight

A few genuinely new ideas to push the plant layer forward once the fixes land.

- **44. Player planting/pruning is the core ritual.** If not already exposed:
  let the player place a plant and trim a stem (trim-branching exists —
  `_pending_trim_nodes`, GOALS F #7). Trimming a stem should drop a fragment
  that can re-root (`plant_fragment.gd` exists, F #13). Close the loop the
  player can actually *do*. *L · L*
- **45. Lily pad as a stage.** Let a snail graze across a pad, a frog-style
  surface dweller rest on one, or fry shelter under the disc's shade — make the
  pad an *interactive surface*, not just décor. (Pads already cast no shade —
  wire them into `local_floater_shade_at` like floaters.) *M · L*
- **46. Lily pads block & filter light.** Mature pads should shade the substrate
  beneath them (reuse the floater shade path), creating the same emergent
  light-competition the duckweed creates — and a reason to manage pad coverage.
  *M · M*
- **47. Drifting seeds / spores you can watch settle.** The seed-bank +
  germination system exists (Plants v2 #14). Make a few seeds *visibly* drift
  and settle into the substrate before sprouting, so propagation has a watchable
  causal chain like the runner trails do. *M · M*
- **48. Emergent growth above the waterline.** Tall stems / cattails that reach
  the surface push a leaf or flower *above* the water (heterophylly exists,
  Plants v2 #1) — a dramatic "my tank grew out of the water" milestone. Verify
  it triggers and reads. *M · L*
- **49. Plant "mood" micro-animations.** A thriving plant occasionally does a
  slow, satisfied full-body stretch (subtle scale pulse); a struggling one
  droops between wilts. Tiny, but it gives each plant presence. *M · M*
- **50. Bloom-time ambient beat.** When a notable plant flowers (lily, emergent
  stem), pair it with a soft audio sting via the ambient system (E45) and a
  story-log line — make flowering an *event* the player notices, not background
  décor. *S · M*

---

## If Cursor only does five

Start with **#0 (measure)** — it gates the growth work. Then:

1. **#1** — lily pad surface bob (kills the "dead prop" read instantly).
2. **#11** — collapse the growth penalty stack to a soft-min (fixes the crawl).
3. **#12** — warm-start `_light_avg`/`_starch` so new plants don't stall at birth.
4. **#21** — tap-a-plant inspector with limiting factor (you'll never be "unsure" again).
5. **#4** — ripple-coupled pad rock (the most "alive" surface cue, cheap once #1 lands).
