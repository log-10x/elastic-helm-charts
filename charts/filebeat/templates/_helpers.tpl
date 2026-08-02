{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "filebeat.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "filebeat.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the container image tag for every workload in this chart.

Single source of truth, so the DaemonSet and the Deployment in one release can
never disagree. An explicit .Values.imageTag wins; otherwise the tag is built
from the chart appVersion and the validated 10x variant. The tag is never
allowed to resolve empty, which is what made the Deployment render a bare
trailing colon (image: "log10x/filebeat-10x:") that a runtime silently resolves
to :latest.
*/}}
{{- define "filebeat.imageTag" -}}
{{- $variant := include "tenx.variant" . -}}
{{- if not .Values.imageTag -}}
{{- if not .Chart.AppVersion -}}
{{- fail "cannot resolve an image tag: imageTag is empty and the chart has no appVersion" -}}
{{- end -}}
{{- end -}}
{{- $tag := .Values.imageTag | default (printf "%s-%s" .Chart.AppVersion $variant) | toString -}}
{{- if not $tag -}}
{{- fail "resolved image tag is empty: set imageTag, or leave it empty and set tenx.variant to \"jit\" or \"native\"" -}}
{{- end -}}
{{- $tag -}}
{{- end -}}

{{/*
Use the fullname if the serviceAccount value is not set
*/}}
{{- define "filebeat.serviceAccount" -}}
{{- if .Values.serviceAccount }}
{{- .Values.serviceAccount -}}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
