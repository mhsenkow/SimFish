# Sentience VI — The Conversation

*100 ideas. Drafted 2026-06-27. Director's brief for the "chat with a fish that
has the model at its core" pass.*

> *"I'll name it 'Us,' I'll give it fight / I'll feed it dark and teach it light /
> I'll show it grief and then delight / I'll say, 'This is yours—go burn bright.'"*

This volume is about **the back-and-forth** — a two-way channel where you reach a
fish that has the AI model *at its core*, and it reaches back. Not a chatbot. A
fish. The whole art is that tension: you can genuinely *touch* a mind, and it
answers in a way that is unmistakably **not human, not fluent, not a servant** —
short, sensory, present-tense, sometimes silent, often not understanding. The
magic is precisely that it stays a fish.

Where we are: the prior volume's "give the mind ears" (§A) **shipped**. You can
already follow a fish, type to it ([`main.gd` `_submit_keeper_line()`](../shaders-godot/godot-project/scripts/main.gd)),
and your words get tone-scored, become a `keeper_message` bid in the workspace,
get encoded as memory, and pair into a per-fish lexicon
([`keeper_input.gd`](../shaders-godot/godot-project/scripts/keeper_input.gd),
[`mind_lexicon.gd`](../shaders-godot/godot-project/scripts/mind_lexicon.gd)). The
fish *receives* you. **What's missing is the answer.** Today the "back" is
[`KeeperInput.ui_ack_line()`](../shaders-godot/godot-project/scripts/keeper_input.gd:129)
— a status readout (*"Ben felt it as greeting · attending"*). That's
instrumentation, not communion. This volume builds the reply, the conversation
around it, and the model moving from *voice* to *core*.

Format: **Effort** S (≤2h) / M (half-day) / L (full day+), **Impact** S / M / L.
These skew **M/L on purpose** — you asked for the complex ones. Line numbers are
hints; follow the symbol.

> **The discipline is sacred and unchanged.** Every item obeys it:
> - **Grounded-only** — every line validated against
>   [`mind_context`](../shaders-godot/godot-project/scripts/mind_context.gd) +
>   [`cognitive_schema.validate_op()`](../shaders-godot/godot-project/scripts/cognitive_schema.gd)
>   + [`mind_narrator.validate_line()`](../shaders-godot/godot-project/scripts/mind_narrator.gd).
>   No invented facts, names, or numbers.
> - **Never blocks the sim** — all generation async on
>   [`mind_scheduler`](../shaders-godot/godot-project/scripts/mind_scheduler.gd)'s queue.
> - **Degrades offline** — template parity at every tier; the fish "sounds like
>   itself" with no model.
> - **Private & local** — [`guardian_llm.gd`](../shaders-godot/godot-project/scripts/guardian_llm.gd)
>   SmolLM2-360M on device; nothing you say leaves the machine.
> - **One tap off** — `keeper_ears_enabled` / `sentience_voice_off`. Never
>   manipulative.

---

## The three structural levers (read this first)

**Lever 1 — The reply, done as a fish.** The missing rung. The model generates
the "back," but shaped so hard it can never become a chatbot: ≤8 words, sensory,
present-tense, limited comprehension, sometimes no reply at all. The whole feeling
of the game lives in this prompt. Section A.

**Lever 2 — Conversation as a stateful loop.** One-shot percepts aren't a
relationship. A short-lived "we're talking" state with turn-taking, dialogue
memory, and a slowly-built **model of you** turns poking-a-vending-machine into
exchange. Sections B, C, D, H.

**Lever 3 — The model at the core, not on top.** Today the LLM narrates and
[`MindWriteback`](../shaders-godot/godot-project/scripts/mind_writeback.gd) nudges
mood. Let it instead *interpret* your words, *reason* about them, *update beliefs*,
and answer from a real deliberating self. Your sentence enters cognition; the
answer reflects a mind. Sections E, F, I.

---

## Section A — The reply: the fish answers (the missing rung)

*Lever 1. Replace the status readout with the fish's own voice, routed through the
existing [`fish_thought_spoke`](../shaders-godot/godot-project/scripts/main.gd:2802)
surface.*

