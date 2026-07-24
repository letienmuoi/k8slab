{{- define "pipeline-auditor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pipeline-auditor.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "pipeline-auditor.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "pipeline-auditor.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "pipeline-auditor.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
lab: "5.4"
{{- end }}

{{- define "pipeline-auditor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pipeline-auditor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
