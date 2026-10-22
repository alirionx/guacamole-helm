{{/*
Egress rule for DNS lookups.
*/}}
{{- define "guacamole.np.dnsRule" -}}
- to:
    {{- toYaml .Values.networkPolicy.dns | nindent 4 }}
  ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
{{- end }}

{{/*
Egress rule to the database (embedded pod or external destination).
*/}}
{{- define "guacamole.np.databaseRule" -}}
{{- $port := include "guacamole.database.port" . | int }}
- ports:
    - protocol: TCP
      port: {{ $port }}
  {{- if include "guacamole.database.embedded" . }}
  to:
    - podSelector:
        matchLabels:
          {{- include "guacamole.componentSelectorLabels" (dict "context" . "component" "database") | nindent 10 }}
  {{- else if .Values.networkPolicy.database.externalTo }}
  to:
    {{- toYaml .Values.networkPolicy.database.externalTo | nindent 4 }}
  {{- end }}
{{- end }}
