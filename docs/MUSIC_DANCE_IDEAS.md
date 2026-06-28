# Music & Dance — 50 Deep Ideas (Pillars 6 & 7)

*Drafted 2026-06-26. Director's brief for choreography + musical intelligence.*

The dream: fish that **dance magically** — phrase-aware, anticipating the drop,
moving in formations with grace and intention — and a tank that **understands the
specific song** (ballet for ambient, frenzy for DnB, sway for lofi). Two pillars,
one doc: **6 — Choreography** (dancing *well*) and **7 — Musical Intelligence**
(understanding *this* track).

Format: **Effort** S/M/L, **Impact** S/M/L; checkbox-tracked; file:line pointers
(match by symbol if lines drift).

> **You already have two music systems — know them before building:**
> - **`music_reactive.gd`** analyzes *external* audio (Spotify preview / local
>   file) into a per-frame `_drive` dict — `bass, mid, high, energy, beat,
>   valence, danceability, tempo`
>   ([music_reactive.gd:56](../shaders-godot/godot-project/scripts/music_reactive.gd:56)).
>   Bands via `AudioEffectSpectrumAnalyzer` on the "MusicSync" bus
>   ([:322](../shaders-godot/godot-project/scripts/music_reactive.gd:322)); beat
>   = a naive energy-threshold + cooldown
>   ([:335](../shaders-godot/godot-project/scripts/music_reactive.gd:335)). It
>   pushes `fauna_behavior_mods()` to fish
>   ([:143](../shaders-godot/godot-project/scripts/music_reactive.gd:143)) and
>   `plant_sway_mult` / `light_fixture_mul` / `palette_overlay` / `bubble_rate_mult`
>   to the world.
> - **`ambient_audio.gd`** *generates* music from tank life and owns the real
>   musical structure: a phrase state machine (VERSE/BUILD/DROP/BREAKDOWN/CHORUS),
>   bars, BPM, chord root, scale/key, and PERSONAS
>   ([ambient_audio.gd:77](../shaders-godot/godot-project/scripts/ambient_audio.gd:77)).
>   Exposes `get_live_status()` (phrase state, bars-left, BPM, chord root) —
>   which the Sound Studio already reads.
> - **The Sound Studio** ([`sound_panel.gd`](../shaders-godot/godot-project/scripts/sound_panel.gd))
>   is a deep control surface: ~50 sliders, vibe PRESETS, mood/style/persona
>   dropdowns, a live spectrum visualizer + phrase readout, WAV recording, "nudge
>   phrase."
> - **Fish dance via** `_music_mods()`
>   ([fish.gd:2494](../shaders-godot/godot-project/scripts/fish.gd:2494)),
>   `_apply_music_beat_surge()`
>   ([fish.gd:2540](../shaders-godot/godot-project/scripts/fish.gd:2540)), and a
>   cross-tank sweep target with per-fish phase jitter
>   ([fish.gd:2507](../shaders-godot/godot-project/scripts/fish.gd:2507)).

---

## The three structural levers (read this first)

