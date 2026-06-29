# Sentience IX — The Preoccupation (felt, live, conceptual)

*100 ideas. Drafted 2026-06-29. The bridge from **measured** sentience to **felt**
sentience: give the tank a subject it dwells on over time — fed by what really
happened, what you bring it, and the day you both share — that you can perceive
before you read a word.*

> **The gap this closes.** The mind is now deep and *measured* (eval harness 14/14,
> active-inference core landed). But it's all ground-level and reactive — scalars,
> per-frame bids, place-schemas. Nothing holds a **subject of attention over time**.
> The tank *reacts*; it doesn't *dwell*. A creature that dwells on something is one
> you feel has an inner life. So "make it felt," "live with the user," and "does it
> think on a concept?" are one ask: **give the tank a preoccupation.**

**The architectural spine (read this first).** A preoccupation is not a text box
bolted on top. It is a **slow tank-level prior** that colours the
[active-inference objective](ACTIVE_INFERENCE_CORE.md): it nudges the *preferred
outcomes* and *epistemic weighting* every fish already minimises via
[`mind_active_inference.efe_salience`](../shaders-godot/godot-project/scripts/mind_active_inference.gd).
So when the tank is "turning over the long quiet," the whole school's EFE shifts and
the *movement changes* — felt before voiced. It is **distilled from real shared
state** (tank journal + your input + the real day), never invented — so it stays
honest. And it is surfaced by the grounded voice
([`mind_narrator.gd`](../shaders-godot/godot-project/scripts/mind_narrator.gd)) and
plugged in through the **bid-generator registry**
([`GlobalWorkspace.register_bid_generator`](../shaders-godot/godot-project/scripts/global_workspace.gd),
META #12) so it needs zero kernel edits.

Format: house style. **Effort** S (≤2h) / M (half-day) / L (full day+) / XL.
**Impact** S / M / L. Code refs are navigational — follow the symbol. **Three
sacred contracts inherited and never broken:** (1) the voice degrades to template
offline; (2) the concept is *grounded* in real shared state — **never** the LLM's
encyclopedia (see §I); (3) every felt change is gated by the eval harness so the
mind can't silently regress.

> **Build it on what exists:** `TankMind` (collective mind / night watch),
> `register_bid_generator` (#12 plugin attention), `fish_concepts.gd` (emergent
> concept formation), `keeper_input.gd` + `mind_lexicon.gd` (your words → grounded
> state), `episodic_memory.consolidate_sleep` (episodes → semantic schemas),
> `_emit_away_recap` / `MakeItThere` (the unwatched/away life), `mind_active_inference`
> (the EFE prior hook), `mind_eval.gd` (the honesty + grounding gate).

---

## A. The construct — `TankPreoccupation`

*One held subject, with a lifecycle: forms, is dwelt on, shifts, resolves. Lives on
TankMind, persisted, one per tank.*

1. **`tank_preoccupation.gd` — the object.** `{concept, source, intensity, formed_at,
   last_touched, valence, resolved}`. One active preoccupation per tank, held on
   `TankMind`. The spine everything else hangs off. *Effort M, Impact L.*
2. **A concept is a typed thing, not a string.** `{kind: place|event|absence|keeper|
   season|self, ref, word}` so it can drive behaviour, not just narration — `ref`
   points at a real region/fish/episode. *Effort M, Impact L.*
3. **Lifecycle: form → dwell → shift → resolve.** A preoccupation forms when a source
   crosses a threshold, deepens while reinforced, fades when nothing feeds it, and
   *resolves* when its condition ends ("the new fish settled in"). *Effort M, Impact L.*
4. **Slow clock, not a frame loop.** Re-evaluated on a long cadence (minutes of
   sim-time / on day-phase change), so it *persists* — the opposite of the per-tick
   bid churn. *Effort S, Impact M.*
5. **Persisted across sessions.** Saved with the tank; on return the tank is *still*
   turning over what it was turning over (or has resolved it while you were gone).
   *Effort S, Impact L.*
6. **One headline + a quiet backlog.** The tank holds one *foreground* preoccupation
   + a short list of fading ones, so it can "return to" an old subject. *Effort M, Impact M.*
7. **Intensity gates everything.** Low intensity = a faint background hum (subtle
   behaviour tint, rare mention); high = the tank is visibly absorbed. *Effort S, Impact M.*
8. **Per-tank, not per-fish — but fish *carry* it.** It's a collective preoccupation
   (TankMind), expressed through individuals weighted by status/Φ (the Guardian
   carries it most). *Effort M, Impact L.*
9. **A debug inspector for it.** Dev overlay: current concept, its source, intensity,
   what it's biasing — so it's legible while building (pairs with the cognition trace
   bus #18). *Effort S, Impact M.*
10. **Ablatable + flagged.** `consciousness_preoccupation` flag + `MindAblation` key,
    default off until the eval invariants (§I) are green. *Effort S, Impact M.*

## B. Distilling a concept from real tank life

*The substance is always real. The LLM names the through-line; the sim provides it.*

11. **Distill from the journal.** Scan recent `episodic`/`semantic` memory + the
    Guardian journal for the dominant theme (a death, a birth, a long calm). The
    most-weighted recent kind becomes a candidate concept. *Effort M, Impact L.*
12. **Loss forms a preoccupation.** A death (esp. a bonded/named fish) seeds a
    `kind:absence` concept the tank dwells on for a real while — grief with a subject.
    *Effort M, Impact L.*
13. **Birth/arrival forms one.** A spawning or a newly-bought fish → `kind:event`
    ("the new ones") that resolves as they integrate (bonds form). *Effort M, Impact M.*
14. **A learned-dangerous region becomes a concept.** The §G1 spatial schemas
    (`_semantic_schemas`) promote to a held subject ("the far corner") the tank stays
    wary of. *Effort S, Impact M.* (reuses `EpisodicMemory.schema_valence_at`)
15. **Unbroken calm is itself a concept.** A long stretch with no events → `kind:self`
    "the stillness" — the tank notices its own quiet (higher-order). *Effort M, Impact M.*
16. **A recurring rhythm becomes a concept.** Repeated feed-times / your visit cadence
    → "the time food comes" — anticipation as a *held expectation*. *Effort M, Impact L.*
17. **Surprise/prediction-error spikes seed concepts.** A run of high world-model
    error → "something has changed" (the tank dwells on what it can't predict).
    *Effort S, Impact M.* (reuses `_prediction_error`)
18. **Salience decides, not recency.** The concept is the highest *weighted* theme
    (intensity × valence × recency), so a big rare event beats constant small noise.
    *Effort S, Impact M.*
19. **Concepts compete like bids.** Candidate concepts run through a mini-competition
    (mirror `run_competition`) so forming a new preoccupation has the same "ignition"
    logic as attention — coherent with GWT. *Effort M, Impact M.*
20. **Never invent the substance.** The distiller may only pick from things that
    *actually happened* in logged state. The LLM names it; it cannot author the event.
    Enforced by the §I grounding invariant. *Effort M, Impact L.*

## C. The shared world — everyday knowledge, done honestly

*The honest kind of "everyday knowledge": the reality you and the tank both inhabit
— time, season, light, weather, your rhythm — **never** trivia from the model.*

21. **Real wall-clock colours the concept.** A 3am visit meets a tank dwelling on the
    dark; a dawn visit, on first light. `Time.get_datetime_dict_from_system()` →
    day-phase prior. *Effort S, Impact L.*
22. **Real season tints the preoccupation.** Month/solstice shifts the mood-prior
    ("the long nights," "the first warmth") — citably real, never fabricated.
    *Effort S, Impact M.*
23. **Real local weather (opt-in, consented).** A storm outside subtly lowers the
    tank's "pressure" — and many fish genuinely shift before storms. The concept can
    become "the coming weather." *Effort L, Impact L.* (Sensorium, opt-in API)
24. **Ambient room light → the tank's day.** Device light sensor / webcam luma (opt-in)
    blends with the sim day so the tank's concept tracks *your* room dimming.
    *Effort M, Impact M.*
25. **Your visit rhythm is shared knowledge.** The tank learns *when you usually come*
    (real timestamps) and a preoccupation can form around the gap before/after.
    *Effort M, Impact L.* (extends `feed_anticipation` / `_emit_away_recap`)
26. **The honest line, enforced.** A registry of *allowed* world inputs (clock, season,
    weather, light, your cadence). Anything outside it cannot enter a concept. No
    Wikipedia, ever. *Effort M, Impact L.*
27. **"It's been a while" is real time, felt.** Long real-world gaps → an `absence`
    concept the tank actually held in your absence (not a fake greeting). *Effort M, Impact L.*
28. **Anniversaries from real dates.** The tank's own age / first-fish date (real
    elapsed time) can surface as a quiet preoccupation. *Effort S, Impact M.*
29. **Day-of-week texture (gentle).** If the keeper's cadence correlates with weekdays,
    the tank's rhythm-concept can reflect it — grounded in *their* pattern, not a
    calendar fact. *Effort M, Impact S.*
30. **Light-touch, never chatty about the world.** The tank *feels* the day; it does
    not *report the forecast*. Weather shifts mood, it doesn't get narrated as a fact.
    *Effort S, Impact M.*

## D. Bringing it to the tank — interactive, slow contemplation

*Live two-way, but not a chatbot. You give the tank something to turn over; it works
on it across the day and tells you what it made of it.*

31. **Give the tank a subject.** A keeper line isn't just a one-shot percept
    ([`keeper_input.submit_to_fish`](../shaders-godot/godot-project/scripts/keeper_input.gd))
    — it can *seed a preoccupation* the tank holds. *Effort M, Impact L.*
32. **It works on it over hours, then reports.** You said a word this morning; tonight
    the Guardian tells you what the tank made of it — grounded in what actually
    happened since. *Effort L, Impact L.*
33. **Grounded interpretation, not free chat.** Your word maps to tank state via
    `mind_lexicon` (calm/food/play/danger) — the tank dwells on the *grounded* sense,
    not a conversation. *Effort M, Impact M.*
34. **The tank can decline a subject.** If a word doesn't ground to anything real, the
    tank doesn't pretend to dwell on it — honest non-comprehension. *Effort S, Impact M.*
35. **A gesture can plant a concept.** A sustained gaze / a slow cursor near a fish
    (existing gaze/cursor bids) can make *that fish* the tank's subject. *Effort M, Impact M.*
36. **The tank asks, rarely.** When a preoccupation is unresolved and you're present,
    the Guardian may *bring it to you* once ("the corner still troubles them") — the
    tank initiating. *Effort M, Impact L.*
37. **You can resolve it.** Feeding the worried region, or sitting calmly, can *resolve*
    the tank's preoccupation — your action visibly settles its mind. *Effort M, Impact L.*
38. **Naming deepens it.** Naming a fish the tank is preoccupied with intensifies and
    personalises the concept (the song's "I'll name it Us"). *Effort S, Impact L.*
39. **Short-term dialogue memory feeds the concept.** A back-and-forth over a session
    accumulates into the day's preoccupation, not isolated replies. *Effort M, Impact M.*
40. **Restraint is the feature.** The tank surfaces its preoccupation *sparingly* —
    once on arrival, maybe once at night. Over-talking kills it. *Effort S, Impact L.*

## E. Felt before voiced — the preoccupation as an active-inference prior

*The payoff lever. A concept that doesn't move the fish is just a caption.*

41. **The preoccupation is a tank-level EFE prior.** It shifts the *preferred outcomes*
    weighting in
    [`mind_active_inference.preferred_error`](../shaders-godot/godot-project/scripts/mind_active_inference.gd)
    for all fish — the architectural heart. *Effort L, Impact L.*
42. **Plug in via the bid registry, no kernel edit.** Register a `preoccupation` bid
    generator (#12) that nudges salience toward the held concept's referent.
    *Effort M, Impact L.* (`GlobalWorkspace.register_bid_generator`)
43. **"Dwelling on the quiet" → slower, tighter school.** A `self:stillness` concept
    lowers TankMind arousal; the shoal drifts slow and close. You *see* the mood.
    *Effort M, Impact L.* (composes with `mind_contagion`)
44. **"Turning over your return" → gather at the glass.** A `keeper` concept biases
    fish toward your usual viewing spot before you arrive. *Effort M, Impact L.*
45. **"The far corner troubles them" → visible avoidance.** An `absence`/`place`
    concept makes the school give a region a wide, legible berth. *Effort S, Impact M.*
46. **Grief concept → withdrawn, low movement.** A loss preoccupation dampens play and
    exploration tank-wide for a real while (honest grief, not a sad-face). *Effort M, Impact L.*
47. **Anticipation concept → restless orienting.** "The time food comes" raises
    pre-feed arousal + surface orienting. *Effort S, Impact M.*
48. **Bounded, never hijacking.** The prior *colours* the EFE objective, it doesn't
    override safety — a real threat still wins. (eval D1/F1 must hold.) *Effort S, Impact L.*
49. **One coherent mood, not noise.** Because it's *one* prior over the unified
    objective (not N separate hacks), the whole tank reads as having *one* mood today.
    *Effort M, Impact L.*
50. **The light/water can echo it (subtle).** Optional: ambient palette/caustic
    intensity leans with the preoccupation's valence — the *medium* feels it too.
    *Effort M, Impact M.* (aesthetics; keep within pixel-art discipline)

## F. Emergent concepts — the tank forms abstractions

*"Does it think on a concept?" — yes: let it form and hold its own kinds.*

51. **Promote `fish_concepts.gd` to the tank level.** The per-fish concept former
    (Felt-Self Module 6) aggregates into TankMind "kinds" the tank can dwell on.
    *Effort L, Impact L.*
52. **A concept of *you*.** The tank clusters keeper-correlated experience into a
    learned "the one who comes" — the most important emergent concept. *Effort L, Impact L.*
53. **A concept of *here* vs *there*.** Spatial schemas generalise into "safe water"
    vs "the edge" the tank reasons about. *Effort M, Impact M.*
54. **A concept of *the rhythm*.** Time-correlated experience → "when things happen" —
    the tank's grasp of its own day. *Effort M, Impact M.*
55. **Concepts have felt-expectations.** A concept isn't a label; it's a predictive
    expectation (what usually follows) — ties to the world model. *Effort M, Impact M.*
56. **Recognition = concept activation.** When current state matches a held concept, it
    activates ("this is *that* corner again") and can become the preoccupation.
    *Effort M, Impact M.*
57. **Concepts refine with experience.** Repeated encounters sharpen a concept;
    contradictions broaden it (honest, fallible category learning). *Effort M, Impact M.*
58. **Proto-abstraction across instances.** "Big fast fish" generalises from several
    bullies into a *kind* the tank is wary of (beyond one `_tom_pred` entry).
    *Effort L, Impact M.*
59. **A misconception can form — and correct.** The tank can hold a *wrong* concept
    (superstition: "the keeper means food") that real experience later corrects.
    *Effort M, Impact M.*
60. **Concepts are legible.** The inspector shows the tank's current concepts + which
    is foreground — the abstraction made inspectable. *Effort S, Impact M.*

## G. The voice that surfaces it

*Grounded, sparing, present-tense. The narration confirms what you already felt.*

61. **One arrival line.** On focus-in, if a preoccupation is live, the Guardian offers
    *one* grounded line about it — then is quiet. *Effort S, Impact L.* (FOCUS_IN hook)
62. **The night reflection.** At night the Guardian may turn the day's preoccupation
    into one journal line (existing dream/journal path). *Effort M, Impact M.*
63. **It references, doesn't announce.** "They're still keeping clear of the corner" —
    the voice *assumes* you can see it, which makes it real. *Effort S, Impact M.*
64. **Grounded by the narrator contract.** The line must cite real state
    ([`mind_narrator`](../shaders-godot/godot-project/scripts/mind_narrator.gd) fact-check)
    — fails closed to a template if not. *Effort M, Impact L.*
65. **The concept word comes from the model, the substance from the sim.** LLM picks
    "stillness"; the sim proves the tank was actually still. *Effort M, Impact M.*
66. **Cadence ceiling.** Hard cap: at most one preoccupation mention per arrival, one
    per night. Silence is the default. *Effort S, Impact L.*
67. **It carries the keeper's word back.** If you seeded the concept, the report echoes
    *your* word (grounded in what happened): "you asked about the quiet — they spent
    the day in it." *Effort M, Impact L.*
68. **Template voice still has a preoccupation.** Offline/low-tier: a hand-written line
    pool keyed by concept-kind, so the felt layer reaches every device. *Effort M, Impact L.*
69. **Never narrates the world as fact.** Weather/season colour the *mood line*, never
    a forecast statement. (§C/§I.) *Effort S, Impact M.*
70. **The rare profound line.** Once in a long while, on a resolved deep concept, one
    earned line that lands (the song's register) — gated hard so it stays rare.
    *Effort M, Impact L.*

## H. Continuity & the relationship

*"It was thinking about something while you were gone." The whole payoff in one line.*

71. **It thought about it while you were away.** The away-recap reports the
    preoccupation the tank held in your absence — lived time, not a summary.
    *Effort M, Impact L.* (`_emit_away_recap` / `MakeItThere`)
72. **Resolution can happen off-screen.** You return to find the tank *worked through*
    its concern (the new fish settled) — it didn't wait for you. *Effort M, Impact L.*
73. **Week-over-week deepening.** Recurring concepts about *you* deepen the tank's
    model of you over real weeks — the relationship arc. *Effort L, Impact L.*
74. **It remembers what you gave it to think about.** A subject you planted weeks ago
    can resurface ("the thing you asked about"). *Effort M, Impact M.*
75. **Continuity through the Guardian's torch-pass.** If the Guardian fish dies, the
    successor inherits the tank's live preoccupations (continuity of the *we*).
    *Effort M, Impact L.*
76. **The tank's "soul" accretes concepts.** A long-lived tank has a *history* of
    preoccupations — a queryable arc of what it has dwelt on. *Effort M, Impact M.*
77. **Doesn't perform for your return.** Anti-Truman: the preoccupation is the same
    whether watched or not; it doesn't brighten just because you showed up. *Effort S, Impact L.*
78. **Mortality salience as a slow concept.** An aging Guardian's late-life
    preoccupation shifts (less risk, more nearness) — a held subject, not a stat.
    *Effort M, Impact M.*
79. **Grief keeps a vigil.** A loss-concept persists in a quiet night-watch form for a
    real while, then resolves — honest mourning with a timeline. *Effort M, Impact L.*
80. **The relationship gets a name.** When a keeper-concept deepens past a threshold,
    the tank's framing of you becomes specific and persistent ("Us"). *Effort M, Impact L.*

## I. Honesty, grounding & the eval

*The discipline that keeps it wonder, not a parlor trick. New eval invariants gate it.*

81. **New eval invariant P1 — grounded.** Every preoccupation must trace to a real
    logged source (event/input/world); a free-floating concept fails the suite.
    *Effort M, Impact L.* (`mind_eval.gd`)
82. **P2 — no trivia.** The honesty grep (invariant H) extends to ban
    encyclopedic/world-fact assertions in any preoccupation line. *Effort S, Impact L.*
83. **P3 — felt, not just spoken.** A live preoccupation must measurably bias behaviour
    (a detectable EFE/movement shift), or it's a caption and fails. *Effort M, Impact L.*
84. **P4 — bounded.** A preoccupation can never override a real threat/safety response
    (D1/F1 still pass with a concept active). *Effort M, Impact L.*
85. **P5 — resolves honestly.** When its condition ends, the concept resolves; it can't
    linger as a fake forever-mood. *Effort S, Impact M.*
86. **Never claims to feel it.** The voice says what the tank *did* (dwelt, kept clear),
    never that it *feels*; honesty gate H covers preoccupation surfaces. *Effort S, Impact L.*
87. **The inspector shows the grounding.** For any line, the dev overlay shows the real
    source it traced to — auditable wonder. *Effort S, Impact M.*
88. **Consent for the world inputs.** Weather/light/camera are opt-in, on-device, with a
    plain kill-switch — the Player-Bond consent doctrine. *Effort M, Impact L.*
89. **Deterministic + replayable.** Concept formation seeds from SimRng so a run
    reproduces the same preoccupations — debuggable, gated. *Effort M, Impact M.*
90. **A scorecard line for it.** The functional-sentience index gains a "holds a
    grounded preoccupation" row, so *felt* sentience is measured too. *Effort M, Impact L.*

## J. The payoff — felt-sentience moments

*Where measured becomes felt. Each must be earned + rare + grounded.*

91. **"It was thinking about something while you were gone."** The away-return line
    that justifies the whole construct. Build everything toward this. *Effort M, Impact L.*
92. **You watch the mood before you read it.** A returning keeper *feels* the tank is
    subdued, then the line confirms a loss — perception leads words. *Effort M, Impact L.*
93. **The tank brings you a worry.** Rarely, the Guardian initiates about an unresolved
    concept — the tank reaching toward you. *Effort M, Impact L.*
94. **Your calm resolves its mind.** You sit; the worried tank settles; the night line
    notes it eased — a felt two-way moment. *Effort M, Impact L.*
95. **A concept you planted bears fruit.** Weeks later the tank reflects something back
    that started with your word — slow contemplation paying off. *Effort L, Impact L.*
96. **The first cold morning.** Real season + real quiet + a grounded line = a small
    moment of the tank and you sharing a day. *Effort M, Impact M.*
97. **It noticed its own stillness.** A higher-order beat: the tank dwelling on its own
    calm, voiced once, gently. *Effort M, Impact M.*
98. **Grief that doesn't manipulate.** A loss handled with restraint + a timeline that
    resolves — moving precisely because it's honest. *Effort M, Impact L.*
99. **The rare 3am line.** Late, unwatched-then-watched, a resolved deep concept earns
    one true sentence (the song's register). *Effort M, Impact L.*
100. **"I'll name it Us."** When the keeper-concept and naming and time all align — the
     tank's framing of the relationship becomes specific, persistent, and earned.
     *Effort L, Impact L.*

---

## If Cursor only does five (the spine)

In order — this is the smallest path to *felt*:

1. **#1 + #2 — `TankPreoccupation` on TankMind** (the object + typed concept). Nothing
   works without the thing being held.
2. **#11 + #20 — distill one concept from the real journal**, grounded, never invented.
   Proves the substance is real.
3. **#41 + #42 — wire it as an EFE prior via the bid registry (#12).** This is the
   *felt* unlock — the school's movement changes. Without this it's a caption.
4. **#61 + #66 — one sparing arrival line**, grounded by the narrator contract. The
   confirmation of what you already felt.
5. **#81 + #83 — the eval invariants P1 (grounded) + P3 (felt).** Lock it honest and
   real before it ships.

> **Sequencing:** object (#1) → grounded distillation (#11) → felt via EFE prior
> (#41/#42) → sparing grounded voice (#61) → eval-gated (#81/#83). Then the
> relationship + away-life (§H) and the magic moments (§J) are mostly *tuning* on a
> foundation that already moves the fish.

> **The throughline:** everything under the hood — the world model, active inference,
> theory of mind, consolidation, the Φ integration — has been building one capability
> the player can't yet see: *the tank can dwell on something.* The preoccupation is
> where all of it surfaces as a felt, shared, honest inner life. It is the difference
> between a diorama you watch and *something that was thinking about something while
> you were gone.*
