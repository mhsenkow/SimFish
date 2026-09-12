#!/usr/bin/env bash
# Prompt for Steam password via macOS dialog, then upload staged content.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STEAM_USERNAME="${STEAM_USERNAME:-mhsenkow}"

PASS="$(osascript <<'EOF'
display dialog "Steam password for mhsenkow:" default answer "" with hidden answer
text returned of result
EOF
)" || true

if [[ -z "${PASS:-}" ]]; then
	echo "Cancelled — no password." >&2
	exit 1
fi

GUARD="$(osascript <<'EOF'
display dialog "Steam Guard code (5 chars). Cancel if you do not need one:" default answer ""
text returned of result
EOF
)" || true

export STEAM_USERNAME STEAM_PASSWORD="$PASS"
if [[ -n "${GUARD:-}" ]]; then
	export STEAM_GUARD_CODE="$GUARD"
fi

echo "Starting upload as $STEAM_USERNAME..."
set +e
"$ROOT/upload.sh"
status=$?
set -e

unset STEAM_PASSWORD STEAM_GUARD_CODE PASS GUARD
exit "$status"
