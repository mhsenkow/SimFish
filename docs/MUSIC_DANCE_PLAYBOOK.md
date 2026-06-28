# Fish Dance Playbook — 50 Specific Recipes

*Drafted 2026-06-26. The choreographer's playbook — companion to
[MUSIC_DANCE_IDEAS.md](MUSIC_DANCE_IDEAS.md).*

That doc was the architecture (the clock, the move library, genre detection) — and
Cursor built it: `MusicContext` (`/root/MusicContext`) + `MusicChoreography`
([music_context.gd](../shaders-godot/godot-project/scripts/music_context.gd),
[music_choreography.gd](../shaders-godot/godot-project/scripts/music_choreography.gd))
now own a real beat/bar clock, moves, formations, and `compute_dance_target()`.

**This doc is the *content* on top of it** — specific swimming motions, exact
"musical feature → movement" mappings, and the casting-by-color/species system —
to get the dance from "sorta responds" to **Little Mermaid musical number**.

**The "fits every song" principle:** every recipe maps motion to *continuous
universal features* that **every** track has (tempo, band balance, energy,
beat-phase, brightness) and casts fish into *parts* by their looks. Same rules,
different song in → different dance out. No per-song authoring.

Format: **Effort** S/M/L · **Impact** S/M/L; checkbox-tracked; real symbols cited.

> **Two gaps this doc fills (found by reading the rig):**
> - **The body locomotion isn't musical yet.** The swim animation
>   (`_swim_phase`, `_tail_pivot.rotation.y`, fins) is driven by *speed*
>   (`wag_freq = 2.5 + speed*5.5`, [fish.gd ~5503](../shaders-godot/godot-project/scripts/fish.gd:5503));
>   the audit notes "no music-specific modulation there yet." Section 1 fixes this.
> - **No casting by appearance.** `compute_dance_target()` treats fish uniformly.
>   Per-fish traits exist and go unused for music: `base_color`, `accent_color`,
>   `color_vibrancy()`, `species`, `swim_pattern`, `growth_factor` (size),
>   `mouth_orientation`, `home_y`/`preferred_y`, `lead_score`, `finnage`,
>   `eye_spot`. Section 2 casts with them.
>
> Available to read every frame: `MusicContext.get_clock()` →
> `{beat_phase, bar_phase, downbeat, phrase_state, tempo}` and `get_context()` →
> `{bass, mid, high, beat, energy, energy_env, valence, brightness, centroid,
> timbre_sharp, genre, mood, swing, drop_flash, confidence}`.

---

## Section 1 — Make the *swimming itself* musical (lock locomotion to the beat)

The single most impactful section: the fish's body becomes an instrument.

