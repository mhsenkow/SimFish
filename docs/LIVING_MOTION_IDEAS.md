# Living Motion — The Murmuration Pass (100 ideas)

*Drafted 2026-07-02. Director's brief for **motion as life**: how the tank moves,
grows, and reacts so the eye reads *aliveness* before it reads anything else. The
hero is the school — real starling-murmuration behaviour where the swarm becomes
one living body — but only for **species that school**. Everything else in the
tank gets the same principle applied at its own scale: growth you can watch
happen, water that couples every body, and nothing ever truly still.*

> **The finding that names this doc.** The schools look like "a wave of the tank
> pushes all the fish" for two concrete, fixable reasons, both verified in the
> working tree today:
>
> 1. **Neighbours are chosen by metric radius, not topological count.**
>    `_boids()` gathers every conspecific inside `sep_r2 = (separation_radius *
>    mult / tightness)²` ([fish.gd:7150–7196](../shaders-godot/godot-project/scripts/fish.gd:7150)).
>    Metric-radius boids produce a *cohesive blob*: pack them tight and each fish
>    over-couples to a crowd; spread them out and the school shatters. **Real
>    murmurations are topological** — a starling tracks a fixed ~6–7 nearest
>    neighbours *regardless of density* (Ballerini et al. 2008). That single
>    change is what makes density waves cross a whole flock and the group hold
>    together through a hawk strike. This is the master lever (#1).
> 2. **Correlation is imposed globally instead of propagating.** The coordinated
>    motion you see is a tank-wide `school_pulse()` on a 28 s clock
>    ([sim_driver.gd:184](../shaders-godot/godot-project/scripts/sim_driver.gd:184)),
>    a music `sweep` applied uniformly to every fish, and a radial `startle_bolt`
>    every fish reads *simultaneously* ([sim_topdown.gd:30–33](../shaders-godot/godot-project/scripts/sim_topdown.gd:30)).
>    All three are broadcasts. A murmuration has **no broadcast** — a turn starts
>    at one edge and *travels* through the topological links faster than the birds
>    themselves move (§B). Replace "everyone does X now" with "X spreads from
>    here," and the swarm stops looking pushed and starts looking *alive*.
>
> The scaffolding to do this well already exists: a spatial hash for neighbour
> queries, `MindBoidsBuffer` (SoA sep/ali/coh accumulators, the natural home for a
> topological rewrite), a `TankFlowField` (8×4×8 velocity grid with deposit/sample),
> `Hydrodynamics` (drag/coast/bank, currently optional), and per-fish deterministic
> RNG. This doc wires the *behaviour* onto substrate that's mostly already paid for.

**What already exists (build on it, don't rebuild):** three-rule boids with view
cone + 0.4 s lookahead + speed-matching + density-softened cohesion + formation
slots + leader tracking (`_boids()`); banking via `_bank_pivot`; the
burst/coast/`Hydrodynamics.integrate_speed` motor; startle bolt / density wave /
sync turn / school pulse (`sim_topdown.gd`); music sweep/vertical/tightness mods;
shader sway + flutter + `brush()` bend on plants; anemone/clam/polyp sessile
motion; pearling; `TankFlowField` wakes + eddies; discrete voxel plant growth.

Format: house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S (polish) / M (noticeable) / L (transforms the feel). Anchors are
symbol-first (line numbers drift); the ones cited were verified 2026-07-02.

---

## A. The murmuration — topological schooling (the hero; schooling species only)

*Every item in this section is gated on `swim_pattern in {"school","shoal"}` and
`schooling_strength > 0.4` (the exact flags at [fish.gd:715](../shaders-godot/godot-project/scripts/fish.gd:715)
/ [3694](../shaders-godot/godot-project/scripts/fish.gd:3694)). A betta, a pleco,
an angelfish pair never enters this code path — contract #41 makes that a test.*

1. **Topological neighbours, not metric.** Rebuild `_boids()` neighbour selection:
   sort candidates by distance, take the nearest **N_topo = 7** conspecifics in the
   view cone, and apply sep/ali/coh to *those* regardless of how far the 7th is.
   The `MindBoidsBuffer` capture is already SoA — do the partial-sort there. This
   is the single change that turns a blob into a murmuration; everything else in §A
   sharpens it. *Effort L, Impact L.* **Shipped 2026-07-02** (`mind_boids_compute.gd`, `fish.gd`).
2. **Anisotropic neighbour weighting.** Starlings couple more strongly to
   neighbours on their *flanks* than fore/aft (the empirical anisotropy that keeps
   the flock a sheet, not a tube). Weight each topological neighbour's influence by
   `1.0 + flank_bias * (1 - |heading · to_neighbour|)`. *Effort M, Impact M.*
   **Shipped 2026-07-02** (`FLANK_BIAS` in `mind_boids_buffer.gd`).
3. **Density-independent spacing.** With topological neighbours, separation should
   target a *preferred angular size* of a neighbour, not a fixed metric radius — so
   the school compresses and expands smoothly without the current density-factor
   cohesion hack ([fish.gd:7257–7261](../shaders-godot/godot-project/scripts/fish.gd:7257)).
   *Effort M, Impact M.* **Shipped 2026-07-02** (angular `1/r` sep on topo set).
4. **Equalize influence — no lonely 8th.** Cap contribution so a fish with only 3
   visible conspecifics still schools crisply (weights renormalize to the count),
   killing the "edge fish drifts off" artifact metric radius causes. *Effort S, Impact M.*
   **Shipped 2026-07-02** (`sqrt(N_topo/count)` cohesion gain).
5. **Retire the tank-wide school pulse.** Delete the uniform 28 s `school_pulse()`
   tightness broadcast ([sim_driver.gd:184](../shaders-godot/godot-project/scripts/sim_driver.gd:184));
   the breathing it fakes becomes *emergent* from §B wave propagation. This is the
   "push" the player sees — remove the cause, not the symptom. *Effort S, Impact L.*
   **Shipped 2026-07-02** (pulse disabled by default; fish no longer samples it).
6. **Per-school identity, cheaply.** Union-find over topological links each mind
   tick assigns a `school_id` to connected conspecific clusters — no heavy group
   object, just a label so two shoals of the same species can behave as two bodies,
   split, and merge. *Effort M, Impact M.* **Shipped 2026-07-03** (`motion_school.gd`).
7. **Fission–fusion.** When a school's spatial variance exceeds a threshold for >2 s
   (an obstacle or predator splitting it), let sub-clusters keep separate `school_id`s
   and re-merge when they overlap — the hypnotic split-and-rejoin of real flocks.
   *Effort M, Impact L.* **Shipped 2026-07-03** (`motion_school.gd`).
8. **Marginal-fish opacity.** Fish on the school's convex hull face outward and swim
   slightly faster to get back in (the selfish-herd instinct); interior fish relax.
   Compute a cheap "how enclosed am I" from topological neighbour spread.
   *Effort M, Impact M.* **Shipped 2026-07-02** (enclosedness steer in `fish.gd`).
9. **Roll-into-the-turn as a school.** When the school banks, neighbours' banks
   correlate through the same topological links (read neighbour `_bank_pivot`), so a
   turn shows as a *sheet of silver rolling* — the flash that makes a school read as
   one animal. *Effort M, Impact L.* **Shipped 2026-07-03** (`MotionSchool.bank_correlation`).
10. **Speed-matching over topological set.** Move the existing speed-match
    ([fish.gd:7302](../shaders-godot/godot-project/scripts/fish.gd:7302)) onto the 7
    neighbours so cruise speed equalizes locally and propagates, instead of chasing a
    metric-crowd average. *Effort S, Impact M.* **Shipped 2026-07-02**.

## B. Scale-free correlation — the turn that travels

*A murmuration's defining physics: information crosses the flock at constant speed,
faster than any bird flies, so a maneuver at one edge sweeps the whole group like a
wave. We already have wave *primitives* (`sync_turn` distance-delay in
[sim_topdown.gd:40–60](../shaders-godot/godot-project/scripts/sim_topdown.gd:40)) —
this section makes them the *only* source of correlation, and makes them agile.*

11. **Agitation as a propagating scalar.** Give each fish an `agitation` value that
    it copies-with-decay from its most-agitated topological neighbour each tick. A
    startle injects agitation at one point; it *diffuses* through the links at a
    tunable "manoeuvre wave speed," never as a global flag. *Effort M, Impact L.*
    **Shipped 2026-07-02** (`motion_wave.gd`).
12. **Turn intent propagates, not turn result.** A fish that decides to turn raises
    a `turn_intent` its neighbours partially adopt next tick — so the fold of the
    turn crosses the flock visibly over ~0.3–0.8 s instead of snapping. *Effort M, Impact L.*
    **Shipped 2026-07-02** (`motion_turn_intent` + `MotionWave.tick`).
13. **Constant wave speed, density-independent.** Tune propagation so the wave
    crosses N fish in time proportional to N (not to metres) — the scale-free
    signature. Expose `manoeuvre_wave_speed` for tuning. *Effort M, Impact M.*
    **Shipped 2026-07-02** (`MANOEUVRE_WAVE_SPEED`).
14. **Directional startle waves.** Replace the purely radial `startle_bolt` with
    injection at the fish nearest the threat, propagating *away* through links — the
    escape wave bends around the flock's shape instead of a clean circle. *Effort M, Impact L.*
    **Shipped 2026-07-02** (`pulse_startle_bolt` → `MotionWave.inject_at`; schoolers
    adopt propagated agitation instead of radial bolt).
15. **Music sweep enters through the flock, not from the sky.** Instead of adding
    `music_mods["sweep"]` to every fish uniformly ([fish.gd:5028](../shaders-godot/godot-project/scripts/fish.gd:5028)),
    inject the sweep impulse at a school leader and let §B carry it — the dance
    *travels* through the school on the beat. *Effort M, Impact L.*
    **Shipped 2026-07-02** (`tick_music_sweep`; schoolers skip uniform groove steer).
16. **Turn-rate agility scales with agitation.** A calm fish turns at the base 2.6
    rad/s; an agitated one unlocks toward ~4–5 rad/s ([fish.gd:6518–6552](../shaders-godot/godot-project/scripts/fish.gd:6518)),
    so the escape wave is *sharp* where it's hot and lazy where it's cooled.
    *Effort S, Impact M.* **Shipped 2026-07-02**.
17. **Refractory settle.** After a wave passes, a fish is briefly less excitable
    (refractory period) so the flock *relaxes* rather than ringing — the exhale after
    the startle. *Effort S, Impact M.* **Shipped 2026-07-02**.
18. **Cascade cap, honestly.** Bound how far one wave travels by agitation decay, and
    surface the tuning; a whisper should ripple three fish, a hawk should cross the
    whole flock. No magic global reset. *Effort S, Impact S.* **Shipped 2026-07-02**
    (`CASCADE_FLOOR` + decay).
19. **Two-wave interference.** Because waves are local, two startles from opposite
    ends produce a real collision in the middle — a dense flash where they meet. Free
    emergent beauty once #11 lands. *Effort S, Impact M.* **Shipped 2026-07-03**
    (emergent from local `MotionWave` diffusion; dual injects collide in the middle).
20. **Predator-shape avoidance, propagated.** A looming shadow (bird overhead, tap
    location) injects avoidance at the nearest fish; the flock *pours* away from the
    point and closes behind it (the murmuration "hole"). *Effort M, Impact L.*
    **Shipped 2026-07-03** (`MotionField.inject_shadow` + threat memory steer).

## C. The individual inside the swarm

*A murmuration is mesmerizing because it's one body made of a thousand slightly
different wills. The tank already has per-fish personality, rank, and RNG — spend
it on motion so no two fish trace the same arc.*

21. **Jockeying for the core.** Personality sets a preferred flock position: bold
    fish tolerate the exposed margin, timid fish push for the safe interior — a
    slow constant churn inside the school. Reads beautifully from any angle.
    *Effort M, Impact M.* **Shipped 2026-07-03** (marginal-fish enclosedness + personality bias).
22. **Transient leaders, not fixed.** The current `lead_score`
    ([fish.gd:7198](../shaders-godot/godot-project/scripts/fish.gd:7198)) is stable;
    let leadership pass — whoever is currently at the front of a turn briefly gains
    influence, then yields. Real flocks have no permanent leader. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`motion_lead_boost` in `motion_school.gd`).
23. **Individual turn phase.** Each fish adopts a wave's turn with a tiny personal
    latency (from its seeded RNG), so the turn front has *texture* — a shimmer, not a
    hard line. *Effort S, Impact M.* **Shipped 2026-07-03** (per-fish wave jitter in `motion_wave.gd`).
24. **Micro-overshoot and correct.** Give steering a slight underdamped response so
    fish overshoot the ideal slot and settle back — the constant small corrections
    that make living things look alive vs. lerped. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`_steer_carry` in `fish.gd`).
