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

4. **Copy depot IDs:**
   ```bash
   cp steam/depot_ids.env.example steam/depot_ids.env
   # edit steam/depot_ids.env with your depot IDs
   ```
   `steam/depot_ids.env` is git-ignored (local only); only the `.example` is committed.

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
