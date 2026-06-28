# Sentient Fish — 50 Deep Ideas (Pillar I: Inner Life)

*Drafted 2026-06-26. Director's brief for the inner-life pass.*

The north star: fish that seem to **think and feel** — that visibly perceive,
deliberate, remember, have moods you can read, and grow into individuals you
bond with. Four seams: (1) the thinking fish, (2) memory & learning,
(3) emotion & mood, (4) personality & character arcs.

Format follows [GOALS.md](GOALS.md) / [the plants doc](PLANT_IMPROVEMENT_IDEAS.md):
**Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S / M / L. Every
idea is grounded with file/line pointers (line numbers are navigational hints —
follow the symbol name if they've drifted).

> **The fish-brain is already deep.** Before adding anything, know what's
> shipped so you don't rebuild it:
> - **Decision loop** — a priority-tiered state machine in
>   [`fish.gd` tick()](../shaders-godot/godot-project/scripts/fish.gd:2468) with
>   ~25 tiers and `enum Mode { CRUISE, FORAGE, COURT, SPAWN, FLEE, REST }`.
> - **Personality** — 5 heritable traits (`boldness, curiosity, sociability,
>   gluttony, calm`), rolled/inherited in
>   [`creature_naming.gd`](../shaders-godot/godot-project/scripts/creature_naming.gd),
>   persisted, with epithets ("the Bold").
> - **Affect** — `mood`, `stress`, `curiosity_drive`, `spooked`, `familiarity`
>   ([fish.gd:200–268](../shaders-godot/godot-project/scripts/fish.gd:200)).
> - **Memory** — `feed_heatmap` (4³), `grudges`, `habituated`, a 6-event working
>   `memory` ring, `visited_regions` (4³), `bonds`, `lead_score`.
> - **AI layer** — [`ai_director.gd`](../shaders-godot/godot-project/scripts/ai_director.gd)
>   Ollama bridge: names, a 4³ regional "intent" mood grid, transient per-fish
>   moods, and ambient chronicle lines. Offline-first.
> - **Identity** — `bio` lifetime journal, personalized epitaphs + mourning in
>   [`sim_driver.gd`](../shaders-godot/godot-project/scripts/sim_driver.gd),
>   lineage tree. Save v5.
> - H9 (#81–90) already shipped: learns-you familiarity, the trauma scar,
>   pair bonds, rest debt, boredom, desperation, social-need stress.

---

## The three structural levers (read this first)

Most of the 50 hang off three architectural gaps. Fixing these is what turns
"good behavior rules" into "a mind."

**Lever 1 — Decisions are winner-take-all, so you never see deliberation.**
The tier system uses **early returns**: the highest active drive fires and
blocks the rest ([fish.gd:2468+](../shaders-godot/godot-project/scripts/fish.gd:2468)).
A fish can't *visibly* weigh curiosity against caution, hesitate, or change its
mind — it just snaps to whatever wins. The single biggest "it's thinking" win is
a thin **arbitration/deliberation layer** over the tiers (#10–12). This is the
headline.

**Lever 2 — Perception is radius-based and omniscient, so "noticing" is free.**
There's no real field of view or line-of-sight — fish find food/threats via
`sim.query_*_in_radius()` regardless of where they're facing or what's in the
way (only boids alignment uses a cone, at ~[fish.gd:5594](../shaders-godot/godot-project/scripts/fish.gd:5594)).
Give fish a **real sensorium** (vision cone, occlusion, scent, lateral line) and
suddenly "it spotted me," "it didn't see the food behind the rock," and "it
smelled the flake" become believable (#1–5).

**Lever 3 — The LLM never speaks about an individual.**
[`ai_director.gd`](../shaders-godot/godot-project/scripts/ai_director.gd) only
produces ambient *regional* moods + tank-level chronicle. It never says anything
about *this fish*. Pointing the LLM at individuals — one-line bios, periodic
reflections on a fish's arc — is the cheapest, highest-immersion path to
"sentient" (#38–39). Always with an offline fallback.

---

## Section A — The Thinking Fish (perception, attention, deliberation)

### Perception — give them a real sensorium (Lever 2)

- [x] **1. True vision cone.** Add a forward FOV; targets outside it aren't seen
  until the fish sweeps its gaze. Gate the radius queries in
  [tick()](../shaders-godot/godot-project/scripts/fish.gd:2468) by a
  `heading · to_target` cone test (reuse the boids-cone math at
  [fish.gd:5594](../shaders-godot/godot-project/scripts/fish.gd:5594)). Makes
  head-turns meaningful and creates honest "didn't notice it" beats. *M · L*
- **2. Line-of-sight occlusion.** A flake behind a rock / a predator behind a
  plant isn't detected until the fish rounds it. Cheap occlusion check against
  hardscape + dense plant biomass before a percept counts. Makes scapes actually
  hide things (deepens fry shelter + ambush). *M · M*
- **3. Lateral-line sense.** Short-range *omnidirectional* detection of sudden
  movement — a neighbor's dart or struggle felt even when off-camera/behind.
  Drives a flinch + turn-to-look. The sense that "something moved." *M · M*
- **4. Scent gradients.** Food and dying/bleeding creatures emit a diffusing
  scent plume; bottom-feeders especially do chemotaxis (swim up-gradient)
  instead of teleport-knowing where food is. Layer onto the waste/food spatial
  queries ([~fish.gd:3327](../shaders-godot/godot-project/scripts/fish.gd:3327)).
  *L · M*
- **5. Acuity that depends on conditions.** Scale sight range by species
  (predators sharper), light level (dim at night/low light), and water clarity —
  couple to the existing `bloom_intensity` + `tannins`. A fish gropes in murky
  water; a clear tank sees far. *S · M*

### Attention — one spotlight, with tells

- **6. Attention as a scarce resource.** A fish truly attends to ONE salient
  thing at a time, with a switching cost — so a hungry fish fixated on food is
  slower to notice a threat (believable tunnel vision). Today many tiers attend
  at once. Track a single `_focus` percept; bias sensing toward it. *M · L*
- **7. Salience-driven gaze.** Score each percept (motion, size, novelty,
  hunger-relevance, threat) and point the head/eye at the winner every moment,
  reusing `_interest_target` / `_gaze_yaw`
  ([fish.gd:4125](../shaders-godot/godot-project/scripts/fish.gd:4125)). The eye
  always rests on the most interesting thing — the core "it's paying attention"
  read. *M · M*
- [x] **8. Telegraph intent before acting.** A brief "aim" pose — orient + coil — a
  beat before a dart to food or a flee, like a cat's wiggle before a pounce. Hook
  the `burst_remaining` triggers
  ([~fish.gd:891](../shaders-godot/godot-project/scripts/fish.gd:891)). Lets the
  player *read* the decision a moment before the motion. *M · L*
- [x] **9. Double-take.** After passing something novel, occasionally stop and look
  back — "wait, what was that?" Extends the novelty pause
  ([fish.gd:4239](../shaders-godot/godot-project/scripts/fish.gd:4239)) with a
  backward glance. *S · M*

### Deliberation — the visible act of deciding (Lever 1 — the headline)

- [x] **10. Approach–avoidance conflict.** When two drives are close in strength
  (curiosity vs caution at a novel object; hunger vs fear at food near a
  predator), the fish *oscillates* — edges in, retreats, edges in again — before
  committing. THE "you can see it thinking" behavior. Needs a soft-arbitration
  pass over the early-return tiers. *L · L*
- [x] **11. Commitment threshold + hysteresis.** A new drive must beat the current
  one by a margin for a short dwell before the fish switches modes — so it
  doesn't flip-flop, it visibly *makes up its mind* and then sticks. Add a small
  deliberation state between tier evaluation and mode-set. *M · L*
- [x] **12. Indecision animation.** When arbitration is near-tied: micro-pauses,
  head swivels between the two options (food… threat… food…), a fin twitch. Pure
  body-language read of an internal tie. Pairs with #10/#11. *M · M*
- **13. Anticipation & prediction.** Lead drifting food (intercept where it
  *will* be, not where it is), and gather at the feed spot *before* food drops
  from a learned schedule — deepen the feed-anticipation tier
  ([fish.gd:4277](../shaders-godot/godot-project/scripts/fish.gd:4277)) into
  "it knows it's almost feeding time." *M · L*

---

## Section B — Memory & Learning (a fish with a past)

- [x] **14. Make personality *learnable*, not just scarred.** Today the only trait
  change is a one-way `−0.03` boldness scar after trauma
  ([fish.gd:2685](../shaders-godot/godot-project/scripts/fish.gd:2685)).
  Generalize to slow two-way conditioning: repeated safe feedings at the glass
  raise boldness; repeated frights lower it. A fish you've hand-fed 100 times
  *becomes* genuinely bold. *M · L*
- **15. Category fear conditioning.** Generalize `grudges` (per-individual) to
  size/shape categories — bullied by 3+ big fish → wary of *all* big silhouettes;
  learns "tall shadow = danger." Decays faster for high-curiosity fish. *M · M*
- **16. Classical conditioning to cues.** Pair a repeatable cue (the feed tap,
  lights-on, lid open) with food; after enough pairings the fish responds to the
  cue *alone* — rushes up when you tap, before any food. Builds on `habituated` +
  feed anticipation. The clearest "it learned" demo. *M · L*
- **17. Learned, persisted sleep nooks.** `_sleep_nook` is transient; persist it
  and strengthen the bond with each undisturbed night. A fish returns to *its*
  spot; disturbed there, it picks a new one. (Hook noted in the audit.) *M · M*
- [x] **18. Populate patrol anchors.** `patrol_anchors` is allocated but never filled
  ([fish.gd:249](../shaders-godot/godot-project/scripts/fish.gd:249)). Bin the
  top 2–3 `feed_heatmap` hotspots into a loop so a fish has a visible daily
  *route* / tended territory. Instant "it has a routine." *M · M*
- [x] **19. Newcomer → resident arc.** A freshly added fish explores widely (high
  novelty), then settles into a learned home range over days via `visited_regions`
  + a confidence field. Nervous newcomer becomes settled local — a visible
  multi-session arc. *M · M*
- **20. Persisted episodic memory.** The 6-event working `memory` is transient.
  Persist a tiny "notable episodes" log per fish (first meal, first spawn,
  survived a chase, the heater-fail night) that both feeds the bio/chronicle
  *and* drives behavior — e.g. wariness near the spot it nearly died. *M · L*
- **21. Learn the rhythm.** Learn the day/night feeding rhythm and your session
  cadence; a usually-morning-fed fish gets active as the lights come up. Couples
  to the day-length / seasons system (H8 #74). *M · M*
- [x] **22. Curiosity-modulated habituation.** High-curiosity fish habituate *slower*
  (stay interested), low-curiosity fish get bored fast. Today `habituated` decays
  at a flat rate ([fish.gd:2503](../shaders-godot/godot-project/scripts/fish.gd:2503)).
  Makes curiosity a felt trait. *S · M*
- [x] **23. Learned food preferences.** Fish remember which food *kind* satisfied
  them and bias toward it — nudge the static per-species appeal multiplier
  ([fish.gd:614](../shaders-godot/godot-project/scripts/fish.gd:614)) with
  experience. "She loves the bloodworms." *S · M*
- **24. Social learning / imitation.** Naive fry adopt nearby adults' feed/shelter
  map as a prior (copy their heatmap), and leaders "teach." Extend gaze contagion
  ([fish.gd:4089](../shaders-godot/godot-project/scripts/fish.gd:4089)) from
  momentary copying into actual learning. *M · L*
- [x] **25. Emotionally-weighted forgetting.** Not everything should decay at the
  same `0.985/5s`. Scares fade in minutes; near-death traumas and strong bonds
  persist far longer. Memory that feels like memory. *S · M*

---

## Section C — Emotion & Mood (feelings you can read)

- [x] **26. Two-axis affect (valence × arousal).** `mood` is a 1-D scalar
  ([fish.gd:206](../shaders-godot/godot-project/scripts/fish.gd:206)). Add
  *arousal* (calm↔excited) so you can tell "content & resting" from "content &
  playing," and "sulking" from "panic." The substrate for every readable state
  below. *M · L*
- [x] **27. Named states with full-body choreography.** Derive discrete moods
  (content, excited, anxious, frustrated, playful, grieving, bored, cozy) from
  valence/arousal + context, each with a signature *motion quality*: frustrated =
  sharp repeated jabs at the obstacle; cozy = slow tight circles in a nook; bored
  = listless drift. The player reads feelings from how a fish *moves*. *L · L*
- **28. Emotional contagion.** Mood/stress spreads through the school — one
  anxious fish lifts neighbors' arousal, a playful one invites play. Only startle
  headings + gaze spread today; add affect so the tank has a *collective* mood.
  *M · L*
- **29. Color as a live emotion readout.** Deepen mood→color: fear blanches /
  shows stress bars, excitement & courtship intensify, aggression darkens — fast
  chromatophore-style shifts, not just slow vividness. Make it state-specific and
  legible at a glance. *M · M*
- **30. A posture & fin vocabulary.** Clamped fins (stress), flared (excitement/
  aggression), drooping (low energy), erect dorsal (alert) — a readable library
  mapped to states, beyond the current single fin-spread→mood link. *M · M*
- **31. Frustration → giving up.** Repeated failure at a goal (food behind glass,
  a missed hunt) builds frustration (sharper motion), then the fish *disengages*
  — visible persistence then resignation. A new affective loop. *M · M*
- [x] **32. Contentment / "flow."** Great conditions → a visibly relaxed state: slow
  tail, soft turns, hanging in a favorite spot, fins easy. The serenity payoff
  (ties to H10 #96) — a healthy tank should *look* calm. *S · M*
- **33. Boredom that drives action.** H9 #85 made barren tanks listless; go
  further — a bored fish *invents* activity (chases bubbles, nips a plant,
  shadows the cursor). Boredom as a driver, not just a damper. *M · M*
- [x] **34. Startle → vigilance → baseline.** Make the recovery *behaviorally*
  distinct: freeze → hyper-vigilant (extra head-checks, hugs cover) → gradual
  return. `spooked` already decays
  ([fish.gd:2723](../shaders-godot/godot-project/scripts/fish.gd:2723)); give the
  middle phase its own read. *S · M*
- **35. Daily mood weather.** Each "morning" a fish wakes with a mood seeded by
  overnight conditions (rest debt, water quality) that colors the whole day —
  "she's in a mood today." Reads as genuine off-days and good-days. *M · M*
- [x] **36. Anticipatory excitement.** Visible pre-reward buzz: when feed cues fire,
  well-fed-history fish get aroused — faster, fins up, gathering. The "dinner's
  coming!" energy. Couples to conditioning (#16). *S · M*
- **37. Comfort in place.** A fish has a spot it feels safe (its nook/plant) and
  retreats there to *settle* when arousal spikes; proximity drains stress faster.
  Emotional attachment to place (pairs with learned nooks #17). *M · M*

---

## Section D — Personality & Character Arcs (who *this one* is)

*This is where the AIDirector LLM earns its keep (Lever 3). All LLM items must
degrade gracefully offline — the bridge is already fail-soft.*

- [x] **38. LLM one-line bio per named fish.** A one-time *batched* call: given
  personality + species + lineage, write a 1-sentence character bio, shown on
  hover/inspect. The AIDirector already batches names this exact way
  ([ai_director.gd:289](../shaders-godot/godot-project/scripts/ai_director.gd:289))
  — mirror it. Offline fallback: the epithet system. Huge attachment-per-token.
  *M · L*
- **39. LLM-as-witness.** Occasionally the LLM narrates a *specific* fish's arc
  from real bio/personality deltas — "Mira has grown bold: three chases survived,
  her wariness fading." Pipe through the existing `chronicle_line` signal
  ([ai_director.gd:26](../shaders-godot/godot-project/scripts/ai_director.gd:26)).
  Narrated learning makes the invisible legible. *M · L*
- [x] **40. Signature quirks.** Roll 1–2 idiosyncrasies per fish at birth (sleeps in
  the left corner, hates the filter outflow, barrel-rolls after eating, shadows
  one tankmate); persist them. Quirks are what make a fish *memorable*. *M · L*
  — `FishMind.seed_quirks()` + persisted `quirks` array.
- **41. Make the 5 traits matter more visibly.** Audit that traits produce
  *distinct individuals*: a glutton genuinely shoves to the front at feeding
  (note: `gluttony` is barely wired today), a shy one truly lurks at the back,
  the bold one pioneers new regions first. Legibility, not new traits. *M · M*
- **42. Emergent role labels.** Detect stable behavior patterns and surface a
  discovered role in the inspect panel — The Pioneer, The Bully, The Wallflower,
  The Homebody, The Socialite — *derived* from logged behavior, not assigned. The
  player learns who each fish *became*. *M · M*
- **43. Life-stage development.** Personality shifts gently across stages: bold,
  curious fry → settled, territorial adult → mellow elder. A real arc seeded by
  traits and moved by age + experience (today only the trauma scar moves traits).
  *L · M*
- **44. The grumpy elder.** Old fish behave distinctly — slower, hard to startle
  (seen it all), claim prime spots, tolerated by others. Surviving to old age
  *earns* visible character. Ties to age senescence + `lead_score`. *M · M*
- **45. Persisted friendships & rivalries.** `bonds` is saved but mostly unused.
  Populate it from co-schooling time + repeated proximity; surface as visible
  pairs that swim together and individuals that avoid each other, across
  sessions. Named relationships. *M · L*
- **46. Sticky reputation & hierarchy.** `lead_score` / rank resets each session.
  Persist it so an established alpha keeps status and a bullied fish keeps its
  caution — the social order becomes a continuous story, not a nightly reroll.
  *S · M*
- **47. The body shows the life lived.** Scarred/timid fish slowly dull or gain
  visible scar marks; bold, well-fed fish grow more vivid and larger (via
  `_growth_variance`). Personality written on the body over a lifetime. *M · M*
- **48. Main-character weighting.** A named/favorited fish gets a slightly richer
  behavior budget — more frequent quirks, more chronicle lines, mourned harder
  (mourning already weights favorites in
  [sim_driver.gd](../shaders-godot/godot-project/scripts/sim_driver.gd)). Attention
  amplifies individuality where the player is looking. *S · M*
- **49. Personality in *how they deliberate*.** Feed traits into the new
  arbitration layer (#10–12): a bold fish commits fast with little hesitation; a
  timid one dithers and often retreats; a curious one approaches novelty the
  bold-but-incurious one ignores. Personality becomes visible in the *decision
  itself*. *M · L*
- **50. The fish's "voice" (the big swing).** Tasteful, sparing first-person
  micro-thoughts derived from state + personality — "...is that food? ...no.
  ...wait—" — on inspect or as rare ambient flavor. Template-driven offline,
  LLM-flavored online. Opt-in. The literal "you can see it thinking." *L · L*

---

## If Cursor only does five

These five, in order, get you most of the way to "this fish has a mind":

1. **#10** — approach–avoidance deliberation (the headline "it's thinking" read).
2. **#1** — a real vision cone (makes *noticing* meaningful; foundation for attention).
3. **#38** — LLM one-line bios per fish (cheapest attachment win; then #39 witness).
4. **#27** — named emotional states with distinct motion (feelings you can read).
5. **#40** — signature quirks (instant, memorable individuality).

> **Sequencing note:** #26 (two-axis affect) underpins all of Section C, and the
> arbitration layer (#10–12) underpins #49 and much of the "thinking" read — do
> those substrates early and the rest get cheaper.
