# Swimming and motion pass — 2026-10-07

This pass improves the existing locomotion model rather than replacing the species behaviours or schooling system.

## Implemented

- Burst/glide modulation changes the requested pace before speed integration. It no longer repeatedly multiplies current speed on every substep, which compounded damping at fast-forward speeds.
- The burst/glide envelope now uses a full radian tailbeat cycle rather than wrapping once per radian.
- Turn-associated pace support also changes the requested speed instead of repeatedly accelerating the integrated state.
- Removed the anticipation nudge that always biased heading left because the heading angle was unsigned.
- Turn reversals brake existing angular momentum before starting in the opposite direction. Near glass, clearance takes precedence over holding the old turn.
- Turns obey their per-step cap, including retained momentum and near-stationary cases. Aligned fish shed unused angular rate.
- Corrected vertical steering: horizontal rotation-axis components drive pitch; UP drives yaw. Pitch is damped while level yaw retains its full rate.
- The motor eases toward its requested pace instead of switching between full thrust and zero at a tiny speed threshold.
- Coasting receives gentle braking trim. Fully suppressing braking let residual stroke thrust sustain the previous cruise speed after the keeper's intended slow-down.
- Wall approaches ease the requested pace rather than applying a sudden post-integration speed cap. The existing collision/travel bounds remain authoritative.
- Physical thrust and steering use an independent motor clock that advances even when mesh animation is culled. Its long common period preserves slow steering harmonics across wrapping.
- Yaw-rate state updates for culled fish too, avoiding stale turn-associated pace support.
- Bank angles remain bounded, with elapsed-time smoothing.
- Body bends include the previously calculated turn load, scaled by body flexibility; rigid bodies receive less bend.
- Pectoral rowing varies slightly between left and right fins during turns.
- Paused, negative or non-finite time steps preserve physical state.
- Locomotion-specific base tailbeat rates are shared by physical and visual code; mood and musical animation retain their decorative modulation.

No model inference, neighbour searches or new per-step dictionaries were added for these changes. Existing query caches and the tank-boundary fast path remain in use.

## Evidence

The isolated `valli_jungle` probes use the same scenario seed and a 12-second warmup followed by an 18-second sample. Both populations were 20 guppies and 21 glassdarts. The integration/pitch probe before the final coasting trim showed:

| Observation | Before | Revised integration/pitch |
| --- | ---: | ---: |
| Guppy mean speed, tank units/s | 0.49 | 0.65 |
| Glassdart mean speed, tank units/s | 0.53 | 0.88 |
| Guppy neighbour speed correlation | 0.04 | 0.03 |
| Glassdart neighbour speed correlation | 0.07 | approximately 0.00 |
| Guppy turn rate, radians/s | 0.62 | 0.62 |
| Glassdart turn rate, radians/s | 0.59 | 0.57 |
| Mean dissolved O₂ | 0.93 | 0.95 |

These short stochastic samples are diagnostic, not a controlled biological experiment or a general frame-rate guarantee. Correcting compounded damping increases sustained swimming speed; this is an intentional behaviour change rather than a preservation of the old pace. Reports live in `output/swimming_pass/before.txt` and `final_after.txt`; the latter predates the final coasting trim.

The final real-model close-up uses the game's Fish code in the Library renderer, with a bounded movement host, fixed 1/30-second steps and recorded heading/speed/bank telemetry. At 5 seconds its requested pace falls from 0.48 to 0.12. Speed falls from about 0.43 to 0.14 by 6 seconds and settles near 0.11 by the end. Headings reverse while bank angles change smoothly. Verified outputs:

- `output/swimming_pass/complete_frames/motion.csv`
- `output/swimming_pass/swimming.mp4`
- `output/swimming_pass/swimming.gif`

Earlier close-up fixtures omitted a movement-boundary host and therefore showed fin animation without forward motion. They were corrected; the strengthened visibility regression now requires non-zero speed and actual displacement, avoiding a vacuous matching-zero result. Earlier captures remain for audit; the exported previews use only the corrected final sequence.

## Validation

- 554 scripts compile with zero parse failures and zero analyzer warnings.
- Final full suite: 223 passing tests, three existing baseline failures, zero new failures and zero timeouts across 226 tests.
- Swimming continuity regression: 23 checks pass, with no runtime script errors in its final log.
- Performance contract passes: 150-fish tick 189.4 ms versus 50-fish 44.8 ms, within the existing scaling threshold. These are test workload timings, not game FPS.
- Final turning/braking frames were visually inspected and checked against speed, heading and bank telemetry.
- `git diff --check` passes.
- All isolated runs verify the real tank inventory is unchanged.

The full-tank behaviour probe reports rendering/resource leaks at shutdown, an existing probe/runtime limitation. The final dedicated Library-based movement capture exits cleanly.
