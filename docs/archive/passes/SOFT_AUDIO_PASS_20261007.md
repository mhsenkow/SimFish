# Softer sound and further refinements — 2026-10-07

The reported static has a plausible source beyond the hat: the vinyl floor was continuous, and the air bus has a 34× synthesis trim. In the healthy lo-fi probe it produced substantially louder noise than intended. The shaker's internal gain was also disproportionately high. Offline captures cannot establish exactly what the player heard, but both sources are now softer.

## Implemented

1. Remove continuous vinyl hiss from lo-fi while retaining occasional filtered accents.
2. Reduce the lo-fi persona's vinyl amount from 0.24 to 0.06, affecting existing lo-fi configurations as well as new preset selections.
3. Reduce preset vinyl to 0.06.
4. Make zero vinyl genuinely silent even when a persona is selected.
5. Make zero tape modulation genuinely off even when a persona is selected.
6. Give vinyl pops an independent filter state; the hiss generator no longer drives the pop filter.
7. Use a properly distributed inter-pop interval instead of a short uniform interval divided by the nominal rate.
8. Darken and lower the vinyl pop output with two low-pass stages.
9. Darken lo-fi hats to a 1.5 kHz two-pole filter.
10. Round the hat attack with a smoothed envelope.
11. Round shaker attacks separately.
12. Give the shaker two low-pass stages, with a 1.4 kHz cutoff in lo-fi.
13. Lower shaker synthesis gain, especially in lo-fi.
14. Lower lo-fi preset hat and shaker levels.
15. Make clap stereo noise obey its volume and mix controls; a muted clap no longer leaks noise.
16. Cache hat, shaker and vinyl filter coefficients instead of recomputing them per sample.
17. Add a visible **Clean texture** action beside the Sound Studio presets, preserving melody, persona and environmental sounds while turning off vinyl, hats, shaker and claps. Existing Save controls persist the selection.
18. Retain unconsumed audio queue tails during partial drains.
19. Preserve queued audio when the frame budget is zero.
20. Limit queued writes to available playback capacity.
21. Preserve sample order across all three stream queues.
22. Report musical energy independently of tank vitality, so a healthy tank's quiet score is perceived as quiet rather than energetic.
23. Add regression coverage for zero texture controls, lo-fi hiss, clap muting, partial drains and Clean texture preservation.

## Measured comparison

Both isolated captures render 16 seconds of the healthy-tank lo-fi preset. The generator has random event and percussion variation, so they are not identical performances.

| Gain-adjusted dry output | Before | After |
| --- | ---: | ---: |
| Air RMS, active samples | -42.3 dBFS | -61.3 dBFS |
| Mixed RMS, active samples | -35.5 dBFS | -36.5 dBFS |
| Mixed peak | -20.0 dBFS | -26.4 dBFS |
| Clipped PCM samples | 0 | 0 |

The air texture is about 19 dB quieter while the total musical level changes by about 1 dB. Individual layer WAVs omit their playback gain, unlike these probe readouts. The captures exclude master effects and physical output latency. No subjective listening or device-underrun claim is made.

Outputs: `output/soft_audio_pass/{before,after}.wav` and isolated layer WAVs. The queue and music-energy fixes were made after the comparison; they do not change the offline generator's tone.

## Further improvement candidates

These are candidates, not completed work. They extend the existing 1,000-item roadmap with priorities informed by this pass.

1. A/B each noise layer through a short built-in audition, with comparable loudness.
2. Let the keeper solo drums, melody, air and creature accents without editing several knobs.
3. A subtle high-frequency meter to reveal a layer dominating the mix.
4. User-adjustable percussion softness, independent of percussion loudness.
5. A brush/tambourine palette with recognizable physical timbre rather than generic noise.
6. A small stereo resonator for hats, preserving acoustic identity at low volume.
7. Louder accents duck texture slightly instead of adding masking noise.
8. Crossfade whole presets, including delayed tails, without restarting phrase timing.
9. Preview a preset without changing or saving the current performance.
10. Keep a reversible previous-mix snapshot beside Clean texture and Randomize.
11. Make recordings include consistent loudness metadata and clearly label dry versus full-output captures.
12. Measure generator underruns in dense rendered tanks, separately from offline audio output.
13. Account for generated-but-not-yet-audible samples in the fish beat clock.
14. Test stereo balance and mono fold-down for each persona.
15. Calmer nocturnal instrumentation coordinated with fish sleep rather than just quieter volume.
16. Gradual recovery in harmonic brightness after hypoxia, avoiding instant emotional shifts.
17. Longer event cooldowns for repeated feeding and plant propagation accents.
18. Species-specific timbre motifs that remain recognizable across changes of key.
19. Fish memories of repeated motifs, with bounded storage and decay.
20. Music preferences expressed through consistent, restrained behaviour rather than exaggerated dancing.
21. Separate learned musical associations from instantaneous arousal in thoughts.
22. Display confidence when external beat analysis cannot identify a stable pulse.
23. Preserve manual mixer edits when switching only a dance style or a harmonic scale.
24. Clearer explanations of which tank metric is currently changing the arrangement.
25. Keyboard focus should return to an expanded section's heading after collapse.
26. Store expanded Sound Studio sections in session UI state.
27. A compact mixer overview for narrow windows with one-tap access to each layer.
28. Responsive score status with readable tempo, swing and harmonic centre.
29. A reset for each mixer section rather than requiring a whole preset reset.
30. A measured audio regression matrix for healthy, stressed, thriving and nighttime tanks.

## Validation

- 550 scripts compile, with zero parse failures and zero analyzer warnings.
- Full suite: 222 passing tests, three existing baseline failures, zero new failures and zero timeouts across 225 tests.
- New audio texture regression: 18 checks pass. Music listening regression: 22 checks pass.
- Sound Studio visually inspected at desktop and compact window sizes; Clean texture is visible beside the presets at both sizes.
- `git diff --check` passes.
- Every isolated run verifies the real tank inventory is unchanged.

The UI capture still reports rendering/resource leaks during shutdown; this pass does not resolve that existing capture/runtime limitation.
