# Motion budget ledger

*Drafted 2026-10-30 for [CREATURE_MOTION_700.md](CREATURE_MOTION_700.md) #79.
Targets come from the backlog (#693) or are marked as proposals. Measured
numbers come from
[CROWDED_FISH_PERFORMANCE_20261008.md](archive/passes/CROWDED_FISH_PERFORMANCE_20261008.md)
and
[RENDER_SCHOOLING_PERFORMANCE_20261009.md](archive/passes/RENDER_SCHOOLING_PERFORMANCE_20261009.md)
(Apple M2 Ultra, Godot 4.6.2). Code anchors are from `5ad6dd3`.*

Every motion item in the backlog has to fit in a frame that is already
expensive: the 197-fish rendered stress tank runs at about 3 FPS. This ledger
says how much CPU each creature's motion may spend per frame at each level of
detail, which features run at each tier, and how many draw calls each creature
may cost. It keeps **targets** and **measurements** in separate columns. No
per-tier motion cost has been measured yet.

## What is being budgeted

| Term | Means | Excludes |
|---|---|---|
| **Motion CPU** | Time per rendered frame in a creature's pose and secondary-motion code: for a fish, the pose pass at the end of `_motion_substep` (bank, tail, fins, head, breath, display) and, later, springs, chains, gaze and envelopes | Steering and locomotion integration, the 10 Hz sim tick, cognition |
| **Integration CPU** | The locomotion substeps (steer, thrust, drag, move). Reported separately; the physics LOD (#697) budgets it | Pose |
| **Sync** | Uploading moved voxel transforms to the GPU (`FaunaSpeciesBatch`, `VoxelBatch`) | GPU shading |
| **Draw calls** | Draw submissions the creature adds to a frame | — |

## The tiers

| Tier | Who | Features that run (target) |
|---|---|---|
| **Hero** | The followed or selected creature, whatever its distance | Everything: spine chain, fin and veil springs, eyes and gaze, jaw and opercula, breath, envelopes, shader ripple |
| **Near** | Visible and close to the camera | Spine, fin springs, gaze, breath, envelopes, shader ripple. No face (eyes, jaw, opercula) |
| **Far** | Visible and distant | Clock, analytic wave, envelopes for key actions only, shader ripple. Chains and gaze become per-voxel phase delays in the shader (#252, #694) |
| **Offscreen** | Outside the frustum | The clock and the trajectory only. No pose writes. Must seed a fresh pose on re-entry (#273) |

**In `5ad6dd3` there is no tiering beyond the frustum.** A fish outside the
frustum skips the whole pose pass (`do_body_anim`,
[fish.gd:7684](../shaders-godot/godot-project/scripts/fish.gd:7684); the test
is the fish's origin point, `is_creature_visible_to_camera`,
[sim_driver.gd:3251](../shaders-godot/godot-project/scripts/sim_driver.gd:3251)),
and shrimp do the same. Every visible fish runs the full pose pass. Off-frustum
fish brains run every other sim tick. The tier names above match the
`MotionLod` helper being written in the working tree at the time of writing
(uncommitted; it proposes `NEAR_MAX` = 9 u). Until that lands, "hero" and
"near" are design categories, not code.

## The ledger

**µs** are CPU microseconds per creature per rendered frame on the reference
machine (Apple M2 Ultra). Scale them for slower hardware by the ratio of the
perf-contract fixture times.

### Motion CPU, µs per creature per frame

| Creature | Hero | Near | Far | Offscreen | Source of the target | Measured |
|---|---|---|---|---|---|---|
| Fish | **15** | **4** | **1** | ≤ 0.5 *(proposed)* | #693 (hero, near, far) | Not measured per tier. See the measured facts below |
| Shrimp | 15 | 4 | 1 | ≤ 0.5 | *Proposed:* as many channels as a fish once five two-segment leg pairs and antenna chains land (#512, #513, #242) | Not measured |
| Crab, lobster, mantis | 15 | 4 | 1 | ≤ 0.5 | *Proposed:* same rig as shrimp | Not measured |
| Glass snail | 8 | 2 | 0.5 | ≤ 0.2 | *Proposed:* foot, shell spring, two tentacles, stalks, pedal band | Not measured |
| Trumpet snail, worm, cucumber (each) | 3 | 1 | 0.3 | 0 | *Proposed:* a short chain each | Not measured |
| Tubifex patch (whole patch) | 5 | 2 | 0.5 | 0 | *Proposed* | Not measured |
| Clam, coral, anemone, hydra (each) | 5 | 1 | 0.3 | 0 | *Proposed;* these already animate every second frame (`ANIM_STEP`, [coral.gd:744](../shaders-godot/godot-project/scripts/coral.gd:744)) | Not measured |
| Microfauna (whole swarm, up to 320) | — | 300 total | 300 total | 0 | *Proposed:* about 1 µs per plankton, mostly in the shader (#647) | Not measured |
| Eggs (each) | 0.5 | 0.2 | 0.1 | 0 | *Proposed* | Not measured |

### Draw calls per creature

| Creature | Today (`5ad6dd3`) | Target | Notes |
|---|---|---|---|
| Fish, 36 or more fish in the tank | One MultiMesh draw per species batch, shared by every fish of that species (`MIN_FISH_FOR_BATCH`, [fauna_species_batch.gd:41](../shaders-godot/godot-project/scripts/fauna_species_batch.gd:41)) | Unchanged | Extra spine joints add bone syncs, not draws; #698 moves the bend into the shader |
| Fish, fewer than 36 | One MultiMesh per voxel-bearing pivot: up to 8 per fish (Head, BodyMid, TailPivot, DorsalPivot, Dorsal2, AnalPivot, PecRight, PecLeft) | Unchanged | `FaunaVoxelBuilder` keys its batches by pivot ([fauna_voxel_builder.gd:66](../shaders-godot/godot-project/scripts/fauna_voxel_builder.gd:66)) |
| Shrimp, crab, lobster, mantis | One `VoxelBatch` per voxel-bearing pivot (legs, antenna segments, tail, body) | Unchanged until measured | — |
| Glass snail, clam, worm, cucumber, trumpet snail | One `MeshInstance3D` per voxel (for example `_shell_voxels`, [snail.gd:924](../shaders-godot/godot-project/scripts/snail.gd:924)) | One per moving part (#699) | The largest draw-call saving available among invertebrates |
| Coral, anemone, hydra | Body voxels in one MultiMesh; animated parts as separate meshes | Unchanged | — |
| Microfauna | Three MultiMesh draws for the whole swarm | Unchanged | — |

### Frame-level gates

| Gate | Target | Status |
|---|---|---|
| 150-fish rendered scenario (#695) | No slower than the Phase 0 baseline | **Baseline not recorded yet.** Record it from `5ad6dd3` before any Phase 2 item merges |
| `smoke_perf_contract.gd` | 150-fish sim tick under 490 ms, and under 4.5× the 50-fish tick | In place (it measures the sim tick, not motion) |
| Topological boids (`smoke_motion_topo_perf.gd`) | Under 900 µs per fish per sim tick | In place (steering, not pose) |
| Motion lines in the perf contract (#700) | Per-tier motion µs against this ledger | Not built |

## Measured facts

| What | Number | Source | Caveat |
|---|---|---|---|
| Fish `_process` cost in the 197-fish rendered tank | Frame 360.37 ms median and 363.13 ms mean with all fish processing, 332.98 ms with every fish's `_process` off: about 27–30 ms, or **140–150 µs per fish per frame** (*derived*) | Crowded-fish pass, the intermediate run's split diagnostic (fish `_process` off, as `FISH_PROBE_SPLIT` does) | Includes integration, pose and colour together. At about 3 FPS each fish runs several integration substeps per frame (4–12 by the `n_steps` formula, [fish.gd:6936](../shaders-godot/godot-project/scripts/fish.gd:6936), *computed*), so this overstates a healthy 60 fps frame. The split phase follows the sampling phase in the same run, but it is not a paired benchmark |
| Voxel sync | 400 bones and 9,600 voxels: **9.614 ms median**, 10.042 ms p95 (14.535 ms before the October 9 pass). About 24 µs per bone, or 1.0 µs per voxel (*derived*) | Render-and-schooling pass, `dev/fauna_sync_cost_probe.gd` | Dummy renderer: script and API cost only. The probe doesn't separate per-bone from per-voxel cost |
| Rendering with the simulation off, 197 fish | 114.26 ms (Oct 8); 117.63 and 124.78 ms (Oct 9) | Both passes | Rendering and sync dominate even with no simulation |
| Whole frame, 197 fish | 331.83 ms median, 357.95 ms p95 (Oct 8 follow-up); 354.36 ms mean (Oct 9) | Both passes | Deliberately overloaded, very low oxygen; short, evolving samples |
| Sim tick, headless | 34.2 / 142.1 / 354.4 ms median at 50 / 150 / 300 fish (Oct 8 final) | Crowded-fish pass, `dev/crowded_cpu_probe.gd` | Sim tick, not per frame; cognition dominates |

**What the numbers say.** Pose math is not where the frame goes. At the
targets, 150 near-tier fish cost 150 × 4 µs = 0.6 ms, 4% of a 60 fps frame
(16.7 ms) and 2% of a 30 fps one. Sync, at about 1 µs per moving voxel, already
costs more per fish than the hero motion budget, and rendering costs more than
both. The budget therefore has two jobs:

1. Keep new motion code inside its per-tier µs, so that a hundred fish of
   springs and chains don't add up to the frame.
2. Stop new motion from increasing **sync**: no new moving voxels per fish
   without removing others, and bending for batched fish in the shader
   (#694, #698) rather than through new bones.

## Measuring it

Nothing in the ledger's "Measured" columns can be filled from existing probes.
To fill them:

1. Time the pose pass on its own: `Time.get_ticks_usec()` around the pose
   section of `_motion_substep`, behind a debug flag, accumulated per tier.
2. Use a fixture that runs at 60 fps or better, so each fish takes one substep.
   The overloaded 197-fish tank inflates the numbers.
3. Run through `scripts/dev_run.sh`, as the existing probes do.
4. Report the median and p95 per tier, and per species where they differ.
5. Record the result in this file with the date, commit and machine.

## Wiring it into the gates (not done)

#79 asks for the perf contract to read this ledger. That needs:

- the target table above as data the contract can load (for example a file
  under `data/motion/`), so there is one source of truth;
- a motion timing hook (#112) that reports per-creature µs per tier;
- a check in `smoke_perf_contract.gd`, or a new serial perf smoke, that fails
  when a tier's p95 exceeds 1.5× its target on the reference fixture;
- the dev overlay colouring each creature against its tier budget (#112).

Until then this page is the ledger, and each motion PR's description states
its measured cost against it ([../CONTRIBUTING.md](../CONTRIBUTING.md#motion-changes)).
