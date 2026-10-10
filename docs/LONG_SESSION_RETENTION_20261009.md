# Long-session retention and aging — 9 October 2026

An aging tank has two different costs: more living organisms/geometry to simulate,
and bookkeeping left behind by departed organisms. This pass fixes demonstrated
retention without reducing fish learning, breeding, animation detail or sensory
range. It does not establish that every long-session slowdown is a memory leak.

## What was retained

- Shared fauna batches hid departed voxels but appended every replacement to new
  slots. CPU transform/color/custom arrays and GPU capacity followed lifetime
  births instead of the peak live population. Render sync groups were removed,
  so looking only at the group count missed the accumulating hidden geometry.
- Learned-mind clocks, boundary/prompt/lexicon caches and dirty-save entries had
  no common fish lifetime cleanup. Completed cognition results could remain
  forever if their fish departed before consuming them.
- Narrator operation memoization had no size bound. Its pending jobs could retain
  departed fish references or publish late results into a reloaded tank.
- The fauna material update registry strongly owned its first 320 materials.
  Those dead materials remained alive, while newer living materials beyond the
  cap missed water-light/fixture/rim updates. The palette-write cache also kept
  global entries for material identities after those materials were gone.
- Fish, shrimp and snail reproduction created an unparented species-library Node
  for every lineage calculation and never freed it. Pure static key helpers now
  calculate the same lineage without allocating a Node.
- Floating-plant prototype trees had no explicit eviction policy. They now have
  a 64-entry recency cache that frees evicted trees and clears at SceneTree
  shutdown. Rebuilds detach retiring children before queuing deletion, preventing
  same-frame rebuilds from cloning old geometry into the next prototype.
- A plant removed between distance-bucket ticks could leave an unconsumed clock
  behind. Live and save-loaded plants now wire clock cleanup on tree exit.

## Changes

Fauna batches opt into reuse of permanently retired slots. An old handle is
explicitly detached before its index is reused, and the replacement resets its
custom attributes. Temporary visibility changes do not retire a slot. Deferred
plant uploads retain append-only reservation and atomic admission. Shared fauna
also perform coarse, owner-specific compaction after sustained sparse usage;
untracked static geometry is excluded from handle-based compaction.

`Fish._exit_tree()` releases transient bookkeeping through `MindCacheRegistry`.
Cognition jobs/results carry the originating Node instance identity as well as
its persistent save id. Worker publication and main-thread application reject
old lifetimes; cancellation never blocks the frame waiting for a running brain.
A late departed worker cannot recreate its dirty-save entries.

Narrator operations use a 512-entry bounded cache with recency refresh on hits.
Departure removes queued/pending work. Cancelled workers keep only the task id
needed for joining; their fish/context references are released immediately.
Model requests have unique request identifiers so an old reply cannot hijack a
new request for the same saved fish and situation. Reset joins outstanding
narrator workers before clearing their result stores.

The fauna material registry uses weak references and prunes stale entries. All
living registered materials receive updates, including populations beyond the
old cap. Palette memoization now lives on each material, so it shares that
material's lifetime; explicit overlay changes invalidate it.

Plant buffer compaction checks run roughly once per simulation second, or at the
existing five-second shrink deadline, instead of scanning every handle at 10 Hz.
The live population and deferred-write checks still precede compaction.

## Fish already forget

Episodic memory is capped at **64 episodes per fish**. Weak episodes decay below
the forgetting threshold; rehearsal strengthens recalled memories, keeper-word
memories decay more slowly, and sleep distills recurring experience into bounded
semantic facts and spatial schemas. This pass keeps those mechanisms and limits.
Removing dead bookkeeping is different from erasing a living fish's learning.
Tank transfers preserve episodes and felt-state continuity. A re-entering fish
requests a complete mind in its next delta save, so clearing transient dirty
flags cannot omit its learning from the destination tank.

## Measurements

Apple M2 Ultra, Godot 4.6.2. All probes used `scripts/dev_run.sh` and reported an
unchanged real tank inventory. These are controlled CPU/static-memory probes,
not process RSS, GPU-memory readings or interactive frame-rate guarantees.

The churn probe creates 24 generations of 12 actual Fish, queues real threaded
cognition, consumes none of the completed results, registers 24 shared probe
voxels per fish, then removes every fish and synchronizes the renderer.

