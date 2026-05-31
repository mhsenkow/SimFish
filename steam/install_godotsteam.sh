#!/usr/bin/env bash
# Install GodotSteam GDExtension into the Godot project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/shaders-godot/godot-project"
ADDON="$PROJECT/addons/godotsteam"
VERSION="${GODOTSTEAM_VERSION:-v4.19.1-gde}"
ZIP="godotsteam-4.19.1-gdextension-plugin-4.4.zip"
URL="https://codeberg.org/GodotSteam/GodotSteam/releases/download/${VERSION}/${ZIP}"

if [[ -f "$ADDON/godotsteam.gdextension" && "${GODOTSTEAM_FORCE:-0}" != "1" ]]; then
	echo "GodotSteam already installed at $ADDON (set GODOTSTEAM_FORCE=1 to reinstall)"
	exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading GodotSteam ${VERSION}..."
curl -fsSL -o "$tmpdir/$ZIP" "$URL"
mkdir -p "$PROJECT/addons"
unzip -q "$tmpdir/$ZIP" -d "$PROJECT"
echo "Installed GodotSteam to $ADDON"
