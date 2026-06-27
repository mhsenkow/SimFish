#!/usr/bin/env bash
# Download the Guardian GGUF into the Godot project for Steam/desktop exports.
# The game loads this from res://assets/guardian/ — no runtime download needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/shaders-godot/godot-project/assets/guardian"
MODEL="SmolLM2-360M-Instruct-Q4_K_M.gguf"
URL="https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/${MODEL}"

mkdir -p "$DEST"
if [[ -f "$DEST/$MODEL" && "${GUARDIAN_MODEL_FORCE:-0}" != "1" ]]; then
	echo "Guardian model already present at $DEST/$MODEL"
	exit 0
fi

echo "Downloading Guardian model (~250MB) to $DEST/$MODEL ..."
curl -fsSL -o "$DEST/$MODEL" "$URL"
echo "Done."
