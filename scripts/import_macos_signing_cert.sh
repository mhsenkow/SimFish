#!/usr/bin/env bash
# Import a Developer ID .p12 into a temporary keychain (GitHub Actions macOS runner).
# Requires env: MACOS_CERTIFICATE (base64 p12), MACOS_CERTIFICATE_PASSWORD
set -euo pipefail

if [[ -z "${MACOS_CERTIFICATE:-}" || -z "${MACOS_CERTIFICATE_PASSWORD:-}" ]]; then
	echo "Set MACOS_CERTIFICATE (base64 .p12) and MACOS_CERTIFICATE_PASSWORD." >&2
	exit 1
fi

KEYCHAIN="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

CERT_PATH="$RUNNER_TEMP/signing.p12"
echo "$MACOS_CERTIFICATE" | base64 -D > "$CERT_PATH"
security import "$CERT_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

echo "Keychain ready: $KEYCHAIN"