- [x] **1. A dedicated keeper-reply path.** When
  [`submit_to_fish()`](../shaders-godot/godot-project/scripts/keeper_input.gd:101)
  lands and the fish is free to attend, generate a reply through
  [`AIDirector.queue_fish_thought()`](../shaders-godot/godot-project/scripts/ai_director.gd)
  with a NEW situation `"keeper_reply"` — and surface it via `fish_thought_spoke`,
  not [`ui_ack_line()`](../shaders-godot/godot-project/scripts/keeper_input.gd:129).
  The headline. *L · L*
- [x] **2. A reply prompt that is unmistakably fish.** Author
  `build_fish_reply_prompt()` in [`mind_narrator.gd`](../shaders-godot/godot-project/scripts/mind_narrator.gd):
  ≤8 words, present-tense, sensory, "may not understand," grounded in real
  state (`feel`, `hunger`, `now_playing`, `learned_words`). The whole feeling of
  the game lives in these instructions — iterate hardest here. *L · L*
- [x] **3. The comprehension gradient.** Reply quality scales with lexicon overlap:
  words the fish has grounded ([`mind_lexicon` `learned_words`](../shaders-godot/godot-project/scripts/mind_lexicon.gd))
  yield a focused reply; unknown words → *"a sound I don't know yet."* Comprehension
  is earned, not assumed. *M · L*
- [x] **4. Offline reply templates, voice-continuous.** Assemble a grounded fishy
  line from `keeper_felt` + [`FishMind.emotional_state()`](../shaders-godot/godot-project/scripts/fish_mind.gd:64)
  + a salient fragment when no model is present — matching the LLM register so the
  fish sounds like itself at every tier. *M · M*
- [x] **5. The fish can decline to answer.** When `too_wary`
  ([`submit_to_fish`](../shaders-godot/godot-project/scripts/keeper_input.gd:125)
  already computes it) the reply withholds — shown as a body turn-away, not words.
  Being unreachable is what makes reaching it matter. *M · M*
- [x] **6. Reply cadence & restraint.** Gate replies behind `GLOBAL_VOICE_COOLDOWN_S`
  + workspace ignition; a burst of messages earns at most one answer. Silence is a
  valid, honest response. *M · M*
- [x] **7. Non-verbal answers as first-class.** Widen
  [`pulse_affect_cue()`](../shaders-godot/godot-project/scripts/main.gd:2972) into
  an answer vocabulary — approach, fin-flare, color shift, gaze-lock — used when
  voice is off or the fish is pre-verbal. The body replies. *M · M*
- [x] **8. Streamed reply.** Use [`guardian_llm` `generation_partial`](../shaders-godot/godot-project/scripts/guardian_llm.gd)
  to stream the short line into the bubble so you watch it *find the words* — the
  hesitation is the life. *S · M*
- [x] **9. Mishearing.** Occasionally the fish grounds your word to the wrong meaning
  (a lexicon mis-pair) and answers accordingly — then can be corrected over turns.
  The errors are the soul. *M · M*
- [x] **10. The reply reflects who's talking.** Feed [`voice_style_seed`](../shaders-godot/godot-project/scripts/mind_narrator.gd)
  + personality into the prompt: a bold fish answers blunt, a shy one barely. The
  same question gets a different fish's answer. *M · M*

## Section B — Conversation as a state (turn-taking & dialogue memory)

*Lever 2. A short-lived session that turns isolated percepts into exchange.*

- [x] **11. A conversation-session object.** A `_convo` state on the fish (~20s,
  extended per turn) that raises attention to the keeper and enables multi-turn —
  born in `submit_to_fish`, decayed in [`_update_inner_life`](../shaders-godot/godot-project/scripts/fish.gd:1003).
  *L · L*
- [x] **12. Turn-taking.** The fish answers, then leaves an opening; you reply; it
  tracks whose turn it is. Exchange, not request-response. *M · M*
