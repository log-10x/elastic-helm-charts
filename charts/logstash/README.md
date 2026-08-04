# Logstash + 10x Helm Chart

Log10x enhanced Logstash Helm chart for Kubernetes.

## Description

This Helm chart deploys Logstash as a StatefulSet with optional Log10x sidecar integration for log cost analytics and optimization.

**Based on:** [elastic/helm-charts/logstash](https://github.com/elastic/helm-charts)

## Installing

### Install using the Helm repository

```bash
# Add the Log10x Elastic Helm charts repo
helm repo add log10x-elastic https://log-10x.github.io/elastic-helm-charts

# Install the chart
helm install my-logstash log10x-elastic/logstash -f values.yaml
```

### Install from source

```bash
# Clone the repo
git clone https://github.com/log-10x/elastic-helm-charts.git

# Install the chart
helm install my-logstash ./elastic-helm-charts/charts/logstash -f values.yaml
```

## Log10x Integration

Enable the Log10x sidecar by configuring the `tenx` section in your values file:

```yaml
tenx:
  enabled: true
  # REQUIRED. Without it the sidecar exits 1 on
  # "readStream(stream:logstash) requires a license" while Logstash keeps
  # shipping raw. Use licenseSecret instead to keep the token out of git.
  licenseJwt: "YOUR-LICENSE-JWT"
  kind: "receive"  # Options: report, receive, optimize
  runtimeName: "my-logstash-instance"

  # Optional: Git access token for private repositories
  gitToken: "YOUR-GIT-TOKEN"

  # Optional: GitOps configuration
  config:
    git:
      enabled: true
      url: "https://github.com/YOUR-ORG/YOUR-CONFIG-REPO.git"
      branch: "main"  # Optional
  symbols:
    git:
      enabled: true
      url: "https://github.com/YOUR-ORG/YOUR-SYMBOLS-REPO.git"
      branch: "main"  # Optional
      path: "path/to/symbols"  # Optional
```

### How events reach the engine and come back

Logstash and the sidecar share one network namespace, and the round trip uses
two TCP sockets:

```
Logstash `tenx-ingest` pipeline ──► sidecar :5046 ──► 10x Receiver
                                                            │
Logstash `tenx-destinations` pipeline ◄────────────────── :5045
```

With `tenx.pipeline.managed` on (the default) the chart writes both pipelines
and the `pipelines.yml` that points at them, so an install with a licence works
out of the box. Put your sources in `tenx.pipeline.ingestInput`, your enrichment
in `tenx.pipeline.ingestFilter`, and your real destinations in
`tenx.pipeline.destinationOutput`. Filters belong on the ingest side only, so
each event is enriched exactly once.

Three things about the ports are worth knowing before you change them:

- The sidecar listens on **5046**, not the engine module's own 5044 default. The
  stock `logstash` image binds 5044 for its `beats` input, and one namespace
  means the second bind fails with `Address already in use`.
- The engine opens the write-back socket to 5045 as it builds its pipeline,
  before Kubernetes has given Logstash time to bind it. `tenx.waitForLogstash`
  polls the port first, then execs the engine.
- The engine-side values reach it through a ConfigMap that replaces the image's
  `run/input/forwarder/logstash/config.yaml`, because that file is the only
  place the engine reads them from. Setting them as environment variables or as
  extra launch arguments does not work, and the second one is fatal: the launch
  macro expands the file into CLI options itself, so a repeat is `option
  'logstashInputPort' (string) should be specified only once` and exit 2.
  `tenx.config.git` or `tenx.config.volume` hands the whole config tree to you,
  ports included, and the chart stops rendering that ConfigMap.

To hand-write the whole thing instead, set `tenx.pipeline.managed: false` and
supply `logstashPipeline` and `logstashConfig` yourself. Any key you set under
those two always wins over the chart's.

### What the probes watch

Until chart 1.2.0 the `tenx` container carried no probe of any kind. The kubelet
marked it Ready the instant the container was created and never looked again.
Measured on this chart at 1.1.39, with the licence set to the literal string
`not-a-jwt`: `helm install` returned 0, the pod reported `2/2 Running`, the tenx
container reported `ready=true` with `restarts=0`, and the engine produced no
output at all. Chart CI cannot fail on an engine that is not running.

A dead engine needs no probe. The container command execs the engine over
itself, so the engine is pid 1: when it exits, the container exits and the
kubelet restarts it. Three probes now cover the states nothing else sees.

| Probe | Fails when |
|-------|------------|
| `startupProbe` | The wait loop is still polling and the engine has not been launched. While a startup probe is pending the kubelet runs neither of the other two, which is what stops liveness from restarting a container whose only problem is that Logstash is slow to bind. |
| `readinessProbe` | Nothing owned by the engine is listening on `tenx.inputPort`. Everything Logstash hands it goes nowhere. |
| `livenessProbe` | The engine is in the process table and doing nothing: stopped, traced, or deadlocked. This is the only state that needs a kill, and the one the container survives indefinitely. |

The readiness test is the one that observes the *engine* rather than the
process. `readStream(stream:logstash)` binds that port at the end of pipeline
construction, after the licence has been verified, so an engine that cannot
licence itself, cannot load its config, or is still building never passes it.
The listening socket also has to be one of pid 1's own file descriptors:
Logstash shares this network namespace, and a check that only asked whether
something was listening would pass on the wrong process.

`startupProbe.failureThreshold` is derived from
`tenx.waitForLogstash.timeoutSeconds` plus `tenx.healthcheck.startupGraceSeconds`
rather than fixed, so raising the wait cannot leave a container the kubelet
kills before its peer is up. Set it explicitly to take the number back.

Nothing keys off event flow. An idle Logstash is a healthy Logstash, and the
engine accrues CPU on its own timers whatever the traffic.

### Log10x Modes

| Mode | Description |
|------|-------------|
| `report` | Read-only observation. Emits cost and usage metrics without modifying the event stream |
| `receive` | Filter mode. Drops events per local or centralized policy |
| `optimize` | Filter and losslessly compact events for 50-65% volume reduction |

## Configuration

### Log10x Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tenx.enabled` | Enable Log10x sidecar container | `false` |
| `tenx.image.repository` | Log10x container image repository | `log10x/pipeline-10x` |
| `tenx.image.tag` | Log10x container image tag (defaults to the chart appVersion) | `""` |
| `tenx.licenseJwt` | Licence JWT. The chart puts it in a Secret | `""` |
| `tenx.licenseSecret` | Name of an existing Secret holding the token. Wins over `licenseJwt` | `""` |
| `tenx.licenseSecretKey` | Key inside that Secret | `license-jwt` |
| `tenx.licenseDelivery` | `file` (`TENX_LICENSE_FILE`) or `env` (`TENX_LICENSE_KEY`) | `file` |
| `tenx.apiKey` | Deprecated. Read as the licence when nothing else is set | `""` |
| `tenx.inputPort` | Port the sidecar listens on for events from Logstash | `5046` |
| `tenx.outputPort` | Port of the Logstash `tcp` input the sidecar writes back to | `5045` |
| `tenx.outputHost` | Host of that `tcp` input | `127.0.0.1` |
| `tenx.inputMessageField` | Field in each event holding the log line | `message` |
| `tenx.outputEncodeType` | Return wire format: `delimited` or `json` | `delimited` |
| `tenx.waitForLogstash.enabled` | Wait for `outputPort` to bind before launching the engine | `true` |
| `tenx.waitForLogstash.timeoutSeconds` | How long to wait before launching anyway | `300` |
| `tenx.healthcheck.enabled` | Give the sidecar engine-aware probes | `true` |
| `tenx.healthcheck.stallSeconds` | How long the engine may burn no CPU before liveness calls it frozen | `60` |
| `tenx.healthcheck.startupGraceSeconds` | Head-room on top of `waitForLogstash.timeoutSeconds` for the engine's own boot | `600` |
| `tenx.healthcheck.startupProbe` | Startup probe timings. `failureThreshold` is derived when left empty | see values.yaml |
| `tenx.healthcheck.readinessProbe` | Readiness probe timings | see values.yaml |
| `tenx.healthcheck.livenessProbe` | Liveness probe timings | see values.yaml |
| `tenx.pipeline.managed` | Render the two Logstash pipelines and `pipelines.yml` | `true` |
| `tenx.pipeline.ingestInput` | `input { }` body of the ingest pipeline | `beats` on 5044 |
| `tenx.pipeline.ingestFilter` | `filter { }` body of the ingest pipeline | adds `tag` |
| `tenx.pipeline.destinationOutput` | `output { }` body of the destinations pipeline | `stdout` |
| `tenx.kind` | Operation mode: `report`, `receive`, or `optimize` | `receive` |
| `tenx.runtimeName` | Optional name for this runtime instance | `""` |
| `tenx.resources` | Resource limits for Log10x sidecar | see values.yaml |
| `tenx.gitToken` | Git access token for private repositories | `""` |
| `tenx.configFetcherImage.repository` | Git config fetcher image | `log10x/git-config-fetcher` |
| `tenx.configFetcherImage.tag` | Git config fetcher image tag | `1.0.0` |
| `tenx.config.git.enabled` | Enable fetching config from a git repository | `false` |
| `tenx.config.git.url` | Full HTTPS URL of the config git repository | `""` |
| `tenx.config.git.branch` | Branch to pull (optional) | `""` |
| `tenx.config.volume.enabled` | Mount a PVC for config (air-gapped) | `false` |
| `tenx.config.volume.claimName` | PVC claim name for config volume | `""` |
| `tenx.symbols.git.enabled` | Enable fetching symbols from a git repository | `false` |
| `tenx.symbols.git.url` | Full HTTPS URL of the symbols git repository | `""` |
| `tenx.symbols.git.branch` | Branch to pull (optional) | `""` |
| `tenx.symbols.git.path` | Sub-path within repo for symbols (optional) | `""` |
| `tenx.symbols.volume.enabled` | Mount a PVC for symbols (air-gapped) | `false` |
| `tenx.symbols.volume.claimName` | PVC claim name for symbols volume | `""` |

### Logstash Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicas` | Number of Logstash replicas | `1` |
| `image` | Logstash Docker image | `docker.elastic.co/logstash/logstash` |
| `imageTag` | Logstash Docker image tag | `8.5.1` |
| `logstashConfig` | Logstash configuration files | `{}` |
| `logstashPipeline` | Logstash pipeline configuration | `{}` |
| `logstashJavaOpts` | Java options for Logstash | `-Xmx1g -Xms1g` |
| `resources` | Resource requests and limits | see values.yaml |
| `persistence.enabled` | Enable persistent storage | `false` |
| `volumeClaimTemplate` | PVC template for StatefulSet | see values.yaml |
| `extraEnvs` | Extra environment variables | `[]` |
| `extraVolumes` | Extra volumes | `[]` |
| `extraVolumeMounts` | Extra volume mounts | `[]` |
| `extraContainers` | Extra containers | `[]` |
| `extraInitContainers` | Extra init containers | `[]` |
| `service` | Service configuration | `{}` |
| `ingress` | Ingress configuration | see values.yaml |
| `nodeSelector` | Node selector for pod scheduling | `{}` |
| `tolerations` | Tolerations for pod scheduling | `[]` |
| `affinity` | Affinity rules | see values.yaml |

For the complete list of configuration options, see [values.yaml](./values.yaml).

## Usage Notes

- The chart deploys a StatefulSet with automated rolling updates by default
- Ensure the JVM heap size in `logstashJavaOpts` matches your resource limits
- When using Log10x, the sidecar and Logstash talk over two TCP sockets inside the shared pod network namespace, `tenx.inputPort` in and `tenx.outputPort` back
- Configuration files can be set via ConfigMap using `logstashConfig`
- When overriding `logstash.yml`, always include `http.host: 0.0.0.0` for probes to work

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Receiver Deployment](https://doc.log10x.com/apps/receiver/deploy/)

## License

This chart is licensed under the Apache License 2.0.

**Note:** The Log10x engine requires a commercial license. See [Log10x Pricing](https://www.log10x.com/pricing?utm_source=github&utm_medium=readme&utm_campaign=elastic-helm-charts&utm_content=inline) for details.
