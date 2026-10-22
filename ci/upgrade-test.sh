#!/bin/bash
# Upgrade test: installs the latest released chart version, creates data, upgrades to the chart in
# this repository and verifies that the data and the guacadmin login survive (version policy of
# the embedded database). Skipped if no release exists yet. Needs a kind cluster.
source "$(dirname "$0")/lib.sh"

NS="${NS:-guacamole-upgrade}"
REPO="${REPO:-oci://ghcr.io/alirionx/charts/guacamole}"
TYPE="${TYPE:-postgresql}"
GUAC=http://127.0.0.1:18081

previous="$(helm show chart "$REPO" 2>/dev/null | awk '/^version:/ {print $2}' || true)"
if [ -z "$previous" ]; then
    log "no released chart found at $REPO, skipping the upgrade test"
    exit 0
fi
current="$(awk '/^version:/ {print $2}' "$CHART/Chart.yaml")"
log "upgrading from released $previous to $current (database type $TYPE)"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
values=(--set "database.type=$TYPE" --set database.embedded.persistence.size=1Gi)
helm upgrade --install guacamole "$REPO" --version "$previous" -n "$NS" "${values[@]}" --wait --timeout 8m >/dev/null

port_forward "$NS" svc/guacamole 18081:80
password="$(admin_password "$NS" guacamole)"
token="$(login "$GUAC" guacadmin "$password")"
[ -n "$token" ] || die "login on $previous failed"
source_ds="$(curl -s -X POST "$GUAC/api/tokens" --data-urlencode username=guacadmin --data-urlencode "password=$password" | jq -r .dataSource)"
curl -sf -X POST "$GUAC/api/session/data/$source_ds/connections?token=$token" -H 'Content-Type: application/json' \
    -d '{"name":"upgrade-test","protocol":"ssh","parentIdentifier":"ROOT","parameters":{"hostname":"example.com","port":"22"},"attributes":{}}' >/dev/null
log "created connection upgrade-test on $previous"
stop_port_forwards

helm upgrade guacamole "$CHART" -n "$NS" "${values[@]}" --wait --timeout 8m >/dev/null
port_forward "$NS" svc/guacamole 18081:80
token="$(login "$GUAC" guacadmin "$password")"
[ -n "$token" ] || die "guacadmin login failed after the upgrade"
names="$(curl -s "$GUAC/api/session/data/$source_ds/connections?token=$token" | jq -r '[.[].name] | join(" ")')"
[[ " $names " == *" upgrade-test "* ]] || die "connection lost during the upgrade (connections: $names)"
log "after the upgrade to $current: login OK, connection upgrade-test present"
log "OK"
