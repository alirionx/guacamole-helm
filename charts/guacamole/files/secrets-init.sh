#!/bin/bash
# Secret init job: verifies user-provided Secrets and creates missing chart-managed Secrets.
# Runs before the workloads (Helm pre-install/pre-upgrade, Argo CD PreSync) and is idempotent.
#
# Environment:
#   EXISTING_SECRETS  space-separated "name:key[,key...]" entries that must already exist (Opaque, keys present)
#   MANAGED_SECRETS   space-separated "name:key[,key...]" entries that are created with random values if missing
#   SECRET_LABELS     JSON object with labels for created Secrets
set -euo pipefail

SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
API="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
NAMESPACE="$(cat "$SA_DIR/namespace")"
TOKEN="$(cat "$SA_DIR/token")"
RESPONSE=/tmp/response.json

log() { echo "[secrets-init] $*"; }
die() { echo "[secrets-init] ERROR: $*" >&2; exit 1; }

# Performs an API request; prints the HTTP status code, body goes to $RESPONSE.
api() {
    curl -sS --cacert "$SA_DIR/ca.crt" -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" -o "$RESPONSE" -w '%{http_code}' "$@"
}

# Checks that the Secret in $RESPONSE is of type Opaque and contains the given non-empty keys
# (comma-separated). The API pretty-prints JSON for non-kubectl clients, so whitespace is
# stripped first (Secret data is base64 and never contains whitespace).
verify_secret() {
    local name="$1" keys="$2" flat data key
    flat="$(tr -d ' \t\r\n' < "$RESPONSE")"
    grep -q '"type":"Opaque"' <<< "$flat" \
        || die "Secret \"$name\" must be of type Opaque"
    data="$(grep -o '"data":{[^}]*}' <<< "$flat" || true)"
    for key in ${keys//,/ }; do
        grep -Eq "\"${key//./\\.}\":\"[^\"]+\"" <<< "$data" \
            || die "Secret \"$name\" has no non-empty key \"$key\""
    done
}

# Generates a random alphanumeric password with 32 characters.
random_password() {
    local value
    value="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
    [ "${#value}" -eq 32 ] || die "Generating a random password failed"
    printf '%s' "$value"
}

for entry in ${EXISTING_SECRETS:-}; do
    name="${entry%%:*}" keys="${entry#*:}"
    code="$(api "$API/api/v1/namespaces/$NAMESPACE/secrets/$name")"
    case "$code" in
        200) verify_secret "$name" "$keys"; log "Secret \"$name\" (keys \"$keys\") found" ;;
        404) die "Secret \"$name\" referenced in values does not exist in namespace \"$NAMESPACE\"" ;;
        *)   die "Reading Secret \"$name\" failed with HTTP $code: $(cat "$RESPONSE")" ;;
    esac
done

for entry in ${MANAGED_SECRETS:-}; do
    name="${entry%%:*}" keys="${entry#*:}"
    code="$(api "$API/api/v1/namespaces/$NAMESPACE/secrets/$name")"
    case "$code" in
        200)
            verify_secret "$name" "$keys"
            log "Secret \"$name\" already exists, keeping it"
            ;;
        404)
            data=""
            for key in ${keys//,/ }; do
                data="${data:+$data,}\"$key\":\"$(random_password | base64 -w0)\""
            done
            body="$(printf '{"apiVersion":"v1","kind":"Secret","type":"Opaque","metadata":{"name":"%s","labels":%s},"data":{%s}}' \
                "$name" "${SECRET_LABELS:-{\}}" "$data")"
            code="$(api -X POST --data "$body" "$API/api/v1/namespaces/$NAMESPACE/secrets")"
            case "$code" in
                201) log "Secret \"$name\" created with random values (keys \"$keys\")" ;;
                409) log "Secret \"$name\" was created concurrently, keeping it" ;;
                *)   die "Creating Secret \"$name\" failed with HTTP $code: $(cat "$RESPONSE")" ;;
            esac
            ;;
        *) die "Reading Secret \"$name\" failed with HTTP $code: $(cat "$RESPONSE")" ;;
    esac
done

log "done"
