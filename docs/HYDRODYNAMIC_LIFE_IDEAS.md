# Hydrodynamic Life — 50 Deep Ideas (Pillar 9)

*Drafted 2026-06-26. Director's brief for the motor/physics layer — all creatures.*

The goal: every animal **moves like a real body in real water** — the tail/fins
actually drive it, it carries momentum, coasts, banks, gets shoved by current,
and leaves a wake. This is the motor layer that *underwrites everything else*
(the dancing, the sentience, the bond all read better when the bodies move
truthfully).

Format: **Effort** S/M/L · **Impact** S/M/L; checkbox-tracked; real symbols cited.

> **The headline finding (read this):** **locomotion is cosmetic for every
> creature.** The swim animation (`_swim_phase`, `_tail_pivot`, fins) is purely
> visual and *decoupled* from propulsion. Motion is a separate `heading + speed`
> model in `_motion_substep`
> ([fish.gd ~5284](../shaders-godot/godot-project/scripts/fish.gd:5284)):
> `speed = move_toward(speed, target_spd, linear_accel*dt)`
> ([~5392](../shaders-godot/godot-project/scripts/fish.gd:5392), `linear_accel =
> 2.5`), heading rotated at a constant `max_turn_rate = 2.6` rad/s
> ([~5351](../shaders-godot/godot-project/scripts/fish.gd:5351)). There is **no
> drag, no added mass, no coasting, no buoyancy**, and the swim-mode taxonomy
> (`locomotion_type`: subcarangiform/anguilliform/ostraciiform/labriform/
> thunniform, [fish.gd ~420, ~5554](../shaders-godot/godot-project/scripts/fish.gd:5554))
> only changes the *wag*, not the physics. The tail never produces thrust.

---

## The three structural levers

