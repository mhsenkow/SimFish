#!/usr/bin/env bash
# Copy llama.cpp runtime dylibs beside the exported godot_llama framework.
# Godot bundles the GDExtension framework but not libllama/libggml from bin/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/WalstadLoom.app}"
BIN="$ROOT/shaders-godot/godot-project/addons/godot_llama/bin"
FRAMEWORKS="$APP/Contents/Frameworks"

if [[ ! -d "$APP" ]]; then
	echo "Missing app bundle: $APP" >&2
	exit 1
fi
if [[ ! -d "$BIN" ]]; then
	echo "Run scripts/install_godot_llama.sh first." >&2
	exit 1
fi

mkdir -p "$FRAMEWORKS"
copied=0
for f in "$BIN"/lib*.0.dylib; do
	[[ -f "$f" ]] || continue
	cp -f "$f" "$FRAMEWORKS/"
	copied=$((copied + 1))
done
if [[ $copied -eq 0 ]]; then
	echo "No lib*.0.dylib in $BIN — skipping macOS llama bundle." >&2
	exit 0
fi
echo "Bundled $copied llama.cpp dylibs into $FRAMEWORKS"
