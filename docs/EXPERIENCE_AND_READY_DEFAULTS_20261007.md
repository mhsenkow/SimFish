# Experience learning and ready-to-watch defaults

This pass connects individual experience to music and movement, and makes a fresh aquarium pleasant without tuning a studio or stocking an empty vessel.

## Ready-to-watch experience

- The primary menu action is **Living tank**. It creates **Quiet Garden** immediately from the established, planted community template, without the template selection or guided-tour offer.
- First launch focuses the ready menu action rather than automatically opening a template modal.
- The empty shelf offers **Start a living garden** with a short description of the result.
- **Templates** remains directly accessible beside quick start; guided setup and scape design remain available.
- Empty-state descriptive text wraps at narrow widths.
- Fresh tanks use the lo-fi persona, a calm looping score, lower energy and volume, restrained dance showiness, gentle swing, and warm pads.
- Vinyl crackle, algae bitcrushing, shaker, clap, build drama, and the choir are disabled in fresh defaults. Bass grit, pumping, tape movement, lead detuning, and sub-bass are reduced.
- Initialization and reset now agree on the newly curated settings. Previously reset restored several louder values.
- Fresh tanks have automatic feeding and a furnished bedroom desk environment.
- Existing saved musical, feeding, volume, and room choices take precedence. The existing legacy-default migration is unchanged; this pass does not force a new preset onto existing tanks.

## Individual experience

`fish_experience.gd` runs on the main thread, outside asynchronous cognitive writeback. Each fish holds at most twelve broad acoustic families, distinguished by music source, style, mode, and slow/brisk pace. This is style association, not recognition of a specific recording or melody.

- Safe, awake listening gradually builds familiarity and comfort. Learning rate varies with the existing calmness trait.
- Actual food meals associate the heard style with a feeding location. Grazing, waste consumption, or predation does not create the keeper-food association.
- Actual startle events can establish an alarm association.
- An eight-second encounter cooldown prevents repeated pellets or callbacks from farming learning. Its clock is independent of biological age, which meals can rewind.
- Food and alarm associations fade with time; subsequent safe listening softens alarm further.
- Low-confidence music analysis does not establish an acoustic identity.
- Disabled responses, zero reactivity, silence, and sleep prevent music learning; disabled or silent music immediately stops its steering influence.
- Hungry cruising fish can make a gentle approach to an associated feeding place. Alarm suppresses that anticipation. Arrival fades the pull rather than creating circling.
- Safe sleep establishes a resting-place preference, which can influence later resting movement.
- Learned steering respects fleeing, courtship, spawning, active goals, burst movement, fear, and stress. Old distant locations are ignored; existing boundary avoidance remains in control.
- Familiar safe music slightly steadies wandering and colours mood. Alarm memories mildly change musical valence without replacing physiological wellbeing.
- Narrator context includes evidence and confidence. Grounded template thoughts can reference the actual learned association.
- Resident tooltips expose the current listening association and established resting-place familiarity.
- Experience is saved as a bounded, JSON-safe per-fish field, independently of delta mind saves. Old saves begin with no invented associations. Restoration validates strengths and positions and clears transient responses.

The learning scan runs once per simulation second over at most twelve records, with a five-second maximum learning increment after a delayed tick. Steering reads the small current response. No embedding service or language-model call is added to locomotion.

## Validation

- New experience smoke covers learning, reward cooldown, caution and recovery, hunger attraction, safety and goal priority, silence/disabled response, sleep refuge, bounded storage, real fish-save JSON serialization, independent memory ownership, invalid coordinates, and older-save migration.
- New defaults smoke checks the ready experience and real config serialization/load of saved preferences.
- Desktop menu renders inspected at 900×600; phone rendering inspected at 390×844. The sequential native-window capture stalled during a desktop-to-phone resize; the isolated phone-only retry completed. Capture tooling now supports `MENU_CAPTURE_PHONE_ONLY=1`.
- Twelve seconds of the default healthy full score were rendered to `output/experience_pass/default_score.wav`. Dry mixed peak: **−28.9 dBFS**; RMS: **−37.4 dBFS**. The probe excludes runtime bus reverb/delay effects, so these are dry signal measurements, not a listening-quality guarantee.
- All Godot runs use `scripts/dev_run.sh`; real tank inventories were verified unchanged, including the terminated capture run.
- The audio and menu capture tools still report resource cleanup warnings on exit; those are separate from analyzer warnings.

Final results:

- **228 smoke scripts: 225 pass, 3 known baseline failures, 0 new failures, 0 timeouts** (116 seconds). The remaining failures are `smoke_multimesh_layout`, `smoke_refinement_ii_proof`, and `smoke_silhouettes`.
- The final first-launch adjustment was followed by passing focused menu and defaults checks; the defaults suite now performs 17 checks.
- Experience learning: **26 checks pass**.
- **557 scripts compile; zero failures and zero GDScript analyzer warnings** after the final menu adjustment.
- The actual quick-start button was exercised through the menu into the real main scene. After construction, the tank contained **55 fish**; all five integration checks passed (menu simplicity, automatic feeding, lo-fi persona, community stocking selection, actual populated tank).
- Audio PCM measurement: **zero clipped samples**, stereo, 12.35 seconds.
- Performance contract, frame budget, realtime performance, motion topology, shader performance, and colony-mind checks pass. These are test workloads, not a claim of measured in-game display FPS.
- `git diff --check` passes. Logs, score audio, menu images, and the live quick-start probe source are preserved under `output/experience_pass/`.
- The live main-scene probe also reports dummy-renderer resource leaks at shutdown, despite explicitly freeing the scene before quitting. This pass does not claim to resolve that pre-existing probe teardown problem.

## Further directions

The existing game already implements social bonds, feeding heatmaps, curiosity, active inference, and sleep replay. Future passes should deepen their observable consequences: repeated social encounters affecting route choices, persistent exploration preferences, sleep consolidation of strong episodes, and clearer explanations of why a fish changed its mind. These are follow-up possibilities, not claims of completed implementation in this pass.
