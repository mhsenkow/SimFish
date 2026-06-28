# You & Them — 50 Deep Ideas (Pillar 5: The Player Bond)

*Drafted 2026-06-26. Director's brief for the player↔fish bond.*

The goal: a real **two-way channel**. Fish that notice *you* — your cursor, your
face at the glass, your gestures, your routine — and that you can read noticing
you back. "They know I'm here" is the single biggest sentience multiplier,
because sentience is *relational*: a mind that responds to you feels like a mind.

Format follows the prior docs: **Effort** S/M/L, **Impact** S/M/L; file:line
pointers (line numbers are hints — follow the symbol). Each idea is tagged with
its sensing dependency: **[no model]** pure code, **[webcam]** needs the face
stack, **[hands]** needs hand/pose, **[mic]** needs audio capture.

> **What exists today (so we build beyond it):**
> - **The "glance" is a proxy, not real sensing.**
>   [`update_player_glance(camera_pos)`](../shaders-godot/godot-project/scripts/sim_driver.gd:345)
>   clamps the orbit camera's *position* into the tank and adds a "hold bonus"
>   when the camera is still ≤0.05u for up to 6s. That's the entire model of
>   "the player is paying attention." Fish read it via
>   `_cached_glance_strength` / `_cached_glance_point`
>   ([fish.gd:4040](../shaders-godot/godot-project/scripts/fish.gd:4040), throttled 1s).
> - **`familiarity`** (0..1, persisted) builds when fed near the camera
>   ([fish.gd:4081](../shaders-godot/godot-project/scripts/fish.gd:4081)) and
>   lowers the approach gate: `effective_bold = boldness + familiarity*0.4`.
> - **`habituated["player"]`** decays novelty so the player gets "boring."
> - **Touch:** `_startle_fish_near_tap()`
>   ([main.gd:1558](../shaders-godot/godot-project/scripts/main.gd:1558)) +
>   `sim.pulse_glass_tap()`; `_drop_food_at_cursor()`
>   ([main.gd:1603](../shaders-godot/godot-project/scripts/main.gd:1603));
>   `_pick_creature_at_click()` to follow.
> - **No device sensors at all** — no `CameraServer`, no microphone, no
>   accelerometer. Clean slate.
> - **Native plugins already ship** (`godotsteam.gdextension` across
>   mac/win/linux/android) and Apple cam/mic entitlements are already scaffolded
>   in `export_presets.cfg` — so the native-extension path is *proven*.

---

## Director's verdict: can we bundle a local model under 500MB?

**Short answer: yes for the part that matters, with one smart caveat.** The key
is to *decouple sensing from language* — they're different models with wildly
different sizes.

**Your size picture is great.** The project is 104MB, but **93MB of that is the
godotsteam addon** (native binaries for *all* platforms). A per-platform export
only ships one platform's binary, and the actual game content is tiny (~3MB
scripts, ~0.2MB shaders, ~0.2MB assets — it's procedural). So a desktop export
is well under 150MB today. You have lots of headroom under 500MB.

**1. Player-SENSING models (face / hands / pose) — bundle them. ~30–50MB.**
These are tiny and they deliver ~80% of this entire pillar:
- Face detection (BlazeFace): ~1–2MB · Face landmarks/mesh: ~3–4MB
- Hand tracking (palm + landmarks): ~15MB · Body pose (MoveNet Lightning): ~5–9MB
- ONNX Runtime (or MediaPipe) native lib: ~10–25MB, one per export.

**Total added ≈ 30–50MB.** Trivially under budget, on every platform incl.
Android. (Web: getUserMedia + ONNX-Runtime-Web/MediaPipe-WASM works too.) **Do
this.** It's the transformative layer and it's cheap.

**2. A bundled LANGUAGE model (instead of Ollama) — possible, but cap it small
and ship it as an optional download.**
- The current `qwen2.5:3b` (Ollama) is ~2GB quantized — can't bundle.
- Realistic bundled ceiling under 500MB: **SmolLM2-360M Q4 ≈ ~250MB** (comfortable)
  or **Qwen2.5-0.5B-Instruct Q4 ≈ ~400MB** (tight; non-Meta, respects your
  model preference). Engine = llama.cpp as a GDExtension (~2–10MB). Good enough
  for short *flavor* (one-line bios, micro-thoughts), not real reasoning.
- **Caveat:** baking even 250MB into the base installer hurts the **Web** build
  badly (multi-hundred-MB download before play) and bloats the Android base. So:

