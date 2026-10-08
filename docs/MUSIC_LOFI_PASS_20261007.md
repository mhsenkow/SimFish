# Music and listening pass — 2026-10-07

The lo-fi preset now selects its lo-fi persona and hybrid bed, so it produces a continuous musical arrangement rather than mostly texture noise. The arrangement uses restrained drums, sub-bass, granular shimmer, vinyl and tape modulation, with a soft FM tine for the arpeggio. Existing synthesis voices and worker infrastructure are reused; no model inference was added to audio generation.

## Behaviour and interface

- Tempo changes advance an accumulated musical clock instead of recalculating every past sample at the new tempo. Live beat status updates once per rendered frame rather than once per bar.
- Generative music derives smoothed valence and arousal from musical features with elapsed-time smoothing. Key descriptions use the actual selected scale. Muted music is absent from fish thoughts and choreography.
- Lo-fi movement is restrained, varies with boldness, and fades with sleep and stress. Zero reactivity preserves baseline speed; lo-fi does not trigger beat darts.
- Fish mood receives a gentle generative musical influence. The updated mood and arousal reach MindState before the cognitive kernel commits them.
- Music context includes tempo, energy, swing, mood and confidence, with short sensory descriptions passed to the narrator. This extends simulated perception; it does not establish consciousness or persistent musical memory.
- Feeding respects the lo-fi/loop arrangement instead of forcing an energetic build. Disabled event audio cannot change the arrangement through feeding or extended death cues.
- Sound Studio opens on Tank score when external sync is off. Presets and essential controls precede expandable groove, texture, harmony, mixing and ecosystem controls. A listening description explains the current passage. Full score presets clear stale persona overrides; dance-only choices preserve the selected score.
- Completed synthesis worker tasks are reclaimed after completion.

## Audio evidence

Offline healthy-tank probes used the actual generator and the lo-fi preset. Outputs are under `output/music_pass_20261007/`. The baseline is 16.1 seconds and the revised sample is 24.1 seconds, so these are diagnostic excerpts rather than identical deterministic performances.

| Dry output | Before | After |
| --- | ---: | ---: |
| Mixed peak | -21.1 dBFS | -20.0 dBFS |
| Mixed RMS (WAV) | -36.5 dBFS | -35.6 dBFS |
| Synth silence fraction (probe) | 0.981 | 0.000 |
| Air layer RMS change | — | about -6 dB |
| Clipped PCM samples | 0 | 0 |

Individual layer WAVs are exported before the bus mix gain; their levels differ from the mixed WAV and probe's gain-adjusted readouts. These captures exclude the master effects and physical audio output. They verify generator output, not subjective listening quality or device underruns. Audible synchronization still includes generator buffering and device latency. Generative energy is a tank-state proxy, not measured output loudness or spectral analysis; the external music analyser remains separate.

## Validation

- Final compile check: 549 scripts, zero failures and zero analyzer warnings.
- Music subset: all four tests pass; the new listening regression performs 21 checks.
- Full 224-test run: 220 pass, three existing baseline failures, no timeouts, and one marginal timing failure in `smoke_perf_contract` (194.1 ms for 150 fish versus 40.4 ms for 50 fish; threshold 4.5×). The isolated recheck passes at 185.6 versus 42.5 ms. This is close to the threshold; no claim of a measured overall frame-rate improvement is made.
- The earlier new-test fixture incorrectly called a scene-only accessor on a detached node, then freed a node during a frame callback. Both fixture errors were corrected; the final music subset passes. Earlier failed logs remain alongside final verified logs.
- Sound Studio captures were visually inspected at desktop and compact sizes. The capture fixture selects a named sound preset and suppresses the first-run information overlay in its isolated profile. Compact layout retains visible presets and scroll access to the controls.
- `git diff --check` passes.

All game/test runs use `scripts/dev_run.sh` with isolated user data and verify that the real tank inventory is unchanged. UI capture reports resource leaks during process shutdown; these remain a capture/runtime limitation rather than a clean shutdown claim.