**Lever 1 — Articulation doesn't drive motion.** The body and the propulsion are
orthogonal. Couple them: a tail/fin stroke should produce a forward impulse, so
speed *pulses* with the beat and the creature visibly pushes itself through the
water (#1–8). You don't need CFD — a stroke-synced surge gets 90% of the feel.

**Lever 2 — There's no fluid, so nothing feels like it's *in* water.** Linear
accel/decel, constant turn rate, no momentum tail-off. Add quadratic drag
(exponential coast-down), added mass (resist sudden direction change), burst→glide,
speed-dependent turn radius, banked inertial turns (#9–18). This single cluster is
the biggest "oh, that's water" win.

**Lever 3 — Every creature swims in a private vacuum.** Only floaters + microfauna
feel the aeration current; nothing leaves a wake; only fish brush plants. Add one
lightweight **shared flow field** that all creatures both *sample* (drift, lean,
work upstream) and *contribute to* (wakes, displacement) — coupling the whole tank
into one body of water (#37–48).

---

## Section A — Thrust from articulation (make the body do the swimming)

- [x] **1. Stroke → forward impulse.** Add a small forward surge each tail
  half-stroke (`max(0, sin(_swim_phase))` × efficiency) so `speed` *pulses* with
  the wag instead of being independent. Couples `_swim_phase`
  ([fish.gd ~5645](../shaders-godot/godot-project/scripts/fish.gd:5645)) to motion.
  The core fix for Lever 1. *M · L*
- [x] **2. Burst-and-glide gait.** Real fish thrust then coast. Let the stroke
  impulse (#1) + drag (#9) produce a natural surge-glide ripple within cruising,
  not constant velocity. Carangiform fish especially. *M · L*
- [x] **3. Thrust scales with demand.** Big tail amplitude when accelerating, small
  trim strokes when cruising — drive `tail_amp`/`wag_amp_extra` from
  `(target_spd − speed)` so you *see* effort vs coasting. *S · M*
- [x] **4. Swim-mode physics, not just looks.** Make `locomotion_type` actually
  change handling: thunniform = efficient high-speed cruise, poor low-speed
  turning; anguilliform = slow but turns on a dime; ostraciiform (boxfish/puffer)
  = stiff, hover-y, precise. Today all five share identical physics. *M · L*
- [x] **5. Pectoral rowers get pec thrust.** Labriform fish (tangs/angels) derive
  thrust from the pectoral row (`_pec_*_pivot`,
  [fish.gd ~5737](../shaders-godot/godot-project/scripts/fish.gd:5737)), tail mostly
  steering — so they hover and maneuver, not sprint. *M · M*
- [x] **6. Tail-beat recoil yaw.** Each stroke yaws the head slightly opposite the
  tail (real fish wag their nose). Apply a tiny counter-rotation to `_head_pivot`
  in phase with `_swim_phase`. Sells that the tail is *working* against water.
  *S · M*
- [x] **7. Backpaddle / station-keeping.** Hovering fish (and labriform/ostraciiform)
  hold position against drift with little reverse pectoral sculls — visible
  fin-trimming instead of frozen stillness. *M · M*
- [x] **8. Effort shows in the body.** When pushing hard (acceleration, upstream,
  burst), exaggerate body-wave amplitude + a faint strain in posture; when gliding,
  the body goes smooth and straight. Reads as exertion vs ease. *S · M*

---

## Section B — Real fluid feel: drag, momentum, coasting

- [x] **9. Quadratic water drag.** Replace the linear `move_toward` decel
  ([fish.gd ~5392](../shaders-godot/godot-project/scripts/fish.gd:5392)) with drag
  `dv/dt = thrust − k·v²` so a fish that stops thrusting *coasts* to a halt
  exponentially. The single biggest "real water" change, and cheap. *M · L*
- [x] **10. Added mass / inertia.** Water resists sudden direction change. Smooth
  the heading change more at high speed and make the body *carry* through a turn
  (momentum), rather than the velocity tracking desire instantly. *M · L*
- [x] **11. Burst → glide, not burst → brake.** After `burst_remaining` ends
  ([fish.gd ~2889](../shaders-godot/godot-project/scripts/fish.gd:2889)), let the
  fish *coast* on drag (#9) instead of linearly decelerating — a dart should end in
  a long graceful glide. *S · L*
- [x] **12. Speed-dependent turn radius.** Make `eff_turn`
  ([fish.gd ~5287](../shaders-godot/godot-project/scripts/fish.gd:5287)) scale down
  with speed so fast fish carve wide arcs and slow fish pivot tight — real
  hydrodynamics (turn radius ∝ speed). Today turn rate is constant. *S · L*
- [x] **13. Banked, leaning turns.** Roll into turns with centripetal lean
  proportional to `speed × turn_rate` (extend the `_bank`/`dance_bank` hook,
  [fish.gd ~5454](../shaders-godot/godot-project/scripts/fish.gd:5454)) — a fast
  banking turn reads as momentum fighting water. *S · M*
- [x] **14. Overshoot & settle.** A fish darting to a target slightly overshoots
  then drifts back (inertia + drag), instead of arriving exactly. Tiny, but it's
  the difference between a puppet and a body. *S · M*
- [x] **15. Active braking pose.** To stop fast, fish *flare* — splay pectorals,
  arch the body, throw a reverse tail-flick — a visible brake, not a smooth ramp to
  zero. Trigger when `target_spd` drops far below `speed`. *M · M*
- [x] **16. Heading lags steering.** The desired direction leads; the body arcs to
  meet it over time (it doesn't snap). Mostly there via turn-rate, but make the lag
  speed-scaled so fast turns visibly swing wide. *S · M*
- [x] **17. Neutral buoyancy & hover.** Give Y a gentle buoyancy spring toward a
  hover depth + a slow idle bob, instead of treating Y as a pure steering axis
  ([fish.gd ~5335](../shaders-godot/godot-project/scripts/fish.gd:5335)). Resting
  fish hang and bob; they don't hold Y like a drone. *M · L*
- [x] **18. Sink/rise when idle vs working.** Slightly negative buoyancy when a fish
  stops swimming (drifts down, then corrects with a stroke) — the constant subtle
  swim-to-stay-up that real fish do. *M · M*

---

## Section C — Per-creature locomotion (all the animals)

- [x] **19. Shrimp: real tail-flip jet escape.** The escape is currently cosmetic
  amplitude ([shrimp.gd ~1365](../shaders-godot/godot-project/scripts/shrimp.gd:1365)).
  Make it a true backward impulse — a hard caridoid flick that *launches* the shrimp
  tail-first with recoil, then a tumble. The signature shrimp move. *M · L*
- [x] **20. Shrimp: pleopod paddle for mid-water swim.** When swimming (not crawling)
  add visible swimmeret paddling that drives gentle forward motion, vs the current
  body-bob-only ([shrimp.gd ~1382](../shaders-godot/godot-project/scripts/shrimp.gd:1382)).
  *M · M*
- [x] **21. Shrimp: substrate grip (no sliding).** Walking shrimp should grip — no
  drift/slide on the substrate, feet planted; only the tail-flip breaks contact.
  Tighten the gravity-glide model
  ([shrimp.gd ~1272](../shaders-godot/godot-project/scripts/shrimp.gd:1272)). *S · M*
- [x] **22. Snail: propulsive foot wave.** The `_pulse_phase` squash
  ([snail.gd ~549](../shaders-godot/godot-project/scripts/snail.gd:549)) should be a
  *peristaltic* wave that travels along the foot and actually paces the glide — so
  the muscular ripple visibly *is* the propulsion, retrograde wave and all. *M · M*
- [x] **23. Snail: righting response.** If a snail drops/flips off the glass, animate
  it landing on its shell and slowly righting — instead of teleporting upright. A
  beloved real-snail moment. *M · M*
- [x] **24. Snail: weight & uphill effort.** Climbing glass is slower than gliding
  the floor (gravity on the shell); the snail visibly labors uphill and can slip a
  little. *S · S*
- [x] **25. Microfauna: copepod escape jump.** Add the signature sudden high-speed
  hop away from disturbance (a passing fish, the cursor) on top of the gentle drift
  ([microfauna_swarm.gd ~155](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:155)).
  *S · M*
- [x] **26. Microfauna: low-Reynolds instant stop.** Tiny creatures have *no* inertia
  — they should stop dead when not paddling (the opposite of fish), not coast on a
  held drift vector. Zero out drift between hops/bobs. The honest physics of being
  small. *S · M*
- [x] **27. Daphnia: hop-and-sink rhythm.** Make the bob a real "hop up, passively
  sink" cycle (their antennae-rowing diving gait), distinct from the copepod's
  horizontal jerks — by morph ([microfauna_swarm.gd ~157](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:157)). *S · S*
- [x] **28. Worms: peristaltic crawl that *translates*.** Today worms wriggle in
  place + drift separately ([wriggle_worm.gd ~137](../shaders-godot/godot-project/scripts/wriggle_worm.gd:137)).
  Make the anchor-extend-contract wave actually pull the body forward, so the motion
  and the displacement are one. *M · M*
- [x] **29. Worms: burrow in/out.** Tail anchored in substrate, body extending to
  feed then retracting — instead of the bristle worm just lerping its Y depth
  ([bristle_worm.gd ~99](../shaders-godot/godot-project/scripts/bristle_worm.gd:99)).
  *M · M*
- [x] **30. Sea cucumber: tube-feet ripple + body creep.** Add a traveling
  stretch-compress of the body (it lengthens, anchors the front, pulls the rear) and
  a faint tube-feet shimmer, vs the pure X/Z drift
  ([sea_cucumber.gd ~120](../shaders-godot/godot-project/scripts/sea_cucumber.gd:120)).
  *M · M*
- [x] **31. Coral/anemone: base→tip tentacle wave.** Tentacle sway is a rigid
  rotation today ([coral.gd ~760](../shaders-godot/godot-project/scripts/coral.gd:760));
  make the bend a wave that travels base→tip so tentacles *undulate* in the current
  like real polyps. *M · M*
- [x] **32. Coral: current-driven sway amplitude.** Tentacle/polyp sway amplitude
  should scale with the local flow (#37), not a fixed sine — strong current = big
  lean, still water = gentle. Extends the existing `flow_bias` tilt
  ([coral.gd ~763](../shaders-godot/godot-project/scripts/coral.gd:763)). *S · M*
- [x] **33. Coral: polyp mouth + grab.** Polyps open/close and tentacles *curl
  inward* to pass captured food to the mouth (couples to the night-feeding hook),
  vs sway-only. *M · M*
- [x] **34. Coral: retract on touch/threat.** Anemone/hydra tentacles flinch-retract
  when a fish brushes them or O₂ crashes (extend `_feeding_extension`,
  [coral.gd ~801](../shaders-godot/godot-project/scripts/coral.gd:801)). *S · M*
- [x] **35. Reynolds-by-size rule.** One shared principle: small creatures = no
  inertia, instant start/stop (microfauna, fry); large = momentum + coasting
  (#9–11). Scale drag/added-mass by body size so the whole bestiary feels
  size-appropriate. *M · L*
- [x] **36. Per-species handling profiles.** A small data table per species: top
  speed, accel, turn radius, drag, buoyancy, gait — so an eel, a tuna-type, a
  boxfish, a shrimp, and a snail each *handle* distinctly. Pairs with #4. *M · M*

---

## Section D — The shared fluid: currents, wakes & displacement

- [x] **37. One lightweight flow field.** A coarse 3D velocity grid (low-res, cheap)
  representing tank water motion, seeded by the aeration jet
  ([world.gd ~1080](../shaders-godot/godot-project/scripts/world.gd:1080)). The
  substrate every other idea here samples. *Foundation.* *L · L*
- [x] **38. All creatures sample the current.** Fish/shrimp/snails should drift with
  it, lean into it, and work harder upstream — today only floaters + microfauna feel
  flow. Add a flow sample to `_motion_substep`. *M · L*
- [x] **39. Creatures contribute wakes.** A moving creature pushes a little velocity
  into the field behind it, which decays — so the water carries the memory of motion
  (the basis for drafting, scatter, swirl). *M · L*
- [x] **40. Wake push on neighbors & particles.** A fish's wake nudges nearby fish,
  microfauna, bubbles, and detritus in its trailing direction — you *see* the water
  move when something swims past. *M · L*
- [x] **41. Slipstream / drafting.** Trailing fish in a school sit in the leader's
  wake and spend less energy (couples to the existing schooling) — the real reason
  fish school in formation. *M · M*
- [x] **42. Wake vortices behind fast movers.** A subtle trailing swirl (particles or
  a shader trail) shed off the tail during bursts/fast cruising, so speed leaves a
  visible signature in the water. *M · M*
- [x] **43. Everything parts the plants.** `_brush_bend` is fish-only
  ([plant.gd ~227](../shaders-godot/godot-project/scripts/plant.gd:227)). Let shrimp,
  snails, big fish, and the flow field itself bend plants as they pass — and bigger
  bodies part them more. *S · M*
- [x] **44. Substrate displacement from the whole crew.** Dust kick-up is fish-only
  ([world.gd spawn_substrate_dust](../shaders-godot/godot-project/scripts/world.gd));
  add it (scaled) for shrimp scuttles, cory sifts, sea-cucumber creep, snail trails.
  *S · M*
- [x] **45. Wake scatters microfauna.** When a fish barrels through a plankton cloud,
  the microfauna scatter in its wake then re-gather — predation/perception drama
  made physical (extends [microfauna_swarm.gd ~161](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:161)). *M · M*
- [x] **46. Surface bow-wave.** A fish swimming just under the surface pushes a small
  traveling bow-wave / V-wake on the meniscus (extend `spawn_burst_ripple`,
  [world.gd ~5467](../shaders-godot/godot-project/scripts/world.gd:5467) into a
  continuous trailing wake, not just a dart ring). *M · M*
- [x] **47. Bubbles ride the flow.** Aeration/pearling bubbles get carried by the
  flow field + creature wakes (curve, swirl, cluster) instead of rising straight —
  makes the current *visible* through the bubbles. *M · M*
- [x] **48. Current varies in space & time.** The flow field should be stronger near
  the outflow, slack in corners, with slow eddies — so there are calm spots fish
  rest in and brisk lanes they ride. Replaces the single fixed jet vector. *M · M*

---

## Section E — Polish, performance & legibility

- [x] **49. LOD the physics.** Full fluid (drag, added mass, wake) for near/hero
  creatures; cheap kinematics for distant ones — keep the cost where the camera is.
  Reuse the existing distance LOD. *M · M*
- [x] **50. Settle-to-rest, never frozen.** Idle/sleeping creatures ease into a
  buoyant hover with tiny fin-trim corrections + a slow drift (#17), so a "resting"
  animal is still visibly *in water* and alive — never a static prop. *S · M*

---

## If Cursor only does five

The flow field (**#37**) is the one foundation; build it early. Then:

1. **#9** — quadratic drag + coasting (the single biggest "real water" feel, cheap).
2. **#1** — stroke → thrust impulse (the body finally does the swimming; Lever 1).
3. **#38 + #39** — creatures sample *and* feed the flow field (wakes + drift; the
   whole tank becomes one body of water).
4. **#19 / #25 / #23** — the signature per-creature fixes (shrimp tail-jet, copepod
   hop, snail righting) so it's not just fish that feel real.
5. **#17** — buoyancy & hover (fish hang in the water instead of holding position
   like drones).

> **Pragmatic note:** none of this needs real CFD. #9 (drag) + #1 (stroke surge) +
> #37 (a coarse, decaying velocity grid) together produce ~90% of the "real animal
> in real fluid" feeling for a tiny fraction of the cost. Build those three, tune,
> then layer the per-creature and wake detail on top.
