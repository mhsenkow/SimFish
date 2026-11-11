# Faster minds and gentler starting habitats — 9 October 2026

This pass removes repeated cognitive work and repairs learning that was being
discarded. New habitats begin with their complete planting and established
biology in place; automatic feeding responds to appetite. Fish geometry,
movement integration, sensory reach and cognitive scheduling are retained.

## Performance work

- Keep a bounded recall cache on each fish or worker proxy instead of an
  unbounded global cache keyed by save ID. Cache keys include the requested
  result count and quantization mode; new experiences invalidate recall
  immediately. Deleted fish and reopened tanks cannot share cached memories.
- Calculate query norm and quantization configuration once per retrieval.
  Scan memory buckets in place while preserving the original top-k order,
  fallback and rehearsal behavior.
- Restore ordinary MindState snapshots with one detached deep copy, rather
  than copying their nested collections again after migration. Exclusively
  owned worker jobs and results transfer their collections without further
  cloning. Save, history and ordinary public snapshot APIs remain detached.
- Give the one-shot fish save serializer its already-detached MindState rather
  than taking a second snapshot and cloning it again. Transient location cues
  are omitted from saves and cleared on load, including legacy saves that
  contain one; worker handoffs still carry them.
- Construct a full MindState only when a cognitive cycle will consume it.
  Applying an available worker result no longer requires a speculative full
  snapshot of the current mind.
- Build one attention census per simulation tick and update it as fish change
  focus. Tank-theme queries reuse the counts. Ties retain the original first
  appearance in the roster; that case still scans the roster.
- Skip empathy roster searches when no bond meets the existing threshold.
  Every eligible bond retains its original distance and stress checks.
- Cache the real-world breeding season multiplier per physics frame. Cached
  partners are checked again for availability, health and distance before
  courtship; stale or freed candidates cannot initiate a pair bond.
- Cache the TankConfig node identity for the brain-thread switch while reading
  its current value. Headless runs now honor the serial setting too.

## Learning continuity

Three reproduced bugs were undermining the existing mind systems:

1. Situation recall read a relevance score from an episode, although scores
   existed only in temporary search wrappers. Relevance was always zero, so
   recalled food or danger locations never became steering cues. The strongest
   relevant finite location now supplies the cue, including after a worker
   round trip. Temporary scores stay out of saves.
2. The final MindChannel commit restored a snapshot taken before binding and
   learning. Newly bound moments and recurrent model updates disappeared at
   the end of the cycle. Completed runtime updates are now captured before
   committing; workspace and self-model authority remain on MindState.
3. The recurrent predictor's readout-learning guard looked for hidden state in
   the weight dictionary. Hidden state lives on the model, so learning returned
   immediately. The readout now learns against the previous prediction's
   hidden state before rolling the recurrence forward.

Late worker batches also preserve newer main-thread experiences, prediction
updates, learned habits, biography moments and changed felt-self components.
An extended regression reproduced habits rolling back from 0.9 to 0.5 and a
new biography line disappearing when an older batch applied. Component merges
retain newer live learning while accepting worker changes to untouched fields;
unchanged worker components require no main-thread copy. This improves continuity
in the game's simulated inner life; these checks do not establish consciousness.

## Tending a finished habitat

World builds a habitat over many frames. Ecology now waits until its founders,
planting, fixtures and saved state are ready. The initial carrying capacity and
photosynthetic canopy are calculated from the finished planting, including
floating plants and plant health. Construction contributes no accumulated
simulation debt. Later capacity changes keep their existing gradual response.

Capacity now includes established bacterial support from filters and sponge
aeration, scaled by the actual colony, aeration strength and filter condition.
Previously Iwagumi could begin with 30 fish against a calculated capacity of 14,
despite its established cycle. This change supports the sparse stone garden
without replacing its negative space with a jungle. Fresh new colonies provide
less support. Newly established filters begin with matured media; saved age,
chemistry and keeper settings retain their restored values.

Automatic feeding still runs every 12 simulated seconds and respects the
keeper's feeding setting. It sizes a bounded ration from unmet fish appetite
and a small hungry-shrimp supplement, credits food already present, and limits
additional feeding during oxygen or ammonia pressure. Pellets are spread above
hungry residents so one random feeding point does not monopolize the ration.
Existing grazing, nutrient quantities and consumption systems remain active.

All **17 authored starter layouts** built within their calculated capacity in
the initial audit. Wildcard is generated rather than an authored layout and was
not included. Mixed founder ages and biomass vary between builds.

Three actual World builds were then observed for **36 simulated seconds**:

