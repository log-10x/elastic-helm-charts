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
