{{/*
Validates guacamole.extraExtensions: unique names, exactly one source, mandatory checksum for URLs.
*/}}
{{- define "guacamole.extensions.validate" -}}
{{- $names := list }}
{{- range .Values.guacamole.extraExtensions }}
{{- if has .name $names }}
{{- fail (printf "guacamole.extraExtensions: duplicate name %q" .name) }}
{{- end }}
{{- $names = append $names .name }}
{{- $sources := 0 }}
{{- if .image }}{{ $sources = add1 $sources }}{{ end }}
{{- if .url }}{{ $sources = add1 $sources }}{{ end }}
{{- if .imageVolume }}{{ $sources = add1 $sources }}{{ end }}
{{- if ne (int $sources) 1 }}
{{- fail (printf "guacamole.extraExtensions[%s]: set exactly one source (image, url or imageVolume)" .name) }}
{{- end }}
{{- if and .imageVolume (gt (len $.Values.guacamole.extraExtensions) 1) }}
{{- fail (printf "guacamole.extraExtensions[%s]: an imageVolume source must be the only extension, because its directory is mounted as GUACAMOLE_HOME/extensions; use the image source to combine several extensions" .name) }}
{{- end }}
{{- if and .url (not (regexMatch "^[a-fA-F0-9]{64}$" (.sha256 | default ""))) }}
{{- fail (printf "guacamole.extraExtensions[%s]: sha256 (64 hex characters) is required for url sources" .name) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Init containers that place extension JARs into the shared "extensions" volume.
*/}}
{{- define "guacamole.extensions.initContainers" -}}
{{- $root := . }}
{{- range .Values.guacamole.extraExtensions }}
{{- if .image }}
- name: extension-{{ .name }}
  image: {{ include "guacamole.image" (dict "image" .image "context" $root) | quote }}
  imagePullPolicy: {{ .image.pullPolicy | default "IfNotPresent" }}
  command: ["/bin/sh", "-c"]
  args:
    - {{ $root.Files.Get "files/extension-copy.sh" | quote }}
  env:
    - name: SOURCE
      value: {{ .path | default "/extensions" | quote }}
    - name: TARGET
      value: /target
  securityContext:
    {{- toYaml $root.Values.guacamole.securityContext | nindent 4 }}
  resources:
    {{- toYaml $root.Values.guacamole.extensionsInit.resources | nindent 4 }}
  volumeMounts:
    - name: extensions
      mountPath: /target
{{- else if .url }}
- name: extension-{{ .name }}
  # The guacamole image provides curl and sha256sum.
  image: {{ include "guacamole.image" (dict "image" $root.Values.guacamole.image "context" $root) | quote }}
  imagePullPolicy: {{ $root.Values.guacamole.image.pullPolicy }}
  command: ["/bin/sh", "-c"]
  args:
    - {{ $root.Files.Get "files/extension-download.sh" | quote }}
  env:
    - name: URL
      value: {{ .url | quote }}
    - name: SHA256
      value: {{ .sha256 | lower | quote }}
    - name: FILE_NAME
      value: {{ .fileName | default (printf "%s.jar" .name) | quote }}
    - name: TARGET
      value: /target
  securityContext:
    {{- toYaml $root.Values.guacamole.securityContext | nindent 4 }}
  resources:
    {{- toYaml $root.Values.guacamole.extensionsInit.resources | nindent 4 }}
  volumeMounts:
    - name: extensions
      mountPath: /target
{{- end }}
{{- end }}
{{- end }}

{{/*
Image pull secrets of the pod: global ones plus those of extension images.
*/}}
{{- define "guacamole.extensions.pullSecrets" -}}
{{- $secrets := .Values.imagePullSecrets }}
{{- range .Values.guacamole.extraExtensions }}
{{- range .imagePullSecrets }}
{{- if not (has . $secrets) }}
{{- $secrets = append $secrets . }}
{{- end }}
{{- end }}
{{- end }}
{{- with $secrets }}
{{- toYaml . }}
{{- end }}
{{- end }}