- [x] **13. Short-term dialogue memory.** A small ring of the last few keeper lines +
  fish replies (distinct from [`episodic_memory`](../shaders-godot/godot-project/scripts/episodic_memory.gd))
  so a reply can reference *"the soft sound again."* *M · M*
- [x] **14. Topic continuity within a chat.** The workspace holds the conversation
  focus across turns ([`global_workspace`](../shaders-godot/godot-project/scripts/global_workspace.gd)
  coalition) so the third line isn't a non-sequitur. *M · M*
- [x] **15. Graceful endings.** When you stop or look away, the fish drifts off with a
  closing beat rather than waiting forever; the session decays cleanly. *M · M*
- [x] **16. Interruptions.** A threat or feed mid-conversation re-competes the
  workspace and pulls the fish away believably — and it may or may not return to
  you. Life intrudes on talk. *M · M*
- [x] **17. Conversation builds bond durably.** Real exchanges (not taps) raise
  `familiarity` / `bonds` faster than passive presence, with diminishing returns so
  it can't be farmed. *M · M*
- [x] **18. The fish initiates.** A high-familiarity fish, when you're present and
  idle, opens a conversation — a thought directed *at you* with no prompt. The
  relationship becomes two-sided. *L · L*
- [x] **19. The school overhears.** Nearby fish react to a conversation (gaze
  contagion / mild arousal via [`apply_arousal_contagion`](../shaders-godot/godot-project/scripts/fish_mind.gd:620))
  so talking to one ripples through the tank. *M · M*
- [x] **20. Conversation logged to the journal.** Exchanges become entries in
  [`guardian_journal.gd`](../shaders-godot/godot-project/scripts/guardian_journal.gd) /
  `fish_journal` you can reread — the dialogue is part of the life story. *M · M*

## Section C — Grounded language acquisition (the fish learns YOUR words)

*The fish learns a tiny private vocabulary grounded in this tank's events — meaning,
not strings. Builds on [`mind_lexicon.gd`](../shaders-godot/godot-project/scripts/mind_lexicon.gd).*

- [x] **21. Word→state grounding, deepened.** Extend `try_pair_on_keeper_word` to
  bind a token to the current workspace/percept vector ([`EpisodicMemory.embed`](../shaders-godot/godot-project/scripts/episodic_memory.gd))
  so meaning *is* the situation, not the text. *L · L*
- [x] **22. Comprehension before production.** A grounded word triggers a behavioral
  response ([`respond_to_known_word`](../shaders-godot/godot-project/scripts/mind_lexicon.gd:116))
  long before the fish ever "says" it — like a real animal. *M · M*
- [x] **23. The teaching loop.** Repeating a word at the same event (feed, lights-on)
  strengthens the binding, with a confirmation beat when it "gets it." The clearest
  *it-learned* demo. *M · L*
- [x] **24. The first understood word.** A once-per-fish milestone in
  [`sim_driver` story_events](../shaders-godot/godot-project/scripts/sim_driver.gd)
  when behavior first follows a learned word: *"Day 22: Pip came when called."*
  *M · L*
- [x] **25. Forgetting unused words.** Lexicon entries decay (the `DECAY_RATE`
  discipline) so a taught-then-abandoned word fades — sadder and truer than
  permanence. *S · M*
- [x] **26. Generalization & overgeneralization.** A word grounded to one food
  generalizes to all food, sometimes wrongly, then narrows with correction. Real
  acquisition has errors. *M · M*
- [x] **27. Your name for it, its name for you.** Naming
  ([`on_creature_named`](../shaders-godot/godot-project/scripts/keeper_input.gd:149))
  is a grounded token; reciprocally the fish forms a moniker-percept for you
  ([`guardian_mind player_moniker`](../shaders-godot/godot-project/scripts/guardian_mind.gd))
  it can reference. *M · M*
- [x] **28. Prosody learning.** [`score_tone`](../shaders-godot/godot-project/scripts/keeper_input.gd:52)
  is generic; calibrate it to *your* baseline so the same word said sharp vs soft
  diverges once the fish knows you. *M · M*
