#!/usr/bin/env bash
# Live progress bar for steamcmd — pure bash (no Python / no IDE analysis).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "$ROOT/depot_ids.env" ]] && source "$ROOT/depot_ids.env"

depot_name() {
	case "$1" in
		"${STEAM_DEPOT_WINDOWS:-}") echo "Windows" ;;
		"${STEAM_DEPOT_LINUX:-}") echo "Linux" ;;
		"${STEAM_DEPOT_MACOS:-}") echo "macOS" ;;
		*) echo "depot $1" ;;
	esac
}

BAR_W=44
phase="starting"
pct=0
detail=""
in_xfer=0
started=$SECONDS
last_tick=$SECONDS

bar() {
	local p=$1 f
	p=$((p < 0 ? 0 : (p > 100 ? 100 : p)))
	f=$((p * BAR_W / 100))
	printf '\r  [%*s%-*s] %3d%%  %-12s %s' "$f" '' $((BAR_W - f)) '' "$p" "$phase" "$detail"
}

banner() {
	printf '\n%s\n  %s\n%s\n' "────────────────────────────────────────────────────────" "$1" "────────────────────────────────────────────────────────"
}

heartbeat() {
	local now=$SECONDS
	if (( now - last_tick >= 8 )); then
		printf '\n  … still running (%s, %ds elapsed)\n' "$phase" "$((now - started))"
		last_tick=$now
	fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
	printf '%s\n' "$line"

	if [[ "$line" == *"Successfully finished AppID"* && "$line" == *"BuildID"* ]]; then
		bid="${line##*BuildID }"; bid="${bid%%)*}"
		bar 100
		printf '\n'
		banner "Steam upload complete · BuildID ${bid} · $(( (SECONDS - started) / 60 ))m $(( (SECONDS - started) % 60 ))s"
		continue
	fi

	if [[ "$line" == *"Starting AppID"* && "$line" == *" build"* ]]; then
		banner "SteamPipe upload started"
		phase="packaging"
		pct=0
		in_xfer=0
		bar 0
		continue
	fi

	if [[ "$line" =~ Building\ depot\ ([0-9]+) ]]; then
		id="${BASH_REMATCH[1]}"
		phase="$(depot_name "$id")"
		pct=0
		detail=""
		in_xfer=0
		banner "Depot: $phase"
		bar 0
		continue
	fi

	if [[ "$line" == *"Scanning content"* ]]; then
		phase="scanning"
		pct=0
		in_xfer=1
		bar 0
		continue
	fi

	if [[ "$line" == *"Uploading content"* ]]; then
		phase="uploading"
		pct=0
		in_xfer=1
		bar 0
		continue
	fi

	if (( in_xfer )) && [[ "$line" =~ \(([0-9]+)%\) ]]; then
		pct="${BASH_REMATCH[1]}"
		if [[ "$line" =~ ([0-9.]+)\ MB ]]; then
			detail="${BASH_REMATCH[1]} MB"
		fi
		bar "$pct"
		last_tick=$SECONDS
		continue
	fi

	if [[ "$line" == *"Logging in using cached credentials"* \
		|| "$line" == *"Logged in OK"* \
		|| "$line" == *"Logging in user"* ]]; then
		phase="login"
		printf '  · %s\n' "$(echo "$line" | sed 's/^[[:space:]]*//')"
	fi

	heartbeat
done

printf '\n'