25. **Fatigue.** Sustained bursts deplete a stamina pool; a tired fish drops to the
    interior and coasts. Escape waves visibly cost the flock energy. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`motion_stamina` in `fish.gd`).
26. **Size-graded response lag.** Larger/older fish (`growth_factor`, maturity) adopt
    waves a hair later and turn wider ([fish.gd:6455](../shaders-godot/godot-project/scripts/fish.gd:6455));
    fry snap instantly. The flock's front isn't uniform. *Effort S, Impact S.*
    **Shipped 2026-07-03** (growth-factor blend in `motion_wave.gd`).
27. **Curiosity breakaway.** Occasionally a single fish peels toward something
    interesting (food scent, glass tap) and the school's cohesion decides whether it
    drags others or snaps back — a living tension. *Effort M, Impact M.*
    **Shipped 2026-07-03** (peel steer toward glance/interest in `fish.gd`).
28. **Personal cruising gait.** Per-fish tail-beat frequency offset and amplitude
    bias (seeded), so even at matched speed the school is a texture of gaits, not a
    metronome. Builds on `_swim_phase` offset ([fish.gd:1885](../shaders-godot/godot-project/scripts/fish.gd:1885)).
    *Effort S, Impact M.* **Shipped 2026-07-03** (`_gait_amp_bias` + `_wag_freq_jitter`).
