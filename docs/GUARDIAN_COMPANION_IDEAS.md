# The Guardian — Embedded-AI Companion & the Living Story

*Drafted 2026-06-26. Pillar 10: Presence & Ritual — the embedded-model construct.*

The construct: **one fish becomes a mildly-sentient companion** with an **ongoing,
persistent story**, driven by an **AI model embedded in the app itself** (no Ollama
required), and the story is woven from your **presence and rituals** — your comings,
goings, routines, and the life of the tank. It's the emotional spine that makes you
*return*: not a feature, a relationship.

Format: **Effort** S/M/L · **Impact** S/M/L; checkbox-tracked; real symbols cited.

> **The Guardian already exists — this elevates it.** Cursor built the protagonist
> scaffolding; don't rebuild it:
> - **`guardian_fish.gd`** — a single chosen fish (`is_guardian`), with
>   `offline_guardian_bio()`, `guardian_thought()`, and `arc_chapter_line(fish,
>   sim, chapter, situation)` (4 chapters × situations: arrival / feed_nudge /
>   autofeed / water_stress / morning / **successor** / **lost**).
> - **`sim_driver.gd`** — `_ensure_guardian()` (primary-favorite → boldest named →
>   first alive), `_tick_guardian()` → `evaluate_tick()` → emits
>   `guardian_spoke(text, speaker, action)`. `_guardian_arc` + `_guardian_id`
>   **persisted** (save v5).
> - **AIDirector** ([ai_director.gd](../shaders-godot/godot-project/scripts/ai_director.gd))
>   — Ollama at a **configurable** `ai_endpoint` ([:50](../shaders-godot/godot-project/scripts/ai_director.gd:50))
>   hitting `/api/generate`; `queue_fish_bio()`→`fish_bio_ready`, `note_event()`→
>   batched `chronicle_line`, fail-soft offline. `character_bio` per fish, persisted.
> - **Presence hooks** — `NOTIFICATION_APPLICATION_FOCUS_IN/OUT`
>   ([main.gd ~7170](../shaders-godot/godot-project/scripts/main.gd:7170)),
>   `last_quit_unix` + `_emit_away_recap()` ([sim_driver ~5049](../shaders-godot/godot-project/scripts/sim_driver.gd:5049)),
>   `_feed_time_history` + `feed_anticipation_active()`
>   ([sim_driver ~118](../shaders-godot/godot-project/scripts/sim_driver.gd:118)),
>   `update_player_glance()`.
> - **Story** — tank-wide `story_events` (200) + `log_story_event()`; the story
>   popup ([main.gd ~5335](../shaders-godot/godot-project/scripts/main.gd:5335)).
>
> **What's missing (= this doc):** the model is **Ollama-only** (no embedded
> model); the Guardian's voice is **procedural templates**, not generative; there's
> **no ongoing per-fish journal** (only a tank-wide log + a static one-line bio);
> and presence/ritual is *detected* but not yet *narrated by the Guardian*.

---

## The three structural levers

