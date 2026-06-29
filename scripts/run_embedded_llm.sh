#!/usr/bin/env bash
# Local /api/generate shim for the Guardian embedded voice tier (#1).
# Exposes Ollama-compatible HTTP so AIDirector needs no changes — point
# Settings → AI → embedded endpoint at http://127.0.0.1:8080
#
# Prerequisites (one-time, opt-in download — not bundled in the base app):
#   1. llama.cpp built with server (`llama-server` on PATH), OR Ollama on a
#      second port with a small model pulled.
#   2. A ≤0.5B GGUF model, e.g. Qwen2.5-0.5B-Instruct Q4 (~400MB).
#
# Usage:
#   ./scripts/run_embedded_llm.sh /path/to/model.gguf
#   ./scripts/run_embedded_llm.sh   # uses $GUARDIAN_GGUF or prompts

set -euo pipefail

PORT="${GUARDIAN_LLM_PORT:-8080}"
HOST="${GUARDIAN_LLM_HOST:-127.0.0.1}"
MODEL_PATH="${1:-${GUARDIAN_GGUF:-}}"

if [[ -z "$MODEL_PATH" ]]; then
  echo "Usage: $0 /path/to/model.gguf" >&2
  echo "Or set GUARDIAN_GGUF to your downloaded GGUF path." >&2
  exit 1
fi

# SYSTEMIC #18 — warn before loading a 250MB+ model on low-RAM hosts.
MIN_FREE_MB="${GUARDIAN_LLM_MIN_FREE_MB:-2048}"
if command -v vm_stat >/dev/null 2>&1; then
  free_pages="$(vm_stat | awk '/Pages free/ {gsub("\\.", "", $3); print $3}')"
  page_size="$(vm_stat | awk '/page size/ {gsub(/[^0-9]/, "", $8); print $8}')"
  if [[ -n "$free_pages" && -n "$page_size" ]]; then
    free_mb=$((free_pages * page_size / 1024 / 1024))
    if (( free_mb < MIN_FREE_MB )); then
      echo "WARNING: only ~${free_mb}MB free RAM — embedded LLM needs ~${MIN_FREE_MB}MB+." >&2
    fi
  fi
elif [[ -r /proc/meminfo ]]; then
  free_mb="$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)"
  if [[ -n "$free_mb" ]] && (( free_mb < MIN_FREE_MB )); then
    echo "WARNING: only ~${free_mb}MB MemAvailable — embedded LLM needs ~${MIN_FREE_MB}MB+." >&2
  fi
fi

if ! [[ -f "$MODEL_PATH" ]]; then
  echo "Model not found: $MODEL_PATH" >&2
  exit 1
fi

if command -v llama-server >/dev/null 2>&1; then
  echo "Starting llama-server on ${HOST}:${PORT} (Ollama-compatible /api/generate)…"
  exec llama-server \
    --host "$HOST" \
    --port "$PORT" \
    --model "$MODEL_PATH" \
    --ctx-size 2048 \
    --parallel 1 \
    --cont-batching
fi

if command -v ollama >/dev/null 2>&1; then
  echo "llama-server not found — falling back to Ollama on port ${PORT}." >&2
  echo "Pull a small model first, e.g.: ollama pull qwen2.5:0.5b" >&2
  export OLLAMA_HOST="${HOST}:${PORT}"
  exec ollama serve
fi

echo "Neither llama-server nor ollama found on PATH." >&2
echo "Install llama.cpp (https://github.com/ggerganov/llama.cpp) or Ollama." >&2
exit 1
