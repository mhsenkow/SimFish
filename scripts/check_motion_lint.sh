#!/usr/bin/env bash
# Motion lint (CREATURE_MOTION_700 #115). Two habits made creature motion
# depend on the frame rate or run on a clock that ignores the creature:
#
#   1. lerp(a, b, dt * k) smoothing: overshoots once dt*k > 1 and looks
#      different at 30, 60 and 144 Hz. New code uses MotionEase.damp() or
#      lerp(a, b, 1.0 - exp(-dt * k)).
#   2. sin(TIME * k) / cos(TIME * k) in fauna shaders: every animal on one
#      global clock, including sleeping and dead ones. New motion reads a
#      per-instance phase.
#
# Existing uses are counted in scripts/motion_lint_baseline.txt. The check
# fails when a file goes ABOVE its baseline, so the count can only go down.
# After removing uses, lower the baseline with:  scripts/check_motion_lint.sh --update
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$ROOT/shaders-godot/godot-project"
BASELINE="$ROOT/scripts/motion_lint_baseline.txt"

GD_FILES=(
	scripts/fish.gd scripts/shrimp.gd scripts/snail.gd scripts/trumpet_snail.gd
	scripts/wriggle_worm.gd scripts/bristle_worm.gd scripts/sea_cucumber.gd
	scripts/tubifex_patch.gd scripts/clam.gd scripts/coral.gd scripts/egg.gd
	scripts/snail_egg.gd scripts/microfauna_swarm.gd scripts/fish_life_bouts.gd
	scripts/fish_alive.gd scripts/fish_locomotion.gd scripts/hydrodynamics.gd
)
SHADERS=(shaders/voxel_fauna_mm.gdshader)

count() {
	local file="$1" kind="$2"
	[[ -f "$PROJ/$file" ]] || { echo 0; return; }
	if [[ "$kind" == lerp ]]; then
		# A lerp whose weight is dt * k, but not the exp(-dt * k) form.
		perl -ne '$n++ if /lerpf?\(/ && /(?<!exp\(-)(?<![.\w])s?dt \* [0-9]/; END { print $n + 0, "\n" }' "$PROJ/$file"
	else
		grep -cE '(sin|cos)\(TIME' "$PROJ/$file" || true
	fi
}

current() {
	for f in "${GD_FILES[@]}"; do echo "lerp $f $(count "$f" lerp)"; done
	for f in "${SHADERS[@]}"; do echo "time $f $(count "$f" time)"; done
}

if [[ "${1:-}" == "--update" ]]; then
	current > "$BASELINE"
	echo "[motion_lint] baseline written: $BASELINE"
	exit 0
fi

[[ -f "$BASELINE" ]] || { echo "[motion_lint] missing $BASELINE (run with --update)" >&2; exit 2; }
fail=0
while read -r kind file n; do
	base="$(awk -v k="$kind" -v f="$file" '$1==k && $2==f {print $3}' "$BASELINE")"
	base="${base:-0}"
	if (( n > base )); then
		echo "[motion_lint] $file: $n frame-rate-dependent ${kind} uses (baseline $base)" >&2
		fail=1
	fi
done < <(current)
if (( fail )); then
	echo "[motion_lint] use MotionEase.damp() / 1.0 - exp(-dt * k), or a per-instance phase" >&2
	exit 1
fi
echo "[motion_lint] ok"
