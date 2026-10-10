# Crowded fish performance — 8 October 2026

This pass removes repeated work while retaining each fish's geometry, movement
integration, social radius and cognitive systems. It does not make crowded tanks
cheap enough to promise smooth play at arbitrary population sizes.

## Changes

- Replace ordered all-pairs school merging with a 3D spatial grid. Candidate
  ordering and the strict merge radius remain the same. Skip merge searches when
  a species already has one school. Dying fish no longer merge with living fish.
- Keep connected school identities stable across ticks and remove expired school
  timers. Previously new IDs every tick prevented fission timers from accumulating
  and left old timer entries behind.
- Read neighbor signals directly on real fish, and calculate social distances
  without allocating string-keyed pair-cache entries and unused heading data.
- Resolve the preferred buddy once per fish in CPU topological schooling, and
  avoid allocating empty arrays for absent spatial buckets.
- Limit simulation catch-up across physics callbacks within a rendered frame,
  using measured tick cost. Discarded time advances neither ecology nor daylight.
  This reduces repeated overload work; it cannot make one expensive tick cheap.
  Under overload, simulation time can advance slower than wall time.
- Integrate locomotion in the same small steps, but compute the displayed fin and
  bank pose once per frame. Preserve turn-rate history between movement steps.
- Group shared fauna voxel uploads by moving bone. Calculate each bone's tank-local
  transform once, then apply each voxel's original local transform. Dead handles
  and deleted bones are reclaimed without leaving ghost geometry.

## CPU measurements

Apple M2 Ultra, Godot 4.6.2, headless real SimDriver and Fish fixtures. Fixed seed,
12 warmup ticks and 12 measured ticks per population; optional stage profiling
is enabled in both runs. These are simulation-tick durations, **not FPS**.

| Fish | Before median / p95 | After median / p95 | Median reduction |
| --- | --- | --- | --- |
| 50 | 42.712 / 46.502 ms | 39.203 / 44.882 ms | 8% |
| 150 | 173.610 / 201.829 ms | 152.048 / 184.835 ms | 12% |
| 300 | 481.638 / 508.916 ms | 379.112 / 412.049 ms | 21% |

At 300 fish, schooling-field work averaged 66.83 → 9.88 ms per tick;
neighbor construction averaged 53.03 → 35.48 ms. Social signals/contagion averaged
0.218 → 0.067 ms per fish. Cognition and social memory still dominate the rest.
Repeated development runs vary: the 150-fish median ranged from 142 to 162 ms,
and 300-fish median from 360 to 379 ms. These short deterministic fixtures support
the direction of improvement, not a universal percentage or frame-rate promise.

Reproduce with:

```sh
SIM_PROFILE=1 CROWDED_PROBE_OUT=/tmp/crowded_cpu.json \
  ./scripts/dev_run.sh --headless --script res://dev/crowded_cpu_probe.gd
```

## Rendered stress test

The beginner sandbox topped up to 150 guppies contains **197 total fish**, with
plants, other species, water, UI and audio running. The probe uses isolated user
data and checks the real tank inventory afterward.

Before the frame-budget and pose changes, mean frame time was 447.96 ms, median
375.24 ms and p95 628.00 ms. With those changes, an intermediate run measured
363.13 ms mean, 360.37 ms median and 392.69 ms p95. These runs have short sample
windows and evolving tank state; they are not an exact paired benchmark.

The intermediate split diagnostic measured 332.98 ms with fish animation off
and 120.80 ms with simulation off. Both CPU simulation and rendering need further
work. Do not interpret the CPU fixture improvement as crowded tanks reaching
60 FPS.

With grouped bone uploads, the final stress run measured 372.56 ms mean,
368.69 ms median and 392.22 ms p95 (38 measured frames). The simulation-off split
fell from 120.80 to 114.26 ms; the full-tank median improvement is within the
variation between these short runs. Grouping removes redundant lookups, but is
not a dramatic GPU improvement. This 197-fish overload scenario still runs at
roughly 2.7 FPS and remains unsuitable as a smooth-play target.

Receipts are in the ignored `output/crowded_perf/` directory: `before.json`,
`validated_cpu.json`, and `rendered_grouped_150.txt`. Every isolated run reported
an unchanged real tank inventory.

## Next architectural work

1. Split simulation work into bounded jobs so a full-population tick cannot stall
   one frame. Preserve event order and ecological clock consistency when doing so.