**Lever 1 — Embed the model with (almost) zero rewrite.** The AIDirector endpoint
is configurable and speaks `/api/generate`. Wrap a small bundled model in a local
server exposing that same endpoint, point `ai_endpoint` at `localhost:PORT`, and the
existing bio/chronicle/mood plumbing *just works* — offline, free, private. (#1–9)

**Lever 2 — Give the Guardian a mind, not a script.** Today it picks from template
lines. Give it a persistent inner-state (what it remembers about you, wants, feels,
believes) that the model reads and updates — *mild sentience*, continuous across
sessions. (#10–27)

**Lever 3 — Make the relationship the story.** Weave the existing presence hooks
(arrival, absence, your routine) into an ongoing, chaptered **journal** the Guardian
authors in its own voice — so coming back means finding out what *it* has to say.
(#28–50)

> **Size budget (from [PLAYER_BOND_IDEAS.md](PLAYER_BOND_IDEAS.md)):** a ≤0.5B model
> — **SmolLM2-360M (~250MB)** or **Qwen2.5-0.5B Q4 (~400MB, non-Meta)** — plus a
> ~5MB llama.cpp engine fits under 500MB. Ship it as an **opt-in download** so the
> base installer stays tiny (esp. Web/Android). The native-plugin path is already
> proven by `godotsteam`.

---

## Section A — Ship the embedded model (the enabler)

- [x] **1. The zero-rewrite path: a local `/api/generate` shim.** `scripts/run_embedded_llm.sh` + embedded endpoint in Settings; AIDirector `queue_guardian_line()` uses the same `/api/generate` path.
- [x] **2. The model + engine.** SmolLM2-360M-Instruct Q4 auto-downloads to `user://guardian/` on first launch; llama.cpp runs in-process via `godot_llama`.
- [x] **3. Three tiers, one fallback chain.** Template → **in-process** (`GuardianLlm`) → HTTP embedded → Ollama via `active_llm_tier`.
- [x] **4. Opt-in download, not baked in.** Steam CI bundles the GGUF; slim builds show agree/decline before a one-time download to `user://guardian/`.
- [x] **5. Never block the sim.** `queue_guardian_line()` returns template immediately; async upgrade via `guardian_line_ready`; 6 s HTTP timeout.
- [x] **6. In-process GDExtension.** `GuardianLlm` autoload + `godot_llama` (`scripts/install_godot_llama.sh` for dev/CI builds).
- [x] **7. Guard the output.** `_sanitize_guardian_output()` — word cap, newline trim, profanity filter, template fallback.
- [x] **8. Stable, not random.** Low temperature (0.35), seed from cache key, per-day cache in `_guardian_line_cache`.
- [x] **9. The pitch is a feature.** Settings → Guardian voice section + offline/private explainer copy.

---

## Section B — The Guardian's mind (mild sentience)

- [x] **10. A persistent inner-state.** `guardian_mind.gd` → `_guardian_arc["mind"]` with mood, wants, beliefs, memories, etc.
- [x] **11. It remembers *you*.** Episodic `memories_of_you` from focus, feed, away, glance hooks.
- [x] **12. Desires & intentions.** `update_wants()` drives proactive feed/water/safety wants passed to the model.
- [x] **13. A model of its world.** `world_read` from chemistry + daylight in `update_world_read()`.
- [x] **14. A model of *you*.** `player_read` + `player_moniker` from visit count, gaps, feed history.
- [x] **15. Personality that drifts with experience.** `personality_drift` + `apply_personality_drift()` on crash/successor/loss.
- [x] **16. It knows its own history.** `bio` passed in AI context; predecessor note on torch-pass.
- [x] **17. Opinions & preferences.** Persisted `preferences` dict (corner, food) in mind state.
- [x] **18. The same individual every launch.** Mind + journal in save v6 (`guardian_journal`, `guardian_arc`).
- [x] **19. A quiet inner life.** At night / while you're away it has private moments
  the journal can recount — "while you slept I watched the light move on the glass."
  *M · M* — `compose_quiet_inner_line` + `quiet_inner` journal entries on away/night.

---

## Section C — The voice (how it speaks)

- [x] **20. Generative, not template.** `_speak_guardian()` → `AIDirector.queue_guardian_line()`; templates remain fallback.
- [x] **21. Sparing and earned.** Existing `speak_cd` (55 s) unchanged.
- [x] **22. Tone tracks its mind.** Full mind dict in AI context / system prompt.
- [x] **23. It addresses you.** Templates + `player_moniker` in context.
- [x] **24. It remembers what it said.** `recent_lines` ring in mind + prompt.
- [x] **25. Where it appears.** `guardian_spoke` notification + journal; story popup **Guardian diary** tab.
- [x] **26. It speaks meaning, not logs.** `interpreted_situation()` + `world_read` in context.
- [x] **27. A real literary voice.** Naturalist-diary system prompt in `_build_guardian_prompt()`.

---

## Section D — The ongoing story (the journal)

- [x] **28. A persistent Guardian journal.** `guardian_journal.gd` + `_guardian_journal` in save v6.
- [x] **29. Real chapters.** Deepen the existing 4-chapter arc (`chapter` in
  `_guardian_arc`) into evolving chapters with beginnings and turns — a life with
  shape. *M · M* — `CHAPTER_TITLES` + `maybe_advance_chapter` on visits/age.
- [x] **30. Authored from what actually happens.** Away recap, story events (`_maybe_guardian_journal_from_story`), focus, feed nudges.
- [x] **31. Callbacks & continuity.** Entries reference earlier ones — "the fry I
  worried over has grown bold" — so the story is woven, not episodic. *M · M*
  — `GuardianJournal.weave_callback` on append.
  *(predecessor quotes on torch-pass; AI callbacks not yet)*
- [x] **32. A beautiful Diary UI.** Story popup → **Guardian diary** tab (serif, newest-first).
- [x] **33. A daily entry ritual.** `_maybe_guardian_daily_entry()` on first visit of sim-day.
- [x] **34. You're a character in it.** Visit memories, away entries, monikers in journal voice.
- [x] **35. The journal is the save's soul.** Persisted in save v6 alongside `guardian_arc`.
- [x] **36. Exportable / shareable.** **Copy diary** → clipboard (`export_guardian_journal_plain()`). *(text only; no image yet)*

---

## Section E — Presence & ritual (the heart of Pillar 10)

- [x] **37. It notices you arrive.** `on_player_focus_in()` → arrival line + visit memory.
- [x] **38. It notices you leave.** `on_player_focus_out()` → departure line + settle mood.
- [x] **39. "You were gone three days" — in its voice.** `_emit_away_recap()` routes through `_speak_guardian("away_recap")` + journal.
- [x] **40. It learns your routine.** `update_player_read()` reads `_feed_time_history`.
- [x] **41. Rituals you build together.** `rituals` counter in mind (`fed`, `hello tap` hooks).
- [x] **42. Time-of-day in its voice.** `world_read` + morning situation from `last_daylight`.
- [x] **43. The long arc of visits.** `visit_count`, `longest_gap_s`, monikers drift with cadence.
- [x] **44. It mirrors your attention.** Glance → `record_player_action("watched")` when held at glass.
- [x] **45. Nudges, in character.** Feed nudges still via `_speak_guardian("feed_nudge")` + generative upgrade.

---

## Section F — Arc, mortality & legacy

- [x] **46. It grows up.** A young Guardian is curious/naive; an elder is wry/wise —
  the voice matures over real time. *M · M* — `voice_maturity` + naive/elder arrival lines.
- [x] **47. The torch-pass.** Successor inherits journal via `merge_predecessor()` + predecessor mind fields.
- [x] **48. A real finale.** `"finale"` situation on Guardian death + journal epitaph entry.
- [x] **49. Legend.** A long-lived Guardian becomes legend — referenced by its
  successor, remembered in the journal, its bloodline noted. *M · M*
  — `note_legend` on death + torch-pass header in `merge_predecessor`.
- [x] **50. The closing loop, in its voice.** `_speak_guardian(g, "closing_loop")` on milestone #100.

---

## If Cursor only does five

The two foundations first — the embedded model (**#1**) + the Guardian's
persistent mind (**#10**) + the journal (**#28**) — then:

1. **#1** — the `/api/generate` shim so a bundled model drives the existing AI with
   no rewrite (the enabler for everything).
2. **#20** — route the Guardian's voice through the model (generative, not
   templates) — the payoff you feel immediately.
3. **#28 + #30** — the persistent journal, authored from real events + presence.
4. **#39 + #37** — presence woven in: it greets your return and tells you what it
   lived through while you were gone.
5. **#47** — the torch-pass, so the story (and your bond) survives the Guardian's
   death.

> **Why this is the right shape:** concentrating the (small, slow, limited)
> embedded model on **one** fish is both the technical answer (a 0.5B model can't
> drive 30 fish, but it can drive one character beautifully) *and* the narrative
> answer (you get a protagonist, not ambient chatter). The Guardian scaffolding,
> the presence hooks, and the configurable LLM endpoint already exist — this is
> mostly *wiring a mind and a story through them*.
