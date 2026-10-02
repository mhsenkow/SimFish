# Player-facing claim evidence map

Holistic finishing task **012**. Inventory of grounded claims the player can see
or hear, traced to inputs. Speculative internal module names (`DeltaG`,
`MindSoul`, `_belief_cue`, felt-self layer tags, etc.) must **not** become factual
player claims.

Legend: **F** = supported fact from sim/UI state · **I** = inference / soft label ·
**M** = missing context (claim should soften or hide) · **X** = must not surface
as a factual player statement.

---

## Status chips / tank glance

| Claim surface | Source | Inputs | Kind | Notes |
|---|---|---|---|---|
| Status headline (`O₂ %`, NH₃/NO₂, day/phase, reef warmth/alk/bleach) | `OnboardingLegibility.tank_status_glance` / `_status_headline` | `KeeperCare.stats_from_sim` → `dissolved_o2`, ammonia/nitrite, `day_phase`, saltwater vitals | **F** | Numbers are live sim reads |
| Mood driver line (`stressed — low O₂`, `thriving — balanced loop`, …) | `OnboardingLegibility.mood_driver` | Same stats + `KeeperCare.mood_score` | **I** | Score uses fixed freshwater denominators biomass/algae/waste `600/60/100` (`KeeperCare.mood_score`) — comparative, not a lab assay |
| Care footer hint | `KeeperCare.primary_action_hint` → `OnboardingLegibility.tank_status_footer` | Thresholds on O₂, ammonia, nitrite, stocking ratio, reef bleach/alk | **I** | Actionable suggestion, not a diagnosis |
| Keeper tier label (`crisis`/`stressed`/`steady`/`thriving`) | `KeeperCare.tier_from_stats` | `mood_score` + hard gates (stocking, O₂, ammonia) | **I** | Gates conversation openness; do not present as veterinary fact |

---

## Care hints & feedback

| Claim surface | Source | Inputs | Kind | Notes |
|---|---|---|---|---|
| Care dock / guardian care hint text | `KeeperCare` advisor path (`care_hint` in result dict) | Crisis/stress stats from sim | **I** | Soft guidance |
| Visible care burst (splash / cavitation / wipe) | `CareFeedback.event_for(action, magnitude)` | Action id + magnitude from care systems | **F** (visual) | Grammar is presentation of an action that already ran |
| Feed dock status | `main._feed_dock_status_text` | Feed type / cooldown UI state | **F** | UI state, not ecology prose |

---

## Fish / creature headlines

| Claim surface | Source | Inputs | Kind | Notes |
|---|---|---|---|---|
| Activity label (`Cruising`, `Foraging`, …) | `main.creature_activity_label` | `Fish.current_mode` / shrimp / clam mode enums | **F** | Enum → label; do not invent modes |
| Relationship blurb (`Paired with…`, `Wary of…`) | `main._creature_relationship_line` | Live `partner` ref or strongest `grudges` id resolved to a living creature | **F** / **M** | Empty if partner/rival gone — do not claim absent bonds |
| Display name | `fish_name` / naming pipeline | Player name or generated name | **F** | Persist via `display_name` |
| Familiarity / mood scalars in inspect | Fish fields | `familiarity`, `mood`, `arousal` | **I** | Continuous proxies; prefer qualitative copy over fake precision |
| Learned beliefs / danger points | `FishLearnedMind` → `_belief_cue` | Saved `mind.learned_mind.beliefs` | **I** / **X** | May drive steering & soft voice; never claim “this fish knows X scientifically” |
| Internal mind module names | `DeltaG`, `MindSoul`, `FishBinding`, workspace digests, … | Mind save dict keys | **X** | Diagnostics / code only (`SOUL_CREED.md`) |

---

## Tank dialogue

| Claim surface | Source | Inputs | Kind | Notes |
|---|---|---|---|---|
| Template replies / callbacks | `TankDialogue` | `keeper_memory` topics, promises, sim vitals snapshot (`feed_unix`, O₂, …) | **F** when citing stored topics / vitals · **I** when soft feeling words | Callbacks require age/turn gaps (`CALLBACK_MIN_AGE_S`, `CALLBACK_TURN_GAP`) |
| Tank-initiated lines | `TankDialogue` init path | Wall unix quiet (`INIT_KEEPER_QUIET_S`, `INIT_MIN_GAP_S`, kind cooldown), priority kinds (`o2_low`, birth, death, …) | **I** grounded on kind triggers | Wall clock — not sim time |
| Dreams / “what are you thinking” | `TankDialogue` dream / thought answers | Recombined day events + fish state | **I** | Must stay within logged events |
| LLM / Guardian lines | `AIDirector` / `GuardianLlm` via `MindContext` | Context bag from sim + mind | **I** | Fail soft to templates; never invent events absent from context (`ENGINEERING_CREED`, `SOUL_CREED`) |

---

## Chronicle / story

| Claim surface | Source | Inputs | Kind | Notes |
|---|---|---|---|---|
| Chronicle paragraphs | `TankChronicle` templates + `_fmt` | Classified `story_events`, fish legacies, chapter beats | **F** when naming births/deaths/care from events · **I** when literary glue | Empty tank → explicit “nothing yet” line |
| Story toasts / death summary | `CommsInbox` / `main._flush_death_summary` | Buffered resident deaths | **F** | Windowed aggregation |
| `story_events` raw kinds | `SimDriver` event resolution | Breed, die, eat, care, … | **F** | Prefer these over free-form LLM for factual history |

---

## Grounding rules (for later tracks 11–12)

1. If the input field is missing, omit or soften the claim (**M** → silent).
2. Never print internal schema keys or module names as if the fish said them (**X**).
3. Distinguish **measured** (O₂, ammonia, stocking count) from **scored** (mood_score, tier).
4. Wall-time dialogue cooldowns must not be narrated as “days passed in the tank” unless `tank_age_s` / chronicle day agrees.

Evidence anchors: `onboarding_legibility.gd`, `keeper_care.gd`, `care_feedback.gd`,
`tank_dialogue.gd`, `tank_chronicle.gd`, `main.creature_activity_label`,
`fish_learned_mind.gd`, `docs/SOUL_CREED.md`.
