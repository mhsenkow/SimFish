#!/usr/bin/env bash
# Upload staged content to Steam via steamcmd.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${1:-$ROOT/depot_ids.env}"

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

STEAM_USERNAME="${STEAM_USERNAME:-mhsenkow}"

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
		"$template" > "$out"
}

mkdir -p "$ROOT/output"
gen_vdf "$ROOT/app_build.vdf.template" "$ROOT/app_build.vdf"
gen_vdf "$ROOT/depot_build_win.vdf.template" "$ROOT/depot_build_win.vdf"
gen_vdf "$ROOT/depot_build_linux.vdf.template" "$ROOT/depot_build_linux.vdf"
gen_vdf "$ROOT/depot_build_mac.vdf.template" "$ROOT/depot_build_mac.vdf"

prompt_hidden() {
	local title="$1"
	osascript -e "display dialog \"${title}\" default answer \"\" with hidden answer" \
		-e 'text returned of result' 2>/dev/null || true
}

prompt_text() {
	local title="$1"
	osascript -e "display dialog \"${title}\" default answer \"\"" \
		-e 'text returned of result' 2>/dev/null || true
}

run_upload() {
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
	steamcmd "${args[@]}"
}

password="${STEAM_PASSWORD:-}"
guard="${STEAM_GUARD_CODE:-}"
echo "Uploading build for AppID $STEAM_APP_ID as $STEAM_USERNAME..."

set +e
if [[ -n "$password" ]]; then
	output="$(run_upload "$STEAM_USERNAME" "$password" "$guard" 2>&1)"
else
	output="$(run_upload "$STEAM_USERNAME" "" "$guard" 2>&1)"
fi
status=$?
set -e
echo "$output"

if [[ $status -ne 0 && "$output" == *"Cached credentials not found"* ]]; then
	password="$(prompt_hidden "Steam password for ${STEAM_USERNAME}:")"
	if [[ -z "$password" ]]; then
		echo "Upload cancelled — password required." >&2
		exit 1
	fi
	set +e
	output="$(run_upload "$STEAM_USERNAME" "$password" "$guard" 2>&1)"
	status=$?
	set -e
	echo "$output"
fi

if [[ $status -ne 0 ]]; then
	if [[ "$output" == *"Steam Guard"* || "$output" == *"Account Logon Denied"* ]]; then
		if [[ -z "$guard" ]]; then
			guard="$(prompt_text "Steam Guard code for ${STEAM_USERNAME}:")"
		fi
		if [[ -n "$guard" ]]; then
			echo "Retrying with Steam Guard code..."
			run_upload "$STEAM_USERNAME" "$password" "$guard"
		else
			exit 1
		fi
	else
		exit "$status"
	fi
fi
