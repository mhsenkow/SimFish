# Holistic implementation ledger

The [1,000-item review](HOLISTIC_IMPROVEMENTS_1000.md) is the roadmap. This ledger records concrete implementation and evidence from the first pass on 2026-10-07. It does **not** mark all 1,000 proposals complete. Existing working-copy improvements were preserved; the entries below describe this pass's additions.

**Save recovery unresolved:** An existing scenario smoke deleted slot 13's current and previous state during the first full run because the old isolation launcher was ineffective. The launcher and test are repaired; no exact backup has been found. See [the incident report](DEV_SAVE_ISOLATION_INCIDENT_20261007.md).

## Fish movement and appearance

- **WL-0076 — implemented:** Tailbeat rate responds to speed measured against estimated body length, with bounded rates for small fry and distinct locomotion profiles. Geometry and species identity remain intact.
- **WL-0077, WL-0079 — implemented:** Current-carried and stationary fish reduce their main tail/body wave. Previously the effort multiplier largely affected a small acceleration bonus while the baseline wag continued. Pectorals retain braking and station-holding responses.
- **WL-0097 — implemented:** Tail effort eases through a short exponential response. The live animation reuses one result dictionary per fish.
- **WL-0084 — implemented:** Gill breathing and pectoral rowing have independently integrated phases, seeded from individual variation. Changing respiratory load or fin frequency changes phase velocity instead of jumping the pose. The duplicate idle tail-phase advance is removed. The legacy multifrequency swim carrier stays continuous; wrapping it every tailbeat would introduce jumps in its noninteger harmonics.
- **WL-0028, WL-0030 — partial:** Fan-tailed fish now use six overlapping membrane strips that widen from the peduncle and round at the trailing corners. Their finnage is included in the fan itself, rather than adding disconnected caudal, dorsal, and anal veil plates again. This bounds tail geometry while retaining separate forked, lyre, square, crescent, and lanceolate templates. Front and side portraits and all six continuity cases are checked; other large-fin templates still need refinement.
- **WL-0052 — partial:** Opaque fauna shading now distinguishes thin fin tissue from body tissue using existing per-instance alpha. Membranes receive restrained view-dependent shading and vibrancy. Age, stress, and mood color washes preserve tissue density. This preserves opaque batching; it does not add expensive sorted transparency or claim to solve every planar fin silhouette.
- **Library reference portraits:** Fish use a stable preview identity and initialize as adults. Reopening the same genome produces a repeatable reference instead of a new randomly colored animal. The portrait audit fixes mixed morph randomization for comparisons.

Sources: `fish.gd`, `hydrodynamics.gd`, `fauna_voxel_builder.gd`, `voxel_fauna_mm.gdshader`, `library_panel.gd`.

## Reproduction and keeper understanding

- **WL-0213 — implemented:** Resident hover details explain the current physiological breeding blocker: growing, recovering, hungry, tired, or stressed. They also distinguish courtship, gestation, mouthbrooding, and livebearer males ready to respond. The UI and partner-seeking path use the same condition function. Suitable conditions explicitly do not promise a mate or suitable habitat. The existing seasonal thresholds and population suppression remain in force.
- **WL-0226 — implemented:** New eggs use bounded species-specific accelerated development profiles. Unknown species retain the 30-second default. These values are gameplay seconds, not biological incubation times.
- **WL-0227 — implemented within existing simulation units:** Incubation responds to normalized warmth and dissolved oxygen, with bounded rates and nonnegative time steps. The environment is sampled once per brood tick, not once per egg. Low oxygen slows development without introducing a new mortality rule.
- **WL-0229 — implemented:** One visible egg represents one prospective fry. The old four-cell egg representation implied more offspring than the hatch path produced. This also removes three mesh/material updates per embryo.
- **WL-0901, WL-0916 — partial:** Egg saves preserve independent chronological age, developmental progress, and incubation duration. Older saves keep their original 30-second deadline and age progress. Loading color arrays does not mutate the supplied save dictionary. This pass does not redesign the entire save format or all livebearer birth paths.

Sources: `egg.gd`, `sim_driver.gd`, `residents_panel.gd`, `fish.gd`.