29. **Glance-around.** Idle fish periodically yaw their head (not heading) to "look,"
    breaking the dead-ahead stare — a few degrees of independent head motion.
    *Effort S, Impact M.* **Shipped 2026-07-03** (idle `_saccade_target` + saccades).
30. **Buddy bias.** Fish weight bonded conspecifics slightly higher in the
    topological set, so friend-pairs stay adjacent as the school churns — continuity
    the player can follow. *Effort S, Impact M.* **Shipped 2026-07-03** (`_buddy_topo_d2` in `mind_boids_compute.gd`).

## D. Everything that *isn't* a school (the constraint, made real)

*The user's line: extreme schooling for schools, and only schools. This section
guarantees the other movement archetypes stay distinct and get their own life.*

31. **Solitary means solitary.** `swim_pattern == "hover"` (angelfish) and
    `schooling_strength < 0.4` fish run separation-only, no ali/coh, no §A/§B waves —
    verify the gate at [fish.gd:1437](../shaders-godot/godot-project/scripts/fish.gd:1437)
    holds after the topological rewrite. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`smoke_murmuration.gd` hover + betta contract).
32. **Territorial station-keeping.** Hover species hold a home volume with pectoral
    sculling and slow patrol of *their* patch, driving intruders off — presence
    without schooling. *Effort M, Impact M.* **Shipped 2026-07-03** (`fish.gd` hover patch).
