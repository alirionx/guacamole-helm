{{/*
Validates the database configuration. Included by every template that depends on it.
*/}}
{{- define "guacamole.database.validate" -}}
{{- $db := .Values.database }}
{{- if not (has $db.type (list "postgresql" "mysql")) }}
{{- fail (printf "database.type must be \"postgresql\" or \"mysql\" (got %q)" $db.type) }}
{{- end }}
{{- if eq $db.mode "external" }}
{{- if not $db.external.host }}
{{- fail "database.external.host is required when database.mode is \"external\"" }}
{{- end }}
{{- if not $db.external.existingSecret }}
{{- fail "database.external.existingSecret is required when database.mode is \"external\" (Opaque Secret holding the database password)" }}
{{- end }}
{{- else if eq $db.mode "embedded" }}
{{- if eq $db.embedded.secretKey $db.embedded.superuserSecretKey }}
{{- fail "database.embedded.secretKey and database.embedded.superuserSecretKey must differ" }}
{{- end }}
{{- else }}
{{- fail (printf "database.mode must be \"external\" or \"embedded\" (got %q)" $db.mode) }}
{{- end }}
{{- end }}

{{- define "guacamole.database.embedded" -}}
{{- if eq .Values.database.mode "embedded" }}true{{ end }}
{{- end }}

{{/*
Environment variable prefix of the selected database type, as used by the official image.
*/}}
{{- define "guacamole.database.envPrefix" -}}
{{- if eq .Values.database.type "mysql" }}MYSQL{{ else }}POSTGRESQL{{ end }}
{{- end }}

{{- define "guacamole.database.defaultPort" -}}
{{- if eq .Values.database.type "mysql" }}3306{{ else }}5432{{ end }}
{{- end }}

{{/*
Name of the embedded database StatefulSet and Service.
*/}}
{{- define "guacamole.database.embeddedName" -}}
{{- include "guacamole.componentName" (dict "context" . "component" "database") }}
{{- end }}

{{- define "guacamole.database.host" -}}
{{- if include "guacamole.database.embedded" . }}
{{- include "guacamole.database.embeddedName" . }}
{{- else }}
{{- .Values.database.external.host }}
{{- end }}
{{- end }}

{{- define "guacamole.database.port" -}}
{{- if and (not (include "guacamole.database.embedded" .)) .Values.database.external.port }}
{{- .Values.database.external.port | int }}
{{- else }}
{{- include "guacamole.database.defaultPort" . }}
{{- end }}
{{- end }}

{{- define "guacamole.database.name" -}}
{{- if include "guacamole.database.embedded" . }}
{{- .Values.database.embedded.database }}
{{- else }}
{{- .Values.database.external.database }}
{{- end }}
{{- end }}

{{- define "guacamole.database.username" -}}
{{- if include "guacamole.database.embedded" . }}
{{- .Values.database.embedded.username }}
{{- else }}
{{- .Values.database.external.username }}
{{- end }}
{{- end }}

{{/*
Secret holding the application user password (and, for embedded, the superuser password).
*/}}
{{- define "guacamole.database.secretName" -}}
{{- if include "guacamole.database.embedded" . }}
{{- .Values.database.embedded.existingSecret | default (printf "%s-database" (include "guacamole.fullname" .)) }}
{{- else }}
{{- .Values.database.external.existingSecret }}
{{- end }}
{{- end }}

{{- define "guacamole.database.secretKey" -}}
{{- if include "guacamole.database.embedded" . }}
{{- .Values.database.embedded.secretKey }}
{{- else }}
{{- .Values.database.external.secretKey }}
{{- end }}
{{- end }}

{{/*
Image of the embedded database.
*/}}
{{- define "guacamole.database.embeddedImage" -}}
{{- if eq .Values.database.type "mysql" }}
{{- include "guacamole.image" (dict "image" .Values.database.embedded.mariadb.image "context" .) }}
{{- else }}
{{- include "guacamole.image" (dict "image" .Values.database.embedded.postgresql.image "context" .) }}
{{- end }}
{{- end }}

{{/*
Pod security context of the embedded database: defaults to the user of the official image.
*/}}
{{- define "guacamole.database.podSecurityContext" -}}
{{- $uid := ternary 999 70 (eq .Values.database.type "mysql") }}
{{- $defaults := dict "runAsUser" $uid "runAsGroup" $uid "fsGroup" $uid "fsGroupChangePolicy" "OnRootMismatch" }}
{{- toYaml (merge (deepCopy .Values.database.embedded.podSecurityContext) $defaults) }}
{{- end }}
