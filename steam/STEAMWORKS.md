# walstad loom — Steamworks

> **Internal dev doc** — depot upload, GodotSteam, store asset generation. Not linked from the public landing page; players use the [Steam store](https://store.steampowered.com/app/4796460/).

App ID **4796460** · Store name **walstad loom**

## One-time Steamworks setup

1. **Create depots** (Partner site → App Admin → walstad loom → SteamPipe → Depots):
   - Windows depot (e.g. `walstad loom — Windows`)
   - Linux depot
   - macOS depot
   - Note each **Depot ID** (numeric, assigned by Steam).

2. **Configure launch options** (App Admin → Installation → General):
   - Windows: `WalstadLoom.exe`
   - Linux: `WalstadLoom-linux.x86_64`
   - macOS: `WalstadLoom.app`

3. **macOS 64-bit flag (required)** — App Admin → Edit Steamworks Settings →
   Application → **Supported Operating Systems** → under macOS check:
   - **64 Bit (Intel) Binaries Included**
   - **Apple Silicon Binaries Included** (universal export includes arm64)
   Without these, Steam shows the false banner *“Your current macOS version is
   unable to run 32-bit games”* even though the Godot 4.6 export is universal
   64-bit (`x86_64` + `arm64`). Click **Save**, then the **Publish** tab and
   publish. Docs: [Platforms](https://partner.steamgames.com/doc/store/application/platforms).
   If CI notarized the build cleanly, also check **App Bundles Are Notarized**.

4. **Upload the Client Icon** (App Admin → **Store Presence → Library Assets**
   → *Client Icon*): [`steam/store/assets/icons/clienticon.ico`](store/assets/icons/clienticon.ico).

   This is the one icon Steam will *not* take from the build. Windows embeds
   its icon into `WalstadLoom.exe` at export (`application/modify_resources`)
   and macOS gets `icon.icns` inside the `.app`, but **Linux ELF binaries carry
   no icon at all**, so on the Linux client and Steam Deck this file is the only
   icon Steam has. The field also **rejects PNG** — it must be `.ico`, which is
   why `clienticon.png` sitting next to it was never accepted.

   Regenerate it (plus every capsule) with:
   ```bash
   steam/store/.venv/bin/python steam/store/generate_assets.py
   ```
   Library Assets changes go live only after **Publish** on the store page —
   uploading alone leaves the placeholder showing.

5. **Copy depot IDs:**
   ```bash
   cp steam/depot_ids.env.example steam/depot_ids.env
   # edit steam/depot_ids.env with your depot IDs
   ```
   `steam/depot_ids.env` is git-ignored (local only); only the `.example` is committed.


## Achievements, Cloud & Rich Presence (BROAD_DIRECTIONS #2)

Code side lives in `scripts/steam_stats.gd` (contract + pure evaluation),
`scripts/steam_achievements.gd` (driver + Steam calls), wired by
`scripts/steam_service.gd`. Gated by `scripts/smoke_steam_stats.gd`.

### 1. Achievements — partner-site config

`SteamStats.ACHIEVEMENTS` is the **source of truth**. Every API Name below must
exist in App Admin → **Achievements** with the same API Name, or the unlock is
silently dropped by Steam. Regenerate this table any time the array changes:

```gdscript
print(SteamStats.partner_manifest())
```

| API Name | Display Name | Description |
|---|---|---|
| `ACH_CYCLED` | Cycled | Bring a tank through the nitrogen cycle to established. |
| `ACH_FIRST_FRY` | New Arrivals | See your first fry hatch in a tank you built. |
| `ACH_GEN_3` | Third Generation | Raise a lineage to its third generation. |
| `ACH_GEN_10` | Ten Generations Deep | Raise a lineage to its tenth generation. |
| `ACH_MORPH_FIRST` | Something New | Watch a lineage drift far enough to become its own morph. |
| `ACH_MORPH_5` | Speciation Event | Hold five distinct emergent morphs in one tank. |
| `ACH_SHRIMP_COLONY` | Colony | Grow a shrimp population past twenty-five. |
| `ACH_SNAIL_CREW` | Cleanup Crew | Keep ten or more snails working the glass. |
| `ACH_JUNGLE` | Jungle | Fill a tank with thirty living plants. |
| `ACH_FLOWERING` | Above the Waterline | Coax an aquatic plant into flowering. |
| `ACH_BALANCED` | Walstad Balance | Hold a cycled tank at healthy oxygen and near-zero ammonia, understocked, for ten sim minutes. |
| `ACH_LIBRARY_10` | Field Notes | Record ten species in the library. |
| `ACH_LIBRARY_25` | Taxonomist | Record twenty-five species in the library. |
| `ACH_OLD_TANK` | Mature Tank | Keep a single tank running for a hundred sim days. |

Each needs an unlocked + locked icon (64×64 png) uploaded on the partner site.

### 2. Steam Cloud — use Auto-Cloud, not the API

Saves are plain files under `user://`, so **Auto-Cloud** covers them with no
code. App Admin → **Cloud** → Auto-Cloud, add one root per platform:

| Platform | Root | Path | Pattern |
|---|---|---|---|
| Windows | `WinAppDataRoaming` | `Godot/app_userdata/walstad loom` | `tanks/*` |
| macOS | `MacHome` | `Library/Application Support/Godot/app_userdata/walstad loom` | `tanks/*` |
| Linux | `LinuxHome` | `.local/share/godot/app_userdata/walstad loom` | `tanks/*` |

Also add a second pattern per root for the achievement mirror and species
library: `steam_stats.json`, `species_library_global.json`.

**Do not sync** `guardian/` — the bundled GGUF is ~250MB and ships in the depot.

Quota: set bytes generously (a mature tank's `state.json` can approach the
50 MiB `MAX_JSON_BYTES` ceiling) and file count ≥ 64 (3 rotated backups ×
slots).

### 3. Rich Presence — localisation token

`steam_achievements.gd` sets `status` plus `steam_display = "#Status_Tank"`.
Steam renders nothing unless that token is declared: App Admin → **Rich
Presence Localization**, English:

```
Status_Tank = {#status}
```

Without it the friends list shows a blank status rather than
"Cycled tank · 12 fish · 30 plants · gen 4".


## Local development

Install GodotSteam (once per clone):

```bash
./steam/install_godotsteam.sh
```

Run from the Godot editor or exported binary with Steam client open. `steam_appid.txt` (App ID 4796460) must sit next to the executable for non-Steam launches during development.

## Build & upload

Export desktop builds (macOS, Windows, Linux presets), then:

```bash
cd shaders-godot/godot-project
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Linux"
godot --headless --path . --export-release "macOS"

cd ../..
./steam/stage_content.sh          # copies build/ → steam/content/
STEAM_USERNAME=your_partner_account ./steam/upload.sh
```

`upload.sh` generates VDFs from templates, runs `steamcmd`, and uploads to a **draft** build. Set the build live in Steamworks → Builds.

## Store page checklist

See also **`steam/REVIEW_FEEDBACK.md`** for Valve build-review failures
(Build `#24083947`) and the fix checklist before resubmit.

Generate capsule art and screenshots. First-time setup creates a local venv
(git-ignored) with Pillow:

```bash
cd steam/store
python3 -m venv .venv
.venv/bin/pip install pillow playwright requests
.venv/bin/python generate_assets.py
```

On later runs just `.venv/bin/python generate_assets.py`. The generator reads
hand-made capsule art + gameplay screenshots from `marketing/` (see
`generate_assets.py` `MARKETING_CAPSULES`).

Then upload everything under `steam/store/assets/` via **Edit Store Page → Graphical Assets → Drop images here**.

See `steam/store/` for draft copy and suggested tags:

- **Short description:** Generative pixel-art Walstad aquarium. Plants grow, fish school, shrimp graze, snails crawl — self-balancing ecosystem in chunky pixels.
- **Tags:** Simulation, Casual, Pixel Graphics, Relaxing, Nature, Singleplayer
- **Capsule art:** 616×353 header, 460×215 small capsule, 231×87 library capsule

Package IDs from app creation (reference):

| Package | ID |
|---------|-----|
| Developer Comp | 1667203 |
| Beta Testing | 1667204 |
| Main | 1667205 |

## GitHub releases vs Steam

GitHub Releases (`walstad-loom-*.zip`) remain for direct downloads. Steam builds use the same export presets; stage with `steam/stage_content.sh` before upload.
