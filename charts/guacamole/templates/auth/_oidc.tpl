{{/*
ConfigMap entries (environment variables of the official image) for OpenID Connect.
*/}}
{{- define "guacamole.oidc.env" -}}
{{- $oidc := .Values.auth.oidc }}
{{- if $oidc.enabled }}
{{- range $key := list "issuer" "authorizationEndpoint" "jwksEndpoint" "clientId" }}
{{- if not (get $oidc $key) }}
{{- fail (printf "auth.oidc.%s is required when auth.oidc.enabled is true" $key) }}
{{- end }}
{{- end }}
OPENID_ENABLED: "true"
OPENID_ISSUER: {{ $oidc.issuer | quote }}
OPENID_AUTHORIZATION_ENDPOINT: {{ $oidc.authorizationEndpoint | quote }}
OPENID_JWKS_ENDPOINT: {{ $oidc.jwksEndpoint | quote }}
OPENID_CLIENT_ID: {{ $oidc.clientId | quote }}
OPENID_REDIRECT_URI: {{ include "guacamole.auth.redirectUri" (dict "context" . "value" $oidc.redirectUri "name" "auth.oidc.redirectUri") | quote }}
{{- with $oidc.scope }}
OPENID_SCOPE: {{ . | quote }}
{{- end }}
{{- with $oidc.usernameClaim }}
OPENID_USERNAME_CLAIM_TYPE: {{ . | quote }}
{{- end }}
{{- with $oidc.groupsClaim }}
OPENID_GROUPS_CLAIM_TYPE: {{ . | quote }}
{{- end }}
{{- with $oidc.attributesClaims }}
OPENID_ATTRIBUTES_CLAIM_TYPE: {{ . | quote }}
{{- end }}
{{- if not (kindIs "invalid" $oidc.allowedClockSkew) }}
OPENID_ALLOWED_CLOCK_SKEW: {{ $oidc.allowedClockSkew | quote }}
{{- end }}
{{- if not (kindIs "invalid" $oidc.maxTokenValidity) }}
OPENID_MAX_TOKEN_VALIDITY: {{ $oidc.maxTokenValidity | quote }}
{{- end }}
{{- if not (kindIs "invalid" $oidc.maxNonceValidity) }}
OPENID_MAX_NONCE_VALIDITY: {{ $oidc.maxNonceValidity | quote }}
{{- end }}
{{- end }}
{{- end }}
