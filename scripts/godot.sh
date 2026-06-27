#!/usr/bin/env bash
# Resolve Godot CLI for headless smoke tests and agent shells.
# Cursor/CI shells often skip ~/.zshrc, so plain `godot` may be missing even
# when the Godot.app editor works from Finder or your own terminal.
set -euo pipefail

resolve_godot() {
	if [[ -n "${GODOT_BIN:-}" && -x "$GODOT_BIN" ]]; then
		echo "$GODOT_BIN"
		return 0
	fi
	local candidates=(
		"/Applications/Godot.app/Contents/MacOS/Godot"
		"$HOME/godot/Godot.app/Contents/MacOS/Godot"
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"
	)
	for c in "${candidates[@]}"; do
		if [[ -x "$c" ]]; then
			echo "$c"
			return 0
		fi
	done
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return 0
	fi
	echo "Godot not found. Set GODOT_BIN or install Godot.app." >&2
	return 1
}

GODOT="$(resolve_godot)"
exec "$GODOT" "$@"
