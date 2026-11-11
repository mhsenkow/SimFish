# Seedling reliability and performance pass — 2026-10-07

## Screenshot failure

The seed genome stored a live GDScript resource. JSON converted that resource to debug text such as `(res://scripts/coral.gd):<GDScript#-9223371980634233312>`. Germination later tried to load the entire debug string as a filename.

Seed production and nested JSON serialization now write the script resource path. A bounded resolver repairs the old debug format, validates Plant inheritance, and falls back to Plant for missing or inappropriate scripts. Existing saved seeds can germinate without manually editing the tank. Missing paths are cached to avoid repeated resource lookups.

## Related fixes

- Configure inherited coral, branch and spiral geometry before initial voxel construction; preserve coral form and saved tip color.
- Recompute terrain height when relocating a seedling.
- Apply plant capacity limits to dormant-seed germination and stop consuming dormant seeds when the tank is full. Deliberate planting remains available.
- Preserve separate dormant-seed age cohorts when loading, rather than assigning one cohort's viability and age to an unrelated family.
- Replace dormant inventory on restore, including empty saves and repeated legacy loads.
- Keep unnamed descendants of different parent lineages distinct.
- Reject invalid seed cells, nonfinite quantities and nonpositive consumption.
- Restore array-encoded underside colors to Color values during genome enrichment.

## Performance and consistent behavior

Fish music responses are cached within each render/physics frame, with invalidation during life ticks and saved-state restoration. Simulation and animation share the complete response, including sleep and stress. This also fixes simulation music calculations that previously omitted those traits.

Plant-grid rebuilds now populate the occupied-cell index used by adaptive queries. Previously broad plant queries walked empty grid cells because that index was never populated. Candidate ordering and results remain covered by the sparse-query smoke.

## Validation

Final compile: **561 scripts, zero compile failures, zero analyzer warnings**.

Full regression suite: **227 passed, zero new failures, three known failures, zero timeouts**, out of 230 scripts, in 121 seconds. Existing baseline failures remain `smoke_multimesh_layout`, `smoke_refinement_ii_proof`, and `smoke_silhouettes`.

Focused coverage: seed-resource integrity 31 checks, music-response cache seven checks, sparse ecology queries 19 checks. The seed regression executes actual `World.spawn_seedling` with the exact corrupted screenshot string, through a fixture that avoids creating a real tank.

Single-run CPU microbenchmark on this machine:

| Operation | Before | After | Ratio |
|---|---:|---:|---:|
| 6,000 repeated music-response reads within a frame | 39,395 µs | 1,151 µs | 34.2× |
| 3,000 broad plant queries in a sparse habitat | 54,589 µs | 2,379 µs | 22.9× |

The music benchmark deliberately measures repeated reads; the first read still computes a complete response. The query benchmark measures a sparse habitat with a broad radius; dense or narrow searches will differ, and index sorting adds rebuild work. These are individual measurements, not distribution estimates or end-to-end frame timings.

Final isolated compile, suite, and benchmark all verified that the real tank inventory was unchanged. All Godot runs use `scripts/dev_run.sh` and its user-data preflight. Early runs observed concurrent real-slot-20 autosaves while the player's game was running; no backup was restored over that live state. Final validation follows the player's confirmation that the game was stopped.

Benchmark source and logs: `output/reliability_pass/`. These are CPU microbenchmarks of specific operations, not an overall FPS guarantee.