**Lever 1 — Two music brains that don't talk.** The generative engine knows the
*musical time* (bars, phrase, key, chord); the fish only consume the dumb
per-frame `_drive`. **Bridge them:** route the generative engine's structure into
the choreography layer, and unify both behind one `MusicContext`/clock so the
dance is source-agnostic (#1, #37). This single move unlocks 80% of the doc.

**Lever 2 — It's *reactive*, not *choreographed*.** Today the "dance" is
amplitude × energy with phase offsets + a beat-triggered cross-tank sprint
([fish.gd:2540](../shaders-godot/godot-project/scripts/fish.gd:2540)). There's no
vocabulary of moves, no formations, no anticipation, no easing-for-grace. Add a
**choreography layer** that plays *phrases* of eased, intentional motion off the
clock (#11–25). This is the gap between "twitches on the beat" and "moves
beautifully."

**Lever 3 — Your music isn't *understood*, and the Spotify path is fragile.**
External tracks get no bars/phrases/key/genre, and `tempo`/`valence`/
`danceability` come from Spotify's `audio-features` endpoint
([music_reactive.gd:598](../shaders-godot/godot-project/scripts/music_reactive.gd:598))
— which Spotify **deprecated for new apps (Nov 2024) and whose preview URLs were
removed.** So lean on **on-device analysis** for robustness (#26–37), treat
Spotify metadata as best-effort, and use the always-available generative engine
as the reliable spine.

---

# Pillar 6 — Choreography (dancing well)

## Section 6A — A musical clock & anticipation (the foundation)

- [x] **1. One MusicClock all dancers share.** A single source of `beat_phase`
  (0..1 within the beat), `bar_phase` (0..1 within the bar), `downbeat`, and
  `phrase_state`, fed by whichever source is live (generative `get_live_status()`
  today; external analysis later). Fish read the *clock*, not raw bands.
  *Foundation.* *M · L*
- [x] **2. Real beat phase, not a flag.** `_drive.beat` is a 1→0 decaying flag and
  `beat_phase` is just per-instance jitter
  ([fish.gd:2507](../shaders-godot/godot-project/scripts/fish.gd:2507)). Give every
  fish a true phase within the bar so motion can land *on*, *before*, or *between*
  beats. *M · L*
- [x] **3. Anticipate the beat (wind-up & release).** Fish coil/gather just before
  the downbeat and release *on* it — an eased curve that peaks with the kick, like
  the cat-wiggle before a pounce. Replaces the lagging post-beat burst. The core
  "it's dancing, not reacting" read. *M · L*
- [x] **4. Count bars on the external path.** Derive bar position from tempo + beat
  so even Spotify/file tracks have musical structure (today only the generative
  engine counts bars). Feeds the clock (#1). *M · M*
- [x] **5. Drop anticipation.** Read the generative engine's BUILD→DROP phrase
  state (`get_live_status().phrase_state_name`,
  [ambient_audio.gd](../shaders-godot/godot-project/scripts/ambient_audio.gd)) and
  have the school *build tension* through the build (gather, rise, tighten) then
  *explode* on the drop. The single most magical moment — and the data already
  exists; fish just don't read it. *M · L*
- [x] **6. Moves last a phrase, not a frame.** A choreographic move spans e.g. 4–8
  bars. Sequence one move per phrase so the dance has structure instead of
  per-frame jitter. *M · L*
- [x] **7. Quantize transitions to the grid.** Snap formation changes and sweep
  direction flips to bar / half-bar boundaries so they land *with* the music, not
  whenever a frame fires. *M · M*
- [x] **8. Tempo-scaled motion.** Slow track → languid wide arcs; fast track →
  tight quick moves. Scale the whole vocabulary by BPM so it always reads "in
  time." *S · M*
- [x] **9. Swing & groove feel.** Read the generative engine's `swing` / `humanize`
  (PERSONAS, [ambient_audio.gd:77](../shaders-godot/godot-project/scripts/ambient_audio.gd:77))
  and offset motion timing — a swung lo-fi track lilts lazily behind the beat; a
  straight trance track snaps on-grid. *M · M*
- [x] **10. Breathing school on calm sections.** Couple school expand/contract to
  the bar (inhale 2 bars, exhale 2) so even quiet music has a visible, musical
  pulse. *S · M*

## Section 6B — A vocabulary of moves & formations

- [x] **11. A named move library.** Define discrete parameterized moves — sweep,
  spiral, vortex, wall-bounce, V-formation, starburst, carousel, cascade — each a
  motion over a phrase. Today there's only "cross-tank sweep." The heart of
  choreography. *L · L*
- [x] **12. Choreographed formations.** Fish take formation slots (line, V, circle,
  grid) and *hold* them through a phrase, then transition. Reuse the boids
  formation-slot system but make slots choreographed, not just spacing. *L · L*
- [x] **13. The wave (Mexican-wave ripple).** A bob/turn that propagates through
  the school in sequence across an axis — cheap (phase = position) and instantly
  reads as intentional and beautiful. *M · L*
- [x] **14. Vortex / bait-ball on intensity.** High-energy sections form a rotating
  torus the school orbits (real fish do this). Reuse predator-balling tightness as
  a *dance* move triggered by energy + drop. *M · L*
- [x] **15. Call-and-response between groups.** Split the school (by species /
  personality / `lead_score`) into two choirs that alternate moves across bars —
  one sweeps on bar 1, the other answers on bar 2. The essence of dancing
  *together*. *M · L*
- [x] **16. Soloists & ensemble.** A high-`lead_score`/favorited fish breaks out as
  a soloist during the chorus while the rest hold formation; rotate soloists per
  phrase. Leverages existing leadership. *M · M*
- [x] **17. Easing & grace.** Replace linear/abrupt dance steering with eased curves
  (ease-in-out, anticipation, follow-through). The current beat-surge is a hard
  burst; grace is what makes it *beautiful*, not twitchy. *M · L*
- [x] **18. Bank & flourish into turns.** Fish roll/bank into dance turns
  (exaggerated vs natural swimming) so direction changes have flair. Reuse the bank
  pivot. *S · M*
- [x] **19. Depth as a stage.** Use the vertical axis deliberately — coordinated
  layer rises (curtain up), cascading falls — on musical cues, instead of mid/high
  → vertical jitter ([fish.gd:2516](../shaders-godot/godot-project/scripts/fish.gd:2516)). *M · M*
- [x] **20. Mirror & symmetry.** Pair fish or left/right tank halves to move in
  mirror symmetry during certain phrases — symmetry reads instantly as
  "designed." *M · M*
- [x] **21. Per-species dance signatures.** Tetras shimmer-and-dart, a betta does
  slow grand sweeps, cories do a low groove — each species dances to character
  (tie to `swim_pattern`). Today the response is uniform. *M · L*
- [x] **22. Personality in the dance.** Bold fish lead and improvise; timid ones
  stay in formation; gluttons break for food mid-number. The 5 traits shape
  choreographic *role* (ties to the sentient-fish doc). *M · M*
- [x] **23. Composed for the camera.** Orient/scale formations to read from the
  current camera angle (a V points at the viewer) — the dance is staged *for the
  watcher*. Synergy with Pillar 5 (camera as audience). *M · M*
- [x] **24. Graceful enter/exit.** Fish ease *into* dance when music starts and
  settle *out* when it stops, instead of the per-frame modifier snapping on/off.
  The transition itself should be lovely. *S · M*
- [x] **25. Shape the whole song as an arc.** Build → peak formation at the drop →
  relaxed denouement, so a track has a beginning/middle/end rather than constant
  intensity. Uses phrase state (#5) over the full duration. *M · L*

---

# Pillar 7 — Musical Intelligence (understanding this song)

## Section 7A — On-device analysis (so *your* music is understood)

- [x] **26. Robust on-device beat tracking + tempo.** Add an onset/autocorrelation
  tempo+downbeat tracker so local files (and any audio) get accurate BPM and bar
  phase without Spotify metadata. The reliable foundation for the whole external
  path (Lever 3). *L · L*
- [x] **27. Multi-band onset detection.** Separate kick / snare / hat onsets via
  sub-band flux so different hits drive different motions (kick = bass lunge, hat =
  shimmer). Today it's one combined beat flag
  ([music_reactive.gd:335](../shaders-godot/godot-project/scripts/music_reactive.gd:335)). *M · M*
- [x] **28. Section detection (verse/chorus).** Detect structural boundaries via
  energy/timbre novelty so phrase-aware choreography (6A) works on *your* tracks,
  not just the generative engine's. *L · M*
- [x] **29. Build & drop detection.** Spot risers (rising spectral centroid +
  energy ramp) and the drop, so drop-anticipation (#5) fires on external music —
  "it knew the drop was coming" for your own songs. *M · L*
- [x] **30. Key/scale detection → palette.** Chroma analysis to estimate key + mode;
  feed the color overlay
  ([music_reactive.gd:226](../shaders-godot/godot-project/scripts/music_reactive.gd:226))
  — minor = cooler/moodier, major = brighter. The generative engine already knows
  its key; give external tracks the same. *M · M*
- [x] **31. Genre/mood classification.** A tiny on-device classifier (or a heuristic
  from tempo + energy + spectral features + danceability) tags the track:
  ambient / lofi / DnB / orchestral / pop… *M · M*
- [x] **32. Genre → dance language.** The pillar's payoff: each genre selects a
  different choreography style — ambient = slow ballet & wide arcs; DnB = frantic
  schooling & scatter; lofi = lazy loose sway; orchestral = stately formations;
  pop = bouncy sync. Switches the move library (#11) + easing (#17) per genre.
  *M · L*
- [x] **33. Mood → emotional coloring.** Valence/energy set the tank's tone (bright
  bouncy major pop vs moody slow minor), affecting both motion quality and
  color/light together. *M · M*
- [x] **34. Dynamics → ensemble size.** Quiet intro = a few fish gently moving; full
  mix = the whole tank engaged. Scale *how many* fish dance with the track's
  dynamic envelope so dynamics read visibly. *M · M*
- [x] **35. Timbre → texture.** Bright/harsh timbre → sharp jittery motion + sparkle;
  warm/mellow → smooth flowing motion. Map spectral centroid/rolloff to motion
  sharpness. *M · M*
- [x] **36. Confidence-gated intelligence.** When analysis confidence is low
  (ambiguous track), fall back gracefully to simple reactive mode rather than
  guessing wrong. Honest degradation. *S · M*
- [x] **37. A unified `MusicContext`.** One object — `{tempo, bar_phase,
  phrase_state, section, key, mode, genre, mood, energy_env, onsets[]}` — that BOTH
  the generative engine and external analysis populate and ALL choreography +
  visuals consume. Makes the source irrelevant. *Foundation, pairs with #1.* *M · L*

## Section 7B — Performance, expression & the Sound Studio

- [x] **38. Choreography presets in the Studio.** Extend the existing persona/style
  PRESETS ([sound_panel.gd:118](../shaders-godot/godot-project/scripts/sound_panel.gd:118))
  with dance-style presets the player can lock — or auto-detect (#31). *M · M*
- [x] **39. A "showiness" dial.** Separate from sync intensity: how much fish
  prioritize *performance* vs natural behavior. 0 = subtle groove; 1 = full show.
  A taste knob in the Studio. *S · M*
- [x] **40. Healthy tank dances better.** Couple choreography quality to tank health
  — a thriving tank dances joyfully, a stressed one's dance is ragged. Ties the
  music payoff to ecological balance (H10 serenity). *M · M*
- [x] **41. The drop as a coordinated tank-wide flourish.** On a detected/generated
  drop, fire formation explosion + light flash + bubble burst + color pop + caustic
  surge **on the same downbeat**. Today these react independently — choreograph them
  *together*. *M · L*
- [x] **42. Inter-system choreography (the tank as one instrument).** Plants, lights,
  caustics, bubbles, and fish share the clock and play *complementary* parts (lights
  hit the downbeat, plants sway the off-beat, fish carry the melody) instead of all
  chasing the same energy. Bridges toward Pillar 8 (synesthesia). *M · L*
- [x] **43. Show the intelligence in the Studio.** Extend the live readout
  ([sound_panel.gd:358](../shaders-godot/godot-project/scripts/sound_panel.gd:358))
  to display *detected* structure for external tracks — bar phase, section, key,
  genre — so the player sees it working. *S · M*
- [x] **44. Capture the moment.** The Studio already records WAV
  ([sound_panel.gd:506](../shaders-godot/godot-project/scripts/sound_panel.gd:506));
  add synced video/gif capture of a great dance (ties to F12 photo + Pillar 5
  "moments"). Shareable magic. *M · M*
- [x] **45. Conduct the tank.** Like the existing "Nudge Phrase" button
  ([sound_panel.gd:539](../shaders-godot/godot-project/scripts/sound_panel.gd:539)),
  let the player trigger a move — tap for a wave, a vortex, a formation — so you can
  *conduct*. Playful and delightful. *M · M*
- [x] **46. Per-species channel routing.** Route bands/instruments to species
  (tetras → highs, plecos → bass) so different fish embody different parts of the
  music. The `music_influence_*` flags in `tank_config.gd` are the foundation. *M · M*
- [x] **47. Life events on the downbeat.** Spawns/hatches that land near a downbeat
  get a choreographic emphasis — the tank's life syncs to the music. Subtle magic.
  *S · M*
- [x] **48. A musical (predictive) beat tracker.** Improve the naive threshold
  detector ([music_reactive.gd:335](../shaders-godot/godot-project/scripts/music_reactive.gd:335))
  with predictive tracking so motion stays locked to the grid through quiet
  passages / missed beats — dancing in time, not stuttering. *M · L*
- [x] **49. Latency compensation.** Account for audio output latency + the smoothing
  lerps so visible motion lands *on* the beat, not ~100ms behind. A calibration
  offset — critical for "looks tight." *S · L*
- [x] **50. The "wow" tuning pass.** Curate reference tracks across genres and tune
  the whole pipeline until it looks *magical* on real music; ship a bundled demo
  track + "demo dance." The polish that separates "neat" from "whoa." *M · L*

---

## If Cursor only does five

The two foundations first (**#1 MusicClock** + **#37 MusicContext** — they bridge
the two brains), then:

1. **#5** — drop anticipation reading the generative phrase state (huge magic,
   mostly *wiring data that already exists*).
2. **#11** — the named move library (turns reaction into choreography).
3. **#17** — easing & grace (the literal difference between twitching and "moves
   beautifully").
4. **#32** — genre → dance language (the Pillar-7 payoff the player feels).
5. **#26** — on-device beat tracking (makes *your own* music work robustly, free of
   the deprecated Spotify path).

> **Build order:** wire the clock/context (#1, #37) and route the generative
> engine's existing structure into the fish *first* — that alone makes the
> tank-generated music danceable with real phrasing, today, with no new DSP. Then
> add on-device analysis (#26–30) so external tracks get the same intelligence.
> Layer the move vocabulary + easing (#11–25) on top. Save the genre/mood mapping
> (#31–35) and the polish pass (#50) for once the spine is solid.
