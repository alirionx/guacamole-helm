{{/*
PodDisruptionBudget for a component.
Usage: include "guacamole.pdb" (dict "context" . "component" "guacd" "name" $name "values" .Values.guacd)
*/}}
{{- define "guacamole.pdb" -}}
{{- $pdb := .values.podDisruptionBudget }}
{{- if $pdb.enabled }}
{{- $minSet := not (kindIs "invalid" $pdb.minAvailable) }}
{{- $maxSet := not (kindIs "invalid" $pdb.maxUnavailable) }}
{{- if and $minSet $maxSet }}
{{- fail (printf "%s.podDisruptionBudget: set either minAvailable or maxUnavailable, not both" .component) }}
{{- end }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "guacamole.componentLabels" (dict "context" .context "component" .component) | nindent 4 }}
spec:
  {{- if $minSet }}
  minAvailable: {{ $pdb.minAvailable }}
  {{- else }}
  maxUnavailable: {{ $pdb.maxUnavailable | default 1 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "guacamole.componentSelectorLabels" (dict "context" .context "component" .component) | nindent 6 }}
{{- end }}
{{- end }}

{{/*
HorizontalPodAutoscaler for a component Deployment.
Usage: include "guacamole.hpa" (dict "context" . "component" "guacd" "name" $name "values" .Values.guacd)
*/}}
{{- define "guacamole.hpa" -}}
{{- $hpa := .values.autoscaling }}
{{- if $hpa.enabled }}
{{- if and (not $hpa.targetCPUUtilizationPercentage) (not $hpa.targetMemoryUtilizationPercentage) }}
{{- fail (printf "%s.autoscaling: set targetCPUUtilizationPercentage and/or targetMemoryUtilizationPercentage" .component) }}
{{- end }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "guacamole.componentLabels" (dict "context" .context "component" .component) | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .name }}
  minReplicas: {{ $hpa.minReplicas }}
  maxReplicas: {{ $hpa.maxReplicas }}
  metrics:
    {{- with $hpa.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ . }}
    {{- end }}
    {{- with $hpa.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ . }}
    {{- end }}
  {{- with $hpa.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
