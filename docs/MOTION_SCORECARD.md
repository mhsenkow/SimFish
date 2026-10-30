# Motion scorecard — twelve principles × eight families

*Drafted 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #120.
First baseline: graded from the code at `5ad6dd3` (the Phase 0 commit), read
against the Phase 0 notes in the backlog. Not yet graded from clips.*

One page, updated at every milestone. It shows where the motion is weakest,
so the next pass knows where to spend. The principles and their tags are the
water versions defined in
[CREATURE_MOTION_700.md](CREATURE_MOTION_700.md#the-twelve-principles-translated-for-water).
The Phase 6 gate asks for **B or better in every family**; no family has a B
yet.

## Summary

| Principle | Fish | Shrimp | Crabs, lobsters, mantis | Snails | Worms | Sessile | Microfauna | Eggs |
|---|---|---|---|---|---|---|---|---|
| SQ Squash and stretch | D | D | F | C | D | D | F | F |
| AN Anticipation | D | F | F | C | F | F | F | C |
| ST Staging | D | D | D | D | D | D | D | D |
| PP Pose to pose | C | D | D | C | D | C | F | D |
| FT Follow-through | D | C | D | D | C | C | F | D |
| SI Slow in, slow out | C | C | D | C | D | C | D | C |
| AR Arcs | C | D | D | C | D | D | D | F |
| SA Secondary action | C | C | D | C | C | C | F | C |
| TI Timing | C | C | C | D | C | D | D | C |
| EX Exaggeration | D | D | F | D | D | D | F | D |
| SD Solid drawing | C | C | C | C | D | D | D | D |
| AP Appeal | C | C | D | C | D | D | D | D |
| **Mean** (A=4 … F=0) | **1.58** | **1.42** | **0.92** | **1.67** | **1.17** | **1.25** | **0.50** | **1.17** |

**Where to spend next.** Staging and exaggeration are D or worse everywhere:
nothing in the tank manages legibility at pixel scale yet (#60, #171, #359).
Anticipation is F in five families. Microfauna and crabs score lowest, and
microfauna are also the cheapest to lift: a sawtooth hop (#638), facing
(#643) and a shader flap (#647). Glass snails score highest because Phase 0
fixed most of their faults.

## Grades

| Grade | Meaning |
|---|---|
| **A** | Convincing across the family. Measured, and passes the blind review ([MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md)) for that family |
| **B** | Present and mostly right; small, known gaps; backed by a metric or a clip |
| **C** | Present in a basic form; mechanical in places or missing for some members |
| **D** | Token, or present but visibly wrong |
| **F** | Absent, or contradicted by what the code does |

## Fish

| Principle | Grade | Why (code at `5ad6dd3`) |
|---|---|---|
| SQ | D | The only scale changes are the courtship puff (`_display_scale`), a 3% music kick on BodyMid, the gape on `Head.scale.z` and the gravid rest scale. No volume-preserving bend, coil or strike stretch (#121–#123) |
| AN | D | The only real anticipation is `aim_before_burst` (0.12–0.22 s, feeding frenzies only) and the livebearer pursuit. Darts start on the frame the bout is chosen; startles are set in `tick()` and rate-limited by `inertial_turn`; `_turn_lean` follows the yaw rate already happening |
| ST | D | Nothing chooses a broadside or camera-facing display, and there is no pixel-amplitude or event budget. The fry dart trail fires on every fry burst (#190) |
| PP | C | Recognisable postures exist: sift nose-down (0.55 rad), brake nose-up, cleaning tilt, sleep roll (visible since #4), senescent nose-down, the livebearer S, death on the flank. They are picked by a first-match pitch ladder, with no pose library and no transition times |
| FT | D | Tail, mid-body, head and fins are `sin()` of a phase each frame. Only `_fin_tail_activity`, `_turn_lean` and the bank are smoothed, first-order, with no overshoot or settle. Veils, barbels, feelers and `Dorsal2` are rigid |
| SI | C | Speed follows thrust and quadratic drag, with a coasting branch; yaw rate ramps (`inertial_turn`); bank, lean and wall yaw are exponentially damped. But brain targets step at 10 Hz (#253), a dart is a 4× motor acceleration (#255), and several pose lerps use `dt·k` |
| AR | C | Turn-rate caps give curved paths, the bank now leans into the turn (#1), and wall redirects ease the visible yaw (#14). No path planning, no tail-tip figure-eight, and the pectorals move about one axis |
| SA | C | Breath bob, gill pulse, saccades, idle glances and gaze hold, mood-driven fin carriage, shimmy and flash fidgets, pectoral rowing. No eyes, jaw or opercula, and the gill pulse of a resting fish in good water runs at about 0.14 Hz (0.35 Hz at a breath load of 1) |
| TI | C | Beat rate scales with speed and body length per locomotion type, with ±12% per-fish jitter and a mood tempo. But the tail and thrust run on different clocks (#13), every species shares one set of bout timings (#337), stride is near 1 L per beat against a published 0.65 L, and the puffer, corydoras and pleco use the wrong locomotion type (#19) |
| EX | D | No key action is pushed for legibility. The largest amplitudes are the dance bank (±0.95 rad) and courtship |
| SD | C | Body proportions survive every layer (#7), the bank is correct, and pose channels are clamped. Three sibling pivots (no spine, #64), pectorals that mirror apart from a quarter-cycle offset, no pelvic fins, and bottom fish that hover |
| AP | C | Species differ by swim pattern and locomotion family, and the guppy has a real display. The signatures that make a species recognisable (corydoras wink, oto grazing, puffer fins, danio burst-and-glide) are missing |

## Shrimp

| Principle | Grade | Why |
|---|---|---|
| SQ | D | The molt is a 1.10× whole-body pop. The landing dip (0.016 u) is the only squash |
| AN | F | The escape fires on the tick that predator pressure passes 0.35, with no freeze or antenna drop (#541), and there is no leg reach before landing |
| ST | D | The flip now moves tail-first, but nothing makes it read at pixel scale |
| PP | D | A nibble nod, and legs tucked while swimming or flipping. No feeding stance, molt sequence or death curl |
| FT | C | The antenna segments lag each other by 0.38 rad with damping falloff, which is overlapping action, and the eggs ride the tail (#22). There is no follow-through after a stop |
| SI | C | The brain target is interpolated between ticks (`sim_tick_blend`) and landings ease in. Heading turns at a constant rate (#264), start and stop are linear (#265), and the leg sweep is a sawtooth (#515) |
| AR | D | The flip bends up to 0.6 rad toward safety but travels in a straight line. No swimming arcs between perches |
| SA | C | Antenna sway, the nibble nod, walking bob and waddle. The pleopods never beat (`_pleopod_phase` is unused), and there are no antennule flicks or picking hands |
| TI | C | A distance-driven gait with a step rate per body plan, and crepuscular activity. The flip lasts 0.28 s against a real flexion of 30–50 ms |
| EX | D | No key moment is pushed. The flip is part of a sine swing of the tail pitch |
| SD | C | The abdomen no longer wags like a fish (#12), and the legs tuck in flips. Three one-segment leg pairs instead of five two-segment ones; foot slip not measured |
| AP | C | Reads as a scurrying, nodding shrimp. The cherry shrimp's picking signature is missing (#524) |

## Crabs, lobsters and mantis shrimp

| Principle | Grade | Why |
|---|---|---|
| SQ | F | No squash beyond the shared molt pop |
| AN | F | Nothing telegraphs: no claw raise, no eye fixation before a strike |
| ST | D | No threat display (#545) |
| PP | D | A walking pose only; no threat, rearing or death pose |
| FT | D | Antennae on the shared sines only; claws and eyestalks are rigid |
| SI | D | Constant-rate turns and linear starts and stops; no heavy settle on a stop (#556) |
| AR | D | Straight walks; flips as shrimp |
| SA | D | The legs walk (crab legs are hinged since #24). Claws, eyestalks, mouthparts and raptorial arms are static |
| TI | C | Gait profiles differ by body plan (crab 7.5, mantis 4.5, lobster 3.2 steps per unit), so weight reads in the stride |
| EX | F | The mantis strike and the pistol snap don't exist |
| SD | C | Crab legs hinge and the body faces across its travel. The leg phases form a quarter-cycle rear-to-front wave, not an alternating tetrapod gait, and the stroke runs along the body axis (#542) |
| AP | D | The sideways crab walk reads. No claw-to-mouth feeding, mantis eyes or burrow peeking |

## Snails (glass snails and trumpet snails)

| Principle | Grade | Why |
|---|---|---|
| SQ | C | Squash deforms only the foot, and the clamp flattens it under a dropping shell (#28). No volume-preserving foot stretch (#566); trumpet snails are rigid |
| AN | C | The eye stalks point into a turn before the body follows (the stalk turn lean in `_tick_eye_stalks`), and they pull in on a clamp. No tentacle sweep and no cautious re-emergence (#577) |
| ST | D | No pedal waves, the one snail motion that reads through the glass (#565) |
| PP | C | Crawling, the paused scan, the clamped tuck, the shell-first sink and righting are distinct states that blend |
| FT | D | The shell is rigid on the foot, with no rock or swing (#567). Tuck and stalks start on the same frame (#576) |
| SI | C | Stalks ease fast in and slow out (0.15 s, 1.5 s), the shell tucks in 0.17 s and lifts over 1.4 s, and surface changes blend over 0.6 s (#26). Facing still turns at 5.5 rad/s (#266), and trumpet snails change velocity instantly (#267) |
| AR | C | Surface transitions blend position and rotation instead of snapping. No edge sequence (#569); a fall is a sink, then a slerp |
| SA | C | Stalk sway, scheduled stalk pulls, an idle squash and a grazing rasp pulse. No head or tentacles (#570) |
| TI | D | A 180° turn in 0.57 s; righting is a fixed 1.9 s slerp; crawl speed (0.11 u/s, gated by a 0.21 Hz pulse) is not calibrated (#581) |
| EX | D | Nothing is pushed; the clamp is the only legible event |
| SD | C | The head now leads the crawl (#25), the shell doesn't squash, and snails no longer sink under the floor (#27). Trumpet snails never face their travel (#594) |
| AP | C | Glass snails hold a heading for 6–14 s and read as snails. Trumpet snails read as drifting cones |

## Worms (wriggle worms, bristle worms, tubifex, sea cucumber)

| Principle | Grade | Why |
|---|---|---|
| SQ | D | Cucumber segments stretch together, in phase (#32). No peristalsis (#599) |
| AN | F | Tubifex hide a worm in one frame when grazed. Nothing telegraphs a withdrawal |
| ST | D | The tubifex patch doesn't withdraw as one (#606) |
| PP | D | No coil or withdrawn pose |
| FT | C | The bristle-worm wave now runs head to tail with the bristles on their segments (#30, #31); each tubifex worm has its own phase |
| SI | D | Pure sines; an instant hide; no easing on emergence |
| AR | D | Wriggle worms strafe instead of following the head's path (#598) |
| SA | C | Lateral undulation, the tubifex wriggle and cucumber tentacles, at fixed rates |
| TI | C | Frame-rate drift (#29) and the double phase step (#32) are fixed. The tubifex rate ignores oxygen (#607) |
| EX | D | Nothing is pushed |
| SD | D | Worms don't face their travel, and tubifex rotate about their centre instead of their base (#605) |
| AP | D | They read as generic wigglers |

## Sessile animals (clams, coral, anemones, hydra)

| Principle | Grade | Why |
|---|---|---|
| SQ | D | Polyp scale retraction, eased since #38. Anemones never ball up and hydra never contract |
| AN | F | Clams ignore threats (#622). Polyps retract after a fish arrives, not before |
| ST | D | Retraction doesn't spread from the point of touch (#630) |
| PP | C | The clam's REST → OPENING → FEEDING → CLOSING cycle reads as a sequence of poses |
| FT | C | Soft coral sways with lag from base to tip, and anemone tips sway as children of their tentacles (#33) |
| SI | C | The clam gape eases exponentially and respects the time scale (#36), and polyp retraction is eased. Opening and closing take the same time (#619), the siphon appears in one frame at 25% gape (#620), and coral steps every second frame (#636) |
| AR | D | Reef clam shells rotate about their own centres, not the hinge (#618) |
| SA | C | Polyp pulse, tentacle sway, hydra tentacle sines |
| TI | D | Symmetric gape timing; hydra have no contraction bursts (#613) |
| EX | D | No shadow reflex or snap (#624) |
| SD | D | The reef clam hinge is in the wrong place |
| AP | D | They read as decoration that breathes |

## Microfauna (copepods, daphnia, larvae)

| Principle | Grade | Why |
|---|---|---|
| SQ | F | None |
| AN | F | None. Copepods hop when a wake reaches them, which is a reaction, not a telegraph |
| ST | D | Swarms don't form clouds or clear around fish (#654, #655) |
| PP | F | No poses: one baked mesh per morph |
| FT | F | Appendages are baked into the mesh |
| SI | D | Hop drift decays exponentially with no coasting, which is right at this size. The daphnia rise and sink is a square wave (#638), and the swarm steps at 30 Hz with no interpolation |
| AR | D | Hops are straight segments (#294); nothing faces its travel |
| SA | F | No appendage motion (#647) |
| TI | D | Daphnia complete about 0.28 cycles a second against several hops a second. Copepod hop lengths are plausible |
| EX | F | None |
| SD | D | A ±0.30 rad yaw wobble; never faces its travel (#643) |
| AP | D | Specks that drift |

## Eggs (fish, snail and shrimp eggs)

| Principle | Grade | Why |
|---|---|---|
| SQ | F | None |
| AN | C | The wobble ramps in over the last 30% of incubation and the glow pulse quickens before hatching (`egg.gd`) |
| ST | D | Nothing marks the hatching moment |
| PP | D | Snail clutches swap in an instant (#649) |
| FT | D | Shrimp eggs ride the abdomen (#22); fish and snail eggs are rigid |
| SI | C | The wobble runs on a render-rate visual clock (#35) |
| AR | F | No fall path in `egg.gd`: scattered eggs don't drift down (#651) |
| SA | C | Wobble and glow pulse |
| TI | C | Pulse and wobble rates rise with development |
| EX | D | Nothing is pushed |
| SD | D | Eggs sit; they don't stick or settle |
| AP | D | They read as eggs; there is no hatching moment (#648) |

## How to re-grade

**When.** At every phase gate in the backlog's plan, and before any release
that changes motion. Add a row to the history table below and update the
summary grid.

**Evidence.** Grade from what can be seen, not from what was merged:

1. **Clips.** Once the motion lab and clip capture exist (#94, #98), use their
   clips. Until then, use `dev/swimming_capture.tscn` for fish and
   `dev/inspect.tscn` stills for snails, worms and anemones. Run both through
   `scripts/dev_run.sh`.
2. **Metrics.** Jerk, kink count, phase lag, Strouhal and twins (#85–#89),
   the probe columns (#100), the invertebrate probe (#101), foot slip (#102)
   and facing (#103), as they land.
3. **The blind review.** The family's identification rate and "alive" rating
   from [MOTION_REVIEW_PROTOCOL.md](MOTION_REVIEW_PROTOCOL.md).

**Rules.**

- Grade the family's **common case**, not its best member. One good species
  doesn't lift the fish row.
- **No grade above C without a metric or a clip** that shows it.
- **No A without a blind-review result** for that family.
- Grade at the default camera and at **30 fps** (mobile). A motion that only
  reads at 60 fps scores one grade lower.
- Don't upgrade for code that can't be seen: off-frustum work, sub-pixel
  amplitude, or a feature behind a flag that is off.
- Every changed cell needs a one-line reason and its evidence (clip path,
  metric value or review row) in the history table.
- Grade with the backlog's principle definitions, not general animation
  taste. Cartoon squash and stretch scores lower, not higher.

## History

| Date | Commit | Basis | Fish | Shrimp | Crabs | Snails | Worms | Sessile | Micro | Eggs | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-30 | `5ad6dd3` | Code reading (this page) | 1.58 | 1.42 | 0.92 | 1.67 | 1.17 | 1.25 | 0.50 | 1.17 | First baseline, after Phase 0. Re-grade from clips at the Phase 1 gate |