| After all 288 lifetimes | Before | After |
|---|---:|---:|
| Shared voxel slots, with zero live probe fish | 6,912 | 288 |
| GPU instance capacity | 8,192 | 512 |
| Departed entries in each measured clock/prompt/dirty/result store | 288 | 0 |
| Static memory growth from generation 4 through 23 | 15.436 MB | 0.041 MB |

The slot peak is retained for immediate reuse until the sparse-buffer hold
expires. A separate regression test verifies that coarse maintenance then
releases empty arrays and shrinks GPU capacity to the 64-instance floor.

For a fixed, fully living 5,000-voxel buffer, median compaction bookkeeping fell
from **839.436 µs** to **79.068 µs per 0.1-second tick**, about **91% less CPU**.
This measures maintenance only, with seven repetitions of 500 calls. It leaves
rendering, animation and biological growth intact.

The accelerated beginner-habitat aging probe runs 120 simulated seconds and
yields every ten ticks. Before changes, fish grew from 47 to 60, shrimp from 20
to 33, plants to 150, and scene nodes from 3,256 at the ten-second sample to
4,641 at the end. Episodic totals reached 3,840, exactly 60 × 64. Median tick time
rose from 59.514 ms in the first sample window to 112.728 ms in the last.
That run demonstrates both increasing living workload and capped memory; it
cannot isolate the cause of all interactive slowdown. The follow-up probe
records per-stage times for further diagnosis. Its final sample contained 64
fish, 30 shrimp and 140 plants; median tick time was 94.670 ms, with the fish
stage averaging 71.654 ms. Fish simulation remains the largest measured cost. Wall-clock throttles, asynchronous
cognition, plant growth and breeding produce different trajectories between
runs, so their total tick times are not a deterministic before/after benchmark.

## Validation

- `smoke_session_retention.gd`: **248 assertions** covering repeated lifetimes,
  completed/in-flight cancellation, same-id reloads, unique narrator requests,
  bounded memoization and preservation of transferred memories.
- `smoke_retired_voxel_slots.gd`: **38 headless / 41 Metal assertions** covering
  churn, stale handles, temporary hiding, deferred admission, shrinking and
  untracked static geometry. Metal checks actual transform/color/custom readback.
- `smoke_render_material_lifetime.gd`: **775 assertions**, including 384 living
  fauna materials, collection of unused materials and palette invalidation.
- `smoke_breeding_retention.gd`: **82 assertions** covering 32 actual fish/shrimp
  offspring calculations, unchanged canonical parent keys, zero detached-Node
  growth, same-frame floater rebuilding, cache eviction and living geometry.
- Existing plant registry coverage now checks removal of pending bucket clocks.
- Final compile check: **603 scripts, zero failures and zero analyzer warnings**.
- **257/257 isolated strict smoke suites passed** in 140 seconds, with no
  regressions, known failures or timeouts. The final transfer-save safeguard was
  also checked in a targeted rerun of the session-retention suite.

Probe receipts live in ignored `output/retention_followup/`:
`churn_before.json`, `churn_after.json`, `compaction_before.json`,
`compaction_after.json`, `aging_before.json` and `aging_after.json`.
The final ten-second World diagnostic no longer reports the detached
species-library Nodes, leaked mesh instances, ObjectDB objects or retained
resources at shutdown. It still reports one dummy-renderer shader RID at exit,
so this is not a claim that all teardown diagnostics have been eliminated. The
120-second aging receipt predates the final breeding/prototype fixes; it retains
its earlier shutdown diagnostics for comparison.

Reproduce:

```bash
RETENTION_PROBE_OUT="$PWD/output/retention_churn.json" \
  ./scripts/dev_run.sh --headless --script res://dev/retention_churn_probe.gd
COMPACTION_PROBE_OUT="$PWD/output/compaction_cost.json" \
  ./scripts/dev_run.sh --headless --script res://dev/compaction_cost_probe.gd
AGING_PROBE_SECONDS=120 AGING_PROBE_OUT="$PWD/output/aging_cost.json" \
  ./scripts/dev_run.sh --headless --script res://dev/aging_cost_probe.gd
./scripts/run_smokes.sh --strict
./scripts/check_warnings.sh
```
