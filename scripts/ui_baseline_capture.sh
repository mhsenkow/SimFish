#!/usr/bin/env bash
# UI layout baseline (HOLISTIC #007).
#
# Runs dev/ui_capture.tscn for wide + narrow logical viewports through
# scripts/dev_run.sh, saving overlap / focus / Escape reports.
#
# Usage:
#   scripts/ui_baseline_capture.sh
#   UI_CAPTURE_STATES=baseline,care scripts/ui_baseline_capture.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${UI_BASELINE_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="${UI_BASELINE_OUT:-$ROOT/output/ui_baselines/$STAMP}"
mkdir -p "$OUT"

export UI_CAPTURE_OUT="$OUT"
export UI_CAPTURE_PASSES="${UI_CAPTURE_PASSES:-1152x648,900x600}"
export GODOT_SCRATCH_NAME="walstad_loom_ui_baseline_$$"
export GODOT_DEV_OUT_ROOT="$OUT/dev_run"

echo "[ui_baseline] out=$OUT passes=$UI_CAPTURE_PASSES"
"$ROOT/scripts/dev_run.sh" --path "$ROOT/shaders-godot/godot-project" \
	res://dev/ui_capture.tscn

{
	echo "# UI layout baseline"
	echo
	echo "- stamp: \`$STAMP\`"
	echo "- commit: \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
	echo "- passes: \`$UI_CAPTURE_PASSES\`"
	echo
	echo "Reports: \`report_*.txt\` / \`report_*.json\` in this directory."
	echo "Remaining overlaps after the harness baseline are marked \`new=1\`."
} >"$OUT/SUMMARY.md"

echo "[ui_baseline] wrote $OUT/SUMMARY.md"
ls -la "$OUT" | head -40
