#!/usr/bin/env bash
# Export Developer ID Application cert + private key as a .p12 for GitHub Actions secrets.
# Run locally once; upload the base64 output as repo secret MACOS_CERTIFICATE.
set -euo pipefail

IDENTITY="${MACOS_SIGN_IDENTITY:-Developer ID Application: Michael Senkow (WC44W2QVE4)}"
OUT="${1:-$HOME/Desktop/walstad-loom-signing.p12}"

echo "Exporting: $IDENTITY"
echo "Output: $OUT"
echo "You will be prompted for a NEW export password (store as MACOS_CERTIFICATE_PASSWORD secret)."
echo

security export -t identities -f pkcs12 -o "$OUT" "$IDENTITY"

echo
echo "Base64 for GitHub secret MACOS_CERTIFICATE:"
base64 < "$OUT" | tr -d '\n'
echo
echo
echo "Done. Add secrets at: GitHub repo → Settings → Secrets → Actions"
echo "  MACOS_CERTIFICATE          = base64 above"
echo "  MACOS_CERTIFICATE_PASSWORD = export password you just chose"
