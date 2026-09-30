#!/usr/bin/env bash
# Zero-warnings gate for GDScript in scripts/ and dev/.
#
# Runs dev/compile_check.gd under --debug, which makes Godot print the editor's
# GDScript analyzer warnings (integer division, shadowed built-ins, unused
# locals, ...) to stderr as it compiles each script. Exits 1 if compile_check
# itself fails or if any WARNING points at a res://scripts/ or res://dev/ file.
#
# Deliberate cases take @warning_ignore("<code>") on the line/declaration,
# e.g. fish.gd's _learned_mind, which other modules reach through get()/set().
#
# Usage: ./scripts/check_warnings.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/shaders-godot/godot-project"
LOG="$(mktemp -t walstad_warnings.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

"$ROOT/scripts/godot.sh" --headless --debug --path "$PROJECT" \
	--script res://dev/compile_check.gd >"$LOG" 2>&1 </dev/null
rc=$?

# A WARNING line is followed by "   at: GDScript::reload (res://path.gd:LINE)".
warnings="$(awk '/^WARNING:/ { w = $0; if ((getline nxt) > 0 && nxt ~ /\(res:\/\/(scripts|dev)\//) { sub(/^[ \t]+/, "", nxt); print w " || " nxt } }' "$LOG" | sort -u)"

grep -E '^\[compile_check\]' "$LOG" || true
if [[ $rc -ne 0 ]]; then
	echo "[check_warnings] compile_check failed (exit $rc):" >&2
	grep -E 'FAILED|SCRIPT ERROR|Parse Error' "$LOG" >&2 || tail -40 "$LOG" >&2
	exit 1
fi
if [[ -n "$warnings" ]]; then
	n="$(printf '%s\n' "$warnings" | wc -l | tr -d ' ')"
	printf '%s\n' "$warnings" >&2
	echo "[check_warnings] $n GDScript warning(s) — fix them or add a targeted @warning_ignore" >&2
	exit 1
fi
echo "[check_warnings] 0 warnings"