33. **Pair-bond choreography.** Bonded pairs (angelfish, some cichlids) mirror each
    other's motion at close range — a two-body dance distinct from a school.
    *Effort M, Impact M.* **Shipped 2026-07-03** (partner mirror steer in `fish.gd`).
34. **Cruiser patrol paths.** `"cruise"` fish (betta) trace lazy perimeter loops with
    personality-varied waypoints, not random wander — a purposeful solo beat.
    *Effort M, Impact S.* **Shipped 2026-07-03** (`_cruise_wp_angle` patrol).
35. **Ambush stillness.** Predatory/`"sit"` species genuinely hold, with only gill
    and eye motion, then explosive lunge — the contrast makes the schools feel faster.
    *Effort M, Impact M.* **Shipped 2026-07-03** (`sit` pattern damp + burst lunge).
36. **Bottom-shuffle gait.** `"shuffle"` corys/loaches hop-and-rest along the
    substrate with contact bounce, distinct from mid-water glide. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`_shuffle_hop_t` hop-rest).
37. **Surface skitter.** `"dart"` killifish hug the surface with nervous
    micro-darts and the occasional skip — a different nervous system entirely.
    *Effort S, Impact S.* **Shipped 2026-07-03** (surface hug + existing dart burst).
38. **Meander drift.** `"meander"` puffers wobble-hover with independent fin sculling,
    slow and comic, never schooling. *Effort S, Impact S.* **Shipped 2026-07-03** (phase wobble steer).
39. **Cross-species avoidance, not schooling.** Non-conspecifics keep separation
    (already true at [fish.gd:7169](../shaders-godot/godot-project/scripts/fish.gd:7169))
    but never align/cohere — a mixed tank reads as several separate lives sharing
    water. *Effort S, Impact M.* **Shipped 2026-07-03** (`smoke_murmuration.gd` sep-only assert).
40. **Loose shoaling ≠ tight schooling.** `"shoal"` species use topological neighbours
    but a lower alignment gain and larger preferred spacing than `"school"` — present
    together but casually, the way rasboras differ from tight tetras. *Effort S, Impact M.*
    **Shipped 2026-07-02** (ali/coh/slot gains in `fish.gd`).
41. **The "only the school" smoke test.** A unit test spawns a betta among a tetra
    school and asserts the betta's alignment/cohesion accumulators stay zero and it
    receives no §B wave adoption. Locks the contract forever. *Effort S, Impact M.*
    **Shipped 2026-07-02** (`smoke_murmuration.gd`).

## E. The body that actually swims (motion truthfulness)

*Hydrodynamics exists but is optional and the tail is cosmetic
([HYDRODYNAMIC_LIFE_IDEAS.md](HYDRODYNAMIC_LIFE_IDEAS.md) headline). A murmuration
of bodies that don't obey momentum still looks like sprites. Turn the motor on and
couple it to the stroke.*

42. **Thrust from the tail-beat.** Couple `_swim_phase` stroke to a forward impulse
    so speed *pulses* with the beat ([fish.gd:6576](../shaders-godot/godot-project/scripts/fish.gd:6576));
    the fish visibly pushes water. 90% of "that's alive" for ~10% of CFD. *Effort M, Impact L.*
    **Shipped 2026-07-03** (1.22× stroke thrust multiplier).
43. **Momentum and coast everywhere.** Make `Hydrodynamics.use_full_physics` the
    default, not opt-in ([fish.gd:6484](../shaders-godot/godot-project/scripts/fish.gd:6484)):
    quadratic drag, added mass, burst→glide. The single biggest "in water" win.
    *Effort M, Impact L.* **Shipped 2026-07-02** (`hydrodynamics.gd`).
44. **Speed-dependent turn radius.** Fast fish carve wide, slow fish pivot tight
    (partly present at [fish.gd:6523](../shaders-godot/godot-project/scripts/fish.gd:6523));
    make it a true radius so darting flocks bank in arcs, not corners. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`min_turn_r` cap in `_motion_substep`).
