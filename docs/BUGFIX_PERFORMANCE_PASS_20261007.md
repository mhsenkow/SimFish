# Planting bug and performance pass — 2026-10-07

## Changes

The screenshot's repeated epiphyte warning came from manual placement sampling a random substrate position and searching only within the six-unit propagation radius. A host elsewhere in the tank could be missed. Without a nearby host, the code silently changed the plant into a rooted plant.

Manual library and creator placement now searches all eligible hardscape in the tank. If no host exists, placement returns false and supplies “Add rock or driftwood before placing this epiphyte.” Both panels display the reason. The genome remains an epiphyte; no warning is emitted and no substitute plant is spawned. Autonomous attachment retains its original local search radius. Creator batch placement also builds its genome once rather than once per individual.

Fish open-water travel previously ran fourteen iterative boundary clamps per movement step. The new fast path checks the requested endpoint once and accepts it when it fits below the water surface. Travel reaching a boundary retains the original conservative search. A water-surface guard prevents the emergent-plant region from being treated as a swimming shortcut.

Fish cognition now captures the initial diagnostic snapshot only for cycles that consume it. Sleeping and gated cycles avoid that unused deep copy. Mind-state diff comparison borrows current collections and copies only changed values. Public snapshots and both ends of a retained diff remain detached from subsequent nested mutations. Cognition frequency, memory decay, and decision modules are unchanged.

## Validation

- Manual planting: 10 assertions covering hostless refusal, keeper-facing reason, genome identity, distant-host attachment, local propagation limits, and ordinary rooted plants.
- Swimming boundaries: 72 assertions across box, triangle, hex, cylinder, and sphere, comparing boundary travel with the original search and checking body clearance and water-surface shortcuts. Interior steps use one clamp.
- Mind diff: 9 assertions covering unchanged state, float noise threshold, snapshots, and nested ownership on both sides of changed workspace/self-model values.

The test fixtures load World after autoload initialization, avoiding a headless compile-order failure. Helper scripts are not named `smoke_*`.

## Measurement method

Rendered sequential before/after runs use the same default beginner-sandbox workload, 180 settle frames and a five-second sample, on Godot 4.6.2 / Metal Mobile / Apple M2 Ultra. The before variant copies the fish and mind-state sources saved at the start of this pass; other resources are shared. The user's separate game session was stopped before this pair. Populations and geometry can vary slightly because the aquarium is alive. Results are development-engine samples, not an exported-build or low-end guarantee.

All verification launches use the corrected private-project isolation launcher and verify the real tank inventory. This pass does not resolve the earlier slot-13 loss documented in [the save incident report](DEV_SAVE_ISOLATION_INCIDENT_20261007.md).

## Rendered results

| Default workload | Before | After |
|---|---:|---:|
| Median frame time | 133.10 ms | 130.62 ms |
| p95 frame time | 148.92 ms | 149.34 ms |
| p99 frame time | 149.42 ms | 149.69 ms |
| Fish | 47 | 47 |
| Fish + shrimp + plants | 195 | 196 |
| Draw calls in final sampled frame | 2,745 | 2,742 |

The median decreased about 1.9%; p95/p99 did not improve. This pair does **not** establish a substantial whole-game performance improvement. Simulation remains expensive and the development sample is far above a 16.7 ms frame budget. These changes remove known redundant work without reducing the living simulation's update frequency or visual fidelity. Further work should profile the fish decision and plant simulation paths and verify exported-build timings.

Evidence is in `output/bugperf_pass_20261007/{before_clean,after_clean}/default.json` and `comparison.log` (git-ignored local output). Both sequential runs used isolated user data, and the before/after hashes of the real tank inventory matched.

## Final regression result

The complete suite finished in 114 seconds: **220 passed, 0 new failures, 3 existing known failures, 0 timeouts**, across 223 scripts. The existing baseline remains `smoke_multimesh_layout`, `smoke_refinement_ii_proof`, and `smoke_silhouettes`; no failures were added or hidden. The new regressions passed all 91 assertions. Compile/warning checking loaded **547 scripts with 0 failures and 0 analyzer warnings**. The real save inventory remained unchanged throughout the final suite.