## Light and ecological cycles

Daylight and seasonal cues advance through the same accepted simulation time as ecology. Previously the four-tick hitch cap discarded biological catch-up time while the day cycle continued through the entire input delta. Pause remains shared, and the keeper can still freeze daylight independently while ecology runs. An eight-check regression covers hitches, pause, daylight freeze, and accelerated time.

## Rendering and search costs

- Plant root hairs, anchors, and rhizomes use one root MultiMesh per plant rather than one render node per voxel. Local rotations, cached box dimensions, colors, logical root counts, visibility ranges, and growth handles are preserved. Scene teardown invalidates retained root handles.
- Static desk planks, desk lip pieces, and wall bricks share batches by material. Window cutouts, shade variation, cached dimensions, and the room transform remain intact. Animated room props stay independently addressable. An ineffective old shadow loop was removed: it stopped at the final light child before ever reaching a desk plank.
- Shared species geometry updates after fish animation at render cadence. Admission dropping below the population threshold no longer deletes existing animation registrations. Batch transforms account for a translated or rotated tank. Freed pivots hide their geometry; scene-owned drivers release batches when a tank closes. Transform inverses and pivot transforms are cached within each upload, and live sync slots are compacted in place.
- **WL-0938 — implemented for plant, algae, and waste candidate queries:** Broad searches in sparse tanks walk sorted occupied cells instead of constructing hundreds of empty buckets. Small/dense queries retain cell traversal. Candidate membership and order match the previous algorithm; final distance/state filtering remains with existing callers.
- Topological schooling now selects its CPU path before attempting GPU dispatch. It no longer computes and reads back GPU results that would immediately be discarded. This is particularly relevant to supported non-Metal GPU paths; macOS already bypassed that dispatch.
- An unused deep copy of the previous mind snapshot was removed. Cognition, social memory, individual decisions, and the ecological simulation remain active.

## Diagnostics and isolated verification

- **WL-0926, WL-0927 — partial:** Rendered workload reports include visible geometry ownership, process/physics monitor values, optional subsystem splits, and optional per-stage simulation/inner-life timings. Node counts identify owners; they are not GPU timings. Stage profiles are opt-in with `SIM_PROFILE=1`.
- The smoke runner uses a bounded FIFO of child processes, compatible with macOS Bash 3. Its old `wait -n || wait` fallback drained the first pool and left its counter at seven, serializing subsequent launches. Timing-sensitive performance smokes still run alone.
- The existing fish behavior probe's “sim off” diagnostic now disables physics processing, where the simulation actually runs. Disabling ordinary processing had left simulation active and mislabeled that comparison.
- **WL-0919, WL-0962 — extended:** `scripts/dev_run.sh --command ./scripts/run_smokes.sh` now supplies an isolated initial project configuration, verifies the actual user-data directory with a no-autoload preflight, keeps full recovery copies, and checks real tank inventory afterward. The old override-only path failed; see the incident below. The real project configuration is never rewritten.
- Six meaningful regression scripts cover motion/development, root geometry, shared fauna lifecycle, sparse ecology queries, exact preservation of invalidated saves, and cycle synchronization. They use `TestSupport.Suite` and verify behavior and ownership, not merely source strings.
- The application logger now initializes its bounded ring during construction. A service can log before autoload readiness without indexing an empty ring. Its regression includes that startup case. The cognition fixture also supplies its daylight contract instead of generating a false service error.

## Measured evidence

Artifacts live under `output/improvement_pass_20261007/` (git-ignored scratch output). The baseline and geometry-pass samples used Godot 4.6.2, the Metal Mobile renderer, and an Apple M2 Ultra. These runs use the development engine binary; exported-build performance is still unverified. Each workload sampled five seconds after settling, with 47 fish. These are review-machine samples, not a low-end performance promise.

| Workload | Baseline draw calls | After root/room batching | Baseline median frame ms | Geometry-pass median frame ms |
|---|---:|---:|---:|---:|
| Default | 6,297 | 3,165 | 123.36 | 130.12 |
| Dense preset | 6,230 | 2,772 | 124.91 | 129.38 |
| Feeding interaction | 6,793 | 3,122 | 133.67 | 122.32 |