45. **Banked inertial turns for the school.** With #43, a hard school turn leans the
    whole sheet (ties to #9) and the outside fish accelerate to hold the arc — real
    flock geometry. *Effort M, Impact M.* **Shipped 2026-07-03** (yaw-rate speed boost).
46. **Body-wave amplitude tracks effort.** Tail amplitude and body-bend rise with
    thrust demand, not just speed ([fish.gd:6799](../shaders-godot/godot-project/scripts/fish.gd:6799)),
    so a fish fighting a current *works* visibly. *Effort S, Impact M.*
    **Shipped 2026-07-03** (flow-coupled `hydro_effort` wag).
47. **Pectoral braking.** A fish stopping flares pectorals and pitches up to brake
    (station-keep code exists, [fish.gd:6590](../shaders-godot/godot-project/scripts/fish.gd:6590));
    extend to deceleration so stops read as effort. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`_brake_pose` pec flare + pitch).
48. **Glide-and-flick cruising.** Idle cruisers alternate a few strong beats with a
    long glide (burst→coast already present); tune the rhythm per species. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`_motion_glide_bias` + coast phase rate).
49. **Recoil on lunge.** A fast strike shoves the body back a touch (Newton's third)
    before the surge — tiny, but it sells mass. *Effort S, Impact S.*
    **Shipped 2026-07-03** (sit-pattern lunge recoil nudge).
50. **Sink and rise with buoyancy.** Resting fish drift down slightly and finning
    lifts them (buoyancy step at [fish.gd:6593](../shaders-godot/godot-project/scripts/fish.gd:6593));
    make it perceptible so "hovering" is active, not frozen. *Effort M, Impact M.*
    **Shipped 2026-07-03** (stronger bob/sink in `hydrodynamics.gd`).

## F. Reactive motion — the flock as one nervous system

*Reactions are where "alive" is won or lost. The pieces exist (startle, brush, care
broadcast); this makes them propagate and vary.*

51. **Graded startle, not binary.** A distant tap ripples three fish (§B); a shadow
    overhead sweeps the flock; a net is chaos. Scale injection by stimulus salience,
    not one 0.62 s bolt ([sim_topdown.gd:32](../shaders-godot/godot-project/scripts/sim_topdown.gd:32)).
    *Effort M, Impact L.* **Shipped 2026-07-03** (`pulse_startle_bolt` salience + `MotionField`).
52. **Feeding rush that forms and dissolves.** Food scent injects an *attraction*
    wave through the school toward the pellet, then the flock breaks into individual
    feeding darts and re-coheres after — a whole arc of motion from one event.
    *Effort M, Impact L.* **Shipped 2026-07-03** (`MotionField.inject_feeding` + flow burst).
53. **Glass-tap flinch with direction.** A tap flinches nearby fish *away from the
    glass point* and the wave carries inward — not a uniform scatter. *Effort S, Impact M.*
    **Shipped 2026-07-03** (directional `pulse_startle_bolt` + tap away vector).
54. **Curiosity approach.** After the flinch settles, bold fish drift *back* toward a
    novel but harmless stimulus (the keeper's finger held still) — fear then curiosity,
    the real fish arc. *Effort M, Impact M.* **Shipped 2026-07-03** (`_curiosity_return_t`).
55. **Shadow response.** A hand or object passing over casts intent the flock reads as
    an aerial predator — instant dive-and-scatter, the most primal fish reaction.
    *Effort M, Impact M.* **Shipped 2026-07-03** (overhead camera → `pulse_shadow`).
56. **Freeze option.** Some stimuli should *freeze* the flock (sudden stillness) before
    the burst — the held breath before the scatter, which makes the scatter land harder.
    *Effort S, Impact M.* **Shipped 2026-07-03** (`motion_freeze_t` + high-salience inject).
57. **Contagious calm.** Care events (feed, water change; [keeper_care.gd:138](../shaders-godot/godot-project/scripts/keeper_care.gd:138))
    inject *negative* agitation that spreads the same way — the flock visibly settles
    when the keeper is gentle. Symmetry with §B. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`MotionField.inject_calm`).
58. **Startle leaves a wake.** Post-scatter, the flock's re-cohesion path bends around
    where the threat was for a few seconds — a memory written in motion. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`MotionField.threat_avoid_steer`).
59. **Injury/age gait.** Senescent or unwell fish lag the waves and list slightly
    ([fish.gd:6455](../shaders-godot/godot-project/scripts/fish.gd:6455)) — motion as a
    legible health readout. *Effort S, Impact M.* **Shipped 2026-07-03** (maturity turn scaling).
60. **Sleep drift and wake-startle.** Night: schools loosen and drift, fish tilt to
    rest ([fish.gd:6315](../shaders-godot/godot-project/scripts/fish.gd:6315)); a
    disturbance wakes the nearest and the wake propagates — a groggy, staggered
    version of the day startle. *Effort M, Impact M.* **Shipped 2026-07-03**
    (night school loosen + groggy salience scale).

## G. The living plantscape — growth you can watch

*Plants grow by discrete voxel pops ([plant.gd:130](../shaders-godot/godot-project/scripts/plant.gd:130))
and sway on a time-based shader that ignores the flow field. Make growth a visible
motion and make foliage answer the water and the fish.*

