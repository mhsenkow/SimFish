#!/usr/bin/env bash
# HOLISTIC #080 — five-state mature habitat capture series for one fixture.
# States: fresh | matured | biofilm | grazed_wipe | disturbed
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${ROOT}/output/visual_baselines/habitat_080_${STAMP}"
mkdir -p "${OUT}"
SCENARIO="${1:-valli_jungle}"
export VISUAL_CAPTURE_SCENARIO="${SCENARIO}"
export VISUAL_CAPTURE_ANGLES="${VISUAL_CAPTURE_ANGLES:-fit,close}"
export VISUAL_CAPTURE_DAY_PHASE="${VISUAL_CAPTURE_DAY_PHASE:-0.25}"

capture() {
  local state="$1"
  local cfg="${2:-}"
  export VISUAL_CAPTURE_OUT="${OUT}/${state}"
  mkdir -p "${VISUAL_CAPTURE_OUT}"
  if [[ -n "${cfg}" ]]; then
    export VISUAL_CAPTURE_CFG="${cfg}"
  else
    unset VISUAL_CAPTURE_CFG || true
  fi
  echo "== ${state} =="
  "${ROOT}/scripts/dev_run.sh" --headless --path shaders-godot/godot-project \
    --scene res://dev/visual_capture.tscn || true
}

capture fresh "start_matured=false"
capture matured "start_matured=true"
# Biofilm / graze / disturb rely on live tank age; matured cold-start approximates.
capture biofilm "start_matured=true"
capture grazed_wipe "start_matured=true"
capture disturbed "start_matured=true"

{
  echo "habitat_080 series scenario=${SCENARIO}"
  echo "states: fresh, matured, biofilm, grazed_wipe, disturbed"
  echo "out: ${OUT}"
  echo "Review: history should read through accumulated differences; oldest still leaves useful views of residents."
  ls -la "${OUT}" || true
} | tee "${OUT}/SUMMARY.txt"
echo "Wrote ${OUT}/SUMMARY.txt"
