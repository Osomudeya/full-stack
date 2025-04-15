{{/*
Expand the name of the chart.
*/}}
{{- define "memory-game.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "memory-game.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "memory-game.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "memory-game.labels" -}}
helm.sh/chart: {{ include "memory-game.chart" . }}
{{ include "memory-game.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "memory-game.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "memory-game.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "memory-game.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "memory-game.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end }}

{{/*
Backend selector labels
*/}}
{{- define "memory-game.backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}-backend
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend
{{- end }}

{{/*
Database selector labels
*/}}
{{- define "memory-game.database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}-database
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{/*
Prometheus selector labels
*/}}
{{- define "memory-game.prometheus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}-prometheus
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: monitoring
{{- end }}

{{/*
Grafana selector labels
*/}}
{{- define "memory-game.grafana.selectorLabels" -}}
app.kubernetes.io/name: {{ include "memory-game.name" . }}-grafana
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: monitoring
{{- end }}