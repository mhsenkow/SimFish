#!/usr/bin/env bash
# Shared SHA256 verify helper for supply-chain scripts.
verify_sha256() {
	local file="$1"
	local expected="$2"
	local label="${3:-$file}"
	local remove_on_fail="${4:-0}"

	if [[ ! -f "$file" ]]; then
		echo "ERROR: missing $label" >&2
		return 1
	fi
	local got
	if command -v shasum >/dev/null 2>&1; then
		got="$(shasum -a 256 "$file" | awk '{print $1}')"
	else
		got="$(sha256sum "$file" | awk '{print $1}')"
	fi
	if [[ "$got" != "$expected" ]]; then
		echo "ERROR: SHA256 mismatch for $label" >&2
		echo "  expected: $expected" >&2
		echo "  got:      $got" >&2
		if [[ "$remove_on_fail" == "1" ]]; then
			rm -f "$file"
		fi
		return 1
	fi
	return 0
}
