#!/usr/bin/env bash
# Thin resolver — prefer scripts/dev_run.sh for captures/probes/smokes.
#
# Isolation (HOLISTIC #001) lives in scripts/dev_run.sh so this file stays a
# pure Godot locator for CI and callers that already sandboxed themselves.
# When GODOT_ISOLATE=1 (default for interactive agent shells that export it),
# this re-enters through dev_run.sh once, then resolves the binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${GODOT_ISOLATE:-0}" == "1" && "${GODOT_VIA_DEV_RUN:-0}" != "1" ]]; then
	export GODOT_VIA_DEV_RUN=1
	exec "$ROOT/scripts/dev_run.sh" "$@"
fi

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
