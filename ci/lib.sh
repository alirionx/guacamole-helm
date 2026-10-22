#!/bin/bash
# Shared helpers of the integration tests.
set -euo pipefail

CHART="${CHART:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts/guacamole}"
log() { echo "[$(basename "$0")] $*"; }
die() { echo "[$(basename "$0")] ERROR: $*" >&2; exit 1; }

# Starts a port-forward in the background and waits until it accepts connections.
# Usage: port_forward <namespace> <resource> <local:remote>
port_forward() {
    kubectl -n "$1" port-forward "$2" "$3" >/dev/null 2>&1 &
    PORT_FORWARDS="${PORT_FORWARDS:-} $!"
    local port="${3%%:*}"
    for _ in $(seq 1 30); do
        (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && return 0
        sleep 1
    done
    die "port-forward to $2 in $1 did not become ready"
}
# Stops all port-forwards started by port_forward.
stop_port_forwards() {
    local pid
    for pid in ${PORT_FORWARDS:-}; do kill "$pid" 2>/dev/null || true; done
    PORT_FORWARDS=""
}
trap stop_port_forwards EXIT

# Prints the guacadmin password of a release.
admin_password() { kubectl -n "$1" get secret "$2-admin" -o jsonpath='{.data.password}' | base64 -d; }

# Logs in with username/password and prints the auth token (empty on failure).
login() { # base_url username password
    curl -s -X POST "$1/api/tokens" --data-urlencode "username=$2" --data-urlencode "password=$3" |
        jq -r '.authToken // empty'
}
