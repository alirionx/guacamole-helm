#!/bin/bash
# Integration test: OpenID Connect single sign-on against Dex (implicit flow), group claim and
# automatically created database accounts. Needs a kind cluster (current kubectl context).
#
# The script plays the browser: Guacamole redirects to Dex, the password form of Dex is posted,
# Dex redirects back with the ID token in the URL fragment, which is posted to /api/tokens.
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "$0")/lib.sh"

NS="${NS:-guacamole-oidc}"
DEX_CHART_VERSION="${DEX_CHART_VERSION:-0.26.0}"
PASSWORD="Dex-Test-Password-1"
ISSUER="http://dex.dex.svc.cluster.local:5556"
GUAC=http://127.0.0.1:18080
DEX_PORT=15556

log "installing Dex ${DEX_CHART_VERSION}"
hash="$(docker run --rm httpd:2.4-alpine htpasswd -bnBC 10 '' "$PASSWORD" | tr -d ':\n')"
helm upgrade --install dex dex --repo https://charts.dexidp.io --version "$DEX_CHART_VERSION" \
    -n dex --create-namespace --wait --timeout 5m -f - >/dev/null <<VALUES
config:
  issuer: ${ISSUER}
  storage: {type: memory}
  # Guacamole accepts ID tokens valid for up to 300 minutes (Dex default: 24h)
  expiry: {idTokens: 1h}
  oauth2:
    skipApprovalScreen: true
    responseTypes: [code, token, id_token]
  enablePasswordDB: true
  staticClients:
    - id: guacamole
      name: Guacamole
      secret: unused-by-implicit-flow
      redirectURIs: [http://guacamole.test/]
  staticPasswords:
    - {email: alice@example.com, username: alice, userID: 1b4c06a2-7c0e-4f55-9c1e-5a1f0d8d1a01, hash: "${hash}", groups: [guac-admins]}
    - {email: bob@example.com, username: bob, userID: 2c5d17b3-8d1f-4a66-8d2f-6b2a1e9e2b02, hash: "${hash}", groups: []}
VALUES

log "installing the chart with OIDC in namespace ${NS}"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
helm upgrade --install guacamole "$CHART" -n "$NS" --wait --timeout 8m -f - >/dev/null <<VALUES
database:
  embedded:
    persistence: {size: 1Gi}
auth:
  extensionPriority: "*, openid"
  autoCreateAccounts: true
  oidc:
    enabled: true
    issuer: ${ISSUER}
    authorizationEndpoint: ${ISSUER}/auth
    jwksEndpoint: ${ISSUER}/keys
    clientId: guacamole
    redirectUri: http://guacamole.test/
    scope: openid email profile groups
networkPolicy:
  enabled: true
  guacamole:
    extraEgress:
      - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: dex}}}]
        ports: [{protocol: TCP, port: 5556}]
VALUES

port_forward "$NS" svc/guacamole 18080:80
port_forward dex svc/dex "$DEX_PORT:5556"
JAR="$(mktemp)"
C=(curl -s -c "$JAR" -b "$JAR" --connect-to "dex.dex.svc.cluster.local:5556:127.0.0.1:${DEX_PORT}")
redirect() { "${C[@]}" -o /dev/null -w '%{redirect_url}' "$@"; }
absolute() { if [[ "$1" == /* ]]; then echo "${ISSUER}$1"; else echo "$1"; fi; }

# Prints the Guacamole auth token of an SSO login.
sso_login() { # email
    local url
    url="$(redirect "$GUAC/api/ext/openid/login")"
    [[ "$url" == "${ISSUER}/auth?"* && "$url" == *response_type=id_token* ]] ||
        die "unexpected redirect to the identity provider: $url"
    url="$(absolute "$(redirect "$url")")"                        # Dex: choose the password connector
    local form; form="$(absolute "$(redirect "$url")")"; [[ "$form" == "$ISSUER"* ]] || form="$url"
    url="$(absolute "$(redirect --data-urlencode "login=$1" --data-urlencode "password=$PASSWORD" "$form")")"
    while [[ "$url" == "$ISSUER"* ]]; do url="$(absolute "$(redirect "$url")")"; done
    local token; token="$(grep -o 'id_token=[^&]*' <<<"$url" | cut -d= -f2 || true)"
    [ -n "$token" ] || die "Dex did not return an ID token for $1 (redirect: ${url%%#*})"
    curl -s -X POST "$GUAC/api/tokens" --data-urlencode "id_token=$token" | jq -r '.authToken // empty'
}

log "creating the Guacamole group guac-admins with ADMINISTER permission"
admin_token="$(login "$GUAC" guacadmin "$(admin_password "$NS" guacamole)")"
[ -n "$admin_token" ] || die "guacadmin login failed"
api="$GUAC/api/session/data/postgresql"
curl -sf -X POST "$api/userGroups?token=$admin_token" -H 'Content-Type: application/json' \
    -d '{"identifier":"guac-admins","attributes":{"disabled":""}}' >/dev/null || true
curl -sf -X PATCH "$api/userGroups/guac-admins/permissions?token=$admin_token" -H 'Content-Type: application/json' \
    -d '[{"op":"add","path":"/systemPermissions","value":"ADMINISTER"}]' >/dev/null

for user in alice bob; do
    token="$(sso_login "$user@example.com")"
    [ -n "$token" ] || die "SSO login of $user failed"
    permissions="$(curl -s "$api/self/effectivePermissions?token=$token" | jq -c .systemPermissions)"
    log "SSO login of $user: OK, system permissions $permissions"
    case "$user" in
        alice) [ "$permissions" = '["ADMINISTER"]' ] || die "alice should be admin via the group claim" ;;
        bob)   [ "$permissions" = '[]' ] || die "bob should have no system permissions" ;;
    esac
done

accounts="$(curl -s "$api/users?token=$admin_token" | jq -r 'keys | join(" ")')"
[[ "$accounts" == *alice@example.com* && "$accounts" == *bob@example.com* ]] ||
    die "SSO users were not created in the database (accounts: $accounts)"
log "database accounts created automatically: $accounts"
log "OK"
