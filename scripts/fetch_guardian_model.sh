#!/usr/bin/env bash
# Download the Guardian GGUF into the Godot project for Steam/desktop exports.
# The game loads this from res://assets/guardian/ — no runtime download needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/supply_chain/manifest.env
source "$ROOT/scripts/supply_chain/manifest.env"
# shellcheck source=scripts/supply_chain/verify_sha256.sh
source "$ROOT/scripts/supply_chain/verify_sha256.sh"

DEST="$ROOT/shaders-godot/godot-project/assets/guardian"
MODEL="$GUARDIAN_MODEL_FILENAME"
URL="https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/${MODEL}"

mkdir -p "$DEST"
if [[ -f "$DEST/$MODEL" && "${GUARDIAN_MODEL_FORCE:-0}" != "1" ]]; then
	if verify_sha256 "$DEST/$MODEL" "$GUARDIAN_MODEL_SHA256" "Guardian model"; then
		echo "Guardian model already present and verified at $DEST/$MODEL"
		exit 0
	fi
	echo "Existing Guardian model failed checksum — re-downloading…"
	rm -f "$DEST/$MODEL"
fi

echo "Downloading Guardian model (~250MB) to $DEST/$MODEL ..."
curl -fsSL -o "$DEST/$MODEL" "$URL"
verify_sha256 "$DEST/$MODEL" "$GUARDIAN_MODEL_SHA256" "Guardian model" 1
echo "Done (SHA256 verified)."