| Habitat | Living fish, start → finish | Mean fish hunger | Mean fish stress | Ammonia |
| --- | --- | --- | --- | --- |
| Iwagumi | 30 → 30 | 0.383 | 0.001 | 0.0065 |
| Beginner sandbox | 47 → 47 | 0.344 | 0.213 | 0.0057 |
| Shrimp sanctuary | 0 → 0 | — | — | 0.0063 |

Shrimp sanctuary grew from 33 to 56 shrimp during this observation. Oxygen
remained plentiful in all three. This is a startup and early-settling check,
not a multi-day ecological balance proof or a guarantee for resized templates.

## Measurements

Same-machine Godot 4.6.2 headless real Fish/SimDriver fixtures, fixed seed,
12 warmup ticks and 12 measured ticks per population. Stage profiling enabled
in both runs; asynchronous brain mode explicitly retained for comparability.
These are **CPU simulation-tick durations, not FPS**.

| Fish | Before median / p95 | Final median / p95 |
| --- | --- | --- |
| 50 | 37.934 / 40.284 ms | 35.911 / 38.680 ms |
| 150 | 140.941 / 152.208 ms | 135.231 / 145.653 ms |
| 300 | 357.477 / 367.381 ms | 339.423 / 364.697 ms |

The final fixture is about **4–5% cheaper at the median** across these
populations. After the attention-census change, an earlier 300-fish run measured
310.969 ms median / 335.811 ms p95, about 13% cheaper at the median. Other
intermediate 300-fish runs ranged from 327 to 371 ms while fixes were being
integrated. Small populations did not consistently improve in every run;
the repaired learning also performs work the broken baseline discarded.
These short samples support reduced repeated work, not a universal speedup.
Crowded tanks still need architectural work before smooth real-time play
can be promised.

Focused microbenchmarks (median of five batches of 500 operations):

| Operation | Before | After |
| --- | --- | --- |
| Recall from 64 episodes | 274.020 µs | 185.796 µs |
| Restore an independent nested mind snapshot | 144.500 µs | 74.392 µs |
| Adopt an exclusively owned snapshot | — | 9.114 µs |

Recall is about 32% cheaper and ordinary snapshot restoration about 49% cheaper
in this fixture. The adoption timing excludes the detached snapshot creation
that must happen before crossing a thread boundary; it is not a zero-copy
claim for the complete worker pipeline.

## Reproduction and validation

```sh
SIM_PROFILE=1 CROWDED_PROBE_OUT=/tmp/crowded_cpu.json \
  ./scripts/dev_run.sh --headless --script res://dev/crowded_cpu_probe.gd

MEMORY_PROBE_OUT=/tmp/memory_cost.json \
  ./scripts/dev_run.sh --headless --script res://dev/memory_cost_probe.gd

TENDING_PROBE_SCENARIOS=iwagumi,beginner_sandbox,shrimp_sanctuary \
  TENDING_PROBE_SECONDS=36 TENDING_PROBE_OUT=/tmp/settled_starters.json \
  ./scripts/dev_run.sh --headless --script res://dev/tending_start_probe.gd
```

`CROWDED_PROBE_THREADS=0` selects serial cognition for a separate measurement.
The old headless path forced threads on despite the probe requesting serial;
do not compare a new serial run to that old asynchronous baseline.

Seven new regression suites cover recall relevance and cache isolation,
worker ownership and migration, retained learning across complete cycles,
incremental attention equivalence, habitat construction, appetite-based rations
and stale mate candidates. Existing mind, chemistry, motion and save tests also
exercise the changed systems.

The first full suite passed 250 of 251 tests and exposed a transient recall cue
being restored from the newly complete worker serialization. The save boundary
now explicitly excludes and resets that cue. Extended save tests verify legacy
cue clearing and nested snapshot isolation; all seven save suites pass.

Final validation: **251/251 isolated regression suites pass** in 150 seconds,
with no known failures, regressions or timeouts. Timing-sensitive suites run
serially. All **592 scripts compile with zero GDScript warnings**. The seven
new suites include 195 assertions, with before/after failures reproduced for
missing recall cues, discarded cycle updates and late-worker learning rollback.

Receipts live in the ignored `output/tending_performance/` directory:
`before.json`, `final_cpu.json`, `census_async.json`, `memory_before.json`,
`memory_after.json`, `all_starter_builds.json`, `settled_starters.json` and
intermediate profiles.
Every isolated World run reported an unchanged real tank inventory. Existing
headless World probes still emit renderer/resource cleanup diagnostics on exit;
their successful reports do not establish leak-free shutdown.