The geometry change reduced draw submissions substantially but did **not** establish a reliable frame-rate improvement. The dense preset changes the density budget rather than demonstrating a larger fauna count; it must not be described as a population stress test.

A subsequent independent subsystem split averaged 133.12 ms with everything active, 71.17 ms with fish animation off, and 25.10 ms with simulation physics off. These are diagnostic samples at different moments of a living tank, not additive component timings. They identify simulation work as the next priority. Detailed profiles found fish decisions substantially more expensive than schooling-field construction. Sparse query timing and final regression results are recorded below after verification.

The populated front capture preserves root placement and room geometry. Its composition diagnostics still report a centered focal mass and a narrow swim corridor. The front and side reference portraits confirm a continuous fan-tail silhouette. The animals remain stylized voxel art; this pass does not claim photorealism. Immediate capture shutdown also reports renderer/resource cleanup warnings, so exported-build visual and lifecycle validation remains outstanding.

## Save incident

The first full regression run deleted the current and previous state of slot 13, “Iwagumi Stone Garden,” through an existing destructive scenario smoke and ineffective override-based isolation. Recovery is **unresolved**. Configuration/metadata and other tank file content survived. The launcher, scenario smoke, and incompatible-save retention have been corrected. See [the incident report](DEV_SAVE_ISOLATION_INCIDENT_20261007.md) for exact evidence, hashes, recovery status, and safeguards. Later unchanged inventories do not undo this loss.

## Verification results

- Complete suite: **217 passed, 0 new failures, 3 existing baselined failures, 0 timeouts** across 220 scripts, in 113 seconds. The existing failures remain `smoke_multimesh_layout`, `smoke_refinement_ii_proof`, and `smoke_silhouettes`; they were not hidden or added to the baseline.
- New regressions: motion/development and fan budget 59 checks; root batching 6; shared fauna lifecycle 7; sparse ecology queries 16; save invalidation archive 8; cycle-clock synchronization 8. All passed.
- The corrected isolation path passed its actual-directory preflight and left real tank inventory unchanged throughout the final suite.
- Informational sparse-query fixture: 1,000 radius-eight searches in a two-cell grid took 44,351 µs through the reference implementation and 606 µs through the adaptive implementation. This approximately 73× synthetic query improvement is **not** a whole-game frame-rate claim.
- Final compile/warning gate: **542 scripts, 0 compile failures, 0 analyzer warnings**. Shell syntax and `git diff --check` also passed.
- The final profiler-enabled three-workload sample reported default/dense/interaction medians of 129.93/129.88/133.56 ms and 2,692/2,710/2,845 draws, before the last fan contour change. This reinforces the remaining simulation bottleneck. The completed default workload with profiling disabled reported **131.78 ms median, 150.00 ms p95, 47 fish, and 2,687 draws**. Compared with the initial default sample, draw submissions fell about 57%; frame-rate improvement is not established. The application remains well above a 16.7 ms frame budget on this development-engine sample, so “incredibly fast” is an outstanding goal.

## Remaining scope

### Follow-up: planting and performance bugs

The subsequent bug pass fixes manual epiphyte placement and reports missing hardscape in the creator/library UI instead of warning and silently changing the plant. It also adds an open-water travel fast path and removes unused cognition snapshot copies while preserving detached history. The complete follow-up suite passed 220 scripts with the same three known failures and no timeouts. A clean rendered timing pair showed 133.10 → 130.62 ms median with unchanged p95; this does not establish a substantial overall speedup. See [the bug/performance pass](BUGFIX_PERFORMANCE_PASS_20261007.md) for implementation and measurement details.

The unlisted proposals remain unimplemented or only previously present in the application. Important follow-through includes profiling and reducing cognition copies without losing memory; clear swim corridors and less competing visual noise; species-specific fin contours; offspring-to-parent continuity across every reproductive path; shared light/ecological time contracts; and measured low-end/exported-build performance. The next pass should use measured player benefit and cost rather than expanding all 1,000 ideas simultaneously.
