{{/*
Name of the Secret holding the guacadmin password.
*/}}
{{- define "guacamole.admin.secretName" -}}
{{- .Values.auth.admin.existingSecret | default (printf "%s-admin" (include "guacamole.fullname" .)) }}
{{- end }}

{{/*
Database Secret entry ("name:key[,key]") for the secret init job.
*/}}
{{- define "guacamole.init.databaseSecret" -}}
{{- $keys := list (include "guacamole.database.secretKey" .) }}
{{- if include "guacamole.database.embedded" . }}
{{- $keys = append $keys .Values.database.embedded.superuserSecretKey }}
{{- end }}
{{- printf "%s:%s" (include "guacamole.database.secretName" .) (join "," $keys) }}
{{- end }}

{{/*
Secrets that must exist already ("name:key[,key]" list), checked by the secret init job.
*/}}
{{- define "guacamole.init.existingSecrets" -}}
{{- $list := list }}
{{- if or (eq .Values.database.mode "external") .Values.database.embedded.existingSecret }}
{{- $list = append $list (include "guacamole.init.databaseSecret" .) }}
{{- end }}
{{- if .Values.auth.admin.existingSecret }}
{{- $list = append $list (printf "%s:%s" .Values.auth.admin.existingSecret .Values.auth.admin.secretKey) }}
{{- end }}
{{- if and .Values.auth.duo.enabled .Values.auth.duo.existingSecret }}
{{- $list = append $list (printf "%s:%s" .Values.auth.duo.existingSecret .Values.auth.duo.secretKey) }}
{{- end }}
{{- join " " $list }}
{{- end }}

{{/*
Secrets created by the secret init job if missing ("name:key[,key]" list).
*/}}
{{- define "guacamole.init.managedSecrets" -}}
{{- $list := list }}
{{- if and (include "guacamole.database.embedded" .) (not .Values.database.embedded.existingSecret) }}
{{- $list = append $list (include "guacamole.init.databaseSecret" .) }}
{{- end }}
{{- if not .Values.auth.admin.existingSecret }}
{{- $list = append $list (printf "%s:%s" (include "guacamole.admin.secretName" .) .Values.auth.admin.secretKey) }}
{{- end }}
{{- join " " $list }}
{{- end }}

{{/*
Names of all Secrets the secret init job may read.
*/}}
{{- define "guacamole.init.secretNames" -}}
{{- $names := list }}
{{- range splitList " " (printf "%s %s" (include "guacamole.init.existingSecrets" .) (include "guacamole.init.managedSecrets" .) | trim) }}
{{- $names = append $names (splitList ":" . | first) }}
{{- end }}
{{- toJson (uniq $names) }}
{{- end }}

{{/*
Hook annotations for resources of the secret init phase (Helm pre-install/pre-upgrade, Argo CD PreSync).
Usage: include "guacamole.init.secretsHook" (dict "weight" -10 "deletePolicy" "before-hook-creation")
*/}}
{{- define "guacamole.init.secretsHook" -}}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: {{ .weight | quote }}
helm.sh/hook-delete-policy: {{ .deletePolicy }}
argocd.argoproj.io/hook: PreSync
argocd.argoproj.io/sync-wave: {{ .weight | quote }}
argocd.argoproj.io/hook-delete-policy: {{ .argoDeletePolicy | default "BeforeHookCreation" }}
{{- end }}

{{/*
Common pod spec fields of the init jobs (scheduling, security context, pull secrets).
*/}}
{{- define "guacamole.init.podCommon" -}}
restartPolicy: Never
enableServiceLinks: false
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
securityContext:
  {{- toYaml .Values.initJobs.podSecurityContext | nindent 2 }}
{{- with .Values.initJobs.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.initJobs.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.initJobs.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