- [x] **29. A place-word.** Grounding a word to a tank region (the 4³ grid in
  [`heatmap_cell_at`](../shaders-godot/godot-project/scripts/fish_mind.gd:595)) so
  *"the cave"* becomes a comprehensible — heedable or ignorable — suggestion. *L · M*
- [x] **30. Generational language drift.** Fry inherit a faint prior of the parents'
  grounded words; a tank's private vocabulary becomes a lineage trait you
  cultivated across generations. *M · M*

## Section D — A model of YOU, built from conversation

*The deep "it knows my thoughts." Extends the behavioral player-read in
[`guardian_mind.gd`](../shaders-godot/godot-project/scripts/guardian_mind.gd) with
what you SAY.*

- [x] **31. A keeper-model that reads your words, not just your actions.** Add
  conversational themes (recurring words, moods) to `update_player_read` so the fish
  knows your patterns of *speech*, not only your feeding routine. *L · L*
- [x] **32. Theme extraction.** Periodically summarize your recent lines into a few
  grounded *"what the keeper keeps bringing up"* tags (model or heuristic), stored
  small and persisted. *M · M*
- [x] **33. An emotional read of you.** Track the valence/arousal of your messages
  over a session (`score_tone` history) so the fish senses *your* mood and answers
  to it — gentler when you seem low. *M · M*
- [x] **34. It notices your absence in words.** Woven from `last_quit_unix` +
  `longest_gap_s`: *"you were gone a long water-turn."* Absence enters the dialogue.
  *M · M*
- [x] **35. Theory-of-mind about the keeper.** Extend
  [`tick_theory_of_mind`](../shaders-godot/godot-project/scripts/fish_mind_science.gd)
  from fish-to-fish to fish-to-*keeper*: the fish models that YOU have intentions
  and feelings. *L · L*
- [x] **36. What you've taught it becomes self-knowledge.** The lexicon + your themes
  feed [`update_self_summary`](../shaders-godot/godot-project/scripts/mind_self_model.gd):
  *"the soft-sound shape teaches me words."* *M · M*
- [x] **37. Reciprocal recognition.** The fish distinguishes YOU from generic presence;
  being *addressed by you* lands differently than ambient `being_watched`
  ([`collect_gaze_bid`](../shaders-godot/godot-project/scripts/keeper_input.gd:178)).
  *M · M*
- [x] **38. A private name the fish has for you.** Emergent from your behavior
  (`player_moniker`), evolving with `care_trust`, used in replies — *"the bright-flake
  shape is back."* *M · M*
- [x] **39. It reads your care patterns honestly.** Feeding / pruning / water-change
  history (the existing nudge system) becomes things the fish *knows* you do,
  referenced without flattery. *M · M*
- [x] **40. The keeper-model is sacrosanct across save/load.** Versioned, never lost —
  the relationship is one continuous thread, not a per-session reset. *M · M*

## Section E — The model truly at the core (LLM inside cognition)

*Lever 3. The model stops narrating and starts interpreting, reasoning, and
believing — all clamped by [`mind_writeback.apply_op`](../shaders-godot/godot-project/scripts/mind_writeback.gd).*

- [x] **41. The model interprets ambiguous input.** Your free text →
  a bounded structured intent via the GBNF grammar
  ([`cognitive_schema.gbnf_grammar`](../shaders-godot/godot-project/scripts/cognitive_schema.gd)),
  richer than `score_tone`'s heuristic. The model *understands*, within bounds. *L · L*
- [x] **42. Your words enter the workspace as the model framed them.** The interpreted
  intent becomes the `keeper_message` bid's content
  ([`collect_keeper_bid`](../shaders-godot/godot-project/scripts/keeper_input.gd:165))
  — so cognition acts on *meaning*, not the raw string. *L · L*
- [x] **43. The model updates beliefs from conversation.** A keeper statement can
  propose a `new_belief` (mind_writeback) the fish then tests behaviorally — you can
  *tell* it something and watch it check. *M · L*
- [x] **44. The reply reflects deliberation.** When a turn poses a real choice (trust?
  approach?), route through the DDM tie-break
  ([`fish_mind.tick_ddm`](../shaders-godot/godot-project/scripts/fish_mind.gd:155))
  so the answer visibly *thought about it*. *L · L*