**Recommended architecture (tiered — fits the existing fail-soft AIDirector):**
- **Tier 0 — templates/offline** (today's fallback): 0MB, always works.
- **Tier 1 — bundle the vision stack** (~40MB) for all the *sensing* in this doc.
- **Tier 2 — tiny LLM as an opt-in first-run download** (~250–400MB), not baked
  into the base installer → base install stays safely <500MB everywhere.
- **Tier 3 — Ollama** (existing) as the "pro" tier for users who have it.

So: **the "they notice me" magic ships in ~40MB and stays tiny. The "they have a
voice" magic uses a ≤0.5B model delivered as an optional download.** That keeps
you under half a gig on every platform, with Ollama still available as the
premium upgrade. (Exact bytes depend on final quant — I can pin precise per-
platform numbers once you pick the engine + model.)

---

## Section A — The cursor & touch channel (deepen what's there) · [no model]

The fastest wins — buildable today, no sensors. The current channel is blunt
(camera-position glance + a startle tap); make it expressive.

- **1. Cursor as a finger at the glass.** When the player *hovers* (not dragging)
  over the glass, project a "fingertip point" into the tank; curious/bold fish
  drift over and track it as it moves. The classic finger-follow. Today only
  camera position feeds glance ([sim_driver.gd:345](../shaders-godot/godot-project/scripts/sim_driver.gd:345))
  — add a distinct hover channel. *M · L*
- **2. Lure & lead.** Move the cursor slowly → bold fish follow it in a little
  conga line; move it fast/erratic → they scatter. Real-time play, gated by
  per-fish boldness/familiarity ([fish.gd:4058](../shaders-godot/godot-project/scripts/fish.gd:4058)). *M · L*
- **3. Make "glance" actually gaze.** Replace proximity-as-attention with a real
  look ray: raycast the camera/cursor forward and find which fish are *in the
  look direction*, so a fish feels specifically looked-at, not just "camera is
  near." Upgrade [sim_driver.gd:355](../shaders-godot/godot-project/scripts/sim_driver.gd:355). *M · M*
- **4. Per-fish "being watched" response.** When one fish is the gaze target, it
  reacts as an individual — shy freezes/edges off, bold approaches and poses.
  Route gaze to the picked/followed fish, not the whole tank. *M · M*
- **5. A tap grammar.** One gentle tap = curiosity ping (fish look); rapid taps =
  alarm (flee); tap-and-hold = sustained presence. Today Shift+LMB is a single
  blunt startle ([main.gd:1558](../shaders-godot/godot-project/scripts/main.gd:1558)).
  Give taps meaning. *M · M*
- **6. Cursor warmth builds trust.** Time spent calmly near your hovering cursor
  (no startle) slowly raises familiarity, like feeding does — extend the
  familiarity build ([fish.gd:4081](../shaders-godot/godot-project/scripts/fish.gd:4081))
  to the hover channel. *S · M*
- **7. The don't-chase paradox.** Skittish fish flee a cursor that chases but
  approach one that waits nearby — reward patience. "Earn them by not grabbing."
  *M · M*
- **8. Taps you can feel (directionally).** A glass tap registers on the
  lateral-line sense (sentient-fish doc #3) so fish orient *toward or away* from
  the tap point by temperament — not a blanket startle. *S · M*
- **9. The cursor near feeding time.** The spot your cursor hovers becomes
  associated with food via `feed_heatmap`
  ([fish.gd:126](../shaders-godot/godot-project/scripts/fish.gd:126)); fish gather
  to your cursor near feed time *before* food drops. *M · M*

---

## Section B — Your face in their world · [webcam]

The transformative layer (vision stack ~40MB). The elegance: **feed the face
channel into the *same* `update_player_glance()` point/strength** the camera
proxy uses, so all downstream fish behavior works unchanged — you're just
swapping the *source* of "where's the player."

- **10. Presence detection — "someone's there."** The lightest use: a face is
  present + roughly where. Sit down at the tank → fish notice the new presence
  and come to the glass (shy ones retreat). The single biggest "they know I'm
  here" beat. BlazeFace (~1MB). *M · L*
- **11. Face-following.** Fish track your face across the screen — move left, the
  bold ones follow. Map face centroid → a glass-plane point feeding
  `_interest_target`. "They watch you move around the room." *M · L*
- **12. Eye contact.** Face-mesh gaze: looking *at* the tank vs past it changes
  how attentive fish respond; look away and they relax/disperse. ~4MB. *M · M*
- **13. Lean-in intimacy.** Face size = distance. Lean toward the glass → bold
  fish meet you at the front pane; lean back → they drift to mid-tank. A physical
  proximity dance. *M · M*
- **14. Personality split on *your* arrival.** Same presence makes bold fish
  approach and shy fish hide — reuse the `effective_bold` split
  ([fish.gd:4058](../shaders-godot/godot-project/scripts/fish.gd:4058)). Real
  presence makes personalities legible against *you*. *S · M*
- **15. They learn *your* face.** Over sessions, fish habituate to your recurring
  presence (less startle, faster approach) — extend `habituated["player"]`
  ([fish.gd:2503](../shaders-godot/godot-project/scripts/fish.gd:2503)) to mean
  *you*. An unfamiliar face gets the cautious treatment (see #37). *M · L*
- **16. Gentle expression mirroring.** A relaxed/smiling face nudges tank mood
  calmer/brighter (a calm keeper = a calm tank). Subtle, opt-in; ties to the
  emotion doc's contagion. *M · M*
- **17. Performing for the watcher.** Frame the webcam presence in-world as a
  large gentle "watcher" beyond the glass; bold fish *display/show off* when
  watched, reusing courtship display anims. "Peacocking for you." *M · M*
- **18. Privacy-first foundation (non-negotiable).** Frames never leave the
  device; all processing on-device; explicit opt-in toggle; full graceful
  fallback to the cursor/camera proxy when off. Apple cam entitlement already
  scaffolded (`export_presets.cfg`). *M · L (foundation)*
- **19. One presence pipe.** Implementation discipline: webcam face, cursor
  hover, and camera proxy all resolve to the same glance point/strength
  ([sim_driver.gd:345](../shaders-godot/godot-project/scripts/sim_driver.gd:345)),
  picking the best available source. Everything downstream stays source-agnostic.
  *M · M (foundation)*

---

## Section C — Gesture language: things you do that they answer · [hands]

MediaPipe Hands (~15MB) / pose (~9MB). Keep the vocabulary small and high-signal,
and **always with a tap/key equivalent** so it's additive, never gating.

- **20. Open palm = the feeding hand.** Show an open palm → fish that trust you
  gather expectantly (then tap to actually feed). The universal "food's coming"
  cue. *M · L*
- **21. Point to lead.** Point at a spot → bold fish look/move that way. Hand
  vector → tank point → interest target. *M · M*
- **22. Wave hello.** A wave triggers a greeting beat — fish that know you
  approach; new fish startle. A ritual. *M · M*
- **23. "Settle" hand.** A slow flat-hand lowering gesture (paired with #16)
  lowers tank arousal — you can *soothe* a stressed tank with a gesture. *M · M*
- **24. Real finger at the glass.** Index-fingertip landmark → the finger-follow
  point: the physical version of #1, fish track your actual finger near the
  screen. *M · M*
- **25. Gestures they *learn*.** Pair a repeatable gesture with food (conditioning,
  sentient-fish doc #16) so fish learn *your* personal "come here" signal —
  trainable per tank, persisted per fish. *L · L*
- **26. Big two-hand presence.** Spread arms (pose model) = a large presence that
  impresses bold fish / spooks timid ones — playful full-body scale interaction.
  *M · S*
- **27. Acknowledge the gesture.** When a gesture lands, give a clear in-world ack
  (fish orient + soft chime) so the player *learns the fish understood* — closes
  the call-and-response loop legibly. *S · M*

---

## Section D — Recognition, trust & the taming arc · [no model] (richer with [webcam])

The relationship layer — mostly code, building on `familiarity`. This is where
"they know me" becomes a felt, earned thing.

- **28. A per-fish bond with *you*.** `familiarity` is one generic scalar; make
  each fish's bond legible and distinct — some warm fast, some never fully do
  (personality). Surface a trust meter in the inspect panel. *M · L*
- **29. The taming arc (headline).** A shy newcomer you earn over days: calm
  presence + hand-feeding + no startles → fleeing → glass-watching → eating from
  your cursor/finger. Multi-session progression with milestone story-log lines.
  The core relationship payoff. *L · L*
- **30. Recognizing you vs a stranger.** With #15, your recurring face = "safe
  keeper," an unknown face = cautious. Without webcam, "you" = the consistent
  interaction pattern. Recognition is always *specific*. *M · L*
- **31. The hand that feeds.** Fish associate the direction food arrives from
  (your feeding spot, `feed_heatmap`) with you and orient to that "hand"
  expectantly — the most basic real-fish bond, made explicit. *M · M*
- **32. Trust is losable.** Repeated startles (taps, lunges) drop bond/familiarity;
  rebuilding takes time. The trauma scar ([fish.gd:2685](../shaders-godot/godot-project/scripts/fish.gd:2685))
  applied to *the relationship*. Makes trust mean something. *M · M*
- **33. Bond unlocks intimacy, not points.** High bond unlocks behaviors —
  hand-feeding, cursor-following, posing, resting where you sit — never a score
  (ties to H10 #96, serenity-not-points). *M · M*
- **34. The ones you love, love you back.** A named/favorited fish (follow +
  residents panel) bonds faster and remembers you best. Mutual attention — the
  ones you watch become the ones who know you. *S · M*
- **35. Readable at a glance.** A bonded fish behaves differently *on sight of
  you* (comes forward, fins up) so you read your relationships without a panel —
  the tank greets you according to how you've treated it. *M · M*
- **36. Guest mode.** A "someone else is watching" state (different face, or a
  toggle) where the tank acts shyer — so showing a friend feels true: "they're
  shy with you; they know me." Delightful social proof of the bond. *M · M*

---

## Section E — Begging, following & reciprocity (the visible loop) · [no model]

The two-way loop made unmistakable: they ask, you answer, that invites the next
move. This is the literal "noticing each *other*."

- **37. Begging at feeding time.** Fish that learned your rhythm crowd the front
  glass and beg (excited vertical bobbing — the betta/cichlid classic) when they
  sense you near feed time. The #1 "they want me" tell. *M · L*
- **38. Greeting on arrival.** Fresh presence (face appears / app refocus / cursor
  returns) → bonded fish do a brief greeting swim to the front. "Happy to see
  you." *M · M*
- **39. An entourage that follows.** Bold/bonded fish track and follow your
  face/cursor along the glass — a persistent follow for high-bond fish (extends
  #2). *M · M*
- **40. Call and answer.** Design explicit reciprocal loops: you act (tap, gesture,
  lean) → they respond → their response invites your next move. Rhythm, not
  one-shot reactions. *M · L*
- **41. They ask *you* for things.** A hungry fish begs; a stressed one hovers at
  the cleaner station where you can see it — the tank communicates needs *to
  you*, expressed by the fish (the in-world version of H10 #92 nudges). *M · L*
- **42. Reward reinforces the loop.** Answer a beg with food, or a greet with
  attention, and bond ticks up + the fish visibly registers the payoff — the loop
  self-reinforces. *S · M*
- **43. The unbothered ones.** Some species/personalities ignore you entirely
  (true to life) — which makes the ones who *do* engage feel chosen. Restraint as
  design. *S · M*

---

## Section F — Presence, absence, ritual & voice · [no model] + [mic]

The relationship across time — and the audio channel (reuse the music-reactive
bus, no model needed for clap/voice energy).

- **44. They notice you leave.** Presence drops (face gone / window blurred /
  cursor long-idle) → the tank settles into "no one's watching" mode: more
  natural, less front-glass. Catching them off-duty paradoxically sells the
  aliveness. *M · M*
- **45. Eager return after absence.** Tie to the away-summary (`last_quit_unix`,
  H10 #94): the longer you were gone, the bigger the greeting on return (within
  reason). "They missed you." *M · M*
- **46. Daily ritual recognition.** Visit at consistent times → fish anticipate
  *you* at that hour (extends conditioning + rhythm-learning, sentient-fish #21).
  Your routine becomes theirs. *M · M*
- **47. Clap / voice channel.** Feed a mic capture (`AudioEffectCapture`) into the
  existing music-reactive audio bus
  ([music_reactive.gd](../shaders-godot/godot-project/scripts/music_reactive.gd),
  `AudioEffectSpectrumAnalyzer`) — a clap grabs attention, a calm voice soothes.
  Opt-in, on-device, ~0MB (pure DSP). Mic entitlement already set. *M · M*
- **48. It knows its name.** A tiny on-device keyword spotter (or, honestly, even
  audio-energy routed to your *followed/favorite* fish) makes saying a fish's
  name turn *that* fish toward you. Even a "faked" version lands hard
  emotionally. Scope carefully. *L · M*
- **49. Reading the room.** Sustained loud/chaotic ambient audio (a party) makes
  the tank warier; quiet calm makes it bolder — the tank responds to your
  environment, not just direct input. *M · S*
- **50. The relationship is the long game.** Frame the whole pillar as a bond that
  deepens over months: a per-fish "relationship" view (how you met, trust earned,
  shared history pulled from `bio`
  ([fish.gd:113](../shaders-godot/godot-project/scripts/fish.gd:113)) + the story
  log + lineage). You & Them becomes the emotional spine, not a gimmick. *M · L*

---

## If Cursor only does five

The substrate first (#18/#19/#28 — privacy-opt-in, one presence pipe, per-fish
bond), then:

1. **#3 → #10** — make "glance" a real presence source (cursor-gaze today;
   webcam face when the vision stack lands). Everything else plugs into this.
2. **#37** — begging at feeding time (the biggest "they want me" tell; pure code).
3. **#29** — the taming arc (the headline relationship payoff, multi-session).
4. **#1** — cursor-as-finger they follow (instant magic, no model).
5. **#20** — open-palm feeding gesture (flagship gesture once hands are in).

> **Build order that respects the model question:** ship Sections A + D + E first
> (all **[no model]**, all buildable now — they make the bond real with zero size
> cost). Land the **[webcam]** vision stack (~40MB) for Section B as the big
> upgrade. Treat the bundled LLM (sentient-fish doc's "voice") as a later opt-in
> download. That sequence keeps you shippable and under 500MB the whole way.
