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
True when the chart owns the engine-side socket settings, which it does unless
the whole 10x config tree is being supplied from Git or a volume. In those cases
the ports live in that tree and tenx.inputPort / tenx.outputPort reach only the
Logstash half of the pair.
*/}}
{{- define "tenx.socketConfigManaged" -}}
{{- if and .Values.tenx.enabled (not .Values.tenx.config.git.enabled) (not .Values.tenx.config.volume.enabled) -}}
true
{{- end -}}
{{- end -}}

{{/*
Replacement for the image's own
  /etc/tenx/config/pipelines/run/input/forwarder/logstash/config.yaml

This file, not any argument, is where the engine's socket settings come from.
The @run/input/forwarder/logstash launch macro expands it into CLI options
already, so passing logstashInputPort a second time is a picocli
OverwrittenOptionException and exit 2, and that holds for the documented
overrideKey/overrideValue form too. Replacing the file is what works, measured
on 1.1.39: "Reading events from Logstash tcp output on tcp://0.0.0.0:5046".

Keep the include list identical to the image's copy. It is what pulls in the
module that defines these options in the first place.
*/}}
{{- define "tenx.socketConfig" -}}
# Rendered by the log10x/logstash chart. Replaces the copy shipped in the image
# so tenx.inputPort / tenx.outputPort / tenx.outputHost take effect.
tenx: run

include:
  - run/input/forwarder/config.yaml
  - run/modules/input/forwarder/logstash

logstash:

  input:
    # The port the engine listens on for the Logstash `tcp` output. Not 5044:
    # the stock logstash image binds that for its own `beats` input, and the two
    # containers share a network namespace.
    port: {{ .Values.tenx.inputPort }}
    messageField: {{ .Values.tenx.inputMessageField | default "message" }}

  output:
    # The Logstash `tcp` input that receives processed events back.
    host: {{ .Values.tenx.outputHost }}
    port: {{ .Values.tenx.outputPort }}
    encodeType: {{ .Values.tenx.outputEncodeType }}
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
