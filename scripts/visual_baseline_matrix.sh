#!/usr/bin/env bash
# Visual baseline matrix (HOLISTIC #002).
#
# Captures beginner, Valli, blackwater, reef, and a nonrectangular tank at day
# and night through the real main.tscn path, writing comparable fit + close
# images plus meta.json (seed, tier, resolution, clock, build, settle).
#
# Improves on the one-off holistic_review_20261001 sample by:
#   - covering five scenarios × two clocks instead of a single Valli midday
#   - always recording meta.json beside metrics.txt
#   - routing through scripts/dev_run.sh so the player's tanks stay untouched
#   - grading with camera-intent profiles (HOLISTIC #003)
#
# Usage:
#   scripts/visual_baseline_matrix.sh
#   VISUAL_BASELINE_SETTLE=360 scripts/visual_baseline_matrix.sh
#   VISUAL_BASELINE_SCENARIOS="valli_jungle,hex_jungle" scripts/visual_baseline_matrix.sh
#
# Output: output/visual_baselines/<stamp>/<scenario>/<day|night>/{fit,close}.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV_RUN="$ROOT/scripts/dev_run.sh"
PROJECT="$ROOT/shaders-godot/godot-project"
STAMP="${VISUAL_BASELINE_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_ROOT="${VISUAL_BASELINE_OUT:-$ROOT/output/visual_baselines/$STAMP}"
SETTLE="${VISUAL_BASELINE_SETTLE:-360}"
ANGLES="${VISUAL_BASELINE_ANGLES:-fit,close}"
SCENARIOS_CSV="${VISUAL_BASELINE_SCENARIOS:-beginner_sandbox,valli_jungle,blackwater,reef,hex_jungle}"
PHASES_CSV="${VISUAL_BASELINE_PHASES:-day:0.25,night:0.75}"

mkdir -p "$OUT_ROOT"
SUMMARY="$OUT_ROOT/SUMMARY.md"
{
	echo "# Visual baseline matrix"
	echo
	echo "- stamp: \`$STAMP\`"
	echo "- settle frames: \`$SETTLE\`"
	echo "- angles: \`$ANGLES\`"
	echo "- commit: \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
	echo
	echo "| Scenario | Phase | Dir | Notes |"
	echo "|---|---|---|---|"
} >"$SUMMARY"

IFS=',' read -r -a SCENARIOS <<<"$SCENARIOS_CSV"
IFS=',' read -r -a PHASE_SPECS <<<"$PHASES_CSV"

echo "[visual_baseline] out=$OUT_ROOT scenarios=${#SCENARIOS[@]} phases=${#PHASE_SPECS[@]}"

for scenario in "${SCENARIOS[@]}"; do
	scenario="$(echo "$scenario" | tr -d '[:space:]')"
	[[ -z "$scenario" ]] && continue
	for spec in "${PHASE_SPECS[@]}"; do
		spec="$(echo "$spec" | tr -d '[:space:]')"
		name="${spec%%:*}"
		phase="${spec##*:}"
		cell="$OUT_ROOT/$scenario/$name"
		mkdir -p "$cell"
		echo "[visual_baseline] $scenario $name (day_phase=$phase) → $cell"
		# Absolute filesystem path: visual_capture accepts user:// or absolute.
		export VISUAL_CAPTURE_OUT="$cell"
		export VISUAL_CAPTURE_SCENARIO="$scenario"
		export VISUAL_CAPTURE_DAY_PHASE="$phase"
		export VISUAL_CAPTURE_SETTLE="$SETTLE"
		export VISUAL_CAPTURE_ANGLES="$ANGLES"
		export GODOT_SCRATCH_NAME="walstad_loom_baseline_${scenario}_${name}_$$"
		export GODOT_DEV_OUT_ROOT="$cell/dev_run"
		set +e
		"$DEV_RUN" --path "$PROJECT" res://dev/visual_capture.tscn
		ec=$?
		set -e
		note="ok"
		if (( ec != 0 )); then
			note="exit $ec"
		elif [[ ! -f "$cell/metrics.txt" ]]; then
			note="missing metrics"
		else
			fails="$(grep -c 'FAIL' "$cell/metrics.txt" || true)"
			note="$fails FAIL lines"
		fi
		echo "| \`$scenario\` | \`$name\` ($phase) | \`$scenario/$name\` | $note |" >>"$SUMMARY"
	done
done

{
	echo
	echo "## How to read"
	echo
	echo "Each cell has \`fit.png\`, \`close.png\`, \`metrics.txt\`, and \`meta.json\`."
	echo "Grades use camera-intent profiles from \`frame_metrics.view_profile\`:"
	echo "close views do not fail solely on the hero-view shadow floor."
	echo
	echo "Re-run a single cell:"
	echo
	echo '```bash'
	echo "VISUAL_BASELINE_SCENARIOS=valli_jungle VISUAL_BASELINE_PHASES=day:0.25 \\"
	echo "  scripts/visual_baseline_matrix.sh"
	echo '```'
} >>"$SUMMARY"

echo "[visual_baseline] wrote $SUMMARY"
cat "$SUMMARY"
