# App Store Connect — walstad loom (iOS / iPad)

Bundle ID: `com.mhsenkow.walstadloom`  
Team: `WC44W2QVE4` · Category: **Games → Simulation** (secondary: Casual)  
Price: **$2.99** USD base (GitHub releases stay free; Steam is separate)

Shell: Godot 4.6 iOS export (`build/ios/`)

## Name
walstad loom

## Subtitle (≤30 chars)
A living pixel aquarium

## Promotional text (≤170)
Start a planted Walstad tank, watch fish school and breed, and keep the water in balance.

## Description
walstad loom is a generative pixel-art aquarium. Plants grow, fish school and breed, shrimp climb, snails clean the glass — a closed nutrient loop that settles into a Walstad-style balance as you watch.

• One-tap Living tank with gentle lo-fi and automatic feeding  
• Eighteen habitat templates and free-form aquascaping  
• Individual fish with genomes, schooling, and simulated learning  
• Day/night photoperiod, water chemistry, and reef mode  
• Touch-friendly HUD for iPhone and iPad  

No account required. Saves stay on device. The optional Guardian companion runs on-device when available; iOS builds use template voice by default.

## Keywords
aquarium,fish,walstad,pixel,simulation,plants,relaxing,tank,idle,godot

## Support URL
https://github.com/mhsenkow/SimFish/issues

## Marketing URL
https://mhsenkow.github.io/SimFish/docs/

## Privacy policy URL
https://mhsenkow.github.io/SimFish/docs/privacy.html
(create if missing — declare on-device saves, no ad SDK, optional local LLM)

## Age rating
4+ (no UGC, no messaging, mild nature sim).

## App Privacy
**Data Not Collected** unless you later add analytics SDKs. No advertising ID.

## Review notes
1. Launch → Living tank (or Templates).  
2. Wait for the aquascape to build; pinch/drag camera; open Care / Feed.  
3. Optional: Settings → confirm touch controls.  

No login. Next store build **0.2.51 (64)**. ASC marketing version stays **1.0**.

## Build / encryption
- Marketing version **0.2.51**, build **64** (ASC version string **1.0**)  
- `ITSAppUsesNonExemptEncryption` = false (HTTPS only; no custom crypto)

## API upload
```bash
export APPLE_API_KEY_ID=397A4HMVSU
export APPLE_API_ISSUER=69a6de78-8ab8-47e3-e053-5b8c7c11a4d1
# key: ~/.appstoreconnect/private_keys/AuthKey_397A4HMVSU.p8
xcrun altool --upload-app -f build/ios/export/WalstadLoom.ipa -t ios \
  --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER"
```

## Local archive
```bash
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --export-release "iOS" ../../build/ios/WalstadLoom.ipa
# then:
cd build/ios
xcodebuild -project WalstadLoom.xcodeproj -scheme WalstadLoom \
  -destination 'generic/platform=iOS' -archivePath Archive.xcarchive \
  DEVELOPMENT_TEAM=WC44W2QVE4 CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION=64 -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath Archive.xcarchive \
  -exportPath export -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

## Portal leftovers (Account Holder)
1. Accept updated **Apple Developer Program License Agreement**  
2. Complete **Digital Services Act** trader status (EU)  
3. **Edit Legal Entity** if offering paid apps (free app may still need entity for agreements)  
4. Apps → New App → iOS → Bundle `com.mhsenkow.walstadloom` → SKU `walstad-loom`  
5. Paste Name / Subtitle / Description / Keywords / URLs above  
6. Upload IPA → assign to 1.0 → screenshots (iPhone 6.7" + iPad 13")  
7. App Privacy → Data Not Collected  

## Status (2026-10-29)
- Desktop and the site ship **v0.2.51**. App Store Connect marketing version remains **1.0**; binary **0.2.51 / 64**.
- ASC app `6823230910` — iOS + macOS were **Developer Rejected** after canceling stuck Waiting-for-Review submissions; rebuild **64** then **Add for Review**.
- Price **$2.99** USA base; categories Games → Simulation + Casual; secondary Entertainment  
- Screenshots: iPhone 6.7" ×3, iPad 13" ×3, Mac 2560×1600 ×3 (App Preview video **not** required)  
- Privacy: Data Not Collected + privacy URL live  
- Still optional / Account Holder: real App Review phone (placeholder `+1 412 555 0100`), EU **DSA** trader status, Availability “Set Up” if prompted, more screenshots (up to 10)  


### Mac App Store pkg (re-sign notes)
Godot’s MAS export omits top-level `LSMinimumSystemVersion` (only `LSMinimumSystemVersionByArchitecture`). Preset `macOS App Store` now injects it via `additional_plist_content`. If rebuilding by hand:

```bash
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 11.0' \
  build/mas/WalstadLoom.app/Contents/Info.plist
codesign --force --deep --options runtime --timestamp \
  --sign "Apple Distribution: Michael Senkow (WC44W2QVE4)" \
  --entitlements mas.entitlements build/mas/WalstadLoom.app
productbuild --component build/mas/WalstadLoom.app /Applications \
  --sign "3rd Party Mac Developer Installer: Michael Senkow (WC44W2QVE4)" \
  build/mas/WalstadLoom.pkg
xcrun altool --upload-app -f build/mas/WalstadLoom.pkg -t osx \
  --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER"
```