- [x] **1. Lock the tail-beat to tempo.** Drive `wag_freq`
  ([fish.gd ~5503](../shaders-godot/godot-project/scripts/fish.gd:5503)) from
  `get_clock().tempo` when music is active — e.g. one full tail stroke per beat —
  instead of `2.5 + speed*5.5`. Blend toward it (don't hard-snap) so motion stays
  smooth. The fish's *locomotion* now rides the BPM. **The headline recipe.** *M · L*
- [x] **2. Subdivide the stroke by size.** Big fish (`growth_factor` high) wag at
  half-time (1 stroke / 2 beats), small fish at double-time (2 / beat). The school
  self-organizes into a rhythm section + a hi-hat shimmer. Maps size → register.
  *M · L*
- [x] **3. Downbeat body-pulse.** On `downbeat`, every fish does one emphasized
  full-amplitude `_tail_pivot` stroke + a tiny forward lunge — the visible "1" of
  the bar. *S · M*
- [x] **4. Kick → body thump.** On a bass transient (`bass` onset), a quick
  compress/extend of `_body_mid_pivot.scale` + a forward surge — the fish thumps
  with the kick. *S · M*
- [x] **5. Snare/clap → tail-flick accent.** On a mid/snare onset, a single sharp
  `_tail_pivot.rotation.y` whip + a small heading jink. Reads as the backbeat.
  *S · M*
- [x] **6. Hi-hat → fin flutter.** Map `high` to pectoral/dorsal flutter rate
  (`_pec_*_pivot`, `_dorsal_pivot`,
  [fish.gd ~5651–5675](../shaders-godot/godot-project/scripts/fish.gd:5651)) so
  cymbals make fins shimmer. *S · M*
- [x] **7. Bass sustain → undulation amplitude.** Smoothed `bass` swells whole-body
  wave amplitude (`tail_amp` / `wag_amp_extra`) so a deep bassline makes fish
  undulate languidly. *S · M*
- [x] **8. Glide on rests / held notes.** When energy dips between hits, fish stop
  beating and *coast* (pause `_swim_phase` advance, extend glide), then resume on
  the next hit. Silence becomes stillness — the musical breath. *M · M*
- [x] **9. Banking flourish on accents.** Push the existing `dance_bank` hook
  ([fish.gd ~5454](../shaders-godot/godot-project/scripts/fish.gd:5454)) harder on
  strong onsets so fish *roll into* dance turns balletically. *S · M*
- [x] **10. Swing the stroke.** Apply `_ctx.swing` to tail-beat timing (delay the
  off-beat wag) so a swung lo-fi track makes the swimming itself lilt. *M · M*

---

## Section 2 — Casting: musical parts by color, species, size & depth

The orchestration — turn a uniform school into a cast. **This is the
color/species idea.**

- [x] **11. Assign a `_music_role` per fish.** Derive a stable role once (at spawn /
  first dance) from traits: size → register, color → band, species → section,
  `lead_score`/vibrancy → soloist. Store it; everything below reads it. *Casting
  foundation.* *M · L*
- [x] **12. Visual EQ by water column.** Route `bass` → bottom dwellers, `mid` →
  mid-water, `high` → top dwellers (via `home_y`/`preferred_y`). The tank becomes a
  literal spatial equalizer — lows rumble along the floor, highs sparkle at the
  surface. Gorgeous, legible, fits every song. *M · L*
- [x] **13. Color = frequency band (the color organ).** Map `base_color` hue to a
  band: warm/red fish react to bass, green to mids, blue/cool to highs. Each
  frequency lights up *its color* of fish. *M · L*
- [x] **14. Size = register.** Big fish carry slow low parts (grand half-time
  sweeps), small fish the fast high parts (flicks, double-time). From
  `growth_factor`; pairs with #2. *S · M*
- [x] **15. Species = orchestra section.** Each `species`/`swim_pattern` gets a
  signature part + move: tetras = shimmer ensemble on highs; corydoras = bass
  groove on the floor; hatchetfish = treble skimming the surface; betta/gourami =
  the slow melodic lead. *M · L*
- [x] **16. Warm vs cool = two choirs.** Split the cast by hue temperature into
  Choir A / B; they take the existing call-and-response across bars. Color makes
  the two voices visually obvious. *M · M*
- [x] **17. Vivid fish = soloists.** Highest `color_vibrancy()` fish are cast as
  soloists for choruses/drops (break formation, take center, hit the melody). The
  prettiest fish naturally lead the number. *S · M*
- [x] **18. Finnage = expressiveness.** Long-finned fish (`finnage`/
  `fin_length_factor` high) get the slow, sweeping, flourish-heavy moves (fins read
  beautifully in slow motion); compact fish get snappy staccato moves. *S · M*
- [x] **19. Mouth orientation = staging level.** Superior-mouth fish hold the high
  surface line, inferior-mouth the low floor line (`mouth_orientation`) —
  reinforces the visual-EQ vertical staging. *S · S*
- [x] **20. Corps vs principals.** Tight-schoolers ("school") do synchronized
  formation work; loners/hover species do independent expressive solos. The number
  has both a corps de ballet and principals. *M · M*
- [x] **21. `lead_score` = section leaders.** The top-`lead_score` fish in each
  section leads its sub-group's move; others follow a half-beat behind (a
  follow-the-leader lag that reads as coordination). *S · M*