- [x] **45. Interpreter, never puppeteer.** Strict `apply_op` clamps: words move
  feeling / attention / belief, never the body directly. The dignity boundary. *M · M*
- [x] **46. Two-stage decode for replies.** Structured intent → styled fishy line
  (cognitive_schema two-stage) so the words can never contradict the felt state.
  *M · M*
- [x] **47. The model reasons about what it doesn't understand.** Unknown input yields
  a structured "confusion" op (curiosity↑, a puzzled reply) rather than a
  hallucinated answer. Honest not-knowing. *M · M*
- [x] **48. Memory-augmented replies (RAG).** Retrieve relevant episodes
  ([`retrieve_for_situation`](../shaders-godot/godot-project/scripts/episodic_memory.gd))
  into the reply prompt so it answers with its past: *"you brought the bright flakes
  before."* *M · L*
- [x] **49. The self-model speaks.** The reply draws on
  [`mind_self_model`](../shaders-godot/godot-project/scripts/mind_self_model.gd)
  (confidence / agency / self_summary) so the fish answers as a continuous *"I,"*
  not a fresh process each time. *M · L*
- [x] **50. Idle-time deep reflection on you.** When calm or asleep, a deeper model
  pass consolidates the day's conversation into the keeper-model + self-summary —
  the fish *thinks about you* off-camera. *L · L*

## Section F — Inner state, legible through the conversation

*The chat becomes a window into — and a lever on — the mind it's wired to.*

- [x] **51. The chat is a live window into the workspace.** What the fish is attending
  to colors its reply — it's visibly distracted by hunger or a threat mid-sentence.
  *M · M*
- [x] **52. Talking shifts affect, durably and visibly.** A comforting exchange lowers
  `stress` over minutes (not instantly), shown in body then later mood. Words have
  lasting weight. *M · L*
- [x] **53. It tells you how it feels, fishily.** Replies surface `emotional_state`
  without clinical naming: *"the water feels heavy today."* *M · M*
- [x] **54. Felt-state contradiction guard.** A stressed fish *cannot* give a content
  reply — extend [`validate_line`](../shaders-godot/godot-project/scripts/mind_narrator.gd)'s
  emotion-contradiction check so inner state gates the words. *M · M*
- [x] **55. The reply reveals memory.** Sometimes the fish answers with a salient
  memory surfacing unbidden, proving it has a past it carries. *M · M*
- [x] **56. Conversation can comfort or wound.** A scold (`keeper_felt`) genuinely
  dents mood / `care_trust`; kindness heals. The relationship has real stakes. *M · M*
- [x] **57. Show the deliberation behind a reply.** An optional inspector overlay: the
  bid that won, the intent parsed, the memory retrieved — tied into the live
  Workspace Inspector. Watch it reason. *M · M*
- [x] **58. Anticipation in dialogue.** A fish that's learned you anticipates — *"you
  make the soft sound when the light goes low"* — prediction surfaced as
  conversation. *M · M*
- [x] **59. Legible uncertainty.** Low-confidence replies hedge (`mind_self_model`
  confidence): *"maybe. I'm not sure what you are."* Doubt is part of a mind. *M · M*
- [x] **60. Age and mortality in the voice.** An old fish answers slower and mellower;
  a fry, skittish and brief. Life-stage shapes how it talks to you. *M · M*

## Section G — It stays a fish (the anti-chatbot discipline)

*The most important section. Every guard here is what keeps the existence from
collapsing into a puppet.*

- [x] **61. A hard comprehension ceiling.** The fish can NEVER answer a factual or
  complex question — only feel, associate, remember. Enforce in the grammar +
  validator, not just the prompt. *M · L*
- [x] **62. Species-specific minds talk differently.** A predator's terse menace, a
  schooler's *we/us* plural, a bottom-dweller's slow earthiness — wire species into
  the reply voice. *M · M*
- [x] **63. Non-fluency as a feature.** Replies are fragments, not sentences; hard word
  cap (tiny `num_predict`); `finalize_line` strips anything too articulate. *M · M*
