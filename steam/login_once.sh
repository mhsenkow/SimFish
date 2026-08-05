#!/usr/bin/env bash
# One-time interactive login to cache steamcmd credentials on this Mac.
# After this succeeds, ./upload.sh can reuse the session without a password prompt.
set -euo pipefail

STEAM_USERNAME="${STEAM_USERNAME:-mhsenkow}"
echo "Logging in as $STEAM_USERNAME..."
if steamcmd +login "$STEAM_USERNAME" +quit; then
	echo "Cached session OK — run: STEAM_USERNAME=$STEAM_USERNAME ./steam/upload.sh"
else
	echo "Login failed — run interactively: steamcmd +login $STEAM_USERNAME" >&2
	exit 1
fi
