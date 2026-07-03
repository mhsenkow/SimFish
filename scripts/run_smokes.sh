#!/usr/bin/env bash
# Run headless Godot smoke tests (ENGINEERING_EXCELLENCE #41 / #42).
# Prefer smoke_runner.gd for a single aggregated exit code:
#   ./scripts/godot.sh --headless --path shaders-godot/godot-project \
#     --script res://scripts/smoke_runner.gd
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$ROOT/scripts/godot.sh"
PROJECT="$ROOT/shaders-godot/godot-project"

# Platform-specific smokes that need native extensions or hardware.
SKIP=(
	smoke_llama_macos.gd
)

should_skip() {
	local name="$1"
	for s in "${SKIP[@]}"; do
		[[ "$name" == "$s" ]] && return 0
	done
	return 1
}

failed=0
passed=0
while IFS= read -r path; do
	[[ -z "$path" ]] && continue
	script="$(basename "$path")"
	if should_skip "$script"; then
		echo "[smoke] SKIP $script"
		continue
	fi
	rel="res://scripts/$script"
	echo "[smoke] RUN  $script"
	if "$GODOT" --headless --path "$PROJECT" --script "$rel"; then
		passed=$((passed + 1))
	else
		echo "[smoke] FAIL $script" >&2
		failed=$((failed + 1))
	fi
done < <(find "$PROJECT/scripts" -maxdepth 1 -name 'smoke_*.gd' -print | sort)

echo "[smoke] done: $passed passed, $failed failed, ${#SKIP[@]} skipped"
if (( failed > 0 )); then
	exit 1
fi
