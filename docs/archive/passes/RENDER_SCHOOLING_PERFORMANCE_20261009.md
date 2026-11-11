# Rendering and schooling performance — 9 October 2026

This follow-up removes repeated work while keeping voxel detail, full per-frame
poses, sensory range, cognition cadence and the existing schooling decisions.

## Changed

- `VoxelBatch` mutations already upload their changed instance. Normal `flush()`
  now commits visibility and culling only, instead of uploading every transform,
  pigment and custom field again. Fauna and hardscape callers no longer request
  a second full upload afterward. The explicit repair/benchmark `blit_buffer()`
  path remains available, including its stable per-instance Metal fallback.
- Exact unchanged transform/color/custom writes are skipped. There is no motion
  quantization, approximate color threshold or lower animation update rate.
- Shared fauna cache each bone's local box union when its voxels are created.
  Each rendered pose transforms those conservative boxes and merges them per
  species batch. This replaces repeated per-voxel culling calculations. The
  existing shader-sway margin remains. Static untracked instances and invalid
  group poses retain the exact per-voxel fallback.
- Topological schooling retains the worst selected slot as candidates arrive.
  Most distant candidates need one comparison instead of seven. Candidates
  already guaranteed to be rejected skip view-cone normalization. Packed tick
  inputs are read locally; partner preference, range, species separation,
  vertical bands, ordering, ties and float32 distance storage remain unchanged.
- The behavior probe explicitly releases its scene before quitting. It still
  emits pre-existing renderer/resource shutdown diagnostics; this is not a
  claim of leak-free World teardown.

## Measurements

Apple M2 Ultra, Godot 4.6.2. All game runs used `scripts/dev_run.sh`; every run
reported an unchanged real tank inventory. Timings below are CPU milliseconds,
not a promise about frame rate on another device.

The fixed moving-fauna workload uses 400 bones and 9,600 voxels, with eight
warm-up poses and twelve measured full poses. Before: **14.535 ms median**,
**14.982 ms p95**. The initial optimized run: **9.396 ms median**, **10.663 ms
p95**. The final guarded implementation measured **9.614 ms median**,
**10.042 ms p95**, about **34% less synchronization time** than before.
It uses the dummy renderer, so it isolates script/instance API overhead rather
than GPU shading or fence cost.

The crowded CPU probe uses real Fish and SimDriver at 50/150/300 fish, fixed
seed, twelve warm-up ticks and twelve measured ticks, asynchronous cognition.
At 300 fish the mean schooling-neighbor stage fell from **38.638 ms** to
**21.031 ms**, about **46% less work**. Total median tick time varied from
**335.762 ms before** to **312.170 ms** on the first optimized run and
**335.323 ms** on the final run. Cognition scheduling and worker contention
still dominate; these measurements do not establish a consistent overall
simulation speedup.

The real rendered beginner tank topped up with 150 guppies contains 197 fish.
Before/initial-after mean frames were **364.92 / 354.36 ms** (about 3% lower),
with p95 **393.17 / 384.05 ms**. This is deliberately severe crowding and reaches
very low dissolved oxygen, rather than representing a healthy starter habitat.
Different frame timing also changes the resulting motion/physiology sample;
use the deterministic force fixture for behavioral equivalence. With simulation
processing disabled, rendering still took **117.63 / 124.78 ms** in the two
samples. It remains expensive and noisy; reduced upload work alone does not
make this stress scene fast.

## Regression coverage

- `smoke_schooling_force_equivalence.gd`: **13,476 assertions** comparing
  all separation/alignment/cohesion vectors, neighbor counts, integer speeds and
  seven ordered neighbor slots against captured pre-optimization outputs at
  16/64/128/256 fish. An independent linear selector checks repeated ties,
  sub-float32 distances and partner-weighted distances at every insertion.
- `smoke_voxel_commit.gd`: growth beyond initial capacity, non-symmetric poses,
  color/custom changes, hide/restore, atomic deferred admission, compaction and
  clearing. **37 assertions on the actual Metal renderer**; headless runs check
  CPU mirrors and admission because the dummy renderer cannot retain GPU data.
- Extended fauna lifecycle coverage checks all eight transformed box corners
  inside the culling bounds, including rotations, non-uniform scaling, newly
  added voxels, dead siblings and untracked static instances.

**Final validation:** all **253/253 isolated smoke suites passed** in 145
seconds, with zero regressions, known failures or timeouts. All **596 scripts
compile with zero GDScript warnings**. The actual Metal commit test passed its
37 assertions; the extended fauna lifecycle suite passed 50 assertions.

Receipts are in ignored `output/performance_followup/`: `cpu_before.json`,
`cpu_after.json`, `cpu_final.json`, `sync_before.json`, `sync_after.json`,
`sync_final.json`, `rendered_before.txt`, `rendered_after.txt` and the Iwagumi
visual capture. The final Iwagumi photo was inspected: moving fish and their
fin geometry remain present, with no visible culling gaps in that view.

Reproduce:

```bash
FAUNA_SYNC_PROBE_OUT=/tmp/fauna_sync.json \
  ./scripts/dev_run.sh --headless --script res://dev/fauna_sync_cost_probe.gd
SIM_PROFILE=1 CROWDED_PROBE_OUT=/tmp/crowded.json \
  ./scripts/dev_run.sh --headless --script res://dev/crowded_cpu_probe.gd
./scripts/dev_run.sh --script res://scripts/smoke_voxel_commit.gd
./scripts/run_smokes.sh --strict
./scripts/check_warnings.sh
```
