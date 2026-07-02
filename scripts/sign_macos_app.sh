#!/usr/bin/env bash
# Re-sign WalstadLoom.app with Developer ID after Godot export + llama dylib bundle.
# Run after bundle_macos_llama_dylibs.sh (dylibs must exist before signing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/WalstadLoom.app}"
ENTITLEMENTS="$ROOT/scripts/macos/WalstadLoom.entitlements"

DEFAULT_IDENTITY='Developer ID Application: Michael Senkow (WC44W2QVE4)'
IDENTITY="${MACOS_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"

if [[ ! -d "$APP" ]]; then
	echo "Missing app bundle: $APP" >&2
	exit 1
fi
if [[ ! -f "$ENTITLEMENTS" ]]; then
	echo "Missing entitlements: $ENTITLEMENTS" >&2
	exit 1
fi

sign_file() {
	local target="$1"
	local use_entitlements="${2:-0}"
	local args=(--force --options runtime --timestamp --sign "$IDENTITY")
	if [[ "$use_entitlements" == "1" ]]; then
		args+=(--entitlements "$ENTITLEMENTS")
	fi
	codesign "${args[@]}" "$target"
}

echo "Signing with: $IDENTITY"

# Innermost binaries first — required for valid nested signatures.
while IFS= read -r -d '' f; do
	sign_file "$f" 0
done < <(find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -path '*.framework/*' ! -name 'Info.plist' ! -name '*.plist' \) -print0 2>/dev/null || true)

while IFS= read -r -d '' fw; do
	if [[ -d "$fw" ]]; then
		sign_file "$fw" 0
	fi
done < <(find "$APP/Contents/Frameworks" -name '*.framework' -print0 2>/dev/null || true)

MAIN_EXE="$APP/Contents/MacOS/walstad loom"
if [[ ! -f "$MAIN_EXE" ]]; then
	echo "Missing main executable: $MAIN_EXE" >&2
	exit 1
fi
sign_file "$MAIN_EXE" 1
sign_file "$APP" 1

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t exec -vv "$APP" 2>&1 || true

echo "Signed OK: $APP"
