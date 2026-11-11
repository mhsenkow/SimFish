# Ecology restore and neighbour query pass — 2026-10-07

## Stable plant competition across reloads

The structured allelopathy store previously added saved chemical mixtures to the existing field. Repeated restores could strengthen plant competition, while an empty structured save left the old families present. Legacy scalar migration also added to existing mixtures.

Restores now replace the field, including empty saves. Legacy migration starts from a cleared store. Saved coordinates and amounts use finite numeric coercion, and runtime emissions reject invalid cells and nonfinite amounts. Invalid elapsed time leaves the field unchanged. Kin resistance, family limits, total concentration limits, and decay behavior are preserved.

## Reduced simulation allocations

Neighbour searches for fish/shrimp, render-rate nearby-fish searches, and nearby-snail searches now check for an occupied cell before retrieving its bucket. This avoids constructing empty arrays for missing grid cells on every organism scan. Chemistry totals now read a cached concentration rather than summing and allocating a values array. Emission, family eviction, decay, reinitialization and restore maintain that cache. A first attempt that removed only the values allocation benchmarked slower with the added validation; the cache resolves that overhead.

Empty plant inventories return immediately from plant searches. Nearby-fish searches cannot return stale grid fish after the inventory is cleared. Public fish, plant, and snail radius queries reject nonfinite positions or radii and invalid negative radii before grid arithmetic.

## Validation

The new `smoke_ecology_restore_integrity` covers repeated and empty restores, legacy migration, kin resistance, invalid cell and number handling, decay, live nearby-fish results, exact-distance filtering, and clearing inventory.

Compile check: **562 scripts, zero failures, zero warnings**. The new integrity smoke has 29 checks.

Single-run benchmark, original implementation versus the final implementation in the same isolated process:

| Operation | Before | After | Reduction in elapsed time |
|---|---:|---:|---:|
| 100,000 chemistry total reads, four families | 49,866 µs | 33,703 µs | 32.4% |
| 6,000 neighbour searches, 12 fish in one occupied cell | 43,454 µs | 33,857 µs | 22.1% |

These CPU microbenchmarks do not measure whole-game FPS. Occupancy and query frequency affect the benefit; the neighbour comparison uses the prior query algorithm with its constant offsets and scratch array.

Final regression suite: **228 passed, zero new failures, three existing baseline failures, zero timeouts**, out of 231 scripts, in 121 seconds. Existing failures: `smoke_multimesh_layout`, `smoke_refinement_ii_proof`, `smoke_silhouettes`. Final isolated runs verified that the real tank inventory was unchanged. Godot runs use `scripts/dev_run.sh` with user-data isolation and real-tank inventory checks. Logs are under `output/reliability_pass/`.
