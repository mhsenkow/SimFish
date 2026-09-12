#!/usr/bin/env bash
# Headless smoke runner (BROAD_DIRECTIONS #10).
#
# Replaces the serial version, which booted Godot once per smoke, in
# sequence, with no per-script timeout. At 155 smokes that was >10 minutes
# and, as AGENTS.md warned, a single slow soak (smoke_tank_balance) could
# stall an unattended run forever.
#
# This runner:
#   - runs N smokes in parallel (default: CPU count, capped at 8), except
#     the timing-sensitive perf smokes, which run serially afterwards
#   - enforces a per-script timeout so one hang cannot wedge the suite
#   - supports CI sharding: --shard 2/4 runs the second quarter
#   - keeps each smoke's output in its own log, printed only on failure
#   - reports TIMEOUT separately from FAIL, because they need different fixes
#   - honours scripts/smoke_baseline.txt: a KNOWN failure does not fail the
#     run, but a NEW failure does — and so does a baselined smoke that
#     starts passing, so stale entries get deleted instead of accumulating
#
# Usage:
#   scripts/run_smokes.sh                      # everything, auto parallelism
#   scripts/run_smokes.sh -j4 --timeout 120    # 4 jobs, 120s per script
#   scripts/run_smokes.sh --shard 1/4          # CI shard
#   scripts/run_smokes.sh --include save       # only smokes matching "save"
#   scripts/run_smokes.sh --slow               # ALSO run the slow soaks
#   scripts/run_smokes.sh --strict             # ignore the baseline; fail on any
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$ROOT/scripts/godot.sh"
PROJECT="$ROOT/shaders-godot/godot-project"
LOGDIR="${SMOKE_LOG_DIR:-$ROOT/.smoke-logs}"
BASELINE="$ROOT/scripts/smoke_baseline.txt"

# Needs native extensions or physical hardware — never runnable in CI.
SKIP_ALWAYS=(
	smoke_runner.gd          # runs the others; would recurse
	smoke_llama_macos.gd     # needs the godot_llama extension built
	smoke_gamepad_live.gd    # asserts a physical pad is connected
	smoke_joypad_probe.gd    # same
)

# Correct but slow (ecology soaks). Excluded by default, run with --slow.
# These are the scripts the old runner could hang on.
SKIP_SLOW=(
	smoke_tank_balance.gd
)

# Timing-sensitive: these MEASURE wall-clock, so a parallel run starves them
# and they fail their own budget. smoke_perf_contract sits at ~460 ms against
# a 490 ms ceiling with the machine idle — sharing 8 ways guarantees a false
# failure. Run after the parallel batch, one at a time.
SERIAL_ONLY=(
	smoke_perf_contract.gd
	smoke_perf_realtime.gd
	smoke_shader_perf.gd
	smoke_motion_topo_perf.gd
	smoke_frame_budget.gd
)

JOBS="$( (command -v sysctl >/dev/null && sysctl -n hw.ncpu) || nproc || echo 4 )"
(( JOBS > 8 )) && JOBS=8
TIMEOUT=180
SHARD_I=1
SHARD_N=1
INCLUDE=""
RUN_SLOW=0

while (( $# )); do
	case "$1" in
		-j*)            JOBS="${1#-j}"; shift ;;
		--jobs)         JOBS="$2"; shift 2 ;;
		--timeout)      TIMEOUT="$2"; shift 2 ;;
		--include)      INCLUDE="$2"; shift 2 ;;
		--slow)         RUN_SLOW=1; shift ;;
		--shard)        SHARD_I="${2%%/*}"; SHARD_N="${2##*/}"; shift 2 ;;
		--strict)       BASELINE=""; shift ;;
		-h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

should_skip() {
	local name="$1" s
	for s in "${SKIP_ALWAYS[@]}"; do [[ "$name" == "$s" ]] && return 0; done
	if (( ! RUN_SLOW )); then
		for s in "${SKIP_SLOW[@]}"; do [[ "$name" == "$s" ]] && return 0; done
	fi
	return 1
}

# macOS ships no coreutils `timeout`. perl's alarm is present everywhere and
# exits 142 on SIGALRM, which is how a hang is told apart from a failure.
run_one() {
	local script="$1"
	local log="$LOGDIR/${script%.gd}.log"
	# Backgrounded + explicit wait so the shell does not print its own
	# "Alarm clock: 14" job-control notice when the alarm fires.
	perl -e 'alarm shift; exec @ARGV or exit 127' \
		"$TIMEOUT" "$GODOT" --headless --path "$PROJECT" \
		--script "res://scripts/$script" >"$log" 2>&1 &
	local pid=$!
	wait "$pid" 2>/dev/null
	local rc=$?
	if (( rc == 0 )); then
		echo "PASS $script"
	elif (( rc == 142 )); then
		echo "TIMEOUT $script"
	else
		echo "FAIL $script rc=$rc"
	fi
}

