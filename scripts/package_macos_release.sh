#!/usr/bin/env bash
# Full macOS release pipeline: export → bundle llama dylibs → sign → (optional) notarize → zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/shaders-godot/godot-project"
APP="$ROOT/build/WalstadLoom.app"
ZIP="$ROOT/artifacts/walstad-loom-mac.zip"
DO_NOTARIZE="${NOTARIZE:-0}"

cd "$ROOT"
bash scripts/godot.sh --headless --path "$PROJECT" --import
bash scripts/godot.sh --headless --path "$PROJECT" --export-release "macOS"
mkdir -p "$APP/Contents/MacOS" artifacts
# steam_appid.txt must not live in Contents/MacOS/ — it breaks codesign (APP_ID is
# hardcoded in steam_service_desktop.gd; Steam client injects the id at launch).
bash scripts/bundle_macos_llama_dylibs.sh "$APP"
bash scripts/sign_macos_app.sh "$APP"

if [[ "$DO_NOTARIZE" == "1" ]]; then
	bash scripts/notarize_macos_app.sh "$APP"
fi

cd "$ROOT/build"
zip -r "$ZIP" WalstadLoom.app
echo "Packaged: $ZIP"
