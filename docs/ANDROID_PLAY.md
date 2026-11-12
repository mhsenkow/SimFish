# Google Play — walstad loom (Android)

Package: `com.mhsenkow.walstadloom`  
Console app: [Walstad Loom](https://play.google.com/console) · free game  
Privacy: https://mhsenkow.github.io/SimFish/docs/privacy.html

## Store copy

**Name:** walstad loom  

**Short description (≤80):**  
A living pixel-art Walstad aquarium. Plants grow, fish school, water balances.

**Full description:**  
walstad loom is a generative pixel-art aquarium. Plants grow, fish school and breed, shrimp climb, snails clean the glass — a closed nutrient loop that settles into a Walstad-style balance as you watch.

• One-tap Living tank with gentle lo-fi and automatic feeding  
• Eighteen habitat templates and free-form aquascaping  
• Individual fish with genomes, schooling, and simulated learning  
• Day/night photoperiod, water chemistry, and reef mode  
• Touch-friendly HUD for phones and tablets  

No account required. Saves stay on device. Android builds use template companion voice (no on-device LLM bundle).

**Category:** Games → Simulation (tags: Casual, Offline)  
**Contact:** mhsenkow@gmail.com · Support: https://github.com/mhsenkow/SimFish/issues  
**Marketing:** https://mhsenkow.github.io/SimFish/docs/

## Graphics (local)

Prepared under `marketing/play/` (not all committed):

- `icon_512.png` — high-res icon  
- `feature_graphic_1024x500.png` — feature graphic  
- `phone_01.png` … `phone_05.png` — phone screenshots (from Steam assets)

## Release signing (local only)

Upload keystore lives in gitignored `secrets/`:

```bash
secrets/walstadloom-upload.keystore
secrets/android_upload.env
secrets/export_android_release_password.txt
```

`export_presets.cfg` points at the keystore path with an empty password; inject the password only for the export, then clear it.

Android Gradle build template is installed under `shaders-godot/godot-project/android/` (gitignored). Reinstall from Godot **Project → Install Android Build Template** if missing.

## Export AAB

```bash
# one-shot: inject password, export, strip
PASS=$(cat secrets/export_android_release_password.txt)
# set keystore/release_password in export_presets temporarily, then:
./scripts/godot.sh --headless --path shaders-godot/godot-project \
  --export-release "Android" ../../build/WalstadLoom.aab
# clear keystore/release_password again
```

Local Play uploads flip the Android preset to Gradle AAB
(`gradle_build/use_gradle_build=true`, `export_format=1`,
`export_path=../../build/WalstadLoom.aab`) with the upload keystore.
**Do not commit that flip** — CI ships the sideload APK
(`use_gradle_build=false`, `export_format=0`) for GitHub Releases.
Current store track: `version/name=0.2.54`, `version/code=67`.

## Play Console status (2026-10-28)

Done in Console:
- Privacy policy URL
- Ads → No
- Sign-in / restricted access → No
- Content ratings (IARC Game, ESRB Everyone)
- Target audience → 18 and over
- Data safety → no data collected/shared (saved after audience)
- Advertising ID → No
- Government / Financial / Health → none
- Store settings → Game / Simulation; email + website

Local ready:
- AAB `build/WalstadLoom.aab` (v0.2.50 / versionCode 63)
- Graphics in `marketing/play/` (icon, feature, phone_01–05)

Still needs manual file upload (browser file picker blocked for automation):
1. Default store listing → Add assets (icon, feature graphic, ≥2 phone screenshots) → Save
2. Internal testing → Create release → upload `build/WalstadLoom.aab` → add testers

## Play Console checklist

1. Privacy policy URL  
2. Ads → No  
3. App access / sign-in → no login  
4. Content rating questionnaire (IARC)  
5. Target audience (18+ or All ages as appropriate; no kids-directed)  
6. Data safety → no data collected  
7. Government / Financial / Health → No  
8. Category + contact details  
9. Default store listing + graphics  
10. Internal testing → upload AAB → add testers  
11. Closed testing (≥14 days typically) before production access  

GitHub Releases keep shipping free APKs; Play is the store distribution path.
