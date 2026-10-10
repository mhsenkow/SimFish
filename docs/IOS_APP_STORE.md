# iOS / App Store path for walstad loom

Godot already exports Android and ships a touch HUD (`mobile_hud.gd`,
`OS.has_feature("ios")`). This doc is the App Store checklist for iPhone + iPad.

## Current state (v0.2.39)

| Piece | Status |
|---|---|
| Touch / mobile HUD | Shipped |
| iOS export preset | `export_presets.cfg` → **iOS** (`com.mhsenkow.walstadloom`) |
| Bundle ID on Apple Developer | **Needs create** — match macOS/Android: `com.mhsenkow.walstadloom` |
| Distribution cert | Present locally: `Apple Distribution: Michael Senkow (WC44W2QVE4)` |
| Provisioning profile | Local profile **Loom App Store** is for `com.loom.storyteller` — **wrong app** |
| App Store Connect app record | Needs create for walstad loom |
| ASC API key on disk | `~/.appstoreconnect/private_keys/AuthKey_397A4HMVSU.p8` (needs Issuer ID) |
| Guardian LLM on iOS | Disabled (same policy as Android / AGENTS.md) |

## One-time Apple setup

1. **Developer Portal → Identifiers**  
   Create App ID `com.mhsenkow.walstadloom` (iOS / iPadOS). Enable Game Center only if you want it; leave push off for now.

2. **Profiles**  
   Create an **App Store** distribution profile for that App ID, download it, and install. Put the UUID into the iOS preset (`application/provisioning_profile_uuid_release`) or export with:
   ```bash
   export GODOT_IOS_PROVISIONING_PROFILE_UUID_RELEASE="<uuid>"
   ```

3. **App Store Connect**  
   Create the app: name **walstad loom**, bundle `com.mhsenkow.walstadloom`, primary category Games → Simulation (or Casual). Fill privacy nutrition labels (no tracking today).

4. **ASC API Issuer ID**  
   App Store Connect → Users and Access → Integrations → App Store Connect API. Copy the **Issuer ID** and keep it with Key ID `397A4HMVSU`. Local notarization/CI already expecting `NOTARY_API_ISSUER`.

## Export locally

```bash
mkdir -p build/ios
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --export-release "iOS" ../../build/ios/WalstadLoom.ipa
```

Or export the Xcode project (`application/export_project_only=true`), open it in Xcode, Archive → Distribute App → App Store Connect.

Signing identity for release: `Apple Distribution: Michael Senkow (WC44W2QVE4)`  
Team ID: `WC44W2QVE4`  
Targeted devices: iPhone + iPad (`targeted_device_family=2`).

## Upload

```bash
xcrun altool --upload-app -f build/ios/WalstadLoom.ipa -t ios \
  --apiKey 397A4HMVSU --apiIssuer "<ISSUER_UUID>"
# or: open Xcode Organizer → Distribute
```

## Product notes for review

- Exclude Steam + godot_llama + Guardian GGUF from the iOS preset (same as Android/Web).
- Expect thermal / memory pressure on older phones; start from the existing mobile fidelity path in `tank_config.gd`.
- Screenshots need iPhone 6.7" and iPad 12.9" (or current required sizes) before submission.
- First TestFlight build is the practical gate before public App Store review.

## Not blocking the desktop release

GitHub + Steam ship from the existing macOS/Windows/Linux (+ Android APK) pipeline. iOS is additive: finish Apple identifiers/profile + Issuer ID, then export and upload.
