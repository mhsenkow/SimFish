#!/usr/bin/env bash
# Performance budget by workload (HOLISTIC #013).
#
# Runs dev/perf_workload_probe.tscn through scripts/dev_run.sh for default,
# dense, mature, and interaction-heavy tanks. Records p50/p95/p99, hardware,
# cap, tier, draw calls, entities, and main-thread spikes via PerfGovernor.
#
# Usage:
#   scripts/perf_workload_baseline.sh
#   PERF_WORKLOADS=default,dense scripts/perf_workload_baseline.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${PERF_BASELINE_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="${PERF_BASELINE_OUT:-$ROOT/output/perf_baselines/$STAMP}"
WORKLOADS_CSV="${PERF_WORKLOADS:-default,dense,mature,interaction}"
SAMPLE_S="${PERF_SAMPLE_S:-8}"
mkdir -p "$OUT"

export PERF_PROBE_OUT="$OUT"
export PERF_PROBE_SAMPLE_S="$SAMPLE_S"
export PERF_PROBE_WORKLOADS="$WORKLOADS_CSV"
export GODOT_SCRATCH_NAME="walstad_loom_perf_baseline_$$"
export GODOT_DEV_OUT_ROOT="$OUT/dev_run"

echo "[perf_baseline] out=$OUT workloads=$WORKLOADS_CSV sample=${SAMPLE_S}s"
"$ROOT/scripts/dev_run.sh" --path "$ROOT/shaders-godot/godot-project" \
	res://dev/perf_workload_probe.tscn

{
	echo "# Perf workload baselines"
	echo
	echo "- stamp: \`$STAMP\`"
	echo "- commit: \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
	echo "- workloads: \`$WORKLOADS_CSV\`"
	echo
	echo "Machine-specific: these numbers do not represent low-end devices."
	echo "See \`report.json\` / \`SUMMARY.md\` written by the probe."
} >"$OUT/WRAPPER.md"

echo "[perf_baseline] wrote $OUT"
ls -la "$OUT" | head -40
