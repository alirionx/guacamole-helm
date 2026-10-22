{{/*
Chart name, truncated to the 63 characters allowed for DNS labels.
*/}}
{{- define "guacamole.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified release name. Used as prefix for all resource names.
*/}}
{{- define "guacamole.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Name of a component resource, e.g. "<fullname>-guacd".
Usage: include "guacamole.componentName" (dict "context" . "component" "guacd")
*/}}
{{- define "guacamole.componentName" -}}
{{- printf "%s-%s" (include "guacamole.fullname" .context | trunc 50 | trimSuffix "-") .component }}
{{- end }}

{{- define "guacamole.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for all resources.
*/}}
{{- define "guacamole.labels" -}}
helm.sh/chart: {{ include "guacamole.chart" . }}
{{ include "guacamole.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: guacamole
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "guacamole.selectorLabels" -}}
app.kubernetes.io/name: {{ include "guacamole.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels / selector labels for a component.
Usage: include "guacamole.componentLabels" (dict "context" . "component" "guacd")
*/}}
{{- define "guacamole.componentLabels" -}}
{{ include "guacamole.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "guacamole.componentSelectorLabels" -}}
{{ include "guacamole.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "guacamole.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "guacamole.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- required "serviceAccount.name is required when serviceAccount.create is false" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference. A digest takes precedence over the tag; the tag defaults to appVersion.
Usage: include "guacamole.image" (dict "image" .Values.guacd.image "context" .)
*/}}
{{- define "guacamole.image" -}}
{{- $repo := .image.repository }}
{{- if .image.registry }}
{{- $repo = printf "%s/%s" .image.registry .image.repository }}
{{- end }}
{{- if .image.digest }}
{{- printf "%s@%s" $repo .image.digest }}
{{- else }}
{{- printf "%s:%s" $repo (.image.tag | default .context.Chart.AppVersion | toString) }}
{{- end }}
{{- end }}

{{/*
Tomcat context name for WEBAPP_CONTEXT: "/" -> "ROOT", "/a/b" -> "a#b".
*/}}
{{- define "guacamole.webappContext" -}}
{{- $path := .Values.guacamole.contextPath }}
{{- if not (hasPrefix "/" $path) }}
{{- fail (printf "guacamole.contextPath must start with \"/\" (got %q)" $path) }}
{{- end }}
{{- if and (ne $path "/") (hasSuffix "/" $path) }}
{{- fail (printf "guacamole.contextPath must not end with \"/\" (got %q)" $path) }}
{{- end }}
{{- if eq $path "/" }}ROOT{{ else }}{{ trimPrefix "/" $path | replace "/" "#" }}{{ end }}
{{- end }}

{{/*
Context path with trailing slash, used for probes and NOTES.
*/}}
{{- define "guacamole.contextPathSlash" -}}
{{- if eq .Values.guacamole.contextPath "/" }}/{{ else }}{{ printf "%s/" .Values.guacamole.contextPath }}{{ end }}
{{- end }}

{{/*
Whether the RemoteIpValve is enabled; null means "enabled when exposed via Ingress or HTTPRoute".
*/}}
{{- define "guacamole.remoteIpValve.enabled" -}}
{{- $enabled := .Values.guacamole.remoteIpValve.enabled }}
{{- if kindIs "invalid" $enabled }}
{{- $enabled = or .Values.ingress.enabled .Values.httpRoute.enabled }}
{{- end }}
{{- if $enabled }}true{{ end }}
{{- end }}
