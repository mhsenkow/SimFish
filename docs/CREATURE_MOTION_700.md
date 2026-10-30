# The Illusion of Life — 700 Motion Ideas for Every Creature

*Drafted 2026-10-29. Director's brief: a deep, holistic pass on the motion of
every creature in the tank, and on how real that motion looks, judged against
the twelve basic principles of animation
([Wikipedia](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation);
Thomas and Johnston, *The Illusion of Life*, 1981).*

> **Headline finding.** Creatures in this tank are *steered* by a careful,
> physically motivated motor (quadratic drag, stroke thrust, inertial turns,
> a real flow field). Their *bodies* are animated by direct `sin()`
> assignments, and those have no memory. A fish is three sibling pivots
> (`Head`, `BodyMid`, `TailPivot` under `BankPivot`,
> [fish.gd:2848](../shaders-godot/godot-project/scripts/fish.gd:2848)), so the
> default swimmer performs a standing counter-wag, not a travelling wave
> (`body_phase = π`,
> [fish.gd:7742](../shaders-godot/godot-project/scripts/fish.gd:7742)). Several
> shipped motions never reach the screen because a later line overwrites them:
> the turn lean, the brake flare and the sleep roll. A shader ripple on global
> `TIME` wags every fish, every corpse, and every shrimp's abdomen sideways like
> a fish's
> ([voxel_fauna_mm.gdshader:152](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:152)).
> Of the twelve principles, the tank is weakest on **anticipation**,
> **follow-through** and **slow in/slow out**. All three need state, and the
> animation layer has none.

## Scope

Every animal that moves:

- **21 fish species** (`SPECIES_LIBRARY`,
  [tank_config.gd:1218](../shaders-godot/godot-project/scripts/tank_config.gd:1218)).
- **Crustaceans:** caridean shrimp, crabs, lobsters and crayfish, and mantis
  shrimp (`shrimp.gd`).
- **Snails:** glass snails in eight shell forms (`snail.gd`) and trumpet
  snails.
- **Worms:** wriggle worms, bristle worms and tubifex, plus the reef sea
  cucumber.
- **Sessile and filter animals:** freshwater and reef clams, corals,
  anemones and hydra.
- **Microfauna:** copepods, daphnia and larvae.
- **Eggs.**

This document is about the **body**: how motion looks. It deliberately does
not redo the sibling docs, which are about where creatures go and what the
water does:

- [HYDRODYNAMIC_LIFE_IDEAS.md](HYDRODYNAMIC_LIFE_IDEAS.md): thrust, drag and
  flow. All 50 shipped except #14 (partial), #33 and #36 (partial), and #49
  (stub).
- [LIVING_MOTION_IDEAS.md](LIVING_MOTION_IDEAS.md): topological schooling and
  propagation.
- [LIVING_LOCOMOTION_20261008.md](LIVING_LOCOMOTION_20261008.md) and
  [SWIMMING_MOTION_PASS_20261007.md](SWIMMING_MOTION_PASS_20261007.md): pass
  reports.

Where an idea here touches shipped work, it builds on it and says so.

## How to read this

- Ideas are numbered **1–700** in one sequence, grouped into five parts and 30
  lettered sections. Cross-references use `#n`.
- Each idea ends with *tags · effort/impact*:
  - **Tags** are the principles it serves (table below). A dash means
    infrastructure.
  - **Effort:** S ≤ 2 h, M about half a day, L a day or more.
  - **Impact:** S polish, M noticeable, L changes how the tank feels.
- Line anchors are from `4fc358e`. `fish.gd` is 10,037 lines and moves fast,
  so grep the symbol before editing.
- Nothing here is ticked. The audit behind it is the "what the motion has
  today" table and the ten levers below. Every claim of absence was grepped.

## What the motion has today

| Family | Body rig | What moves | What's missing |
|---|---|---|---|
| Fish | 3 sibling yaw pivots plus bank; 4 fin pivots; shader ripple | Counter-wag tail and mid-body; pectorals a quarter cycle apart; dorsal and anal on swim phase; head recoil; saccade micro-yaw; breath bob; gape after a meal | Travelling wave, follow-through, anticipation (except `aim_before_burst`), eyes, jaw, opercula, pelvic fins, caudal spread, C-start, a real death |
| Shrimp | ~15 pivots: tail, 6 antenna segments, 3 leg pairs | Distance-driven gait with a sawtooth sweep; tail sine; antenna sines; nibble nod | 2 leg pairs, knees, pleopod beat, picking hands, pitch-axis tail flip, landing, molt sequence |
| Crabs, lobsters, mantis | Same builder | Lobster and mantis legs walk | Crab legs static; claws, raptorial arms and eyestalks static |
| Glass snails | Shell and foot on root; eye stalks | Pulsed crawl, eye-stalk sway with real turn lead, rasp | May crawl sideways; shell squashes; surface changes snap; 180° turn in 0.57 s; no head, tentacles or pedal waves |
| Worms, tubifex, cucumber | One mesh per voxel | Lateral sines; Y lerps | Facing, peristalsis; bristle-worm wave runs backwards; frame-rate drift; cucumber double step |
| Clams, coral | Hinge (freshwater); centre-pivot shells (reef); polyp scale | Gape cycle, polyp pulse, tentacle sway | Asymmetric open/close timing, stepped retraction, anemone tips (check), no threat response |
| Microfauna | 3 multimeshes, baked morphs | Hops, square-wave daphnia, twitches | Facing, hop-and-sink rhythm, appendages |

## The ten structural levers

Most of the 700 ideas follow from one of these.

1. **The body can't carry a wave.** Three sibling pivots mean rotating the
   mid-body doesn't carry the tail, and the default `body_phase = π` is a
   standing wave. Only anguilliform phases approximate travel. → #64–#68, #121.
2. **Animation without memory.** Tail, fins and antennae are assigned from
   `sin()` each frame
   ([fish.gd:7869](../shaders-godot/godot-project/scripts/fish.gd:7869),
   [shrimp.gd:1741](../shaders-godot/godot-project/scripts/shrimp.gd:1741)).
   With no state there is no follow-through, settle or easing. The only
   follow primitive in the codebase is `flower_motion.gd`. → #41–#43, H.
3. **Many writers, one channel.** Bank, BodyMid yaw, pectoral roll and
   `BankPivot.scale` each have several writers, and the last one wins. → #2–#7, #44.
4. **A shader that doesn't know what it's drawing.** The ripple runs on
   `TIME·6.2` for everything; `fauna_vertex_bend` is never written; crustacean
   tails get the fish bend weight. → #10–#12, #50.
5. **Two clocks.** `_motor_phase` drives thrust and `_swim_phase` drives the
   tail, so surges don't match strokes. → #13, #49.
6. **Anticipation that lags.** `_turn_anticipation` is built from the yaw rate
   already happening; startles are bound by the inertial cap; darts and music
   surges start at full speed. → E.
7. **No face.** Eyes and mouth are plain voxels; there is no jaw, no operculum
   pivot, and `_gill_pivot` is never built. Meanwhile the fish "blinks", which
   fish can't do. → K.
8. **Snaps.** Wall bounce, snail surface changes, clamp squash, polyp
   retraction, the siphon pop, 10 Hz steering steps and constant-rate turns. → I, #14, #26.
9. **Ready-made layers left unwired.** `_spark_motion`,
   `feed_anticipation_drift`, `signal_reaction_delay`, `breath_hover_offset`,
   `tick_mourning_stance`, `affordance_motor_scale`, `_school_phase_offset`,
   `_speed_personality`, `_pleopod_phase`, `overshoot_bias`, and an
   unreachable thunniform mode. → #17, #18, #19, #150, #156, #163, #316, #453, #460, #520.
10. **Probes count behaviour, not motion.** `fish_behaviour_probe` measures
    depth, speed CV and hover %; `motion_debug_overlay` draws depth bands.
    Nothing measures spacing, arcs, phase lag, twins or snaps. → C.