- [x] **22. Personality flavors the part.** Bold fish improvise extra flourishes,
  timid fish stay locked in formation, gluttons break for food then snap back —
  character within the choreography (boldness/calm/gluttony in `traits`). *M · M*

---

## Section 3 — Specific staging numbers (the Little Mermaid devices)

Concrete named numbers, each with a musical trigger so it fires on any song.

- [x] **23. The fountain.** On a BUILD, the cast gathers low + center; on the DROP it
  erupts up and out like a firework. Uses `phrase_state` + `drop_flash`. The
  showstopper. *M · L*
- [x] **24. Kickline.** A `line` formation where fish bob up/down *in sequence* on
  the beat (phase = slot index) — a Rockettes kickline. *M · M*
- [x] **25. Baton-pass wave.** Make the existing `wave` move cast-aware: each fish
  *flicks its tail* as the wave front passes it, so it reads as motion handed down
  the line. *S · M*
- [x] **26. Stratified carousel.** Sections orbit center at different radii/speeds —
  bass slow inner ring, treble fast outer ring — a rotating music box. Extends
  `carousel`. *M · M*
- [x] **27. Shape schooling.** On a chorus, the cast briefly forms a simple readable
  shape (heart, star, ring) via formation slots, then dissolves. Gate on
  `phrase_state == "chorus"`. *L · M*
