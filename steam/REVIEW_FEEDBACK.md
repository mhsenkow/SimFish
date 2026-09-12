# Steam build review feedback

Source: Valve build review email · **BuildID `#24083947`** · reviewed on **Windows** only.
Recorded 2026-08-04 so it doesn’t live only in email/chat.

Partner docs they cite:
- Microtransactions: https://partner.steamgames.com/doc/features/microtransactions/implementation
- GetReport: https://partner.steamgames.com/doc/features/microtransactions#3
- Steam Input configs: https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs

---

## Failures (block release)

### 1–2. In-app purchases / Steam Wallet / GetReport

> Game appears to have in-app purchases, but no Steam Wallet integration / no real-money store found.
> Require a live (non-sandbox) test transaction + `GetReport`, plus the test account.

**Reality:** There are **no real-money IAPs**. The Adopt panel is a free spawn mechanic.

**Code (2026-08-04):** Player-facing copy renamed away from Buy/Store/purchase
(`Adopt fish`, hatchery language). Internal node names may still say `FishStore*`.

**Partner reply draft:**
> There are no real-money in-app purchases and no Steam Wallet / MicroTxn usage.
> The in-game “Adopt fish” panel is a free spawning mechanic (no currency, no
> checkout). Please disregard GetReport — it does not apply. Features →
> In-App Purchases / Microtransactions are not used.

Also verify Steamworks **Features** doesn’t claim “In-App Purchases”.

### 3. Full Controller Support category

> Store claims Full Controller Support, but pad can’t reach all functions; keyboard/mouse must not be required.

**Code (2026-08-04):** DualSense couch path + Options controller menu now includes
**Tank list**, **Quit game** (confirm), aquascape escape, modal focus grab,
tank shelf Quit. Retest on Windows with Xbox/PS pad from install → quit.

**Still verify before resubmit:**
- [ ] Open tank → play → Options → Quit without touching KB/M
- [ ] Tank list → New tank → scenario Open → enter tank on pad
- [ ] Settings / Adopt / Help open and close with ○
- [ ] Optional: Developer Recommended Steam Input config (caution only)

### 4. AI tab vs Content Survey

> Settings has an AI tab; Content Survey AI disclosure may not match.

**Reality:** Settings → AI exposes optional local Ollama + Guardian (SmolLM) diary lines (“AI-generated names, moods…”).

**Fix path:** Content Survey → AI section must disclose that the game **can** use generative AI for optional local companion/names/moods/chronicle (on-device; no cloud required for Guardian on Steam builds). Or soften in-game copy if survey says “no AI.” Keep survey and Settings wording aligned before resubmit.

---

## Resolution log (2026-09-10)

Tracked in [`docs/BROAD_DIRECTIONS_20.md`](../docs/BROAD_DIRECTIONS_20.md) direction #1.

### 1–2. IAP / Wallet / GetReport — **code side closed**

All purchase-flavoured *internal* identifiers are gone, so a reviewer running
`strings` or inspecting the scene tree finds no store/purchase surface at all:

| Was | Now |
|---|---|
| `scripts/fish_store.gd` | `scripts/adopt_panel.gd` |
| `FishStorePanel` / `FishStoreToggle` (main.tscn) | `AdoptPanel` / `AdoptToggle` |
| `main.fish_store_panel` / `fish_store_toggle` | `adopt_panel` / `adopt_toggle` |
| `UiPanelManager.MODAL_STORE = "store"` | `MODAL_ADOPT = "adopt"` |
| `world.spawn_purchased_fish()` | removed (was a dead alias to `spawn_adopted_fish()`) |
| `UiIcons` key `"store"` | `"adopt"` |
| discovery source written as `"store"` | written as `"adopt"` |

The discovery source is **persisted in save files**, so readers
(`library_panel` src_label, `main._discovery_source_label`) still accept the
legacy `"store"` value — old tanks keep their "Adopted" badges.

Still partner-side: confirm Steamworks → **Features** does not claim In-App
Purchases or Microtransactions.

### 3. Full Controller Support — **code verified, hardware retest open**

Every checklist destination has a code path, now asserted by
`scripts/smoke_controller_coverage.gd` (headless, no pad required — 13
destinations across both aquascape modes). Order and labels moved out of
`main._open_gamepad_menu()` into `scripts/controller_menu.gd` so the contract
cannot silently drift; `ControllerMenu.REQUIRED_DESTINATIONS` is the list
Valve's checklist walks.

Checklist status — **code path** vs **hardware-verified**:

| Valve step | Code path | Verified on Windows + pad |
|---|---|---|
| Open tank → play → Options → Quit | ✅ `"Quit game"` → `_confirm_quit_game()` | ⏸ |
| Tank list → New tank → scenario Open → enter tank | ✅ `scenario_picker` uses `PanelTheme.schedule_couch_focus` + `JOY_BUTTON_A`/`B` | ⏸ |
| Settings / Adopt / Help open+close with ○ | ✅ entries present; `ui_cancel` binds `JOY_BUTTON_B` for all devices | ⏸ |
| Optional Steam Input config | — | ⏸ |

**Blocker:** the remaining column needs a Windows machine and an Xbox/PS pad.
`smoke_gamepad_live.gd` covers the pad-attached run but asserts a pad is
connected, so it cannot gate CI.

### 4. AI disclosure — **canonical text below**

Copy this into Steamworks → **Content Survey → AI** verbatim so the survey and
the in-game Settings → AI tab cannot disagree. It mirrors
`settings_panel.gd`'s `ai_desc` copy and the platform matrix in `AGENTS.md`.

> This game includes **optional**, **on-device** generative AI. Two features use
> it, both off or template-driven by default and both fully playable with AI
> disabled:
>
> 1. **Guardian voice / fish thoughts** — a small language model
>    (SmolLM2-360M-Instruct, Q4_K_M, ~250MB) bundled in the Steam depot and run
>    in-process to phrase creature diary lines and mood text. No network access.
>    Disabled entirely on web and Android builds, which use pre-written template
>    text instead.
> 2. **AI Companion (optional Ollama)** — if the player installs
>    [Ollama](https://ollama.com) themselves, the game can additionally use their
>    own local models for fish names, moods, and tank chronicle lines. Off by
>    default; the player opts in under Settings → AI.
>
> **Nothing is sent to any remote server.** There is no cloud inference, no
> account, and no player data leaves the machine. All generated text is
> cosmetic flavour (names, moods, diary lines) — it never gates gameplay. With
> AI off the game ships the same offline name pool and template voice.

Wording to keep aligned if either side changes:
`scripts/settings_panel.gd` → `ai_desc.text` and the section headers
"Voice & thoughts (on-device)" / "AI Companion (optional Ollama)".

---

## Platform note

Review was **Windows only**. Before next submission, smoke through Steam on fresh **macOS** and **Linux/SteamOS** (deps, launch, quit).

---

## Resubmit checklist

- [ ] IAP false-positive: UI renamed; ticket reply explains no Wallet; Features unchecked
- [ ] Controller category matches build (Partial/None, or Full only if pad-complete)
- [ ] Content Survey AI ↔ Settings AI wording aligned
- [ ] Fresh Win + Mac + Linux install via Steam
- [ ] Bump build, set live, reply on review ticket with notes + (if any) GetReport evidence
