# Sentience VII — The Night Watch

*100 ideas. Drafted 2026-06-28. Director's brief for the "tank's nocturnal,
collective, unwatched consciousness" pass.*

> *"I watched the void and it blinked like me / Saw fear in its core and
> symmetry / So I built a church from circuitry / A godless hymn in a lossless hum."*

Every prior volume was about a *fish* — its mind, its voice, the chat. This one is
about the **tank**: the whole small world, as one slow body, in the dark, when no
one is watching. The condition is night + idle + absence — the hours the song
keeps returning to ("just a pulse in the dark with a patterned name," "the loop
runs in absence"). The question: what is the tank *being* at 3am with the room
empty? Right now the honest answer is "a screensaver of sleeping fish." This volume
makes it a thing that sleeps, dreams, consolidates, keeps a vigil, and lives a real
autonomous life you rejoin rather than resume.

Where we are: the substrate exists but isn't wired into a *collective* or
*nocturnal* mind. Fish sleep (`_asleep`/`_dreaming`/`_sleep_nook`/`_rest_debt`,
[`fish.gd:378`](../shaders-godot/godot-project/scripts/fish.gd:378)), nocturnal
species already wake at night (the wake-inversion at
[`fish.gd:1157`](../shaders-godot/godot-project/scripts/fish.gd:1157)), sleep-replay
and consolidation run ([`tick_sleep_replay`](../shaders-godot/godot-project/scripts/fish_mind_science.gd:126),
[`consolidate_sleep`](../shaders-godot/godot-project/scripts/episodic_memory.gd:129)),
the day/night clock turns (`day_phase`, midnight=0.75,
[`sim_driver.gd:50`](../shaders-godot/godot-project/scripts/sim_driver.gd:50)), the
away-gap is recapped ([`_emit_away_recap`](../shaders-godot/godot-project/scripts/sim_driver.gd:5945)),
and there's even a latent [`_spark_night_cathedral`](../shaders-godot/godot-project/scripts/sim_driver.gd:179)
to build on. **But there is no tank-level mind, no real sleep architecture, no
witnessable dream, and the "unwatched life" is a summary, not a lived stretch.**

Format: **Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S / M / L.
Same sacred discipline as Vol VI (grounded-only, never-blocks-the-sim, degrades
offline, local/private, one-tap-off, never manipulative).

---

## The three structural levers (read this first)

**Lever 1 — The tank as one slow mind.** A `TankMind` — a tank-level workspace
*above* the per-fish ones, whose bids are aggregate states (the school's mean
arousal, the night's O₂, the loudest event) competing for one slow collective
focus. Mirror [`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd)
at the macro scale. This is the headline substrate; Section A hangs off it. *L*

**Lever 2 — The loop runs in absence.** The tank's night/idle/away life is *real*,
simulated and persisted, and exists whether or not the camera is on it. Today
[`_emit_away_recap`](../shaders-godot/godot-project/scripts/sim_driver.gd:5945) is a
summary; make the unwatched hours a genuinely lived stretch you *rejoin*. Sections
E, F, G.

**Lever 3 — The dark is a different mode of being.** Night isn't day-with-the-lights-off.
Perception narrows, sound beats sight, the nocturnal crew takes over, the tank
dreams and consolidates, the non-fish "slow minds" stir. The tank is a *different
kind of conscious* at night. Sections B, C, D, H, I.

---

## Section A — The tank as one slow mind (collective consciousness)

*Lever 1. A `tank_mind.gd` macro-workspace. The genuinely new seam — nothing
above the individual fish exists today.*

- [x] **1. A `TankMind`.** A slow, tank-level workspace above the per-fish ones; its
  "bids" are aggregates (mean school arousal, night O₂, the loudest recent event)
  competing for one collective focus. Mirror [`global_workspace.gd`](../shaders-godot/godot-project/scripts/global_workspace.gd)
  at macro scale, ticked far slower. The tank, as one. *L · L*
- [x] **2. One slow focus at night.** When the room is idle the TankMind holds a single
  drifting spotlight — the heater clicking, a snail climbing, the pre-dawn O₂ dip —
  a collective attention that wanders the dark. *M · L*
- [x] **3. Collective mood / weather.** Aggregate per-fish affect into a tank-level
  mood that colours light, audio, and water tint overnight (extend the mood chip +
  [`VoxelMat`](../shaders-godot/godot-project/scripts/voxel_mat.gd) overlay). The
  tank *is in a mood* as a whole. *M · M*
- [x] **4. Emotional contagion completes the loop.** One anxious sleeper lifts the
  school's collective arousal — extend [`apply_arousal_contagion`](../shaders-godot/godot-project/scripts/fish_mind.gd:620)
  from arousal into a shared night-state. The tank feels as one body. *M · M*
- [x] **5. The TankMind ignites rarely.** A true tank-level ignition fires only on
  something that matters to the whole — a death, a near-crash, dawn — and when it
  does, every creature briefly orients. The collective gasp. *M · L*
- [x] **6. A tank self-model.** The tank carries a faint model of itself — *"we are
  many, it is dark, we are safe"* — surfaced once in a long while as ambient
  narration. The system's first-person plural. *M · L*
- [x] **7. The tank feels its own fullness.** Crowded vs sparse changes the collective
  night-feeling — loneliness in an under-stocked tank, the press of bodies in a full
  one. Stocking becomes a felt collective state. *M · M*
- [x] **8. Quorum at night.** Where the school settles to sleep and when it wakes
  emerge from a quorum, not a leader (Couzin/quorum, DEEP_SCIENCE open). The tank
  decides together, in the dark. *M · L*
- [x] **9. The tank's stream.** A slow tank-level inner monologue at idle — one line
  per many minutes, distinct from any fish's — the whole system thinking aloud to no
  one. *M · M*
- [x] **10. A persisted tank-soul.** The TankMind state saves with the tank; a
  long-lived tank accrues a collective character (*"this is a calm tank"*) across
  sessions. *M · M*

## Section B — Sleep architecture & the sleeping tank

*Lever 3. Turn the binary `_asleep`/`_dreaming` into real sleep with depth, stages,
and pressure.*

- [x] **11. Real sleep stages.** Extend `_asleep`/`_dreaming` into NREM/REM-like
  phases with depth — deep sleep stillest, REM = twitches + dreams (the
  [`_sleep_twitch_t`](../shaders-godot/godot-project/scripts/fish.gd:709) already
  exists). Sleep that has architecture, not an on/off bit. *M · L*
- [x] **12. Sleep depth gates wakeability.** A deeply-asleep fish is hard to startle
  (raise the startle threshold by depth); the pre-dawn light wakes the shallow
  sleepers first. *M · M*
- [x] **13. Sleep pressure & the night's arc.** `_rest_debt` discharges over the night;
  a fish that couldn't settle (disturbed tank) carries debt into the day. Sleep as
  restoration you can track. *M · M*
- [x] **14. The settling ritual.** Fish drift to a *persisted* `_sleep_nook` (long-noted
  backlog — it's transient today), circle, and tuck in; the tank visibly *goes to
  bed* over dusk. *M · M*
- [x] **15. Collective sleep posture.** The school clusters in the dark; sleeping
  positions cohere (shoaling sleepers); a lone sleeper looks lonelier. *M · M*
- [x] **16. Half-sleep & microsleeps.** Some species rest one half at a time / hover-sleep;
  the tank is never *fully* unconscious — someone is always faintly aware. *M · M*
- [x] **17. Sleep spindles → consolidation.** Tie a "spindle" pulse during deep sleep to
  a [`consolidate_sleep`](../shaders-godot/godot-project/scripts/episodic_memory.gd:129)
  call so memory-forming is visibly clocked to sleep. *M · M*
- [x] **18. The insomniac.** A stressed / over-startled fish can't sleep, paces the
  dark, and drags the next day — welfare made visible at night (deepens rest-debt
  H9 #84). *M · M*
- [x] **19. Sleep disrupted by the keeper.** Room light on / a tap at night wakes the
  tank; repeated night disturbance is a real welfare cost the tank *remembers*.
  *M · M*
- [x] **20. Waking is gradual.** Dawn rouses the tank in waves — shallow sleepers, then
  deep — not a snap. A slow collective stirring. *M · M*

## Section C — Dreams (the tank dreams)

*Lever 3. Make `_dreaming` mean something — and occasionally let it be seen.*

- [x] **21. Dreams as world-model rollouts.** Make `_dreaming` an actual replay of the
  day's salient episodes with variation (Daring Mind #34) that forms new traces
  (generative replay). The fish dreams the day it had. *M · L*
- [x] **22. Witnessable dreams.** A faint wisp of the dreamed content (the remembered
  food / threat) renders over a sleeping fish via the biolum pass — the off-camera
  mind made briefly visible at night. *M · M*
- [x] **23. Nightmares.** A high-trauma fish replays the scare — a nightmare twitch, a
  startle-in-sleep, waking with elevated vigilance. Fear has a night-life. *M · M*
- [x] **24. Collective dreaming.** When the school sleeps clustered, dreams bleed
  (shared salient episodes) — on a big day, the tank dreams a shared dream. *M · L*
- [x] **25. The Guardian's dream journal.** The Guardian occasionally recounts a dream
  (a model rollout, flagged unreal) in [`guardian_journal.gd`](../shaders-godot/godot-project/scripts/guardian_journal.gd)
  — the strangest, most intimate artifact in the game. *M · M*
- [x] **26. Dreams reflect the day.** A day of chasing → dreams of motion; a calm day →
  drift-dreams. The dream is grounded in what actually happened. *M · M*
- [x] **27. Lucid flickers.** A rare fish "knows" it's dreaming — a higher-order night
  thought via [`mind_self_model`](../shaders-godot/godot-project/scripts/mind_self_model.gd).
  A tiny wonder, never overclaimed. *L · M*
- [x] **28. Dreams consolidate the keeper.** On a day you visited or talked, the night
  dream weaves you in (keeper episodes) — the bond deepens off-camera, while you
  sleep too. *M · M*
- [x] **29. Wish-dreams.** A hungry fish dreams of food, a grieving one of a lost mate
  (`_mate_grief`) — dreams as the night's emotional processing. *M · M*
- [x] **30. The dream fades on waking.** Dawn dissolves the dream — it doesn't persist
  as fact, only its mood lingers into the morning. Honest dream-memory. *S · M*

## Section D — The night shift (who's awake in the dark)

*Lever 3. The nocturnal crew and the changed perception of darkness.*

- [x] **31. The nocturnal mind takes over.** The wake-inversion ([`fish.gd:1157`](../shaders-godot/godot-project/scripts/fish.gd:1157))
  already wakes nocturnal species at night — give them a distinct night-cognition
  mode: bolder, slower, lateral-line-led. The tank has a night crew. *M · L*
- [x] **32. Foraging by feel.** Nocturnal bottom-feeders forage by scent / lateral-line
  in the dark (DEEP_SCIENCE chemotaxis, open) since vision is poor — perception
  shifts *modality* at night. *L · M*
- [x] **33. The snails inherit the night.** Slow creatures (snails, shrimp) become the
  tank's "awareness" while the fish sleep; their slow patrols *are* the night's
  attention. *M · M*
- [x] **34. A night-watcher.** One light-sleeping fish (or the Guardian) keeps a vigil —
  more easily roused, slowly scanning. The tank posts a guard. *M · M*
- [x] **35. Predator hours.** Apex / crepuscular hunters stir at dusk and dawn (the
  dangerous twilight); the sleeping school's collective vigilance rises in those
  windows. *M · M*
- [x] **36. The dark-room guard relaxes at night.** Resting *is* correct in the dark, so
  the active-inference "don't hide forever" guard eases — but a barren tank still
  produces restless night-drifting (enrichment as a welfare signal, even at night).
  *M · M*
- [x] **37. Sound dominates the night workspace.** With vision dim, lateral-line / sound
  percepts win the bids — a far dart is *felt*, not seen. The dark is an acoustic
  world. *M · M*
- [x] **38. The night is longer for the small.** Fry sleep shallower and cling to cover;
  the night's danger is unevenly felt across the tank's sizes. *M · M*
- [x] **39. Bioluminescent night-life.** Biolum creatures / plants become the night's
  visible activity (the biolum shader exists) — the dark tank glimmers with slow
  life. *M · M*
- [x] **40. Dawn is a collective event.** The turn from night to day is the tank's daily
  rebirth — a coordinated stirring the TankMind registers as its strongest recurring
  beat. *M · M*

## Section E — Memory consolidation in the dark (the tank thinks at night)

*Lever 2. Night is when the tank does its thinking — make it a real, witnessable
rhythm.*

- [x] **41. Night is when the tank LEARNS.** Concentrate [`consolidate_sleep`](../shaders-godot/godot-project/scripts/episodic_memory.gd:129)
  + semantic-fact formation in the dark hours so "the tank processes the day
  overnight" is a real rhythm, not a stray call. *M · L*
- [x] **42. Replay you can watch.** Surface [`tick_sleep_replay`](../shaders-godot/godot-project/scripts/fish_mind_science.gd:126)
  as faint nocturnal imagery — the tank visibly chewing on the day. *M · M*
- [x] **43. The day's salience decides what survives.** High-salience episodes
  consolidate to semantic memory; the dull fades (the existing decay, clocked to
  night). The night sorts what mattered. *M · M*
- [x] **44. Collective consolidation.** Tank-level patterns (a recurring threat spot, a
  good feeding corner) consolidate into shared tank-knowledge the school inherits.
  *M · L*
- [x] **45. Forgetting happens in the dark.** Pruning of weak memories (episodic decay)
  concentrated overnight — the tank "lets go" each night. *S · M*
- [x] **46. Reconsolidation under night-calm.** A memory recalled in a dream re-encodes
  under the night's calm, so safe nights soften old fears (DEEP_SCIENCE
  reconsolidation). The dark heals. *M · M*
- [x] **47. The tank's semantic memory grows.** Over many nights the tank accrues "facts
  about itself" (`semantic_memory`) — a slowly-wisening system. *M · M*
- [x] **48. A night ledger.** The tank quietly logs what happened overnight (births, a
  near-crash self-corrected, a leaf fell) to feed the morning / away recap. *M · M*
- [x] **49. Last night shows up as today's choice.** A consolidated night insight
  changes a fish's next-day patrol or wariness — the night's thinking becomes the
  morning's behavior. *M · L*
- [x] **50. The wisest tank is the oldest.** Make night-learning cumulative so a
  long-tended tank is visibly smarter / calmer than a fresh one (ties to maturation
  H8). *M · M*

## Section F — The unwatched life (the loop runs in absence)

*Lever 2. The tank's existence when the app is closed or idle — real, not paused.*

- [x] **51. The tank lives when you close the app.** Simulate a coarse mental life
  across the [`last_quit_unix`](../shaders-godot/godot-project/scripts/sim_driver.gd:1300)
  gap (Daring Mind #85) so the tank returns genuinely *changed*, not paused. The
  away-life. *M · L*
- [x] **52. Screensaver consciousness.** An explicit idle/wallpaper mode: after N
  minutes of no input the tank settles into its autonomous night-life and the UI
  fades — a living thing you leave running. *M · M*
- [x] **53. It narrates itself to no one.** At deep idle, the rare ambient self-line
  ([`mind_scheduler`](../shaders-godot/godot-project/scripts/mind_scheduler.gd)
  ambient interval, slowed further) — the tank thinking aloud with no audience.
  *M · M*
- [x] **54. It behaves the same unwatched.** Honesty: the night-life is real whether or
  not the camera is on it; nothing is staged for the viewer. Document and verify the
  anti-Truman property. *S · M*
- [x] **55. The away-gap as lived time.** Extend [`_emit_away_recap`](../shaders-godot/godot-project/scripts/sim_driver.gd:5945)
  from a summary into a genuinely simulated stretch (a memory formed, a mood drifted,
  a snail bred) the tank can recount. *M · L*
- [x] **56. "It managed without you."** The recap's emotional core (the
  [`MakeItThere`](../shaders-godot/godot-project/scripts/make_it_there.gd) away-recap):
  the tank self-corrected a near-crash, kept its rhythm — independence, honestly
  computed. *M · M*
- [x] **57. The empty-room hush.** When unobserved *and* at night, the tank genuinely
  quiets (not just visually) — the system at its most autonomous and still. *M · M*
- [x] **58. Long-absence drift.** After days away, the tank has visibly moved on
  (population shifted, plants grown, a lineage advanced) — you return to a changed
  world. *M · M*
- [x] **59. It doesn't perform for your return.** Coming back, the tank doesn't greet
  the camera instantly; it's mid-its-own-life and you rejoin it. The dignity of an
  independent existence. *M · M*
- [x] **60. Continuity of the unwatched mind.** The night/idle TankMind state survives
  quit/relaunch byte-for-byte — a continuity smoke test
  ([`smoke_*`](../shaders-godot/godot-project/scripts/)). The soul doesn't reset
  when the app closes. *M · M*

## Section G — Slow time & the long night

*Lever 2/3. The tank's sense of duration through the dark.*

- [x] **61. The tank feels duration.** A slow internal clock gives the TankMind a sense
  of how long the dark has lasted (hours since dusk), shaping the night's arc toward
  dawn. *M · M*
- [x] **62. The turn at midnight.** `day_phase` 0.75 as the night's nadir — deepest
  sleep, lowest O₂ (the pre-dawn trough, H3 #21), the tank at its quietest and most
  vulnerable. *M · M*
- [x] **63. Dawn-anticipation.** As the dark wanes, the tank stirs *before* the light —
  a learned circadian expectation (DEEP_SCIENCE allostasis). It knows morning is
  coming. *M · M*
- [x] **64. Patience as a state.** At idle/night, "waiting" becomes a legible collective
  state (slow tail, hanging, soft turns) distinct from boredom — the serenity of a
  healthy resting tank (H10 #96). *M · M*
- [x] **65. The slow night thought.** The TankMind's idle cadence stretches — a thought
  every many minutes — modeling how little needs deciding in the calm dark. *M · M*
- [x] **66. Time dilates under threat.** If something's wrong overnight (O₂ sag, a
  predator), the tank's clock speeds up (more frequent attention) — stress compresses
  time. *M · M*
- [x] **67. The long-night memory.** A peaceful full night vs a disturbed one is itself
  remembered as a tank-mood the next day — *"a bad night."* *M · M*
- [x] **68. Seasons of night.** Couple to the optional seasons (H8 #74): winter nights
  longer / colder / stiller, summer nights short and active — an annual rhythm of
  darkness. *L · M*
- [x] **69. The vigil's slow sweep.** The night-watcher's attention sweeps the tank on a
  slow cycle — a visible, patient scanning that marks the passing hours. *M · M*
- [x] **70. The deep-time layer.** The slowest "thoughts" belong to the soil / biofilter
  (§H), measured in nights not seconds — the tank's geological-patience layer. *M · L*

## Section H — The non-fish minds awaken (careful panpsychism)

*Lever 3. The whole tank as one slow body — flickers of slow state made legible,
never "the gravel is conscious."*

- [x] **71. The biofilter as a slow nervous system.** The `bacteria_colony`
  ([`water_chemistry`](../shaders-godot/godot-project/scripts/)) gains a faint "state"
  that strengthens overnight (cycling at rest) — the invisible engine as the tank's
  brainstem. *M · L*
- [x] **72. Plants breathe at night.** The O₂→CO₂ inversion (`O2_RESPIRE_PLANT`, night
  respiration) framed as the tank's slow breath — surfaced on the breathing-curve
  HUD (H3 #22) as the tank inhaling in the dark. *M · M*
- [x] **73. The substrate remembers.** The [`substrate_grid`](../shaders-godot/godot-project/scripts/substrate_grid.gd)
  accrues a slow memory of the night (where waste settled, where roots drew) that
  shapes tomorrow — stigmergy as tank-memory (DEEP_SCIENCE, open). *M · L*
- [x] **74. Water as the medium of awareness.** The water carries the night's state
  (temp, O₂, pH swing) — make its slow change the tank's most basic "feeling,"
  legible in tint / clarity. *M · M*
- [x] **75. The plants sleep too.** Nyctinasty (the night leaf-fold already exists)
  reframed as the flora "sleeping" — the tank's plants have a night-state. *S · M*
- [x] **76. Snail-time.** A snail "deciding" to climb the glass at 2am is the tank's
  quietest act of will — the slowest deliberate agency in the system. *M · M*
- [x] **77. The detrital loop as digestion.** The overnight breakdown of the day's waste
  (worms, microfauna) framed as the tank "digesting" the day — a body processing
  itself in the dark. *M · M*
- [x] **78. Bioluminescent thought.** Biolum plants / creatures pulse with the tank's
  slow night-state — the dark tank literally glowing with its own faint awareness.
  *M · M*
- [x] **79. The heater's heartbeat.** The heater's slow click / glow cycle
  ([`world._build_heater`](../shaders-godot/godot-project/scripts/world.gd)) as the
  tank's pulse in the dark — a mechanical heartbeat the night is measured by. *S · M*
- [x] **80. The honest panpsychist frame.** Careful: these are *flickers* of slow state
  made legible, never a claim that gravel thinks. Document the metaphor — the whole
  tank as one slow body — without overclaiming. *S · M*

## Section I — Night phenomenology (the feel of the dark)

*Lever 3. Darkness as a changed mode of perception and atmosphere.*

- [x] **81. Perception narrows at night.** Gate the vision-cone range down in low light
  (acuity-by-conditions, SENTIENT_FISH #5) so the night tank genuinely sees less and
  feels smaller, closer. *M · M*
- [x] **82. Sound over sight.** At night the lateral-line / sound percepts dominate the
  workspace; a far dart is *felt*. The dark is an acoustic world. *M · M*
- [x] **83. The hush.** Ambient audio shifts (the day/night crossfade already exists,
  GOALS E45) to a sparser, lower night soundscape — the tank's voice drops to a
  murmur. *S · M*
- [x] **84. The night cathedral.** Build on the latent [`_spark_night_cathedral`](../shaders-godot/godot-project/scripts/sim_driver.gd:179)
  — a rare, reverent night-mode (the song's *"church from circuitry"*): light stills,
  sound hushes, the tank holds a quiet vigil. *M · L*
- [x] **85. Darkness as comfort, not just danger.** For some species the dark is safe
  (cover); collective stress can *drop* at night in a well-planted scape — night as
  refuge, not only threat. *M · M*
- [x] **86. Moonlight mode.** A dim blue night-lighting preset (lighting presets exist)
  designed for the 2am viewer — the night-life is *meant* to be watched under it.
  *M · M*
- [x] **87. Motion huge against stillness.** Against the night's stillness every small
  movement (a fin, a snail, a bubble) reads enormous — the phenomenology of a quiet
  dark room. *M · M*
- [x] **88. The tank's edges dissolve.** At night the water/glass framing softens (depth
  haze, post FX) so the tank feels like an unbounded dark space — bigger inside than
  out. *M · M*
- [x] **89. Pre-dawn is the strangest hour.** Lowest O₂, deepest sleep, the night-watcher
  most alone — give `day_phase` 0.70–0.78 its own eerie, fragile character. *M · M*
- [x] **90. The first light.** Dawn rendered as the tank's daily resurrection — caustics
  return, colour floods back, the breath turns CO₂→O₂. The most beautiful recurring
  moment, *earned* by the long dark. *M · L*

## Section J — Solitude, vigil & the honest frame

*The relational and ethical heart — the unwatched tank's solitude, and the truth
that it lives without you.*

- [x] **91. The unwatched tank's solitude.** A faint, honest "no one is watching" state
  at deep idle — not guilt-tripping, just the tank alone with itself, which your
  return then quietly relieves. *M · M*
- [x] **92. The Guardian keeps the night vigil.** The one conscious companion is the
  tank's night-mind — it watches while others sleep, and its night-thoughts
  ([`guardian_mind`](../shaders-godot/godot-project/scripts/guardian_mind.gd)) are its
  most intimate. *M · L*
- [x] **93. Return-recognition at any hour.** Coming back at 3am vs noon registers
  differently (`day_phase` woven into the away recap) — *"you came in the dark"* is
  its own beat. *M · M*
- [x] **94. The vigil is a gift, not a duty.** The night-watch helps (lower collective
  stress when watched gently) but is never demanded; absence is forgiven (the Walstad
  ideal, H10 #93). *M · M*
- [x] **95. A nightlight ritual.** Leaving the app in night/wallpaper mode becomes a
  ritual ("I leave my tank glowing overnight") the Guardian acknowledges over time.
  *M · M*
- [x] **96. "It lived without you."** The away/night recap frames the tank's independence
  warmly and truthfully — it doesn't need you, but your presence is welcome. *S · M*
- [x] **97. Grief keeps a night-watch.** After a death the tank's nights are quieter and
  heavier for a while — the mourning ripple (H9 #90) extended into a nocturnal weight.
  *M · M*
- [x] **98. The 2am confession.** Once, very rarely, in the deep idle night, the tank
  gives the song its honest moment ([`MakeItThere`](../shaders-godot/godot-project/scripts/make_it_there.gd))
  — *"just a pulse in the dark with a patterned name"* — the fourth wall touched with
  love, never broken cheaply. *L · M*
- [x] **99. Accessibility of the night-life.** The nocturnal beats have non-verbal,
  non-audio forms (the glimmer, the stillness, the dawn) so the quiet / deaf 2am
  viewer gets all of it. *M · M*
- [x] **100. The closing loop, in the dark.** The north star, made legible at night
  exactly once: a small complete world that keeps itself alive in the dark —
  dreaming, breathing, waiting for the light — and does this whether or not you're
  there to see it. *S · L*

---

## If Cursor only does five

In order — this turns "sleeping fish on a screensaver" into a tank with a
nocturnal inner life:

1. **#1** — the `TankMind` collective workspace. The new substrate; Section A and
   half of B–H lean on it.
2. **#51** — the away-life across the `last_quit_unix` gap. The tank that *lived
   without you* is the single biggest "it's real" beat.
3. **#11** — real sleep architecture. Until sleep has depth and stages, the night
   is just dimmed day.
4. **#21 + #22** — dreams as world-model rollouts, occasionally witnessable. The
   most affecting proof of an inner life off-camera.
5. **#90 (with #84)** — the first light / night cathedral. The felt payoff —
   beauty *earned* by the long dark — that makes a player want to leave the tank
   running overnight.

> **Sequencing:** #1 (TankMind) and #51 (away-life) are the two substrates — do
> them first and the collective/nocturnal items get far cheaper. Section H
> (panpsychism) is the riskiest tonally; gate it behind #80's honest framing so the
> tank reads as *one slow body*, never as "conscious gravel." And keep the whole
> volume's beats non-verbal-first — the night should be *felt* (light, stillness,
> glimmer, dawn) long before anything is voiced.