2. Reduce unnecessary mind-state copies while preserving snapshot isolation and
   worker-thread ownership. Cognitive detail should remain available for selected,
   named and guardian fish.
3. Move bone transforms into a GPU palette or consolidate voxel geometry per bone
   so shared rendering no longer writes a full transform per voxel per frame.
4. Compare equal tank populations over longer samples, including stable healthy
   tanks and overload cases. Track visual continuity and behavior alongside timing.

## Validation

- All **238** isolated regression smokes pass (145 seconds); no known failures,
  regressions or timeouts. Timing-sensitive tests ran serially.
- All **573** scripts compile with **zero GDScript warnings**.
- School regression: 195 checks cover ordered merge equivalence, strict-radius
  boundaries, stable identities, expired timers and dying-fish exclusion.
- Swimming regression compares substepped movement, speed and motor phase with
  batched visual poses and checks finite transforms.
- Fauna lifecycle regression: 10 checks cover tank-local coordinates, continued
  animation after admission changes, distinct voxel transforms in a shared bone,
  partial handle removal, ghost cleanup and reopening tanks.
- Clock regression: 12 checks cover pause, frozen light, fast-forward and exhausted
  render budgets without daylight/ecology drift.
- Existing development probes still print renderer/resource cleanup warnings on
  exit. A passing timing probe does not establish leak-free shutdown.

## Follow-up: owned mind state and reusable learning contexts

A second pass targets mind helpers, without changing cognition frequency or
neighbor visibility:

- `MindSoul.ensure()` and `FishRelevance.ensure()` borrow the host's owned runtime
  dictionary. Previously each read deep-copied the entire state and replaced it.
  An outer caller could then overwrite nested habit learning with its older copy;
  relevance reads similarly orphaned held binding references. A regression test
  reproduced both failures before the fix.
- Save/load snapshots and worker-proxy capture still deep-copy their state. The
  new ownership test checks that mutations cannot cross these boundaries.
- MindState retains its independent collection snapshots, but reads typed Fish
  fields directly rather than testing and coercing every known field again.
- Neighbor conversation checks read the already-initialized state directly.
- Felt-self and active-inference helpers cache the TankConfig node identity;
  configuration values remain live, including same-frame changes. Worker paths
  still read their immutable worker configuration.
- Learned habits and action values use four repeating day contexts, rather than
  the exact floating-point day phase. Repetition can now build a learned habit.
  Both context tables are capped at 128 entries, including oversized old tables
  when they next receive a learning update. Oldest contexts are evicted first;
  the context being reinforced is retained. Legacy exact-clock entries gradually
  give way to the new reusable keys.

Fresh same-machine CPU baseline before this follow-up: 50 fish 43.552 ms,
150 fish 162.449 ms, 300 fish 403.558 ms median. Before the final autoload-cache
optimization, completed measurements were 37.145 / 141.815 / 357.812 ms: about
13–15% cheaper in that run. An earlier ownership-only run measured
38.685 / 136.899 / 334.832 ms, illustrating the variation between short runs.

The rendered 197-fish follow-up measured **331.83 ms median**, **357.95 ms p95**
and **334.58 ms mean**, compared with the previous grouped-renderer run's
368.69 / 392.22 / 372.56 ms. That is roughly a 10% improvement in this short,
evolving-tank sample, still only about 3 FPS in this overload scenario. No
user saves changed. The rendered follow-up predates the final autoload-cache
optimization; its result should not be attributed to that additional change.

Final CPU measurement including cached autoload identities:

| Fish | Before this follow-up median / p95 | Final median / p95 |
| --- | --- | --- |
| 50 | 43.552 / 46.700 ms | 34.151 / 38.830 ms |
| 150 | 162.449 / 164.239 ms | 142.077 / 156.911 ms |
| 300 | 403.558 / 427.526 ms | 354.393 / 370.312 ms |

This final run reduces crowded-fixture median tick cost by roughly 12–13%.
The final 300-fish median is about 26% below the original first-pass baseline;
that comparison spans several evolving fixes and short benchmark runs.
Receipts: `mind_before.json`, `mind_cached_final.json`, `rendered_mind_150.txt`
and the before/after `mind_ownership_*_test.log` files in `output/crowded_perf/`.

Follow-up validation: **239/239 isolated regression smokes pass** (142 seconds),
including the 20-check owned-state regression. All **574 scripts compile with
zero warnings**. The tests cover nested learning, held binding references,
save/load and worker isolation, reusable contexts, bounded old/new tables,
schema reset, and live same-frame configuration toggles.
