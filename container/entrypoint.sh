#!/usr/bin/env bash
# Translate vivarium-serve env vars into CLI flags, then exec the binary.
#
# Recognised env vars (defaults are baked into the Containerfile's ENV):
#   HOST            bind address           (default 0.0.0.0)
#   PORT            TCP port               (default 8080)
#   WEB_ROOT        Godot web build path   (default /opt/vivarium/web)
#   LOG_STDOUT      log telemetry to stdout (true sets --log-stdout)
#   PROMETHEUS      expose /metrics        (true sets --prometheus)
#   CLIENT_TIMEOUT  seconds before a client expires from /metrics
#
# Anything passed positionally to the container is appended last, so
#   podman run ... vivarium-serve --help
# still does what you'd expect.

set -euo pipefail

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

args=( --host "${HOST:-0.0.0.0}" --port "${PORT:-8080}" )

if [[ -n "${WEB_ROOT:-}" ]]; then
    args+=( --web-root "$WEB_ROOT" )
fi

if is_truthy "${LOG_STDOUT:-}"; then
    args+=( --log-stdout )
fi

if is_truthy "${PROMETHEUS:-}"; then
    args+=( --prometheus )
fi

if [[ -n "${CLIENT_TIMEOUT:-}" ]]; then
    args+=( --client-timeout "$CLIENT_TIMEOUT" )
fi

exec /usr/local/bin/vivarium-serve "${args[@]}" "$@"
