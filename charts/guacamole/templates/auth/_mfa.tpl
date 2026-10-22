{{/*
ConfigMap entries for TOTP.
*/}}
{{- define "guacamole.totp.env" -}}
{{- $totp := .Values.auth.totp }}
{{- if $totp.enabled }}
TOTP_ENABLED: "true"
{{- with $totp.issuer }}
TOTP_ISSUER: {{ . | quote }}
{{- end }}
{{- with $totp.digits }}
TOTP_DIGITS: {{ . | quote }}
{{- end }}
{{- with $totp.period }}
TOTP_PERIOD: {{ . | quote }}
{{- end }}
{{- with $totp.mode }}
TOTP_MODE: {{ . | quote }}
{{- end }}
{{- with $totp.bypassHosts }}
TOTP_BYPASS_HOSTS: {{ join "," . | quote }}
{{- end }}
{{- with $totp.enforceHosts }}
TOTP_ENFORCE_HOSTS: {{ join "," . | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
ConfigMap entries for Duo. The client secret is passed via secretKeyRef (see the Deployment).
*/}}
{{- define "guacamole.duo.env" -}}
{{- $duo := .Values.auth.duo }}
{{- if $duo.enabled }}
DUO_ENABLED: "true"
DUO_API_HOSTNAME: {{ $duo.apiHostname | quote }}
DUO_CLIENT_ID: {{ $duo.clientId | quote }}
DUO_REDIRECT_URI: {{ include "guacamole.auth.redirectUri" (dict "context" . "value" $duo.redirectUri "name" "auth.duo.redirectUri") | quote }}
{{- if not (kindIs "invalid" $duo.authTimeout) }}
DUO_AUTH_TIMEOUT: {{ $duo.authTimeout | quote }}
{{- end }}
{{- with $duo.bypassHosts }}
DUO_BYPASS_HOSTS: {{ join "," . | quote }}
{{- end }}
{{- with $duo.enforceHosts }}
DUO_ENFORCE_HOSTS: {{ join "," . | quote }}
{{- end }}
{{- end }}
{{- end }}
