#!/usr/bin/env bash
# Stage desktop builds into steam/content/ for SteamPipe upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
CONTENT="$ROOT/steam/content"

rm -rf "$CONTENT"
mkdir -p "$CONTENT/windows" "$CONTENT/linux" "$CONTENT/macos"

if [[ -f "$BUILD/WalstadLoom.exe" ]]; then
	cp "$BUILD/WalstadLoom.exe" "$CONTENT/windows/"
	echo "Staged Windows build"
else
	echo "Missing $BUILD/WalstadLoom.exe — export with the Windows Desktop preset first" >&2
fi

if [[ -f "$BUILD/WalstadLoom-linux.x86_64" ]]; then
	cp "$BUILD/WalstadLoom-linux.x86_64" "$CONTENT/linux/"
	chmod +x "$CONTENT/linux/WalstadLoom-linux.x86_64"
	echo "Staged Linux build"
else
	echo "Missing $BUILD/WalstadLoom-linux.x86_64 — export with the Linux preset first" >&2
fi

if [[ -d "$BUILD/WalstadLoom.app" ]]; then
	cp -R "$BUILD/WalstadLoom.app" "$CONTENT/macos/"
	echo "Staged macOS build"
else
	echo "Missing $BUILD/WalstadLoom.app — export with the macOS preset first" >&2
fi

echo "Content staged under steam/content/"