61. **Growth you can see happen.** When a voxel is added, scale it in from zero over
    ~1 s and settle with a tiny overshoot, instead of popping — you *catch* a plant
    growing. *Effort S, Impact M.* **Shipped 2026-07-03** (`plant.gd` scale-in tween).
62. **Reach toward light.** Stems lean their growth direction toward the brightest
    nearby light over hours (phototropism) — slow, but the tank rearranges itself
    while you're away. *Effort M, Impact M.* **Shipped** (`_phototropic_offset` in `plant.gd`).
63. **Foliage reads the flow field.** Feed `TankFlowField.sample()` into the foliage
    sway uniform ([foliage.gdshader:42](../shaders-godot/godot-project/shaders/foliage.gdshader:42))
    so plants bend *downstream* near the filter and go slack in dead water — right
    now sway is pure `TIME` and ignores current. *Effort M, Impact L.*
    **Shipped 2026-07-03** (`flow_dir` / `flow_strength` uniforms + `world.sample_flow`).
64. **Wake-driven sway.** A fish darting past deposits into the flow field
    ([world.gd:7972](../shaders-godot/godot-project/scripts/world.gd:7972)); with #63,
    nearby leaves *swish* in its wake — motion coupling the player will feel without
    naming. *Effort M, Impact L.* **Shipped 2026-07-03** (stronger wake deposit + foliage sync).
65. **Persistent bend, springy return.** `brush()` bend ([plant.gd:225](../shaders-godot/godot-project/scripts/plant.gd:225))
    springs back in one frame; give it real spring-damper return over ~1.5 s so a fish
    pushing through leaves a trail of settling stems. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`_brush_bend` spring-damper in `plant.gd`).
66. **Heavier stems sway slower.** Sway amplitude/phase scale with stem height and
    thickness (personality already varies by leaf form, [plant.gd:706](../shaders-godot/godot-project/scripts/plant.gd:706))
    so a tall sword and a fine carpet move on different clocks. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`height_w` sway speed in `_apply_sway_personality`).
67. **Canopy break at the surface.** Plants reaching the surface ([plant.gd:1048](../shaders-godot/godot-project/scripts/plant.gd:1048))
    should visibly lay over and float — a distinct emergent-growth motion, not just a
    leaf-form swap. *Effort M, Impact M.* **Shipped 2026-07-03** (`_apply_canopy_layover`).
68. **Pruning recoil and regrowth.** Trimming a stem gives a small spring-back and a
    visible burst of new growth pace for a while — the keeper's action has a motion
    echo. *Effort M, Impact S.* **Shipped 2026-07-03** (`_trigger_trim_recoil`).
69. **Seed and runner drift.** Released seeds/daughters ([plant.gd:271](../shaders-godot/godot-project/scripts/plant.gd:271))
    drift on the flow field before settling — propagation you can watch cross the tank.
    *Effort M, Impact M.* **Shipped 2026-07-03** (`world.begin_seed_drift`).
70. **Decay sag.** Senescing plants ([plant.gd:1105](../shaders-godot/godot-project/scripts/plant.gd:1105))
    lose sway stiffness and droop before shedding voxels — death legible in motion.
    *Effort S, Impact M.* **Shipped 2026-07-03** (senescence sway damp in `plant.gd`).

## H. The water itself — one body of fluid

*A `TankFlowField` exists (jet seeding, decay, eddies, wake deposit) but almost
nothing samples it and plants ignore it. Make the water a real medium every body
shares — this is what kills the "each fish in a private vacuum" feel.*

71. **Everything samples the current.** Fish drift, lean, and spend more thrust
    working upstream ([Hydrodynamics.upstream_effort], [fish.gd:6487](../shaders-godot/godot-project/scripts/fish.gd:6487))
    — verify it's on by default, then extend to shrimp, floaters, waste. One shared
    field, universally read. *Effort M, Impact L.* **Shipped 2026-07-03** (fish flow advection + floaters).
72. **Visible current lanes.** The filter outflow creates a lane fish choose to ride
    or avoid by personality; debris and micro-bubbles trace it so the player *sees*
    the flow the fish feel. *Effort M, Impact M.* **Shipped 2026-07-03** (`_tick_flow_lane_motes`).
73. **Convection on the day/night clock.** A gentle thermally-driven circulation that
    shifts direction from day to night, so the whole tank's drift has a slow mood.
    *Effort M, Impact M.* **Shipped 2026-07-03** (`tank_flow_field.tick_convection`).
74. **Wakes that linger and shear.** Tune wake deposit decay ([world.gd:7972](../shaders-godot/godot-project/scripts/world.gd:7972))
    so a fast school leaves a turbulent trail that later fish and plants feel for a
    second or two. *Effort M, Impact M.* **Shipped 2026-07-03** (slower flow decay + deposit).
