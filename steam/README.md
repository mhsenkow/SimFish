# walstad loom — Steamworks

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

3. **Copy depot IDs:**
   ```bash
   cp steam/depot_ids.env.example steam/depot_ids.env
   # edit steam/depot_ids.env with your depot IDs
   ```

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

Generate capsule art and screenshots:

```bash
cd steam/store && .venv/bin/python generate_assets.py
```

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
