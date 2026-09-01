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

{{/*
True when the git config fetcher init container is wanted.
*/}}
{{- define "tenx.gitInit" -}}
{{- if and .Values.tenx.enabled (or .Values.tenx.config.git.enabled .Values.tenx.symbols.git.enabled) -}}
true
{{- end -}}
{{- end -}}

{{/*
Every environment variable the engine needs, emitted at zero indent for the
caller to place.

This lives here rather than in daemonset.yaml because the Deployment needs the
identical set. Until chart 1.5.0 it did not have it: the Deployment carried no
TENX_* variable at all, so the engine in the image fell back to the baked-in
"limited" key, failed the licence gate on metricOutput, and took the container
down through the entrypoint's pipefail. A Deployment install crash-looped from
the first second with tenx.enabled left at its default of true.
*/}}
{{- define "tenx.env" -}}
# The engine reads exactly one credential, the licence JWT, from
# TENX_LICENSE_FILE or TENX_LICENSE_KEY. Optional: without one the engine runs
# on its built-in 30-day evaluation licence (10 nodes, airgapped), so an
# unlicensed install starts and evaluates rather than crash-looping.
{{- if eq (include "tenx.licenseConfigured" .) "true" }}
{{- if eq (include "tenx.licenseDelivery" .) "file" }}
- name: TENX_LICENSE_FILE
  value: {{ include "tenx.licenseFilePath" . | quote }}
{{- else }}
- name: TENX_LICENSE_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "tenx.licenseSecretName" . }}
      key: {{ .Values.tenx.licenseSecretKey | default "license-jwt" }}
{{- end }}
{{- end }}
# Read by the health checks, which skip every engine-side test when 10x is
# switched off so the same probe script works either way.
- name: TENX_ENABLED
  value: "true"
- name: TENX_PROBE_STALL_SECONDS
  value: {{ .Values.tenx.healthcheck.stallSeconds | quote }}
- name: TENX_PROBE_FILEBEAT_TEST
  value: {{ .Values.tenx.healthcheck.readinessFilebeatTest | quote }}
{{- if .Values.tenx.runtimeName }}
- name: TENX_RUNTIME_NAME
  value: {{ .Values.tenx.runtimeName | quote }}
{{- end }}
{{- if .Values.tenx.config.git.enabled }}
- name: TENX_CONFIG
  value: "/etc/tenx/git/config"
{{- else if .Values.tenx.config.volume.enabled }}
- name: TENX_CONFIG
  value: "/etc/tenx/config"
{{- end }}
{{- if .Values.tenx.symbols.git.enabled }}
- name: TENX_SYMBOLS_PATH
  value: "/etc/tenx/git/config/data/shared/symbols"
{{- else if .Values.tenx.symbols.volume.enabled }}
- name: TENX_SYMBOLS_PATH
  value: "/etc/tenx/symbols"
{{- end }}
# Launch macro for the in-container engine. '@run/input/forwarder/filebeat' is
# the FOLDER form: the engine resolves it against its include paths to
# log-10x/config's pipelines/run/input/forwarder/filebeat/config.yaml. That
# folder has no receive/ subdirectory, so the older
# '@run/input/forwarder/filebeat/receive/config.yaml' spelling aborts the launch
# with "error expanding launch macro". This value matches the image's own
# TENX_RUN_ARGS default, so overriding it here changes nothing but keeps the
# read-only flag appendable for report mode.
- name: TENX_RUN_ARGS
{{- if eq .Values.tenx.kind "report" }}
  value: "@run/input/forwarder/filebeat @apps/receiver receiverReadOnly true"
{{- else }}
  value: "@run/input/forwarder/filebeat @apps/receiver"
{{- end }}
{{- if eq .Values.tenx.kind "optimize" }}
- name: receiverOptimize
  value: "true"
{{- end }}
{{- end -}}

