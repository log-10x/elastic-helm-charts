{{/* vim: set filetype=mustache: */}}

{{/*
Image tag for the 10x sidecar.

Defaults to .Chart.AppVersion, the engine release this chart is built against.
It used to default to .Chart.Version, the CHART version, which is a different
number on a different release cadence: a chart advertising appVersion 1.1.39
deployed log10x/pipeline-10x:1.0.21 and nothing in the render said so.
*/}}
{{- define "tenx.imageTag" -}}
{{- .Values.tenx.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{/*
Resolve the licence JWT the chart should place in its own Secret.

Returns the empty string when the token is not the chart's to manage, which is
either because tenx.licenseSecret names a Secret someone else owns, or because
nothing was supplied at all.

tenx.apiKey is read as the licence because that is what it always was. The
TENX_API_KEY variable it used to set is read by nothing: it appears neither in
the image's config tree nor in the engine binary. Carrying the value over to the
licence is what makes an existing install start working instead of continuing to
fail.
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
{{- printf "%s-tenx-license" (include "logstash.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
True when some Secret, chart-owned or pre-existing, carries a licence for this
release. Everything licence-shaped in the StatefulSet hangs off this.
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
True when the sidecar gets engine-aware probes.
*/}}
{{- define "tenx.healthcheckEnabled" -}}
{{- if and .Values.tenx.enabled .Values.tenx.healthcheck.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
One probe stanza. Takes {ctx, probe, mode}.

Every field of the caller's probe is carried through except the handler, which
becomes the health script in the requested mode. A probe carrying two handlers
is rejected by the API server, so the handler is replaced rather than merged.
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

{{/*
failureThreshold for the startup probe.

The startup probe is what keeps the liveness probe off the container while the
engine is not up yet, so its budget has to cover both slow parts of a normal
start: the wait for Logstash to bind, and the engine's own pipeline build. Both
are minutes, not seconds. Measured on this chart at 1.1.39, on a contended
node, the engine printed its first line 40 seconds after exec and reached
"pipeline units:" 142 seconds after that.

Deriving it from tenx.waitForLogstash.timeoutSeconds is what stops the two from
drifting apart: raising the wait to 1800 without raising this would give a
container that the kubelet kills before its peer is ever up. Set
tenx.healthcheck.startupProbe.failureThreshold to take the number back.
*/}}
{{- define "tenx.startupFailureThreshold" -}}
{{- $hc := .Values.tenx.healthcheck -}}
{{- if $hc.startupProbe.failureThreshold -}}
{{- $hc.startupProbe.failureThreshold -}}
{{- else -}}
{{- $period := int ($hc.startupProbe.periodSeconds | default 10) -}}
{{- if lt $period 1 }}{{- fail "tenx.healthcheck.startupProbe.periodSeconds must be at least 1." -}}{{- end -}}
{{- $wait := 0 -}}
{{- if .Values.tenx.waitForLogstash.enabled -}}
{{- $wait = int .Values.tenx.waitForLogstash.timeoutSeconds -}}
{{- end -}}
{{- $budget := add $wait (int $hc.startupGraceSeconds) -}}
{{- div (add $budget (sub $period 1)) $period -}}
{{- end -}}
{{- end -}}

{{/*
True when the chart renders the Logstash pipelines that talk to the sidecar.
*/}}
{{- define "tenx.managedPipeline" -}}
{{- if and .Values.tenx.enabled .Values.tenx.pipeline.managed -}}
true
{{- end -}}
{{- end -}}

{{/*
Reject a sidecar input port equal to the Logstash return port. Both containers
share one network namespace, so the pair has to be distinct or one of the two
binds fail with "Address already in use" and the sidecar exits 1.
*/}}
{{- define "tenx.validatePorts" -}}
{{- if eq (toString .Values.tenx.inputPort) (toString .Values.tenx.outputPort) -}}
{{- fail (printf "tenx.inputPort and tenx.outputPort are both %v. The sidecar listens on one and writes back to the other inside a single network namespace, so they cannot be the same port." .Values.tenx.inputPort) -}}
{{- end -}}
{{- end -}}

{{/*
The engine-side socket settings, as environment variables.

The shipped run/input/forwarder/logstash/config.yaml resolves each of these
through TenXEnv.get("<VAR>", <default>), which runs BEFORE the
@run/input/forwarder/logstash macro expands the file into launch arguments. One
occurrence reaches picocli either way, so there is nothing to collide with and
no OverwrittenOptionException. Passing the same values as bare arguments, or
through overrideKey/overrideValue, is still exit 2: by then the macro has
already contributed its own copy.

This is why the chart no longer ships a ConfigMap holding a second copy of a
file that lives in the image. That copy went stale the moment the shipped file
gained a key, and nothing detected it.

Requires an engine image whose config tree resolves these variables. On an
older image the file pins literals, the variables are ignored, and the sidecar
binds 5044 and dies on "Address already in use" against the stock logstash
image's beats input.
*/}}
{{- define "tenx.socketEnv" -}}
- name: TENX_LOGSTASH_INPUT_PORT
  value: {{ .Values.tenx.inputPort | quote }}
- name: TENX_LOGSTASH_INPUT_MESSAGE_FIELD
  value: {{ .Values.tenx.inputMessageField | default "message" | quote }}
- name: TENX_LOGSTASH_OUTPUT_HOST
  value: {{ .Values.tenx.outputHost | quote }}
- name: TENX_LOGSTASH_OUTPUT_PORT
  value: {{ .Values.tenx.outputPort | quote }}
- name: TENX_LOGSTASH_OUTPUT_ENCODE_TYPE
  value: {{ .Values.tenx.outputEncodeType | quote }}
{{- end -}}

{{/*
Logstash ingest pipeline: sources, enrichment, handoff to the sidecar.
*/}}
{{- define "tenx.ingestConf" -}}
# Rendered by the log10x/logstash chart (tenx.pipeline.managed=true).
# Events enter here, are handed to the 10x sidecar over TCP, and come back on
# the separate `tenx-destinations` pipeline. Filters belong here, so each event
# is enriched exactly once.
input {
{{ .Values.tenx.pipeline.ingestInput | trim | indent 2 }}
}
{{- if .Values.tenx.pipeline.ingestFilter }}

filter {
{{ .Values.tenx.pipeline.ingestFilter | trim | indent 2 }}
}
{{- end }}

output {
  tcp {
    id => "out_to_tenx"
    host => "127.0.0.1"
    port => {{ .Values.tenx.inputPort }}
    codec => json_lines
  }
}
{{- end -}}

{{/*
Logstash destinations pipeline: reads processed events back from the sidecar.

This pipeline is also what binds tenx.outputPort. The sidecar opens that socket
at startup, so a chart that does not bind it leaves the sidecar with nothing to
connect to.
*/}}
{{- define "tenx.destinationsConf" -}}
# Rendered by the log10x/logstash chart (tenx.pipeline.managed=true).
# Keep this pipeline filter-free. Filters here would re-run on every event
# coming back from the sidecar.
input {
  tcp {
    id => "in_from_tenx"
    host => "0.0.0.0"
    port => {{ .Values.tenx.outputPort }}
    codec => json_lines
  }
}

output {
{{ .Values.tenx.pipeline.destinationOutput | trim | indent 2 }}
}
{{- end -}}

{{/*
pipelines.yml wiring the two pipelines above. Replaces the image's single
`main` pipeline, which is what frees port 5044: the stock image ships a
pipeline/logstash.conf holding a `beats` input on that port.
*/}}
{{- define "tenx.pipelinesYml" -}}
- pipeline.id: tenx-ingest
  path.config: "/usr/share/logstash/pipeline/tenx-ingest.conf"
- pipeline.id: tenx-destinations
  path.config: "/usr/share/logstash/pipeline/tenx-destinations.conf"
{{- end -}}

{{/*
Effective pipeline files: what the user asked for, plus the chart's own when
tenx.pipeline.managed is on. A user key of the same name always wins.

Emitted as YAML so callers can read it back with fromYaml and stay in sync with
the ConfigMap, the volumeMounts and the checksum annotation.
*/}}
{{- define "logstash.pipelineFiles" -}}
{{- $files := dict -}}
{{- range $path, $config := .Values.logstashPipeline -}}
{{- $_ := set $files $path $config -}}
{{- end -}}
{{- if eq (include "tenx.managedPipeline" .) "true" -}}
{{- if not (hasKey $files "tenx-ingest.conf") -}}
{{- $_ := set $files "tenx-ingest.conf" (include "tenx.ingestConf" .) -}}
{{- end -}}
{{- if not (hasKey $files "tenx-destinations.conf") -}}
{{- $_ := set $files "tenx-destinations.conf" (include "tenx.destinationsConf" .) -}}
{{- end -}}
{{- end -}}
{{- toYaml $files -}}
{{- end -}}

{{/*
Effective config files, same rule: user keys win, the chart adds pipelines.yml
when it owns the pipelines.
*/}}
{{- define "logstash.configFiles" -}}
{{- $files := dict -}}
{{- range $path, $config := .Values.logstashConfig -}}
{{- $_ := set $files $path $config -}}
{{- end -}}
{{- if eq (include "tenx.managedPipeline" .) "true" -}}
{{- if not (hasKey $files "pipelines.yml") -}}
{{- $_ := set $files "pipelines.yml" (include "tenx.pipelinesYml" .) -}}
{{- end -}}
{{- end -}}
{{- toYaml $files -}}
{{- end -}}
