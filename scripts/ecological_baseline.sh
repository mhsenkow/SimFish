#!/usr/bin/env bash
# Ecological trajectory baselines (HOLISTIC #006).
#
# Runs dev/balance_soak.tscn in trajectories mode through scripts/dev_run.sh
# for fresh / established / sparse / dense / reef cases. Reports include
# nitrogen, oxygen minima, births, deaths, biomass, and recovery after one
# feed pulse. Conclusions note sampled seeds ≠ universal guarantees.
#
# Usage:
#   scripts/ecological_baseline.sh
#   BALANCE_DAYS=2 BALANCE_TRAJECTORY=reef scripts/ecological_baseline.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${ECO_BASELINE_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="${ECO_BASELINE_OUT:-$ROOT/output/ecological_baselines/$STAMP}"
mkdir -p "$OUT"

export BALANCE_MODE="${BALANCE_MODE:-trajectories}"
export BALANCE_DAYS="${BALANCE_DAYS:-2}"
export BALANCE_FEED_PULSE="${BALANCE_FEED_PULSE:-1}"
export BALANCE_OUT="$OUT"
export BALANCE_SEED="${BALANCE_SEED:-305419896}"
export GODOT_SCRATCH_NAME="walstad_loom_eco_baseline_$$"
export GODOT_DEV_OUT_ROOT="$OUT/dev_run"

echo "[eco_baseline] out=$OUT mode=$BALANCE_MODE days=$BALANCE_DAYS seed=$BALANCE_SEED"
"$ROOT/scripts/dev_run.sh" --path "$ROOT/shaders-godot/godot-project" --headless \
	res://dev/balance_soak.tscn

{
	echo "# Ecological baselines wrapper"
	echo
	echo "- stamp: \`$STAMP\`"
	echo "- commit: \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
	echo "- mode: \`$BALANCE_MODE\` days: \`$BALANCE_DAYS\` seed: \`$BALANCE_SEED\`"
	echo
	echo "See \`SUMMARY.md\` and per-trajectory JSON in this directory."
	echo "Sampled seeds are not universal guarantees."
} >"$OUT/WRAPPER.md"

echo "[eco_baseline] wrote $OUT"
ls -la "$OUT" | head -40
