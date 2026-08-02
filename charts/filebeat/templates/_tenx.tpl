{{/* vim: set filetype=mustache: */}}
{{/*
Resolve and validate the 10x distribution variant.

Only two variants are published as images: "jit" and "native". Any other value
used to be spliced straight into the image tag by printf, which never validates,
so a typo (or an unset value) produced a syntactically valid but unpullable
reference such as "log10x/filebeat-10x:1.0.20-jit-edge" or
"log10x/filebeat-10x:1.0.20-%!s(<nil>)" with exit code 0.

This helper fails the render instead. values.schema.json catches the same class
of mistake earlier, but --set-string and merged parent-chart values can reach the
templates in shapes the schema tolerated, so both layers are kept.

See https://doc.log10x.com/engine/flavors
*/}}
{{- define "tenx.variant" -}}
{{- $raw := .Values.tenx.variant -}}
{{- if kindIs "invalid" $raw -}}
{{- fail "tenx.variant is unset or null. Set it to \"jit\" or \"native\". See https://doc.log10x.com/engine/flavors" -}}
{{- end -}}
{{- $v := $raw | toString -}}
{{- if not (has $v (list "jit" "native")) -}}
{{- fail (printf "tenx.variant must be \"jit\" or \"native\", got %q. See https://doc.log10x.com/engine/flavors" $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}

{{/*
Resolve the licence JWT the chart should place in its own Secret.

Returns the empty string when the token is not the chart's to manage, which is
either because tenx.licenseSecret names a Secret someone else owns, or because
nothing was supplied at all.

tenx.apiKey and tenx.license are read as the licence because that is what they
always were. TENX_API_KEY, the variable they used to set, is read by nothing: it does
not appear in the image's config tree, and

  grep -c -a TENX_API_KEY /opt/tenx-edge/bin/tenx-edge-1.1.38-amd64-native

returns 0 against 2 for TENX_LICENSE_KEY. Rather than leave those installs
broken, the value is carried over to the licence.
*/}}
{{- define "tenx.licenseJwt" -}}
{{- if .Values.tenx.licenseSecret -}}
{{- else if .Values.tenx.licenseJwt -}}
{{- .Values.tenx.licenseJwt -}}
{{- else if .Values.tenx.apiKey -}}
{{- .Values.tenx.apiKey -}}
{{- else if .Values.tenx.license -}}
{{- .Values.tenx.license -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret that holds the licence: the caller's when tenx.licenseSecret
is set, otherwise the one this chart renders.
*/}}
{{- define "tenx.licenseSecretName" -}}
{{- if .Values.tenx.licenseSecret -}}
{{- .Values.tenx.licenseSecret -}}
{{- else -}}
{{- printf "%s-tenx-license" (include "filebeat.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
True when some Secret, chart-owned or pre-existing, carries a licence for this
release. Everything licence-shaped in the DaemonSet hangs off this.
*/}}
{{- define "tenx.licenseConfigured" -}}
{{- if .Values.tenx.licenseSecret -}}
true
{{- else if (include "tenx.licenseJwt" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
Validate tenx.licenseDelivery. "file" projects the Secret and sets
TENX_LICENSE_FILE, "env" injects TENX_LICENSE_KEY.
*/}}
{{- define "tenx.licenseDelivery" -}}
{{- $raw := .Values.tenx.licenseDelivery -}}
{{- if kindIs "invalid" $raw -}}
{{- fail "tenx.licenseDelivery is unset or null. Set it to \"file\" or \"env\"." -}}
{{- end -}}
{{- $v := $raw | toString -}}
{{- if not (has $v (list "file" "env")) -}}
{{- fail (printf "tenx.licenseDelivery must be \"file\" or \"env\", got %q." $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}

{{/*
Absolute path the licence is projected to under "file" delivery.
*/}}
{{- define "tenx.licenseFilePath" -}}
{{- printf "/etc/tenx/license/%s" (.Values.tenx.licenseSecretKey | default "license-jwt") -}}
{{- end -}}

{{/*
Build a probe that watches the engine as well as Filebeat.

Takes {probe, mode}. Every field of the caller's probe is kept except the handler
itself, so periodSeconds, failureThreshold and the rest stay tunable in one place
in values.yaml while the command becomes the 10x health check.

The handler is replaced rather than merged because a probe carrying two handlers
is rejected by the API server.
*/}}
{{- define "tenx.probe" -}}
{{- $rest := omit .probe "exec" "httpGet" "tcpSocket" "grpc" -}}
exec:
  command:
    - sh
    - /etc/tenx/probes/tenx-health.sh
    - {{ .mode }}
{{- if $rest }}
{{ toYaml $rest }}
{{- end }}
{{- end -}}