- [x] **28. Spotlight soloist.** During a melodic chorus, slow/dim the ensemble and
  let the soloist (#17) trace the melody contour center-stage while others hold a
  soft backing sway. *M · L*
- [x] **29. Mirror pairs.** Use the `mirror` formation to pair fish across the
  tank's center axis in exact symmetry through a phrase. Instantly reads as
  "designed." *M · M*
- [x] **30. The V flyover.** A V/chevron sweeps across the tank on a sustained
  phrase (migrating-birds style), point fish leading — and it frames well from the
  camera. *M · M*
- [x] **31. Stratified tornado.** Cast-aware `vortex`: bass fish form the slow wide
  base, treble fish spiral fast up top — a layered waterspout on peak energy. *M · M*
- [x] **32. Counterpoint lane-swaps.** Two sub-groups cross *through* each other in
  opposite lanes on alternating bars — visual counterpoint, like two melodic lines
  weaving. *M · M*
- [x] **33. Curtain rise/fall.** Tie the `curtain` move to phrase entries/exits: the
  cast rises as a curtain on the intro, falls on the outro. Frames the song. *S · M*
- [x] **34. Cascade on a descending fill.** Fish drop top→bottom in sequence on a
  descending riser (`cascade`), then swim back up. Maps pitch descent → vertical
  descent. *M · M*
- [x] **35. Freeze-frame on the break.** On a BREAKDOWN/rest, the whole cast freezes
  mid-pose (hold position + stop wag) for the silence, then snaps back on the
  return. Pairs with #8. *S · M*
- [x] **36. The bow.** When the track ends, the cast does a graceful settle — slow
  descent + fin-spread "bow" toward the camera — then disperses to natural
  swimming. The number has an *ending*. *M · M*

---

## Section 4 — The "fits every song" engine

- [x] **37. The universal feature→motion table.** One documented mapping every move
  respects: `tempo`→stroke rate · `bass`→undulation amp + low-cast · `mid`→melody
  cast · `high`→fin flutter + treble cast · `energy`→ensemble size & speed ·
  `beat_phase`→anticipation easing · `valence`→posture openness ·
  `brightness`→height. Because these exist for *every* track, the dance always
  fits. *The spec — write it once, every recipe obeys it.* *M · L*
- [x] **38. Always-on baseline groove.** Even on ambient/quiet/beatless tracks, a
  gentle tempo-locked sway + soft sectional drift so the tank is *never* visually
  dead. Floor `dance_blend` at a small value when music is active. *S · M*
- [x] **39. Energy → how many fish dance.** Quiet intro = a few fish gently moving;
  full mix = the whole cast engaged. Scale participation by `energy_env` so the
  stage visibly fills up. *M · M*
- [x] **40. Intensity floor & ceiling.** Clamp motion so a whisper-quiet song still
  moves visibly and a wall-of-noise song doesn't dissolve into chaos — every genre
  looks *good*, not just loud ones. *S · M*
- [x] **41. Brightness → height.** Map `centroid`/`brightness` to the cast's average
  height (bright song = rise + sparkle near the top; dark song = sink + brood low).
  A whole-tank mood shift per song. *S · M*
- [x] **42. Genre auto-styles the cast.** Hook `GENRE_PROFILES`
  ([music_choreography.gd](../shaders-godot/godot-project/scripts/music_choreography.gd))
  to also pick the casting emphasis: DnB → treble frenzy dominates; dub → bass cast
  leads; orchestral → full sectional formations. Same fish, different number. *M · M*
- [x] **43. Latency compensation.** A small lead-time offset so the *visible*
  stroke/accent lands ON the beat, not ~100ms behind (audio out + smoothing lag).
  One tunable in MusicContext. Critical for "tight." *S · L*
- [x] **44. Confidence-gated showiness.** When `confidence` is low, fall back to the
  baseline groove (#38) rather than commit to wrong moves — never look like it's
  dancing to the wrong song. *S · M*

---

## Section 5 — Polish & the "wow" details

- [x] **45. Color pulse on *its* beat.** Reuse `palette_overlay` / `fauna_scale_pulse`
  so each cast flushes color on its band's hit — bass fish glow on the kick, treble
  fish flash on hats. Synced color + motion. *S · M*
- [x] **46. Fin-flare on accents.** On strong accents, briefly flare fins wide (the
  existing fin-flare/`mood` path,
  [fish.gd ~5662](../shaders-godot/godot-project/scripts/fish.gd:5662)) — a visual
  "ta-da." *S · M*
- [x] **47. Eye-spot / accent flash.** Fish with `eye_spot` or a strong
  `accent_color` flash it on downbeats — sparkle keyed to the music. *S · S*
- [x] **48. Bubble punctuation on the drop.** Tie `bubble_rate_mult` to `drop_flash`
  so the drop gets a coordinated bubble burst alongside the fountain (#23). *S · M*
- [x] **49. Motion trails in fast passages.** A subtle afterimage on high-speed dance
  moves (optional shader) so frantic sections read as energetic streaks, not blur.
  *M · S*
- [x] **50. The hero-shot nudge.** During a peak formation (drop/chorus), gently bias
  the auto-orbit camera to a flattering angle that frames the shape for the watcher
  (ties to Pillar 5 "composed for the camera"). Make the magic moment *seen*. *M · M*

---

## If Cursor only does five

The casting foundation (**#11**) + the mapping spec (**#37**) first — they're the
substrate — then:

1. **#1** — lock the tail-beat to tempo (the swimming itself becomes musical; the
   literal thing you asked for, and the biggest single visible change).
2. **#12** — visual EQ by water column (the color/species idea made spatial —
   bass on the floor, treble at the surface).
3. **#15** — species = orchestra section (each kind of fish dances to character).
4. **#23** — the fountain (build→drop showstopper; the "whoa" moment).
5. **#38** — always-on baseline groove (guarantees it looks alive on *any* song).

> **Why this fits every song:** #37 maps motion to features every track has, and
> #11–15 cast fish to *roles* that those features drive. A dub track → the bass
> cast leads a slow floor groove; a DnB track → the treble cast erupts in a
> surface frenzy — automatically, from the same code. That's the "Little Mermaid
> number that fits any song."
