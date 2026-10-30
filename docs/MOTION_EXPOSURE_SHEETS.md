# Motion exposure sheets

*Drafted 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #106
(an exposure sheet per behaviour) and #687 (exposure sheets at 30 fps). Code
anchors are from `5ad6dd3`; grep the symbol, since Phase 1 is editing
`fish.gd` in the working tree.*

An exposure sheet is the animator's timing chart: the key poses of an action
and how many frames each one gets. These sheets are the spec the motion smokes
test against (#107–#109, #170). Each sheet gives the target at 60 fps, the
target at 30 fps (mobile and battery saver, `_apply_fps_cap`,
[main.gd:12615](../shaders-godot/godot-project/scripts/main.gd:12615)), and
the minimum frames that must survive at 30. Each sheet also says what the code
does today, so the gap is visible.

Durations come from the backlog items cited on each sheet and from
[MOTION_REFERENCE.md](MOTION_REFERENCE.md). Where the real animal is faster
than a frame, the sheet stretches the *duration* to stay visible and keeps the
real *shape* and angle (#360: exaggerate time, not amplitude).

## Rules for every sheet

- **Frames are rendered frames at `time_scale` 1.** A stage of *s* seconds is
  `round(s × 60)` frames at 60 fps and `max(min30, round(s × 30))` frames at
  30 fps.
- **The 30 fps floor (#687).** Every action keeps at least one wind-up frame
  and at least one hit frame at 30 fps. The **Min @30** column is the floor a
  smoke fails below. A dash means the stage has no floor and simply scales.
  An action whose real hit is shorter than one frame (C-start stage 1, a
  mantis strike, a pistol snap) is stretched to the floor, never dropped.
- **Tolerance.** Smokes allow ±1 frame per stage at 60 fps and ±1 at 30, but
  never below Min @30.
- **Ease column.** *Fast-in* means most of the change happens early (an
  exponential approach or an impulse). *Expo-out* is a drag-shaped decay.
  *In-out* eases both ends. *Hold* means a moving hold (#214): breath, fins
  and eyes keep going.
- **Sim-tick quantisation.** Anything decided in a fish's `tick()` (10 Hz,
  `SIM_HZ`, [sim_driver.gd:70](../shaders-godot/godot-project/scripts/sim_driver.gd:70)) starts on a 100 ms boundary, which is 6 frames at 60 and 3 at
  30. Timers that count down in `tick()` are quantised the same way.
  Off-frustum fish brains run every other tick. An action that needs finer
  timing must run its envelope in `_process`, as the shrimp escape timer does
  (`_escape_remaining` counts down in `_motion_substep`,
  [shrimp.gd:1518](../shaders-godot/godot-project/scripts/shrimp.gd:1518)).
- **Other fixed steps.** The microfauna swarm steps at a fixed 30 Hz with no
  interpolation (`STEP`,
  [microfauna_swarm.gd:28](../shaders-godot/godot-project/scripts/microfauna_swarm.gd:28)),
  and coral, anemones, hydra and the reef clam animate every second frame
  (`ANIM_STEP`, [coral.gd:744](../shaders-godot/godot-project/scripts/coral.gd:744)).
  At 60 fps their stages move in two-frame steps.
- **Exponential eases.** A rate *k* (1/s) in `1 − exp(−k·dt)` reaches 95% of
  its target in 3/*k* seconds. The "today" notes use that figure.

## How a smoke reads a sheet

1. Spawn the creature from a fixed seed in an isolated run
   (`scripts/dev_run.sh`).
2. Drive its `_process` at a fixed `dt` of 1/60, then repeat at 1/30.
3. Trigger the action and record the channels the sheet names every frame.
4. Find stage boundaries from the action's envelope state once
   `ActionEnvelope` (#52) exists. Until then, use the **test proxy** listed on
   the sheet.
5. Assert each stage's frame count against the sheet. Assert that peak speed
   comes after the wind-up (#107), that the follow-through lasts at least
   0.3 s (#108), and that speed has no constant segments between rests (#109).

---

## 1. Dart (voluntary burst)

Backlog #106, #143, #147, #148, #155, #240, #255.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Wind-up | Head and eyes turn 0.1–0.2 rad toward the new heading; pectorals back-scull; tail cocked to the side opposite the first power stroke; body still | 100 | 6 | 3 | 2 | In-out |
| Strike | First power stroke at full amplitude; dorsal and anal fins depress, pectorals adduct; speed climbs to its peak over these frames and the first glide frames | 67 | 4 | 2 | 1 | Fast-in |
| Glide | Tail straight, all fins folded, speed decaying by drag | 400 | 24 | 12 | — | Expo-out |
| Settle | Pectorals re-open below about 40% speed, then the dorsal, then the caudal; tail amplitude grows back to cruise through a spring | 200 | 12 | 6 | — | In-out |
| **Total** | | **767** | **46** | **23** | | |

**Today (`5ad6dd3`).** A dart is a bout picked in `FishLifeBouts._next_bout`
([fish_life_bouts.gd:109](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:109))
at render rate: 0.4–0.8 s at 0.9–1.0 of max speed, with the heading offset by
half of `_bout_yaw`. The motor acceleration is multiplied by 4
([fish.gd:7373](../shaders-godot/godot-project/scripts/fish.gd:7373)), and
`_bout_env` approaches the dart level at rate 7.0. There is no wind-up pose,
and tail amplitude rises on the same frame as speed demand.

**Test proxy.** The frame where `_bout_kind` becomes `BOUT_DART` starts the
wind-up. Peak `speed` must come at least 6 frames later at 60 fps (at least 2
at 30).

## 2. C-start (escape)

Backlog #145, #122, #163, #282, #342, #360, #370.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Latency | None. A direct threat starts stage 1 on the frame it is detected; a propagated alarm waits `signal_reaction_delay`, 80–250 ms (#163) | 0 / 80–250 | 0 / 5–15 | 0 / 3–8 | — | — |
| Stage 1, coil | Body curls into a C (90–120°, kept real), head swings away from the threat, heading rotates 60–120° without the inertial cap; chord −8%, girth +4%; fins tucked. Real duration 10–20 ms, stretched | 50–67 | 3–4 | 2 | 1 | Fast-in |
| Stage 2, stroke | Tail sweeps the other way, body straightens, peak acceleration. One smear frame allowed (#370) | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Glide | Straight flight, fins folded, drag decay | 300–600 | 18–36 | 9–18 | — | Expo-out |
| Recovery | Curved turn back (#282), fins re-open in order, fast breathing | 500–1000 | 30–60 | 15–30 | — | In-out |

**Today.** Startles are raised in `tick()` with `_startle_remaining` between
0.18 and 0.58 s depending on the source (for example
[fish.gd:6298](../shaders-godot/godot-project/scripts/fish.gd:6298)), so
latency is 0–100 ms by tick phase. The heading change is limited by
`FishLifeBouts.inertial_turn`
([fish_life_bouts.gd:151](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:151)).
There is no coil and no stroke shape.

**Test proxy.** Yaw changes by at least 60° within 4 frames at 60 fps (2 at
30) of the startle flag, and the speed peak falls inside stage 2.

## 3. S-start strike (pike-type predators, killifish)

Backlog #146, #168, #485. The gar strikes differently; see the variant below.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Stalk hold | Motionless drift, fin sculling only, eyes fixed on the prey | 1000–3000 | 60–180 | 30–90 | — | Hold |
| Coil | Body into an S with the head *on line* with the prey (a C-start swings the head away) | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Lunge | Body straightens and drives straight forward; mouth opens 2 frames before contact | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Close | Jaw shuts | 50 | 3 | 2 | 1 | Fast-in |
| Recovery | Glide, swallow | 300–500 | 18–30 | 9–15 | — | Expo-out |

**Gar variant.** From the stalk hold, a sideways snap of the head and jaws
lasting 2–4 frames at 60 (1–2 at 30, min 1). The body barely moves (Porter &
Motta 2004).

**Today.** No stalk, coil or strike shape. Predation resolves as a
`kill_prey` event, and the predator's speed comes from `burst_remaining`.

**Test proxy.** None until the action exists.

## 4. Suction-feeding strike (a fish taking a food particle)

Backlog #124, #149, #299, #343, #476, #477.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Approach | Slow, curving in from below or the side (#281) | varies | — | — | — | In-out |
| Fixation | Halt; eyes converge; body aligns; slight back-scull | 150–300 | 9–18 | 5–9 | 3 | Hold |
| Gape | Mouth and throat expand *before* contact | 40 | 2–3 | 1–2 | 1 | Fast-in |
| Suck | Head-forward stretch of 4–6%; the particle zips into the mouth over 2–3 frames | 60–100 | 4–6 | 2–3 | 1 | Fast-in |
| Close | Mouth shuts; opercula flare to expel the water | 80 | 5 | 2–3 | 1 | Fast-in |
| Chew and swallow | Jaw works, settle | 300 | 18 | 9 | — | In-out |

**Today.** `FishMind.aim_before_burst` sets `_aim_remaining` to 0.12–0.22 s,
during which the pull toward food drops to 22%
([fish.gd:5156](../shaders-godot/godot-project/scripts/fish.gd:5156)). It is
used only for feeding frenzies and counts down in `_update_inner_life` at the
sim tick, so it lasts 2–3 ticks. Food is eaten on contact and disappears
(#477). `_trigger_mouth_gape` fires *after* the meal is recorded
([fish.gd:1739](../shaders-godot/godot-project/scripts/fish.gd:1739)), and
`_mouth_gape` decays at 5.5/s.

**Test proxy.** `_mouth_gape` must be above zero at least 2 frames at 60 (1 at
30) before the meal event.

## 5. Peck (a grazing jab at a plant or surface)

Backlog #149, #487.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Fixation | Halt, eyes on the spot, body aligned to the surface normal | 100–150 | 6–9 | 3–5 | 2 | Hold |
| Jab | Head-forward stretch toward the surface | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Bite | Mouth snaps | 33 | 2 | 1 | 1 | Fast-in |
| Recoil | Drift back, tail fanning to hold station | 150–250 | 9–15 | 5–8 | — | Expo-out |
| *Repeat* | 2–5 pecks per visit | | | | | |

**Today.** `FishLifeBouts.peck_steer` runs at the sim tick
([fish_life_bouts.gd:286](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:286)).
It cycles every 0.42 s: a forward push for 0.14 s, then a drift back for
0.28 s ([fish_life_bouts.gd:351](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:351)),
for 1.2–3.0 s per visit. Because the 0.14 s window is sampled at 10 Hz, a jab
lasts one or two ticks depending on phase. There is no head pose and no
fixation.

**Test proxy.** Speed toward the peck point peaks in the jab window, and the
fixation stage shows speed below 15% of max for at least 6 frames at 60
fps.

## 6. Surface gulp (labyrinth fish and other air breathers)

Backlog #133, #152, #167, #205, #315, #344, #364.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Pre-gulp hang | Nose up under the surface, holding (labyrinth fish) | 200–500 | 12–30 | 6–15 | 3 | Hold |
| Rise | An upward arc with the nose up 15–25°, steepening to 30–45° at the meniscus | 600–1200 | 36–72 | 18–36 | — | In-out |
| Gulp | Mouth at the meniscus, gape +30%, throat swells; a ring spreads on the surface | 150 | 9 | 5 | 2 | Fast-in |
| Turn and dive | Roll and turn head-down; a swallowing contraction runs back along the throat; a spent-air bubble leaves the gill or mouth | 400 | 24 | 12 | — | In-out |

**Today.** `_aerial_timer` sends the fish on a 2.0–3.5 s trip every 15–28 s
(labyrinth fish) or 25–40 s (the `shuffle` pattern) by overriding `home_y`
([fish.gd:4310](../shaders-godot/godot-project/scripts/fish.gd:4310)). The
timer is set in `tick()`. There is no pose.

**Test proxy.** Pitch at the meniscus is at least 0.5 rad nose-up, and the
gape is open in the gulp stage for at least 2 frames at 30.

## 7. Corydoras air dash

Backlog #131, #166, #249, #271, #279, #315. The ascent and descent times are
estimates from hobby footage; measure them (see
[MOTION_REFERENCE.md](MOTION_REFERENCE.md)).

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Take-off | Head lifts slightly, pectorals splay (#166) | 33–50 | 2–3 | 1–2 | 1 | Fast-in |
| Dash up | Near-vertical, body straight, fast tail beats | 400–800 | 24–48 | 12–24 | — | Fast-in |
| Gulp | Mouth at the surface | 100–200 | 6–12 | 3–6 | 1 | Fast-in |
| Roll and dive | A curved glide back down, slower than the climb; a bubble released | 800–1500 | 48–90 | 24–45 | — | In-out |
| Landing | 3% squash in Y, pelvic and pectoral fins splay (#131) | 33 | 2 | 1 | 1 | Fast-in |
| Settle | Tail and pectorals settle through two small oscillations (#249) | 200 | 12 | 6 | — | Expo-out |

**Today.** The same trip machinery as the surface gulp (a `home_y` change).
There is no take-off, roll or landing pose.

**Test proxy.** Ascent stage is shorter than the descent stage, and vertical
speed stays above 50% of max through the dash.

## 8. Brake and park

Backlog #14, #156, #226, #270, #274.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Brake onset | Starts at a distance of speed² / (2·decel) from the target; pectorals flare forward, nose pitches up, tail cups | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Brake hold | Held until speed falls below about 40% | varies | — | — | — | Hold |
| Final glide | A slow last glide onto the spot | 300–600 | 18–36 | 9–18 | — | Expo-out |
| Reverse sculls | One or two back-sculls of the pectorals, each | 200–300 | 12–18 | 6–9 | 2 | In-out |
| Park | Hover pose with a moving hold | — | — | — | — | Hold |

**Today.** `Hydrodynamics.brake_pose_amount`
([hydrodynamics.gd:198](../shaders-godot/godot-project/scripts/hydrodynamics.gd:198))
returns a continuous brake from the gap between speed and target (only above
speed 0.35, and only when the target is below 55% of speed). It adds 0.55× to
pectoral amplitude and spread, offsets the tail by 0.38×, and pitches the nose
up by 0.22× (tail [fish.gd:7923](../shaders-godot/godot-project/scripts/fish.gd:7923),
pitch [fish.gd:7729](../shaders-godot/godot-project/scripts/fish.gd:7729),
pectorals [fish.gd:8026](../shaders-godot/godot-project/scripts/fish.gd:8026)). A wall redirect adds a 0.3 s brake (`WALL_BUMP_S`) and eases the
visual yaw out at rate 14 (`_bump_yaw`). Braking is not planned ahead, and
`overshoot_bias` is unused.

**Test proxy.** The brake pose rises above 0.12 before the speed curve turns
down, and there is no frame on which the speed drops by more than 25% at once.

## 9. Display flare (betta frontal and lateral, livebearer sigmoid)

Backlog #157, #173, #197, #198, #312, #358, #361.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Notice | Dorsal lifts, head turns to the receiver, colour flushes (#157) | 300 | 18 | 9 | 2 | In-out |
| Flare | Median fins fully erect; opercula flared (betta); body arched; or the livebearer S (tail, mid-body and head) | 150–250 | 9–15 | 5–8 | 2 | Fast-in |
| Hold | Broadside to the receiver, or to the camera when either side would do (#173); quivering, shown as amplitude above the visible cap (#358); hold time ×1.5 over the real value (#361) | 1000–3000 | 60–180 | 30–90 | — | Hold |
| Release | Fins relax in order and the fish swims off | 400–600 | 24–36 | 12–18 | — | Expo-out |

**Today.** Guppies and endlers use `FishLifeBouts.sigmoid_env`
([fish_life_bouts.gd:276](../shaders-godot/godot-project/scripts/fish_life_bouts.gd:276)):
a linear ramp in at 4/s (0.25 s, 15 frames at 60), out at 2.5/s (0.4 s, 24
frames), held for `_lb_display_t` 0.9–1.9 s, with a quiver at 19 rad/s
(3 Hz). The S is tail 0.5 rad, mid-body −0.85 of that, head 0.3 rad, plus up
to 0.32 extra pectoral amplitude ([fish.gd:7943](../shaders-godot/godot-project/scripts/fish.gd:7943)).
Bettas use `_courtship_flare`, which raises wag and pectoral amplitude and
puffs `_display_scale`. There are no opercula and no notice stage.

**Test proxy.** `_lb_sigmoid` (or the display envelope that replaces it)
reaches 0.9 within the flare stage's frame count, and the hold lasts at least
60 frames at 60 fps.

## 10. Shrimp tail flip

Backlog #23, #291, #518, #519, #541.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Freeze | Antennae sweep forward, legs tuck, body still | 33–67 | 2–4 | 1–2 | 1 | Fast-in |
| Flexion | Abdomen flexes under (pitch about X), tail fan spreads; the shrimp shoots backward and up with its head still facing the threat. Real 30–50 ms | 50 | 3 | 2 | 1 | Fast-in |
| Re-extension | Slower; the fan folds | 150–250 | 9–15 | 5–8 | — | In-out |
| Arc | Up, then gliding down (#291) | 200–400 | 12–24 | 6–12 | — | Expo-out |
| *Repeat* | One to three flips; each cycle | 250–400 | 15–24 | 8–12 | | |

**Today.** `_escape_remaining = 0.28` when predator pressure passes 0.35
([shrimp.gd:915](../shaders-godot/godot-project/scripts/shrimp.gd:915), in
`tick()`), counting down at render rate. During it the tail pitch is
`sin(_swim_phase) × (0.65 + 0.4 × remaining)`
([shrimp.gd:1813](../shaders-godot/godot-project/scripts/shrimp.gd:1813)).
`_swim_phase` advances at 3 + 4·speed rad/s
([shrimp.gd:1471](../shaders-godot/godot-project/scripts/shrimp.gd:1471)),
which is less than half a cycle in 0.28 s, so the visible flex depends on
where the phase started (from reading the code, not measured). The body yaws
at most 2 rad/s (`ESCAPE_FLIP_YAW_RATE`) and travels tail-first within 0.6 rad
of straight back (`ESCAPE_FLIP_CONE`). Legs tuck. There is no freeze and no
tail fan.

**Test proxy.** `TailPivot.rotation.x` reaches its flexion extreme within 3
frames at 60 (2 at 30) of the escape flag, always in the same direction, and
is about X only (#110).

## 11. Shrimp landing

Backlog #37, #525.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Reach | Legs extend down over the last ~0.22 u | 67–100 | 4–6 | 2–3 | 1 | In-out |
| Touchdown | A small body squash | 33 | 2 | 1 | 1 | Fast-in |
| Settle | One dip and recovery; legs gather | 300 | 18 | 9 | — | Expo-out |

**Today.** Within 0.22 u of the floor, Y eases at `LAND_EASE_RATE` 4.0 (95% in
0.75 s), grips at `LAND_GRIP_EPS` 0.006, then dips once over
`LAND_SETTLE_TIME` 0.3 s by up to `LAND_SETTLE_DEPTH` 0.016
([shrimp.gd:1450](../shaders-godot/godot-project/scripts/shrimp.gd:1450)).
There is no leg reach.

**Test proxy.** No frame at 60 fps moves Y by more than 0.02 u in the last
0.22 u, and the settle dip happens exactly once.

## 12. Snail clamp (tuck) and re-emergence

Backlog #28, #39, #576, #577. Stages overlap: each start time is from the
threat frame.

| Stage | Key pose | Start (ms) | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|---|
| Tentacles in | Tentacles and eye stalks shorten | 0 | 150 | 9 | 5 | 2 | Fast-in |
| Head and foot in | The head pulls under, the foot retracts | 100 | 400 | 24 | 12 | — | Fast-in |
| Shell clamps | The shell drops onto the flattened foot | 300 | 150 | 9 | 5 | 1 | Fast-in |
| Operculum closes | Species with an operculum | 450 | 200 | 12 | 6 | 1 | In-out |
| Hold | Clamped | — | 5–30 s | — | — | — | Hold |
| Tentacles out | Slowly, first | 0 | 1500 | 90 | 45 | — | In-out |
| Foot out | After the tentacles are half out | 1000 | 1000 | 60 | 30 | — | In-out |
| Shell lifts | Overlapping the foot | 1200 | 1400 | 84 | 42 | — | In-out |
| Crawl resumes | After a short pause | 2600–3100 | — | — | — | — | In-out |

**Today.** Stalks and shell start on the same frame, with no ordering. The
stalks ease in at `EYE_RETRACT_RATE` 20 (95% in 0.15 s) and out at
`EYE_EXTEND_RATE` 2.0 (1.5 s)
([snail.gd:252](../shaders-godot/godot-project/scripts/snail.gd:252)); the
shell tucks at `TUCK_IN_RATE` 18 (0.17 s) and lifts at `TUCK_OUT_RATE` 2.2
(1.4 s) ([snail.gd:258](../shaders-godot/godot-project/scripts/snail.gd:258)).
The clamp holds for `CLAMP_RELEASE_GRACE` 0.7 s after the threat leaves.

**Test proxy.** Stalk extension falls below 0.5 at least 3 frames at 60 (1 at
30) before the shell tuck passes 0.5; on re-emergence, stalks pass 0.5 before
the tuck falls below 0.5.

## 13. Snail edge crossing

Backlog #26, #56, #569, #593.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Head reach | Head and tentacles reach across the edge onto the new surface | 500–1000 | 30–60 | 15–30 | — | In-out |
| Foot over | The foot bends over the edge | 500–1000 | 30–60 | 15–30 | — | In-out |
| Shell tips | The shell tips over last; it may tap the glass (#593) | 500–1000 | 30–60 | 15–30 | 2 | In-out |
| **Total** | | 1500–3000 | 90–180 | 45–90 | | |

**Today.** The logical pose changes surface in one step, so clamps and scans
see the right surface. The visible `Body` node eases position and rotation from
the last drawn pose over `SURFACE_BLEND_S` 0.6 s
([snail.gd:303](../shaders-godot/godot-project/scripts/snail.gd:303)), which
is 36 frames at 60 and 18 at 30, as one rigid blend. Spawn and load still
snap.

**Test proxy.** No frame rotates the visible body by more than 0.1 rad, and
the head crosses the edge before the shell's centre does.

## 14. Clam close and open

Backlog #619, #620, #622, #624.

| Stage | Key pose | ms | @60 | @30 | Min @30 | Ease |
|---|---|---|---|---|---|---|
| Siphon retracts | First, on a threat or at the end of feeding | 67–100 | 4–6 | 2–3 | 1 | Fast-in |
| Valves snap shut | The adductor closes the valves, with a slight rebound | 150 | 9 | 5 | 2 | Fast-in |
| Closed | Resting | varies | — | — | — | Hold |
| Valves crack | The gape starts | 300 | 18 | 9 | — | In-out |
| Valves open | Ease to full gape | 700 | 42 | 21 | — | In-out |
| Siphon extends | Gradually, once the gape passes about 25% | 500–800 | 30–48 | 15–24 | — | In-out |
| Filtering | The siphon pulses | — | — | — | — | Hold |

**Today.** `_open_amount` approaches its target at rate 4.0 in both directions
(95% in about 0.75 s), so opening and closing take the same time
([clam.gd:230](../shaders-godot/godot-project/scripts/clam.gd:230)). The mode
machine runs at the sim tick: REST 4.5 s, OPENING 1.0 s, FEEDING 6.0 s,
CLOSING 0.8 s ([clam.gd:66](../shaders-godot/godot-project/scripts/clam.gd:66)).
The siphon appears in one frame once the gape passes 25%
([clam.gd:237](../shaders-godot/godot-project/scripts/clam.gd:237)). Clams do
not respond to threats.

**Test proxy.** Closing reaches 95% shut in at most 9 frames at 60 (5 at 30);
opening takes at least 4× as long as closing; the siphon is fully retracted
before the valves pass half-closed.

---

## The 30 fps floor at a glance

| Action | Wind-up stage | Min @30 | Hit stage | Min @30 |
|---|---|---|---|---|
| Dart | Wind-up | 2 | Strike | 1 |
| C-start | Stage 1 coil | 1 | Stage 2 stroke | 1 |
| S-start strike | Coil | 1 | Lunge | 1 |
| Gar strike | Stalk hold | — | Head snap | 1 |
| Suction strike | Fixation and gape | 3 and 1 | Suck | 1 |
| Peck | Fixation | 2 | Jab and bite | 1 each |
| Surface gulp | Pre-gulp hang | 3 | Gulp | 2 |
| Corydoras dash | Take-off | 1 | Gulp | 1 |
| Brake | Brake onset | 1 | Reverse scull | 2 |
| Display flare | Notice | 2 | Flare | 2 |
| Shrimp flip | Freeze | 1 | Flexion | 1 |
| Shrimp landing | Reach | 1 | Touchdown | 1 |
| Snail clamp | Tentacles in | 2 | Shell clamps | 1 |
| Snail edge | Head reach | — | Shell tips | 2 |
| Clam close | Siphon retracts | 1 | Valves snap shut | 2 |

None of the fourteen actions meets its sheet today. The fish ones mostly lack
a wind-up, the snail ones lack ordering, and the shrimp flip and clam close
lack the fast hit.
