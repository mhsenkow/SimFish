#!/usr/bin/env bash
# HOLISTIC #099 — matched behaviour-probe runs across render caps.
# Usage: ./scripts/fish_probe_fps_matrix.sh [scenario] [seed]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENARIO="${1:-valli_jungle}"
SEED="${2:-4242}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT}/output/fish_probe_matrix/${STAMP}"
mkdir -p "${OUT_DIR}"
export FISH_PROBE_SCENARIO="${SCENARIO}"
export FISH_PROBE_FIXED_SEED="${SEED}"
export FISH_PROBE_WARMUP_S="${FISH_PROBE_WARMUP_S:-12}"
export FISH_PROBE_SAMPLE_S="${FISH_PROBE_SAMPLE_S:-20}"
export FISH_PROBE_STOCK="${FISH_PROBE_STOCK:-guppy:8,glassdart:10,corydoras:4,betta:2}"

for FPS in 30 60 0; do
  LABEL="fps${FPS}"
  export FISH_PROBE_MAX_FPS="${FPS}"
  export FISH_PROBE_TIME_SCALE=1
  export FISH_PROBE_OUT="${OUT_DIR}/${LABEL}.txt"
  echo "== ${LABEL} =="
  "${ROOT}/scripts/dev_run.sh" --headless --path shaders-godot/godot-project \
    --scene res://dev/fish_behaviour_probe.tscn || true
done

export FISH_PROBE_MAX_FPS=60
export FISH_PROBE_TIME_SCALE=4
export FISH_PROBE_OUT="${OUT_DIR}/fps60_ts4.txt"
echo "== fps60_ts4 =="
"${ROOT}/scripts/dev_run.sh" --headless --path shaders-godot/godot-project \
  --scene res://dev/fish_behaviour_probe.tscn || true

{
  echo "fish_probe_fps_matrix scenario=${SCENARIO} seed=${SEED}"
  echo "tolerated: dart% ±8pp; path_len_xz ±12%; tank_age_delta ≈ sample_sim_s"
  echo "artifacts: ${OUT_DIR}"
  for f in "${OUT_DIR}"/*.txt; do
    echo "--- $(basename "$f") ---"
    grep -E '^(fish_behaviour_probe|holistic_099|frame_ms)' "$f" || true
  done
} | tee "${OUT_DIR}/SUMMARY.txt"
echo "Wrote ${OUT_DIR}/SUMMARY.txt"
