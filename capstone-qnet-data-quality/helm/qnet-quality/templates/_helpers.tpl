{{- define "qnet-quality.name" -}}
qnet-quality
{{- end -}}

{{- define "qnet-quality.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "qnet-quality.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "qnet-quality.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "qnet-quality.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: qnet-data-quality
app.kubernetes.io/component: worker
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
release-track: {{ .Values.releaseTrack | quote }}
{{- end -}}

{{- define "qnet-quality.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qnet-quality.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