{{/*
Pod volumes the engine needs: the licence, the probe script, and whatever the
git or PVC config sources bring. Emitted at zero indent.
*/}}
{{- define "tenx.volumes" -}}
{{- if and (eq (include "tenx.licenseConfigured" .) "true") (eq (include "tenx.licenseDelivery" .) "file") }}
- name: tenx-license
  secret:
    secretName: {{ include "tenx.licenseSecretName" . }}
    # Read-only to every uid in the pod rather than 0400, which would hide the
    # token from a non-root securityContext with no fsGroup set.
    defaultMode: 0444
    items:
      - key: {{ .Values.tenx.licenseSecretKey | default "license-jwt" }}
        path: {{ .Values.tenx.licenseSecretKey | default "license-jwt" }}
{{- end }}
{{- if .Values.tenx.healthcheck.enabled }}
- name: tenx-probes
  configMap:
    name: {{ template "filebeat.fullname" . }}-tenx-probes
    defaultMode: 0555
{{- end }}
{{- if eq (include "tenx.gitInit" .) "true" }}
- name: tenx-git
  emptyDir: {}
{{- end }}
{{- if .Values.tenx.config.volume.enabled }}
- name: tenx-config-volume
  persistentVolumeClaim:
    claimName: {{ .Values.tenx.config.volume.claimName }}
{{- end }}
{{- if .Values.tenx.symbols.volume.enabled }}
- name: tenx-symbols-volume
  persistentVolumeClaim:
    claimName: {{ .Values.tenx.symbols.volume.claimName }}
{{- end }}
{{- end -}}

{{/*
The container mounts matching tenx.volumes. Emitted at zero indent.
*/}}
{{- define "tenx.volumeMounts" -}}
{{- if and (eq (include "tenx.licenseConfigured" .) "true") (eq (include "tenx.licenseDelivery" .) "file") }}
- name: tenx-license
  mountPath: /etc/tenx/license
  readOnly: true
{{- end }}
{{- if .Values.tenx.healthcheck.enabled }}
- name: tenx-probes
  mountPath: /etc/tenx/probes
  readOnly: true
{{- end }}
{{- if eq (include "tenx.gitInit" .) "true" }}
- name: tenx-git
  mountPath: /etc/tenx/git
{{- end }}
{{- if .Values.tenx.config.volume.enabled }}
- name: tenx-config-volume
  mountPath: /etc/tenx/config
{{- end }}
{{- if .Values.tenx.symbols.volume.enabled }}
- name: tenx-symbols-volume
  mountPath: /etc/tenx/symbols
{{- end }}
{{- end -}}

{{/*
The git config fetcher init container. Emitted at zero indent.
*/}}
{{- define "tenx.gitInitContainer" -}}
- name: tenx-git-config
  image: "{{ .Values.tenx.configFetcherImage.repository }}:{{ .Values.tenx.configFetcherImage.tag }}"
  imagePullPolicy: "{{ .Values.tenx.configFetcherImage.pullPolicy }}"
  env:
    - name: GIT_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ template "filebeat.fullname" . }}-tenx-git-token
          key: token
  args:
    {{- if .Values.tenx.config.git.enabled }}
    - "--config-repo"
    - {{ .Values.tenx.config.git.url | quote }}
    {{- if .Values.tenx.config.git.branch }}
    - "--config-branch"
    - {{ .Values.tenx.config.git.branch | quote }}
    {{- end }}
    {{- end }}
    {{- if .Values.tenx.symbols.git.enabled }}
    - "--symbols-repo"
    - {{ .Values.tenx.symbols.git.url | quote }}
    {{- if .Values.tenx.symbols.git.branch }}
    - "--symbols-branch"
    - {{ .Values.tenx.symbols.git.branch | quote }}
    {{- end }}
    {{- if .Values.tenx.symbols.git.path }}
    - "--symbols-path"
    - {{ .Values.tenx.symbols.git.path | quote }}
    {{- end }}
    {{- end }}
  volumeMounts:
    - name: tenx-git
      mountPath: /data
{{- end -}}