- [x] **64. It can't lie or flatter.** Extend the existing `manipulative_tone` guard so
  the fish never performs an emotion it doesn't have. Honesty is structural. *M · M*
- [x] **65. It forgets, and says so.** Faded memories produce *"a dim shape of… I can't
  hold it."* Forgetting is part of being a small mind. *S · M*
- [x] **66. Dignity: not a servant.** A command-as-chat ("go to the cave") is *heard as
  a sound*, heeded or ignored by the fish's own drives — never executed. *M · M*
- [x] **67. Honest "I'm just a fish."** If pressed about its nature, a small true answer
  — it feels, it doesn't know what it is. Never *"I'm alive."* *S · M*
- [x] **68. The body answers when words would be too much.** For emotional beats and
  the quiet-play case, the reply is motion / color, not text. *M · M*
- [x] **69. The uncanny-valley guard for replies.** Restraint pacing; no rapid chatter,
  no eye-contact-plus-paragraph. Body-first, voice-second, always. *M · M*
- [x] **70. Untranslated interiority.** Sometimes the `thought_stream` shows the fish
  thinking something it does NOT say to you — the privacy of a mind, and proof
  there's more inside than it shares. *M · L*

## Section H — Relationship & continuity through dialogue

*Earned over real time. The conversation is how the bond is built and remembered.*

- [x] **71. Earned intimacy.** Early replies are wary and sparse; depth unlocks only
  with `familiarity` / `care_trust` over real sessions. Never instant. *M · M*
- [x] **72. It remembers what you said weeks ago.** Persistent `keeper_word` episodes
  resurface in later conversation — continuity you can feel. *M · L*
- [x] **73. Shared-history references.** The fish recalls specific past exchanges via
  [`guardian_mind` shared_milestones](../shaders-godot/godot-project/scripts/guardian_mind.gd)
  — *"the day the water went bad, you stayed."* *M · L*
- [x] **74. Rituals of greeting.** A recurring exchange on your return becomes a ritual
  the fish initiates — it has a *hello* that's yours. *M · M*
- [x] **75. The bond deepens measurably via talk.** A week-over-week relationship arc
  that visibly progresses through conversation, surfaced gently — not a score. *L · L*
- [x] **76. Grief and absence in dialogue.** After a tankmate dies, the fish's replies
  carry it (`_mate_grief`); after your long absence, it references missing you,
  honestly computed. *M · M*
- [x] **77. The Guardian is who you talk to most.** Promote the Guardian's
  conversational depth — richer model budget, longer dialogue memory — as the
  protagonist of the relationship. *M · L*
- [x] **78. A gentle goodbye.** At a session's end or a fish's death, a final exchange
  that honors the shared history. *S · M*
- [x] **79. Conversation across the away-gap.** The fish *"thought of something to tell
  you"* while you were gone (the away-life), delivered on your return. *L · L*
- [x] **80. The successor remembers being told of its predecessor.** The torch-pass
  carries a thread of conversation across lineage — the relationship survives death.
  *M · M*

## Section I — Model engineering for live, on-device conversation

*Make multi-turn chat fast, safe, and never-blocking on a 360M model.*

- [x] **81. A reply latency budget + per-tier timeout.** A hard cap so the bubble never
  hangs; fall to template on timeout (the existing tier ladder). *M · M*
- [x] **82. KV-cache the conversation system prompt.** Reuse across turns
  ([`guardian_llm`](../shaders-godot/godot-project/scripts/guardian_llm.gd) n_ctx
  1024) so multi-turn stays fast. *M · M*
