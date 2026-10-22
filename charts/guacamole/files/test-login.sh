#!/bin/sh
# Helm test: the login page is served and the database authentication answers. Uses no
# credentials, so it also passes after the guacadmin password was changed.
set -eu
log() { echo "[test] $*"; }
code="$(curl -s -o /dev/null -w '%{http_code}' "$URL")"
[ "$code" = 200 ] || { log "ERROR: login page $URL returned HTTP $code"; exit 1; }
log "login page $URL: HTTP 200"
user="helm-test-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
response="$(curl -s -X POST "${URL}api/tokens" --data-urlencode "username=$user" --data-urlencode "password=x")"
case "$response" in
    *'"type":"INVALID_CREDENTIALS"'*) log "database authentication answered (login of unknown user rejected)" ;;
    *) log "ERROR: unexpected response of ${URL}api/tokens: $response"; exit 1 ;;
esac
