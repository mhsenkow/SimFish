#!/usr/bin/env bash
# Audio reference set (HOLISTIC #009).
#
# Wraps dev/audio_probe.tscn via scripts/dev_run.sh for healthy, stressed,
# day, night, full, and simple beds. Copies listenable WAVs and peak/RMS/
# silence measurements under output/audio_baselines/.
#
# Usage:
#   scripts/audio_baseline.sh
#   AUDIO_BASELINE_SECONDS=8 scripts/audio_baseline.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${AUDIO_BASELINE_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="${AUDIO_BASELINE_OUT:-$ROOT/output/audio_baselines/$STAMP}"
SECONDS_N="${AUDIO_BASELINE_SECONDS:-12}"
mkdir -p "$OUT"

# name|cmdline user args after --
CASES=(
	"healthy|state=healthy"
	"stressed|state=stressed"
	"day|state=healthy daylight=1.0"
	"night|state=healthy daylight=0.12"
	"full|state=healthy fullbed"
	"simple|state=healthy simplebed"
)

SUMMARY="$OUT/SUMMARY.md"
{
	echo "# Audio baselines"
	echo
	echo "- stamp: \`$STAMP\`"
	echo "- seconds: \`$SECONDS_N\`"
	echo "- commit: \`$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)\`"
	echo
	echo "| Case | Peak dBFS | RMS dBFS | Silence | WAV |"
	echo "|---|---|---|---|---|"
} >"$SUMMARY"

echo "[audio_baseline] out=$OUT cases=${#CASES[@]}"

for spec in "${CASES[@]}"; do
	name="${spec%%|*}"
	args="${spec#*|}"
	cell="$OUT/$name"
	mkdir -p "$cell"
	export GODOT_SCRATCH_NAME="walstad_loom_audio_${name}_$$"
	export GODOT_DEV_OUT_ROOT="$cell/dev_run"
	export AUDIO_PROBE_OUT="$cell"
	echo "[audio_baseline] $name → $cell ($args)"
	set +e
	# shellcheck disable=SC2086
	"$ROOT/scripts/dev_run.sh" --path "$ROOT/shaders-godot/godot-project" --headless \
		res://dev/audio_probe.tscn -- seconds="$SECONDS_N" out="$name" $args \
		> "$cell/probe.log" 2>&1
	ec=$?
	set -e
	peak="$(rg -N '\[audio\] mix\s+peak' "$cell/probe.log" | tail -1 | awk '{print $4}' || true)"
	rms="$(rg -N '\[audio\] mix\s+peak' "$cell/probe.log" | tail -1 | awk '{print $7}' || true)"
	sil="$(rg -N 'silence_frac|silence' "$cell/probe.log" | tail -1 || true)"
	[[ -z "$peak" ]] && peak="n/a"
	[[ -z "$rms" ]] && rms="n/a"
	[[ -z "$sil" ]] && sil="see probe.log"
	wav="missing"
	if ls "$cell"/*.wav >/dev/null 2>&1; then
		wav="$(ls "$cell"/*.wav | head -1 | xargs basename)"
	fi
	note="ok"
	(( ec != 0 )) && note="exit $ec"
	echo "| $name | $peak | $rms | $sil | \`$wav\` ($note) |" >>"$SUMMARY"
done

echo "[audio_baseline] wrote $SUMMARY"
ls -la "$OUT" | head -40
