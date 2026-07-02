#!/usr/bin/env bash
# Submit WalstadLoom.app to Apple notarization and staple the ticket.
#
# Credentials (pick one):
#   A) Keychain profile (recommended locally):
#        xcrun notarytool store-credentials "walstad-loom-notary" \
#          --apple-id YOU@EMAIL --team-id WC44W2QVE4 --password APP-SPECIFIC-PASSWORD
#      then: NOTARY_KEYCHAIN_PROFILE=walstad-loom-notary ./scripts/notarize_macos_app.sh
#
#   B) App Store Connect API key (recommended for CI):
#      NOTARY_API_KEY=AuthKey_XXXX.p8 NOTARY_API_KEY_ID=... NOTARY_API_ISSUER=...
#
#   C) Inline app-specific password:
#      APPLE_ID=... APPLE_APP_SPECIFIC_PASSWORD=... APPLE_TEAM_ID=WC44W2QVE4
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/WalstadLoom.app}"
ZIP="${2:-$(mktemp -t walstad-loom-notarize.XXXXXX.zip)}"
CLEANUP_ZIP=0
if [[ $# -lt 2 ]]; then
	CLEANUP_ZIP=1
fi

TEAM_ID="${APPLE_TEAM_ID:-WC44W2QVE4}"

if [[ ! -d "$APP" ]]; then
	echo "Missing app bundle: $APP" >&2
	exit 1
fi

echo "Creating notarization zip: $ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

NOTARY_ARGS=(submit "$ZIP" --wait)
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
	NOTARY_ARGS+=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [[ -n "${NOTARY_API_KEY:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER:-}" ]]; then
	NOTARY_ARGS+=(--key "$NOTARY_API_KEY" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
	NOTARY_ARGS+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID")
else
	echo "No notarization credentials. Set NOTARY_KEYCHAIN_PROFILE or API key or APPLE_ID+password." >&2
	exit 1
fi

echo "Submitting to Apple notarization (this can take several minutes)..."
xcrun notarytool "${NOTARY_ARGS[@]}"

echo "Stapling ticket to app..."
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

if [[ "$CLEANUP_ZIP" == "1" ]]; then
	rm -f "$ZIP"
fi

echo "Notarized OK: $APP"