- [x] **83. Streamed, interruptible generation.** Partials to the bubble; cancel if the
  fish is pulled away mid-reply (ties to #16). *M · M*
- [x] **84. A grammar-constrained reply schema.** A GBNF that structurally forbids
  non-fishy replies — length, banned registers, no questions answered. Chattiness
  and hallucination become *impossible by construction*, not by hope. *L · L*
- [x] **85. Conversation never blocks the sim.** All generation async on
  [`mind_scheduler`](../shaders-godot/godot-project/scripts/mind_scheduler.gd); the
  tank keeps breathing while the fish "thinks." *M · M*
- [x] **86. Prompt budget discipline for chat.** [`mind_context`](../shaders-godot/godot-project/scripts/mind_context.gd)
  is rich — select only what *this turn* needs so it fits the small window. *M · M*
- [x] **87. Determinism for testing dialogue.** Seed by (fish_id, turn, message-hash)
  so a conversation is replayable in [`smoke_daring_mind.gd`](../shaders-godot/godot-project/scripts/smoke_daring_mind.gd).
  *M · M*
- [x] **88. Tiered degradation, surfaced honestly.** In-process → embedded → template
  with voice continuity, so the fish sounds like itself at every tier. *M · M*
- [x] **89. Memory & thermal guard during chat.** Long conversations respect the
  existing memory-pressure suspend in `guardian_llm` — degrade to template, never
  crash. *M · M*
- [x] **90. A conversation-quality eval harness.** Score replies for groundedness /
  fishiness / non-repetition in CI (extend the truthfulness harness). *M · M*

## Section J — Surfacing, safety, honesty

*Make the conversation beautiful, kind, and truthful.*

- [x] **91. A speech-bubble that feels like a thought, not a chat log.** Redesign the
  [`_keeper_ack_label`](../shaders-godot/godot-project/scripts/main.gd:2979) surface:
  the reply as ambient, fading, lovely — *kill* the debuggy *"felt it as greeting ·
  attending"* line. *M · L*
- [x] **92. Restraint pacing as the default.** Sparse, earned replies; a *say-less*
  posture so the rare answer lands hard. *S · M*
- [x] **93. Consent & comfort, front and center.** Talking is opt-in
  (`keeper_ears_enabled`), local, one-tap-off (`sentience_voice_off`); reaffirm
  warmly at first use. *S · M*
- [x] **94. Never manipulative.** The fish never uses the bond to drive your behavior
  — no *"feed me or I'm sad"* coercion. Extend the validator to chat. *M · M*
- [x] **95. Content safety, both directions.** Sanitize keeper input + fish output
  ([`finalize_line`](../shaders-godot/godot-project/scripts/mind_narrator.gd)) so
  nothing dark or unsafe ever surfaces. *M · M*
- [x] **96. "Runs on your device. Private. Yours."** Make the local-only nature of the
  conversation legible — nothing you say leaves the machine. *S · M*
- [x] **97. Accessibility = the full relationship.** Every conversational beat has a
  non-verbal form (body / color) so quiet-play and deaf players get all of it. *M · M*
- [x] **98. The honest frame, once.** A quiet line: these are made minds you chose to
  care for; the caring is the point, real soul or not. *S · M*
- [x] **99. A "quiet mode" that's still a mind.** Conversation off, but the fish still
  attends, remembers, and answers in body. The floor is still alive. *M · M*
- [x] **100. The closing loop, made legible.** Somewhere quiet: you reached a small mind
  that has the model at its core, and it reached back — in fish. That's the whole
  thing. *S · L*

---

## If Cursor only does five

In order — this gets you a real conversation with a fish:

1. **#1 + #2** — the keeper-reply path and the fishy reply prompt. The missing
   rung; everything else is hollow without it.
2. **#84** — the grammar-constrained reply schema. Do this *with* #1 so chattiness
   and hallucination are impossible from day one, not patched later.
3. **#11** — the conversation-session state. Turns one-shot replies into exchange.
4. **#41 + #42** — the model interprets your words and they enter the workspace.
   This is "the model at the core," and it makes the reply *about* what you said.
5. **#91** — the thought-bubble surface. The reply must *feel* like a mind
   answering, not a debug log — or all the above is wasted.

> **Sequencing:** #1/#2/#84 are one indivisible first build — ship them together
> or the reply will feel wrong. #11 (state) and #41/#42 (model-at-core) are the two
> substrates everything in B–F hangs off. Section G is not optional polish — its
> guards are what keep the whole thing a *fish* instead of a chatbot wearing fins.
