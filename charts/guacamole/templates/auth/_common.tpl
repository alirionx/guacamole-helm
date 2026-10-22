{{/*
Public URL of Guacamole used as redirect URI by SSO and Duo: the explicit value or derived from
the first Ingress host or HTTPRoute hostname.
Usage: include "guacamole.auth.redirectUri" (dict "context" . "value" .Values.auth.oidc.redirectUri "name" "auth.oidc.redirectUri")
*/}}
{{- define "guacamole.auth.redirectUri" -}}
{{- $v := .context.Values }}
{{- $path := $v.guacamole.contextPath }}
{{- if .value }}
{{- .value }}
{{- else if and $v.ingress.enabled $v.ingress.hosts }}
{{- printf "%s://%s%s" (ternary "https" "http" $v.ingress.tls.enabled) (first $v.ingress.hosts) $path }}
{{- else if and $v.httpRoute.enabled $v.httpRoute.hostnames }}
{{- printf "https://%s%s" (first $v.httpRoute.hostnames) $path }}
{{- else }}
{{- fail (printf "%s is required when it cannot be derived from ingress.hosts or httpRoute.hostnames" .name) }}
{{- end }}
{{- end }}

{{/*
Validates combinations of authentication settings.
*/}}
{{- define "guacamole.auth.validate" -}}
{{- if and .Values.auth.totp.enabled .Values.auth.duo.enabled }}
{{- fail "auth.totp and auth.duo are mutually exclusive: enable only one second factor" }}
{{- end }}
{{- if .Values.auth.duo.enabled }}
{{- range $key := list "apiHostname" "clientId" "existingSecret" }}
{{- if not (get $.Values.auth.duo $key) }}
{{- fail (printf "auth.duo.%s is required when auth.duo.enabled is true" $key) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ConfigMap entries for all authentication settings. Extensions of the official image are activated
by their environment variables only; nothing is downloaded.
*/}}
{{- define "guacamole.auth.env" -}}
{{- include "guacamole.auth.validate" . }}
{{- with .Values.auth.extensionPriority }}
EXTENSION_PRIORITY: {{ . | quote }}
{{- end }}
{{- if .Values.auth.autoCreateAccounts }}
{{ include "guacamole.database.envPrefix" . }}_AUTO_CREATE_ACCOUNTS: "true"
{{- end }}
{{- include "guacamole.oidc.env" . }}
{{- include "guacamole.totp.env" . }}
{{- include "guacamole.duo.env" . }}
{{- end }}