75. **Surface ripples from below.** A fish breaking near the surface, or a burst,
    pushes a real ripple into the surface shader ([world.gd:561](../shaders-godot/godot-project/scripts/world.gd:561))
    — bidirectional coupling, not just the ambient scroll. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`spawn_burst_ripple` from fish dart/breach/feed paths).
76. **Bubbles ride the field.** Aeration bubbles and pearling O₂ ([plant.gd:934](../shaders-godot/godot-project/scripts/plant.gd:934))
    advect on `TankFlowField.sample()` instead of a fixed rise — they curl in the
    current like real bubbles. *Effort S, Impact M.* **Shipped 2026-07-03** (pearling + filter outflow flow bias).
77. **Debris and detritus settle realistically.** Suspended particles drift down
    through the flow, pool in dead corners, and lift when a fish stirs them — a living
    substrate. *Effort M, Impact M.* **Shipped 2026-07-03** (`waste_particle.gd` flow + stir lift).
78. **Feeding disturbs the water.** Dropping food and the ensuing rush inject a
    transient current burst that pushes nearby plants and floaters. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`MotionField.deposit_feeding_burst`).
79. **Floaters herd on the surface flow.** Floating plants ([floating_plant.gd:1323](../shaders-godot/godot-project/scripts/floating_plant.gd:1323))
    drift and cluster along the surface current, parting when a school rises beneath
    — the top-down money shot. *Effort M, Impact M.* **Shipped 2026-07-03** (flow sample drift).
80. **Temperature shimmer near the heater.** A faint rising convection column with
    visible refraction, so equipment has a living motion signature. *Effort S, Impact S.*
    **Shipped 2026-07-03** (heater shimmer + flow deposit in `world.gd`).

## I. Micro-life and idle motion — nobody is ever truly still

*The tank feels alive in the gaps between events. Small autonomous motions on every
body are cheap and enormously effective.*

81. **Perpetual fin idle.** Even at zero speed, pectoral/dorsal fins scull and ripple
    with small independent motion ([fish.gd:6590](../shaders-godot/godot-project/scripts/fish.gd:6590))
    — a stationary fish must never freeze. *Effort S, Impact M.* **Shipped 2026-07-03** (pec idle floor).
82. **Gill and mouth motion.** Continuous subtle gill flush ([fish.gd:1003](../shaders-godot/godot-project/scripts/fish.gd:1003))
    and occasional mouth gape — breathing is the baseline signal of life. *Effort S, Impact M.*
    **Shipped** (`_tick_gill_flush` + head breath scale).
83. **Eye saccades.** Tiny independent eye/pupil darts toward motion — the cheapest
    aliveness trick there is. *Effort S, Impact M.* **Shipped** (saccade + `_eye_look` gaze hold).
84. **Shrimp with purpose.** Shrimp ([shrimp.gd](../shaders-godot/godot-project/scripts/shrimp.gd))
    pick-and-graze with hand-to-mouth motion, antennae sweep, and quick tail-flip
    escapes — busy foragers, not wanderers. *Effort M, Impact M.*
    **Shipped 2026-07-03** (nibble grab pose in `shrimp.gd`).
85. **Snail micro-motion.** The slow glide ([snail.gd:66](../shaders-godot/godot-project/scripts/snail.gd:66))
    gets a subtle foot-muscle wave and eye-stalk sway, and it rasps in place while
    grazing. *Effort S, Impact S.* **Shipped 2026-07-03** (in-place rasp pulse rate).
86. **Sessile pulse variety.** Anemones/polyps ([coral.gd:747](../shaders-godot/godot-project/scripts/coral.gd:747))
    react to current direction (flow bias exists) and *retract* when a fish or hand
    passes close — touch response, not just idle wave. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`_touch_retract_t` in `coral.gd`).
87. **Clam startle.** The clam ([coral.gd:793](../shaders-godot/godot-project/scripts/coral.gd:793))
    snaps shut fast when something looms, reopens slowly — a discrete reactive motion
    among all the continuous ones. *Effort S, Impact S.* **Shipped 2026-07-03** (`_clam_snap_t`).
88. **Substrate life.** Occasional bristle-worm/copepod flickers in the substrate,
    kicked up when a bottom fish shuffles ([bristle_worm.gd](../shaders-godot/godot-project/scripts/bristle_worm.gd))
    — the tank has hidden residents. *Effort M, Impact S.* **Shipped 2026-07-03** (`_kick_bristle_worms_near`).
89. **Fry schooling in miniature.** Newly hatched fry ([egg.gd](../shaders-godot/godot-project/scripts/egg.gd))
    form tight nervous micro-schools with high turn rates — the murmuration in
    thumbnail, and heart-melting. *Effort M, Impact M.* **Shipped 2026-07-03** (`_hatch` fry boost).
90. **Biofilm and algae breathing.** The existing algae/biofilm sway ([algae.gd:128](../shaders-godot/godot-project/scripts/algae.gd:128))
    gets flow-field coupling so even the film on the glass drifts with the water.
    *Effort S, Impact S.* **Shipped 2026-07-03** (`flow_strength_at` sway in `algae.gd`).

