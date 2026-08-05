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

## Platform note

Review was **Windows only**. Before next submission, smoke through Steam on fresh **macOS** and **Linux/SteamOS** (deps, launch, quit).

---

## Resubmit checklist

- [ ] IAP false-positive: UI renamed; ticket reply explains no Wallet; Features unchecked
- [ ] Controller category matches build (Partial/None, or Full only if pad-complete)
- [ ] Content Survey AI ↔ Settings AI wording aligned
- [ ] Fresh Win + Mac + Linux install via Steam
- [ ] Bump build, set live, reply on review ticket with notes + (if any) GetReport evidence
