#!/usr/bin/env bash
# Upload staged content to Steam via steamcmd.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${1:-$ROOT/depot_ids.env}"
LOG="${STEAM_UPLOAD_LOG:-$ROOT/output/steam_upload.log}"
VIZ="$ROOT/upload_viz.sh"

if [[ ! -f "$ENV_FILE" ]]; then
	echo "Copy depot_ids.env.example to depot_ids.env and set your depot IDs." >&2
	exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

for var in STEAM_APP_ID STEAM_DEPOT_WINDOWS STEAM_DEPOT_LINUX STEAM_DEPOT_MACOS; do
	if [[ -z "${!var:-}" ]]; then
		echo "Set $var in $ENV_FILE" >&2
		exit 1
	fi
done

STEAM_USERNAME="${STEAM_USERNAME:-}"
if [[ -z "$STEAM_USERNAME" ]]; then
	echo "Set STEAM_USERNAME in the environment (your Steamworks partner account)." >&2
	exit 1
fi
STEAM_SETLIVE="${STEAM_SETLIVE:-}"

if ! command -v steamcmd >/dev/null 2>&1; then
	echo "Install steamcmd first: https://partner.steamgames.com/doc/sdk/uploading" >&2
	exit 1
fi

"$ROOT/stage_content.sh"

gen_vdf() {
	local template="$1" out="$2"
	sed \
		-e "s/@STEAM_APP_ID@/$STEAM_APP_ID/g" \
		-e "s/@STEAM_DEPOT_WINDOWS@/$STEAM_DEPOT_WINDOWS/g" \
		-e "s/@STEAM_DEPOT_LINUX@/$STEAM_DEPOT_LINUX/g" \
		-e "s/@STEAM_DEPOT_MACOS@/$STEAM_DEPOT_MACOS/g" \
		-e "s/@STEAM_SETLIVE@/$STEAM_SETLIVE/g" \
		"$template" > "$out"
}

mkdir -p "$ROOT/output"
: >"$LOG"
gen_vdf "$ROOT/app_build.vdf.template" "$ROOT/app_build.vdf"
gen_vdf "$ROOT/depot_build_win.vdf.template" "$ROOT/depot_build_win.vdf"
gen_vdf "$ROOT/depot_build_linux.vdf.template" "$ROOT/depot_build_linux.vdf"
gen_vdf "$ROOT/depot_build_mac.vdf.template" "$ROOT/depot_build_mac.vdf"

prompt_hidden() {
	local title="$1"
	if [[ -t 0 ]]; then
		echo -n "${title} "
		read -rs password
		echo
		printf '%s' "$password"
		return
	fi
	osascript -e "display dialog \"${title}\" default answer \"\" with hidden answer" \
		-e 'text returned of result' 2>/dev/null || true
}

prompt_text() {
	local title="$1"
	if [[ -t 0 ]]; then
		echo -n "${title} "
		read -r guard
		printf '%s' "$guard"
		return
	fi
	osascript -e "display dialog \"${title}\" default answer \"\"" \
		-e 'text returned of result' 2>/dev/null || true
}

# macOS: fake a TTY so steamcmd flushes lines (piped uploads otherwise look frozen).
run_steamcmd() {
	if [[ "$(uname -s)" == "Darwin" ]] && command -v script >/dev/null 2>&1; then
		script -q /dev/null steamcmd "$@"
	else
		steamcmd "$@"
	fi
}

run_upload_live() {
	local user="$1" pass="${2:-}" guard="${3:-}"
	local -a args=()
	if [[ -n "$guard" ]]; then
		args+=(+set_steam_guard_code "$guard")
	fi
	if [[ -n "$pass" ]]; then
		args+=(+login "$user" "$pass")
	else
		args+=(+login "$user")
	fi
	args+=(+run_app_build "$ROOT/app_build.vdf" +quit)

	echo ""
	echo "╔══════════════════════════════════════════════════════╗"
	echo "║  walstad loom  →  Steam  (~${total_mb} MB · 3 depots)      ║"
	echo "║  Progress bar below · log: steam/output/steam_upload.log ║"
	echo "╚══════════════════════════════════════════════════════╝"
	echo ""

	set -o pipefail
	if [[ -t 1 && -x "$VIZ" ]]; then
		run_steamcmd "${args[@]}" 2>&1 | tee -a "$LOG" | bash "$VIZ"
	else
		run_steamcmd "${args[@]}" 2>&1 | tee -a "$LOG"
	fi
	return "${PIPESTATUS[0]}"
}

password="${STEAM_PASSWORD:-}"
guard="${STEAM_GUARD_CODE:-}"
total_mb="$(du -sm "$ROOT/content" 2>/dev/null | awk '{print $1}')"
echo "Uploading AppID $STEAM_APP_ID as $STEAM_USERNAME (branch: ${STEAM_SETLIVE:-draft})."

if [[ -z "$password" ]]; then
	echo "Using cached steamcmd login (run ./steam/login_once.sh if this fails)."
fi

set +e
run_upload_live "$STEAM_USERNAME" "$password" "$guard"
status=$?
set -e

if [[ $status -ne 0 ]]; then
	if grep -q "Cached credentials not found" "$LOG" 2>/dev/null && [[ -z "$password" ]]; then
		echo "Need password."
		password="$(prompt_hidden "Steam password for ${STEAM_USERNAME}:")"
		[[ -n "$password" ]] || exit 1
		set +e
		run_upload_live "$STEAM_USERNAME" "$password" "$guard"
		status=$?
		set -e
	fi
fi

if [[ $status -ne 0 ]]; then
	if grep -q "Steam Guard\|Account Logon Denied" "$LOG" 2>/dev/null; then
		[[ -n "$guard" ]] || guard="$(prompt_text "Steam Guard code (5 chars):")"
		if [[ ${#guard} -gt 8 ]]; then
			echo "Use the 5-char Guard code, not your password." >&2
			exit 1
		fi
		[[ -n "$guard" ]] || exit 1
		run_upload_live "$STEAM_USERNAME" "$password" "$guard"
	else
		echo "Upload failed — tail -30 $LOG" >&2
		exit "$status"
	fi
fi