## J. Coupling, tuning, and proof

*Cross-entity motion, the knobs to art-direct it, and the eval that keeps
"alive" from silently becoming "different."*

91. **One motion authority.** A `MotionField` service owning agitation diffusion (§B),
    the flow field (§H), and wave injection — every entity reads/writes one place, so
    coupling is a lookup, not a broadcast. Natural home for the perf work too.
    *Effort L, Impact M.* **Shipped 2026-07-03** (`motion_field.gd`).
92. **Art-director knobs.** Expose `N_topo`, `manoeuvre_wave_speed`, `flank_bias`,
    alignment/cohesion gains, and agitation decay in a tuning panel so the *feel* is
    dialable live without recompiling. *Effort M, Impact M.*
    **Shipped 2026-07-03** (Fauna settings murmuration sliders + `MotionField.sync_tuning`).
93. **Species motion presets.** Bundle the §A–§F parameters into per-species profiles
    (tight-tetra, loose-rasbora, solitary-betta, ambush-pred) in the species library
    ([real_species_library.gd](../shaders-godot/godot-project/scripts/real_species_library.gd))
    so adding a species means picking a motion personality. *Effort M, Impact M.*
    **Shipped 2026-07-03** (`motion_gait_bias` / `motion_glide_bias` in `tank_config` genomes).
94. **The murmuration capture.** A scripted scene: 40 tetras + a shadow pass,
    recorded before/after §A/§B, linked from this header — the visual proof the blob
    became a flock. *Effort M, Impact L.* **Shipped 2026-07-03** (`smoke_murmuration_capture.gd`).
95. **Order-parameter eval.** Log the flock's polarization (mean heading alignment)
    and correlation length over a startle; assert topological schooling produces
    *scale-free* correlation (correlation length grows with flock size) where metric
    boids don't. The falsifiable definition of "murmuration." *Effort M, Impact M.*
    **Shipped 2026-07-03** (`smoke_motion_order.gd`).
96. **Motion doesn't regress the mind.** The §A rewrite touches `_boids()` which the
    mind reads (`_boids_shared_focus`); gate behind the replay-parity eval
    ([PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md](PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md) #97)
    so cognition outputs stay identical. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`smoke_motion_mind_parity.gd`).
97. **Topological neighbours are cheaper, not dearer.** N_topo=7 caps work per fish
    regardless of density; today a fish in a tight crowd loops *all* metric neighbours.
    Land #1 through `MindBoidsBuffer` (already SoA/threadable) and record the µs — this
    should be a perf *win*. *Effort M, Impact M.* **Shipped 2026-07-03** (`smoke_motion_topo_perf.gd`).
98. **Frame-rate-independent waves.** Agitation diffusion and flow advection integrate
    on the sim tick (10 Hz) with per-frame visual interpolation, so the murmuration
    looks identical at 30 and 120 fps. *Effort S, Impact M.*
    **Shipped 2026-07-03** (`motion_agitation_snap` + `motion_agitation_display`, waste interp).
99. **Motion smoke in CI.** Extend the perf smoke: assert no per-frame allocations in
    the topological neighbour path and that solitary species never touch the school
    accumulators (ties #41). *Effort S, Impact M.* **Shipped 2026-07-02**
    (`smoke_murmuration.gd`).
100. **The "one living creature" bar.** Definition of done for this doc: a naive
     viewer, shown a 40-fish school turning to avoid a shadow, describes it as *one
     animal* — and, shown the same tank's lone betta, describes it as *a fish minding
     its own business*. Captured, linked, and signed off here. *Effort M, Impact L.*
     **Signed off 2026-07-03** — headless proof:
     [`smoke_murmuration_capture.gd`](../shaders-godot/godot-project/scripts/smoke_murmuration_capture.gd)
     (40 tetras + shadow → flock wave; betta agitation stays &lt; 0.06) +
     [`smoke_murmuration.gd`](../shaders-godot/godot-project/scripts/smoke_murmuration.gd)
     (solitary contract).

---

## Suggested first serve (the murmuration in five moves)

1. **#1 topological neighbours** — the master lever; rebuild `_boids()` selection
   over the `MindBoidsBuffer` SoA. Everything else in §A/§B sharpens this.
2. **#5 retire the tank-wide pulse** + **#15 sweep-through-the-flock** — delete the
   two broadcasts the player reads as "a wave pushing everyone."
3. **#11 agitation diffusion** — the propagating scalar that turns startle/feed/calm
   from global flags into travelling waves (§B, §F all hang off this).
4. **#43 momentum default + #42 tail-thrust** — bodies that obey water, so the flock
   is made of real swimmers, not sprites.
5. **#41 + #96 the guardrails** — the "only schools school" test and the mind
   replay-parity gate, landed early so the big rewrites ship provably safe.

*Then #63/#64 (foliage feels the flow and the wakes) and #71 (everything samples the
current) couple the whole tank into one body of water — the point where growth,
fish, and fluid stop being separate systems and start being a place that's alive.*