is_serial_only() {
	local name="$1" s
	for s in "${SERIAL_ONLY[@]}"; do [[ "$name" == "$s" ]] && return 0; done
	return 1
}

is_baselined() {
	[[ -z "$BASELINE" || ! -f "$BASELINE" ]] && return 1
	grep -qxF "$1" <(grep -vE '^[[:space:]]*(#|$)' "$BASELINE")
}

mkdir -p "$LOGDIR"
rm -f "$LOGDIR"/*.log 2>/dev/null

# Collect, filter, shard.
all=()
while IFS= read -r path; do
	name="$(basename "$path")"
	should_skip "$name" && continue
	[[ -n "$INCLUDE" && "$name" != *"$INCLUDE"* ]] && continue
	all+=("$name")
done < <(find "$PROJECT/scripts" -maxdepth 1 -name 'smoke_*.gd' -print | sort)

selected=()
for i in "${!all[@]}"; do
	if (( i % SHARD_N == SHARD_I - 1 )); then
		selected+=("${all[$i]}")
	fi
done

par_group=()
ser_group=()
for script in ${selected[@]+"${selected[@]}"}; do
	if is_serial_only "$script"; then
		ser_group+=("$script")
	else
		par_group+=("$script")
	fi
done

total=${#selected[@]-0}
if (( total == 0 )); then
	echo "[smoke] nothing to run (include='$INCLUDE' shard=$SHARD_I/$SHARD_N)"
	exit 0
fi

echo "[smoke] $total scripts (${#par_group[@]-0} parallel, ${#ser_group[@]-0} serial) · ${JOBS} jobs · ${TIMEOUT}s timeout · shard ${SHARD_I}/${SHARD_N}"
started=$(date +%s)

# Fan out, bounded by $JOBS.
results_file="$(mktemp)"
running=0
for script in ${par_group[@]+"${par_group[@]}"}; do
	run_one "$script" >>"$results_file" &
	running=$(( running + 1 ))
	if (( running >= JOBS )); then
		wait -n 2>/dev/null || wait
		running=$(( running - 1 ))
	fi
done
wait

# Then the timing-sensitive ones, alone, on a quiet machine.
for script in ${ser_group[@]+"${ser_group[@]}"}; do
	run_one "$script" >>"$results_file"
done

elapsed=$(( $(date +%s) - started ))

passed=$(grep -c '^PASS ' "$results_file" || true)
timedout=$(grep -c '^TIMEOUT ' "$results_file" || true)

# Split failures into NEW (gate-breaking) and KNOWN (baselined).
new_failures=()
known_failures=()
while read -r line; do
	[[ -z "$line" ]] && continue
	set -- $line
	script="$2"
	if is_baselined "$script"; then
		known_failures+=("$script")
	else
		new_failures+=("$script")
	fi
done < <(grep -E '^(FAIL|TIMEOUT) ' "$results_file" || true)

# A baselined smoke that now PASSES means the entry is stale. Fail the run,
# so the holding pen drains instead of growing.
fixed=()
while read -r line; do
	[[ -z "$line" ]] && continue
	set -- $line
	script="$2"
	if is_baselined "$script"; then
		fixed+=("$script")
	fi
done < <(grep -E '^PASS ' "$results_file" || true)

# Print NEW failures with output. Known ones are listed by name only —
# their logs are on disk if wanted, but they are not today's news.
if (( ${#new_failures[@]-0} > 0 )); then
	echo
	for script in ${new_failures[@]+"${new_failures[@]}"}; do
		echo "──── NEW FAILURE $script ────"
		tail -25 "$LOGDIR/${script%.gd}.log" | sed 's/^/  /'
		echo
	done
fi
if (( ${#known_failures[@]-0} > 0 )); then
	echo "[smoke] known failures (scripts/smoke_baseline.txt): ${known_failures[*]-}"
fi
if (( ${#fixed[@]-0} > 0 )); then
	echo "[smoke] these are BASELINED BUT NOW PASSING — delete them from" >&2
	echo "[smoke] scripts/smoke_baseline.txt: ${fixed[*]-}" >&2
fi

echo "[smoke] ${elapsed}s: $passed passed, ${#new_failures[@]-0} new failures, ${#known_failures[@]-0} known, $timedout timed out (of $total)"
echo "[smoke] logs: $LOGDIR"
rm -f "$results_file"
if (( ${#new_failures[@]-0} > 0 || ${#fixed[@]-0} > 0 )); then
	exit 1
fi
exit 0
