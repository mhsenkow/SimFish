#!/usr/bin/env bash
# Isolated Godot launcher for captures, probes, and smokes (HOLISTIC #001).
#
# Wraps scripts/godot.sh so a development run cannot mutate the player's real
# tank directory. Isolation is a scratch user-data name via override.cfg;
# any pre-existing override.cfg is merged and restored afterwards.
#
# Usage:
#   scripts/dev_run.sh --path shaders-godot/godot-project --headless --script res://dev/compile_check.gd
#   scripts/dev_run.sh res://dev/visual_capture.tscn
#   GODOT_ISOLATE=0 scripts/dev_run.sh ...   # escape hatch (not recommended)
#
# Environment:
#   GODOT_ISOLATE=1|0     default 1
#   GODOT_SCRATCH_NAME    custom_user_dir_name (default walstad_loom_dev_<pid>)
#   GODOT_VERIFY_TANKS=1  hash real tanks before/after and fail on change (default 1)
#   GODOT_BIN             forwarded to godot.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$ROOT/scripts/godot.sh"
PROJECT="$ROOT/shaders-godot/godot-project"
OVERRIDE="$PROJECT/override.cfg"
BACKUP=""
SCRATCH_ROOT="$ROOT/.scratch"
INVENTORY_DIR="$SCRATCH_ROOT/inventories"
REAL_TANKS="${GODOT_REAL_TANKS:-$HOME/Library/Application Support/Godot/app_userdata/walstad loom/tanks}"

ISOLATE="${GODOT_ISOLATE:-1}"
VERIFY="${GODOT_VERIFY_TANKS:-1}"
SCRATCH_NAME="${GODOT_SCRATCH_NAME:-walstad_loom_dev_$$}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"
BEFORE_INV=""
AFTER_INV=""

mkdir -p "$SCRATCH_ROOT" "$INVENTORY_DIR"

inventory_tanks() {
	local out="$1"
	{
		echo "# tank inventory $RUN_ID"
		echo "path=$REAL_TANKS"
		if [[ -d "$REAL_TANKS" ]]; then
			# Stable listing: path + size + mtime + content hash when small enough.
			# Large state.json files are hashed fully; the inventory itself is the
			# before/after contract for "player tanks unchanged".
			(
				cd "$REAL_TANKS"
				find . -type f | LC_ALL=C sort | while IFS= read -r f; do
					sz=$(wc -c <"$f" | tr -d ' ')
					mt=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f")
					hx=$(shasum -a 256 "$f" | awk '{print $1}')
					printf '%s\t%s\t%s\t%s\n' "$f" "$sz" "$mt" "$hx"
				done
			)
		else
			echo "(missing)"
		fi
	} >"$out"
}

merge_override() {
	# Preserve an existing override.cfg, then force the isolation keys.
	# Godot ConfigFile: later duplicate keys in the same section win, so we
	# append a final [application] block rather than parsing the whole file.
	if [[ -f "$OVERRIDE" ]]; then
		BACKUP="$SCRATCH_ROOT/override.bak.$RUN_ID"
		cp "$OVERRIDE" "$BACKUP"
		{
			cat "$BACKUP"
			echo
			echo "# walstad loom dev isolation (HOLISTIC #001) — managed by scripts/dev_run.sh"
			echo "[application]"
			echo "config/use_custom_user_dir=true"
			echo "config/custom_user_dir_name=\"$SCRATCH_NAME\""
		} >"$OVERRIDE"
	else
		{
			echo "# walstad loom dev isolation (HOLISTIC #001) — managed by scripts/dev_run.sh"
			echo "[application]"
			echo "config/use_custom_user_dir=true"
			echo "config/custom_user_dir_name=\"$SCRATCH_NAME\""
		} >"$OVERRIDE"
		BACKUP="__created__"
	fi
	echo "[dev_run] isolate user dir → $SCRATCH_NAME"
}

restore_override() {
	if [[ -z "$BACKUP" ]]; then
		return 0
	fi
	if [[ "$BACKUP" == "__created__" ]]; then
		rm -f "$OVERRIDE"
		echo "[dev_run] removed temporary override.cfg"
	elif [[ -f "$BACKUP" ]]; then
		mv "$BACKUP" "$OVERRIDE"
		echo "[dev_run] restored prior override.cfg"
	fi
}

cleanup() {
	local ec=$?
	restore_override || true
	if (( VERIFY )) && [[ -n "$BEFORE_INV" && -f "$BEFORE_INV" ]]; then
		AFTER_INV="$INVENTORY_DIR/${RUN_ID}_after.txt"
		inventory_tanks "$AFTER_INV"
		# Compare content hashes only (ignore mtime drift from listing).
		local b a
		b="$(grep -v '^#' "$BEFORE_INV" | grep -v '^path=' | awk -F'\t' '{print $1"\t"$4}' | LC_ALL=C sort)"
		a="$(grep -v '^#' "$AFTER_INV" | grep -v '^path=' | awk -F'\t' '{print $1"\t"$4}' | LC_ALL=C sort)"
		if [[ "$b" != "$a" ]]; then
			echo "[dev_run] FAIL: real tank directory changed during isolated run" >&2
			echo "  before: $BEFORE_INV" >&2
			echo "  after:  $AFTER_INV" >&2
			diff -u <(printf '%s\n' "$b") <(printf '%s\n' "$a") >&2 || true
			exit 1
		fi
		echo "[dev_run] tank inventory unchanged ($BEFORE_INV)"
	fi
	exit "$ec"
}

trap cleanup EXIT

if (( ISOLATE )); then
	if (( VERIFY )); then
		BEFORE_INV="$INVENTORY_DIR/${RUN_ID}_before.txt"
		inventory_tanks "$BEFORE_INV"
		echo "[dev_run] inventoried real tanks → $BEFORE_INV"
	fi
	merge_override
else
	echo "[dev_run] GODOT_ISOLATE=0 — using live user data (player tanks at risk)"
fi

# Distinct output hint for callers that write under user:// or output/.
export GODOT_DEV_RUN_ID="$RUN_ID"
export GODOT_DEV_SCRATCH_NAME="$SCRATCH_NAME"
export GODOT_DEV_OUT_ROOT="${GODOT_DEV_OUT_ROOT:-$ROOT/output/dev_runs/$RUN_ID}"
mkdir -p "$GODOT_DEV_OUT_ROOT"

# If caller did not already pin VISUAL_CAPTURE_OUT, give each run its own dir.
if [[ -z "${VISUAL_CAPTURE_OUT:-}" ]]; then
	export VISUAL_CAPTURE_OUT="$GODOT_DEV_OUT_ROOT/visual_capture"
fi

echo "[dev_run] out=$GODOT_DEV_OUT_ROOT"
# Prevent godot.sh from re-entering this script when GODOT_ISOLATE=1 is set.
export GODOT_VIA_DEV_RUN=1
# Do not exec — the EXIT trap must restore override.cfg and verify tanks.
set +e
"$GODOT" "$@"
ec=$?
set -e
exit "$ec"