The constraint over all ten is **pixel scale**: a fish is 22–45 px long, and a
fish crossing the frame broadside foreshortens its own tail beat (#172).

## The twelve principles, translated for water

The principles come from Thomas and Johnston's *The Illusion of Life* and were
written for hand-drawn cartoons. Cartoon exaggeration is not what this tank
needs. Each principle has a version that is simply true of an animal moving
through a fluid 800 times denser than air, and those are the versions used
below. Every idea in the backlog is tagged with the principles it serves.

| Tag | Principle | What it means for a creature in water |
|---|---|---|
| **SQ** | Squash and stretch | The body keeps its volume while it bends. The convex flank lengthens and the concave flank shortens; a fish coiled into a C-start is the extreme squash, and a fish lunging at food is the stretch. A snail's foot thins as it extends, a worm's segments fatten as they shorten, a shrimp's abdomen bunches as it flexes, a coral polyp narrows as it reaches. Never a cartoon bounce. |
| **AN** | Anticipation | Real animals telegraph. A fish turns its head and eyes before its body, sculls its pectorals before it moves off, bends into a C before an escape, and pauses with its mouth aimed before a strike. A shrimp freezes and lowers its antennae before a tail flip; a snail sweeps its tentacles before it changes course. Anticipation is also attention: the glance that tells the viewer where to look next. |
| **ST** | Staging | Make the important motion unmistakable at the game's pixel scale. A display is turned broadside, a fight happens in clear water, the rest of the tank yields a little, and the camera, the light and the palette all help. Motion smaller than a pixel does not exist, and twenty fish doing different big things at once is noise. |
| **PP** | Straight ahead and pose to pose | The simulation is straight-ahead animation: physics integrates each frame and the result is fluid but formless. Behaviours need key poses too (alert, display, sleep, feed, sift, sick, dead) that the procedural motion travels between and settles into, so a behaviour has a recognisable shape rather than just a different speed. |
| **FT** | Follow through and overlapping action | Loose tissue lags and settles. Long fins, veil tails, barbels, antennae, gourami feelers, shrimp legs, snail tentacles and the snail's shell all carry momentum after the body changes what it is doing. Body parts move on different timings: head first, then the trunk, then the tail; the tail keeps going after the stroke stops and damps out. |
| **SI** | Slow in and slow out | Water reshapes easing. Acceleration from a stroke is fast; deceleration is drag, so it is exponential, never linear and never a snap. Escapes are explosive in and long out. Hovering fish drift in and out of station. Legs on substrate ease into stance and snap through swing. Nothing should ever move at constant speed between two rests. |
| **AR** | Arcs | Paths curve. A fish's heading traces an arc whose radius widens with speed and body length; the head traces an arc in plan, the tail tip a figure-eight in profile, a pectoral fin tip a figure-eight while rowing. Sinking food, falling snails, a shrimp's hop and a corpse rolling over all follow arcs. Straight lines and pivots read as mechanical. |
| **SA** | Secondary action | Breathing, eye movement, fin flickers, the operculum pumping, a shrimp's maxillipeds fanning and pleopods beating, a snail's tentacles waving, tubifex tails swaying, a clam's siphon pulsing. These are what make an animal look alive when it is not doing anything, and they must support the main action rather than compete with it. |
| **TI** | Timing | Timing tells weight. A 6 cm angelfish turns more slowly than a 2 cm ember tetra; fry beat their tails faster and jerkier; a lobster's reactions are heavier than a cherry shrimp's. Tail-beat frequency should follow body length and speed (a Strouhal number of roughly 0.2 to 0.4), bout lengths should follow the species, and temperature, oxygen, age and time of day should all shift the clock. |
| **EX** | Exaggeration | Used with restraint and on purpose. Pixel scale eats subtle motion, so key moments (the C-start, the display flare, the strike, the gulp) are pushed 10–30% beyond biology to stay legible, and the push scales with camera distance. Cruise motion stays biological. Exaggeration is also contrast: a stillness that makes the dart land. |
| **SD** | Solid drawing | Bodies have volume, weight and balance. Bend without shearing voxels, keep the centre of mass and the centre of buoyancy where they are, let bottom-dwellers rest on their pelvic fins, plant shrimp feet on the ground, sit snails' feet flush with the glass. Avoid "twins": left and right fins that mirror each other, and whole schools posed identically. |
| **AP** | Appeal | Every species has a readable motion personality (guppies bustle, angelfish are stately, otocinclus are diligent, shrimp are fussy, corydoras are comic), and every individual has a signature inside it. Appeal is also clarity: clean motion without jitter, eyes that look at something, and moments that reward the keeper for watching. |

## The plan

Seven phases. Each has a gate that must hold before the next phase starts. Part
IV (invertebrates) depends only on Phases 0–1 and can run in parallel with the
fish work, one creature family per branch, since the families share no files.

| Phase | Items | What it delivers | Gate |
|---|---|---|---|
| **0. Stop cancelling motion** | 1–40 | The overwrites, sign errors, axis bugs, frame-rate drifts and corpse wags fixed. No new systems. | Full smoke suite green; a before/after clip for each fish fix, captured with `dev/swimming_capture.tscn` through `dev_run.sh`; `inspect` stills for snails, worms and anemones. |
| **1. Tools to see and primitives to build with** | 41–63, 69–120 | Core first (#41, #44, #49, #50, #52, #94, #81): `MotionSpring`, `MotionChain`, `PoseComposer`, `ActionEnvelope`, `GazeController`, `BreathOscillator`, one motion clock, per-instance shader data, the motion lab, onion skins and the speed graph. | Springs stable at 30/60/120 Hz; the composer's single-writer assertion is on in debug; the motion lab renders every species; `smoke_motion_mind_parity` unchanged. |
| **2. The fish body** | 64–68, 121–142, 221–252, 297–330, 375–396 | A spine chain with a travelling wave, volume-preserving bend, follow-through on every fin, eyes, jaw, opercula and pelvic fins, and a body that is solid and never twinned. | The phase-lag metric shows a travelling wave for every type (#87); Strouhal in range (#88); twin metric under its ceiling (#89); perf contract within budget (#700). |
| **3. Fish actions** | 143–170, 193–220, 253–296, 331–374 | Anticipation, the pose library, exposure-sheet timing, arcs and a legibility-scaled exaggeration layer. | Anticipation smoke (#107); follow-through smoke (#108); kink count (#86) and jerk p95 (#85) at or below the Phase 2 baseline outside declared actions. |
| **4. Everything that isn't a fish** | 512–655 | Shrimp, crustaceans, snails, worms, sessile animals and microfauna. | Facing smoke (#103); foot slip ≤ 10% (#102); invertebrate probe (#101) clean; every death ends in a pose (#111). |
| **5. Lives** | 427–511 | Life stages, health tells, night, feeding and social contact. | The health vocabulary (#461) is legible in a blind review (#117). |
| **6. Ensemble and presentation** | 171–192, 397–426, 656–700 | Staging, species signatures, water contact, dance, camera, and the performance work that pays for it all. | 150-fish rendered scenario no slower than the Phase 0 baseline (#695); principle scorecard (#120) at B or better for every family. |

**Ordering inside a phase.** Do the items with the highest Impact-to-Effort
ratio first, and every item that unblocks a later one. Within Phase 2 that
means #64 (the spine) before anything in Section H, and #297 (eye pivots)
before anything that involves gaze.

**One idea per PR.** Each PR says which principle it serves, which metric moved
and which clip shows it (#116), the house rule for idea docs.

**Phase 0 status (2026-10-29).** 34 of 40 items shipped; #11, #13, #17, #19
and #21 are deferred to the items that own their design, and #20 is kept
as the physics-LOD hook. Each item records what was done or why it waited.
Three bugs turned up beyond the list:
- The body-proportion genes were being erased (#7).
- Snail eye stalks never bound to their snail (#39).
- Snail stuck detection fired every 1.4 s, so every snail turned at random
  instead of holding a heading for 6–14 s.

Full suite: 260 of 265 pass. The 5 failures also fail on clean `4fc358e`
(footer labels, freed-instance guard, lifelike-motion fan count,
localization, and a `project.godot` window-scale check). A new
`smoke_snail_motion` covers the snail items.

**Phase 1 status (2026-10-30).** 68 of the 75 Phase 1 items shipped (62) or
partly shipped (6), along with three Phase 0 items that were waiting on them
(#11, #13, #17). The rest have reasons noted on each item:
- Waiting for the behaviours they test: #107–#109, #111.
- Moved into Phase 2: #69.
- Deferred: #71.
- Moved to the perf work: #112 goes with #700.

What shipped:
- The toolkit in `scripts/motion_*.gd`.
- One stroke clock for thrust and the visible tail.
- A per-draw shader wave phase.
- Motion profiles as data.
- The expression layer, cosmetic only.
- The motion lab, overlay, clip tools and probes.
- Six motion docs, the motion lint, and a smoke-runner fix: a smoke that
  failed to parse used to count as a pass.

First baseline from the new probes (short runs):
- Guppy Strouhal is 0.44 and glassdart 0.63, against a 0.2–0.4 target.
- Head-to-tail lag sits at π (a standing wave, lever 1).
- Fish average 7–8 snaps per minute.
- Legged crustaceans' feet slide 60–120% of a stride while planted (target
  ≤10%).
- Worms don't face their travel.

Phases 2 and 4 are built to move exactly these numbers.

**Phase 2 status (2026-10-30), first tranche.** 13 items shipped and 3 partly.
This tranche covers the spine pass, the travelling wave, caudal and bank
springs, fin folding, tuck, drag and roll lag, rest pitch, anti-twin
pectorals and the Strouhal tuning. The probe moved accordingly:
- Arc breaks went from 14–38 to 0–4 per fish-minute in a typical run.
- Snaps went from 7–8 to 1–3.
- Head/body→tail lag moved off π.
- Strouhal went from 0.44–0.63 to 0.36–0.41.

Still open in Phase 2 are the items that need new geometry or pivots: eyes,
jaw and opercula (#297–#307), pelvic fins (#379), veil, barbel and feeler
chains (#223, #227, #228), the shader volume bend (#121), and the multi-joint
spine (#65).

---

# Part I — Foundations

Nothing in Parts II–IV lands cleanly until the motion has one writer per
channel, a body that can carry a wave, and a way to measure what changed.

## A. Fix what is already broken (1–40)

These are defects found while auditing for this document. Several of them
quietly cancel motion that earlier passes shipped, so fixing them is the
cheapest realism in the backlog. Verify each before changing it; line numbers
are from `4fc358e`.

- [x] **1. Bank into the turn, not against it.** `bank_target` is `-yaw_rate·0.35`
  plus `Hydrodynamics.centripetal_bank`, which is `+speed·yaw·0.08`, so the
  faster a fish turns the *less* it banks
  ([fish.gd:7656](../shaders-godot/godot-project/scripts/fish.gd:7656),
  [hydrodynamics.gd:286](../shaders-godot/godot-project/scripts/hydrodynamics.gd:286)).
  Pick one convention (dorsal fin leans toward the centre of the turn) and make
  both terms agree. *AR SD · S/M*
  **Phase 0 (2026-10-29):** `centripetal_bank` now shares the base bank's sign;
  capture telemetry shows the bank into the turn on all 188 turning frames.
- [x] **2. Stop overwriting the BodyMid turn lean.** The `-yaw_rate·0.12` lean at
  [fish.gd:7672](../shaders-godot/godot-project/scripts/fish.gd:7672) is
  replaced by a plain assignment at
  [fish.gd:7885](../shaders-godot/godot-project/scripts/fish.gd:7885) on the
  same substep, so it has never been visible. Fold it into the 7885 sum. *AR · S/S*
  **Phase 0 (2026-10-29):** Folded into one `_turn_lean` (target
  `-yaw_rate·0.12`), scaled by the locomotion's base flexibility rather than
  the effort-scaled amplitude.
- [x] **3. Stop overwriting the brake flare.** The pectoral brake flare added at
  [fish.gd:7873](../shaders-godot/godot-project/scripts/fish.gd:7873) is
  overwritten by the pectoral assignments at
  [fish.gd:8004](../shaders-godot/godot-project/scripts/fish.gd:8004)/8006.
  Make braking a term inside `pec_amp`/`pec_spread`. *SI SA · S/M*
  **Phase 0 (2026-10-29):** The brake flare is a term in `pec_spread`; the
  brake pitch joined the pitch targets.
- [x] **4. Make the sleep and cleaning roll survive.** The sleep tilt
  ([fish.gd:6955](../shaders-godot/godot-project/scripts/fish.gd:6955)) and
  cleaning tilt (6942) lerp `rotation.z`, and then `_motion_substep` writes
  `rotation.z = _bank` (7670). The visible result is about 0.003 rad. Add a
  `_posture_roll` term to the bank sum instead. *PP SD · S/M*
  **Phase 0 (2026-10-29):** `_apply_posture_overlays` sets `_posture_roll`,
  which the substep adds to the bank. The cleaning pitch moved into the pitch
  targets.
- [x] **5. Key the sleep posture on sleep, not darkness.** The posture overlay at
  [fish.gd:6947](../shaders-godot/godot-project/scripts/fish.gd:6947) checks
  `daylight < 0.18`. Drive it from `_asleep`/`_sleep_depth` so a fish awake in
  the dark doesn't hang in a sleep pose and a dozing fish at dusk does. *PP TI · S/M*
  **Phase 0 (2026-10-29):** The sleep roll follows `_asleep` and deepens with
  `_sleep_depth`.
- [x] **6. Give the pregnancy bulge its own node.** The bulge scale written at
  [fish.gd:6889](../shaders-godot/godot-project/scripts/fish.gd:6889) fights
  the lerp-to-one at 7891. Put the bulge on a dedicated child of BodyMid so
  body motion and the gravid silhouette don't share a channel. *SD · S/S*
  **Phase 0 (2026-10-29):** The bulge sets `_body_mid_rest_scale`; the pose
  pass eases toward it and layers the music kick on top (one writer rather than
  a new node).
- [x] **7. One owner for `BankPivot.scale`.** Affect tweens
  ([fish.gd:1225](../shaders-godot/godot-project/scripts/fish.gd:1225)), the
  courtship pulse (8035) and death all write it. Route them through one scale
  composer (see #44) that multiplies the layers. *SQ · S/M*
  **Phase 0 (2026-10-29):** `BankPivot.scale = _body_proportions ×
  _display_scale × _affect_scale`. This also fixed a worse bug: the same pivot
  holds the body-proportion genes, and the courtship pulse and its lerp-to-one
  erased them, so any fish that had courted, or had a non-default width, lost
  its shape until reload. Affect cues now tween `_affect_scale`; the death
  shrink keeps proportions.
- [x] **8. Fix the mouthbrood anchor path.** `"Bank/BodyMid/BodyFront"` at
  [fish.gd:3712](../shaders-godot/godot-project/scripts/fish.gd:3712) doesn't
  exist, so the throat bulge falls back to the Fish root and ignores bank and
  head motion. Point it at a real node under `BankPivot`. *SD · S/S*
  **Phase 0 (2026-10-29):** The bulge parents to the head pivot.
- [x] **9. Build or delete `_gill_pivot`.** It is declared at
  [fish.gd:1085](../shaders-godot/godot-project/scripts/fish.gd:1085) and
  never assigned; the gill code falls back to scaling the whole head (6980).
  Build a real operculum pivot (#303). *SA SD · M/M*
  **Phase 0 (2026-10-29):** Deleted the never-assigned field; the operculum
  itself is #303.
- [x] **10. Write `fauna_vertex_bend`.** The uniform at
  [voxel_fauna_mm.gdshader:38](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:38)
  defaults to 1.0 and nothing sets it, so the shader body ripple runs on
  sleeping fish, resting shrimp and corpses. Drive it per instance (#50) from
  tail activity. *TI · S/L*
  **Phase 0 (2026-10-29):** Per-fish quiet level in the integer part of
  `INSTANCE_CUSTOM.a` (iridescence keeps the fraction): body ripple follows
  tail activity, sleep and death still it, and fins stop on sleep and death.
  Quantised with hysteresis, so voxels only re-upload when the level moves.
- [x] **11. Phase-lock the shader ripple to the tail.** The ripple uses global
  `TIME·6.2`
  ([voxel_fauna_mm.gdshader:152](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:152))
  while the pivots use `_swim_phase`. Pass the phase in instance data so the
  flank ripple and the tail beat are one wave. *FT TI · M/L*
  **Phase 0:** *Deferred to #50.* The per-voxel custom data is uploaded per
  handle, so a continuous per-fish phase would mean re-uploading every voxel
  every frame. It needs the instance-data design in Phase 1.
  **Phase 1 (2026-10-30):** `fauna_wave_phase` is an instance uniform each fish
  sets on its pivot MultiMeshes every posed frame, so the flank ripple is the
  tail's own wave. Fish in a shared species batch (36 or more of a kind) keep
  the global clock, since one draw serves the whole school.
- [x] **12. Take the fish wag off crustaceans.** `_bone_bend_weight` gives any
  node named `TailPivot` a bend weight of 1.0
  ([fauna_voxel_builder.gd:111](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd:111)),
  so every shrimp, crab and lobster abdomen wags sideways like a fish. Give
  crustacean voxels weight 0, or a pitch-axis flag (#517). *SD · S/L*
  **Phase 0 (2026-10-29):** `FaunaVoxelBuilder.lateral_body_wave`; shrimp
  builders turn it off, so crustacean voxels carry zero bend.
- [x] **13. Couple visible tail beat to thrust.** `_motor_phase`
  ([fish.gd:7256](../shaders-godot/godot-project/scripts/fish.gd:7256)) drives
  thrust and `_swim_phase` drives the tail, so the surges land at random against
  the strokes. Derive both from one clock (#49), with the thrust peak at
  maximum tail velocity (mid-stroke), not at maximum displacement. *TI SI · M/L*
  **Phase 0:** *Deferred to #49.* `smoke_swimming_continuity` requires
  identical physics for visible and culled fish, while the visible tail's rate
  includes mood, glide and dance factors computed only for drawn fish. Merging
  the clocks first means moving those factors into a render-independent rate.
  **Phase 1 (2026-10-30):** Done with #49. The visible tail is the stroke clock
  a quarter cycle back (`_swim_phase = _motor_phase − π/2 + offset`), so the
  tail crosses the midline as `max(0, sin)` thrust peaks.
- [x] **14. Replace the wall-bounce snap.** A hard block snaps heading 62% toward
  a reflection and sets `speed = allowed/dt`
  ([fish.gd:7557](../shaders-godot/godot-project/scripts/fish.gd:7557),
  7568). Replace it with a 0.2–0.3 s brake pose (pectorals forward, body
  pitched up, tail cupped) and a turn away that obeys the inertial cap. *SI AR · M/M*
  **Phase 0 (2026-10-29):** Physics unchanged (collision still redirects the
  path). `_note_wall_bump` holds the visual yaw on the bank pivot and eases it
  out over about 0.2 s, removes the snap from the bank's yaw rate, and raises a
  0.3 s brake pose.
- [x] **15. Remove the fish blink.** Fish have no eyelids. The 0.18 step squash
  toggled at the 10 Hz tick
  ([fish.gd:1701](../shaders-godot/godot-project/scripts/fish.gd:1701), 7964)
  reads as a flicker. Replace it with an eye roll or saccade (#300). *SD AP · S/M*
  **Phase 0 (2026-10-29):** Blink removed.
- [x] **16. Call the turn lean what it is.** `_turn_anticipation`
  ([fish.gd:7655](../shaders-godot/godot-project/scripts/fish.gd:7655)) is
  built from the *current* yaw rate, so it lags the turn. Rename it to
  `_turn_lean` and build real anticipation separately (Section E). *AN · S/S*
  **Phase 0 (2026-10-29):** Renamed `_turn_lean`; real anticipation is still
  Section E.
- [x] **17. Consume or delete `_spark_motion`.** fin_spread, tail_amp, stillness
  and the speed and turn scales are computed in
  [fish_spark_expression.gd:121](../shaders-godot/godot-project/scripts/fish_spark_expression.gd:121)
  and nothing reads them. Feed them into the pose composer as an
  "expression" layer. *AP · S/M*
  **Phase 0:** *Deferred to #44.* `FishSparkExpression.tick` never runs at
  runtime, so consuming `_spark_motion` means switching a module on. That
  should land with the pose composer, not as a fix.
  **Phase 1 (2026-10-30):** Wired as cosmetic only. The sim refreshes the
  modifiers at the brain tick for visible fish; the pose eases in `tail_amp`,
  `fin_spread` and `stillness`. Speed, turn and wander scales are deliberately
  ignored, and the phase 1 smoke checks the path is unchanged.
- [x] **18. Read `_school_phase_offset` and `_speed_personality`.** Both are set at
  [fish.gd:2203](../shaders-godot/godot-project/scripts/fish.gd:2203) and
  never read. They are exactly the per-fish tempo and phase that stop schools
  beating in lockstep. *TI SD · S/M*
  **Phase 0 (2026-10-29):** Both duplicated live state: the swim phase is
  already randomised per fish and `_cruise_mult` is already a persistent speed
  bias. Deleted, with the RNG draws kept so seeded spawns don't shift.
- [ ] **19. Let species choose their locomotion type.** `locomotion_type` is
  derived from `body_shape`
  ([fish.gd:2604](../shaders-godot/godot-project/scripts/fish.gd:2604)) and
  no `SPECIES_LIBRARY` entry
  ([tank_config.gd:1218](../shaders-godot/godot-project/scripts/tank_config.gd:1218))
  overrides it, so thunniform is unreachable and the pufferfish is treated as
  a boxfish. Add an explicit field (see Section L). *TI AP · S/M*
  **Phase 0:** *Deferred to #331.* Reclassifying (corydoras, pleco, betta, reef
  fish, puffer) changes their hydrodynamic profiles and cruise speeds, not just
  their look.
- [ ] **20. Delete the dead `move_toward` fallback.**
  `Hydrodynamics.use_full_physics` always returns true
  ([hydrodynamics.gd:290](../shaders-godot/godot-project/scripts/hydrodynamics.gd:290)),
  so the branch at
  [fish.gd:7488](../shaders-godot/godot-project/scripts/fish.gd:7488) is dead.
  Removing it makes the motor easier to reason about. *— · S/S*
  **Phase 0:** *Kept.* The fallback is the hook the physics LOD (#697) needs.
- [ ] **21. Collapse the stacked turn-rate damps.** `_motion_substep` multiplies
  the turn cap by about seven speed-, size- and age-based factors
  ([fish.gd:7402](../shaders-godot/godot-project/scripts/fish.gd:7402)–7419),
  several of which repeat each other. Replace them with one documented
  turn-radius curve (#275) so arcs can be tuned. *AR TI · M/M*
  **Phase 0:** *Deferred to #275.* Collapsing the damps without changing
  behaviour is a pure refactor; tuning them needs the arc metrics (#83) first.
- [x] **22. Shrimp eggs ride the tail.** A non-gravid shrimp frees the egg
  cluster built on `TailPivot`
  ([shrimp.gd:1785](../shaders-godot/godot-project/scripts/shrimp.gd:1785)),
  and later berried females get a new one on `BankPivot` (1892). Always
  parent it under the abdomen so the eggs move with the tail. *FT SD · S/M*
  **Phase 0 (2026-10-29):** The cluster is built once on `TailPivot` with a
  per-body-plan offset and toggled by visibility.
- [x] **23. Don't flip the shrimp to escape.** The escape flips the display heading
  ([shrimp.gd:1543](../shaders-godot/godot-project/scripts/shrimp.gd:1543)),
  but the 5.5 rad/s visual cap makes 180° take 0.57 s, longer than the 0.28 s
  escape. A real caridean shoots *backwards* with its head still facing the
  threat: keep the heading and drive velocity along `-heading`. *AR SD · S/L*
  **Phase 0 (2026-10-29):** A flip yaws at most 2 rad/s and moves tail-first,
  bent up to 0.6 rad toward safety; when safety lies ahead the shrimp bolts
  forward as before. Legs tuck during a flip.
- [x] **24. Give crab legs pivots.** Crab legs are static voxels on `BankPivot`
  ([shrimp.gd:549](../shaders-godot/godot-project/scripts/shrimp.gd:549)), so
  crabs slide. Build them like caridean legs, with pivots. *SD · M/L*
  **Phase 0 (2026-10-29):** Four hinged leg pairs on the existing gait. The
  stroke still swings along the body axis rather than the travel direction
  (#542).
- [x] **25. Check whether snails crawl sideways.** The eye stalks sit at local
  +X ([world.gd:4772](../shaders-godot/godot-project/scripts/world.gd:4772)),
  the shell coils in XY, and the creature-creator preview rotates the model 90°
  ([creature_creator.gd:1142](../shaders-godot/godot-project/scripts/creature_creator.gd:1142)),
  but the live snail aims −Z along its crawl direction
  ([snail.gd:1971](../shaders-godot/godot-project/scripts/snail.gd:1971)).
  Confirm it in `dev/inspect.tscn` and fix the basis. *SD · S/L*
  **Phase 0 (2026-10-29):** Confirmed in a sandboxed render: travel lined up
  with −Z and not at all with the eye-stalk axis. `MODEL_YAW` turns the model's
  head (+X) onto the crawl direction (head·travel 1.000 over 353 windows); the
  stalk lean, operculum and glass foot pad were re-homed to match, and the
  climb landing height now uses the body's half-length.
- [x] **26. Blend snail surface changes.** Every glass/floor/corner/film
  transition snaps orientation, because `_sync_initial_orientation` passes
  dt=1.0 ([snail.gd:1345](../shaders-godot/godot-project/scripts/snail.gd:1345),
  1974). Replace it with the edge-roll arc in #569. *AR SI · M/L*
  **Phase 0 (2026-10-29):** The logical pose still snaps, so clamps and scans
  see the right surface, but the visible model hangs off a `Body` node that
  eases position and rotation from the last drawn pose over 0.6 s. Spawn and
  load still snap.
- [x] **27. Check the film-release yank.** The sink branch at
  [snail.gd:1583](../shaders-godot/godot-project/scripts/snail.gd:1583)
  doesn't reset `_wall_anchor_offset`, so the next reclamp may pull the snail
  sideways. Confirm it and reset the offset. *SI · S/S*
  **Phase 0 (2026-10-29):** Confirmed, and worse: the stale anchor sent the
  snail under the tank floor. The anchor now moves to the substrate, and a new
  sink state drops the snail shell-first, then rights it.
- [x] **28. Squash the foot, not the shell.** `_apply_squash`
  ([snail.gd:2199](../shaders-godot/godot-project/scripts/snail.gd:2199))
  scales the whole snail node, so the shell deforms. The predator clamp sets
  `scale.y = 0.35` instantly (567). Scale only the foot, and clamp by
  translating the shell down onto it with an ease. *SQ SD · S/L*
  **Phase 0 (2026-10-29):** The snail is built as Body/Shell/Foot; squash
  deforms only the foot, and the clamp is a tuck: the shell drops onto a
  flattened foot in about 0.15 s and lifts back over about 1.4 s.
- [x] **29. Fix the bristle-worm drift.** `position.x += burrow_wave·0.014·…`
  has no `dt`
  ([bristle_worm.gd:101](../shaders-godot/godot-project/scripts/bristle_worm.gd:101)),
  so the worm drifts one way at a speed that depends on frame rate. Tie the
  motion to `sdt` and anchor it to the burrow. *TI · S/M*
  **Phase 0 (2026-10-29):** The burrow wave now pulses the drift (`0.4 +
  1.2·wave`) with `sdt`; the dt-less nudge is gone.
- [x] **30. Reverse the bristle-worm wave.** `ph = _phase + i·0.55`
  ([bristle_worm.gd:110](../shaders-godot/godot-project/scripts/bristle_worm.gd:110))
  sends the wave from tail to head. Use `_phase − i·0.55`, so the wave starts
  at the head and travels backwards. *FT AR · S/M*
  **Phase 0 (2026-10-29):** `_phase − i·0.55`: the wave travels from head to
  tail.
- [x] **31. Attach bristle-worm bristles to their segments.** Segments move in X
  and the bristles stay put. Parent each bristle pair to its segment. *SD · S/S*
  **Phase 0 (2026-10-29):** Bristles are children of their segments.
- [x] **32. Fix the sea-cucumber double step.** `_phase` is advanced twice per
  frame ([sea_cucumber.gd:119](../shaders-godot/godot-project/scripts/sea_cucumber.gd:119),
  121), and the segment-z rewrite (128) drops the build-time centring and
  spacing, which detaches the tentacles and tubercles. *SD TI · S/M*
  **Phase 0 (2026-10-29):** One phase advance, and segments stretch from their
  built, centred positions; tentacles and tubercles are parented to their
  segments.
- [x] **33. Check the anemone tentacle tips.** Tips are set to an absolute
  `y = 0.33V + lift`
  ([coral.gd:800](../shaders-godot/godot-project/scripts/coral.gd:800)), but
  they were built at `body.y + 0.33V`. Confirm in `inspect` and offset them
  from the build position. *SD · S/M*
  **Phase 0 (2026-10-29):** Confirmed. Tips are children of their tentacles, so
  the existing local lift is correct and the tips sway with them.
- [x] **34. Fix the dead-worm kick search.** It looks for worms among World's
  own children
  ([world.gd:11252](../shaders-godot/godot-project/scripts/world.gd:11252)),
  but worms live under `wriggle_root`, so the reaction never fires. *SA · S/S*
  **Phase 0 (2026-10-29):** The kick searches `wriggle_root` for bristle worms.
- [x] **35. Move the fish-egg wobble off the 10 Hz tick.** The wobble at
  [egg.gd:123](../shaders-godot/godot-project/scripts/egg.gd:123) visibly
  steps. Move it to `_process`, and make the comment (20%) match the code
  (30%). *SI TI · S/S*
  **Phase 0 (2026-10-29):** Moved to `_process` on a visual clock that trails
  the sim age.
- [x] **36. Respect `time_scale` in clams.** `clam.gd` `_process` ignores it, so
  clams keep gaping at full speed in slow motion and pause. *TI · S/S*
  **Phase 0 (2026-10-29):** Scaled by `sim.time_scale`, with an exponential
  ease.
- [x] **37. Land shrimp, don't snap them.** Within 0.22 of the substrate, Y snaps
  to substrate + 0.08
  ([shrimp.gd:1503](../shaders-godot/godot-project/scripts/shrimp.gd:1503)).
  Ease the last 0.22 in with a leg-reach pose and a small settle (#525). *SI SQ · S/M*
  **Phase 0 (2026-10-29):** Eases the last 0.22 in, grips within 0.006 and dips
  once on touchdown; walkers keep the exact floor clamp.
- [x] **38. Stop polyp retraction stepping.** Polyp tips jump to ×0.52 when
  `sin < −0.72`
  ([coral.gd:878](../shaders-godot/godot-project/scripts/coral.gd:878), 916),
  and a passing fish snaps extension to 0.08 (1199). Use an ease-in retract
  and a slow re-extend. *SI · S/M*
  **Phase 0 (2026-10-29):** Retraction eases across the threshold, and the
  fish-proximity retract takes about a quarter second instead of one frame.
- [x] **39. Ease snail eye-stalk retraction.** Clamping sets extension to 0 and
  `scale.y` to 0.1 in one frame
  ([snail.gd:2415](../shaders-godot/godot-project/scripts/snail.gd:2415)).
  Real tentacles invaginate quickly but not instantly: about 0.15 s in, about
  1.5 s back out. *SI · S/M*
  **Phase 0 (2026-10-29):** Eased: in within about 0.15 s, out over about 1.5
  s. Also fixed: the stalks never bound to the snail at all (bodies were built
  after `_ready`), so they had never animated, and the operculum always showed.
- [x] **40. Stop the shader wag on every corpse.** Shrimp and fish keep the
  vertex wave through their whole death sequence
  ([fish.gd:7048](../shaders-godot/godot-project/scripts/fish.gd:7048),
  [shrimp.gd:1856](../shaders-godot/godot-project/scripts/shrimp.gd:1856)).
  Zero the per-instance bend on death; this falls out of #10. *SD · S/M*
  **Phase 0 (2026-10-29):** Falls out of #10: death sets the top quiet level.

## B. A shared motion toolkit (41–80)

Today every creature hand-rolls its own `sin()` and `lerpf(a, b, dt·k)`.
Most of the principles need state: springs for follow-through, envelopes for
anticipation, a composer so layers add up instead of overwriting each other.
Build these once, in `scripts/motion/`, and use them everywhere.

- [x] **41. `MotionSpring`.** A second-order dynamics helper (frequency `f`,
  damping `ζ`, response `r`) with float, Vector3 and angle variants, stable
  for any `dt` (semi-implicit, with a `dt` clamp derived from `f`). `r < 0`
  gives anticipation, `r > 1` gives overshoot and `ζ < 1` gives settle. This
  one primitive covers FT, SI and AN. *FT SI AN · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_spring.gd`: f/ζ/r second-order
  dynamics with the k2 stability clamp; float, angle and Vector3 variants.
- [x] **42. Tissue presets.** A data table of spring parameters per tissue: fin
  membrane (f 4, ζ 0.45), veil fin (f 1.6, ζ 0.3), barbel (f 3, ζ 0.5), antenna
  (f 2.5, ζ 0.35), tentacle (f 1.2, ζ 0.6), shell on foot (f 2, ζ 0.7). Every
  secondary part picks a preset instead of inventing constants. *FT · S/M*
  **Phase 1 (2026-10-30):** `MotionSpring.TISSUE`: fin, caudal, veil, barbel,
  antenna, tentacle, shell, body, bank, steer, anticipate.
- [x] **43. `MotionChain`.** An n-link chain where each link springs toward its
  parent's rotation with a per-link lag and stiffness falloff. Use it for
  caudal fins, veils, barbels, feelers, antennae, tentacles and worm bodies. *FT SD · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_chain.gd`, with stiffness falloff
  toward the tip.
- [x] **44. `PoseComposer`: one writer per channel.** Each pivot channel (rot
  x/y/z, scale) gets a list of additive or multiplicative layers (locomotion,
  turn lean, posture, display, breath, expression, music, death) with weights.
  The composer writes each channel once, at the end of the substep. This
  removes the whole class of bugs in #2–#7. *PP · L/L*
  **Phase 1 (2026-10-30):** `scripts/motion_pose_composer.gd`: base + Σadd ·
  Πmul per (node, property), written once. The fish pose moves onto it with the
  spine in Phase 2.
- [x] **45. `PoseLibrary` as data.** Per-species key poses (pivot → rotation and
  scale, plus fin spread and tail spread) stored as `.tres`, with a shared
  fallback set. Section G fills it. *PP AP · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_pose_library.gd` reading
  `data/motion/poses.json`, with `_default` fallbacks; Section G fills the
  poses.
- [x] **46. Separate in and out blend times.** Every pose blend takes an
  `in_time`, `out_time` and ease curve. Alarm postures snap in (0.08 s) and
  release slowly (1.2 s); display poses ease in over 0.4 s. *SI PP · S/M*
  **Phase 1 (2026-10-30):** `MotionPoseLibrary.Blend` takes separate in and out
  times and a curve per pose.
- [x] **47. `Ease` helpers.** Smootherstep, expo-out (drag decay), back-out
  (overshoot), sine-in-out and a custom "drag" curve, as static funcs with
  unit tests. Ban new hand-written polynomials in motion code. *SI · S/M*
  **Phase 1 (2026-10-30):** `scripts/motion_ease.gd`.
- [x] **48. Replace `lerpf(a, b, dt·k)` with `damp()`.** `lerp(a, b,
  1 − exp(−λ·dt))` is frame-rate independent; `dt·k` overshoots once
  `dt·k > 1` and drifts with frame rate. Audit every instance in
  `fish.gd`, `shrimp.gd` and `snail.gd`. *TI SI · M/M*
  **Phase 1 (2026-10-30):** `MotionEase.damp()`. The fish pose block is
  converted; the brain and mood lerps stay, so mind-replay parity holds.
  `check_motion_lint.sh` (#115) stops new ones.
- [x] **49. One motion clock per creature.** A single `MotionClock` advances the
  locomotor phase from speed and body length. The tail, the thrust pulse, the
  pectoral rhythm (as a ratio), the shader ripple and the breath all derive
  from it. *TI · M/L*
  **Phase 1 (2026-10-30):** Thrust and the visible tail share `_motor_phase`.
  Its rate now includes effort (`Hydrodynamics.effort_beat_mult`), glide,
  courtship and a mood factor cached at the 10 Hz brain tick. All are state
  every fish has, so culled and drawn fish still stroke identically. Dancing is
  the one departure: it accumulates in a visual offset that eases back to a
  whole cycle.
- [x] **50. Per-instance shader data.** Pack swim phase, wave amplitude, bend axis
  and a "dead" flag into `INSTANCE_CUSTOM.gba` for every fauna voxel batch,
  and make `voxel_fauna_mm.gdshader` read them instead of `TIME`. *TI FT · M/L*
  **Phase 1 (2026-10-30):** See #11. `INSTANCE_CUSTOM.a` also carries the quiet
  level (#10).
- [ ] **51. Instance uniforms for unbatched fauna.** Snails, clams and worms use
  one `MeshInstance3D` per voxel; give them `instance uniform` phase and bend
  so shader motion is possible without batching. *SD · M/M*
  **Phase 1 (2026-10-30):** *Partly.* The instance-uniform path exists in the
  fauna shader. Snails, clams and worms use `voxel.gdshader` with no vertex
  motion, so they get it when Phase 4 batches them (#699).
- [x] **52. `ActionEnvelope`.** Every discrete action (dart, strike, gulp, flip,
  peck, lunge, hop) runs a wind-up → action → follow-through → settle state
  machine with per-species durations, instead of a bare timer and a speed
  multiplier. *AN FT SI · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_envelope.gd`, with `from_frames()`
  for exposure sheets.
- [x] **53. `GazeController`.** Picks a gaze target (food, mate, rival, threat,
  keeper, reflection, nothing), schedules saccades, and drives eye pivots and
  a head-lead offset. Shared by fish, shrimp eye-stalks and snail tentacles. *AN SA AP · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_gaze.gd`. Fish eyes need pivots
  first (#297).
- [x] **54. `BreathOscillator`.** Rate and depth from O₂, exertion, temperature
  and stress; drives opercula, mouth, buccal pumping and a tiny body bob.
  Replaces the ad-hoc breath Y-bob at
  [fish.gd:7211](../shaders-godot/godot-project/scripts/fish.gd:7211). *SA TI · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_breath.gd`.
- [x] **55. A minimal contact solver.** Plane-projection "IK" for leg tips, the
  snail foot and fish resting on substrate: find the ground under the contact
  point and rotate the limb so it touches. Bounded cost: two raycasts against
  the height field, no physics bodies. *SD · M/L*
  **Phase 1 (2026-10-30):** `scripts/motion_contact.gd`.
- [x] **56. Surface-transition planner.** A shared helper that turns "move from
  surface A to surface B" into a pivot around the shared edge over a set time
  (an arc). Used by snails, climbing shrimp and the hillstream loach. *AR SI · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_surface_transition.gd`.
- [x] **57. `MotionPersonality` per individual.** Seeded tempo (±12%), amplitude
  bias, fin-carriage bias, preferred turn side, boldness and fidgetiness,
  saved with the creature. The existing jitters at
  [fish.gd:2200](../shaders-godot/godot-project/scripts/fish.gd:2200) move
  here. *AP TI · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_personality.gd`. The fish's
  existing jitters move onto it in Phase 2.
- [x] **58. Laterality.** Real fish are lateralised: individuals favour one
  escape direction and one eye for inspecting novel things. Store a bias in
  [-1, 1] and use it for escape side, ambiguous turns and which eye faces the
  keeper. *AP SD · S/M*
  **Phase 1 (2026-10-30):** `MotionPersonality.laterality` and `choose_side()`.
- [x] **59. Motion LOD tiers.** Hero (followed or selected), near, far and
  offscreen, each with a declared feature set: hero gets everything, far drops
  chains and gaze, offscreen keeps only the clock and trajectory. Today only the
  frustum gates body animation
  ([fish.gd:7641](../shaders-godot/godot-project/scripts/fish.gd:7641)). *ST · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_lod.gd`. Tiers declare features;
  creatures consult them from Phase 2.
- [x] **60. Pixel-amplitude budget.** Compute world units per screen pixel at
  each creature (the camera already has `pixel_snap_eye`). Skip channels whose
  amplitude is under half a pixel and boost legibility-critical channels
  (Section M). *ST EX · M/M*
  **Phase 1 (2026-10-30):** `MotionLod.px_per_unit`, `legibility_gain` (capped
  at 1.3) and `worth_animating`.
- [x] **61. Motion event bus.** Emit `dart_started`, `strike`, `gulp`, `landed`,
  `flip`, `clamped` and `startled` with position and strength, for audio,
  particles, camera and neighbour reactions. Today each reaction is wired by
  hand. *ST SA · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_events.gd`. Emitters arrive with
  the actions in Phase 3.
- [x] **62. Pose history ring buffer (debug).** The last 5 s of pivot transforms
  per creature, for onion-skinning and graphs (Section C). *— · S/M*
  **Phase 1 (2026-10-30):** `scripts/motion_pose_history.gd`.
- [x] **63. Move motion constants into data.** Today the match block at
  [fish.gd:7742](../shaders-godot/godot-project/scripts/fish.gd:7742) holds
  them. Put tail amp, body amp, wavelength, pec amp and frequency, turn radius
  and bout timing in a `motion` sub-dictionary of each species. *TI · M/L*
  **Phase 1 (2026-10-30):** `scripts/fish_motion_profiles.gd` (defaults equal
  the old match block) plus `data/motion/locomotion_profiles.json`;
  `reload_data()` re-reads it.
- [ ] **64. Turn the three sibling pivots into a spine chain.** Head, BodyMid and
  TailPivot are siblings of `BankPivot`
  ([fish.gd:2848](../shaders-godot/godot-project/scripts/fish.gd:2848)), so
  rotating the mid-body doesn't carry the tail. Build Head ← Front ← Mid ← Rear
  ← Peduncle ← Caudal, with the visual pivot at each joint. This is the
  structural lever for squash/stretch, overlap and arcs in the body itself. *SD FT AR · L/L*
  **Phase 2 (2026-10-30):** *Partly.* The spine pass places the sibling Head,
  BodyMid and TailPivot along one midline each frame (the tail hangs where the
  mid-body ends), so they act as a chain without re-parenting and the peduncle
  crack is gone. A true multi-joint spine (#65) still needs re-voxelised
  segments.
- [ ] **65. Segment count by body plan.** Anguilliform 7 joints, fusiform 5,
  compressed 4, globiform 2. Small fry use 3 regardless (cost and pixel
  scale). *SD TI · M/M*
- [ ] **66. A real travelling wave.** Joint angle θᵢ = A(xᵢ)·sin(ωt − 2π·xᵢ/λ).
  Use a quadratic amplitude envelope (small at the head, maximum at the tail,
  about 0.1 body length at the tip for carangiform swimmers), with wavelength
  per type: anguilliform about 0.6 L, subcarangiform about 0.9 L, carangiform
  about 1.1 L, thunniform about 1.3 L. Today's default is a standing
  counter-wag (`body_phase = π`). *FT AR TI · M/L*
  **Phase 2 (2026-10-30):** *Partly.* The subcarangiform mid-body now leads the
  tail by a quarter cycle (`body_phase` π → π/2), so the wave travels: the
  probe's head/body→tail lag moved off π. The quadratic envelope and
  wavelength-per-type wait for more joints.
- [ ] **67. Midline from curvature, not angles.** Express the body as a midline
  curvature function (wave plus turn curvature plus pose) and integrate it to
  joint angles. Turning and swimming then add in one space, and the body keeps
  its length. *SD AR · M/M*
- [ ] **68. Follow-the-leader for elongate bodies.** For anguilliform species
  (mudsifter, gar), rear joints trace the path the head took a moment earlier,
  so a turning eel draws its arc with its whole body. *AR FT · M/M*
- [ ] **69. Separate path heading from body orientation.** Keep `heading` as the
  path tangent and let the head and eyes lead it by up to 0.3 rad. This is the
  hook for anticipation and gaze; today `_face_direction` ties the whole body
  to the path ([fish.gd:7140](../shaders-godot/godot-project/scripts/fish.gd:7140)). *AN AR · M/L*
  **Phase 1 (2026-10-30):** *Moves to Phase 2* with the head lead (#143): the
  split is only worth making when something leads.
- [x] **70. A common `CreatureMotor` interface.** Desired velocity, gait phase,
  contact state, current action and pose weights, exposed the same way by
  fish, shrimp, snails and worms, so probes and overlays work on all of them. *— · M/M*
  **Phase 1 (2026-10-30):** `scripts/motion_creature_view.gd`: fish, shrimp,
  snail and others behind one read-only view.
- [ ] **71. Fixed-rate motion integration.** Integrate motion at a fixed 60 Hz
  with render interpolation, instead of variable substeps (1–20 for fish
  ([fish.gd:6914](../shaders-godot/godot-project/scripts/fish.gd:6914)), 1–7
  for shrimp). Springs, chains and replays become deterministic. *TI · L/M*
  **Phase 1 (2026-10-30):** *Deferred.* Fixed-rate integration is a wide
  physics change, and `smoke_motion_phase1` shows fish already land within 0.03
  u at 60 vs 120 Hz. Revisit if the spine's springs drift.
- [x] **72. A frame-rate equivalence harness.** Run each creature's motion at
  30/60/120/144 Hz from one seed and compare trajectories and pose channels
  within a tolerance. This extends the existing walking-consistency check
  to everything. *TI · M/M*
  **Phase 1 (2026-10-30):** In `smoke_motion_phase1` (fish at 30/60/120 Hz);
  shrimp at 30/120 Hz are in `smoke_living_locomotion`.
- [ ] **73. Seeded motion randomness.** Every jitter, fidget and saccade draws
  from a per-creature stream in `sim_rng.gd`, never from global `randf()`,
  so captures can be compared before and after. *— · S/M*
  **Phase 1 (2026-10-30):** *Partly.* Fish motion already draws only from
  seeded per-fish streams. The invertebrates use global `randf()` (79 calls in
  `snail.gd` alone) and convert with their Phase 4 rework.
- [x] **74. Smooth noise instead of sums of sines.** A small 1D simplex/value
  noise helper for wander, fin flicker and antenna sway. Two or three sines
  beat visibly over minutes; noise doesn't. *SA AP · S/M*
  **Phase 1 (2026-10-30):** `scripts/motion_noise.gd`.
- [x] **75. A periodicity audit.** List every `sin(TIME·k)` and fixed-rate
  oscillator in motion code and shaders. Make ratios incommensurate (scale by
  the golden ratio) or move them to noise, so no fin flicks on a visible
  metronome. *TI · S/M*
  **Phase 1 (2026-10-30):** The fauna shader's oscillators (fin flutter 10.5,
  vertical 5.3, fallback ripple 6.2 rad/s) have no small-integer ratios, and
  the stroke clock wraps at 100·2π so its 1.3× and 0.28× harmonics stay
  continuous. Nothing beats visibly; the wander sines move to noise with #277.
- [x] **76. Hysteresis for behaviour-to-pose switching.** A pose can't re-enter
  within N seconds of leaving, and enter and exit thresholds differ, so a fish
  near a threshold doesn't flicker between hover and cruise poses. *PP SI · S/M*
  **Phase 1 (2026-10-30):** `MotionEnvelope.Hysteresis`.
- [x] **77. Defined rest poses.** Every species declares a neutral pose (fin
  carriage, tail spread, head angle). Every layer decays to it, not to zero
  rotation. A betta at rest carries its fins half spread, not clamped. *PP AP · S/M*
  **Phase 1 (2026-10-30):** `MotionPoseLibrary.rest_pose()`; every pose
  inherits rest channels.
- [x] **78. Reduce-motion support.** One setting scales exaggeration, camera
  reactions and fast flicker down by 60% and removes strobing. Ties into
  accessibility and potato mode. *EX · S/M*
  **Phase 1 (2026-10-30):** `MotionLod.exaggeration_scale()` reads the existing
  reduced-motion setting; exaggeration (Section M) goes through it.
- [ ] **79. A motion budget ledger.** Declare per-creature motion cost (CPU µs,
  draw calls) per LOD tier in one table, and make the perf contract read it. *— · S/M*
  **Phase 1 (2026-10-30):** *Partly.* [MOTION_BUDGET.md](MOTION_BUDGET.md)
  holds per-tier targets and the measured facts, kept apart. No per-tier cost
  has been measured yet, and the perf contract doesn't read the ledger (#700).
- [x] **80. Document the motion architecture.** Who writes which channel, the
  layer order and the clocks, as a section in `docs/ARCHITECTURE.md`, so the
  next pass doesn't reintroduce overwrites. *— · S/M*
  **Phase 1 (2026-10-30):** [ARCHITECTURE.md](ARCHITECTURE.md) §11: rig, frame
  order, the writer of every channel, layer variables, clocks, shader contract
  and rules.

## C. Seeing and measuring motion (81–120)

The existing probes measure behaviour (depth bands, speed CV, hover and dart
percentages). None of them measures whether motion *looks* right. Each
principle has a number that can be checked.

- [x] **81. Onion skins in the debug overlay.** In `motion_debug_overlay.gd`,
  draw the last 30 head and tail-tip positions as dots, spaced in time. Clumped
  dots at the ends of a move are slow in/out; evenly spaced dots mean the
  motion is mechanical. *SI AR · S/L*
  **Phase 1 (2026-10-30):** Shift+M in game (`motion_debug_overlay.gd`): 30
  onion-skin dots each for head and tail tip, sampled at 30 Hz, for the
  followed fish or the one nearest screen centre.
- [x] **82. A speed graph for the selected creature.** A 10 s speed trace with
  bout-change markers. A burst should look like a cliff and a long tail, not a
  square wave. *SI TI · S/M*
  **Phase 1 (2026-10-30):** A 10 s speed graph with bout, burst, startle and
  motion-event markers.
- [x] **83. A curvature overlay.** Colour the head path by curvature and flag
  discontinuities (kinks) in red. Arcs should be continuous; kinks are snaps. *AR · S/M*
  **Phase 1 (2026-10-30):** The body-centre path coloured by curvature, with
  breaks ticked in red (the head tip carries the body wave, so it read as false
  breaks).
- [x] **84. A side-view tail-tip trace.** Plot the caudal tip in the fish's own
  frame; a healthy swimmer draws a flattened figure-eight. *AR SD · S/M*
  **Phase 1 (2026-10-30):** Tail-tip traces in the fish's own frame, top and
  side.
- [x] **85. A jerk metric.** Mean and p95 of |d³x/dt³| per species from the
  behaviour probe. Spikes outside declared explosive actions are bugs. *SI · M/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.jerk`.
- [x] **86. A heading-kink count.** Frames where |Δyaw| exceeds the inertial
  cap without a startle or C-start flag. *AR · S/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.heading_kinks`, with exempt frames.
- [x] **87. A body phase-lag metric.** The phase difference head → mid → tail. A
  travelling wave has monotonic lag; a standing wave has 0 or π. Assert it per
  locomotion type. *FT · M/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.phase_lag` (projection at the beat
  frequency).
- [x] **88. A Strouhal check.** St = f·A/U at cruise, asserted in 0.2–0.4 for
  body-caudal swimmers. Catches tails beating too fast for the speed (the
  "paddling in place" look). *TI · S/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.strouhal` and `dominant_hz`.
  **Phase 2 (2026-10-30):** Measured in the probe. Guppy and glassdart Strouhal
  went from 0.44–0.63 to 0.36–0.41 by trimming subcarangiform `tail_amp` to
  0.28 and the speed-added amplitude, since real fish speed up by beating
  faster, not wider.
- [x] **89. A twin metric.** Correlation of left and right pectoral angles over
  10 s, and pose correlation between school neighbours. Assert both below a
  ceiling, so fins and fish don't mirror each other. *SD · S/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.correlation`.
- [ ] **90. A sub-pixel report.** For each animated channel, the screen-space
  amplitude at the default camera. Flag channels under 0.5 px (wasted CPU)
  and over-twitchy channels that shimmer through the palette quantize. *ST · M/M*
  **Phase 1 (2026-10-30):** *Partly.* `MotionLod.amplitude_px` and
  `worth_animating` give the numbers; a per-channel report needs the probe
  columns.
- [x] **91. A single-writer assertion (debug).** The pose composer asserts one
  write per channel per frame, so overwrites like #2–#4 can't return. *— · S/M*
  **Phase 1 (2026-10-30):** `MotionPoseComposer` reports writes that bypass it
  (debug builds).
- [x] **92. A snap detector (debug).** Log any pivot or root transform that
  moves more than a threshold in one frame without a motion event flag. *SI · S/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.snaps` for recorded channels.
- [x] **93. A "corpse wag" smoke.** After death the per-instance bend is 0 and
  no pivot rotates except the death sequence. *SD · S/S*
  **Phase 1 (2026-10-30):** In `smoke_motion_phase1`: death sets quiet level
  15, and it reaches the voxels' instance data.
- [x] **94. A motion lab scene.** `dev/motion_lab.tscn`: one creature per
  species on a neutral backdrop, orthographic side, top and front views, a
  timeline scrubber, 0.1× slow motion, and buttons to trigger each action
  (dart, startle, strike, gulp, display, die). Isolated through `dev_run.sh`. *— · M/L*
  **Phase 1 (2026-10-30):** `dev/motion_lab.tscn`: every species plus caridean,
  crab, lobster, mantis and a snail on a neutral stage with no World or saves;
  side, top and front orthographic views; scripted paths; actions dart,
  startle, gulp, display, court, die, flip, retract and clamp. There is no
  strike to trigger yet.
- [x] **95. Slow motion and frame-step in dev builds.** A hotkey for
  `time_scale` 0.1 and single-frame stepping, so animation can be judged the
  way animators judge it. *— · S/M*
  **Phase 1 (2026-10-30):** In the lab: 0.1×–2×, pause, single-frame step, and
  a scrubber over the last 600 frames.
- [x] **96. A reference library.** `docs/MOTION_REFERENCE.md`: real footage and
  papers per species and behaviour (zebrafish C-start high-speed video, guppy
  sigmoid display, corydoras surface dash, shrimp tail flip, nerite crawl,
  daphnia hop), each with what to look for. *— · S/L*
  **Phase 1 (2026-10-30):** [MOTION_REFERENCE.md](MOTION_REFERENCE.md). Sources
  are named only where certain; the rest are search terms.
- [x] **97. Published kinematic numbers in one table.** Tail-beat amplitude
  about 0.2 L at the tip; stride length 0.6–0.7 L per beat; C-start stage 1
  about 10–20 ms and stage 2 about 20–40 ms; shrimp flip about 30–50 ms;
  Strouhal 0.2–0.4. Each tuning constant cites a row. *TI · S/M*
  **Phase 1 (2026-10-30):** The kinematics table in
  [MOTION_REFERENCE.md](MOTION_REFERENCE.md), with a confidence level, the
  constant it calibrates and today's value per row. The code declares no world
  scale (one comment implies 1 u ≈ 1 m, the backlog assumed 6 cm), so it
  calibrates in body lengths.
- [x] **98. Clip capture.** A dev script that records a 4 s clip of the motion
  lab to `output/motion_lab/*.gif` for review. *— · S/M*
  **Phase 1 (2026-10-30):** `dev/motion_clip.tscn` writes PNG frames,
  `motion.csv` and `meta.json`; `tools/motion_clip_compose.py gif DIR` makes
  the GIF.
- [x] **99. Before/after pairs.** The same seed and scenario, before and after,
  composed side by side into one clip, so every PR in this backlog ships a
  visual diff. *— · S/M*
  **Phase 1 (2026-10-30):** `motion_clip_compose.py pair BEFORE AFTER` lays two
  clips side by side; the same seed replays identically.
- [x] **100. Motion columns in the fish behaviour probe.** Add jerk, kink count,
  Strouhal, phase lag, twin correlation and snap count to
  `dev/fish_behaviour_probe.tscn`. *— · M/M*
  **Phase 1 (2026-10-30):** `fish_behaviour_probe` adds a motion-quality
  section: jerk, kinks, arc breaks, head→tail lag, tail Hz, Strouhal, pectoral
  twin and neighbour correlation, snaps.
- [x] **101. An invertebrate motion probe.** Stance ratio, foot slip, turn rate,
  facing error and surface-transition duration for shrimp, crabs, snails and
  worms. *— · M/M*
  **Phase 1 (2026-10-30):** `dev/invert_motion_probe.tscn`: speed, turn rate,
  facing, stance, foot slip and surface/emerge transitions per type.
- [x] **102. A foot-slip metric.** How far the leg tip slides along the ground
  during stance; target ≤ 10% of stride. *SD · S/M*
  **Phase 1 (2026-10-30):** `MotionMetrics.foot_slip`.
- [x] **103. A facing smoke.** Snails, worms, cucumbers and trumpet snails face
  their direction of travel (dot > 0.9 once moving). Catches #25 and its
  siblings. *SD · S/M*
  **Phase 1 (2026-10-30):** The invertebrate probe measures facing for every
  type. Snails pass (0.97); worms fail (bristle 0.14, wriggle −0.01), as Phase
  4 (#598) expects.
- [x] **104. Frame-rate smokes for every creature.** Built on #72. *TI · S/M*
  **Phase 1 (2026-10-30):** Fish, shrimp and snails have frame-rate checks;
  worms join with Phase 4.
- [x] **105. Motion captures in the visual baseline.** Add motion-lab stills at
  fixed phases to `scripts/visual_baseline_matrix.sh`. *— · S/M*
  **Phase 1 (2026-10-30):** `visual_baseline_matrix.sh` adds motion-lab stills
  (guppy, betta, corydoras, crab at four beat phases).
- [x] **106. An exposure sheet per behaviour.** Document each action's key poses
  and frame counts at 60 fps (dart: 6 frames wind-up, 4 strike, 24 glide, 12
  settle), as the spec the code is tested against. *TI PP · S/M*
  **Phase 1 (2026-10-30):**
  [MOTION_EXPOSURE_SHEETS.md](MOTION_EXPOSURE_SHEETS.md): 14 actions at 60 and
  30 fps, with the 30 fps floors (#687).
- [ ] **107. Smoke: anticipation precedes action.** Every dart, strike and flip
  shows a wind-up state for at least its species minimum before peak speed. *AN · S/M*
  **Phase 1 (2026-10-30):** *Waits for Section E*: there are no wind-ups to
  test yet.
- [ ] **108. Smoke: follow-through after stops.** Tail amplitude decays over at
  least 0.3 s after thrust ends, rather than stopping on the frame. *FT · S/M*
  **Phase 1 (2026-10-30):** *Waits for #230*, which makes the tail swing on
  after thrust stops.
- [ ] **109. Smoke: no constant-speed segments between rests.** The speed curve
  between any two rests has non-zero acceleration at both ends. *SI · S/M*
  **Phase 1 (2026-10-30):** *Waits for Phase 3* timing work.
- [ ] **110. Smoke: crustacean flips are in pitch.** The abdomen flexes about X
  during an escape, not about Y. *SD · S/S*
  **Phase 1 (2026-10-30):** *Partly.* `smoke_motion_phase1` checks crustacean
  voxels carry no lateral bend; the pitch-axis flip test comes with the
  segmented abdomen (#517).
- [ ] **111. Smoke: every death ends in a pose.** Fish belly-up or sunk, snail
  as an empty shell, shrimp curled. None vanishes mid-water. *PP · S/M*
  **Phase 1 (2026-10-30):** *Waits for Phase 5.* Snail old age, clams and worms
  still vanish (#455–#457).
- [ ] **112. A motion perf counter.** Per-creature motion µs in the dev overlay,
  coloured against the #79 budget. *— · S/M*
  **Phase 1:** *Moves to #700*, where per-creature motion cost gets measured
  against the budget ledger (#79).
- [x] **113. Hot-reloaded motion data.** Edit the `motion` sub-dictionary and see
  it apply in the motion lab without a restart. *— · M/M*
  **Phase 1 (2026-10-30):** The lab's "Reload motion data" calls
  `FishMotionProfiles.reload_data()` and `MotionPoseLibrary.reload_data()`.
- [ ] **114. A tuning panel.** Dev sliders for spring presets, wave parameters
  and envelope timings that write back to data. Tuning by eye is how this
  work gets good. *— · M/L*
  **Phase 1 (2026-10-30):** *Partly.* The lab tunes `MotionSpring.TISSUE`
  presets against a live step response and saves `tissue_tuning.json`. The
  presets are a const, and nothing in the game reads them yet, so the sliders
  preview rather than tune live.
- [x] **115. A motion lint.** A check in `check_warnings.sh` style that flags new
  `lerpf(…, dt *` in motion files and new `sin(TIME` in fauna shaders. *— · S/M*
  **Phase 1 (2026-10-30):** `scripts/check_motion_lint.sh` with
  `scripts/motion_lint_baseline.txt`, run in CI next to the warnings check. A
  file can only go down. While building it, the smoke runner turned out to
  count a smoke that failed to parse as a pass; `run_smokes.sh` now fails it.
- [x] **116. A principle line in the PR template.** "Which principle does this
  serve; which metric moved; which clip shows it." *— · S/S*
  **Phase 1 (2026-10-30):**
  [MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md) and a "Motion changes"
  section in CONTRIBUTING.md; the repo has no PR template.
- [x] **117. A blind real-or-game review.** Every few milestones, cut 10 s clips
  of real footage and game footage at matched framing, and have someone who
  hasn't seen the work rank "which looks alive". Track the score. *AP · S/M*
  **Phase 1 (2026-10-30):**
  [MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md): clip spec, raters,
  forced choice plus 1–5 scores, noise estimate and results log.
- [x] **118. Motion CSV export per species.** Generalise the swimming pass's
  `motion.csv` (heading, speed, bank, every pivot channel) to every species
  and action. *— · S/M*
  **Phase 1 (2026-10-30):** `motion_clip` writes every pivot channel per frame,
  legs included.
- [x] **119. Track kinematic distributions, not means.** Report p10/p50/p90 of
  speed, turn rate and bout length. A creature with the right mean and no
  variance looks robotic. *TI · S/M*
  **Phase 1 (2026-10-30):** The probe reports p10/p50/p90 of speed, turn rate
  and bout length.
- [x] **120. A principle scorecard.** One page, updated per milestone: each of
  the twelve principles × each creature family, graded from motion-lab clips
  and metrics. Shows where to spend the next pass. *— · S/L*
  **Phase 1 (2026-10-30):** [MOTION_SCORECARD.md](MOTION_SCORECARD.md), graded
  at `5ad6dd3`. No family is at B yet; staging and exaggeration are D or worse
  everywhere.

---

# Part II — Fish, principle by principle

Fish are most of the motion on screen, so each principle gets its own
section. Most items assume the toolkit in Part I (spine chain #64, composer
#44, springs #41, envelopes #52); where an item can ship without it, it says
so.

## D. Squash and stretch: bodies that keep their volume (121–142)

Today the only scale changes on a fish are the courtship pulse, a 3% music
kick, the post-meal gape, the gill flush and affect tweens
([fish.gd:7888](../shaders-godot/godot-project/scripts/fish.gd:7888),
[fish.gd:1225](../shaders-godot/godot-project/scripts/fish.gd:1225)). In
water, squash and stretch is anatomy: a bending body keeps its volume.

- [ ] **121. Flank stretch from curvature.** In `voxel_fauna_mm.gdshader`,
  push each voxel along the body axis by `curvature × lateral offset × k`. The
  convex flank lengthens, the concave flank shortens, and the volume is
  conserved. This is the volume-preserving bend, done per voxel and free for
  batched schools. Needs #50. *SQ SD · M/L*
- [ ] **122. C-start coil.** During stage 1 of an escape (#145), the body's
  chord length drops about 8% and girth rises about 4%. That is the visible
  "coiled spring". *SQ AN · S/L*
- [ ] **123. Strike stretch.** At peak strike velocity the body lengthens 4–6%
  along Z for three frames, then recovers through a spring with a small
  overshoot. *SQ EX · S/M*
- [ ] **124. Expand the buccal cavity *before* contact.** Suction feeders expand
  the mouth and throat 40–60 ms before the bite, and the food is pulled in by
  that expansion. Today the gape fires after the meal is recorded
  (`_record_meal_at` → `_trigger_mouth_gape`,
  [fish.gd:1749](../shaders-godot/godot-project/scripts/fish.gd:1749)). Move
  it ahead of contact and drive head width, not head length. *SQ AN · S/L*
- [ ] **125. A belly that fills.** Satiety (gut content) inflates the BodyMid
  belly 0–6% in Y, deflating over digestion. A full fish then reads as heavier,
  and its timing (#355) follows. *SQ SD · S/M*
- [ ] **126. Birth deflation with recoil.** A gravid livebearer drops fry and
  deflates quickly (0.4 s) with a small rebound, rather than lerping back
  over many seconds. *SQ FT · S/S*
- [ ] **127. Pufferfish inflation.** Only under a real strike or capture: 4–6
  gulps over about 0.6 s, scaling to about 1.7×, with spines standing (spine
  voxels pushed out along their normals), then a slow 6–10 s deflation with
  burps. It is rare and stressful in real fish, so make it rare and costly to
  the fish's stress, and never a toy. *SQ EX AP · M/L*
- [x] **128. Caudal spread and furl.** The caudal fin spreads (scale Y +10–15%)
  through the power stroke and furls at reversal and during glides. Today
  caudal `scale.y` only changes for fin nicks
  ([fish_alive.gd:248](../shaders-godot/godot-project/scripts/fish_alive.gd:248)). *SQ FT · S/L*
  **Phase 2 (2026-10-30):** Tail `scale.y` widens up to 12% as the tail sweeps
  the midline, scaled by activity; fin tears multiply in through
  `_tail_nick_scale` (the pose now owns that channel).
- [x] **129. Fold median fins at speed.** Real fish depress the dorsal and anal
  fins during bursts to cut drag and erect them for slow manoeuvring and
  turning. Drive dorsal and anal erection from `1 − speed/max` plus a turn
  term. Today they are pure functions of swim phase
  ([fish.gd:7969](../shaders-godot/godot-project/scripts/fish.gd:7969)). *SQ SD · S/L*
  **Phase 2 (2026-10-30):** Dorsal and anal fold back with speed (smoothstep
  0.35–0.9 of max) and stand up again in turns.
- [x] **130. Tuck the pectorals in bursts.** A clear adducted pose (pectorals
  flat against the body) above 70% of max speed, separate from the gradual
  `pec_amp` reduction. *SQ · S/M*
  **Phase 2 (2026-10-30):** Above about 65% of max speed the pectorals tuck:
  spread −0.25, amplitude −60%.
- [ ] **131. Landing squash for bottom fish.** Corydoras, plecos, gobies and
  loaches touching down compress about 3% in Y over two frames, splay pelvic
  and pectoral fins, and recover. This is where their weight shows. *SQ SD · S/M*
- [ ] **132. Hop take-off stretch.** Gobies and hillstream loaches stretch
  slightly on take-off and squash on landing (#293). *SQ AR · S/S*
- [ ] **133. A labyrinth gulp.** Bettas and gouramis gulp at the surface with
  the head stretched up and the throat swollen, then a swallowing contraction
  runs backwards along the throat. A spent-air bubble leaves the gill or mouth
  (#315). *SQ SA · M/M*
- [ ] **134. Global caps.** Hard limits of ±8% for adults, ±12% for fry, and
  ±25% only for gape and puffer inflation, so nothing ever reads as rubber. *SQ SD · S/M*
- [x] **135. Soft fry, stiff elders.** Flexibility (bend gain and squash gain)
  scales with growth stage from `fish_growth.gd`: fry bend about 1.3×,
  senescent fish about 0.7×. *SQ TI · S/M*
  **Phase 2 (2026-10-30):** Body bend and head wave ×1.2 for fry, ×0.75 for
  senescent fish.
- [ ] **136. Collision squash.** When a fish actually hits glass or another fish
  (the panic case), it compresses for two frames and recoils. Pair this with
  the brake pose in #14. *SQ SI · S/S*
- [ ] **137. Jaw protrusion.** Guppies, cichlids and gouramis protrude the upper
  jaw on a bite. Translate the mouth voxels forward about 0.3 v during a
  strike and retract after. This is a stretch of the head, not a scale. *SQ SA · S/M*
- [ ] **138. Breathing girth.** A ±1% girth pulse at rest, in phase with the
  opercula (#303). It is only visible at hero LOD, and only when nothing else
  is moving. *SQ SA · S/S*
- [ ] **139. Eel concertina.** When the mudsifter reverses, burrows or squeezes
  between objects, it compresses into a tighter S (wavelength ×0.6), then
  extends. *SQ AR · M/M*
- [ ] **140. Effortful-stroke girth.** On the first two beats of a burst, the
  peduncle region narrows visibly as the tail loads (scale X −4% at the rear
  segment). *SQ AN · S/S*
- [ ] **141. Gravid belly as its own node.** Builds on #6: the bulge sits on its
  own child of the mid segment, so it bends with the body and doesn't scale
  the fins. *SQ SD · S/S*
- [ ] **142. A squash-and-stretch review clip.** A motion-lab clip per body plan
  with the shader stretch at 0×, 1× and 2×, so the gain is chosen by eye. *SQ · S/S*

## E. Anticipation: every action is telegraphed (143–170)

The only true anticipation in the fish code is `aim_before_burst` before a
feeding frenzy
([fish.gd:5133](../shaders-godot/godot-project/scripts/fish.gd:5133)). The
"turn anticipation" lags the turn (#16), and darts, startles, zoomies and
music surges start at full speed on the frame they are chosen.

- [ ] **143. The head leads the turn.** The head and eyes rotate 0.1–0.3 rad
  toward a new heading 80–150 ms before the trunk follows, using the
  path/body split in #69. This is the most important anticipation cue a fish
  has. *AN AR · M/L*
- [ ] **144. The eyes lead the head.** Eye pivots (#297) rotate toward a new
  target about 60 ms before the head moves. *AN SA · S/M*
- [ ] **145. A real C-start.** Stage 1: the body bends into a C, with the head
  swinging away from the threat and the heading rotating 60–120° *without*
  the inertial turn cap. Stage 2: one large propulsive stroke the other way.
  Then a coast. Real stage 1 takes 10–20 ms; stretch it to 3–4 frames (50–70 ms)
  so it reads at 60 fps (#342). Today's startle is a heading change still bound
  by `inertial_turn`
  ([fish_life_bouts.gd:151](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:151)). *AN SQ EX · L/L*
- [ ] **146. An S-start for predatory lunges.** The gar and killifish strike from
  an S-shaped coil, then straighten into the lunge. It is a different shape
  from the C-start, and the difference reads as "hunting", not "fleeing". *AN SQ · M/M*
- [ ] **147. A pectoral scull before a voluntary dart.** 0.1–0.2 s of pectoral
  back-scull with the body still. It reads as a decision being made. *AN · S/M*
- [ ] **148. Tail cock.** The first beat of any burst starts from a held lateral
  tail position, opposite the first power stroke. Today the tail phase just
  continues from wherever it was. *AN · S/M*
- [ ] **149. Fixation before every bite.** Halt 0.15–0.3 s, converge the eyes,
  align the body and back-scull slightly, then strike. Extend `aim_before_burst`
  to all feeding, including pecks
  ([fish_life_bouts.gd:286](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:286)). *AN ST · S/L*
- [ ] **150. Wire `feed_anticipation_drift`.** It exists in
  `fish_spark_behavior.gd` and is never called. Real fish learn the feeding
  schedule and gather at the feeding spot beforehand. This is anticipation at
  the behaviour level, and keepers notice it immediately. *AN AP · S/L*
- [ ] **151. Begging at the glass.** Around feeding time, or when the keeper's
  cursor rests near the front glass, bold fish gather and dance up and down
  against the glass. The guardian already approaches the glass when hungry
  ([guardian_fish.gd:36](../shaders-godot/godot-project/scripts/guardian_fish.gd:36));
  give it, and others, the begging motion. *AN AP · M/L*
- [ ] **152. A shaped surface gulp.** Nose up 15–25°, accelerate up in an arc,
  gulp, then turn and dive. Today it is a `home_y` change
  ([fish.gd:4271](../shaders-godot/godot-project/scripts/fish.gd:4271)). *AN AR · M/M*
- [ ] **153. A visible freeze.** The pre-flee freeze from
  `MotionField.inject_startle`
  ([motion_field.gd:39](../shaders-godot/godot-project/scripts/motion_field.gd:39))
  currently only slows the fish. Make it a pose: fins snap closed, the tail
  centres, breathing stops, eyes fix. *AN PP · S/L*
- [ ] **154. Roll into the turn first.** Begin the bank one or two frames before
  yaw rate rises, driven from the turn *target*, not the realised yaw rate. *AN AR · S/M*
- [ ] **155. Effort before speed.** Tail amplitude steps up one beat before speed
  rises, because the stroke causes the speed. Verify the order in the speed
  graph (#82). *AN TI · S/M*
- [ ] **156. Brake before arrival.** Begin braking at `speed²/(2·decel)` from a
  target (plant, cave, food, partner), with a pectoral flare, so fish arrive
  rather than overshoot and correct. Use the unused
  `Hydrodynamics.overshoot_bias`
  ([hydrodynamics.gd:279](../shaders-godot/godot-project/scripts/hydrodynamics.gd:279))
  as a deliberate small overshoot for large species only. *AN SI · S/M*
- [ ] **157. A male notices a female.** Dorsal lift, head turn and colour flush
  0.3 s before the approach begins. *AN ST · S/M*
- [ ] **158. Threat before the charge.** The aggressor lowers its head, flares
  its opercula and holds 0.3–1 s, then charges. This gives the target time
  to react, which is staging as well as realism. *AN ST · M/M*
- [ ] **159. Graded urgency.** Wind-up length scales inversely with urgency:
  startle 3–4 frames, feeding strike 150–300 ms, voluntary relocation
  0.3–0.8 s ("looks, then goes"). Declare it per action in the exposure sheet
  (#106). *AN TI · S/M*
- [ ] **160. Visible hesitation.** At a fork (two food items, two shelters), a
  fish sometimes starts toward one, checks, and corrects. The decision becomes
  visible. *AN AP · M/M*
- [ ] **161. Predator inspection.** Guppies and other shoalers approach a
  threat cautiously, in pairs, in stop-start steps, then retreat. This is
  well documented. Use it for a large new tank-mate or the keeper's net. *AN AP · M/L*
- [ ] **162. Track the threat before fleeing.** For a slow approaching threat
  (net, hand, big fish), fish track it with eyes and head for 0.5–1 s before
  the startle triggers. *AN ST · S/M*
- [ ] **163. Wire `signal_reaction_delay`.** It exists in
  `fish_spark_behavior.gd` and is never called. Alarm reactions start
  80–250 ms after the signal, depending on distance and attention, so the
  viewer sees the first fish react and the rest follow. *AN TI ST · S/L*
- [ ] **164. The leader tells.** In a school, the fish that initiates a turn
  (highest `motion_lead_boost`,
  [motion_school.gd:202](../shaders-godot/godot-project/scripts/motion_school.gd:202))
  shows a head turn and bank 1–2 frames before its turn intent is injected.
  The wave then visibly starts somewhere. *AN ST · S/M*
- [ ] **165. Scull before reversing.** Hovering fish that reverse direction
  back-scull with the pectorals for 2–3 beats before moving backwards. *AN · S/S*
- [ ] **166. Bottom take-off.** Corydoras and plecos lift the head slightly and
  splay the pectorals for one frame before leaving the substrate. *AN SD · S/S*
- [ ] **167. Rising pre-gulp.** Before a gulp, a labyrinth fish hangs nose-up
  under the surface for a moment, then rises. *AN · S/S*
- [ ] **168. Pre-strike stillness for stalkers.** The gar drifts motionless
  (fin sculling only) for 1–3 s before an S-start. *AN EX · S/M*
- [ ] **169. Route music surges through envelopes.** The beat surge
  ([fish.gd:4044](../shaders-godot/godot-project/scripts/fish.gd:4044))
  reuses the startle fields and lands at full speed. Route it through
  `ActionEnvelope` with `beat_anticipation`
  ([music_choreography.gd:23](../shaders-godot/godot-project/scripts/music_choreography.gd:23)),
  so dance moves wind up on the pre-beat and hit on the beat. *AN TI · M/L*
- [ ] **170. An anticipation smoke.** Every dart, strike and C-start shows its
  wind-up state for at least its declared minimum before peak speed (#107). *AN · S/M*

## F. Staging: make the important motion unmistakable (171–192)

The render is 1024×576 at most and drops as low as 256×144 under load. At the
default camera a tank unit is roughly 45 px tall at 576 rows and 22 px at 288,
so a one-unit fish is 22–45 px long and a 0.1-unit tail swing is 2–5 px
(estimated from FOV 45, radius 15.5). Motion that doesn't reach a pixel
doesn't exist, and the palette quantize turns sub-pixel jitter into shimmer.

- [ ] **171. A legibility floor.** Key channels (tail swing, fin erection,
  strike stretch, gulp) reach at least 2 px at the default camera and the
  current resolution tier, using #60. *ST EX · M/L*
- [ ] **172. Camera-relative beat legibility.** A fish crossing the frame
  broadside bends its tail toward and away from the camera, so the beat is
  foreshortened to almost nothing. When the lateral bend axis is near the view
  direction, emphasise what the camera *can* see: caudal spread and furl
  (#128), a small vertical heave of the tail tip (#283), and outline change
  through the shader stretch (#121). *ST SD · M/L*
- [ ] **173. Broadside displays toward the camera.** Courtship and threat
  displays are perpendicular to the receiver. When either side would do, pick
  the side that faces the camera. *ST · S/L*
- [ ] **174. Clear the stage.** During a key event (birth, courtship climax,
  fight, death), nearby non-participants get a mild yield field and give
  space, as real fish give fighting fish space. *ST · M/M*
- [ ] **175. An event budget.** At most two or three "big" actions run at once
  in one region of the screen. Optional fidgets, zoomies and play bursts wait
  while an event is on. *ST TI · M/M*
- [ ] **176. A silhouette mode.** A dev toggle that renders fauna flat black on
  white, to judge whether alert, display, sleep and clamped poses read by
  outline alone. *ST SD · S/M*
- [ ] **177. Line-of-sight for events.** Courtship sites, spawning sites and
  rest spots prefer positions with a clear ray to the camera (a cheap test
  against plant AABBs), within what the behaviour allows. *ST · M/M*
- [ ] **178. Lead room for the follow camera.** When following a fish, offset
  the target 15–20% of the frame ahead of its travel
  ([camera_controller.gd:367](../shaders-godot/godot-project/scripts/camera_controller.gd:367),
  `follow_deadzone_step`). *ST · S/M*
- [ ] **179. A camera that sells speed.** On a dart or startle of the followed
  fish, the deadzone widens briefly and the camera catches up with an ease.
  The camera's own slow-in/out tells the viewer how fast that was. *ST SI · S/M*
- [ ] **180. Light the actor, a little.** During a hero event, raise
  `fauna_rim` on the actor for its duration. Restrained: a hint, not a
  spotlight. *ST · S/M*
- [ ] **181. Contact shadows.** Small soft blobs under bottom-dwellers, shrimp
  and snails, so contact with the bed reads. *ST SD · M/M*
- [ ] **182. Stagger synchronous starts.** If several fish start the same action
  within 100 ms (feeding, startle without a propagating wave), add per-fish
  delays drawn from reaction latency. Synchronous starts look like a
  broadcast. *ST TI · S/M*
- [ ] **183. Intent is visible before arrival.** A fish heading for a target
  curves toward it 0.5 s early, so the viewer predicts the move before it
  happens. *ST AR · S/M*
- [ ] **184. A boldest-first feeding response.** When food lands, the boldest
  fish turns first and the rest follow by latency (#163). The cascade is the
  show. *ST TI · S/M*
- [ ] **185. Avoid tangents at rest.** Rest spots keep clearance from glass
  edges, plant silhouettes and other fish, so a resting fish doesn't sit
  exactly on an edge and merge with it. *ST SD · S/S*
- [ ] **186. Organic shoal shapes.** Shoals form an oval with a denser core and
  a ragged edge, never a lattice. The formation slot from `instance_id`
  ([fish.gd:8346](../shaders-godot/godot-project/scripts/fish.gd:8346))
  drifts slowly so it can't settle into a grid. *ST SD · S/M*
- [ ] **187. Keep something still.** An activity budget per tank per minute
  keeps at least one resting animal (a corydoras on the bed, a hovering
  angelfish) on screen as contrast. A tank where everything is busy reads as
  noise. *ST TI · S/M*
- [ ] **188. Display at the reflection.** At night, with the room dark and the
  tank lit, bettas and cichlids occasionally flare at their reflection in the
  front glass. Real, legible, and it stages itself against the camera. *ST AP · M/M*
- [ ] **189. Sound marks the beat.** Gulps, surface pops, jaw snaps and pistol
  snaps emit tiny cues from the motion event bus (#61). *ST · S/M*
- [ ] **190. Fry dart trails, only when it matters.** The dart afterimage
  ([fish.gd:6806](../shaders-godot/godot-project/scripts/fish.gd:6806)) fires
  on every fry burst. Limit it to escapes and play chases, so it means
  something. *ST EX · S/S*
- [ ] **191. Shot-aware detail.** Macro framing turns on hero features (eyes,
  opercula, jaw) for creatures in frame and lowers exaggeration; wide shots do
  the opposite. *ST EX · S/M*
- [ ] **192. Stage the empty water.** Schooling turns, feeding frenzies and
  displays happen in open water when the behaviour allows it, so they read
  against the background. Escapes still go to cover. *ST · S/M*

## G. Pose to pose: a key-pose library (193–220)

Physics is straight-ahead animation: fluid, but formless. Behaviours need
shapes. Each pose below is a target in the `PoseLibrary` (#45) that the
procedural motion settles into and travels between. Every pose keeps a
"moving hold" layer (#214).

- [ ] **193. Cruise.** Fins at half carriage, caudal at mid spread, head level.
  The neutral every other pose returns to. *PP · S/M*
- [ ] **194. Hover.** Pectorals sculling, dorsal raised, body pitched by species
  (nose-down for heavy-headed fish, level for tetras). *PP SD · S/M*
- [ ] **195. Alert.** Dorsal and anal fins erect, pectorals half forward, body
  rigid, caudal slightly cupped, eyes forward, fast breath. *PP AN · S/L*
- [ ] **196. Clamped.** All fins folded tight against the body, body darker,
  slight downward tilt. Clamped fins are the aquarist's classic stress sign.
  Make it readable at 22 px. *PP EX · S/L*
- [ ] **197. Lateral display.** All median fins fully erect, caudal fully
  spread, opercula flared on bettas and cichlids, body slightly arched,
  broadside, quivering. *PP ST · M/L*
- [ ] **198. Frontal threat.** Head-on, opercula flared, pectorals spread. The
  betta flare. *PP ST · S/M*
- [ ] **199. Submission.** Fins folded, body tilted (head-up for cichlids),
  colour paled. *PP · S/M*
- [ ] **200. Head-down picking.** Nose down 30–60°, pectorals forward, tail
  fanning to hold position. *PP · S/M*
- [ ] **201. Attached grazing.** Oto, pleco and hillstream loach: mouth on the
  surface, belly flat to it, pectorals splayed as props, tail slightly
  arched. *PP SD · M/M*
- [ ] **202. Resting on the bed.** Body on the pelvic fins, pectorals splayed as
  a tripod, tail straight or slightly curved. Needs pelvic fins (#379). *PP SD · M/M*
- [ ] **203. Sleep.** Fins relaxed and slightly drooped, minimal tail, slow
  drift, nose angle by species, colours paled. *PP · S/M*
- [ ] **204. Wedged.** Asleep in a thicket: tilted, in contact with leaves. *PP SD · S/S*
- [ ] **205. Surface gulp.** Nose up 30–45°, mouth at the meniscus, pectorals
  spread. *PP · S/M*
- [ ] **206. Sifting.** Nose buried, barbels splayed, tail up; the shipped sift
  pitch of 0.55 rad becomes a full pose. *PP · S/S*
- [ ] **207. Spawning clasps.** The betta nuptial embrace (the male curls
  around the female), the corydoras T-position, the guppy gonopodial swing.
  Each is a signature pose a real keeper recognises. *PP AP · M/L*
- [ ] **208. Mouthbrooding.** Throat distended, with a slow chewing motion that
  tumbles the eggs. *PP SA · S/M*
- [ ] **209. Fanning.** Hovering over eggs, pectorals beating fast, tail
  counter-sculling to hold station. *PP SA · S/M*
- [ ] **210. Listing.** Tilted 20–40°, fins clamped, nose down or floating
  belly-up, depending on the illness. *PP EX · S/M*
- [ ] **211. Gasping.** At the surface, rapid mouth, opercula flared. *PP SA · S/M*
- [ ] **212. Dead.** Belly-up or on the side, fins splayed, body slightly
  curved, eyes fixed. *PP SD · S/M*
- [ ] **213. A transition graph.** Allowed transitions with blend times as data:
  sleep → alert 0.15 s, alert → cruise 0.8 s, display → cruise 0.6 s, clamped
  → cruise 2–4 s. *PP SI · M/M*
- [ ] **214. Moving holds.** No pose is ever frozen: every hold carries breath,
  fin flicker and a little drift. *PP SA · S/L*
- [ ] **215. Continuous affect blending.** Map the mind's valence and arousal to
  continuous weights over relaxed, alert and clamped, rather than switching
  between them. *PP AP · M/L*
- [ ] **216. Actions end in a pose.** A dart ends in a glide pose (fins folded,
  tail straight), then eases to cruise; a strike ends in a "chew" pose; a
  display ends in a relaxed swim-off. Pose-to-pose structure on top of
  straight-ahead physics. *PP FT · M/L*
- [ ] **217. Per-species pose overrides.** The betta display flares much
  further; the angelfish rests with ventral filaments forward; the gourami
  holds its feelers out. *PP AP · S/M*
- [ ] **218. A pose editor in the motion lab.** Per-pivot sliders that save to
  `PoseLibrary`. *PP · M/M*
- [ ] **219. A pose contact sheet.** A dev capture rendering every species ×
  every pose into one PNG for review. *PP · S/M*
- [ ] **220. A pose smoke.** Every species has every required pose, and every
  pose is reachable from cruise in the transition graph. *PP · S/S*

## H. Follow-through and overlapping action (221–252)

Every fin and the tail are assigned directly from `sin()` each frame, with no
state ([fish.gd:7869](../shaders-godot/godot-project/scripts/fish.gd:7869),
7969, 7977), and veil streamers ride the same rigid pivots
([fish.gd:3453](../shaders-godot/godot-project/scripts/fish.gd:3453)).
Nothing lags, nothing settles.

- [x] **221. Spring the caudal fin.** The caudal fin follows the peduncle angle
  through a spring (f ≈ 4–6 Hz, ζ ≈ 0.4). It trails on the stroke, whips at
  reversal and cups. *FT · S/L*
  **Phase 2 (2026-10-30):** The caudal follows its wave target through a spring
  (6 Hz, ζ 0.55: about 7% gain at 3 Hz, so fast beats aren't amplified).
- [ ] **222. Two rows of caudal.** Split the caudal into a leading and a
  trailing voxel row, with the trailing row lagging (a two-link chain), so
  the fin visibly flexes. *FT SD · M/M*
- [ ] **223. Veils as chains.** Betta and fancy-guppy veil streamers get their
  own three-link `MotionChain`s with the veil preset. They billow, trail
  after turns and settle after stops. *FT AP · M/L*
- [ ] **224. Ripple long median fins.** The betta and gourami undulate their
  dorsal and anal fins along the base. Give the long fins several ray pivots
  with phase offsets, so a wave runs along them. *FT SA · M/M*
- [x] **225. Dorsal lag on roll.** The dorsal fin leans against the roll at the
  start of a turn, then catches up. *FT · S/S*
  **Phase 2 (2026-10-30):** Dorsal roll lag through a fin-preset spring,
  clamped ±0.3.
- [x] **226. Pectoral drag.** At the start of a burst the pectorals are swept
  back by drag, then fold; at a stop they flare, then relax. *FT SI · S/M*
  **Phase 2 (2026-10-30):** Acceleration sweeps the pectorals back (damped, up
  to 0.35).
- [ ] **227. Barbels on chains.** Corydoras, pleco and mudsifter barbels
  ([fish.gd:2992](../shaders-godot/godot-project/scripts/fish.gd:2992))
  trail while swimming, drape on the substrate while sifting and flick
  forward on a stop. *FT SA · S/M*
- [ ] **228. Living gourami feelers.** The ventral feelers
  ([fish.gd:3320](../shaders-godot/godot-project/scripts/fish.gd:3320)) are
  static. Make them chains that trail at speed and, separately (#321),
  actively reach toward objects and other fish. *FT SA AP · M/M*
- [ ] **229. Angelfish filaments.** The long ventral filaments and the dorsal
  and anal extensions trail and swing on turns, with the slowest settle of any
  part in the tank. *FT AP · S/M*
- [x] **230. The tail keeps swinging.** When thrust stops, tail amplitude decays
  over one or two beats through a spring, instead of dropping to the effort
  floor at once. *FT SI · S/L*
  **Phase 2 (2026-10-30):** The caudal spring rings the tail down after thrust
  stops.
- [ ] **231. Body yaw overshoot.** After a sharp turn the body overshoots the
  new heading a little and settles (underdamped body-yaw spring, ζ ≈ 0.6). *FT AR · S/M*
- [x] **232. Bank overshoot.** At turn exit the fish rolls slightly past level,
  then settles (bank spring ζ ≈ 0.55). Today the bank uses first-order
  smoothing ([fish.gd:7669](../shaders-godot/godot-project/scripts/fish.gd:7669)). *FT SI · S/M*
  **Phase 2 (2026-10-30):** The bank is an underdamped spring (bank preset, ζ
  0.55).
- [x] **233. Pitch overshoot.** After a rise or dive the nose passes level by
  3–5° and settles. *FT · S/S*
  **Phase 2 (2026-10-30):** Pitch follows a spring (1.2 Hz, ζ 0.6).
- [ ] **234. Order of moving parts.** Starting: eyes → head → pectorals → body →
  tail. Stopping: tail → body, and the fins settle last. Implement as
  per-channel delays in the composer. *FT TI · M/L*
- [ ] **235. Fin rays out of step.** The four dorsal rays
  ([fish.gd:3244](../shaders-godot/godot-project/scripts/fish.gd:3244)) each
  lag the one ahead by a few degrees of phase, so the fin ripples instead of
  moving as a plate. *FT SD · S/M*
- [ ] **236. Bring the static parts to life.** `Dorsal2` and the adipose fin
  ([fish.gd:3267](../shaders-godot/godot-project/scripts/fish.gd:3267), 3297)
  get small springs off their parent segment. *FT · S/S*
- [ ] **237. Heavy bodies lag more.** Larger, deeper-bodied fish (angelfish,
  severum, gar) carry more phase lag down the body and settle more slowly. *FT TI · S/M*
- [ ] **238. Belly slosh.** A heavily gravid or mouthbrooding belly lags body
  accelerations slightly. Soft tissue, very subtle. *FT SQ · S/S*
- [ ] **239. Puffer tail as a rudder.** Puffers swim with dorsal and anal fins
  and keep the tail folded, swinging loosely, until a burst needs it (#405). *FT AP · M/M*
- [ ] **240. Fins re-open in order after a dart.** After a dart, the fish glides
  with fins folded. The pectorals re-open only when speed falls below about
  40%, then the dorsal, then the caudal. *FT PP · S/M*
- [ ] **241. Plants after-sway.** A brushed plant keeps swaying for two or three
  visible oscillations. Tune the spring at
  [plant.gd:306](../shaders-godot/godot-project/scripts/plant.gd:306) for
  that, rather than a single damped bend. *FT · S/M*
- [ ] **242. Shrimp antennae as chains.** Replace the pure-sine antennae
  ([shrimp.gd:1741](../shaders-godot/godot-project/scripts/shrimp.gd:1741))
  with a chain driven by head motion and drag. They stream back when
  swimming, reach forward when exploring and overshoot after stops. *FT SA · M/L*
- [ ] **243. Heavy-headed stops.** Corydoras and plecos dip the head forward on a
  stop and recover. *FT SD · S/S*
- [ ] **244. Veils in current.** Long fins stream downstream in the flow field.
  A betta in the filter current should show it. *FT · S/M*
- [ ] **245. Independent caudal lobes.** Forked tails (`tail_shape`) give the
  upper and lower lobes a small phase difference, as real tails bend
  asymmetrically. *FT SD · S/S*
- [ ] **246. Staged fin re-erection after a fright.** Pectorals first, then
  dorsal, then caudal, over 1–3 s. *FT PP · S/M*
- [ ] **247. Opercula after a cough.** Two or three small beats after the flush,
  not one pulse. *FT SA · S/S*
- [ ] **248. Reversal swing.** When a hovering fish back-paddles, the tail swings
  past neutral and settles. *FT · S/S*
- [ ] **249. Landing settle.** Bottom-dwellers touching down settle the tail and
  pectorals through two small oscillations. *FT SD · S/S*
- [ ] **250. Big tails pull the body.** Fancy male guppies swim awkwardly
  because the tail is heavy. Scale `tail_recoil_yaw`
  ([hydrodynamics.gd:269](../shaders-godot/godot-project/scripts/hydrodynamics.gd:269))
  by tail mass from `tail_shape`, so big-tailed males wobble. *FT AP · S/M*
- [ ] **251. Feelers and barbels in current.** They deflect downstream with the
  flow sample. *FT · S/S*
- [ ] **252. Follow-through by LOD.** Chains run at hero and near LOD only. Far
  LOD uses an analytic phase delay per voxel in the shader. *FT · M/M*

## I. Slow in and slow out (253–274)

- [ ] **253. Interpolate steering between brain ticks.** The brain sets
  `desired` at 10 Hz and only agitation is interpolated
  ([fish.gd:8114](../shaders-godot/godot-project/scripts/fish.gd:8114)), so
  target velocity changes in steps. Run it through a critically damped spring,
  as shrimp already interpolate their target
  ([shrimp.gd:1449](../shaders-godot/godot-project/scripts/shrimp.gd:1449)). *SI · S/L*
- [ ] **254. Drag-shaped deceleration.** Coasting should decay like drag (fast
  at first, then a long tail). Confirm it in the speed graph and tune `drag_k`
  per profile until it does. *SI · S/M*
- [ ] **255. Explosive in.** Darts reach peak speed in two to four beats
  (80–150 ms) from impulse thrust, not from a fourfold linear acceleration
  ([fish.gd:7336](../shaders-godot/godot-project/scripts/fish.gd:7336)). *SI TI · M/L*
- [ ] **256. Ease the turn exit.** "Aligned fish shed unused angular rate" can
  stop the yaw rate on one frame. Limit angular deceleration as well as
  acceleration. *SI AR · S/M*
- [ ] **257. Hover drift.** A hovering fish drifts forward and back by about
  0.02 u, easing in and out: a moving hold, not a lock. *SI SA · S/M*
- [ ] **258. Ease out of fear.** After a flight, fin carriage re-opens and breath
  slows over 3–10 s. The fear arc
  ([fish_alive.gd:153](../shaders-godot/godot-project/scripts/fish_alive.gd:153))
  switches parameters at phase boundaries; ease them instead. *SI · S/M*
- [ ] **259. Ease depth changes.** Vertical moves start and end with eased pitch.
  The buoyancy spring arrives without a bounce for most species and with a
  slight one for bettas. *SI AR · S/M*
- [ ] **260. A spring on pectoral amplitude.** `pec_amp` is rebuilt every frame
  from about eight terms. Put the result through a spring so it can't jump. *SI · S/M*
- [ ] **261. Ease tail-beat frequency.** Damp `wag_freq` with τ ≈ 0.15 s;
  frequency jumps read as hiccups even when the phase is continuous. *SI TI · S/M*
- [ ] **262. Ease mood tempo.** The mood multiplier (0.55–1.7,
  [fish_mind.gd:133](../shaders-godot/godot-project/scripts/fish_mind.gd:133))
  should change over at least 0.5 s, so a mood shift doesn't snap the tempo. *SI · S/S*
- [ ] **263. A dance freeze is a moving hold.** `dance_freeze` stops the tail
  phase dead ([fish.gd:7853](../shaders-godot/godot-project/scripts/fish.gd:7853)).
  Ease the amplitude toward zero with one last small flick, and keep breath
  and fins alive. *SI FT · S/M*
- [ ] **264. Shrimp turn with a spring.** Shrimp heading rotates at a constant
  rate ([shrimp.gd:1467](../shaders-godot/godot-project/scripts/shrimp.gd:1467)).
  Use an angular spring with a rate cap. *SI · S/M*
- [ ] **265. Shrimp start and stop over strides.** Replace the linear
  `move_toward` ramp
  ([shrimp.gd:1487](../shaders-godot/godot-project/scripts/shrimp.gd:1487))
  with an ease over about two strides. *SI · S/M*
- [ ] **266. Snails turn like snails.** Snail facing turns at 5.5 rad/s
  ([snail.gd:266](../shaders-godot/godot-project/scripts/snail.gd:266)), a
  180° turn in 0.57 s, while crawling at 0.11 u/s. Use a spring capped near
  0.6 rad/s so a reversal takes 4–6 s. *SI TI · S/L*
- [ ] **267. Trumpet snails ease their drift.** Velocity changes instantly every
  4–9 s ([trumpet_snail.gd:104](../shaders-godot/godot-project/scripts/trumpet_snail.gd:104)). *SI · S/S*
- [ ] **268. Ease into current carry.** When a fish goes from swimming to being
  carried (`carried`,
  [hydrodynamics.gd:229](../shaders-godot/godot-project/scripts/hydrodynamics.gd:229)),
  blend over 0.5 s so the drift doesn't start abruptly. *SI · S/S*
- [ ] **269. Saccade velocity profile.** Head and eye saccades
  ([fish.gd:7910](../shaders-godot/godot-project/scripts/fish.gd:7910)) move
  fast, settle briefly and then hold. They are not a lerp toward a target. *SI SA · S/M*
- [ ] **270. Park, don't stop.** Arriving at a rest spot ends with a slow final
  glide and one or two small reverse-scull adjustments. *SI PP · S/M*
- [ ] **271. Bottom fish land with a glide.** Corydoras and plecos descend
  through a slowing glide onto the bed, rather than snapping to bed height. *SI SD · S/M*
- [ ] **272. Ease the music blend.** `dance_blend` in and out over at least a
  bar, so a song starting or stopping doesn't jerk the whole tank. *SI · S/S*
- [ ] **273. No pop on entering the frustum.** Off-frustum fish skip body
  animation ([fish.gd:7641](../shaders-godot/godot-project/scripts/fish.gd:7641)),
  so a fish entering view starts from a stale pose. Seed the pose from the
  analytic state and blend over 0.1 s. *SI · S/M*
- [ ] **274. Ease the wall approach in pose too.** The pace already eases near
  glass; the brake pose should start before the steering push does. *SI AN · S/S*

## J. Arcs (275–296)

Arcs come only from turn-rate caps today. There is no path planning, the
wander heading is re-rolled every 4–14 s
([fish.gd:6434](../shaders-godot/godot-project/scripts/fish.gd:6434)), and
a hard block reflects the heading.

- [ ] **275. One turn-radius law.** r_min = k · L · (1 + U/U_ref) per species,
  where L is body length and U is speed. Faster and longer fish turn wider.
  It replaces the stacked damps in #21 and becomes the single tuning knob for
  arcs. *AR TI · M/L*
- [ ] **276. A curvature-limited path follower.** Steering targets come from
  10 Hz tiers, so paths are polylines with rounded corners. Follow them with a
  Dubins-style follower bounded by #275, so headings trace arcs and corners
  are anticipated. *AR AN · M/L*
- [ ] **277. Wander as a meander.** Replace the re-rolled `heading_offset` with
  an Ornstein–Uhlenbeck walk on path curvature. Wander paths become smooth
  meanders with natural variation in tightness. *AR · S/L*
- [ ] **278. Porpoising depth changes.** Depth changes follow an S-curve in the
  vertical plane, with pitch tied to vertical velocity. *AR SI · S/M*
- [ ] **279. The corydoras air dash.** Bottom → surface → bottom as one
  continuous loop: a fast vertical dash, a gulp, and a curved dive back. It
  is one of the most recognisable motions in the hobby. *AR AP · M/L*
- [ ] **280. No spinning on the spot.** Body-caudal swimmers can't rotate in
  place; a low-speed turn needs a little forward or backward travel. Hovering
  labriform fish (angelfish, puffer, gourami) *can* rotate with their
  pectorals. Gate the in-place yaw floor
  ([fish_life_bouts.gd:151](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:151))
  by locomotion type. *AR SD · S/M*
- [ ] **281. A curved approach, a straight strike.** Feeding approaches curve in
  from below or the side; the strike itself is straight. The contrast is what
  reads. *AR ST · S/M*
- [ ] **282. Sharp escape, then a curve.** The C-start is the one sanctioned
  sharp angle. The flight path then straightens and the recovery curves back. *AR · S/M*
- [ ] **283. Tail tip draws a figure-eight.** Add a small caudal pitch heave at
  twice the tail frequency, so the tip draws a flattened figure-eight in the
  fish's frame. This is also what makes the beat visible broadside (#172). *AR SD · S/M*
- [ ] **284. Pectoral figure-eight.** Drive pectoral `rotation.z` and
  `rotation.y` a quarter cycle apart, so the fin tip draws an ellipse. That
  is how labriform fish actually row. Today the pectorals rotate about one
  axis ([fish.gd:7977](../shaders-godot/godot-project/scripts/fish.gd:7977)). *AR SA · S/M*
- [ ] **285. Corners as arcs.** Cruisers patrolling the perimeter
  ([fish.gd:5688](../shaders-godot/godot-project/scripts/fish.gd:5688)) start
  corner turns early, with a radius set by speed, instead of being pushed off
  the glass. *AR AN · S/M*
- [ ] **286. Glass approaches turn parallel.** A fish approaching the front
  glass (begging, inspecting the keeper) turns parallel to it in an arc before
  it arrives. *AR · S/S*
- [ ] **287. Smooth the dart courtship snap.** The `dart` dance variant uses
  `sign(sin)·1.2` ([fish.gd:4871](../shaders-godot/godot-project/scripts/fish.gd:4871)),
  which jumps laterally. Keep the snap but round each corner over two frames. *AR SI · S/S*
- [ ] **288. Schools share a turning centre.** In a school turn the outside fish
  travel a longer arc (they already speed up,
  [fish.gd:7469](../shaders-godot/godot-project/scripts/fish.gd:7469)). Make
  sure curvature is consistent across the school around one centre, rather
  than each fish turning on its own spot. *AR ST · M/M*
- [ ] **289. Sinking things rock.** Dead fish, shed exuviae and empty shells
  sink along a gentle rocking arc, like a falling leaf, not a straight line. *AR SD · S/M*
- [ ] **290. Shrimp swim in arcs.** A shrimp crossing between perches lifts off
  on its pleopods, glides, and descends in a ballistic-looking curve. *AR · S/M*
- [ ] **291. The tail-flip trajectory curves.** A backward flip pitches the body
  up, so the escape path arcs up, then glides down. *AR · S/M*
- [ ] **292. Snails fall in arcs.** A dislodged snail tumbles as it falls, lands,
  and rights itself (#575). *AR · S/M*
- [ ] **293. Bottom hoppers hop.** Gobies and hillstream loaches move in short
  parabolic hops; they are negatively buoyant and don't hover. *AR SD · M/M*
- [ ] **294. Microfauna twitches curve.** Larval twitch paths bend slightly
  instead of jumping in straight segments. *AR · S/S*
- [ ] **295. Shuffle hops arc.** Corydoras and mudsifter shuffle hops
  ([fish.gd:6280](../shaders-godot/godot-project/scripts/fish.gd:6280)) are
  low arcs with a dust puff on each landing. *AR SA · S/M*
- [ ] **296. Curvature continuity as acceptance.** The curvature metric (#83)
  is part of every arc item's done-definition. *AR · S/S*

## K. Secondary action: the animal is alive between actions (297–330)

Eyes and mouth are plain voxels on the head pivot. There is no eye, jaw or
operculum pivot, `_gill_pivot` is never assigned, and the "blink" squashes the
eye of an animal with no eyelids
([fish.gd:2944](../shaders-godot/godot-project/scripts/fish.gd:2944), 1085,
7964).

- [ ] **297. Eye pivots.** Put each eye on its own pivot. Everything else in
  this section that involves gaze depends on it. *SA AN · M/L*
- [ ] **298. Independent eyes.** Each eye saccades on its own schedule, as most
  teleost eyes do. Puffers and gobies make it obvious. *SA AP · S/M*
- [ ] **299. Converge to feed.** Both eyes rotate forward for binocular
  fixation before a bite (#149), and diverge at rest. *SA AN · S/M*
- [ ] **300. Saccades replace the blink.** Two to four eye saccades per 10 s at
  rest, fewer while swimming. Delete the blink (#15). *SA SD · S/M*
- [ ] **301. Eyes stabilise against the tail beat.** During swimming the eyes
  counter-rotate against the head's recoil yaw, so gaze holds still while the
  head wags. It is subtle and very alive at hero LOD. *SA SD · S/M*
- [ ] **302. Eyes on the keeper.** When the cursor is near the front glass, the
  nearest few fish track it with their eyes, and sometimes the head. *SA AP · S/L*
- [ ] **303. Opercula.** A real operculum pivot (#9) flaps at the breath rate
  (#54): about 1–2 Hz at rest, faster with exertion or low O₂, flared in
  display. *SA SD · M/L*
- [ ] **304. The buccal pump.** The mouth opens and closes in anti-phase with
  the opercula: the visible breathing of a resting fish seen head-on. Hero
  LOD only. *SA · S/M*
- [ ] **305. A jaw pivot.** A real lower-jaw rotation for gape, gulp, yawn,
  cough and chew, replacing whole-head scaling. *SA SQ · M/L*
- [ ] **306. A real yawn.** The jaw opens wide for about 0.5 s, the opercula flare
  and the fins spread, then everything closes. Fish do yawn, often on waking.
  This upgrades the idle yawn-gape
  ([fish.gd:6405](../shaders-godot/godot-project/scripts/fish.gd:6405)). *SA AP · S/M*
- [ ] **307. A real cough.** The jaw snaps and the opercula pulse in reverse to
  flush the gills. This replaces the head-scale pulse
  ([fish.gd:6976](../shaders-godot/godot-project/scripts/fish.gd:6976)). *SA · S/M*
- [ ] **308. Ventilating pectorals.** At rest, the pectoral beat rate follows the
  breath rate, because resting pectoral movement helps ventilate, rather than
  running at a fixed floor
  ([fish.gd:7988](../shaders-godot/godot-project/scripts/fish.gd:7988)). *SA TI · S/S*
- [ ] **309. Dorsal flicks.** Occasional quick dorsal raise-and-lower as
  signals between fish, roughly once every 20 s at rest. *SA · S/S*
- [ ] **310. Flashing with a cause.** The substrate flash
  ([fish.gd:8010](../shaders-godot/godot-project/scripts/fish.gd:8010)) is an
  idle fidget. Real flashing (scratching a flank on substrate or rock) is an
  irritation sign. Tie its rate to ammonia, nitrite and parasite load so it
  means something. *SA ST · S/L*
- [ ] **311. Chafing against plants.** The same irritation, rubbing along a leaf.
  The leaf bends. *SA · S/S*
- [ ] **312. Colour moves with pose.** Alert darkens over 0.5 s, sleep pales,
  display intensifies, synchronised with the pose blend, not on a separate
  clock. *SA PP · S/M*
- [ ] **313. Breath-linked bob.** Fold the standalone breath bob
  ([fish.gd:7211](../shaders-godot/godot-project/scripts/fish.gd:7211)) into the
  breath oscillator, so bob, opercula and mouth share one phase. *SA · S/S*
- [ ] **314. Surface dwellers dimple the surface.** Killifish fin flicks under
  the meniscus make small ripples. *SA · S/S*
- [ ] **315. Bubbles as motion events.** A labyrinth fish exhales spent air on
  a gulp, a corydoras releases a bubble after its air dash, and a physostome
  fish occasionally burps after a deep dive. Each comes from the event bus. *SA ST · S/M*
- [ ] **316. Wire `breath_hover_offset`.** It exists in
  `fish_spark_behavior.gd` and is never called. Use it as the hover-breath
  layer. *SA · S/S*
- [ ] **317. The corydoras wink.** Corydoras roll their eyes downward, which
  looks exactly like a wink. One eye, rarely, at rest. *SA AP · S/M*
- [ ] **318. Barbel tapping.** While sifting, barbels tap the substrate in a fast
  alternating rhythm. *SA · S/M*
- [ ] **319. The suckermouth on the glass.** Seen from the front, a grazing
  pleco or oto shows its mouth disc rasping. It is one of the most loved views
  in the hobby and depends on the camera seeing the underside. Render the
  disc with a 2–3 Hz rasp when the fish is on the front glass. *SA AP · M/L*
- [ ] **320. Tail fanning while attached.** Otos and plecos fan the tail gently
  to stay on the surface. *SA · S/S*
- [ ] **321. Feelers that probe.** Gouramis reach their feelers toward objects,
  food and other fish, and touch them. *SA AP · M/M*
- [ ] **322. Bubble-nest building.** A male betta or gourami gulps air and spits
  bubbles into a nest under a floater, then tends it. A long, legible,
  realistic behaviour with clear motion. *SA AP · L/L*
- [ ] **323. Shimmying with a cause.** Livebearers "shimmy" (rock side to side
  without travelling) under poor water or chill. The idle shimmy
  ([fish.gd:8010](../shaders-godot/godot-project/scripts/fish.gd:8010)) should
  come from those conditions. *SA ST · S/M*
- [ ] **324. Flinch at a close pass.** When another fish passes very close, the
  receiver flicks its dorsal and twitches its tail. Make the 0.08 s
  lateral-line flinch
  ([fish_alive.gd:211](../shaders-godot/godot-project/scripts/fish_alive.gd:211))
  visible. *SA · S/S*
- [ ] **325. The gonopodium swings.** Guppy and endler males swing the
  gonopodium forward in display and thrust. Repurpose the anal pivot on
  males. *SA AP · S/M*
- [ ] **326. Spacing corrections.** Fish in a school make constant small
  pectoral corrections in proportion to their spacing error. The school
  shimmers with life without anyone leaving formation. *SA · S/M*
- [ ] **327. Surface snaps.** Surface feeders strike at floating food with a
  quick upward head tilt and a jaw snap. *SA · S/M*
- [ ] **328. Single tail flicks to reorient.** Hovering labriform fish change
  heading with one or two tail flicks, not a continuous wag. *SA TI · S/M*
- [ ] **329. Spit and retake.** A fish occasionally spits out a large particle
  and takes it again. A real, characterful detail. *SA AP · S/M*
- [ ] **330. Chewing.** Severums and other cichlids show jaw motion after a big
  bite. *SA · S/S*

## L. Timing: weight, size, temperature and mood (331–358)

- [ ] **331. Declare real locomotion per species.** Add `locomotion_type` to
  every `SPECIES_LIBRARY` entry
  ([tank_config.gd:1218](../shaders-godot/godot-project/scripts/tank_config.gd:1218)):
  - subcarangiform: glassdart, danio, tetras, guppies, corydoras
  - anguilliform: mudsifter
  - median-fin "betta" mode: betta
  - labriform hover: angelfish, severum, gourami
  - a new tetraodontiform mode (dorsal and anal fin sculling): pufferfish
  - adherent glide: hillstream loach, oto
  - saltatory perching: goby
  - burst-and-rest: pleco
  *TI AP · M/L*
- [ ] **332. Tail-beat frequency from Strouhal.** f = St · U / A, with A ≈ 0.2 L
  and St ≈ 0.3. This replaces the hand-set base rates
  ([hydrodynamics.gd:257](../shaders-godot/godot-project/scripts/hydrodynamics.gd:257))
  with physics that scales across sizes by itself. *TI · M/L*
- [ ] **333. Anti-alias the tail beat.** Real small fish beat at 10–30 Hz; at
  60 fps (30 on mobile) that aliases into wagon-wheel stutter. Cap the
  *visible* frequency near fps/6, lower amplitude above it, and let the shader
  ripple suggest the rest. *TI ST · S/L*
- [ ] **334. Temperature tempo.** If the tank exposes a temperature (`plant.gd`
  and `egg.gd` read one), scale tempo by a Q10 of about 2: a cool tank is
  visibly languid and a warm one brisk. *TI · S/M*
- [ ] **335. Oxygen tempo.** Low O₂ slows swimming, speeds the opercula and
  adds surface time, together. *TI SA · S/M*
- [ ] **336. Crepuscular species.** Corydoras, plecos, shrimp and snails peak
  at dusk and at night. The day-activity lerp
  ([fish.gd:7025](../shaders-godot/godot-project/scripts/fish.gd:7025)) needs a
  per-species curve, not one for all. *TI AP · S/M*
- [ ] **337. Bout statistics per species.** Today every fish shares cruise
  2.5–8 s, hover 1.2–3.8 s and dart 0.4–0.8 s
  ([fish_life_bouts.gd:78](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:78)).
  Give each species its own distributions. *TI AP · M/L*
- [ ] **338. Danio burst-and-glide.** Danios move in discrete bouts every
  0.5–1.5 s with a glide between, which is their defining motion. *TI AP · S/L*
- [ ] **339. Size slows reactions.** Action-envelope durations scale with
  body length^(1/3), so a big angelfish reacts visibly more slowly than an
  ember tetra. *TI · S/M*
- [ ] **340. Holds by species.** Pauses between actions range from 0.2 s
  (guppy) to 2 s (angelfish) and come from the species and the individual. *TI AP · S/M*
- [ ] **341. Log-normal, not uniform.** `randf_range` gives flat distributions.
  Real bout lengths are right-skewed: mostly short, occasionally long. Draw
  durations from log-normals. *TI · S/M*
- [ ] **342. An exposure sheet for the C-start.** Stage 1 in 3–4 frames, stage
  2 in 4–6, a glide of 300–600 ms, then recovery. *TI EX · S/M*
- [ ] **343. An exposure sheet for the strike.** Slow approach; fixation
  150–300 ms; gape 40 ms before contact; strike 60–100 ms; close 80 ms;
  swallow and chew 300 ms. *TI · S/M*
- [ ] **344. An exposure sheet for the gulp.** Rise 0.6–1.2 s, gulp 0.15 s,
  dive 0.4 s. *TI · S/S*
- [ ] **345. Pectoral rate by species.** Labriform pectorals beat at about
  2–4 Hz, with a fixed ratio to the tail in body-caudal swimmers. *TI · S/M*
- [ ] **346. Fry timing.** High frequency, short bouts, frequent rests on
  surfaces. *TI · S/M*
- [ ] **347. Senescent timing.** Slower bouts, longer rests, later reactions,
  lower amplitudes, all together. *TI · S/M*
- [ ] **348. A weight table for invertebrates.** Cherry shrimp react in about
  50 ms; crabs and lobsters in 150–300 ms; snail tentacles withdraw in about
  150 ms and the body in about 300 ms. *TI · S/M*
- [ ] **349. Desync the school, but not completely.** Per-fish phase offsets
  (#18) prevent lockstep, but neighbours drafting at the right spacing drift
  partly into phase, as real schooling fish sometimes do. *TI SD · M/M*
- [ ] **350. Respect `time_scale` everywhere.** Every creature clock follows
  the global time scale. Clams ignore it today (#36). *TI · S/M*
- [ ] **351. Fast-forward as time-lapse.** Above 4×, switch to a time-lapse
  register: relaxed fins, low tail amplitude, smoothed trajectories. Without
  it fast-forward makes fish vibrate. *TI EX · M/L*
- [ ] **352. Slow-motion fidelity.** At 0.25×, pose interpolation runs at full
  frame rate so slow motion stays smooth. *TI · S/M*
- [ ] **353. Individual tempo.** `_speed_personality` (#18) sets ±10% tempo per
  fish. *TI AP · S/S*
- [ ] **354. Anxious is quick, content is slow.** Breath rate, fin-flick
  frequency and hold length follow arousal. *TI AP · S/M*
- [ ] **355. Hungry patrols, full loafs.** Hunger raises patrol speed and dart
  rate; satiety slows both and lengthens holds. *TI · S/M*
- [ ] **356. Juveniles are busier.** More frequent bouts, shorter holds,
  settling with growth. *TI · S/S*
- [ ] **357. Sleep breathing.** Breath rate drops to about 60% asleep. *TI SA · S/S*
- [ ] **358. Display quiver by species.** The courtship quiver rises with
  intensity up to a species cap (guppy about 10–15 Hz, shown as amplitude
  above the visible cap). *TI EX · S/M*

## M. Exaggeration, with restraint (359–374)

- [ ] **359. A legibility gain.** k = clamp(target_px / actual_px, 1, 1.3) on
  key channels only (fin erection, C-start bend, strike stretch, gulp). Never
  above 1.3. *EX ST · S/L*
- [ ] **360. Full C-start curl.** Keep the real 90–120° body curl; exaggerate
  the duration (#342), not the angle. *EX AN · S/M*
- [ ] **361. Display flare.** +20% fin area and 1.5× hold time in displays. *EX ST · S/M*
- [ ] **362. Strike stretch.** As in #123, with a one-frame smear (#370). *EX SQ · S/S*
- [ ] **363. Readable clamping.** Clamped fins shrink 40% and the fish darkens
  so stress reads at 22 px. *EX PP · S/M*
- [ ] **364. Readable gulps.** Gape +30% at the surface, plus a visible ripple
  ring. *EX ST · S/S*
- [ ] **365. Exaggerate contrast, not amplitude.** Put a 100–300 ms hold before
  a big action. The stillness makes the action land. *EX TI · S/L*
- [ ] **366. One exaggerated event per region.** Shares the event budget (#175). *EX ST · S/S*
- [ ] **367. A do-not-exaggerate list.** Cruise tail amplitude, school spacing,
  swim speed and snail speed are realism anchors and stay biological. *EX · S/M*
- [ ] **368. Distance-based exaggeration.** 0% in macro, about 15% at the
  default camera, about 30% in wide shots (#60). *EX ST · S/M*
- [ ] **369. Music lifts the cap.** When `dance_blend` is high, dance moves may
  exaggerate up to +40%, the tank's "magic" register, and fall back as the
  music ends. *EX AP · S/M*
- [ ] **370. Smear frames.** One elongated afterimage frame on strikes and
  C-starts, reusing the fry `DartTrailPool` with one ghost per adult. *EX · S/M*
- [ ] **371. Big-tailed recoil.** As in #250, a little stronger than real so it
  reads. *EX FT · S/S*
- [ ] **372. Readable hypoxia.** Opercula ×1.5 and mouth gaping, so a keeper
  reads the problem before the fish die. *EX SA · S/L*
- [ ] **373. Readable sickness.** Listing angles a little steeper than real. *EX PP · S/M*
- [ ] **374. An exaggeration ledger.** Every exaggerated channel in one table:
  real value, game value, reason. *EX · S/S*

## N. Solid drawing: volume, weight, balance, no twins (375–396)

- [ ] **375. Cap the fin shear.** The shader fin flutter shears fins along Z
  ([voxel_fauna_mm.gdshader:157](../shaders-godot/godot-project/shaders/voxel_fauna_mm.gdshader:157))
  without bound. Cap it so fins bend, not smear. *SD · S/S*
- [ ] **376. No cracks at joints.** Rotating pivots open gaps and overlaps
  between voxel blocks. Add joint filler voxels or overlap the segments, and
  check bends in `inspect`. *SD · M/M*
  **Phase 2 (2026-10-30):** *Partly.* The spine pass closes the
  BodyMid–TailPivot crack; joints inside a segment still use rigid voxel
  blocks.
- [x] **377. Rest pitch from balance.** Each species' centre of mass and centre
  of buoyancy set its rest pitch: corydoras nose-down, some tetras slightly
  nose-up. *SD · S/M*
  **Phase 2 (2026-10-30):** Rest pitch comes from
  `MotionPoseLibrary.rest_pose(species).head_pitch` and fades out as the fish
  swims (corydoras idle nose-down).
- [ ] **378. Bottom fish sink.** Corydoras, plecos, gobies and hillstream loaches
  have little or no swim-bladder lift. When they stop swimming they land; they
  don't hover. *SD TI · S/L*
- [ ] **379. Pelvic fins.** Build pelvic fin pivots. They are needed for resting
  tripods, for the corydoras clasp and for the silhouette. *SD · M/M*
- [ ] **380. Contact at rest.** Resting bottom fish touch the substrate with
  pelvic and pectoral fins through the contact solver (#55), rather than
  floating a voxel above it. *SD · M/M*
- [ ] **381. Belly to the surface.** Adherent grazers align belly-down to the
  surface normal of glass, wood or rock. *SD · S/M*
- [x] **382. No twin pectorals.** Beyond the quarter-cycle offset, give each
  pectoral its own noise and its own spring, so the two sides never mirror. *SD · S/M*
  **Phase 2 (2026-10-30):** Each pectoral's amplitude varies ±12% on its own
  smooth noise.
- [ ] **383. No twin neighbours.** No two neighbours share a phase and a pose;
  enforced by the twin metric (#89). *SD · S/M*
- [x] **384. Anatomical head limits.** Fish have no neck. Clamp head yaw to about
  0.15 rad relative to the front segment; any more lead has to come from the
  body bend. *SD · S/M*
  **Phase 2 (2026-10-30):** Head yaw is clamped to ±0.3 rad.
- [ ] **385. Dorsal-up stability.** Roll always recovers toward dorsal-up for a
  healthy fish. Only illness and death break it. *SD · S/S*
- [ ] **386. Sideslip in turns.** Bodies slide slightly outward in sharp turns. *SD AR · S/S*
- [ ] **387. Crab angle in current.** In a cross-current, the heading turns into
  the flow while the track stays on course. *SD · S/M*
- [ ] **388. A rheotaxis pose.** Station-holding fish face the current with the
  nose slightly down, the pectorals spread and the tail matched to the flow. *SD PP · S/M*
- [ ] **389. Pivots at the right joints.** Audit pivot placement: pectorals at
  the shoulder girdle, the tail pivot at the peduncle rather than mid-tail
  (`TailPivot` sits at z = +1.5 v). *SD · S/M*
- [ ] **390. Fins never vanish edge-on.** Thin voxel fins disappear when they
  rotate edge-on to the camera. Keep a minimum visible thickness or tilt. *SD ST · S/M*
- [ ] **391. Mass in personal space.** Larger fish push smaller ones aside; the
  clearance push is symmetric today
  ([fish_locomotion.gd:63](../shaders-godot/godot-project/scripts/fish_locomotion.gd:63)). *SD · S/M*
- [ ] **392. Balance is active.** A hovering fish shows tiny roll errors that
  pectoral flicks correct. *SD SA · S/M*
- [ ] **393. Align to slopes.** A bottom fish resting on a slope aligns pitch
  and roll to the bed normal. *SD · S/M*
- [ ] **394. Check the top view.** In pond and overhead mode the lateral wave
  reads fully. Verify the travelling wave from above and tune its amplitude
  separately. *SD ST · S/M*
- [ ] **395. No skating.** Any translation without matching locomotor effort,
  other than a glide or current carry, reads as skating. Measure speed
  against effort and flag mismatches. *SD · S/M*
- [ ] **396. Don't clip.** Reduce tail sweep near glass, plants and hardscape
  rather than letting fins pass through them. *SD · S/M*

## O. Appeal: species motion signatures (397–426)

Each signature is a composite of items above. It is what a keeper would
recognise with the colours turned off.

- [ ] **397. Glassdart.** Smooth and quick, tight school, synchronised flank
  flashes, rarely still. *AP · M/M*
- [ ] **398. Mudsifter.** Eel-like and head-first: the body follows the head's
  path (#68), it burrows partway, reverses in a concertina (#139) and emerges. *AP · M/M*
- [ ] **399. Betta.** Stately cruise with heavy, dragging fins (#223, #224);
  stop-and-hover with fins billowing; flares (#198, #188); rests on a leaf (a
  "betta hammock"); builds a bubble nest (#322). *AP · L/L*
- [ ] **400. Killifish.** Hugs the surface, still then sudden; males display
  with quick lateral snaps. *AP · M/M*
- [ ] **401. Guppy.** Bustling and never quite still. Males pursue with the
  sigmoid display and gonopodium swing (#325); females graze and evade. *AP · M/L*
- [ ] **402. Endler.** A faster, dartier guppy with more frequent displays. *AP · S/M*
- [ ] **403. Rummy nose.** The tightest school in the tank, streaming nose to
  tail, with synchronised direction changes. *AP · S/M*
- [ ] **404. Ember tetra.** Mid-water hover-and-go in a loose shoal, with
  frequent short pauses. *AP · S/M*
- [ ] **405. Pufferfish.** Hovers on buzzing dorsal and anal fins with the tail
  tucked (#239); rolls each eye independently (#298); turns in place; inspects
  the keeper; inflates only under severe threat (#127). *AP · L/L*
- [ ] **406. Danio.** Burst-and-glide near the surface (#338), playful chasing,
  never still. *AP · S/M*
- [ ] **407. Corydoras.** Comic and social: hop-and-sift in groups (#295),
  winks (#317), air dashes (#279), tripod rests (#202), busy barbels. *AP · M/L*
- [ ] **408. Angelfish.** Slow, deliberate and vertical; rows with the
  pectorals; long trailing fins (#229); pairs move together. *AP · M/M*
- [ ] **409. Harlequin rasbora.** Shoals by the plants with tilt-and-dart
  moves; spawning pairs turn upside-down under a leaf. *AP · M/M*
- [ ] **410. Otocinclus.** Grazes the glass (#201, #319), makes short dashes to a
  new spot, grazes in groups, flicks its tail while attached. *AP · M/M*
- [ ] **411. Bristlenose pleco.** Mostly still and rasping; bursts to a new
  spot; active at night; rests under wood with the tail fanning. *AP · M/M*
- [ ] **412. Dwarf gourami.** Slow cruiser, feelers probing (#321), surface
  trips for air (#133), nest-building males. *AP · M/M*
- [ ] **413. Reef fish.** Hovers above the coral in a loose group on fast
  pectoral rowing; dives into the coral when threatened. *AP · M/M*
- [ ] **414. Hillstream loach.** A miniature ray: glides over surfaces with the
  pectorals sealed, skitters short distances, grazes in the current. *AP · M/M*
- [ ] **415. Freshwater gar.** Hangs motionless near the surface like a stick,
  sculls its fins, strikes sideways (#146, #168), gulps air. *AP · M/M*
- [ ] **416. Goby.** Perches on a pelvic sucker with the head propped up, hops
  in short arcs (#293), swivels its eyes. *AP · M/M*
- [ ] **417. Severum.** A chunkier angelfish: hovers, picks and digs, turns more
  slowly. *AP · S/M*
- [ ] **418. Individual tells.** Each fish gets one persistent idiosyncrasy from
  `MotionPersonality`: a tail flick before every turn, a habitual resting spot,
  a head tilt. Individuals become recognisable. *AP · M/L*
- [ ] **419. Fish that know the keeper.** Familiar fish follow the cursor along
  the front glass. Real fish learn their keepers. *AP · M/L*
- [ ] **420. Curiosity.** A new plant or decoration gets inspected: slow
  approach, pauses, fixations, retreat, re-approach. *AP AN · M/M*
- [ ] **421. Play in the bubbles.** Some fish repeatedly ride the airstone
  column or the filter outflow. *AP · M/M*
- [ ] **422. Clarity.** A jitter detector flags high-frequency heading noise.
  Clean motion is appealing motion. *AP · S/M*
- [ ] **423. Faces.** A fish facing the camera shows breathing mouth and moving
  eyes (#297, #304). Head-on is the most charming view and today it is the
  most static. *AP SA · M/L*
- [ ] **424. Earn the eye contact.** Fish look at the camera rarely; a fish that
  stares constantly is uncanny. *AP · S/S*
- [ ] **425. Personality as paths.** Bold fish take long, open-water paths; shy
  fish take short paths between cover, with more pauses. Map boldness to
  motion parameters explicitly. *AP TI · S/M*
- [ ] **426. Pairs move as pairs.** Bonded pairs (angelfish, gouramis) travel
  together, one leading by half a body length and mirroring with a 0.2–0.5 s
  delay. *AP ST · M/M*

---

# Part III — Fish through their lives

Part II is about how a fish moves. Part III is about how that motion changes
with age, health, time of day, food and company.

## P. Life stages (427–441)

- [ ] **427. Wigglers before swimmers.** Newly hatched fry hang on glass, leaves
  and substrate, wriggling in short bursts, for a while before they swim free.
  Today fry swim fully from the start. *TI SA · M/M*
- [ ] **428. Fry proportions in motion.** A bigger head and eyes, and a faster
  beat with a smaller absolute amplitude. *SD TI · S/M*
- [ ] **429. Schooling develops with age.** Young fry aren't cohesive; real
  schooling emerges as they grow. Ramp `schooling_strength` with growth stage. *TI AP · S/L*
- [ ] **430. Fry move cover to cover.** By default fry dart between plants and
  stay close to cover. *ST AP · S/M*
- [ ] **431. Continuous growth.** Motion constants that depend on growth (body
  length, flexibility, tempo) change smoothly. No parameter jumps at a
  maturity threshold. *TI · S/M*
- [ ] **432. Maturity changes the repertoire.** Males gain displays and finnage
  as they mature, so their follow-through grows with their fins. *AP FT · M/M*
- [ ] **433. Senescence as a whole.** Old fish are slower and stiffer, rest
  longer, react later, and hold a slight age posture (the shipped 0.22 rad
  senescent pitch, given company). *TI SD · S/M*
- [ ] **434. A natural decline.** Old-age death comes after days of slowing:
  more time on the bed or in the plants, slower breathing, then death. *TI PP · M/M*
- [ ] **435. Livebearer birth.** A guppy fry is born curled, unfurls, and darts
  up and away to cover within a second. *AN AR · S/M*
- [ ] **436. Egg-scatterer spawning runs.** Tetras, danios and rasboras spawn in
  quivering side-by-side runs through the plants. *AP · M/M*
- [ ] **437. Corydoras egg placement.** After the T-position (#207), the female
  carries eggs in her pelvic fins and presses them onto the glass, one
  careful placement at a time. *AP SA · M/M*
- [ ] **438. Shrimplets are jittery.** Juvenile shrimp are small copies with
  quicker, more nervous timing. *TI · S/S*
- [ ] **439. Hatchling snails.** Newly hatched snails crawl out over minutes,
  very slowly, usually onto the glass. *TI · S/M*
- [ ] **440. Growth carries through arcs.** Turn radius, tempo and reaction
  time all scale from body length, so a growing fish changes how it moves as
  well as its size. *AR TI · S/S*
- [ ] **441. Mouthbrooded fry.** Fry released from a mouthbrooder dart back into
  the mouth on a threat. *AP · M/M*

## Q. Health, sickness and death (442–461)

- [ ] **442. Hypoxia reads as hypoxia.** Piping at the surface, nose up, mouth
  working, opercula fast, slower swimming everywhere else. *ST PP · S/L*
- [ ] **443. Ammonia and nitrite stress.** Erratic darting, flashing (#310),
  clamped fins (#196), gasping. Each appears in proportion to the reading. *ST · M/L*
- [ ] **444. Temperature stress.** Lethargic in the cold; restless with surface
  gasping in the heat. *TI · S/M*
- [ ] **445. Swim-bladder trouble.** Floating head-down or belly-up and
  struggling to stay level, with effortful swimming. *PP SD · M/M*
- [ ] **446. Damaged fins move differently.** Torn or nicked fins
  ([fish_alive.gd:248](../shaders-godot/godot-project/scripts/fish_alive.gd:248))
  flutter more, lag more and give less thrust. *FT SD · S/M*
- [ ] **447. Exhaustion after a chase.** The chased fish slows, rests,
  breathes fast, and recovers over a minute. *TI · S/M*
- [ ] **448. A limp after a nip.** A nipped fish favours one side briefly:
  asymmetric pectoral use, a slight list. *SD · S/S*
- [ ] **449. Dying is a sequence.** Loss of equilibrium, slow spirals, resting on
  the bed, weak intermittent bursts, slow breathing, over 10–60 game seconds.
  Today death is a 3.5 s flank roll with a uniform shrink
  ([fish.gd:7048](../shaders-godot/godot-project/scripts/fish.gd:7048)). *PP TI · M/L*
- [ ] **450. A real death pose.** Belly-up or on the side, fins splayed, body
  slightly curved, eyes fixed, per-instance bend zero (#40). *PP SD · S/L*
- [ ] **451. Sink, then settle.** Most fresh corpses sink first: a rocking arc
  (#289) to the bed and a final roll. Floating later, after bloating, is
  optional and probably better left out. *AR SD · S/M*
- [ ] **452. Corpses drift.** A corpse rolls and drifts in the flow until it
  settles. *SD · S/S*
- [ ] **453. Tank-mates react.** Wire `tick_mourning_stance` (never called, in
  `fish_spark_behavior.gd`) alongside the grief pull
  ([fish_social.gd:68](../shaders-godot/godot-project/scripts/fish_social.gd:68)):
  others inspect the body, then avoid the spot. *AP ST · S/M*
- [ ] **454. Shrimp death.** Curled, fallen onto its side, fading paler. *PP · S/M*
- [ ] **455. Snail death by old age.** The body retracts, the shell rolls, and
  an empty shell stays, as starvation already does. Old age just frees the
  node today ([snail.gd:436](../shaders-godot/godot-project/scripts/snail.gd:436)). *PP · S/M*
- [ ] **456. Clam death.** The valves gape open and stay open, the classic sign
  of a dead mussel. Today it is an instant free. *PP · S/M*
- [ ] **457. Worm death.** Limp, then fading into the substrate. *PP · S/S*
- [ ] **458. Recovery is gradual.** Improving health restores fin carriage and
  tempo over minutes, not on a threshold. *SI · S/M*
- [ ] **459. Water changes perk fish up.** A burst of exploration and activity
  after a water change, which keepers know well. *AP TI · S/M*
- [ ] **460. Wire `affordance_motor_scale`.** It exists in
  `fish_spark_behavior.gd` and is never called; use it to tie effort to the
  fish's condition. *TI · S/S*
- [ ] **461. A motion vocabulary of health.** A doc and in-game hint table
  mapping each water problem to its visible tell, so the keeper learns to read
  the tank like an aquarist. This is the gameplay payoff of Part III. *ST AP · S/L*

## R. Night and sleep (462–473)

- [ ] **462. Lights-out panic.** An abrupt switch from light to dark makes
  fish bolt; a sunset ramp doesn't. Reward the gradual dimmer. *AN ST · S/M*
- [ ] **463. Settle over minutes.** Fish slow down, choose a spot and drift
  into the sleep pose over several minutes, staggered by individual. *SI TI · S/M*
- [ ] **464. Sleep by species.** Tetras hover low and pale; corydoras lie on
  the bed; bettas rest on leaves; angelfish hang vertical and still; plecos
  wake up. *PP AP · M/M*
- [ ] **465. Sleep micro-motion.** Slow pectorals, slow opercula, a slight drift
  with the current and an occasional correction. *SA · S/M*
- [ ] **466. Waking.** First light: fins spread, a yawn (#306), slow first
  swims, tempo rising over a few minutes. *SI SA · S/M*
- [ ] **467. Night shift.** Plecos, corydoras, shrimp, snails and worms are
  visibly busier after dark. *TI AP · S/M*
- [ ] **468. Sleepers respond late and badly.** Higher startle threshold,
  longer latency and a clumsier response (a bump, a disoriented swim). *TI · S/M*
- [ ] **469. Quieter sleep twitches.** The sleep twitch (a 0.18 s burst every
  8–25 s) becomes a small fin twitch, much less often. *SA · S/S*
- [ ] **470. Moonlight tempo.** Under the blue night light everything moves
  more slowly. *TI · S/S*
- [ ] **471. Sleepers drift.** Mid-water sleepers drift slowly with the
  current and correct with small beats; they are not locked in place. *SA SD · S/M*
- [ ] **472. Staggered emergence.** Trumpet snails and worms come out over
  10–20 minutes at dusk, not at once. *TI ST · S/M*
- [ ] **473. A dawn peak.** A crepuscular burst of foraging at first light. *TI · S/S*

## S. Feeding (474–491)

- [ ] **474. Food falls like food.** Flakes flutter down along falling-leaf arcs;
  pellets sink straight. Fish track the falling food with their eyes. *AR · M/M*
- [ ] **475. Intercept, don't chase.** Fish aim where the food will be, not where
  it is. *AN AR · S/M*
- [ ] **476. Suction feeding, start to finish.** Approach, gape 40 ms early,
  the particle is pulled in, the mouth closes, the opercula pulse as water is
  expelled, chewing. *SA AN · M/L*
- [ ] **477. Food is visibly sucked in.** The particle zips into the mouth over
  two or three frames. Today it is consumed at d < 0.4
  ([fish.gd:5075](../shaders-godot/godot-project/scripts/fish.gd:5075)) and
  disappears. *SA ST · S/L*
- [ ] **478. Surface strikes.** An upward strike with a head tilt for floating
  food, and a ring on the surface. *SA · S/M*
- [ ] **479. Mid-water snaps.** A dart and a jaw snap. *SA · S/S*
- [ ] **480. Bottom feeding.** Head-down picking, tail up; corydoras sifting
  with puffs of substrate. *PP · S/M*
- [ ] **481. Jostling.** Small sideways shoves and dominance nips at the food;
  subordinates dart in and out. *ST AP · M/M*
- [ ] **482. From frenzy to fullness.** The frenzy burst exists; add the
  slowdown as fish fill. Late feeders are less energetic, and full fish
  ignore food or mouth it and spit. *TI · S/M*
- [ ] **483. Post-meal loaf.** A slow digestive hover with a fuller belly (#125). *TI PP · S/M*
- [ ] **484. A grazing rhythm.** Otos and plecos bite at 2–3 Hz with a small
  forward creep between bites. *TI SA · S/M*
- [ ] **485. Stalk and strike.** A large predator stalks fry: slow approach,
  fixation, S-start. The fry flee into the plants. *AN ST · M/M*
- [ ] **486. Scavengers converge.** Uneaten food on the bed is ignored by full
  fish and found by corydoras, shrimp and snails, which converge on it. *ST AP · S/M*
- [ ] **487. Pecks are jabs.** Each peck
  ([fish_life_bouts.gd:286](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:286))
  is a head-forward stretch and a mouth snap, not just a speed pulse. *SA SQ · S/M*
- [ ] **488. Chewing big bites.** Cichlids work the jaw after a large meal (#330). *SA · S/S*
- [ ] **489. Hunting live food.** With copepods or daphnia in the tank, fish
  hunt them one at a time: fix, stalk, strike. Fish and microfauna finally
  interact. *AN AP · M/L*
- [ ] **490. Picking food off leaves.** Food caught on leaves is picked off by a
  careful hover. *SA · S/S*
- [ ] **491. Feeding pose by mouth position.** Superior-mouthed fish feed
  upward, terminal mouths straight ahead, inferior mouths downward. The
  `mouth_orientation` field already exists; make the feeding pose follow it. *PP SD · S/M*

## T. Social contact (492–511)

- [ ] **492. Pursuit curves.** A chaser cuts corners along a pursuit curve and
  the chased fish zigzags; both bodies bend hard. *AR · M/M*
- [ ] **493. Nips.** A quick strike with a jaw snap and recoil. The victim
  flinches, squashes slightly and clamps its fins briefly. *SA SQ · S/M*
- [ ] **494. Lateral display and tail-beating.** Two males side by side, head to
  tail, fins flared, beating their tails at each other to push water. *ST PP · M/L*
- [ ] **495. Mouth-wrestling.** Cichlids (severum, angelfish) lock jaws and
  push. *ST · M/M*
- [ ] **496. Yielding.** The subordinate turns away, folds its fins and tilts. *PP · S/M*
- [ ] **497. Female evasion.** A female guppy turns away, dives, or nips back. *AP · S/M*
- [ ] **498. Spawning drives.** Egg-scatterer males drive females into the
  plants with quivering runs. *AP · M/M*
- [ ] **499. Territory patrols.** Territorial males (betta, gourami, severum,
  killifish) patrol a boundary and escort intruders out by swimming parallel
  to them, then return. *AP ST · M/M*
- [ ] **500. Angelfish site cleaning.** A pair picks at a leaf surface together,
  quivering, before spawning. *AP · M/M*
- [ ] **501. Parenting.** Fanning (#209), guarding, carrying wrigglers back to
  the site in the mouth. *AP SA · L/M*
- [ ] **502. A frightened school changes its body language.** It tightens,
  synchronises, clamps fins and speeds up. Polarisation shows in the bodies as
  well as in the headings. *ST · S/M*
- [ ] **503. Fountain effect and flash expansion.** A school splits around a
  predator and re-forms behind it; a sudden scare bursts it outward. *AR ST · M/L*
- [ ] **504. Propagate from the snapshot.** `MotionWave` reads neighbours' live
  `motion_agitation`
  ([motion_wave.gd:88](../shaders-godot/godot-project/scripts/motion_wave.gd:88)),
  not the snapshot taken at :56, so the wave can jump several hops in one tick
  depending on array order. The visible turning wave should travel at its
  declared speed. *TI ST · S/M*
- [ ] **505. Split schools in space.** Fission splits by array-index halves
  ([motion_school.gd:143](../shaders-godot/godot-project/scripts/motion_school.gd:143)).
  Split by a plane through the centroid instead, so the two halves are
  actually on two sides. *ST · S/M*
- [ ] **506. Shoal ↔ school.** Shoaling fish switch between a loose foraging
  shoal and a tight, polarised school when threatened or travelling, over
  2–5 s. *ST TI · M/M*
- [ ] **507. Dither fish.** Shy species become bolder and move more openly when
  confident dither fish are present. *AP · S/M*
- [ ] **508. Glass surfing.** Repeated up-and-down along the glass is a stress
  tell in new or crowded tanks. Show it when those conditions hold. *ST · S/M*
- [ ] **509. Near-misses have body language.** A close pass produces a flinch,
  a yaw away and a bank, not just a positional push from `local_clearance_push`. *SA SD · S/M*
- [ ] **510. Formation slots that breathe.** Formation slots drift slowly
  (#186), so fish swap places in the school over minutes, as real schools
  churn. *ST TI · S/M*
- [ ] **511. Fish meet invertebrates.** Fish investigate a shrimp and get an
  antenna flick and a backward hop. A fish bumping a snail on the glass makes
  it clamp. Fish nose at a clam and it closes. Cross-family contact is where a
  tank feels like one ecosystem. *AP ST · M/L*

---

# Part IV — Everything that isn't a fish

## U. Shrimp (512–541)

`shrimp.gd` builds a per-pivot voxel body that can take much more animation
than it gets. There are three leg pairs instead of five; each leg is one
segment with a sawtooth sweep; the antennae are pure sines; the pleopods never
beat; and the abdomen wags sideways like a fish because of the shader (#12).

- [ ] **512. Five pairs of walking legs.** Real decapods have five pereiopod
  pairs; shrimp have three
  ([shrimp.gd:661](../shaders-godot/godot-project/scripts/shrimp.gd:661)).
  Add the missing two, sharing phase with the back pairs if cost matters. *SD · M/L*
- [ ] **513. Two-segment legs.** A merus and a propodus with a knee, so a leg
  lifts by bending rather than by rotating a stick. *SD · M/L*
- [ ] **514. Planted feet.** Leg tips hold their ground contact through stance
  via the contact solver (#55); foot slip stays under 10% (#102). *SD · M/L*
- [ ] **515. A smooth leg cycle.** Replace the linear sawtooth sweep
  ([shrimp.gd:1644](../shaders-godot/godot-project/scripts/shrimp.gd:1644))
  with a stance at constant ground speed and an eased swing, so leg velocity is
  continuous at the turnarounds. *SI · S/L*
- [ ] **516. An alternating tetrapod gait.** Decapods walk with alternating
  tetrapod coordination. Put the phase offsets in data and check them against
  the real pattern. *TI SD · S/M*
- [ ] **517. A segmented abdomen that flexes in pitch.** Split `TailPivot` into
  three abdominal segments plus a telson and uropod fan, flexing about X. *SD SQ · M/L*
- [ ] **518. A real tail flip.** A 30–50 ms abdominal flexion pulls the shrimp
  backwards and up, then a slower re-extension of 150–250 ms. One to three
  flips in a row. The trajectory arcs (#291), and the head keeps facing the
  threat (#23). *AN SQ AR · M/L*
- [ ] **519. A tail fan that opens.** The uropods spread through a flip and
  during swimming and fold at rest. *SQ · S/M*
- [ ] **520. Swimming on pleopods.** A metachronal beat of the swimmerets, back
  to front, at a visible 5–8 Hz, with the body level. `_pleopod_phase` is
  computed and never used
  ([shrimp.gd:1731](../shaders-godot/godot-project/scripts/shrimp.gd:1731)). *SA TI · M/L*
- [ ] **521. Tuck the legs when swimming.** Legs fold back under the body while
  swimming. The comment at
  [shrimp.gd:1629](../shaders-godot/godot-project/scripts/shrimp.gd:1629)
  promises it; today the legs freeze at neutral. *PP SD · S/M*
- [ ] **522. Antennae as sensors.** On top of the chains (#242), antennae swing
  toward an odour source and tap objects in passing. *SA AN · S/M*
- [ ] **523. Antennule flicking.** The short antennules flick at 2–4 Hz,
  faster when food is in the water. Chemical sensing you can see. *SA · S/M*
- [ ] **524. Picking hands.** The first two chelipeds alternate between the
  substrate and the mouth at 3–5 Hz while nibbling. This is the cherry
  shrimp's signature, and today the feeding pose is only a body nod
  ([shrimp.gd:1753](../shaders-godot/godot-project/scripts/shrimp.gd:1753)). *SA AP · M/L*
- [ ] **525. Land on the legs.** The legs reach down before touchdown, the body
  settles with a small squash and the legs gather (#37). *SQ FT · S/M*
- [ ] **526. A feeding stance.** Nose down, tail slightly up, legs splayed. *PP · S/S*
- [ ] **527. Grooming.** Occasional bouts of cleaning the antennae and body with
  the legs and mouthparts. *SA AP · M/M*
- [ ] **528. A molt sequence.** Hide, arch, split the carapace, back out with a
  flip, leave the exuvia, then lie low and soft for hours. Today it is a 1.10×
  scale pop
  ([shrimp.gd:1767](../shaders-godot/godot-project/scripts/shrimp.gd:1767)). *PP TI · M/L*
- [ ] **529. Fanning the eggs.** Berried females fan their pleopods continuously
  and rock the egg mass, which rides the tail (#22). *SA FT · S/M*
- [ ] **530. Shrimplets scatter.** Released shrimplets are driven off by pleopod
  beats and disperse into the moss. Today they are placed at random offsets
  ([sim_driver.gd:5411](../shaders-godot/godot-project/scripts/sim_driver.gd:5411)). *AR · S/M*
- [ ] **531. Amano swarms.** Amano shrimp converge on food as a group, cling
  upside-down to plants and grab greedily. *AP · M/M*
- [ ] **532. The cleaner's rocking dance.** Cleaner shrimp rock side to side to
  advertise, and client fish hold still with mouth and gills open. Today
  CLEAN is a held position. *ST AP · M/L*
- [ ] **533. The pistol snap.** The pistol shrimp's large claw (`claw_asymmetry`)
  closes in one frame, with a cavitation bubble, a flash and a sound. *EX ST · M/M*
- [ ] **534. Walking up surfaces.** Climbing shrimp walk up stems and glass on
  their legs, aligned to the surface (#56). Today CLIMB swims to the graze site
  ([shrimp.gd:1325](../shaders-godot/godot-project/scripts/shrimp.gd:1325)). *SD AR · M/L*
- [ ] **535. Differential stepping.** In a turn, inside legs take shorter steps
  than outside legs. *SD · S/M*
- [ ] **536. Sideways and backward steps.** For a lateral target within about
  0.3 u, shrimp step sideways or back instead of turning. *SD AP · S/M*
- [ ] **537. The mating swarm.** After a female molts, the males swim frantically
  around the tank. Real, dramatic and readable. *AP ST · M/M*
- [ ] **538. A pile-up on food.** Shrimp converge on a pellet and pile on it,
  jostling. *AP · S/M*
- [ ] **539. Mouthpart flutter.** Maxillipeds flutter constantly below the head
  at hero LOD, which is a single voxel flicker. *SA · S/S*
- [ ] **540. Eyestalks that look.** Small rotations of the stalked eyes toward
  stimuli (#53). *SA · S/S*
- [ ] **541. A graded startle.** A small disturbance retracts the antennae and
  freezes the shrimp; a medium one makes it walk away; a large one makes it
  flip. Today it is flip or nothing. *AN TI · S/M*

## V. Crabs, lobsters and mantis shrimp (542–563)

- [ ] **542. A real sideways walk.** With pivots (#24), crabs walk sideways on
  four leg pairs in an alternating tetrapod gait. The leading legs pull and
  the trailing legs push. *SD TI · M/L*
- [ ] **543. Arched legs.** Two-segment legs with the knee up and the body slung
  low. *SD · M/M*
- [ ] **544. Claw-to-mouth feeding.** Crabs feed by alternating their claws to the
  mouth at 1–2 Hz. It is unmistakable. *SA AP · M/L*
- [ ] **545. The threat display.** Claws raised and spread, body up on the legs,
  then a sideways retreat. *PP ST · M/M*
- [ ] **546. Backing into cover.** Crabs back into crevices and shelter rear-first. *AP · S/M*
- [ ] **547. Eyestalks fold.** Crab eyes rise to look and fold into their
  sockets on a threat. *SA · S/M*
- [ ] **548. Lobsters walk forward carrying their claws.** The claws are held
  forward and slightly raised and sway with the steps. *SD · S/M*
- [ ] **549. Heavy tail flips.** Crayfish and lobsters flip backwards as shrimp
  do, but slower and bigger, several flips in a row. *TI SQ · S/M*
- [ ] **550. Antennae sweep in arcs.** The long lobster antennae sweep
  alternately while it explores. *SA AR · S/M*
- [ ] **551. A lobster tail fan.** The uropods spread on each flip. *SQ · S/S*
- [ ] **552. Rearing up.** A defensive lobster or crayfish rears, opens its
  claws and faces the threat. *PP ST · S/M*
- [ ] **553. Bulldozing.** Crayfish shovel substrate with their claws, with
  dust. *SA · M/M*
- [ ] **554. The mantis strike.** The raptorial arms fold and snap out in one
  frame with a smear, after an eye fixation. The stalked eyes rotate
  independently, the mantis shrimp's most famous motion. The arms are static
  today ([shrimp.gd:602](../shaders-godot/godot-project/scripts/shrimp.gd:602)). *AN EX AP · M/L*
- [ ] **555. Burrow peeking.** A mantis shrimp sits in its burrow mouth with only
  its eyes out and pulls back when approached. *AP ST · M/M*
- [ ] **556. Heavy timing.** Crabs and lobsters turn slowly, react in
  150–300 ms and lurch slightly forward on a stop. *TI · S/M*
- [ ] **557. No leg collisions.** Leg phases and pivot limits keep legs out of
  the body and each other. *SD · S/S*
- [ ] **558. Rear-first molting.** Crabs and lobsters back out of the old shell,
  then hide soft. *PP · M/M*
- [ ] **559. Climbing hardscape.** Crabs clamber over rock with the body pitched
  to the slope. *SD · M/M*
- [ ] **560. Bubbling mouthparts.** Crab maxillipeds flutter at rest. *SA · S/S*
- [ ] **561. Scuttle and freeze.** A startled crab runs sideways fast and stops
  dead with its claws up. *AN SI · S/M*
- [ ] **562. Claws don't walk.** Lobster claws are carried, not used as legs. *SD · S/S*
- [ ] **563. Crustacean death.** On the back, legs curled inward. *PP · S/S*

## W. Glass snails (564–593)

Snails are the slowest animals in the tank and the most-watched on the glass.
Several faults stack up: they may crawl sideways (#25), the shell squashes
with the foot (#28), surfaces change in a single frame (#26), and a 180° turn
takes about half a second (#266).

- [ ] **564. Fix the axis first.** #25. *SD · S/L*
- [ ] **565. Pedal waves on the glass.** Seen through the glass, a snail's foot
  shows dark bands travelling along it: the pedal waves. Scroll a band
  texture on the `GlassFootPad`
  ([world.gd:4757](../shaders-godot/godot-project/scripts/world.gd:4757)) at
  the foot-wave speed, forwards or backwards by species. This is the single
  most real thing a snail can do on screen. *SA AP · M/L*
- [ ] **566. The foot stretches, the shell doesn't.** Foot length and width
  pulse with the wave, conserving volume (#28). *SQ SD · S/M*
- [ ] **567. The shell rocks and swings.** The shell sits on a spring relative
  to the foot. It rocks 2–4° with each foot pulse and swings around, then
  settles, 0.3–0.6 s after the head turns. *FT SD · M/L*
- [ ] **568. Shell hitches.** Real snails pull the shell forward in small jerks
  relative to the foot, every 2–4 s. *FT SA · S/M*
- [ ] **569. Edges as a sequence.** Crossing from glass to floor, the head
  reaches across first, the foot follows over the edge, and the shell tips
  over last, over 1.5–3 s (#26, #56). *AR FT · M/L*
- [ ] **570. A head and tentacles.** Add a head with two cephalic tentacles for
  the shell types that have them (pond snails and ramshorns with eyes at the
  base, nerites, mystery snails with stalked eyes and long tentacles). Today
  there are only eye stalks
  ([world.gd:4770](../shaders-godot/godot-project/scripts/world.gd:4770)). *SD SA · M/L*
- [ ] **571. Tentacles feel the way.** They tap the surface ahead and sweep side
  to side. *SA AN · S/M*
- [ ] **572. The apple-snail snorkel.** Mystery and apple snails extend a siphon
  to the surface to breathe. Iconic. *SA AP · M/M*
- [ ] **573. Ramshorns carry the shell upright.** The shell rocks as they go,
  and they glide upside-down along the surface film with the foot flat to it. *SD · S/M*
- [ ] **574. Floating on air.** Pond snails and ramshorns sometimes float up
  after taking air and drift upside-down at the surface before letting go. *AP · S/M*
- [ ] **575. Righting is effort.** The foot reaches out, finds purchase, and
  pulls the shell over, sometimes taking several tries over 3–8 s. Today it
  is a 1.9 s slerp
  ([snail.gd:702](../shaders-godot/godot-project/scripts/snail.gd:702)). *SD TI · M/M*
- [ ] **576. Retraction in order.** Tentacles first (about 0.15 s), then the
  head and foot (about 0.4 s), then the shell drops or clamps, then the
  operculum closes. Overlapping action at snail speed. *FT SI · M/L*
- [ ] **577. Cautious re-emergence.** After 5–30 s: tentacles out slowly first,
  then the foot, then crawling. *AN SI · S/M*
- [ ] **578. Grazing leaves a track.** The rasping head pulses at 1–2 Hz and
  leaves a cleaner trail through the green dust on the glass. *SA ST · M/M*
- [ ] **579. Snail mating.** One snail rides on another's shell for a long while. *AP · M/M*
- [ ] **580. Egg laying takes time.** The snail stays put for a while and the
  clutch grows behind it, instead of appearing instantly. *TI PP · S/M*
- [ ] **581. Calibrate speeds.** 0.11 u/s is about 6.6 mm/s at 1 u ≈ 6 cm.
  Pond snails and ramshorns move nearer 1–2 mm/s and nerites 2–3 mm/s. Set
  speed per shell type from real numbers. *TI · S/L*
- [ ] **582. Surface sets speed.** Faster on glass, slower on sand and gravel,
  slower uphill (shipped), slowest upside-down on the film. *TI · S/M*
- [ ] **583. Trail following.** Snails follow each other's mucus trails, which is
  why they often travel in lines. *AP · M/M*
- [ ] **584. Snails on stems.** The foot wraps the stem, the shell hangs, and the
  whole snail sways with the plant. *FT SD · M/M*
- [ ] **585. Leaves bend under snails.** A snail on a leaf weighs it down
  through the plant brush response. *SD · S/M*
- [ ] **586. Snails crawl over each other.** Instead of avoiding each other. *AP · S/M*
- [ ] **587. Snails in the current.** In strong flow, snails on the glass clamp
  and stop, and snails on stems sway with the stem. Crawling resumes when the
  flow drops. *SD AN · S/M*
- [ ] **588. Apple snails are heavy.** Slower, with long sweeping tentacles and
  the siphon. *TI AP · S/M*
- [ ] **589. Nerites glide.** Low-profile, steady, with the operculum visible when
  they clamp. *AP · S/M*
- [ ] **590. Limpets barely move.** A glacial glide with the shell clamped low. *TI · S/S*
- [ ] **591. Assassin snails erupt.** Nassarius-type snails sit buried with only
  the siphon showing, and burst out of the sand when food arrives. *AN AP · M/L*
- [ ] **592. Fish knock snails off.** A fish bumping a snail on the glass can
  dislodge it into a fall (#292). *AR · S/M*
- [ ] **593. Shells clack.** Shells tap glass and stones crossing edges, with a
  tiny wobble and a sound. *SA · S/S*

## X. Trumpet snails, worms, tubifex and sea cucumbers (594–617)

- [ ] **594. Trumpet snails face their way.** They never rotate today. The
  pointed shell trails behind and up, at 30–45°. *SD · S/M*
- [ ] **595. Night climbers.** Malaysian trumpet snails emerge head-first at
  night and climb the glass in numbers. *AP · M/M*
- [ ] **596. Burrowing rocks the shell.** Going down, the shell rocks side to
  side apex-first and grains shift around it. *SA SD · M/M*
- [ ] **597. A pulsed crawl.** Trumpet snails share the glass-snail foot wave,
  not a constant drift. *SI · S/S*
- [ ] **598. Wriggle worms face their way.** The body yaws to the drift and the
  segments follow the head's path (#68). Today it strafes
  ([wriggle_worm.gd:108](../shaders-godot/godot-project/scripts/wriggle_worm.gd:108)). *SD AR · S/M*
- [ ] **599. Peristalsis.** Segments lengthen and shorten in a wave on top of the
  lateral undulation, as annelids actually move. Bring the surge (about
  10× drift) into proportion. *SQ TI · M/M*
- [ ] **600. Worms coil when touched.** Contract into a coil, then slowly extend. *SQ AN · S/M*
- [ ] **601. Detritus worms whip-swim.** Disturbed detritus worms lash through
  the water in figure-eights. *AR · S/M*
- [ ] **602. Bristle worms row.** A polychaete moves with its parapodia rowing in
  metachronal waves along the body, emerges head-first and backs out of sight
  fast. *SA FT · M/L*
- [ ] **603. Bristles in sequence.** The bristle-worm bristles are built
  ([bristle_worm.gd:49](../shaders-godot/godot-project/scripts/bristle_worm.gd:49))
  and never animated, and the wriggle-worm bristles all roll on one shared
  sine
  ([wriggle_worm.gd:147](../shaders-godot/godot-project/scripts/wriggle_worm.gd:147)).
  Make the pairs beat one after another along the body. *FT · S/M*
- [ ] **604. Nocturnal bristle worms.** They forage out of the burrow at night
  and withdraw quickly on light or vibration. *TI AN · S/M*
- [ ] **605. Tubifex hinge at the base.** Each worm rotates about its base, not
  its centre
  ([tubifex_patch.gd:80](../shaders-godot/godot-project/scripts/tubifex_patch.gd:80)),
  and waves its tail in slow circles with its own phase. *SD SA · S/M*
- [ ] **606. The patch withdraws together.** On a disturbance the whole patch
  disappears into the substrate in about 0.2 s, then the worms re-emerge one
  by one over 10–30 s. Today grazing hides one worm instantly
  ([tubifex_patch.gd:102](../shaders-godot/godot-project/scripts/tubifex_patch.gd:102)). *AN SI ST · S/L*
- [ ] **607. Tubifex wave harder in low O₂.** Real tubifex wave their tails more
  vigorously as oxygen falls, which turns the patch into a gauge. *SA ST · S/M*
- [ ] **608. Sea-cucumber peristalsis.** A wave travelling along the body instead
  of an in-phase stretch, and the body faces its travel. *SQ SD · M/M*
- [ ] **609. Tentacles fed one at a time.** Sea cucumbers push their feeding
  tentacles into the mouth one after another. *SA AP · M/M*
- [ ] **610. Contract when touched.** The cucumber shortens and fattens. *SQ AN · S/M*
- [ ] **611. Tube feet.** A subtle ventral ripple. *SA · S/S*
- [ ] **612. Hydra move.** Hydra somersault and inch along, contract into a ball
  when touched, and bring prey to the mouth with their tentacles. *AP SQ · M/M*
- [ ] **613. Hydra pulses.** Spontaneous contraction bursts every few minutes. *SA TI · S/S*
- [ ] **614. Buried correctly.** Worm bodies sit partly in the substrate with a
  clean boundary, not floating or clipping. *SD · S/M*
- [ ] **615. Dislodged worms drift.** Detached worms drift and tumble in the
  current. *AR · S/S*
- [ ] **616. Fish strike at worms.** Fish strike at exposed worms and the worms
  withdraw. Predator and prey both move. *AN ST · M/M*
- [ ] **617. Staggered emergence.** Worm populations emerge over time, not all
  at once (#472). *TI · S/S*

## Y. Clams, coral, anemones and hydra (618–637)

- [ ] **618. Hinge at the hinge.** The reef clam's shells rotate about their own
  centres ([coral.gd:811](../shaders-godot/godot-project/scripts/coral.gd:811));
  pivot them on the hinge line, as the freshwater clam already does. *SD · S/M*
- [ ] **619. Open slowly, shut fast.** The same lerp opens and closes the hinge
  ([clam.gd:229](../shaders-godot/godot-project/scripts/clam.gd:229)). Open
  over about 1 s with ease-in-out; close in about 0.15 s with an adductor snap. *SI TI · S/L*
- [ ] **620. A siphon that extends.** It extends gradually, pulses as it
  filters, and retracts first on a threat. Today it pops in above 25% open
  ([clam.gd:235](../shaders-godot/godot-project/scripts/clam.gd:235)). *SI SA AN · S/M*
- [ ] **621. Clams plough.** Freshwater clams dig with the foot (extend, anchor,
  pull) and slowly plough furrows through the sand. *SA AP · M/M*
- [ ] **622. Clams respond.** They shut on threats and on bad water; the header
  says they don't today. *AN ST · S/M*
- [ ] **623. A mantle edge.** The mantle flutters along the gape when open. *SA · S/S*
- [ ] **624. Giant-clam shadow reflex.** A reef clam's extended mantle undulates
  slowly and snaps shut, with a squirt, when a shadow passes over it. *AN ST · M/M*
- [ ] **625. Anemone tentacle chains.** Tentacles become chains that bend with
  the flow (after the tip fix, #33) and swing and settle after a fish brushes
  them. *FT SD · M/L*
- [ ] **626. Anemones ball up.** On touch the whole body contracts into a ball,
  then re-expands over minutes. *SQ AN · M/M*
- [ ] **627. Anemones feed.** Tentacles grab food and fold toward an opening
  mouth. *SA · M/M*
- [ ] **628. Anemones lean to light.** A slow lean toward the light over hours. *TI · S/S*
- [ ] **629. Polyps by the clock.** Many corals extend polyps at night and
  retract by day, rippling gradually. *TI · S/M*
- [ ] **630. Retraction spreads.** Polyp retraction ripples outward from the
  point of disturbance, so the viewer sees where the touch came from. *AN FT · M/M*
- [ ] **631. Polyps grab.** Tentacles curl in as a food particle passes (the
  open half of HYDRODYNAMIC #33). *SA · M/M*
- [ ] **632. Sway with the flow.** Soft corals sway base to tip with lag (the
  wave travel exists), with amplitude driven by local flow strength. *FT · S/M*
- [ ] **633. Pulsing corals.** If a xenia-like form exists or is added, it pulses
  at its real rhythm. *SA · S/S*
- [ ] **634. Pecked corals retract locally.** A fish pecking a colony gets a
  local retraction and a slow re-extension. *AN · S/M*
- [ ] **635. Every polyp on its own clock.** Independent phase and extension per
  polyp, never one uniform pulse. *SD · S/M*
- [ ] **636. No stutter at half rate.** Coral animates every second frame
  ([coral.gd:740](../shaders-godot/godot-project/scripts/coral.gd:740)); drive
  it from elapsed time and interpolate so it doesn't step. *SI · S/M*
- [ ] **637. Share the tentacle code.** Anemone, hydra and coral tentacles use the
  same `MotionChain` as barbels and feelers (#43). *FT · S/M*

## Z. Microfauna and eggs (638–655)

The swarm is three MultiMeshes with appendages baked into one mesh per morph
([microfauna_swarm.gd:298](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:298)),
so anything below the whole-body level needs a little shader work.

- [ ] **638. Daphnia hop and sink.** A quick stroke of the antennae (about
  0.1 s up), then a passive sink with the body tilted: a sawtooth, two to four
  hops a second. Today it is a square wave of rise and fall
  ([microfauna_swarm.gd:184](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:184)). *TI SI · S/L*
- [ ] **639. Daphnia stay upright.** Head up during the hops, antennae flapping
  as two voxels in the shader. *SD SA · S/M*
- [ ] **640. Copepods jump away from fish.** A copepod in strike range of a fish
  hops away. *AN · S/M*
- [ ] **641. Copepod hops come in bursts.** Two to four jumps, then a long glide. *TI · S/S*
- [ ] **642. Larvae undulate.** A per-instance micro-wave in the instance shader. *SA · S/S*
- [ ] **643. Microfauna face their way.** They currently wobble ±0.30 rad but
  never face their travel
  ([microfauna_swarm.gd:284](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:284)). *SD · S/M*
- [ ] **644. Phototaxis you can see.** Column density shifts visibly toward the
  light. *ST · S/S*
- [ ] **645. Fish suck them in.** Eaten microfauna are pulled into the mouth
  (#477). *SA · S/S*
- [ ] **646. Bobbing in the current.** Low-Reynolds drift with no coasting
  (shipped), plus turbulence buffeting. *SA · S/S*
- [ ] **647. Per-instance appendage flap.** A phase in `INSTANCE_CUSTOM` lets the
  shader flap appendages cheaply for the whole swarm. *SA · M/M*
- [ ] **648. Eggs tremble before hatching.** Fish eggs tremble as the embryo moves,
  faster as hatching nears (move it to `_process`, #35), then the fry wriggles
  out with a burst. *AN SA · S/M*
- [ ] **649. Snail clutches develop.** Visible dots inside the eggs; hatchlings
  crawl out one by one over minutes. Today the clutch is static and swaps
  instantly ([snail_egg.gd:191](../shaders-godot/godot-project/scripts/snail_egg.gd:191)). *TI · M/M*
- [ ] **650. Eggs move on the shrimp.** The egg mass shifts as the pleopods fan
  (#529). *FT · S/S*
- [ ] **651. Scattered eggs fall.** Scattered eggs drift down in arcs and stick
  where they land on plants and substrate. *AR · S/M*
- [ ] **652. Egg predation.** Fish search for and pick at eggs. *AP · S/M*
- [ ] **653. Fry from under leaves.** Harlequin fry emerge from the undersides
  of leaves. *AP · S/S*
- [ ] **654. Swarms form clouds.** Dense daphnia near the light drift together
  as a cloud. *ST · S/M*
- [ ] **655. Swarms avoid fish.** A slight clearing around fish, as daphnia
  avoid predators by migrating vertically. *AN ST · S/M*

---

# Part V — Water, music, camera and cost

## AA. Water and contact (656–675)

The flow field is real (`water_current.gd`, `tank_flow_field.gd`): fish
deposit wakes, get carried, draft and hold station. It is coarse, though, with
cells of 0.55 u or more and a 10 Hz step, so close contact between bodies and
the things they touch still needs work.

- [ ] **656. Plants react after the fish passes.** The brush response
  ([world.gd:11216](../shaders-godot/godot-project/scripts/world.gd:11216))
  fires as the fish passes. A wake reaches a leaf 0.1–0.3 s later; delay the
  bend by distance. *FT TI · S/M*
- [ ] **657. Pectoral wash.** Hovering fish scull small local flows that nudge
  nearby particles and fine leaves. *SA · S/M*
- [ ] **658. Take-off puffs.** The first beats of a bottom fish leaving the bed
  kick up a small dust plume (a motion event). *SA ST · S/M*
- [ ] **659. Tail-wash on the bed.** A fish swimming low enough stirs fine
  substrate behind its tail. *SA · S/S*
- [ ] **660. Surface contact.** Surface dwellers dimple the meniscus, gulps
  leave rings, and killifish and danios occasionally break the surface (a
  small leap and splash, bounded to stay in the tank). *SA ST · M/M*
- [ ] **661. Matching reflections.** Check that fauna reflections in the glass
  (`fauna_reflection.gdshaderinc`) show the same pose and phase as the fish,
  not a delayed or unbent one. *SD · S/M*
- [ ] **662. Bubbles meet bodies.** Rising bubbles deflect around fish; a fish
  hit by a large bubble flinches. *SA · S/S*
- [ ] **663. Holding against the filter.** In strong flow a fish beats harder,
  gets swept back and recovers. Weak swimmers avoid the outflow; strong ones
  play in it (#421). *TI SD · S/M*
- [ ] **664. Turbulence buffets.** In turbulent cells (`turbulence_at`,
  [tank_flow_field.gd:269](../shaders-godot/godot-project/scripts/tank_flow_field.gd:269)),
  bodies take small random roll and yaw kicks that the fins correct. It reads
  as moving water. *SA SD · S/M*
- [ ] **665. Pushing through plants.** A fish forcing through a dense stand
  slows, and the blades part around the body, instead of a clearance push
  holding it off. *SD · M/M*
- [ ] **666. Resting on leaves.** Bettas, gouramis and angelfish rest on broad
  leaves, and the leaf bends under them. *SD AP · M/M*
- [ ] **667. Nestling in.** Fish hiding in a thicket nestle in, and the blades
  sway around them. *SD · S/M*
- [ ] **668. Rubbing on hardscape.** Flashing along rock (#310) and plecos
  attaching to wood use the hardscape surfaces. *SD · S/M*
- [ ] **669. Weight on plants.** Shrimp and snails on leaves deflect them (#585). *SD · S/S*
- [ ] **670. Floaters part.** Floating plants are pushed aside by a fish rising
  to the surface, and a fish under a floating mat bumps it up. *SD · M/M*
- [ ] **671. Wakes move food.** A fish swimming past sinking food blows it off
  course. *SA · S/M*
- [ ] **672. Sifting leaves trails.** Corydoras sifting leaves disturbed patches
  that settle over time. *SA · M/M*
- [ ] **673. Stirred mulm.** Bottom fish lift detritus, which drifts and
  resettles. *SA · S/M*
- [ ] **674. A school turn whooshes.** A school turning together leaves a
  visible swirl in the particulate (FISH_ALIVE's unticked "whoosh"). *ST · M/M*
- [ ] **675. A near-wake for close contact.** Add a short-range analytic wake
  around each fish for plants and small creatures within a body length, since
  the grid is too coarse to register it. *FT · M/M*

## AB. Music and dance that stay animal (676–683)

The tank is meant to dance. Dance motion should be the animal's own repertoire
set to the beat, not a different animal.

- [ ] **676. Dance moves are actions.** Every dance move runs through
  `ActionEnvelope`: anticipation on the pre-beat, the hit on the beat,
  follow-through after (#169). *AN FT · M/L*
- [ ] **677. Freeze is a moving hold.** As in #263: during `dance_freeze`, breath,
  fins and eyes keep going. *PP SA · S/M*
- [ ] **678. Dance vocabulary by species.** Danios dance in bursts, angelfish in
  glides, corydoras in hops, bettas in flares. Assemble each species' dance
  from its own moves. *AP · M/L*
- [ ] **679. Poses on the downbeats.** Key a display pose on the drop and
  holds on bar lines, with procedural in-betweens: pose to pose, on the music. *PP TI · M/M*
- [ ] **680. Bank caps by body.** `dance_bank` allows ±0.95 rad
  ([fish.gd:7661](../shaders-godot/godot-project/scripts/fish.gd:7661)). A
  tall angelfish rolling that far reads as capsizing. Cap the bank per body
  plan. *SD · S/M*
- [ ] **681. Waves on phrases.** Music-driven school turns
  (`tick_music_sweep`) land on phrase boundaries, with a visible leader (#164). *TI ST · S/M*
- [ ] **682. A clean exit.** When the music ends, dancers return to their own
  motion with follow-through, not a snap. *SI FT · S/S*
- [ ] **683. Trail through fins, not geometry.** The music trail stretches the
  tail to 1.06 ([fish.gd:7881](../shaders-godot/godot-project/scripts/fish.gd:7881)).
  Show it as fin spread and chain follow-through instead. *FT SD · S/S*

## AC. Camera, render and legibility (684–692)

- [ ] **684. Test world-locked dither on moving fauna.** Dither crawl on a
  moving fish reads as noise. Evaluate `dither_world_lock`
  ([main.gd:1947](../shaders-godot/godot-project/scripts/main.gd:1947)) with
  motion-lab clips and decide the default. *ST · S/M*
- [ ] **685. No one-pixel shimmer on slow movers.** A snail whose foot pulse
  moves it back and forth across a pixel boundary flickers. Make slow movers'
  render positions monotonic along their travel. *ST SD · S/M*
- [ ] **686. Stair-steps stay even.** Sub-pixel-per-frame movers step pixel by
  pixel; keep the step rhythm even rather than jittery. *ST TI · S/S*
- [ ] **687. Exposure sheets at 30 fps.** Mobile and battery saver run at
  30 fps ([main.gd:12623](../shaders-godot/godot-project/scripts/main.gd:12623)).
  Every action keeps at least one wind-up frame and one hit frame at 30. *TI AN · S/M*
- [ ] **688. A documentary camera (optional).** An idle mode where the camera
  drifts gently toward significant motion events (a birth, a courtship, a
  molt) and holds. *ST · M/M*
- [ ] **689. Macro turns on the face.** In macro framing, hero features (eyes,
  opercula, jaw, maxillipeds, tentacles) switch on for every creature in
  frame (#191). *ST SA · S/M*
- [ ] **690. Tune for the top view.** From overhead the lateral wave reads at
  full amplitude while from the side it is foreshortened. Pond and overhead
  modes get their own amplitude scale (#394). *ST · S/S*
- [ ] **691. Fins catch the light.** Use `fin_translucency` so moving fins read
  against the background with light coming through them. *ST SD · S/M*
- [ ] **692. Tilt the orthographic camera.** In orthographic mode depth wags
  disappear. A default 8–12° downward pitch brings them back. *ST · S/S*

## AD. Performance: realism on a budget (693–700)

A rendered 197-fish tank ran at about 3 FPS in the crowded-fish pass
([CROWDED_FISH_PERFORMANCE_20261008.md](CROWDED_FISH_PERFORMANCE_20261008.md)),
and bone sync for 400 bones costs about 9.6 ms
([RENDER_SCHOOLING_PERFORMANCE_20261009.md](RENDER_SCHOOLING_PERFORMANCE_20261009.md)).
Everything in this backlog has to fit under that.

- [ ] **693. Batch the spine math.** Compute spine and chain angles per species
  in packed arrays in one pass, not per-node calls. Targets: about 15 µs per
  hero fish, 4 µs near, 1 µs far. *— · M/L*
- [ ] **694. Secondary motion in the shader.** Fin flutter, chain lag and
  appendage flap become per-voxel phase delays in `voxel_fauna_mm.gdshader`
  for batched species. CPU springs only for hero and near LOD. *— · M/L*
- [ ] **695. Gate on the crowded case.** Add a 150-fish rendered scenario to the
  motion perf gate. No motion item may regress it. *— · S/M*
- [ ] **696. Keep the pose layer cosmetic.** `smoke_schooling_force_equivalence`
  (13,476 golden assertions) breaks on any steering change by design. Body
  and pose work must not alter steering forces, which
  `smoke_motion_mind_parity` verifies. Path-shaping items (#275–#277) are the
  exception: re-baseline deliberately, in their own PR. *— · S/L*
- [ ] **697. Make the physics LOD real.** `use_full_physics` is a stub
  ([hydrodynamics.gd:290](../shaders-godot/godot-project/scripts/hydrodynamics.gd:290)).
  Far and offscreen fish get analytic steering without per-stroke thrust. *— · M/M*
- [ ] **698. Curvature, not bones, for batched fish.** Adding spine joints
  multiplies `FaunaSpeciesBatch` bone syncs. For batched fish, send one root
  transform plus wave and curvature parameters per fish, and bend in the
  shader. *— · L/L*
- [ ] **699. Batch the per-voxel creatures.** Snails, clams, worms, cucumbers and
  trumpet snails use one `MeshInstance3D` per voxel. Move them to per-pivot
  `VoxelBatch`es, as shrimp do, so per-part animation becomes affordable. *— · M/M*
- [ ] **700. Motion lines in the perf contract.** Add motion cost to
  `smoke_perf_contract.gd` and require a frame-time A/B for every Part II
  milestone. *— · S/M*

---

## If Cursor only does ten

1. **#1–#4, #10–#13: stop cancelling the motion that already exists.** The
   bank sign, the overwritten lean and brake flare, the vanished sleep roll,
   the ripple that wags corpses and crustacean tails, and the thrust that
   ignores the tail beat. Each is under an hour, and the tank gets visibly
   better with no new systems.
2. **#25, #12, #23: the three invertebrate howlers.** Snails crawling sideways,
   shrimp abdomens wagging like fish, and the shrimp escape that flips the
   wrong way.
3. **#41 + #44: springs and the pose composer.** The two primitives every
   principle needs: state for follow-through and easing, and one writer per
   channel.
4. **#94 + #81: the motion lab and onion skins.** Motion can't be tuned without
   watching it slowly, from the side, with spacing visible.
5. **#64 + #66: a spine with a real travelling wave.** The default fish today is
   a standing counter-wag on three sibling pivots. This is the biggest single
   step from "voxels swimming" to "fish".
6. **#143 + #145: the head leads, and a real C-start.** Anticipation is the
   principle the tank most lacks, and these are its two most legible moments.
7. **#221 + #223 + #230: tails and veils that follow through.** Spring the
   caudal, chain the veils, let the tail swing on after the thrust stops.
8. **#297 + #303 + #300: eyes and opercula.** A fish that breathes and looks
   around is alive at rest, and the fake blink goes.
9. **#565 + #567 + #576: snails that are snails.** Pedal waves on the glass, a
   shell that rocks on the foot, and retraction in order.
10. **#253 + #255 + #128: smooth in, explosive out, caudal spread.**
    Interpolated steering, impulse darts and a breathing tail fin, the cheapest
    big wins in slow in and slow out and squash and stretch.

## Guardrails

- **Realism first, then legibility.** Exaggeration is capped (#134, #359) and
  listed (#374). Cruise motion, school spacing and swim speeds stay biological.
- **Cosmetic layers don't steer.** Pose, chain, eye and fin work must leave
  steering forces bit-identical (#696). Changes to paths are separate and
  re-baselined on purpose.
- **Isolated runs only.** Use `scripts/dev_run.sh` for the motion lab,
  `inspect` and every probe. `dev/capture.tscn` writes to real save slots.
- **Measure before and after.** Every item ships with a metric that moved
  (Section C) and a before/after clip (#99).
- **Check line numbers.** Anchors are from `4fc358e` and `fish.gd` moves fast;
  grep the symbol before editing.
