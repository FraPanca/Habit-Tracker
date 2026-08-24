{{/*
Nome base del chart.
*/}}
{{- define "habit-tracker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Nome completo, univoco per release.
*/}}
{{- define "habit-tracker.fullname" -}}
{{- if eq .Release.Name .Chart.Name -}}
{{- .Chart.Name -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Label comuni da applicare a tutte le risorse (metadata.labels).
*/}}
{{- define "habit-tracker.labels" -}}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Nome del Secret MongoDB da referenziare nei Deployment.
*/}}
{{- define "habit-tracker.secretName" -}}
{{- if .Values.mongodb.auth.existingSecret -}}
{{- .Values.mongodb.auth.existingSecret -}}
{{- else -}}
{{- include "habit-tracker.fullname" . -}}-db-secret
{{- end -}}
{{- end -}}

{{/*
Nome del Service MongoDB.
*/}}
{{- define "habit-tracker.mongodbServiceName" -}}
{{- include "habit-tracker.fullname" . -}}-mongodb
{{- end -}}