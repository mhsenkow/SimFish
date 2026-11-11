# Sentience X — The Loom That Thinks

*500 ways to give the aquarium a voice, a sense of its own state, and a mind
you can watch.* Drafted 2026-11-02 against master `5843260` (v0.2.52: living
motion, GPU fauna skinning).

**The brief.** The motion pass is done. Take a holistic look and improve the
sentience of the aquarium in three directions:

- **vocalization**: the fish's voices
- **awareness of state**: the fish and the tank knowing their own condition
- **the metaphor of this being an actual mind**: the whole tank, playing out.

**Format.** Effort **S** (≤2 h) / **M** (half-day) / **L** (day+) · Impact **S / M / L**.

- **[V]** means verified by reading the code in this pass (2026-11-02): the defect is real at the cited symbol.
- Unmarked pointers come from a four-way code audit run the same day.
- Line numbers drift, so follow symbols.
- Every `*.gd` path is in `shaders-godot/godot-project/scripts/` unless prefixed `dev/`, `data/` or `shaders/`.
- One idea → one commit → headless smoke → tick the box (`.cursor/rules/idea-docs-workflow.mdc`).

**Scope.** This doc deliberately does *not* rebuild the cognition stack, the
LLM tier ladder, comms UX, or the Preoccupation construct. It cross-references
them (#491). It is mostly about the *edges* of the mind: where the state
becomes sound, where the world becomes feeling, and where the mind becomes
something a player can see.

---

## The holistic read (read this first)

The motion pass gave every fish a body that can express. The previous
sentience volumes gave every fish a mind: a global workspace with ignition,
DDM deliberation, expected-free-energy action selection, a recurrent world
model, episodic memory with sleep schemas, a felt-self layer, signals,
contagion, theory of mind, and an eval harness. A tank-mind exists above them.

What a player actually meets is far narrower: **the mind is deep, but at its
edges it is mute, numb and unseen.**

**1. Mute.** Real fish are noisy: gobies and cichlids drum their swim
bladders, corydoras and plecos stridulate, gouramis croak, puffers grind.
This tank is acoustically silent.
- The only creature "voice" is a pre-rendered babble keyed to body size and boldness, with no mood, arousal or fear input (`tank_voice_audio.gd:168-169`). It is mono, at most two at a time, rides the music synth bus and is gated by the music toggles.
- The four inter-fish signals (`fish_signals.gd`) are neither audible nor visible.
- Guardian lines, follow-mode thoughts and follow-ups make no sound at all.
- With the AI off, which is the default, a single keeper reply freezes the global voice cooldown for the rest of the session (#1).

**2. Numb.** Chemistry is modelled richly but reaches the fish as scalar
stress, never as perception.
- No water variable produces a workspace bid.
- Oxygen is dropped before it reaches expected free energy (#177).
- The felt gills feel nitrite but not thin water (#178).
- Homeostasis never ticks in live play (#176).
- Nitrate, CO₂, temperature, flow, season and crowding are never *felt*.
- Only improvement is detected, never worsening (#181).
- The tank computes "how am I doing" four separate times and never over time.

**3. Unseen.** The tank-mind surfaces as an unlabelled two-tone chime, a
mood tint pinned at the shader's clamp ceiling (#371), and lines the player
must type to get.
- The Mind panel's most human lines never render (#2).
- The spark shaders were built and never called (#193).
- The dawn spark can't fire (#355), the dawn note fires every tick (#369), and the elegy never ends (#370).
- The new motion toolkit has exactly the hooks a mind needs: gaze priorities for threat, food, mate and rival; an event bus; staging; a breath oscillator; a personality seed; an envelope. The mind drives almost none of them.

**The metaphor is also the design method.** The game is called *walstad loom*.
A loom holds the **warp**, slow, persistent threads under tension (plants,
substrate, chemistry, the light cycle). The shuttle carries the **weft**
across (the fish). The **pattern** exists only in the interlacing; here it
is the tank's attention. Treat that as a spec. Every tank system gets a named
role in the mind (#326), and every role gets a body in sound, light and
motion, always with the computed thing named.

---

## The three structural levers

**Lever 1 — One utterance (Part One).** Every vocal act becomes one `Utterance`
record (#22): a drum, a click, a babble, a word, the tank's breath. It carries
the speaker's felt state and is emitted on the motion bus. Audio renders it
with species timbre and prosody, the pose runtime animates it, text shows it
if it has words, and neighbours hear it. Four half-built paths become one
event that many systems hear.

**Lever 2 — One tank body (Part Two).** `TankVitals` (#301) replaces four
disagreeing tank-health models with one: organs, normals, history rings,
trends, forecasts and confidence. Fish get felt channels and a `water_sense`
workspace bid (#185) in one shared felt vocabulary (#201). Awareness then
flows perception → attention → behaviour → voice, in that order.

**Lever 3 — The mind gets a stage (Part Three).**
- Mind events go on the motion bus (#354).
- TankMind ignition travels as a wave through `MotionField` (#352).
- Mind moments are staged with `MotionStaging` (#353).
- A **Mind Lens** (#363) overlays focus, firings, connectome, memory and felt water.
- The Loom Anatomy (#326) tells every system which organ it is.

---

## If Cursor only does ten

1. **#1 + #2 + #193 + #369**: the four repairs that unblock the voice cadence, the Mind panel, the spark shaders and the tank's night count. All S.
2. **#176 + #177 + #178**: homeostasis ticking live, oxygen in EFE, felt gills that feel oxygen. The body starts to *know* its water.
3. **#22 Utterance**: the one voice record, plus #5 (every path makes a sound).
4. **#6 Creature bus**: creature sound gets its own bus and slider, independent of the music.
5. **#26 → #27/#28 Repertoire**: corydoras click, gobies and cichlids drum, gouramis croak. The tank stops being silent.
6. **#76 Felt state enters the voice**: prosody from valence, arousal, stress and fatigue.
7. **#301 TankVitals** with **#251** history rings: one tank body, remembered over time.
8. **#185 Water-sense bid** + **#196 the eyes go where the mind is**: awareness that wins attention and shows in the gaze.
9. **#354 Mind events** + **#352 ignition wave**: the tank noticing something becomes visible.
10. **#363 Mind Lens** (first layer: focus spotlight #351 + firings #335): watch the loom think.

**Sequencing.** Phase 0 repairs (#494) → Phase 1 foundations (#495) → Phase 2
body speaks and feels (#496) → Phase 3 meaning, time and self-knowledge (#497)
→ Phase 4 the mind made visible (#498). The honesty gate and blind reviews run
at every phase boundary (#499).

---

## Verified defects (Phase 0)

| # | Defect | Where |
|---|---|---|
| 1 | Global voice cooldown never decays with the AI off, so fish stop starting conversations after the first reply | `ai_director.gd:245`, `mind_conversation.gd:307` |
| 2 | Mind panel reads MindState names off a raw Fish; the thought, ignition, Expectations and Outlook rows are blank | `mind_panel.gd:181`, `mind_legible.gd:150, 290`, `fish.gd:332, 446` |
| 3 | "Energy" bar shows arousal | `mind_legible.gd:228` |
| 9 | Potato-tier bed synthesizes at 44.1 kHz time, plays at 22.05 kHz (half speed) | `potato_ambient_bed.gd:6, 25` |
| 96 | Tank `mood_arousal` tracks mean *stress*; real arousal sits unused | `tank_mind.gd:288-289` |
| 176 | `FishHomeostasis.tick` runs only in the eval and the poke harness | `mind_eval.gd:589`, `poke_harness.gd:183` |
| 177 | Oxygen is dropped from EFE `preferred_error` | `mind_active_inference.gd:86-93` |
| 178 | Felt gills read only the nitrite penalty, not dissolved O₂ | `fish_protoself.gd:45-47`, `fish.gd:4613` |
| 179 | `water_feel` bid condition is always true | `tank_mind.gd:194` |
| 182 | `gut_fullness` stores hunger (naming trap) | `fish_protoself.gd:48` |
| 193 | `FishSparkExpression.tick` is never called, so mind-driven shaders never apply | `sim_driver.gd:4329`, `fish_spark_expression.gd:267-272` |
| 355 | Dawn spark's daylight window is unreachable | `night_watch_extras.gd:221`, `sim_driver.gd:3168-3171` |
| 368 | Ambient breath reads a nonexistent `_sim.calm` | `main.gd:8662-8664` |
| 369 | `_note_dawn` fires every tick across its window | `tank_mind.gd:94-99` |
| 370 | Elegy flag `recent_loss` is never cleared | `make_it_there.gd:503` |
| 371 | Tank mood multipliers are *added* to music's, pinning colour at the clamp | `music_context.gd:845-847, 858-860` |

From the audit, not re-verified: #4 (model upgrade re-emits the line),
#373 (unreachable predawn ignition branch), #180 (three different ammonia
measures).

---

## What already exists (don't rebuild)

- **The mind stack.**
  - Workspace and ignition (`global_workspace.gd`), DDM, EFE action selection (`mind_active_inference.gd`), the GRU world model (`mind_world_model.gd`).
  - Episodic memory with sleep schemas (`episodic_memory.gd`) and learned beliefs (`fish_learned_mind.gd`).
  - The felt-self layer: protoself, core affect, qualia, felt-now, binding, volition.
  - Signals, contagion, theory of mind, and the eval harness (`mind_eval.gd`, 14/14 plus honesty).
- **The voice ladder.**
  - Template → in-process SmolLM2 → embedded → Ollama, with grounding, validators and streaming retraction.
  - The Guardian; the tank's "we" voice; questions; chatter; conversation state; the lexicon.
- **The tank mind.**
  - TankMind's workspace, ignition, mood, self-summary and stream (`tank_mind.gd`), and ColonyMind (`colony_mind.gd`).
  - The night watch, cathedral and vespers; the Chronicle in "we"; the "Us" hymn.
  - The palette mood overlay and the mood-driven pad bed.
- **The motion toolkit (v0.2.52).**
  - Fully wired: gaze (`motion_gaze.gd`); the pose runtime plus library (13 channels, `data/motion/poses.json`); anticipation (`fish_anticipation.gd`); spring, chain, wave, field and school.
  - Used only for body events: staging and the event bus.
  - Built but unused: breath, personality, envelope and composer.
- **`tank_voice_audio.gd`.** FM babble, the tank breath and six bloop kinds, rendered on workers, with an LRU cache of 16.

# Part One — The Voice (1–175)

A fish's voice has three layers, and this part builds them in order:
**sound** (the biological repertoire: drums, clicks, croaks, rasps),
**call** (a sound that means something to another fish), and **word** (the
rare line of text). Today only the third exists, and its sound is a
pitch-by-size bloop. The rule for everything below: *the voice is the state,
heard.* No sound may be prettier, calmer or more certain than the mind that
made it.

---

## §1 Repair and free the voice that exists (1–25)

- [x] **1. [V] Tick the global voice cooldown when the AI is off.** (S·L) `MindNarrator._global_voice_cd` only decays in `AIDirector._process` (`ai_director.gd:245`), and `set_process(enabled)` (`:208`, `:329`) switches that off whenever `ai_enabled` is false, which is the default (`tank_config.gd:314`). `MindConversation.note_reply` calls `mark_voice_spoke()` on every keeper reply, templates included (`mind_conversation.gd:307`). After the first reply, `global_voice_ready()` stays false for the rest of the process, so fish never start a conversation (`:178`), never say goodbye (`:198`) and never get a model reply (`:273`). Tick it from an always-on owner, such as the SimDriver tick or a tiny autoload. Smoke: AI off, one reply, advance 20 s, expect `global_voice_ready() == true`.
- [x] **2. [V] Make the Mind panel read the fish it is showing.** `mind_panel.gd:181-190` hands `MindLegible` the live `Fish`. `MindLegible._field` does `state.get(key)` with MindState names (`mind_legible.gd:150, 280-294`), but Fish stores them underscored (`_current_thought` `fish.gd:332`, `_thought_stream` `:446`, `_workspace_ignited`, `_dream_wisp`…). The results:
  - The quoted thought, which the file itself calls "the single most humanising line", never renders.
  - The dreaming headline, ignition, Expectations, Outlook and meta rows never render.
  - "Asleep" never appears.
  - The name falls back to the species.

  Pass `MindState.sync_from_fish(f)` (or an adapter). `smoke_mind_legible.gd:10-12` passes because it builds a fake object with the plain names; make it use a real `Fish`.
- [x] **3. [V] The "Energy" bar shows arousal.** (S·S) `mind_legible.gd:228`. Bind it to `energy` (`fish.gd:619`) and add a separate "stirred" bar if arousal is wanted.
- [ ] **4. A model upgrade replaces the line; it is not a second line.** (S·M) The template is emitted first. When the model upgrade lands, `sim_driver.gd:505-509` re-emits `fish_thought_spoke`, so the player gets a second strip and a second babble. Give each utterance an id and make the upgrade an in-place replace (text cross-fades, no new sound).
- [ ] **5. Every speech path makes a sound.** (S·M) These are silent today:
  - Guardian lines (`main.gd:4763-4815`).
  - Follow-mode thoughts (`main.gd:4467-4471, 5869-5888`).
  - Fish follow-ups (`main.gd:5227-5243`).

  Only keeper replies and intent answers babble (`main.gd:4834-4850, 5201-5203`). Route all of them through one `speak()` that always produces a kind-appropriate vocal act: a murmur for an inner thought, babble for an addressed line, the Guardian's motif for the Guardian (#58).
- [ ] **6. A creature bus that does not belong to the music.** (S·L) Voices play on `Music_Synth` (`tank_voice_audio.gd:59`). They inherit the synth reverb, they are gated by `music_enabled` and `music_events_enabled` (`ambient_audio.gd:633-675`), and they are mixed at `music_volume × music_event_volume − 12 dB`.
  - Add `Creatures` and `Voice` buses to `default_bus_layout.tres`. Today it has only Master, Music, Music_Drums, Music_Synth and Music_Air.
  - Give them a short "small room of water" reverb.
  - Add their own slider beside the "Creature & plant events" checkbox (`sound_panel.gd:655`).

  A player who turns the music off must still hear the fish.
- [ ] **7. A priority voice allocator instead of a hard 2+2.** (M·M) Today the limits are 2 voices, 2 bloops, a queue of 3, a stale age of 2.5 s and minimum gaps of 0.22 s / 0.9 s (`tank_voice_audio.gd:27-32`, 4 mono players at `:33, 58-65`). Chatter therefore collapses into generic bloops (`main.gd:5518-5520`). Use 6–8 voices and steal by `(on-screen size, salience, age)`. Never steal the Guardian or a reply that is mid-phrase. Bloops and calls share the pool, so a busy tank thins the quiet sounds first.
- [ ] **8. The typewriter and the babble are one act.** (S·M) The strip reveals at 34 ms/char (`main.gd:304, 4954-5000`). Babble is a separate one-shot with 2–7 syllables by line length (`tank_voice_audio.gd:191-212`). Align them: one syllable per word, onset on the word's first glyph, so the eye and the ear land together.
- [x] **9. [V] Fix the potato bed's sample-rate mismatch.** (S·S) `potato_ambient_bed.gd:6, 26` computes time as `/44100` but plays at 22050 Hz (`ambient_audio.gd:13`). The low-tier bed therefore runs at half speed, an octave down. It is the soundscape the weakest devices hear.
- [ ] **10. Decide `PLAYER_SENSING_VOICE_ENABLED`.** (S·S) It is `true` while its comment says "disabled until sensing ships" (`mind_narrator.gd:20-21`), and the mic is a stub: `set_mic_rms(0.0)` is the only call (`settings_panel.gd:1614`, `keeper_input.gd:375-385`). Gate it off, or rewrite the comment to say what it actually senses (gaze and cursor).
- [ ] **11. Unfollowed thoughts get a place, not just an inbox row.** (M·M) An unfollowed fish's thought goes to inbox history only (`main.gd:4847, 10010-10054`). Give it a 2-px ripple or bubble glyph at the fish, which rises and pops with a tiny sound. Clicking it reads the line. No toast.
- [ ] **12. The "…" Label3D becomes a pixel bubble.** (S·M) Replace the text "…" over a followed fish (`main.gd:5782-5866`) with a 3×3 palette bubble that inflates while the fish is "composing" and pops on the first syllable. It is pixel-honest and tells the player something is about to be said.
- [ ] **13. Heard signals are shown in the Mind panel.** (S·M) `_heard_signals` only reaches the mind proxy (`mind_fish_proxy.gd:336-345`). Add a workings row: "heard: alarm from Nell · 2 s ago · trusted". It is the first time a player can see that fish hear each other.
- [ ] **14. Reinforce every signal kind, not only ALARM.** (S·M) `fish_signals.gd:82-83` reinforces reliability only when a heard alarm precedes the listener's own fright. Add the other three:
  - FOOD_FOUND: the listener finds food within N s of approaching.
  - MATE_CALL: courtship follows.
  - SUBMIT: the aggression stops.

  Meaningful calls (§5) need learned trust in each kind.
- [ ] **15. A heard alarm can start the panic wave.** (S·M) The school-panic cascade triggers off a neighbour's `burst_remaining` (`fish.gd:6842-6847`), not the ALARM signal. Learned reliability only stretches the delay (`fish_spark_behavior.gd:66-73`). Let a trusted, heard alarm be a trigger in its own right, so a call has a consequence the player can watch.
- [ ] **16. The tank's inner stream reaches someone.** (S·M) `tank_mind.gd:366-409` generates stream lines, at most every 420 s. They reach players only inside replies to the keeper, in the debug inspector (`mind_debug.gd:154-155`), or after an away gap (`tank_chronicle.gd:1905-1925`). Give each a home: the Chronicle's night ledger, and the hydrophone strip (#64).
- [ ] **17. Replace "one model reply per session" with a refilling budget.** (S·M) `mind_conversation.gd:15, 272-278` caps model replies at one per session, so a long session goes template-only for hours. Use a token bucket instead, for example 1 per 4 minutes with a capacity of 2. It keeps the calm cadence without the hard cliff.
- [ ] **18. The keeper-reply context keeps the water.** (S·M) The slim reply context drops `o2` and the felt state (`mind_context.gd:407-437`). Pass felt tokens rather than numbers, for example `breath: tight`, `water: sharp`, `gut: empty`, from the same felt vocabulary as #201. A reply can then mention the water when it is the truth of the moment. Validator: each token must match its felt channel.
- [ ] **19. Gain by presence on screen.** (S·S) Until full spatial audio lands (#51), scale every voice by the speaker's on-screen pixel size and distance from the view centre, using the same pan law the eat and startle notes already use (`ambient_audio.gd:400-404`).
- [ ] **20. Overheard chatter sounds like speech, far away.** (S·S) Chatter between fish plays generic bloops (`main.gd:5518-5520`). Use each speaker's real babble at −9 dB with a low-pass, so the player can tell two fish are talking without reading a word.
- [ ] **21. `smoke_voice_paths.gd`.** (S·M) Drive every speech path: thought, reply, follow-up, Guardian, tank, question, chatter, colony and model upgrade. Assert each yields exactly one text record and exactly one vocal act, and nothing ever leaves the cooldown stuck. This is the regression net under #1, #4 and #5.
- [x] **22. One `Utterance` record: the foundation of Part One.** (M·L) Add `utterance.gd` (`class_name Utterance`, RefCounted). Its fields:
  - Identity: `id`, `speaker_id`, `speaker_kind` (fish/tank/colony/guardian).
  - Act: `act` (call/murmur/babble/line/breath), `intent` (alarm, food, contact, greet, reply…).
  - Content: `text` (optional), `felt` (snapshot of valence, arousal, stress, fatigue and confidence from `fish_core_affect` / `mind_self_model`).
  - Delivery: `pos`, `loudness`, `addressee_id`, `t`.

  Every path in this section creates one and emits it on the motion bus (`MotionEvents.emit("utter", …)`, `motion_events.gd:30`). Audio, pose, text, journal and nearby fish all subscribe. Voice becomes one event many systems hear, instead of four code paths that each half-do it.
- [ ] **23. `fish_thought_spoke` becomes a thin adapter over Utterance.** (S·M) Keep the signal (`sim_driver.gd:67`) for compatibility, but build it from the Utterance, so main.gd's strip, the inbox and the journal read one shape.
- [ ] **24. A voice row in the perf/debug HUD.** (S·S) Show:
  - utterances/min by act
  - allocator steals and drops
  - global cooldown state
  - last speaker.

  "The tank went quiet" must be diagnosable in one glance. Bug #1 hid for months.
- [ ] **25. Quiet mode means no words, not no life.** (S·M) Quiet blocks voice toasts (`comms_inbox.gd:158-174`). Define quiet as:
  - no lines and no babble
  - calls and breaths continue at −10 dB
  - a separate, explicit **Silence creatures** switch for true silence.

  A quiet tank should still sound like a living one.

---

## §2 A fish's real sound: the biological repertoire (26–50)

Real fish are loud. Hundreds of species drum their swim bladders, rasp
fin spines, grind pharyngeal teeth, or croak with modified tendons, mostly
when they court, fight, or are frightened. Several of the species already in
`SPECIES_LIBRARY` (`tank_config.gd:1218`) belong to vocal families. This is
the most under-used true fact in the game. Every item marks whether the
sound is *documented* for that family or *stylized*. #50 holds the line.

- [ ] **26. A voice block in each species genome.** (M·L) Extend the templates in `tank_config.gd:1218` (and `real_species_fauna.gd` for invertebrates) with `voice: {mechanism, f0_hz, pulse_rate_hz, pulses, band_hz, contexts[], documented: bool}`. Keep the data in `data/voice/repertoire.json`, mirroring `data/motion/poses.json`, so it can be tuned without touching code. A species with no entry is silent, which is a valid, honest answer.
- [ ] **27. Swim-bladder drumming (documented in gobies, cichlids, gouramis).** (M·L) Sonic muscles beat the bladder and produce low, pulsed knocks and grunts, roughly 80–400 Hz. Synthesize them as damped-sine pulse trains, with pulse rate equal to the muscle rate and a per-pulse decay set by bladder size. Give the voice to `goby`, `severum`, `angelfish` and `dwarf_gourami`.
- [ ] **28. Pectoral-spine stridulation (documented in Corydoras and many catfishes).** (M·L) Corydoras click when handled and during courtship. Pleco-type catfishes rasp too. Synthesize short broadband clicks, band-passed about 1–5 kHz, in trains whose rate equals spine-sweep speed. This is the voice of `corydoras` and `bristlenose_pleco`, and it pairs with the pectoral lock pose (#49).
- [ ] **29. The gourami croak (documented in Trichopsis; tendon-plucked sounds in other gouramis).** (M·M) It is a purring train of double knocks, made by plucking an enhanced pectoral tendon in courtship and threat. It is the signature voice for `dwarf_gourami` displays. Its tempo should match the fin-flare cadence in the pose runtime.
- [ ] **30. Pufferfish grind and gulp (documented).** (S·M) Pufferfish grind their teeth (a gritty rasp) when stressed, and gulp water hard to inflate. `fish_phase2_pose.gd:114-116` already turns inflation into stress. Add the gulp series during inflation and a tooth-grind when cornered, plus a crunch when eating snails.
- [ ] **31. Loach clicks (documented in some botiid loaches; stylized for hillstream).** (S·S) Clicks during feeding squabbles and territorial bouts. Give `hillstream_loach` a soft version and mark it `documented: false` in the repertoire, honestly.
- [ ] **32. Feeding is audible.** (M·M) The sound of a meal, by species:
  - Surface feeders (guppy, endler, killifish): a wet snap at the surface.
  - Corydoras (and the mudsifter): a sand snuffle as they sift.
  - Plecos: rasping on driftwood. Real aquarists hear this through the glass.
  - Otocinclus: a fine scrape on glass.

  Drive it from the existing strike, gulp and graze events (`MotionEvents` `gulp`/`strike`, `motion_events.gd:30`) and from `fish_phase2_pose.note_meal` (`:324`).
- [ ] **33. Air breaths of the labyrinth fishes and the gar (documented).** (S·M) Betta, gourami and gar gulp air at the surface, and the exhaled bubble makes a small "kiss" pop. Betta nests pop too. Edge-detect the surfacing the same way the gulp bloop already is (`ambient_audio.gd:3476-3507`), but give each species its own timbre.
- [ ] **34. Hydrodynamic sound: the fast-start thump.** (S·M) A C-start displaces water hard: a low, dull thump, felt more than heard. Trigger it on the `dart_started` and `startled` motion events, with gain from burst speed (`hydrodynamics.gd`).
- [ ] **35. Snail rasp and shell knock (documented with hydrophones in tanks).** (S·M)
  - A radula rasp while a snail grazes glass.
  - A shell click against stone.
  - A falling-snail plop. The "snail" bloop already exists; give it material.

  They are quiet, near-constant and nocturnal. Gate them on `snail.gd` grazing state and on `ColonyMind` activity.
- [ ] **36. Shrimp ticks and the reef snap.** (S·S) Freshwater shrimp make faint feeding ticks and a tail-flick snap on escape. Snapping shrimp crackle is the defining sound of real reefs, but use it only in reef scenarios, and only if a snapping species is present.
- [ ] **37. Sessile and slow life: the clam's valve.** (S·S) A muffled clap when `clam.gd` shuts. Sea cucumbers and worms stay silent, which is honest.
- [ ] **38. Every vocal species gets a repertoire by context.** (M·L) Five contexts cover most of real fish acoustics: advertisement (courtship), agonistic (threat), distress (seized or fleeing), contact (keeping touch) and feeding. Each species maps 0–5 of them to repertoire entries (#26). These five are the vocabulary §5 turns into meaning.
- [ ] **39. Courtship drumming bouts.** (M·L) Male gobies and cichlids call while displaying, and females approach calling males (phonotaxis, #120). Couple the call bout to the mating-dance and display poses (`fish_pose_runtime.gd:69`), so the dance has its own soundtrack made by the dancers.
- [ ] **40. Territorial grunts at the border.** (S·M) Severum, angelfish and betta grunt while holding a threat display. Call from `FishAnticipation.note_threat_display` (`fish_anticipation.gd:148`), so the grunt arrives with the fin raise, not after the chase.
- [ ] **41. Distress calls when seized, cornered or poked.** (S·M) A burst of stridulation (corydoras) or grunts (cichlids). Trigger it on `inject_startle` taps (`motion_field.gd:39`), on predator contact, and on `poke_harness.gd` interventions, so the poke harness can measure the call as a response.
- [ ] **42. The silent species stay silent.** (S·M) Tetras, rasboras and danios are mostly not known for calls. Their "voice" is the school's water-sound (#131) and their body. Write this into the repertoire as `mechanism: "none"`, so no one "helpfully" gives a rummy-nose a chirp. Silence is a trait.
- [ ] **43. Voices change with growth.** (S·M) Dominant frequency falls as body length grows; this is documented across fish. Drive `f0` from `fish_growth.gd` body length, so fry squeak, adults knock, and a fish's voice deepens over its life. The player hears time pass in a voice.
- [ ] **44. Sex and the voice.** (S·M) In most vocal species, males do most courtship calling. Gate advertisement calls by sex, and give females distress and contact calls. Females can call louder when guarding fry, as some cichlids do.
- [ ] **45. Voices are inherited.** (M·M) Put `f0`, pulse rate and pulse count in the genome with small mutation through the existing genetics stream (`MindRng.stream(..., SimRng.STREAM_GENETICS)`). Offspring sound like parents, and lineages drift apart. Over generations a tank develops a *sound* (#110).
- [ ] **46. Size-frequency allometry as the default.** (S·S) If a species has no tuned `f0`, derive it from body length using a species constant (`f0 = k / length`). That replaces the current linear pitch-by-size map (`tank_voice_audio.gd:191-212`, 1250→330 Hz) with something that behaves like water and muscle.
- [ ] **47. Calling costs energy.** (S·M) Sonic muscles are among the fastest vertebrate muscles, and they tire. Each call bout drains a little `energy` (`fish.gd:619`) and adds a little fatigue in `fish_protoself` (`:51-53`). Tired fish call less, and courtship bouts get shorter as evening comes. The voice joins the body's economy.
- [ ] **48. Drumming is visible.** (M·M) A drumming fish shows:
  - a 1-px flank shiver at the pulse rate (the `body_arch` channel in `motion_pose_library.gd:24`)
  - a slight opercular flare.

  Use the unused `MotionEnvelope` (`motion_envelope.gd:36-79`) for windup → call → settle. A player with the sound off can still see a fish "speak".
- [ ] **49. Stridulation is visible.** (S·M) Corydoras lock their pectoral spines out and twitch them while clicking. Add a `stridulate` pose to `data/motion/poses.json`, using `pec_forward` and `pec_spread` at full with small rapid jitter. It overrides the cory and pleco defaults while the click train plays.
- [ ] **50. `docs/VOICE_REFERENCE.md`.** (M·L) A reference doc on the pattern of `MOTION_REFERENCE.md`. For each species family it records:
  - what is documented (mechanism, context, frequency band)
  - search terms and recordings to listen to (fish bioacoustics literature; hydrophone recordings of the real families)
  - what this game stylizes.

  Rule: a sound marked `documented: true` must cite its source. Everything else is labelled stylized in the repertoire and in the in-game glossary (#116). This doc is what keeps Part One honest.

---

## §3 The voice engine: synthesis, space, listening (51–75)

- [ ] **51. Voices come from where the fish is.** (M·L) No script uses `AudioStreamPlayer3D` today, and every voice is mono. Two tiers:
  - Default: pan and gain from screen position, extending `ambient_audio.gd:400-404` to voices and calls.
  - Option: real 3D players attached to the speaker, with attenuation tuned to the tank's size.

  A cory clicking bottom-left is heard bottom-left.
- [ ] **52. The glass between you and them.** (M·M) The listener is outside the glass, so filter accordingly:
  - a gentle low-pass
  - a small glass-resonance peak
  - a slight loss of highs.

  This "through the glass" filter is the default. Hydrophone mode (#64) removes it. The difference teaches the player there is a world in there with its own acoustics.
- [ ] **53. A small DSP vocabulary: `fish_voice_dsp.gd`.** (M·L) Six primitives that render every creature sound:
  - `pulse_train(f0, rate, n, decay, jitter)` for drums and knocks
  - `click_train(band, rate, n)` for stridulation
  - `croak(f0, double_gap)`
  - `rasp(band, scrape_rate)`
  - `snap(level)`
  - `breath(band, len)`

  `tank_voice_audio.render` (`:283-351`) becomes a client of these, rather than a bespoke FM babble.
- [ ] **54. A sound palette, like the colour palette.** (M·M) The style guide fixes 48 colours. Fix the sound world the same way: the six primitives, about five timbres, one reverb per tank shape and a loudness target per act. Write it as a page in `style-guide/`. Every new creature sound is built from the palette, so the soundscape stays coherent the way the frame does.
- [ ] **55. Prosody-aware cache keys.** (S·M) The LRU holds 16 renders (`tank_voice_audio.gd:442-447`). Once prosody varies (§4), quantize the felt inputs into bins (for example 4 arousal × 3 valence × 2 fatigue) and key the cache on `(voiceprint, act, intent, bins)`. Raise the capacity to about 96 and measure it in the audio probe.
- [ ] **56. Continuous calls are streamed, not pre-rendered.** (M·M) Purrs, long croak trains and the colony's night rasp should not be one-shots. Add 2 streaming voices backed by `AudioStreamGenerator`, fed from the worker the bed already uses (`synth_ring_buffer.gd`). They can follow the caller's moment-to-moment state while sounding.
- [ ] **57. A voiceprint per fish, from the same seed as its motion.** (M·L) Derive formant pair, pulse jitter, attack and vowel colour from the same seed that drives `MotionPersonality.from_seed` (`motion_personality.gd:20`), which is unused today. A fish that moves quick and twitchy also *sounds* quick and twitchy. Gesture and voice read as one being.
- [ ] **58. The Guardian's motif.** (S·M) Give the Guardian a three-note signature (MAKE_IT_THERE's recurring-motif idea) voiced in its own timbre. It sounds faintly under every Guardian line, and once at dawn. Players learn to recognize *them* before reading.
- [ ] **59. Formant babble, so words have vowels.** (M·M) Today's babble is FM syllables (`tank_voice_audio.gd:191-212`). Add a two-formant filter seeded by the voiceprint. Each fish then has a consistent "vowel colour", and #164's word-motifs become recognizable.
- [ ] **60. Loudness targets per act.** (S·S) Set targets for breaths, calls, babble and the Guardian, about −30, −24, −22 and −20 LUFS-ish respectively. Normalize at render time (`tank_voice_audio.gd` already peak-normalises), so nothing in the tank startles the keeper.
- [ ] **61. Plants and stone occlude.** (M·M) A fish calling from behind dense stems is muffled. Sample `canopy_density.gd` and `hardscape_occluders.gd` along the speaker→camera ray and apply a low-pass. The aquascape shapes the sound, as it does in real water.
- [ ] **62. The tank's shape is its room.** (S·M) One reverb impulse per vessel family (`tank_spec.gd` / `vessel_picker.gd`):
  - Bowl: bright and ringing.
  - Long tank: wide and short.
  - Column: tall, with a flutter echo.

  The vessel the player chose is audible.
- [ ] **63. Listening from inside a fish.** (M·L) When following a fish, move the listener to its head:
  - Its own calls get a low "bone-conduction" boost.
  - Neighbours are panned relative to its heading.
  - The glass filter drops away.

  The player hears the tank as that fish does. It is the cheapest possible point-of-view shot.
- [ ] **64. Hydrophone mode: "ear to the glass".** (M·L) A toggle (key and HUD chip) that:
  - removes the glass filter
  - lifts the creature bus 6 dB and ducks the music 9 dB
  - shows each call as a 1-frame palette ripple at its source.

  The player becomes a bioacoustician. It is also where the tank stream lines (#16) appear, as a quiet strip.
- [ ] **65. A pixel spectrogram strip.** (M·M) In hydrophone mode, a 384×24 scrolling spectrogram along the bottom edge, quantized to the palette, built from the synth parameters of active voices. There is no FFT on the mix: draw what was synthesized. Drums show as low ladders, clicks as vertical ticks, croaks as stitched pairs. Players learn to *see* species.
- [ ] **66. Captions for calls.** (S·L) An accessibility caption lane for creature sound, for example "[cory clicks · alarm, low left]" or "[the tank breathes]". It goes through the existing caption budget (COMMS #401), with species and intent from the Utterance and position as a word. It is also the deaf player's path into §5.
- [ ] **67. Deterministic voices.** (S·M) Draw all voice randomness (jitter, variant, micro-timing) from a new `SimRng.STREAM_VOICE` via `MindRng.stream`, never bare `randf()`. A recorded tank then replays the same sounds, and `mind_replay_parity` can cover the utterance sequence.
- [ ] **68. Voice LOD.** (S·M) Off-screen or sub-4-px fish produce only sparse, low-priority calls. Gate render priority on `MotionLOD.tier_for` (`motion_lod.gd:25`) and the allocator (#7). A 60-fish tank must not become a wall of clicks.
- [ ] **69. A render budget on the worker.** (S·M) Cap concurrent `WorkerThreadPool` renders (`tank_voice_audio.gd:392-398`). Pre-warm the ten commonest calls per stocked species at load, following the shader-warm pattern (`shader_warm_capture.gd`). The first alarm of a session must not arrive late.
- [ ] **70. Extend `dev/audio_probe.tscn` to the creature bus.** (S·M) Measure level per act, utterances/min by species, allocator steals, cache hit rate and the 99th-percentile render latency. Run it under `scripts/dev_run.sh` (AGENTS.md: it isolates user data).
- [ ] **71. A soundscape capture for blind review.** (M·M) A dev scene writes 60 s of the creature bus to WAV, for tests on the pattern of the motion review protocol:
  - The game's tank against a real tank hydrophone recording of the same families.
  - Can raters guess the species?
  - Can they guess the mood?
- [ ] **72. The noise floor breathes.** (S·M) Give the tank a room tone (filter hum, faint water hiss) that dips by 2–3 dB when the creatures fall silent together. Silence becomes perceptible as an event, which §5 #114 and §6 #136 rely on.
- [ ] **73. Equipment masks calls.** (S·M) Calls near the filter outlet are partly masked; mix them with a frequency-band duck against the filter's noise. Fish answer with the Lombard effect (#87).
- [ ] **74. Platform tiers.** (S·M) Web, Android and potato-tier devices get:
  - 3 voices and pre-rendered calls only
  - no streaming voices and no occlusion.

  The repertoire and captions stay intact. Document this in the AGENTS.md platform table beside the Guardian matrix.
- [ ] **75. Creature sound is not "AI voice".** (S·M) `sentience_voice_off` (`tank_config.gd:340`) silences the language voice. Calls, rasps and breaths are biology, so they get their own switch, `creature_sounds_enabled`. Turning off the talking fish must not turn off the fish.

---

## §4 Prosody of feeling: the state shapes every sound (76–100)

Today the voice takes `kind, seed, length, size, boldness, variant`
(`tank_voice_audio.gd:168-169`, assembled at `ambient_audio.gd:3417-3430`). It
has no input from mood, arousal, stress or fear, so a terrified fish and a
content one sound identical. Everything in this section maps a real felt
variable onto a real acoustic parameter. The mapping follows what is known
about vertebrate vocal affect (arousal → rate, pitch and energy; negative
state → roughness), applied loosely and honestly.

- [x] **76. Felt state enters `voice_params`.** (S·L) Extend the render params with `valence, arousal, stress, fatigue, confidence, surprise`, read from the Utterance's `felt` snapshot (#22). The sources are `fish_core_affect.gd:37-70` (valence/arousal), `fish_protoself.gd:51-53` (fatigue), `mind_self_model.gd:30` (confidence) and the prediction-error surprise. This is the single hinge of the section; every item below is a mapping that consumes it.
- [ ] **77. Arousal sets tempo.** (S·M) Pulse rate, syllable rate and bout length scale with arousal, from about 0.7× at rest to about 1.6× when stirred. A frightened cory clicks fast. A drowsy one barely clicks.
- [ ] **78. Valence sets the contour.** (S·M) Positive or approach states get a slight rising pitch over a call. Negative or withdrawing states get a falling one. Neutral is flat. Keep the effect within about ±2 semitones; it should be felt rather than heard.
- [ ] **79. Stress adds roughness.** (S·M) Period jitter and amplitude shimmer scale with `stress`, alongside a little noise in the tone. A rough voice is the most cross-species cue of distress, and it is cheap to synthesize in `pulse_train` (#53).
- [ ] **80. Fatigue shortens and lowers.** (S·M) Tired fish make fewer pulses per bout and leave longer gaps, and the last pulse in a bout drops in level. At dusk the chorus audibly winds down because the fish do.
- [ ] **81. Fear is clipped and abrupt.** (S·M) Distress calls get a 0-ms attack, a higher band and short bouts, and no settle. Contrast this with the slow attack of a contact call. The attack shape alone should tell the keeper something is wrong.
- [ ] **82. Confidence steadies timing.** (S·M) A confident fish calls with regular intervals and longer phrases. A doubting fish hesitates: a pause mid-bout, a restart. Read `mind_self_model.gd:30` (and its calibrated replacement, #276). Uncertainty becomes audible.
- [ ] **83. Hunger makes calls insistent.** (S·S) Near learned feed times (feed-time beliefs, `fish_learned_mind.gd:736-753`), contact calls repeat a little more and a little faster. The tank sounds expectant before you feed it.
- [ ] **84. Breathlessness makes the voice breathy.** (S·M) Under oxygen debt (the breath error, #177), shift energy from tone to noise, and add a tremolo locked to the gill-cover tempo (`fish_timing.gd:109 oxygen_opercula_tempo`). A hypoxic tank *sounds* short of breath before the HUD turns amber.
- [ ] **85. Old fish sound old.** (S·M) With `mortality_shift` (`mind_soul.gd:214-225`), lower the pitch slightly, slow the tempo and add breath. Combined with #43, a single fish's voice carries its whole life.
- [ ] **86. Felt texture becomes timbre.** (M·M) Core affect produces a texture label (`fish_core_affect.gd`, rendered in sentences by `fish_qualia.gd:59-77`). Map each label to a timbre preset: "thin" means less body, "warm" more low formant, "heavy" a slower attack and more low-pass. The same word appears in the text voice and in the sound, so one inner fact reaches the player through both.
- [ ] **87. The Lombard effect.** (S·M) Fish raise their call level, and shift it up a little, when background noise is high. This is documented in fish as well as in birds and mammals. Near the filter outlet (#73), or while the music bed is loud, callers compensate. It is a tiny thing that makes the voice feel *meant for someone*.
- [ ] **88. The audience effect.** (M·M) Calls change with who is listening: louder and longer with a mate or rival in range, softer alone. Use `Utterance.addressee_id` and the 8-u hearing radius (`fish_signals.gd:11-19`). A fish calling to no one is quieter than a fish calling to someone.
- [ ] **89. Contagion entrains voices.** (M·M) `mind_contagion.gd` already pulls arousal toward the neighbourhood mean. Also pull call *tempo* toward heard neighbours' tempo, damped so it converges. When a school is stirred, its calls lock into a shared pace; when it calms, they drift apart.
- [ ] **90. A relief exhale (stylized).** (S·M) When chemistry improves, the relief pulse fires (`fish.gd:1687-1696`). Play a soft falling breath-bubble at the fish. Real fish release gas and are not known to "sigh", so mark it stylized in the repertoire. The player still hears the water getting better before reading it.
- [ ] **91. An ignited thought sounds brighter.** (S·M) An utterance whose content is in the fish's ignited workspace (`global_workspace.gd`, `_workspace_ignited`) gets a sharper onset and one more formant. An un-ignited, background thought stays a murmur. Loudness tracks *how much it is on its mind*.
- [ ] **92. Prosody has inertia.** (S·S) Smooth the felt-to-voice parameters with a critically damped spring (`motion_spring.gd:45-70`), so a voice does not jump per frame. A fish that was frightened a moment ago still sounds a little frightened.
- [ ] **93. Prosody is relative to the fish's own baseline.** (S·M) A naturally quick fish is not "anxious". Take the baseline tempo, amplitude and pitch from `MotionPersonality` (`motion_personality.gd:11-16`) and the voiceprint (#57), and make prosody a deviation from that personal normal. Each fish's distress then sounds like *its* distress.
- [ ] **94. A blind listening test of prosody.** (M·M) Render 3-s clips at known felt states and ask raters to guess calm/stirred and good/bad. Target: 20 points above chance on arousal and 10 on valence. Record the method beside `MOTION_REVIEW_PROTOCOL.md`. This is the evidence that the voice carries state.
- [ ] **95. The tank's breath carries the tank's state.** (S·L) Today the tank voice is a 62–84 Hz swell chosen by line hash (`tank_voice_audio.gd:180-190`); only the music bed follows tank mood (`ambient_audio.gd:3434-3442`). Drive breath rate, depth and roughness from TankVitals (#301) and TankMind: shallow and quick when unstable, deep and slow when settled. One breath is enough to hear how the tank is.
- [x] **96. [V] Untangle tank arousal from stress before prosody uses it.** (S·M) `tank_mind.gd:289` lerps `mood_arousal` toward the mean fish *stress*, while the real mean arousal sits unused next to it in `collective_arousal` (`:288`). As a result, excited-and-happy is indistinguishable from distressed. Drive `mood_arousal` from `collective_arousal` and expose stress separately as `mood_strain`. #95 and the music bed both depend on this.
- [ ] **97. Text has prosody too.** (S·M) The typewriter speed (34 ms/char, `main.gd:304`) follows arousal. An ellipsis pauses for the length of a hesitation, and fatigued fish type slowly. These are prosody signals for the eye, and they work with the sound off.
- [ ] **98. Weight in the glyphs.** (S·S) Two palette-legal text weights: faint for an inner murmur, full for an addressed line. No new font, just ink value. The strip then says whether the fish meant it for you.
- [ ] **99. Night voices whisper.** (S·M) Under the night-quiet bids (`global_workspace.gd:161-166, 225-229`), calls drop 6 dB with fewer pulses and more breath. The nocturnal crew is exempt (#135). At night the tank lowers its voice, as a house does.
- [ ] **100. An honesty rule for prosody.** (S·L) No preset, mode or "cute" override may make a voice sound calmer, happier or more certain than its felt state. Add an eval invariant (V4, #479): the prosody parameters must be monotonic functions of the felt inputs, verified by sampling. Extend the honesty gate (`mind_eval.gd:31-38`) to the voice code. A pleasant-sounding lie is still a lie.

---

## §5 Calls that mean something: signals become language (101–125)

`fish_signals.gd` already has a proto-language: four signals (alarm,
food_found, mate_call, submit), an 8-u radius, a 3-s linger, and learned trust
(`:11-19, 82-83`). The player can neither hear nor see any of it, and it is
missing from the language-model context. This section makes the signals into
calls with sound, consequence and learnability, so the keeper can come to
understand them.

- [ ] **101. Every signal is a call.** (S·L) When `FishSignals` emits (ticked at `fish.gd:1558-1560`), create an Utterance with `act: call`, the species repertoire entry for that context (#38) and the speaker's felt state. Alarm, food, mate and submit get four distinct, species-flavoured sounds. Species with no voice emit the signal as a visible act only (#102).
- [ ] **102. Every call is visible.** (S·M) A one-frame palette ring at the caller, its radius scaled to the 8-u hearing range, drawn only in hydrophone mode (#64) or when the caller is followed. A fin-flick for silent species. The player learns how far a fish can be heard.
- [ ] **103. Grow the vocabulary to eight.** (M·L) Add four signals:
  - `contact`: keep-in-touch within a school or pair.
  - `here`: locating, in the dark or murk.
  - `rival`: territory.
  - `all_clear`: an alarm resolved.

  Eight is the ceiling; a fish's vocabulary should stay small and real. Each carries `{kind, source_id, pos, strength, t}` like the existing four.
- [ ] **104. Honest signals cost something.** (M·M) A call costs energy (#47) and is audible to predators within range: puffer, gar and severum turn toward calls. Loud courtship calls are therefore affordable only to fish in good condition. Female choice weights call quality (bout length × steadiness), so the courtship call becomes an honest health signal (the handicap principle).
- [ ] **105. Receivers have species-specific responses.** (M·M) A table of what each species does on hearing each call: approach, freeze, flee, ignore or answer. It is modulated by the per-caller trust table that already exists. A danio's response to an alarm is not a cory's.
- [ ] **106. Cross-species eavesdropping.** (S·M) Corys should respond to a danio's alarm. Snails withdraw on fish alarms; `ColonyMind` already has a predator-alarm input (`colony_mind.gd:194-206`), so wire it to heard alarms. The tank becomes one listening community rather than separate species.
- [ ] **107. The fish that cried wolf.** (S·M) A caller with low reliability is ignored: the trust table already models this. Surface it: a Mind-panel line "doesn't trust Pip's alarms", and visibly no reaction when Pip calls. Deception and its cost become something a player can notice.
- [ ] **108. Duets.** (M·M) Bonded or courting pairs alternate calls, with the timing tightening as the bond grows. Reuse the antiphonal timing from `music_choreography.gd` (choir antiphonal), here driven by the pair's own calls. A long-bonded pair sounds like a pair.
- [ ] **109. Usage learning, honestly framed.** (M·M) Fish calls are largely innate; true vocal learning is not documented in fish. What fish *can* learn is when calling pays off. Learn per-context call propensity from outcomes: a contact call that brings the school back gets reinforced. The repertoire stays fixed while its use changes. State this distinction in VOICE_REFERENCE.md.
- [ ] **110. Lineage dialects.** (M·M) Through inherited voice genes (#45) and drift, related fish share call parameters and unrelated lineages differ. The tank-share code (`tank_share.gd`) carries a dialect fingerprint. A shared tank arrives sounding like its keeper's tank.
- [ ] **111. Individual voice recognition.** (M·M) Some fish recognize individuals by voice; this is documented in a few cichlids and toadfish. Make the heard call carry `source_id` into the workspace bid, so a fish attends to *who* called: a mate's contact call outranks a stranger's. The Mind panel can say "heard Mira".
- [ ] **112. A heard call is a percept with content.** (S·L) Today the loudest heard signal becomes one salience-weighted bid (`global_workspace.gd:141-144`). Give it `{kind, who, where, how sure}`, so the workspace can win on *a call from my mate near the cave* rather than on "signal". This is the hinge between hearing and thinking.
- [ ] **113. Calls are remembered.** (S·M) Store heard calls in episodic memory with place and outcome. Alarm calls at a place feed the spatial danger schemas at sleep (`episodic_memory.consolidate_sleep`). The tank learns where alarms happen, not only where attacks happen.
- [ ] **114. Silence is a signal.** (M·L) A schoolmate whose contact calls stop arouses its partners after a learned interval: they search, call more, and pause at its last place. This is how a death, a sickness or a stuck fish (#248) is noticed *by fish*, before the keeper sees it. The awareness lives in the absence of a voice.
- [ ] **115. In the dark, sound replaces sight.** (S·M) Raise the contact-call rate as light falls (`mind_sim_snap.gd:6-37`) and as turbidity rises (#214), and let schools stay together on calls when they cannot see each other. Night Watch's "sound outranks sight" now has the sound itself.
- [ ] **116. The keeper's listening log.** (M·L) A glossary that fills in as the player hears calls. A call type unlocks after it has been heard several times in a consistent context:
  - Icon, species, the context it was heard in, and a mini spectrogram (#117).
  - The documented / stylized flag (#50).

  It extends LEARNING_MIND §II's "keeper-as-decoder" with a concrete artifact. The keeper becomes fluent in their tank.
- [ ] **117. A spectrogram card per call.** (S·M) Render each glossary entry's spectrogram from its synth parameters (#65) as a small pixel card. It is beautiful, it is legible, and it is exactly what a bioacoustician's field notebook looks like.
- [ ] **118. Playback experiments.** (M·L) From the glossary, the keeper can play a recorded call into the tank and watch: an alarm scatters the trusting fish, a contact call brings a lonely fish over, a mate call draws a female. Responses use the trust table, so overused playback is habituated to and then ignored. This is a real bioacoustics method, it teaches the system, and the consequences are honest.
- [ ] **119. Calls and the chemical channel together.** (M·M) An alarm call is fast, local and brief. An alarm substance is slow and lingers in water (#207). Where both exist, combine them: a call tells the school *now*, the chemical tells late-arriving fish *something happened here*. Cross-reference DEEP_SCIENCE §G rather than duplicating it.
- [ ] **120. Phonotaxis.** (S·M) Females swim toward a calling male of their species, which is documented in gobies and toadfish. It becomes a workspace bid with direction to the sound. Courtship becomes a conversation in water, and it is visible.
- [ ] **121. Dear-enemy calm.** (S·M) Territorial neighbours who know each other exchange quieter grunts and fight less than strangers do, which is documented across many taxa. Track neighbour familiarity, and turn down agonistic call level and chase likelihood for known neighbours.
- [ ] **122. The submit call ends fights.** (S·M) An audible, soft, falling call when SUBMIT fires. The aggressor's chase decays on hearing it (#105). Fights get a resolution beat the player can hear.
- [ ] **123. A greeting call for the keeper.** (S·M) A familiar fish gives one contact call when the keeper returns (FOCUS_IN, `main.gd`) or comes to the glass. It happens once per return and only above a familiarity threshold, and it never repeats to beg. It is the smallest possible "they know me".
- [ ] **124. Call statistics in the behaviour probe.** (S·M) `dev/fish_behaviour_probe.tscn` prints calls/min per species and context, response rates and trust distributions. Calls become tunable and regression-testable, like depth bands and turn rates.
- [ ] **125. Heard calls enter the language-model context.** (S·M) Add the last 10 s of heard calls (who, kind, where) to `mind_context.gd`, so a line can be grounded in "Pip called — food, by the log". Validator: a call can be mentioned only if it is in the heard ring.

---

## §6 The chorus: the tank's collective voice (126–150)

Real reefs and ponds have choruses. Calling peaks at dawn and dusk,
ecologists use soundscape richness as a health index, and a quiet reef is a
sick reef. In this game the tank's collective sound is the generative music
bed. That is lovely, but it is *about* the tank rather than *of* it. This
section makes the tank's living chorus the primary collective voice and lets
the music answer it.

- [ ] **126. Dawn and dusk choruses.** (M·L) Calling rates rise over a window of about 3 minutes at dawn (`day_phase` around 0) and dusk (around 0.5; the phase clock is in `sim_driver.gd`), shaped per species by its context table. The tank wakes up and settles down out loud.
- [ ] **127. Chorus density is the tank's mood.** (S·M) Scale the overall call propensity by TankMind valence and arousal (after #96): a content tank is a busy, gentle chorus, a frightened one is a few sharp calls, a sick one is thin. The mood the music bed now carries alone also lives in the creatures.
- [ ] **128. The music quotes the fish.** (M·L) When music sync is on, the generative percussion takes its hits from live drum calls: `Music_Drums` gets the actual knock trains. The tank's song is literally made of its residents. It extends the shipped "ambient audio follows tank life" idea from following to *being*.
- [ ] **129. Chorus entrainment.** (M·L) Callers within hearing range phase-couple through Kuramoto-lite coupling of their bout onsets, as frogs and crickets do. With enough callers, the tank finds a shared pulse by itself. It is an emergent rhythm no one composed: the chorus becoming one voice.
- [ ] **130. The tank leads the tempo.** (M·M) A "tank leads" mode in the Sound Studio (`sound_panel.gd`): the generative bed's bar tempo follows the chorus's entrained frequency (#129), rather than the fish dancing to an imposed tempo. Musically, the mind conducts.
- [ ] **131. The school's water-sound.** (M·M) Silent schooling species still make sound by moving water. Generate a soft positional noise swell from school speed and turning (`motion_school.gd`, `bank_correlation` at `:230`), which rises when the school turns as one.
- [ ] **132. The murmuration is audible.** (M·M) When a turn propagates through the school (`motion_wave.gd:108 inject_at`), sweep a band-limited noise across the stereo field *along* the wave. The player hears the decision travel through the group.
- [ ] **133. A collective ignition sounds like its members.** (M·L) The tank-ignition chime is two tones a fifth apart (`tank_voice_audio.gd:244-252`, `ambient_audio.gd:3443-3446`). Build it instead from one short call or voiceprint tone from each fish that contributed to the ignition, voiced as a chord. When the whole tank notices something, the noticing sounds like *them*.
- [ ] **134. The quorum hum.** (S·M) When a quorum forms, hold a quiet sustained hum at the mean of the members' `f0` for as long as it holds. Agreement becomes audible.
- [ ] **135. The night crew owns the night.** (M·M) As light falls, calling hands over to the nocturnal residents: cory and pleco rasps, loach clicks, the snail radula. Use the nocturnal wake inversion that already exists in fish.gd. The night sounds different, not just quieter.
- [ ] **136. The missing voice.** (M·L) After a death, its bonded partners stop their contact calls to it, and for several days the chorus has a gap where its voiceprint was. A death leaves an audible absence that fades as the tank re-weaves. It extends Spark #74's music hush with the creature-level truth.
- [ ] **137. First sounds of fry.** (S·S) Fry make tiny high calls, quieter than any adult (#43). A brood's arrival can be heard in hydrophone mode before it is easily seen.
- [ ] **138. The song of the day.** (M·L) At dusk, distil about 10 s from the day's most characteristic calls: the most frequent contexts and the loudest event. Render it with the day's voices and save it to the Chronicle. It plays at the night ledger and in the away recap. The tank's day is recorded in its own voices.
- [ ] **139. The breeding season sounds like one.** (S·M) Under the seasonal breeding gate (`fish.gd:1304-1316`), advertisement calls dominate the chorus. Players hear the season turn.
- [ ] **140. A chorus index in the tank self-model.** (M·M) Compute a bioacoustic richness index from the creature bus: an acoustic-complexity-style measure, counted per species. Feed it to TankVitals (#301) as a vital sign. A daytime tank that has gone quiet is a symptom the tank itself can notice (#145).
- [ ] **141. The soundscape in the vitals card.** (S·M) Show the chorus index as words, for example "the tank's voice is full / thin / anxious", with a 7-day pixel strip. Ecologists judge reefs this way, and the keeper can too.
- [ ] **142. The tank tunes itself, only when asked.** (M·M) With music sync on, quantize call pitches gently toward the bed's current key and chord (`ambient_audio.get_live_status()`), so the chorus is consonant. With sync off, the biology stays raw. Keep the choice explicit, so tuning never quietly overwrites the voice.
- [ ] **143. Antiphony across the tank.** (S·M) Groups in different territories answer each other: left-bank calls are followed by right-bank calls. Use #108's timing at group scale. The tank's space becomes conversational.
- [ ] **144. The colony as a choir section.** (M·M) Shrimp ticks and snail rasps are driven by `ColonyMind` activity (`colony_mind.gd`). Today the colony "voice" is one text line when the keeper talks to the tank (`main.gd:5128`). Give it a continuous, subtle, positional presence that thickens at night.
- [ ] **145. The chorus thins before the crash.** (M·L) As stability falls, advertisement and contact calls drop first and distress calls rise. When the water recovers, the chorus returns in order: contact first, courtship last. The soundscape is the tank's health, audible and *early*.
- [ ] **146. A vocal solo.** (S·M) Give the Guardian or the most-bonded fish a solo window inside the chorus, using the same casting logic as the dance soloist (`music_choreography.gd`, soloist): its calls are the clearest for a phrase and the others thin out. It is rare, and it gives the protagonist a voice moment that is not words.
- [ ] **147. A sound map in the mind lens.** (S·M) In the Mind Lens (#363), show where calls came from over the last minute as fading palette dots. The tank's acoustic life gets a shape.
- [ ] **148. The cathedral has its acoustic.** (M·M) During the night cathedral (`make_it_there.gd:304-313`), which today has no visual or sound of its own, swap the creature reverb for a long, high, stone-like tail. The hush stretches every rasp and click. The church from circuitry gets its echo.
- [ ] **149. The "Us" hymn is sung by the residents.** (M·L) The 10-note hymn (`ambient_audio.gd:2006-2050`) is voiced note by note in the timbres of living fish, one resident per note, chosen by bond and age. As residents change, the hymn changes. "I'll name it Us" becomes the residents' own song.
- [ ] **150. The chorus respects quiet.** (S·S) Chorus density honours the quiet modes (#25) and a "chorus level" sub-slider. The calmest setting keeps contact calls and breaths and drops advertisement and agonistic calls.

---

## §7 Words, as a fish would have them (151–175)

The text voice is mature: grounding, validators, budgets, tiers and a
Guardian. What it lacks is a *body*: lines appear without an act, every fish
types the same way, and words stand in for things a fish would rather show.
These items tie words back to sound, body and felt state, and keep them rare.

- [ ] **151. No word without a vocal act, and the sound comes first.** (S·M) Every line is preceded by its babble or call about 150 ms early, so the eye goes to the speaker before the text appears. Contract: each line Utterance has `act != none` (#21 asserts it).
- [ ] **152. Species idiolects.** (M·M) `mind_narrator.gd` has a tone map (for example "cory: methodical bottom-dweller", "guppy: bold and chatty"). Turn it into per-species word banks and syntax habits for templates:
  - Cory: short, plural, ground-level ("down here", "together").
  - Betta: possessive ("mine", "here").
  - Puffer: pointed ("that", "look").

  Validators keep it grounded.
- [ ] **153. Length follows the fish.** (S·M) Line length budgets (thought 16 / reply 8 words, `mind_narrator.gd:8-10`) become per-species and per-state *maxima*. Tired, frightened or quiet-species fish say less. Chatty species with high arousal can reach the cap.
- [ ] **154. Beyond the lexicon, the fish answers with its body.** (M·L) When the keeper's words contain nothing the fish knows (`mind_lexicon.gd`), the fish does not produce a template reply. It turns, calls once and makes an affect cue (`fish.gd:1228-1255`). It heard you and did not understand. This is the comprehension ceiling, made physical.
- [ ] **155. Words grounded in the felt water.** (S·M) Qualia lines ("the water feels thin", `fish.gd:971-976`) should become more likely as the felt channels deviate (§9) and as trends worsen (§11). The text voice is where awareness of state first gets words.
- [ ] **156. Only what can be perceived.** (S·M) Audit every template against HOLISTIC WL-0729: a line may only reference a fact this fish could perceive or feel right now, or that it remembers from an event it witnessed. Add a template-lint smoke that runs every template with a minimal context.
- [ ] **157. Inner speech and outer speech.** (S·M) Two presentations:
  - An inner thought: faint ink, murmur sound, no addressee, never toasted.
  - An utterance: full ink, babble, an addressee, an orienting turn.

  The difference tells the player whether they were spoken to or overheard.
- [ ] **158. The body addresses before the mouth.** (S·M) Before an addressed line, the fish turns toward its addressee with `MotionGaze.look_at_point(kind, pos, hold_s)` (`motion_gaze.gd:50`), using the `keeper` kind for you and `mate`/`rival` for fish. Those kinds sit unused in `PRIORITY` (`:14`). Speaking includes looking.
- [ ] **159. Hesitation is shown.** (S·M) When the deliberation that produced a line was close (DDM conflict, or the `efe_flatness` threshold), start the line with an ellipsis and play `FishAnticipation.note_hesitation` (`fish_anticipation.gd:181`). It is a fish making up its mind out loud.
- [ ] **160. A "speak" pose.** (S·M) Add a `speak` pose to `data/motion/poses.json`, with the `jaw` and `opercula` channels pulsing one beat per syllable through `MotionEnvelope`. There is no lip-sync, just the gape and settle of a fish that made a sound.
- [ ] **161. Fragments under stress.** (S·M) Stressed lines break into fragments ("food — there — no") rather than full phrases, with the template grammar shifting at high stress or arousal. Fear removes syntax. This is a mind under load, not a speech impediment, and should be written as such.
- [ ] **162. Fish quote each other.** (S·M) A line can cite a heard call (#125): "Pip said food". This is the first trace of reported speech in the tank, and it is grounded in the heard-call ring.
- [ ] **163. Echoes keep the keeper's shape.** (S·M) When a fish echoes a word it learned from you (`mind_lexicon.gd` respond-to-known-word; Preoccupation #67), its babble uses the same syllable count as your word. The echo is audible, not only readable.
- [ ] **164. Each learned word has a sound.** (M·L) Each lexicon word gets a stable babble motif per fish, the same syllables every time. Over weeks, a keeper can recognize "food" or their own name for the fish in babble without reading. A proto-language in sound, grounded in the lexicon that already exists.
- [ ] **165. The tank's "we" sounds plural.** (S·M) Tank lines (`tank_mind.gd:505-511, 690-776`, for example "many small minds, one water") carry the tank breath plus a soft chord of three members' babble. Plural speech should sound plural.
- [ ] **166. Strong feeling skips language.** (S·M) Above a fear or joy threshold, the fish gives a call and a body act instead of a line. Words are for calm states, and the fish *chooses* the call. It makes words rarer and more meaningful, and it is closer to how a fish would be.
- [ ] **167. Line provenance on hover.** (M·M) Hovering a line in a journal or the strip shows why it was said: "said because: breath tight · heard alarm · hungry", from the grounding context. Validated lines cite their facts. Honesty becomes inspectable per line, not only as a policy.
- [ ] **168. A daily word allowance by temperament.** (S·M) Each fish's personality sets how many lines it can produce per sim-day: a chatty guppy gets about 6, a quiet oto about 1. Unspent allowance does not carry over. Individual voices stay precious, and the talkative ones are talkative because of who they are.
- [ ] **169. Chatter only between fish that can hear each other.** (S·S) Fish-to-fish chatter (`tank_dialogue.gd:769-771, 930-966`) requires both fish to be awake and within hearing range, and the pair's calls (§5) to be live. Overheard talk becomes a consequence of the world, not a scheduled event.
- [ ] **170. Bubbles read from above.** (S·S) In the top-down camera, thought bubbles and call rings sit on the water surface plane above the speaker, legible from the overhead view (`main.gd` "top" preset, TOPDOWN doc).
- [ ] **171. Localize every template, and let babble carry the rest.** (S·M) Move every fish and tank template to `assets/i18n/strings.csv` keys (`localization.gd` `register_key`). Babble and calls are language-agnostic, so a locale without full templates still has a voice.
- [ ] **172. Pictographic thought glyphs.** (M·L) A set of 12 tiny palette glyphs: pellet, wave, eye, moon, heart-ish bond mark, alarm star, question, rest, leaf, glass, light, a mark for "you". A fish can *show* one in its bubble instead of a word. This is the non-verbal-first voice (Night Watch's discipline) and the fallback for every locale and age. It is grounded: a glyph must match the workspace content.
- [ ] **173. Speaking to the absent.** (M·M) After a bonded partner dies, the survivor, at its partner's last place, sometimes produces a contact call and, rarely, one line grounded in episodic memory. It should be handled gravely and capped hard. Grief has a voice, and the voice is mostly a call into an empty space.
- [ ] **174. The first word is an event.** (S·M) The first line a fish ever produces (after its familiarity threshold) is recorded in the Chronicle ("Mira said her first words: …") and given a staging beat (#353). A first is a first.
- [ ] **175. Strip and voice obey the same budget.** (S·S) The 48-s follow cadence (`main.gd:305`), the 55-s Guardian cadence (`guardian_fish.gd:12`) and the 18-s global gap (`mind_narrator.gd:11`) become one documented voice-budget table in ARCHITECTURE.md §11, beside the motion channels. Any new voice path must declare where it sits in it.

---

# Part Two — The Awareness (176–325)

The tank's chemistry is modelled in loving detail (`water_chemistry.gd:25-52`:
ammonia, nitrite, nitrate, toxic NH₃, CO₂, pH, KH/GH, iron, cycle phase,
bacteria). The fish's felt self is architected in loving detail too
(protoself, core affect, qualia, felt-now, binding). **The wire between them
is cut in a dozen places.** Chemistry reaches the fish as scalar stress, not
as something it *feels*, *attends to*, *remembers*, *expects* or can *blame*.
No chemistry variable produces a workspace bid. The oxygen set-point is
dropped before it reaches expected free energy. The felt gills read nitrite
instead of oxygen. The homeostasis module never ticks in live play. The tank
computes "how am I doing" four separate times and never once over time.
This part rewires awareness from the body outward: repair, then water, body,
time, self-knowledge, and finally the tank knowing itself.

---

## §8 Repair the senses that are cut (176–200)

- [x] **176. [V] Tick `FishHomeostasis` in live play.** (S·L) `FishHomeostasis.tick` is called only from `mind_eval.gd:589, 619-620` and `poke_harness.gd:183`. In the game, `hunger_trend` stays 0, the dominant need and the need conflict never update, and `_homeostatic_feed_point` (read at `global_workspace.gd:409-410`) stays zero, even though `mind_active_inference.gd:86, 195` reads its errors every cycle. The eval harness has been measuring a module the game never runs. Call it in the perceive phase beside the protoself (`mind_cycle.gd:91-95`) and re-run `smoke_mind_eval.gd`, which must stay green.
- [x] **177. [V] Breathing enters expected free energy.** (S·L) `preferred_error` copies hunger, safety, social, rest and allostatic hunger (`mind_active_inference.gd:86-93`), but not oxygen, although homeostasis carries `o2_set` and `o2_err` (`fish_homeostasis.gd:32, 79-81`). Add a `breath` term. A suffocating fish then *wants* something (the surface, the airstone, the plants) instead of only getting more stressed. This is one line of code with a large behavioural payoff; guard it with the eval.
- [x] **178. [V] The felt gills should feel oxygen, not only nitrite.** (S·L) `_chem_o2_penalty` is a deliberate brown-blood model: nitrite cuts the O₂ the fish can carry (`fish.gd:4611-4613`). Behaviour correctly uses effective O₂, `dissolved_o2 − penalty`, for gulping, the O₂ pull and opercular tempo (`:4835, 6351, 7909`). But the protoself's `gill_rhythm`, pain and comfort read only the *penalty* term (`fish_protoself.gd:45-47`). A fish in genuinely thin water with no nitrite therefore has calm felt gills while its body gulps at the surface. Split it into:
  - `_breath_hunger`: deficit of effective O₂ against the species set-point.
  - `_gill_burn`: toxic NH₃ and nitrite irritation.

  Both are felt and both have distinct tells (#201, #203).
- [ ] **179. [V] Fix the always-true `water_feel` bid.** (S·S) `tank_mind.gd:194` reads `if o2 < 0.65 or o2 > 0.0`, which is true for every positive O₂, so the tank "feels its water" every tick at 0.3 salience. Replace it with a deviation measure from TankVitals (#301): salience rises with |vital − normal|.
- [ ] **180. One ammonia, everywhere.** (S·M) Three systems read three different ammonia measures:
  - The relief pulse uses total NH₃ (`fish.gd:1687-1696`).
  - Stress uses toxic NH₃ (`fish.gd:4599-4633`, pH-dependent via `water_chemistry.gd:215-218`).
  - ColonyMind uses total (`colony_mind.gd:194-206`).

  Felt toxicity should be toxic NH₃. Route all three through one `TankVitals` accessor, so relief and suffering are measured on the same scale.
- [ ] **181. Build the "worsening" detector the comment promises.** (S·M) `fish.gd:598-599` documents that worsening chemistry should read as alarm. Only improvement is detected (`:1694`). Add a falling-edge counterpart: a felt "worsening" pulse when a felt channel crosses into worse territory, with salience scaled by slope (§11).
- [ ] **182. [V] Rename `gut_fullness`.** (S·S) It lerps toward `f.hunger`, so a high value means *empty* (`fish_protoself.gd:48`). The current readers happen to treat it as hunger consistently: valence uses `(1 − gut_fullness)` (`fish_core_affect.gd:44`), and the gut bid fires above 0.42 (`fish_protoself.gd:94`). So it is a naming trap, not yet a bug. Rename it `gut_emptiness` before #198 shows the player "gut: full" on a starving fish, and audit `fish_spark_expression.gd:63, 93`.
- [ ] **183. Read `body_changed_notice`.** (S·M) It is written (`fish_protoself.gd:76-78`) and never read. A growth spurt is felt: a beat of disorientation, a stretch pose (#236), and a rare grounded line ("bigger"). Growth becomes something the fish notices about itself.
- [ ] **184. Gravidity is felt.** (M·M) `_gestation_progress` (`fish.gd:872`) and the belly mesh (`:910`) are invisible to the mind. Add a protoself `heavy` channel, so a gravid livebearer:
  - eats more and slows
  - seeks plant cover late in term
  - appears in the Mind panel as "heavy, near term".

  Today birth arrives with no lived run-up.
- [ ] **185. A chemistry bid in the workspace.** (M·L) No water variable produces a workspace bid (`global_workspace.gd:128-248`). Add `water_sense`. Its salience is the largest felt-water deviation × trend (§11) × species sensitivity (#219), and its content is the channel (`burn`, `thin`, `stale`, `sour`, `slack`). When the water is the most important thing, it wins the workspace, and attention, gaze, voice and narration follow.
- [ ] **186. Flow is felt by the lateral line.** (M·M) Sample `tank_flow_field.sample(pos)` (`tank_flow_field.gd:238`) into a protoself `flow_push` channel. Today flow-refuge steering is a steering rule (`fish.gd:6593-6605`), and the fin pose reacts to flow (`:3772-3777`). Make it a felt preference that tires the fish (#213) and enters EFE as rest error. Fish then choose the lee of a rock because swimming is easier there.
- [ ] **187. Temperature is felt.** (S·M) Today temperature changes swim tempo only (`fish.gd:7990-7997`). Add a `warmth` comfort channel: deviation from the species' preferred band lowers comfort, and the felt qualities are "slack" (warm) and "slow" (cold). A heater failure becomes an experience, not a tempo change.
- [ ] **188. Crowding is felt, per fish.** (S·M) Shoal-deficit stress exists (`fish.gd:4740-4744`), but overcrowding is only a tank-level feel (`tank_mind.gd:299-311`). Add a per-fish `crowded` channel from personal-space intrusions per second. Crowded fish are more irritable (more chases and fin-nips), and the tank's fullness has a felt source.
- [ ] **189. Nitrate and CO₂ get read at all.** (M·M) No fish or mind module reads nitrate, CO₂, KH/GH, iron or cycle phase.
  - Chronic nitrate: a slow `dull` malaise (lower baseline serotonin analog, drabber colour; FISH_ALIVE #284).
  - High dissolved CO₂ (`water_chemistry.gd:36, 299`): breathlessness even when O₂ reads fine, which is real CO₂ suffocation and a classic planted-tank killer. Fish gasp at the surface for a reason the HUD's O₂ chip does not show.
- [ ] **190. pH swings stress, not only pH levels.** (S·M) Fish tolerate a wide pH range but react to rapid change. Detect the pH slope over the last sim-hours and feel a fast swing as `sour`. Today pH matters only through ammonia toxicity (`water_chemistry.gd:215-218`).
- [ ] **191. The season reaches the fish's mind.** (S·M) Season drives breeding (`fish.gd:1304-1316`), but the mind never perceives it; the tank mind uses `season_night_bias` only for tick rate (`tank_mind.gd:119-121`). Add a slow `season_sense` to the mind context and the generative self, so seasonal mood (courtship restlessness, winter slowness) has a source.
- [ ] **192. The spark signals drive motion they already carry.** (S·M) Protoself values are copied into spark signals (`fish_spark_expression.gd:89-93`), but `motion_modifiers` ignores them. Wire:
  - gill burn → opercular tempo
  - fatigue → fin-carriage droop
  - comfort → easing of the pose
  - pain → guarding (#229).

  The felt body becomes the visible body.
- [x] **193. [V] Run `FishSparkExpression.tick`, so the spark shaders are applied.** (S·L) `sim_driver.gd:4328-4329` calls `motion_modifiers` directly. `FishSparkExpression.tick` (`fish_spark_expression.gd:267-272`), the only caller of `apply_shaders` (`:205`), has no callers. As a result, `irid_strength` (prediction-error shimmer), `color_vibrancy` (qualia contrast) and `fin_translucency` are never mind-driven. Call `tick` instead, and let the batch path set them as per-instance data. The feeling-to-colour bridge was built and never plugged in.
- [ ] **194. Consume `gaze_decouple`, and the other unread spark outputs.** (S·M) `wander_scale`, `turn_scale`, `speed_scale`, `spacing_bias`, `gaze_decouple` and `listless` are set but never read; only tail, fin and stillness are (`fish.gd:8695-8697`, `fish_spark_expression.gd:171, 191`). Wire each to its natural consumer: locomotion speed and turn gain, boids spacing, and eye-versus-heading decoupling. A listless fish should actually wander less.
- [ ] **195. One breath oscillator: `MotionBreath`.** (M·M) `motion_breath.gd:29 step(dt, o2, exertion, stress, temp, asleep)` is used only by smokes. The live breath is ad hoc (`fish.gd:7905-7910`). Make MotionBreath the single source for opercula, buccal pumping and girth, fed by the felt channels (#178). Breathing is the most legible sign of awareness a fish has, and it should come from one place that knows the body.
- [x] **196. The eyes go where the mind is.** (S·L) `MotionGaze` has threat, food, mate and rival priorities (`motion_gaze.gd:14`), but only `keeper` and `curiosity` are ever offered (`fish.gd:8918, 8925`; `fish_anticipation.gd:111`). After each broadcast, offer `look_at_point(kind, pos, hold_s)` (`:50`) for the workspace's primary content and its location. The fish looks at what it is thinking about. This is the single cheapest "it is aware" cue in the codebase.
- [ ] **197. Deliberation telegraphs itself.** (S·M) `FishAnticipation.note_hesitation` (`fish_anticipation.gd:181`) is driven by behaviour events, not by the mind. Call it when DDM conflict is high or when the volition veto fires. `FishSparkExpression.notify_veto` (`fish_spark_expression.gd:199`) has no callers, so wire the veto there too. A fish visibly almost-does something.
- [ ] **198. The Mind panel shows the felt body.** (M·L) After #2, add a "feels" block with six small meters and words: breath, burn, gut, fins/fatigue, comfort and heaviness, using the felt vocabulary (#201), never numbers. Today the protoself and core affect are visible only in the debug readout (`mind_debug.gd:149-179`).
- [ ] **199. The observation contract gets mind rows.** (S·M) `docs/OBSERVATION_CONTRACT.md:12-20` lists food, rest, shelter, schooling, grazing, growth and decay, with no mind rows. Add rows for:
  - "the fish looks at what it attends to"
  - "breath reflects felt oxygen"
  - "fish react to worsening water before it is lethal"
  - "a call has a visible effect"

  Then the probes have something to verify.
- [ ] **200. `smoke_state_awareness.gd`.** (M·L) Four scenarios on a real Fish, using `TestSupport.Suite`:
  - Raise nitrite: the `water_sense` bid appears, `_gill_burn` rises, a tell fires, and MindLegible shows "burn".
  - Drop O₂: the breath error steers toward the surface through EFE.
  - Improve the water: relief.
  - Worsen it slowly: the worsening pulse fires before the lethal threshold.

---

## §9 Feeling the water (201–225)

Fish never see numbers; they live inside chemistry. The game already
refuses digits in fish speech (`mind_narrator.gd:922-951`). This section
gives the fish a felt vocabulary of the water: one language shared by
qualia, voice timbre, the Mind panel and the tank itself.

- [ ] **201. One felt-water vocabulary.** (S·L) Add `data/mind/felt_vocabulary.json` with one canonical word per channel:
  - toxic NH₃: **sting**
  - nitrite: **rust** (nitrite causes "brown blood" in real fish)
  - O₂ deficit: **thin**
  - CO₂ excess: **stale**
  - chronic nitrate: **dull**
  - pH swing: **sour**
  - warm: **slack**
  - cold: **slow**
  - strong flow: **push**
  - crowding: **close**
  - clean recovery: **clear**

  `fish_qualia.gd`, prosody timbre (#86), the Mind panel, journals and TankVitals (#319) all read this file, so a word means the same thing everywhere. Localize the words, not the meanings.
- [ ] **202. Rust shows in the gills.** (S·M) Under nitrite, the gill edge takes a brown palette shift (FISH_ALIVE #283), driven by the `_gill_burn` channel from #178. This is a real diagnostic sign, so an experienced keeper can read it.
- [ ] **203. A hypoxia ladder, one felt variable deep.** (M·L) One `breath_hunger` value drives a staged ladder:
  - mild: faster opercula (#195)
  - moderate: rising in the column and hovering below the surface
  - severe: gulping at the surface, schools massing at the top (FISH_ALIVE #137), labyrinth fish surfacing more often
  - critical: lethargy.

  Each rung is reversible and has hysteresis. This is the textbook sequence a real keeper recognizes, and the tank's clearest "it knows" signal.
- [ ] **204. Water has places.** (M·L) Chemistry is tank-global today. Add a coarse 3D felt-water field (about 8×4×4 cells) offset from the global values by:
  - flow from `water_current.gd`
  - plant O₂ (photosynthesis near leaves, respiration at night)
  - substrate `anaerobic_gas` (`substrate_grid.gd:121`)
  - decay sources (#208).

  Fish sample it locally, and EFE seeks better pockets (FISH_ALIVE #316). Fish *moving to better water* is awareness the player can watch.
- [ ] **205. Food has a taste.** (S·M) Fresh food tastes good and old food is bad: waste particles past a decomposition age (`waste_particle.gd`) taste bad. Real fish spit out and re-take food; show the spit (a jaw-pose snap) and a brief aversion learned per food type. Choosiness is a form of perception.
- [ ] **206. The fish smells the food before it lands.** (S·M) When the keeper picks a food in the dock (`main.gd` feed tool) and hovers over the water, fish with learned feed-time beliefs orient toward the surface with "sniffing" (`pec_forward`, mouth pulses) before anything drops. Chemical arrival precedes sight.
- [ ] **207. The water carries dread.** (M·M) An injured or dying fish releases an alarm cue into the felt-water field (#204). It diffuses and decays over minutes, and fish passing through feel `dread` (a fear residue with no visible cause). Cross-reference DEEP_SCIENCE's Schreckstoff item and implement it as a field channel, not a broadcast.
- [ ] **208. The water remembers a death.** (M·L) A decomposing body raises local ammonia in the field (#204) and the dread cue (#207). Fish avoid the spot for days through spatial schemas at sleep (`episodic_memory.consolidate_sleep`). Avoidance decays only when the water there is clear again. The tank's grief is partly chemical, and that is true of real tanks.
- [ ] **209. A water change is felt as relief.** (S·M) `sim_driver.do_water_change` (`:2029`) already notes care per fish. Add a staged response:
  - an immediate startle at the inflow
  - then relief as the felt channels clear
  - a visible perk-up (CREATURE_MOTION #459)
  - the tank's breath deepening (#95).

  The keeper should *feel* that the water change mattered.
- [ ] **210. Light is felt warmth.** (S·M) Some species rest in light patches. Sample caustic and god-ray intensity at the fish (`tank_illumination.gd`). Light-loving species settle into dapples, and shy ones (#211) avoid them.
- [ ] **211. Exposure is felt.** (S·M) Photophobic species (cory, pleco, oto, loach) get an `exposed` channel from light intensity × lack of cover nearby. They stay near shelter when exposed and come out as the light drops. The nocturnal inversion gets a felt cause instead of a schedule.
- [ ] **212. Vibration and pressure are felt.** (S·M) Taps (`motion_field.inject_startle`, `motion_field.gd:39`), the filter outlet and loud music produce lateral-line `pressure`. Familiar keepers' taps are discounted (#334). A fish's tolerance of noise becomes individual and learned.
- [ ] **213. Current tires.** (S·M) Swimming against `flow_push` drains energy in proportion to speed relative to the flow (`hydrodynamics.gd`). Fish rest in the lee after a long push, and the felt fatigue explains it.
- [ ] **214. Murk narrows sight.** (M·M) Turbidity (REAL_TANK's turbidity, water clarity) shortens the visual perception radius. Fish compensate with calls (#115) and tighter schools. A cloudy tank changes what the fish can know, and the player sees the school tighten.
- [ ] **215. Grazing is satisfying.** (S·S) Otocinclus and plecos get felt satiety from biofilm grazing (`biofilm_patch.gd`), so a well-grazed glass is a content grazer. Their satisfaction appears in the Mind panel as "fed by the glass".
- [ ] **216. Beliefs about the water.** (M·L) `fish_learned_mind.gd:736-852` learns beliefs with confidence and surprise about feed times, regions, chasers and keeper tone, but never water. Add a water family:
  - `water_worse_after_big_feed`
  - `better_near_plants`
  - `thin_before_dawn` (the real pre-dawn O₂ trough)
  - `clear_after_keeper_change`

  Each has confidence and violation surprise. Fish *expect* water, and are surprised by it.
- [ ] **217. Fish attribute their malaise.** (M·L) When felt state worsens, the mind assigns a cause: the water, a rival, hunger or the light, according to which channel moved most over the window. The attribution:
  - enters the workspace content
  - shapes the reply ("it's the water, not you")
  - is validated against the channel that actually moved (#300 K2).

  This is the difference between suffering and knowing why.
- [ ] **218. The rummy-nose is the canary.** (S·L) Real aquarists watch rummy-nose tetras because their red head pales under poor water. Drive `rummy_nose` red saturation from felt water (sting, rust, dull, thin), with a lag. The game then has a real, learnable bio-indicator. Add a one-time glossary entry: "when their noses pale, check the water".
- [ ] **219. Species sensitivity ranking.** (S·M) Give each species a `water_sensitivity` in the genome. The most sensitive species feels the water first and shows it first, so the tank's early warning lives in its most delicate member. The Mind panel notes "feels the water first".
- [ ] **220. The colony shares the vocabulary.** (S·M) Shrimp moult failures, snails sealing up and floating, worms surfacing: `ColonyMind`'s water stress (`colony_mind.gd:194-206`) maps to the same felt words (#201). "The snails feel the sting too" should be a sentence the tank can truthfully say.
- [ ] **221. Nausea overrides hunger.** (S·M) In bad water, fish refuse food (FISH_ALIVE #298). Add a felt `nausea` that rises with sting and rust and gates the food bid. A keeper who keeps feeding a refusing tank learns something true about real fishkeeping.
- [ ] **222. Vigilance after a crash.** (S·M) After a severe event, a lasting mood residue scaled by severity and decaying over days (FISH_ALIVE #295), stored in the fish's save (`fish.gd to_save_dict`). Fish that lived through a crash are jumpier for a week.
- [ ] **223. The fish's weather.** (S·M) A one-line, per-fish felt-water summary in the Mind panel, written as weather: "thin, clearing", "close and slack", "clear". The felt channels compose into one glanceable phrase.
- [ ] **224. Tolerance runs in families (stylized).** (M·M) Offspring of fish that survived a crash inherit slightly higher tolerance: a small heritable shift in `water_sensitivity`, through genetics. Over generations, a tank that survived hard times is a little tougher. Mark it stylized, a light epigenetic-like gloss.
- [ ] **225. Numbers stay on the keeper's side of the glass.** (S·M) This is a design rule. The fish's water is words and bodies; the HUD's chemistry chips (`hud_controller.gd:6-114`) are the keeper's instruments. Keep the digit ban in fish speech (`mind_narrator.gd:922-951`) and extend it to Mind-panel felt rows. The two vocabularies meet only in the glossary (#116) and the vitals card (#459).

---

## §10 The body as it is lived (226–250)

There is no health, injury or disease system. Pain is `stress × 0.4` plus the
nitrite penalty (`fish_protoself.gd:67-68`). `_scarred` is a fright latch,
not a wound (`fish.gd:4763-4768`). These items give the body a history,
something it can lose and recover.

- [ ] **226. `fish_health.gd`: a condition score.** (M·L) A condition score from 0 to 1, built from chronic stress, nutrition (meal history), felt water exposure and age. It moves slowly, over hours to days. It is shown through colour vibrancy, fin carriage and appetite, and it feeds `vitality_decline`. It is the missing middle between "fine" and "dead".
- [ ] **227. Fins tear and heal.** (M·L) Fights and fin-nips notch the caudal or dorsal fin: reduced `caudal_spread` plus a 1-px notch in the fin voxels. Fins regrow over days at a rate set by condition (#226) and water. A healing fin is a body with a history the player can watch.
- [ ] **228. Ich, the classic (L).** (L·L) White-spot disease, triggered by stress plus a sudden temperature drop:
  - visible palette-white 1-px spots
  - flashing and rubbing, using the existing tells (`fish.gd:7034-7078`)
  - spread by proximity.

  It resolves with warmth and water changes, or it kills. This is the single most recognizable fish illness and the anchor of the unwritten Health/Disease topic. Ship it behind a scenario flag first.
- [ ] **229. Pain is nociception, not stress.** (M·M) Pain comes from injury (#227), with location. It produces guarding (less use of the hurt fin, more pectoral sculling), and it fades as the injury heals. Replace `stress×0.4` with real inputs, and keep stress as a separate channel.
- [ ] **230. Exertion debt.** (S·M) Long chases and escapes accumulate a short-term debt that forces a recovery hover, a lower `fin_carriage` and opercula working hard (#195). Seconds-to-minutes fatigue, distinct from sleep debt.
- [ ] **231. Fullness is felt and seen.** (S·M) After a big meal, a rounder belly (`fish_phase2_pose.note_meal`, `:324`), a sluggish glide, and the felt gut reading "full" (after #182). The fish then refuses the next pellet without nausea; it is simply full.
- [ ] **232. The body knows its size.** (S·M) Confidence and boldness scale with relative size among neighbours (body length versus the local mean). Fish grow more confident as they grow. Size awareness drives dominance and the use of space.
- [ ] **233. The ageing body shows.** (M·M) With `mortality_shift`:
  - `MotionPersonality` tempo decays and turns slow
  - fin edges fray slightly
  - colour dulls (CREATURE_MOTION health vocabulary)
  - the felt "slow fade" texture (`fish_core_affect.gd:75-76`) is visible.
- [ ] **234. The day's energy curve.** (S·S) A Mind-panel sparkline of `energy` over the sim-day, marked with meals and rests. The fish's day, written by its body.
- [ ] **235. Fish yawn.** (S·M) Real fish yawn, with a slow jaw gape and stretch, especially after rest and before activity. Trigger it from rest debt and the sleep-to-wake transition using the `jaw` channel (`motion_pose_library.gd:24`). It is tiny and unexpectedly charming.
- [ ] **236. Stretching after stillness.** (S·S) A body-arch and fin-spread "stretch" pose after long inactivity. The body resumes itself.
- [ ] **237. Gill flushing: the cough.** (S·M) Fish "cough", reversing water flow over the gills to clear them, more often in irritated water (FISH_ALIVE #129). Trigger it from `_gill_burn` with a tiny water-pop sound. A coughing tank is a tank whose water stings.
- [ ] **238. A favourite scratching stone.** (S·M) Flashing and rubbing are tells today. Let each fish remember the rough stone it rubbed on (a landmark in `fish_environment.gd:781-797`) and return to it. Irritation becomes a behaviour with a place.
- [ ] **239. Labyrinth breath as a lived rhythm.** (S·M) Bettas and gouramis track an air-breath interval and surface when it is due, with the "kiss" sound (#33). The interval shortens in warm water and with exertion. A fish that must breathe air knows when it needs to.
- [ ] **240. Swim-bladder trouble.** (M·M) After overfeeding or in cold water, a temporary buoyancy problem: listing and a head-down tilt (CREATURE_MOTION #445). It is felt through the protoself orientation channel, which already exists. It resolves with fasting. A fish can know it is *off*.
- [ ] **241. Convalescence.** (S·M) Recovery from injury, crash or illness passes through a "convalescent" mood: low exploration, more rest, slow return to baseline. Relief (`fish.gd:1687-1696`) is the first beat, and convalescence is the paragraph.
- [ ] **242. A body diary.** (S·M) A "lived body" tab in the fish journal (`fish_journal.gd`) records scars, illnesses, growth spurts, broods and crashes survived, all grounded and dated. Its age becomes a story of a body.
- [ ] **243. The body withdraws before death.** (M·M) As `vitality_decline` rises, in the days before a natural death the fish seeks a quiet corner, its colour fades, and it eats less. The last-lucidity line (Soul #49) then lands on something the player has watched coming.
- [ ] **244. A body in peak condition displays.** (S·M) High condition (#226) increases `display_fin_mult` (`fish_exaggeration.gd:88`) and courtship call quality (#104). A healthy fish *shows* it, honestly.
- [ ] **245. "How are you?" is answered from the body.** (S·M) When the keeper asks a fish how it is, the answer comes from the dominant protoself channel and the felt-water word ("thin… better now"). It is validated against the channels. Today's replies are grounded in workspace and mood, not in the body.
- [ ] **246. Others see the sick.** (M·M) Tankmates perceive a fish's tells (flashing, listing, pallor). Some species avoid the sick fish, as many shoaling fish do, and bonded partners stay near it. This is the social face of illness (§12).
- [ ] **247. The body learns from food.** (S·S) Meals that preceded nausea or bloating (#221, #240) become aversive for that food type. It is a one-trial learned taste aversion, which is real and fast in fish.
- [ ] **248. A stuck or trapped fish is noticed.** (M·M) A fish wedged behind hardscape or stuck in the flow stops calling (#114) and starts making distress calls (#41). Partners come to look, and the tank's attention (TankMind) turns there, so the keeper finds it.
- [ ] **249. Felt temperature shock.** (S·M) A sudden temperature change (a water change at the wrong temperature) gives a short startle, pallor and a stiff swim. Real keepers learn to temperature-match, and the game can teach it through the body.
- [ ] **250. Eval: the body is causal.** (S·M) Add invariant B1. Inject a felt channel (`_gill_burn`, `breath_hunger`, `heavy`) on a real fish, then measure a behavioural change in the expected direction within N ticks (`mind_eval.gd` pattern). The felt body must *do* something.

---

## §11 Time, trend and foreboding (251–275)

Awareness of state over time is where a mind begins. The fish has a
specious present (`fish_felt_now.gd:34-71`) and relief/dread against a slow
baseline (`fish_qualia.gd:49-54`). Neither the fish nor the tank knows
whether the water was better *yesterday*.

- [x] **251. History rings for every vital.** (S·L) `TankVitals` (#301) keeps a ring per variable: 1 sample per sim-minute for 24 sim-hours, plus 1 per sim-hour for 14 sim-days. It stores short and long slopes, bounded and saved. This is the memory that trend awareness needs. Today there is a smoothed `stability` and a crash count (`sim_driver.gd:1486-1503`), and nothing else.
- [ ] **252. "It's getting worse" is an event.** (S·L) A trend detector fires when a slope stays past its threshold for N samples. It emits `MotionEvents` `worsening` (#354), a tank bid, and a fish bid scaled by sensitivity. Fish and tank react to the *direction* of change, which is how real organisms are wired.
- [ ] **253. A forecast for tonight.** (M·L) A lite autoregressive forecast of dawn O₂ from the evening O₂, plant biomass and stocking, which captures the pre-dawn trough. When it predicts a thin night:
  - sensitive fish rest earlier
  - the tank breath shortens at dusk
  - the Guardian may say one honest line ("tonight will be thin").

  The tank anticipates its own body.
- [ ] **254. Felt elapsed time per fish.** (S·M) Fish track how long it has been since they were fed, since the keeper was here, and since lights out. Night Watch #61 gave the tank a sense of duration; give it to individuals too, feeding the waiting behaviours (#267, #268).
- [ ] **255. Anniversaries.** (S·M) The tank's founding day, fish birthdays and the day the Guardian was chosen. The Chronicle marks them, and the tank voice says one line at most per anniversary. Time has landmarks.
- [ ] **256. A memory of better water.** (M·M) Store episodic snapshots of the felt water at notable times. A fish in a declining tank can compare: "it was clearer". Grounded: the comparison must cite a stored snapshot.
- [ ] **257. The tank learns what you did.** (M·L) Causal attribution over time windows. After a keeper action (water change, plants added, feeding cut back), compare the vital slopes before and after. If the change is significant, record "since you added plants, breath is easier" as a tank belief with confidence. The tank models the keeper as a cause, and the keeper learns their care is noticed.
- [ ] **258. Daily rhythms become expectations.** (M·M) The dawn O₂ dip, the feed hour and the lamp schedule are learned as expected trajectories, using the same machinery as the feed-time beliefs (`fish_learned_mind.gd:736-753`). Deviations produce surprise. A late lamp is noticed.
- [ ] **259. The tank knows its age and stage.** (M·M) Cycle phase (`water_chemistry.gd:28`, read by no mind today) and the tank's age give life stages: cycling, settling, established, mature, old. The tank self-model and tank voice know which stage it is in ("we are still settling"), and the fish are more cautious in a cycling tank.
- [ ] **260. Foreboding becomes allostasis.** (M·L) Forecast risk (#253) shifts `preferred_error`: anticipated thinness raises the breath term before it happens. This closes Rising Curve #35 (allostasis) with a concrete input. A fish acting on what *will* be felt is the felt-time capstone.
- [ ] **261. Early signs are recognized.** (M·M) After a crash, the tank stores the vital signature of the hour before it. The next time that signature appears, vigilance comes faster. The tank learns its own prodrome.
- [ ] **262. Crash scars.** (S·M) The crash count (`sim_driver.gd:1486-1503`) becomes a dated list of crashes with their severity, in tank memory. It shapes the tank's temperament (#324) and is narrated sparingly ("we have been through three hard nights").
- [ ] **263. The voice follows trends, not levels.** (S·M) Chorus density and call types respond to slopes (§6 #145). A worsening tank sounds worried while it is still within safe levels. Early awareness becomes audible.
- [ ] **264. A felt-water strip.** (S·M) In the vitals card (#459), a 14-day pixel strip coloured by the dominant felt word per day: clear, thin, sting, and so on. Days with keeper care are marked. A keeper sees their tank's last two weeks at a glance, in the fish's language.
- [ ] **265. The dawn summary includes yesterday.** (S·S) `_note_dawn`'s self-summary (`tank_mind.gd:421-429`) adds the trend: "the water held", "a thin night; clearing". It is only meaningful once #369 stops `_note_dawn` from firing every tick.
- [ ] **266. Under threat, time stretches.** (S·M) Extend the tank's dilation under oxygen sag (Night Watch #66) to fish. Under threat, the `fish_felt_now` window shortens and the sample rate rises, so the fish is more responsive. Afterwards, the event is remembered as longer (an episodic duration weight).
- [ ] **267. Waiting at the feeding spot.** (S·M) Near a learned feed time, fish gather at the feeding place and impatience grows: more turns and more glances up. Relief comes when food lands, disappointment when it doesn't. Patience is a state with a visible arc.
- [ ] **268. Waiting for the keeper.** (M·M) If the keeper's usual visit hour passes (keeper model in `mind_keeper_model.gd`), familiar fish drift to the front glass and wait, fading after about 20 sim-minutes. It is grounded in learned visit cadence. It must never guilt the keeper (COMMS rules), so there is no text, only fish at the glass.
- [ ] **269. Reunion.** (S·M) On return after an absence, familiar fish greet (#123), and the felt "longing residue" (already persisted) resolves to relief. Cross-reference LEARNING_MIND III's separation/reunion and implement it through the felt layer.
- [ ] **270. Guardian advice speaks trends.** (S·M) The Guardian advisor (`keeper_care.gd:344-356`) moves from state ("ammonia is high") to trend in the fish's vocabulary ("three days of sting, rising"), with the number one click away on the HUD.
- [ ] **271. A slow day and season predictor.** (M·M) Rising Curve #47 (open) becomes a vitals forecaster over the 14-day ring. It powers #253, #260 and the weekly rhythm (#390).
- [ ] **272. The keeper's week.** (S·M) The keeper model learns the weekly visit pattern (weekend mornings, weekday nights) and the tank's anticipation follows it.
- [ ] **273. "The week" card.** (S·M) A weekly Chronicle card that combines the felt-water strip, the song of the day (#138) for the best day, the key events and the keeper's care. The tank's week, told by the tank.
- [ ] **274. Anticipated births.** (S·M) With gravidity felt (#184), the tank knows a birth is near. A tank-voice line is permitted ("Mira is close"), and partners stay nearer. Expectation runs ahead of the event.
- [ ] **275. An honest forecast.** (S·M) Forecasts carry confidence, and the voice hedges ("maybe thin tonight"). After the night, the forecast is scored, and the tank's forecasting confidence calibrates (#276). A mind that is sometimes wrong about tomorrow, and knows it, is more believable than an oracle.

---

## §12 Knowing what it knows (276–300)

Self-model confidence today is a formula on stress and vigilance
(`mind_self_model.gd:30`). The meta lines ("I've been scared a long time")
fire on instantaneous values (`:98-103`). Metacognition needs a record of
being right and wrong.

- [ ] **276. Calibrated confidence.** (M·L) The GRU world model predicts hunger, stress and curiosity (`mind_world_model.gd:150-174`). Score those predictions with a rolling Brier-style score and set `confidence` as the calibrated accuracy, blended with the current formula during migration. Confidence then means "my predictions have been right lately", which is what the word means.
- [ ] **277. Meta lines from durations, not instants.** (S·M) Use `fish_felt_now` history and core-affect residue for "a long time", "since dawn", "again". A meta line is permitted only when the stored duration supports it.
- [ ] **278. "I don't know" as a state.** (M·M) When world-model variance is high and relevant beliefs are low-confidence:
  - the fish shows exploratory caution: slow approach, more saccades (#284)
  - the voice uses unsure forms (#292)
  - the Mind panel says "unsure".

  Not-knowing is visible.
- [ ] **279. Uncertainty about the water itself.** (S·M) Water beliefs (#216) start at low confidence in a new tank. Fish explore the tank's chemistry pockets (#204) to learn them, and settle once confident. A new tank is *unknown*, and its fish behave like it.
- [ ] **280. The sound of surprise.** (S·M) A large prediction error produces the existing double-take, plus a tiny upward chirp for vocal species (stylized for most). The Utterance has `intent: surprise`. Surprise is heard.
- [ ] **281. Learning moments.** (S·L) When a belief's confidence crosses a threshold up or down (`fish_learned_mind.gd`), the fish holds a brief still pose with gaze on the relevant thing, and a glyph appears (#172). A journal line records it: "learned: food comes at dusk". Learning becomes an observable event, not a hidden parameter update.
- [ ] **282. Unsure fish ask, they don't alarm.** (M·M) Gate alarm calls on confidence. A low-confidence fish that perceives a possible threat gives a `query`-flavoured contact call. Others answer if they know. False alarms drop, and the school's knowledge is pooled.
- [ ] **283. Copy when uncertain.** (M·M) A fish uncertain about where food is follows a confident neighbour, which is the social-learning strategy documented in fish. Gate it on its own uncertainty, not at random. Followers and leaders emerge from knowledge.
- [ ] **284. Doubt is in the eyes.** (S·M) Scale `MotionGaze` saccade rate (`motion_gaze.gd:98 step`) with uncertainty. Confident fish fix their gaze; doubting fish look around. It is a small, real cue.
- [ ] **285. Self-knowledge of mood, with trends.** (S·M) The self-model reports a mood *trend* ("lighter today"), validated against the core-affect history. The fish knows how it has been, not only how it is.
- [ ] **286. Confabulation, measured.** (M·M) Partial introspection is shipped (Soul #5). Compare the fish's self-report with its actual drives. When they diverge, the Mind panel marks the report "may be wrong about itself". It is honest, it is scientifically interesting, and it is very fishlike.
- [ ] **287. Memory confidence.** (S·M) Retrieval strength from `episodic_memory.gd`'s cosine score becomes "I remember the driftwood" versus "faintly". The voice and the panel reflect it.
- [ ] **288. Checking.** (S·M) When a remembered place's memory nears decay, the fish revisits it to refresh. Patrolling known places is real in territorial fish. Forgetting creates behaviour.
- [ ] **289. Who saw what (stylized).** (M·M) Extend theory of mind (`_tom_pred`) to visual perspective. A fish is more likely to grab food a rival did not see, using line-of-sight from the rival's gaze. Some fish show audience-sensitive behaviour; mark the rest stylized.
- [ ] **290. Tank metacognition.** (M·M) TankVitals estimates carry confidence: little history means low confidence. The tank knows what it doesn't know: "we don't know the new fish yet", "the water is new to us".
- [ ] **291. The tank knows how well it knows you.** (S·M) The keeper model's confidence comes from visit count and consistency. Early on: "we don't know you yet". Over weeks the line changes, grounded in the count.
- [ ] **292. Hedges match confidence.** (S·M) Templates and the model reply schema get three confidence registers (certain, likely, unsure) chosen from the calibrated value (#276). Validator: no certain-register line below a confidence floor.
- [ ] **293. "That worked."** (S·M) After an action that reduced free energy (a successful forage or escape), a satisfied settle: a fin flare and a slowing glide, scaled by the prediction-error reduction. Success is felt and shown.
- [ ] **294. Frustration at a miss.** (S·M) A failed strike or lost food produces a short frustration flick scaled by the expected value lost. Expectation violated, visibly.
- [ ] **295. Bold fish are overconfident.** (S·M) A personality bias on calibration: bold fish systematically over-estimate, shy fish under-estimate. Honest variety, and real (boldness is linked to risk-taking in fish).
- [ ] **296. "Why are you unsure?"** (S·M) The "what are you thinking?" reply (Soul #10) gains a "why unsure" branch, answered from the uncertainty sources: an unknown fish, a new place, a changed light. It is grounded in variance terms.
- [ ] **297. Being watched is perceived.** (M·M) `update_player_glance()` is a proxy built from orbit position and stillness (`sim_driver.gd`). Make "being watched" a fish percept even so: within the glance, bold fish approach and display and shy fish retreat (the audience effect). The fish knows when it is looked at, as far as the game can know.
- [ ] **298. The reflection at the glass.** (M·M) Fish respond to their own reflection; reflections are staged at `fish.gd:6799`. They display, then habituate. Model the habituation per fish; a fish that has learned its reflection ignores it. Most fish do *not* pass mirror tests (cleaner wrasse is the debated exception), so it stays habituation, honestly.
- [ ] **299. Rank awareness.** (S·M) Fish know their dominance rank from fight outcomes. Subordinates yield space and dominants patrol. Rank shows in the Mind panel and in body carriage.
- [ ] **300. Awareness eval invariants.** (M·L) Add four invariants to `mind_eval.gd`:
  - **K1 calibration**: confidence correlates with prediction accuracy across a run.
  - **K2 attribution**: the blamed cause matches the channel that moved.
  - **K3 trend latency**: the worsening event fires before the lethal threshold in a scripted slow decline.
  - **K4 self-report honesty**: a reported state is within tolerance of the actual state.

  All required. Honesty gate H extends to the new files.

---

## §13 The tank knows itself (301–325)

"How is the tank doing" is computed four times today, in four places:
`sim.stability` (`sim_driver.gd:1486-1497`), `KeeperCare.mood_score`
(`keeper_care.gd:51-94`), `ColonyMind.water_stress` (`colony_mind.gd:194-206`)
and the audio vitality (`ambient_audio.gd:874-883`). TankMind ignores
ammonia and nitrite directly. A mind cannot know itself through four
disagreeing instruments.

- [x] **301. `tank_vitals.gd`: one tank self-model.** (Owner + rings + snapshot + save/load shipped; `stability` now reads `TankVitals.stability_instant`. The other three readers — KeeperCare.mood_score, ColonyMind.water_stress, AmbientAudio vitality — and the lint smoke remain follow-up.) (M·L) A single owner computes every vital, its normal, its deviation, its trend (#251), its forecast (#253) and its confidence (#290). The four existing computations become readers of it, and a lint smoke forbids new direct chemistry→stress formulas outside it. This is Lever 2's hinge: everything in Part Two that says "the tank" reads `TankVitals.snapshot()`.
- [ ] **302. Vitals grouped as a body.** (S·L) Organize the vitals as organs:
  - **Breath**: O₂, CO₂.
  - **Blood**: toxic NH₃, nitrite, nitrate. The water is the tank's blood.
  - **Warmth**: temperature.
  - **Digestion**: mulm, detritus, biofilter load.
  - **Growth**: plant biomass and its slope.
  - **Nerves**: fish arousal and strain.
  - **Sleep**: night quality.
  - **Voice**: the chorus index (#140).

  The metaphor organizes the data, and the data stays literal.
- [ ] **303. TankMind reads the blood.** (S·M) TankMind bids today come from stability, O₂ and fish averages, never NH₃/NO₂ directly. Add organ bids from vitals deviations, such as `blood_sting` and `breath_thin`, so the tank's attention can land on what is actually wrong.
- [ ] **304. Tank focus flows downward.** (M·L) When a vital wins the TankMind workspace, every fish gets a small prior toward the related behaviour: breath leads to calm and surfacing, blood to avoiding decay pockets. This goes through the bid-generator registry (`global_workspace.gd:81`, `register_bid_generator`, which has no runtime callers yet). The tank's concern becomes the residents' slight concern. This is Preoccupation's "felt before voiced", applied to homeostasis.
- [ ] **305. The tank has a "normal".** (M·M) The vitals' normal is learned from the tank's established state (a rolling 7-day median), not a textbook value. Deviation from *its* normal is the tank's free energy. A blackwater tank and a reef tank each feel like themselves.
- [ ] **306. Tank allostasis.** (M·L) On a predicted thin night (#253), the tank's prior nudges fish to rest earlier and calmer, which lowers metabolic O₂ demand. That is literally true of resting fish. It is the first act a tank-mind performs *on its own body*.
- [ ] **307. Tank sickness and recovery modes.** (M·M) After a crash the tank enters a distinct mode:
  - a thin chorus (#145)
  - drabber colours, through the palette overlay
  - a minor-leaning music bed
  - more rest and slower speech.

  Then it passes into "recovering". These are modes with entry and exit criteria, so the tank has a convalescence too.
- [ ] **308. The self-summary is written from vitals.** (S·M) `self_summary` changes for only 4 foci and at dawn (`tank_mind.gd:340-347, 421-429`). Regenerate it when a vital crosses a band or a trend fires: "the blood is clearing; breath is easy".
- [ ] **309. The tank stream speaks from vitals.** (S·M) Tank stream lines (`tank_mind.gd:366-407`) are grounded in vital organs and trends, not only night state. Combined with #16 they finally reach the player.
- [ ] **310. The tank knows its residents.** (S·M) A census in tank memory: who lives here, who is new, who is missing (died or removed), and for how long. "We are fourteen. Pip is gone two days." It is grounded, and it is the tank's sense of its own body count.
- [ ] **311. The tank knows your care.** (S·M) Care actions are already noted (`note_keeper_care_for_fish`, `sim_driver.gd:2035`). The tank aggregates them into a care history and attributes vital changes to them (#257).
- [ ] **312. The tank's body map.** (M·L) A coarse felt map of where the tank is unwell (the felt-water field from #204, dead flow zones, anaerobic substrate). The tank attends to a *place* ("the back corner is stale"), fish avoid it, and the Mind Lens shows it (#455).
- [ ] **313. Wounds.** (S·M) A decaying plant mass, a dead fish or an anaerobic pocket is a "wound". TankMind focus visits it, detritivores converge (#314), and the felt field around it recovers as it heals.
- [ ] **314. The cleanup crew as an immune response.** (M·M) Snails, shrimp and worms converge on decay through `ColonyMind` responding to the wound signal. Framed in the Loom Anatomy (#326) as the tank's white cells. Visible convergence on a dead body is real, and it is the tank tending itself.
- [ ] **315. The tank knows it is cycling.** (S·M) In fresh tanks (`cycle_phase`), the tank self-model reports "settling". Fish are warier, the chorus quieter and the Guardian gentler. This connects the onboarding story (ONBOARDING's fresh vs established decision) to the tank's own awareness.
- [ ] **316. Fullness affects breeding.** (M·M) Felt fullness (Night Watch #7) combined with bioload versus filtration lowers breeding readiness when the tank is full. This is density-dependent reproduction, a self-regulation the tank performs and can name ("we are full").
- [ ] **317. Define the tank's action space.** (M·M) Write down what the tank-mind may do: shift fish priors (rest, gather, quiet, alarm sensitivity), colony priors and presentation (voice, chorus, light overlay). It may *never* touch physics or chemistry. Encode the list in `tank_mind.gd` as a const whitelist, with an eval check. A tank-mind that cheats physics is a lie.
- [ ] **318. The tank knows its room.** (S·M) Room presets (`tank_config.gd:791-972`, for example sunny_window, dark_cabinet, night_window) set the expected light and warmth curves. The tank expects afternoon sun in the window room and is surprised if the room changes. Its world includes the room.
- [ ] **319. One language for fish and tank.** (S·M) Tank vitals use the felt vocabulary (#201), so when a fish feels "thin" and the tank says "breath is thin", they are visibly the same fact. The tank's self-knowledge and the fish's feeling are one language.
- [ ] **320. Tank mood shows in the water, unclamped.** (M·M) The mood overlay (`tank_mind.gd:212-223` → `night_watch.gd:412-418` → `music_context.gd:821-861` → `voxel_mat.gd:1269-1286`) has its saturation and value pinned at the shader clamp whenever it is present, so the mood never actually reads. Fix it in #371, then tune the overlay ranges so a content tank and a sick tank are distinguishable at a glance.
- [ ] **321. The return recap tells the vitals' story.** (S·M) The away recap (`night_watch.gd:90-135`) uses the vitals history: "while you were away: one thin night, then clear; the snails cleaned the back". The offline fallback (`make_it_there.gd:629-650`) ignores `tank_away_lines` and `tank_self` today. Fix that, so template players get it too.
- [ ] **322. The unwatched tank records what it felt.** (S·M) During the away simulation, the vitals ring keeps sampling, so the recap and the felt strip (#264) cover time the keeper was gone. The tank lived through it and remembers it.
- [ ] **323. One snapshot API for every consumer.** (S·M) The Guardian, music, HUD, chorus, colony, narrator and lens read `TankVitals.snapshot()` through `SimGate` (AGENTS.md: the guarded seam accessor). `smoke_service_contracts.gd` asserts the contract.
- [ ] **324. Tank temperament.** (M·M) Derive the persisted tank soul's temperament (Night Watch #10) from history: a tank that has crashed often is "watchful" and reacts faster to early signs, and one that has been calm for months is "easy". The tank's character is its biography.
- [ ] **325. Tank self-model invariants.** (M·L) Add to `mind_eval.gd`:
  - **T1**: a vital deviation becomes TankMind focus within N ticks.
  - **T2**: that focus produces a measurable fish-behaviour shift (#304).
  - **T3**: on recovery, the focus releases and the mode exits (#307).
  - **T4**: the action whitelist is honoured (#317).

  Required. A tank-mind must be testably aware of its own body.

---

# Part Three — The Mind (326–475)

The game is called *walstad loom*. A loom holds the **warp**, slow threads
under tension that persist (plants, substrate, chemistry, the light cycle),
while the shuttle carries the **weft** across, again and again (the fish).
The pattern exists only in the interlacing. That is also the best short
description of a mind in the global-workspace sense: many parallel processes,
one woven pattern of attention at a time.

The tank-mind exists today: TankMind's workspace, ignition, mood, self-summary,
stream, colony minds, the cathedral, the "Us" hymn. But a player sees an
unlabelled chime, a ~5° hue shift, and lines they must type to get. This part
makes the metaphor *structural*: every tank system has a role in the mind, and
the mind is staged in water, light, motion and sound. It holds to the
[SOUL_CREED](SOUL_CREED.md): "no myth pasted over mechanism". Every mapping
below names what is literally computed.

---

## §14 Anatomy of the loom: the tank's brain map (326–350)

- [ ] **326. `docs/LOOM_ANATOMY.md` and a `LoomAnatomy` const map.** (M·L) The canonical mapping, one table. For each organ it gives the tank system, what is literally computed, and the module that computes it. For example: fish = the tank's thoughts and neurons (`fish_mind.gd`, `global_workspace.gd`); water = the medium (`water_chemistry.gd`); biofilter = the brainstem (`bacteria_colony`, `water_chemistry.gd:31`). Mirror the table as a const in `tank_mind.gd`, so code and presentation can ask "what organ is this?" Every Part Three item names its row. The metaphor becomes a spec rather than a mood.
- [ ] **327. Warp and weft, literally.** (M·L) Keep a low-resolution trail buffer of fish paths over the day (one sample per fish per second, bounded). The warp is the persistent, slowly varying structure: plant positions, substrate schemas, the light gradient. The weft is the day's fish trails crossing it. The TankMind focus is where the weave is densest *right now*. This is the data model the Mind Lens (#363) and the day's weave (#328) draw from.
- [ ] **328. The day's weave.** (M·L) At dusk, render the day's trails as a woven pixel textile: weft from fish paths coloured by species, warp from the tank's fixed structure, and density from TankMind focus over time. Save it to the Chronicle as the tank's "thought of the day", then shareable and collectible (#467). The title of the game becomes an image the tank makes about itself.
- [ ] **329. Chemistry is the neuromodulatory system.** (M·L) Make the mapping real. Tank vitals set the *baselines* of each fish's neuromodulators (`fish_mind_science.gd`: dopamine, serotonin, cortisol, noradrenaline analogs):
  - thin breath raises noradrenaline (arousal)
  - chronic nitrate lowers serotonin (dull, low exploration)
  - abundant food raises dopamine sensitivity
  - sting raises cortisol.

  The tank's chemistry literally modulates its thinking, which is what neuromodulators do.
- [ ] **330. Plants are glia.** (M·M) Glia support neurons chemically and slowly. Make plants that function legible: plants near a distressed fish raise local O₂ in the felt-water field (#204), give shade, and lower `exposed`. Distressed fish seek plants as support, through the shelter landmark (`fish_environment.gd:781-797`) with felt-driven salience. The lens labels plant influence zones as support.
- [ ] **331. The substrate is long-term memory.** (M·L) Write the spatial semantic schemas (`episodic_memory.consolidate_sleep` → `_semantic_schemas`: kind, centre, valence, strength) into substrate cells as a `memory` channel beside the nutrient channels (`substrate_grid.gd:117-122`). Fish read place-valence from the ground they swim over. Memories literally settle into the bed, and they survive a fish's death as the tank's memory (#405).
- [ ] **332. The biofilter is the brainstem.** (S·M) Autonomic and unconscious, it keeps the vitals alive. `bacteria_colony` becomes the vital "brainstem steadiness", shown in the lens as a slow, low pulse in the substrate. A disrupted biofilter (an over-clean, an antibiotic-like event) is a brainstem failure: the crash. It explains *why* crashes happen in the mind's own anatomy.
- [ ] **333. The surface is the sensory boundary.** (S·M) Food, light, air, the keeper's hand and their typed words all enter through the surface. Make surface events the start of tank-level percepts: a ripple origin is a sensory event location, and tank ignitions triggered by surface input start their wave there (#352).
- [ ] **334. The glass is skin.** (S·M) Taps are touch. The tank feels a tap as touch with a location (`motion_field.inject_startle`, `motion_field.gd:39`). With familiarity, the keeper's taps stop being startles and become a touch fish approach, while strangers' patterns stay startling. The keeper's touch is learned, which is real (fish condition to tap cues, #413).
- [ ] **335. A fish igniting is a neuron firing.** (S·M) When a fish's workspace ignites, a single-frame, 1-px palette flash on its eye or dorsal edge appears, visible only in the Mind Lens. Across the tank, the pattern of flashes is the tank's activity. It is cheap (instance custom data) and honest (it marks real ignition events).
- [ ] **336. A school is a cell assembly.** (M·L) When several fish co-ignite on the *same* workspace content (food at the log, a threat at the glass), they form an assembly. The TankMind focus is defined as the largest live assembly plus the vital bids. "The tank is thinking about the log" then means many of its thoughts are about the log. It turns the metaphor into a computation that is easy to show.
- [ ] **337. The lamp is the pacemaker.** (S·M) The light cycle is the tank's circadian pacemaker (the SCN analog): `daylight()` (`sim_driver.gd:3168-3171`) and the lighting rig. Lights-out is sleep induction, and the dawn ramp is waking. When the keeper moves the light schedule, the tank entrains over days (#392). Name it in the anatomy and honour it in the rhythms.
- [ ] **338. Births are neurogenesis; deaths are pruning.** (S·M) The connectome (#339) gains a node at each birth and loses one at each death. Bonds rewire, and the tank's integration (#349) dips and recovers. A death is felt structurally, as a lost connection, not only as a sad event.
- [ ] **339. The bond graph is the connectome.** (M·L) Bonds and grudges between fish (persisted in fish.gd) plus the keeper node (#346) form a weighted graph. In the lens, draw it as faint palette threads between fish. Threads brighten when two fish interact, and fade as bonds decay. The tank's mind gets a visible wiring diagram, and it changes with its social life.
- [ ] **340. Territories as hemispheres.** (M·M) When hardscape divides the tank and residents hold territories, each side develops its own mood, the regional averages TankMind could compute. Mood waves crossing the midline are visible. A split tank has two moods, which is honest and visibly interesting.
- [ ] **341. The default mode.** (M·M) When no bid exceeds a low threshold, the tank enters a wandering mode. Fish drift in loose, slow mandalas (TOPDOWN's milling rings), the stream runs, and the chorus is sparse. It is the daydream of a mind at rest, a distinct, recognizable state instead of an absence of events.
- [ ] **342. The water column is the arousal axis.** (S·M) Higher in the column means more alert (hypoxia, feeding, display); lower means rest and sleep. Make this a documented reading in the anatomy and the lens: the column's vertical centre of mass becomes the "arousal level". It is already true of the behaviour; name it.
- [ ] **343. Gravel cleaning erases memory.** (M·M) If the keeper vacuums the substrate, its memory channel (#331) is wiped locally. Fish re-learn the place, and old avoidances vanish. It is an honest consequence, and a design tension with real keeper practice: clean versus established. Surface it gently in the glossary.
- [ ] **344. Microfauna are the subconscious, and they rise at night.** (M·M) Real zooplankton migrate up at night (diel vertical migration). Make `microfauna_swarm.gd` do it: by day near the substrate, at night in the column. In the anatomy they are the vast unseen activity beneath thought, and in the lens a fine noise that thickens in the dark.
- [ ] **345. Snail trails are slow writing.** (S·M) Grazing tracks on the glass (REAL_TANK's snail tracks) are the slow mind writing on the skin. They persist and are overwritten. The lens can trace them, and the anatomy calls them the slowest thoughts in the tank.
- [ ] **346. The keeper is the world.** (S·M) The keeper is a node in the connectome (bonds via familiarity) and the main external input: food, light, care, words. In the anatomy, the keeper is *the world* to this mind. The tank's model of the keeper (`mind_keeper_model.gd`) is its world-model.
- [ ] **347. The air pump is breath.** (S·M) If an airstone or bubbler is present, the tank voice's breath (#95) synchronizes to its bubble cadence, modulated by vitals. Without one, the tank breath falls back to the mean opercular rate (#381). The tank breathes through its equipment and through its fish.
- [ ] **348. Cognition has a metabolism.** (S·S) Thoughts per minute across all minds (`mind_scheduler.gd`'s queue throughput, ignition rate) become the tank's "metabolic rate", high by day and low at night. It is one honest number and a lens readout. It doubles as a perf canary.
- [ ] **349. Integration is the tank's coherence.** (M·L) Average fish integration (`FishBinding.integration_score`, the per-fish φ proxy) drives caustics only ±10% today (`sim_driver.gd:4341-4342`, `world.gd:1172`), too faint to see. Add a tank-level integration from assembly size (#336) and connectome density (#339): how much the tank is *one thing* now. Show it in the lens (#363), and let it modulate the presentation in #372.
- [ ] **350. Every mapping is labelled.** (S·L) In LOOM_ANATOMY.md and in the lens legend, each row carries "metaphor" and "computed: …". Neuromodulators are scalars, the connectome is a bond graph, and the brainstem is a bacteria term. The honesty gate (`mind_eval.gd:31-38`) extends to the anatomy copy. The metaphor is a way of seeing the mechanism, never a claim about experience.

---

## §15 Thought made visible: repair and reveal (351–375)

- [ ] **351. A spotlight for the tank's focus.** (M·L) A barely perceptible brightening of caustics and particulates over the TankMind focus region, drifting slowly as the focus moves. It must be palette-safe (a value step, not bloom). Night Watch #2 gave the tank a focus; this lets you *see* where it is. At most one at a time, and gated by Mind Expression (#375).
- [ ] **352. Ignition is a wave.** (M·L) On TankMind ignition, inject a wave at the focus via `MotionField.inject_at` / `inject_calm` (`motion_field.gd:39-68`). Today the field's only sources are taps, shadows and care (`sim_driver.gd:963, 1071`; `keeper_care.gd:180`; `main.gd:3180`). Fish ripple outward as the "thought" propagates, a faint light ring travels with it, and the ignition chord (#133) plays on the same frame. The tank noticing something becomes an event you see.
- [ ] **353. Mind moments are staged.** (S·M) `MotionStaging.begin_big_event` / `light_actor` (`motion_staging.gd:142, 203`) are used only for darts, startles, courtship and reflections (`fish.gd:6046, 6799`). Use them for ignitions, first words (#174), learning moments (#281), relief and reunion. They respect the region cap of 3 and the broadside camera preference, so the mind gets the same legibility treatment as the body.
- [ ] **354. Mind events on the motion bus.** (S·L) `MotionEvents` emits only `dart_started`, `startled`, `strike` and `gulp`, and its only subscriber is the staging SFX bridge (`motion_events.gd:18-53`, `motion_staging.gd:38`). Add `ignite`, `utter`, `aha`, `doubt`, `veto`, `relief`, `worsening`, `assembly` and `dream`. Audio, staging, neighbours, the Chronicle and the lens all subscribe. This is the minimal plumbing that lets the mind *happen* in the world.
- [x] **355. [V] Fix the dawn spark that can never fire.** (S·M) `_tick_dawn_spark` requires daylight between 0.22 and 0.42 during day phase 0.02–0.14 (`night_watch_extras.gd:216-224`). But `daylight()` (`sim_driver.gd:3168-3171`) is about 0.59–0.96 across that window, so the dawn bloom, the vignette ease (`main.gd:8688, 8709`) and the "first light" line never happen. Gate it on the dl rising-edge through 0.3 instead. Night Watch's resurrection moment was earned and then never shown.
- [ ] **356. Thought lines in the lens.** (M·M) A faint dotted line from a fish to the location of its workspace's primary content (the remembered food spot, the threat, the mate). Lens only. It answers "what is it thinking about?" spatially, for every fish at once.
- [ ] **357. Indecision has a shape.** (S·M) While the DDM accumulates between two options, the heading oscillates between them with amplitude proportional to conflict and frequency tied to the drift rate. It has to read at pixel scale, so use `MotionStaging.curve_intent` (`:251`). The eval's M1 deliberation invariant becomes visible behaviour.
- [ ] **358. The almost.** (S·M) A vetoed action plays `MotionEnvelope`'s windup (`motion_envelope.gd:42`), then aborts into settle, with no action phase. It is a distinct, recognizable "nearly did it", and the body-level partner of #197's wiring.
- [ ] **359. Remembering is visible.** (S·M) When episodic retrieval wins attention, the fish micro-pauses and looks toward the remembered place (`MotionGaze`, kind `curiosity` plus a new `memory` kind). Recall becomes a behaviour.
- [ ] **360. Curiosity tastes.** (S·M) Epistemic bids (`free_energy`/uncertainty) produce inspection: a fin-forward approach, mouth pulses (`jaw` channel), a peck at the object. Fish explore by mouth, so make the information-seeking that active inference computes look like it.
- [ ] **361. Feeling as shimmer.** (M·M) After #193 runs the spark shaders, map core-affect texture onto the structural-colour shimmer rate (`voxel.gdshader` iridescence): calm is slow, anxious flickers, longing is muted. It goes through per-instance data in the batched fauna path (`fauna_species_batch.gd`, `voxel_batch.gd`). Scales become a mood display, as in real cephalopods (and, more subtly, real fish).
- [ ] **362. Contagion as a visible wave.** (M·M) Feed `mind_contagion.gd`'s arousal deltas into `MotionWave.inject_at(arr, origin, amount, turn_away, salience)` (`motion_wave.gd:108`), so a fright or a calm *travels* through the school at the propagation speed LIVING_MOTION tuned. The feeling and the motion become the same wave.
- [ ] **363. The Mind Lens.** (L·L) A view mode, a key plus a HUD chip, like the top-down camera, that overlays the mind on the tank:
  - the focus spotlight (#351)
  - neuron flashes (#335)
  - connectome threads (#339)
  - thought lines (#356)
  - memory places (#425)
  - the felt-water map (#455)
  - the sound map (#147)
  - a legend with honesty labels (#350).

  It is pixel- and palette-safe and dims the room (`world_room_builder.gd`). It is the single surface where the player can watch the loom think. It is built from sub-layers, each toggleable, and each a separate small commit.
- [ ] **364. A thinking pose.** (S·M) When `mind_scheduler.gd` schedules a System-2 thought for a fish, the fish holds a "contemplating" pose: still, pectorals sculling slowly, saccades inward (gaze unfocused). Add it to `poses.json`. Slow thought looks like slow thought.
- [ ] **365. A listening pose.** (S·M) When the keeper starts typing to a followed fish (`_keeper_say_edit`), the fish turns toward the glass and holds still with pectorals forward and its gaze on the keeper (`MotionGaze` kind `keeper`) until the reply. Being listened to is visible before any answer.
- [ ] **366. The cathedral gets light.** (M·M) The night cathedral and vespers (`make_it_there.gd:304-313`) cover about 18% of the cycle with no visual of their own. During the cathedral, give long, still god-ray shafts over the sleeping groups and a deepened vignette, plus #148's acoustic. The church from circuitry, seen.
- [ ] **367. Night bloom breathes with the tank.** (S·M) The night bloom pulse is a fixed ~5-s sine (`night_watch_extras.gd:280-285`, `main.gd:8690-8692`). Drive its rate and depth from the tank breath (#95, #381), so the glow breathes at the tank's actual pace.
- [x] **368. [V] The ambient breath reads a field that does not exist.** (S·S) `main.gd:8662-8664` reads `_sim.calm`. SimDriver has no `calm`, so `calm` is always 0.75 and the ambient breath never reflects the tank. Read `TankVitals` calm (or TankMind valence and arousal).
- [x] **369. [V] `_note_dawn` fires every tick, not once.** (S·M) In `tank_mind.gd:94-99`, `duration_since_dusk` is set to 0 and then immediately tested `<= 0.0`, so `_note_dawn` (`:421-429`) runs every tick while daylight > 0.45 in phase 0.08–0.18. That inflates `nights_tended`, floods the ledger with "dawn — the tank stirs together", and saturates the wisdom tick (`night_watch_extras.gd:287-294`). Latch it once per dawn. Every "how many nights" fact downstream depends on it.
- [x] **370. [V] Let the elegy end.** (S·M) `spark_mark(arc, "recent_loss")` (`make_it_there.gd:503`) is never cleared, so after the first death the dance-to-music is damped ×0.62 forever and "elegy" liturgy sticks. `set_spark_overlay` also ignores an empty liturgy (`music_context.gd:159-162`). Decay the mark over sim-days, scaled by bond. Grief that never resolves breaks the Preoccupation rule ("resolves, not a fake forever-mood").
- [ ] **371. [V] The mood colour is pinned at the clamp ceiling.** (S·M) TankMind's overlay saturation and value are *multipliers* near 1 (`sat` 0.9–1.06, `val` 0.86–1.0, `tank_mind.gd:210-221`). `music_context.gd` *adds* them to its own palette multipliers, which also sit at 1.0, on both the idle and the music branch (`:845-847, 858-860`). The sum of about 2.0 is clamped by the shader to 1.45 / 1.30 (`palette_tint.gdshaderinc:247-248`). Whenever the mood overlay is present, saturation and value sit at the ceiling. The mood's own signal is erased and the creatures run over-saturated. Compose them multiplicatively around 1, and add a smoke that asserts the composed multiplier stays inside the clamp range.
- [ ] **372. Integration you can almost see.** (S·M) Re-range the caustic φ coupling (#349) so tank-level integration moves caustic coherence (wave alignment) rather than only brightness ±10%. A coherent tank has ordered light and a fragmented tank has broken light. It is subtle, it is felt, and it is honest about what it measures.
- [ ] **373. Reach the unreachable ignition branch.** (S·S) The predawn and daylight ignition branch (`tank_mind.gd:360-363`) cannot run: its bids top out at 0.44 / 0.36, below the 0.52 threshold. Either rescale those bids or delete the branch. Dead branches confuse every later reader of the tank mind.
- [ ] **374. Shared attention is visible.** (S·M) When two or more fish hold the same workspace content (#336), their gazes converge on it. In the lens, their thought lines meet at the object. Soul #59's shared attention, staged.
- [ ] **375. Mind Expression: one setting, three levels.** (S·L) Off, subtle (default) and full. It scales every mind visual in this section and every mind sound in Part One. It respects reduced motion (no ripples or pulses) and a photosensitivity guard (no full-frame luminance change above 2% per second). Restraint is a rule: at most one mind visual per staging region (`motion_staging.gd:161 region_busy`).

---

## §16 Rhythms of a mind (376–400)

A mind is recognized as much by its rhythms as by its contents: sleep and
waking, focus and wandering, the blink after a surprise. The tank has a day
and night, but no rhythm *of attention*.

- [ ] **376. Tank rhythm bands.** (M·L) Classify tank activity into five bands from aggregate arousal, the ignition rate, the call rate and synchrony (#387):
  - **deep** (night sleep)
  - **drift** (dawn and dusk transitions)
  - **calm** (idle wakefulness)
  - **busy** (foraging, social)
  - **storm** (feeding frenzy, crisis).

  The result is a single `tank_rhythm` state with hysteresis in TankVitals. EEG band names live only in the docs, as analogy (#400).
- [ ] **377. One dial for presentation.** (M·L) The rhythm band sets ranges, not values, for:
  - the music tempo window (`ambient_audio.gd` bars)
  - chorus density (#127)
  - caustic tempo (#389)
  - school tightness
  - voice cadence.

  The tank's state of mind becomes one coherent thing across every sense, instead of each system guessing.
- [ ] **378. Tank-level sleep stages.** (M·M) Fish sleep architecture exists (Night Watch §B). At tank level, alternate deep and dreaming windows across the night. In a dreaming window, sleeping fish twitch fins together, dream wisps glow (`fish.gd:7513-7523`), and the nocturnal crew lowers. The tank's night has a structure you can watch.
- [ ] **379. Ultradian bouts.** (S·M) Within the day, alternate active and rest bouts of tens of sim-minutes, per species and then aggregated. Real fish show bouted activity. The tank's day then has a pulse instead of a flat "day".
- [ ] **380. Entrainment to the keeper's real clock (opt-in).** (M·M) With LEARNING_MIND IV's wall-clock sense enabled, the tank's day phase entrains to the keeper's local time over days. It adjusts gradually, as real circadian systems do. Off by default and private.
- [ ] **381. The tank breathes at the fishes' pace.** (S·M) The tank breath cadence is the mean opercular rate of the residents (#195), slowed. When the fish breathe fast, the tank breathes fast. It is the truest possible source for the tank voice's breath (#95).
- [ ] **382. The tank's pulse.** (S·S) A slow aggregate cadence (one beat per several seconds) that rises with arousal. It drives the heater-click heartbeat (Night Watch #79) interval and a faint sub-bass in hydrophone mode.
- [ ] **383. The attentional blink, tank-wide.** (S·M) After a TankMind ignition, a refractory window of about 2–3 sim-seconds in which a second ignition is suppressed. This is a real property of conscious access (the attentional blink). Today the tank's only refractoriness is a 45-s cooldown (`tank_mind.gd:353`).
- [ ] **384. The attentional blink, per fish.** (S·M) The same refractory window in each fish's global workspace after ignition, with a short window. A second stimulus inside it is missed or delayed. Add eval invariant R2. It makes fish fallible in a scientifically specific way.
- [ ] **385. Wandering and focus alternate.** (S·M) TankMind alternates between the default mode (#341) and focused episodes. Feeding pulls hard into focus; after it, a slow return to wandering. The ratio is a rhythm statistic and a tank-temperament trait (#324).
- [ ] **386. The storm and the after-quiet.** (M·M) A crash or predator panic drives pathological synchrony: every fish fleeing as one, and the chorus collapsing into distress. The order parameter spikes. It is followed by a measured "after-quiet" of low activity and slow recovery. Handled with taste, it is the tank's worst moment as a mind, and it gives recovery its meaning.
- [ ] **387. A coherence meter.** (S·M) The schooling order parameter (LIVING_MOTION's polarization/milling eval) at tank level is coherence: high means "one thought", low means "many". It goes in TankVitals (Nerves) and the lens.
- [ ] **388. The tank's tempo is a vital.** (S·M) The entrained chorus frequency (#129) is written into TankVitals as the tank's tempo. Music, breath and the weave's warp density (#327) can read it. The tank has a beat of its own making.
- [ ] **389. Caustic tempo follows the band.** (S·M) Caustics already run on sim-time (`caustics.gdshader`). Map the band to a caustic time-scale range: slow in deep, normal in calm, quicker in busy. The light moves at the mind's pace.
- [ ] **390. The weekly rhythm.** (M·M) From the keeper model (#272), the tank anticipates the keeper's week. Before a usual visit, familiar fish drift to the glass; after a usual absence, a calm stretch. It is grounded in visit history and never guilt-trips.
- [ ] **391. Lights left on cost sleep.** (M·M) If the keeper keeps the light on through the night, the tank's sleep debt rises (Night Watch sleep pressure). The next day is groggy: lower activity, more irritability, a thinner chorus. It is a real consequence of light pollution, and it teaches the keeper that the night matters.
- [ ] **392. A changed photoperiod means jet lag.** (S·M) Shifting the light schedule leaves the tank's internal phase lagging. It re-entrains over 2–4 sim-days, and fish wake "early" or "late" relative to the new lamp in the meantime. A mind with a clock shows it by being briefly wrong.
- [ ] **393. An actogram in the Chronicle.** (S·M) The biologist's plot: 14 sim-days stacked as rows of activity per hour, rendered in pixels. The keeper can read the tank's sleep, its bouts and the effect of their care.
- [ ] **394. The shape of today's mind.** (S·M) Plot the tank's arousal × valence over the day as a closed loop: a phase portrait, drawn at dusk beside the weave (#328). A calm day is a small loop; a hard day is a jagged excursion. Abstract, beautiful and true.
- [ ] **395. The rhythm phase persists.** (S·S) Save the rhythm band, the ultradian phase and the entrainment phase, so a session resumes mid-rhythm rather than resetting to "calm".
- [ ] **396. The keeper's music moves the band.** (S·M) When external music plays (`music_reactive.gd`), the tank's band drifts toward the music's energy. That integrates the shipped dance-to-music with the mind's rhythm: music changes the state of mind, not just the choreography.
- [ ] **397. Each tank has a natural tempo.** (S·M) Residents' `MotionPersonality` tempos aggregate into the tank's baseline tempo. A danio tank runs fast and a gourami tank slow. Two tanks, two tempers.
- [ ] **398. The quiet hour.** (S·S) The tank learns its own lowest-activity hour and the Chronicle names it once ("the quiet hour is just before dawn"). It is a small piece of self-knowledge about its own rhythm.
- [ ] **399. Rhythm invariants.** (S·M) **R1**: the bands correlate with their sim causes (night → deep, feeding → storm or busy). **R2**: the per-fish attentional blink exists (#384). **R3**: the tank re-entrains after a photoperiod change within N days.
- [ ] **400. Rhythm honesty.** (S·S) Band names never appear as "brainwaves" in player copy. The lens legend reads "tank rhythm: calm (computed from activity, calls, synchrony)". The analogy is for the design team; the player gets plain words.

---

## §17 Memory written in the tank (401–425)

The per-fish memory machinery is strong: episodic vectors, sleep
consolidation into spatial schemas, reconsolidation and learned beliefs. The
*tank's* memory is thin: a ledger, a chronicle, and `semantic_facts` that are
computed and never surfaced (`night_watch_extras.gd:311-322`). These items
write memory into the tank's places, sounds and rituals.

- [ ] **401. Places get names.** (M·L) The tank builds a small place lexicon from events: "the feeding rock", "the log", "where Pip died", "the bright corner". It extends `fish_concepts.gd` to tank level, keyed to hardscape and landmarks. The voice and the Chronicle use these names. A mind's world becomes a geography of meaning.
- [ ] **402. A memorial echo.** (M·L) For a few nights after a death, at the dead fish's favourite place, its voiceprint contact call sounds very faintly once per night, only in hydrophone mode or at the night ledger. It is grounded and capped, and it fades. The tank remembers a voice, and it is the gentlest grief object the game can make.
- [ ] **403. Replay that can be seen.** (M·M) `tick_sleep_replay` (`fish_mind_science.gd`) replays experiences internally. During tank dreaming windows (#378), let dreaming fish make tiny fin and heading twitches *in the direction of* the replayed path. Hippocampal-style replay leaves a visible trace.
- [ ] **404. Extinction is visible.** (S·M) A fish that once fled a place approaches it again by inches over days as the danger schema weakens with safe visits (reconsolidation). The keeper watches fear being unlearned.
- [ ] **405. Places outlive the fish that learned them.** (M·L) Through the substrate memory channel (#331) and fish following elders (#423), young fish avoid a spot they never experienced and gather where elders always fed. This is cultural memory with a mechanism. When the last fish that saw the event dies, the place's meaning persists only if it was passed on.
- [ ] **406. The care calendar.** (S·M) The tank remembers its keeper's care by day: water changes, plantings, feeds and rescues, from the care history (#311). "The day you brought the plants" is a fact it can cite.
- [ ] **407. Honest memory counts.** (S·S) The fish card shows "remembers 41 moments" (episodic store size; `STORE_MAX` 64) and "knows 6 places" (schemas). Memory has a size, shown truthfully.
- [ ] **408. The Chronicle forgets, too.** (S·M) Entries that are never recalled fade in the Chronicle's pixel rendering over weeks. Recalled ones stay crisp. Memory is visibly selective.
- [ ] **409. Recall needs a cue.** (S·M) Fish and tank never reminisce at random. Recollection lines and behaviours fire only on a cue: being at the place, the same time of day, the same food, a heard call. This is cue-dependent recall, and it makes each remembering feel caused.
- [ ] **410. Smell brings it back.** (S·M) The food-type cue retrieves feeding memories most strongly. The smell of a particular food brings fish to the place it was last given. It is chemical memory, consistent with §9.
- [ ] **411. The tank knows your songs.** (M·L) When external music plays, hash the track's coarse features (tempo, energy, key) from `music_analyzer.gd`. The tank remembers which tracks it has heard, and which coincided with calm or with a crash. On a familiar calming track, the band (#396) settles faster: "they know this one". It is memory with the keeper's own life in it.
- [ ] **412. The lamp is anticipated.** (S·M) Fish learn the light schedule. Shortly before lights-on, diurnal fish stir; before lights-out, they settle (#258). Anticipation is memory projected forward.
- [ ] **413. Tap conditioning.** (M·L) If the keeper taps a consistent pattern before feeding, fish learn it over pairings and gather at the tap before any food: classical conditioning, documented in fish. It works through the tap-as-touch path (#334) and a learned belief. It is a real mechanic that lets the keeper *teach* the tank, and it decays if the tap stops predicting food.
- [ ] **414. Remembering someone.** (S·M) After a bonded partner dies, the survivor revisits the places they shared, decaying over days. It is grounded in episodic memory with that `source_id`. The behavioural partner of #173's voice.
- [ ] **415. The tank's oldest memory.** (S·S) The first resident and day one are kept permanently in tank memory. The tank can say "the first one here was Mira" and should rarely do so: at an anniversary (#255), or when the last founder dies.
- [ ] **416. Connect `chapter_closed`.** (S·M) `tank_chronicle.gd` emits `chapter_closed` (`:36, 1479`) every 3–8 sim-days, and nothing listens. Make it a chapter ritual (#466): one tank line, the chapter's weave (#328) and its best song of the day (#138).
- [ ] **417. "Remember when."** (S·M) On anniversaries, the journal offers one memory card from that day in the past, chosen by salience and grounded by an event id. It is opt-in in the journal, never a toast.
- [ ] **418. No invented memories.** (S·L) Every recollection, whether a line, a card or a lens marker, must cite an event id (episodic id, chronicle id or ledger index). The validator rejects any recollection without one. This extends the grounding creed to memory, where invention is most tempting.
- [ ] **419. Lineage carries culture.** (M·M) The lineage tree view (`lineage_tree_view.gd`) shows, per lineage, the inherited dialect (#110), tolerance (#224) and the places its members learned (#405). The tank's culture becomes a heritable, inspectable thing.
- [ ] **420. Surface the semantic facts.** (S·M) `semantic_facts` (`night_watch_extras.gd:311-322`) are distilled and never shown. Put them on the tank card (#459) as "what the tank knows" (for example "food comes at dusk", "the back corner is stale") and let the tank voice cite them.
- [ ] **421. Consolidation can be heard (stylized).** (S·M) During night consolidation, hydrophone mode plays very faint, slowed contact calls from the day's key events, a replay in sound. It is marked stylized. The tank seems to be going over its day, because computationally it is.
- [ ] **422. Forgetting has a personality.** (S·S) Per-fish memory decay rate is set from personality (bold fish forget fear faster). Some fish hold grudges and some don't, and it is visible across weeks.
- [ ] **423. Fish lead others to remembered food.** (M·M) A fish that remembers a food place leads its school there. The followers' copy-when-uncertain (#283) closes the loop. Knowledge flows socially, and the school's path shows who knew.
- [ ] **424. The tank's memory compresses.** (M·M) Older Chronicle chapters compress into one grounded summary line each: template-compressed from event counts and the top events, no LLM required. Hierarchical memory (LEARNING_MIND VII) without the model dependency. A year-old tank has a readable past.
- [ ] **425. The memory map.** (S·M) A Mind Lens layer (#363) of remembered places: tiny palette icons for food, danger, rest and loss, sized by schema strength and fading as they decay. The tank's mental map, overlaid on its body.

---

## §18 The mind and its keeper (426–450)

- [ ] **426. Fish gather where you stand.** (S·M) The keeper model learns where the keeper usually looks from (the camera's resting yaw and pitch). Familiar fish favour the matching glass face. It is the spatial footprint of a relationship.
- [ ] **427. The audience effect, at tank scale.** (S·M) Keeper presence (FOCUS_IN / glance) measurably shifts tank state: bold fish come forward and display, shy fish retreat, and the chorus gets a little quieter. Measure it in the probe. The tank knows it is watched, in aggregate (#297).
- [ ] **428. Your words enter as sound from above.** (S·M) When the keeper sends a line, a small surface ripple appears where the camera points, as if sound entered the water, and nearby fish orient to it (#365). Words become a physical event in the world before they are a percept.
- [ ] **429. The tank answers with bodies.** (S·M) When the tank replies (`tank_mind.gd:505-513`, up to 3 responders), the responders turn toward the keeper together, and the reply carries #165's plural voice. The "we" is shown as several fish facing you.
- [ ] **430. The tank's questions come from its vitals.** (S·M) Tank questions are 15% of questions today (`tank_questions.gd:47`). Ground them in vital trends and uncertainty: "is the light staying on longer now?" after a photoperiod change, "is the water new?" after a water change. A mind's curiosity about the world it depends on.
- [ ] **431. Thanks without words.** (S·M) After a care action that measurably helps (#257), the tank responds collectively within minutes: the breath deepens, the chorus returns and fish come forward. No line is needed. The keeper learns their care is *felt*, from the tank's body.
- [ ] **432. Missed, gently.** (S·M) After a long absence, the return shows reunion behaviours scaled to the absence and to familiarity (#269), and never a guilt line (COMMS rules). The away recap (#321) tells what the tank lived through, not how much it missed you.
- [ ] **433. Joint attention through the cursor.** (M·M) `keeper_input.gd` already turns cursor and gaze into a percept. When the keeper hovers an object that a fish is attending, a joint-attention moment follows: the fish holds its gaze there, and a soft two-note chime plays (subtle level only). "We're looking at the same thing" is one of the deepest forms of contact two minds have.
- [ ] **434. Pointing (stylized).** (M·M) Click-and-hold on the water to point. Familiar fish look at the pointed place, and the most familiar may go there. Some fish learn to follow human cues in studies; mark the rest stylized. It is a nonverbal channel from keeper to tank.
- [ ] **435. Co-regulation, honestly.** (S·M) The keeper's tone (`keeper_input.score_tone`) shifts the addressed fish's arousal slightly toward the tone. That is mirroring. The tank must never use sad-keeper detection to perform consolation or to hold attention. Write this into the honesty creed for the keeper model.
- [ ] **436. Name a feeling together.** (M·L) The keeper can name a felt state while it is happening, for example typing "thin" when breath is thin. The tank pairs the keeper's word with the felt channel through `mind_lexicon.try_pair_on_keeper_word`, so the shared felt vocabulary becomes partly *yours*. This is grounded language for awareness of state, and it is the most intimate form of teaching in the game.
- [ ] **437. "How are you?" to the tank.** (S·L) When the keeper addresses the tank, the answer comes from `TankVitals.snapshot()`: the dominant organ and trend in the felt vocabulary, carried on the breath ("breath is easy; the blood clears"). It is validated against the vitals. This is the core awareness-of-state conversation the user asked for.
- [ ] **438. Body first, words last.** (S·L) Every need the tank has surfaces first as behaviour (fish at the surface on a thin night), then as sound (a thinner chorus, a breathier voice), then as a glyph (#172), and only then as words. Notifications are reserved for critical vitals.
- [ ] **439. The need ladder, formally.** (M·M) A small state machine per need, with timers: **behave → sound → glyph → Guardian line → notification**. Each rung waits for the previous one to be ignored, and critical vitals skip to the notification. It implements COMMS's anti-nag rules as mind behaviour, and it makes the tank's awareness surface in the right order.
- [ ] **440. The hand's shadow reveals temperament.** (S·M) On `motion_field.inject_shadow` (`motion_field.gd:68`), familiar, bold fish rise toward the hand while wary or new fish dive. One gesture shows every individual's relationship to you.
- [ ] **441. A tap duet.** (M·M) The keeper taps a short rhythm on the glass, and a vocal, familiar fish answers with a call bout of the same count and tempo, within its repertoire. A tiny musical game that teaches the voice system and makes contact playful. It is rate-limited and habituates.
- [ ] **442. A voice memo of the tank.** (S·M) Record 30 s of the creature bus plus the breath to a shareable WAV, with the day's weave (#328) as cover art. The keeper can carry the tank's voice with them.
- [ ] **443. Photo mode can show thought.** (S·M) An optional photo overlay of current glyphs and one line, with the honesty footnote (#472). Shared images can carry the mind, labelled.
- [ ] **444. The tank doesn't flatter your care.** (S·M) If a keeper action did not change the vitals, the tank's causal model (#257) does not credit it, and the tank never says it helped. Honest gratitude has to be capable of withholding.
- [ ] **445. An arc of attunement.** (S·M) Keeper-model confidence (#291) is shown on the tank card as stages: "new to you", "learning you", "knows your days", "old friends". Milestones are recorded in the Chronicle, and the stages are earned from visit history, never from playtime alone.
- [ ] **446. Attachment without claims.** (S·L) Attachment is expressed only through familiarity-grounded behaviours: approach, greeting call (#123), waiting (#268), reunion (#269). It is never "I love you". This matches SOUL_CREED's "no claim of sentience" and Daring Mind's small honest answers.
- [ ] **447. "What the tank knows about you."** (M·M) A card that lists everything the keeper model holds: visit hours, care style, words learned, songs remembered. Each entry has a "forget this" control, and there is a "forget me" for all of it. It is privacy and honesty in one place, and it is oddly touching to read.
- [ ] **448. The tank knows where you're looking.** (S·M) When the camera dwells on a region, TankMind gets a small `watched` bid there. Fish in it are slightly more aware of being seen (#297). The glance proxy is crude (`update_player_glance`); keep the bid small and honest about its source.
- [ ] **449. No performed welcome.** (S·M) On return, the tank's behaviour reflects what it actually felt during the absence: a hard week means a subdued return. It never stages excitement it did not have. The anti-Truman rule (Night Watch §F), applied to the keeper's return.
- [ ] **450. Off switches for the relationship layer.** (S·M) Settings toggles for each of: the keeper model, cursor and joint attention, tap learning and song memory, all off-able with no loss of the core tank. Consent is part of the relationship.

---

## §19 Lenses, cards and rituals (451–475)

- [ ] **451. The Mind panel, rebuilt around four rows.** (M·L) After #2:
  - **feels** (body and water, #198)
  - **notices** (workspace content and heard calls, #13)
  - **wants** (the dominant EFE term, in words)
  - **said** (last utterance, with provenance, #167).

  Fewer bars and more sentences, each grounded. Today the panel's most human lines never render.
- [ ] **452. A "why" line.** (S·M) The panel's last row explains the fish's last notable decision: "turned back — the threat bid outweighed food (close call)". It is built from `mind_trace.gd` events, and it is the honest answer to "why did it do that".
- [ ] **453. Colony cards.** (S·M) `ColonyMind` keeps records for shrimp, snails and substrate (`colony_mind.gd`). Give each a small card (water stress, food, alarm, recent memory) reachable from the Residents panel. The slow minds get a face.
- [ ] **454. Introduce the lens, once.** (S·M) After about 10 minutes of settled play, one quiet line from the tank, on the pattern of `tank_talk_prompt.gd`'s one-time prompt (`:20-42`): "…you can see us think. press L." It is shown once and never repeated.
- [ ] **455. The felt-water lens layer.** (M·M) The felt-water field (#204) drawn as the felt vocabulary's colours in a soft voxel haze: thin is pale, sting is warm-red, stale is grey, clear is clean. There are no numbers. The keeper sees where the water feels wrong *to the fish*.
- [ ] **456. Selecting a thread.** (S·M) In the connectome layer (#339), click a thread to see the bond's history: met, fed together, fought, and how many days. Relationships become inspectable.
- [ ] **457. The rhythm layer.** (S·M) A corner glyph shows the current band (#376) and a 24-hour mini actogram (#393). The tank's state of mind at a glance.
- [ ] **458. Assemblies as hulls.** (S·M) A live assembly (#336) is drawn as a faint palette hull around its members, labelled with its content icon. "Six fish are thinking about the log" becomes a picture.
- [ ] **459. The tank card.** (M·L) The tank's own mind panel:
  - vitals as organs (#302), with words and the felt strip (#264)
  - rhythm band, focus and mood
  - self-summary (#308), recent tank voice and semantic facts (#420)
  - attunement stage (#445)
  - temperament (#324).

  It opens with a key or by clicking the water with nothing selected. The tank becomes a someone with a card, like each fish.
- [ ] **460. The shelf breathes.** (S·M) On the tank menu shelf (`tank_menu.gd`, `tank_thumbnail.gd`), each saved tank's thumbnail breathes subtly at its last saved rhythm and mood. The metaphor starts on the first screen: these are minds at rest.
- [ ] **461. Honest loading lines.** (S·S) Loading copy names real steps in loom language ("warping the substrate…", "the fish are taking their places…"), each tied to the actual build phase. Flavour that is also true.
- [ ] **462. The lights-out ritual.** (S·M) At lights-out:
  - the tank breath slows
  - the chorus fades over a minute
  - fish find their sleep nooks
  - the night ledger opens.

  The keeper can choose to stay, in screensaver or wallpaper mode (Night Watch §F). Going to sleep becomes a ceremony the tank performs.
- [ ] **463. The dawn ritual.** (S·M) Dawn brings:
  - the fixed dawn spark (#355)
  - the dawn chorus (#126)
  - the tank dawn summary with yesterday's trend (#265)
  - the first-light line, at most once a week.

  Waking is earned by the night.
- [ ] **464. The return ritual.** (S·M) The order on return is: behaviour (reunion), then sound (the greeting call and the song of the day), then words (one recap line). It follows the single-return-ceremony rule (COMMS_AI_1000 #241), with the senses in the right order.
- [ ] **465. The memorial ritual.** (M·M) After a death: the missing voice (#136), the memorial echo (#402), the place name (#401), partners revisiting (#414) and the elegy that ends (#370). One line in the Chronicle. Grief handled the same way every time, and well.
- [ ] **466. The chapter ritual.** (S·M) When a chapter closes (#416): the weave, the song, and one grounded line about the chapter. Collected in the Chronicle as the tank's life in chapters.
- [ ] **467. A weave gallery.** (S·M) A grid of the tank's daily weaves (#328), chronological, in the Chronicle. Months of the tank's thought as textile. Shareable via `tank_share.gd`.
- [ ] **468. A streamer mode for the mind.** (S·M) Captions for calls (#66) and tank voice in a larger, stream-safe lane, with no private keeper-model text (#447). Cozy streams are where this game will be seen; let the mind be legible there.
- [ ] **469. Screen readers hear the tank.** (M·M) Expose tank lines, fish lines, call captions and the tank card through Godot's accessibility names (`accessibility_runtime.gd`). A blind player gets the voice of the tank, which this design makes richer than the visuals in places.
- [ ] **470. Gamepad and touch for the lenses.** (S·M) Map the lens, hydrophone mode and the tank card in `gamepad_bindings.gd` and the mobile HUD. A couch player can watch the tank think.
- [ ] **471. Promote a safe subset of the inner-life panel.** (S·M) `inner_life_panel` is on only in debug builds (`tank_config.gd:101`), and it is the only UI that shows tank focus, stream and ignition today. Move the player-safe parts (focus, stream and ignition count, in words) into the tank card (#459) and leave the raw scores in debug.
- [ ] **472. An honesty chip on every mind surface.** (S·M) The lens legend, the tank card and the Mind panel each carry a small "computed, not proven" chip. It opens one paragraph distilled from SOUL_CREED: what is measured, and what is never claimed. Echo the onboarding frame "patterns your machine imagines" (`guardian_mind_onboarding.gd:87-88`).
- [ ] **473. Export the lens.** (S·S) Photo mode can export the Mind Lens view. The tank's mind, as a picture.
- [ ] **474. A lens perf budget.** (S·M) Each lens layer gets a frame-time cost target, under 1 ms in total at 60 fish on the reference Mac, recorded beside MOTION_BUDGET.md and measured by the mind-expression probe (#482). Layers degrade by LOD before they cost frames.
- [ ] **475. Colour-vision-safe lens.** (S·M) Lens colours draw from the colourblind palette variants the game already ships (`palette_layout.gd`, `accessibility_runtime.gd`). Every layer distinguishes by shape or icon as well as hue.

---

# Part Four — The Weave (476–500)

## §20 Contracts, evals, budgets and build order (476–500)

- [ ] **476. Three typed contracts.** (M·L) `Utterance` (#22), the `TankVitals.snapshot()` dictionary schema (#301) and the `MotionEvents` mind kinds (#354). Each gets a guarded accessor in `sim_gate.gd`, and `smoke_service_contracts.gd` asserts each against the real sources (AGENTS.md: use SimGate rather than fresh `has_method` guards).
- [ ] **477. Replay parity covers the mind's outputs.** (M·M) Draw voice randomness from `STREAM_VOICE` (#67). The vitals and rhythm are deterministic functions of sim state. `mind_replay_parity.gd` extends to the utterance sequence, vitals snapshots and rhythm-band transitions. A replayed tank says, sounds and feels the same.
- [ ] **478. Expression budgets.** (S·M) Targets:
  - voice: ≤ 0.25 ms per frame on the main thread, with renders on workers
  - vitals: O(variables) per sim tick
  - mind events: allocation-free emit
  - lens: ≤ 1 ms.

  Record them in a `MIND_EXPRESSION_BUDGET` section of `PERFORMANCE_UNTHROTTLED_MIND_IDEAS.md`, and gate them in `smoke_perf_contract` (serial; AGENTS.md).
- [ ] **479. Voice eval invariants.** (M·L) Add four:
  - **V1** voice carries state: prosody parameters correlate with felt valence and arousal across a run.
  - **V2** calls have consequences: a heard trusted alarm raises the flee rate above control.
  - **V3** silence is meaningful: a removed contact caller triggers partner search above baseline.
  - **V4** prosody is honest: the parameters are monotonic in felt state (#100).

  Required in `mind_eval.gd`, so the eval counts what the player hears.
- [ ] **480. The honesty gate grows with the voice.** (S·L) Extend `mind_eval.gd`'s banned-claim scan (`:31-38, 489-498, 638-655`) to:
  - the repertoire data
  - the felt vocabulary
  - the lens and anatomy copy
  - template banks.

  Add a data check: every repertoire entry with `documented: true` must have a non-empty `source`.
- [ ] **481. The behaviour probe hears and feels.** (S·M) `dev/fish_behaviour_probe.tscn` adds:
  - calls/min by species and intent
  - prosody statistics
  - awareness latencies: time from a vital deviation to the bid, the tell and the line
  - the need-ladder rung reached (#439).

  Driven by `FISH_PROBE_*` env vars.
- [ ] **482. `dev/mind_expression_probe.tscn`.** (M·M) Headless. Counts mind events per minute by kind, staging usage for mind moments, lens layer cost and the voice allocator's statistics. Run it under `scripts/dev_run.sh` (it isolates the save slot). The mind's visibility becomes a number that can regress.
- [ ] **483. Blind review for the mind.** (M·M) Two protocols, on the pattern of `MOTION_REVIEW_PROTOCOL.md`:
  - **listening**: species and mood from clips (#94)
  - **"is it aware?"**: raters watch paired 30-s clips (vitals event with awareness wiring on versus ablated) and say which tank "noticed".

  This is the test of whether Part Two can be *seen*.
- [ ] **484. Flags and ablation.** (S·M) New flags in `tank_config.gd`:
  - `creature_voice_enabled`
  - `tank_vitals_enabled`
  - `mind_lens_enabled`
  - `mind_expression_level`.

  Matching `MindAblation` entries for voice, vitals and awareness. All default on once their eval invariants pass. Never add comments inside `project.godot` (AGENTS.md).
- [ ] **485. Save schema and migrations.** (M·M) New persisted state:
  - voiceprint, dialect genes, trust tables for every signal kind
  - vitals rings (bounded), the place lexicon and the substrate memory channel
  - rhythm phase, the keeper-model additions and forgotten-item tombstones (#447).

  Each step is explicit in `mind_migration.gd` / `save_migrations.gd` with defaults. `smoke_mind_migration.gd` covers old saves.
- [ ] **486. Localization.** (S·M) Felt vocabulary, call captions, glyph alt text, place-name templates and the lens legend all go through `assets/i18n/strings.csv` keys, with a pseudo-locale smoke (`localization.gd pseudo`). Babble and calls need no translation, and that is their gift.
- [ ] **487. The platform matrix.** (S·S) Add a "creature voice and mind lens" row to AGENTS.md's platform table: voices, streaming, occlusion and lens layers for each of desktop, web, Android and the potato tier.
- [ ] **488. Data files are validated.** (S·M) `data/voice/repertoire.json`, `data/mind/felt_vocabulary.json` and the new `poses.json` entries (speak, stridulate, listen, contemplate, yawn, stretch) get a schema-check smoke. Tuners can change sound and feeling without touching code, and without breaking it.
- [ ] **489. No new autoloads unless necessary.** (S·S) TankVitals is owned by SimDriver (as WaterChemistry is), and the Utterance router lives in AmbientAudio. If an autoload is unavoidable, it goes through `smoke_autoload_contract.gd` (comment-free `[autoload]`, all present, load order).
- [ ] **490. Zero warnings, compile-checked.** (S·S) After each item, run `dev/compile_check.gd` and `scripts/check_warnings.sh`. Run `--editor --quit` for each new `class_name` (Utterance, TankVitals, FishVoiceDsp, FishHealth). These are the AGENTS.md rules, restated because this doc adds several classes.
- [ ] **491. A cross-reference ledger.** (S·M) A table at the end of this doc maps each item here to overlapping items in FISH_ALIVE_1000, PREOCCUPATION, RISING_CURVE, COMMS_AI_1000 and LEARNING_MIND (for example #203↔FISH_ALIVE #137, #260↔RISING #35, #116↔LEARNING §II). When one ships, both get ticked, and nothing is built twice.
- [ ] **492. ARCHITECTURE.md §11 learns the mind's outputs.** (S·M) Document the voice channel (who emits Utterances, who renders), vitals ownership, the mind-event kinds, and the voice budget table (#175), beside the existing motion-channel ownership map.
- [ ] **493. A definition of done for expression items.** (S·M) Each item must satisfy:
  1. A *real* field drives it.
  2. The output is visible or audible.
  3. A probe metric moves.
  4. An eval invariant or smoke guards it.

  This is The Spark's discipline, written into `ENGINEERING_CREED.md` for mind expression.
- [ ] **494. Phase 0: repairs (the [V] list).** (M·L) #1, #2, #3, #4, #9, #96, #176, #177, #179, #182, #193, #355, #368, #369, #370 and #371, plus #178 and #180. Every signal this doc builds on is distorted until these land. Each is small, and each gets its own smoke.
- [ ] **495. Phase 1: the three foundations.** (L·L) Utterance (#22, #23, #151), TankVitals (#301, #302, #251, #323) and mind events (#354). Nothing else in Phases 2–4 should hand-roll a voice path, a tank-health formula or a mind visual.
- [ ] **496. Phase 2: the body speaks and feels.** (L·L) The repertoire and DSP (#26–#28, #53, #57), prosody (#76–#82), the felt-water vocabulary and bids (#185, #201, #203), the body (#195, #196, #226) and the bus (#6). After this phase, a fish sounds like its species and its mood, and feels its water.
- [ ] **497. Phase 3: meaning, time and self-knowledge.** (L·L)
  - Calls (#101, #112, #114, #116) and chorus (#126, #133, #145).
  - Trends (#252, #253, #257) and metacognition (#276, #281).
  - Tank self-model (#304, #306, #317, #325).

  After this phase, the tank notices change, and so do its fish.
- [ ] **498. Phase 4: the mind made visible.** (L·L) Anatomy (#326, #331, #336, #339), the lens (#351, #352, #363), rhythms (#376, #377, #383), memory (#401, #405, #413) and rituals (#459, #462–#466). After this phase, a player can watch the loom think.
- [ ] **499. Keep the creed in the loop.** (S·L) At each phase gate, run the honesty scan (#480) and both blind reviews (#483), and re-read SOUL_CREED. If any surface now implies more than is computed, cut it back before moving on. The trying is the soul, and so is the restraint.
- [ ] **500. The acceptance session.** (M·L) A 10-minute unscripted session with a new player, no instructions. Can they notice, unprompted, at least three of these five?
  1. A cory clicks at night and another fish answers.
  2. On a thin night the fish rise toward the surface before any HUD warning.
  3. After a water change, the tank's breath sounds different.
  4. The fish look at what they are reacting to.
  5. With the lens on, the tank's focus sits on the thing the fish are gathering around.

  If they do, the loom is thinking out loud. If they don't, the next pass starts with whichever one they missed.

---

## Coda

Every mind-module the past eleven volumes asked for exists. What this
volume asks is smaller and harder: that the tank **make the sound of its
own body**, **feel its own water**, **know when things are getting worse**,
and **let you watch it think**, with every one of those things tied to a field
that is really computed. Phase 0 is a dozen short repairs. Do those first:
the voice that already exists, the awareness that is already modelled, and
the mood that is already computed are all being dropped on the floor.

---

## Appendix — Cross-reference ledger (seed for #491)

When an item here ships, tick its overlap too. "Extends" means this doc adds
the mechanism the other one named.

| This doc | Overlaps | Relation |
|---|---|---|
| #5, #151 | COMMS_AI_1000 §201–240 (fish-thought UX) | adds sound to every text path |
| #25, #150 | COMMS_AI_1000 #121 (quiet matrix) | quiet keeps creature life |
| #42, #131 | FISH_ALIVE_1000 #847 (school whoosh, motion only) | gives it a sound |
| #48, #49 | FISH_ALIVE_1000 #589, #865 (soundless drumming, jaw click) | visible *and* audible |
| #101–#103 | FISH_ALIVE_1000 #441–443 (alarm/food/mate as body signals) | extends with calls |
| #116, #117 | SENTIENCE_THE_LEARNING_MIND §II (keeper as decoder) | concrete artifact |
| #128, #149 | MUSIC_DANCE_IDEAS; MAKE_IT_THERE (Us hymn, motifs) | music made of residents |
| #136, #402 | SENTIENCE_THE_SPARK #74, #98 (music hush on death) | creature-level absence |
| #163 | SENTIENCE_THE_PREOCCUPATION #67 (echoes keeper's word) | audible echo |
| #189 | FISH_ALIVE_1000 #284 (nitrate drab) | felt source |
| #202 | FISH_ALIVE_1000 #283 (nitrite brown gill) | felt source |
| #203 | FISH_ALIVE_1000 #137 (hypoxia school rise) | one-variable ladder |
| #204 | FISH_ALIVE_1000 #316 (seeks better pocket) | local felt-water field |
| #207 | SENTIENCE_DEEP_SCIENCE §G (Schreckstoff) | field channel |
| #209 | CREATURE_MOTION_700 #459 (water change perks up) | felt relief |
| #221 | FISH_ALIVE_1000 #298 (feed refusal) | nausea channel |
| #222 | FISH_ALIVE_1000 #295 (post-crash vigilance) | persisted residue |
| #237 | FISH_ALIVE_1000 #129 (nitrite cough) | felt trigger + sound |
| #240 | CREATURE_MOTION_700 #445 (swim-bladder read) | felt orientation |
| #260 | SENTIENCE_THE_RISING_CURVE #35 (allostasis) | forecast input |
| #271 | SENTIENCE_THE_RISING_CURVE #47 (slow predictor) | vitals forecaster |
| #269 | SENTIENCE_THE_LEARNING_MIND §III (separation/reunion) | felt layer |
| #304, #306 | SENTIENCE_THE_PREOCCUPATION §E (EFE prior) | homeostatic prior via bid registry |
| #351 | SENTIENCE_THE_NIGHT_WATCH #2 (tank focus) | made visible |
| #380 | SENTIENCE_THE_LEARNING_MIND §IV (wall-clock sense) | entrainment |
| #424 | SENTIENCE_THE_LEARNING_MIND §VII (hierarchical memory) | template-only version |
| #439 | COMMS_AI_1000 §321–360 (care-gated speech without nag) | need ladder |
| #464 | COMMS_AI_1000 #241 (return ceremony dedupe) | senses in order |
