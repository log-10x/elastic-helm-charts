# Filebeat + 10x Helm Chart

Log10x enhanced Filebeat Helm chart for Kubernetes.

## Description

This Helm chart deploys Filebeat as a DaemonSet (or Deployment) with integrated Log10x engine for log cost analytics and optimization.

**Based on:** [elastic/helm-charts/filebeat](https://github.com/elastic/helm-charts)

## Installing

### Install using the Helm repository

```bash
# Add the Log10x Elastic Helm charts repo
helm repo add log10x-elastic https://log-10x.github.io/elastic-helm-charts

# Install the chart
helm install my-filebeat log10x-elastic/filebeat -f values.yaml
```

### Install from source

```bash
# Clone the repo
git clone https://github.com/log-10x/elastic-helm-charts.git

# Install the chart
helm install my-filebeat ./elastic-helm-charts/charts/filebeat -f values.yaml
```

## Log10x Integration

The Log10x engine is integrated directly into the Filebeat container image. Enable it by configuring the `tenx` section in your values file:

```yaml
tenx:
  enabled: true
  licenseJwt: "YOUR-LICENSE-JWT"   # required; download from https://console.log10x.com
  kind: "receive"  # Options: report, receive, optimize
  variant: "native"  # image tag suffix; "jit" is retired
  runtimeName: "my-filebeat-instance"

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

### Log10x Modes

| Mode | Description |
|------|-------------|
| `report` | Read-only observation. Emits cost and usage metrics without modifying the event stream |
| `receive` | Filter mode. Drops events per local or centralized policy |
| `optimize` | Filter and losslessly compact events for 50-65% volume reduction |

### Licence

The licence is required. It is not a premium-feature switch: it is checked while
the receiver pipeline is being built, before a single event is read, and two
units of the default pipeline demand it.

```
metricOutput(Log10xMetricRegistryFactory)   the metric surface
logOutput(run/modules/output/event/unix)    the write-back socket to Filebeat
```

Because the write-back path is behind the same gate, an unlicensed engine cannot
even hand events back. It prints

```
metricOutput(Log10xMetricRegistryFactory) requires a license.
Get yours at https://console.log10x.com
```

and exits 1. The container goes with it in about three seconds, because the
image's entrypoint runs `set -euo pipefail` around
`exec filebeat "$@" 2>&1 | tenx-edge run ...`, so an unlicensed install
crash-loops rather than shipping raw. The licence baked into the public image is
of type `limited` and does not satisfy this gate.

Supply it in one of two ways.

```yaml
# The chart creates the Secret.
tenx:
  licenseJwt: "eyJhbGciOi..."

# You manage the Secret; nothing sensitive lands in the values file.
tenx:
  licenseSecret: "my-tenx-licence"
  licenseSecretKey: "license-jwt"
```

By default the Secret is projected to `/etc/tenx/license/<licenseSecretKey>` and
`TENX_LICENSE_FILE` points at it, which is what the engine's own bootstrap config
recommends: the token never enters the process environment. Set
`tenx.licenseDelivery: env` to inject `TENX_LICENSE_KEY` by `secretKeyRef`
instead.

`tenx.apiKey` and `tenx.license` are deprecated. They used to set `TENX_API_KEY`,
a variable nothing reads: it appears nowhere in the image's config tree and
nowhere in the engine binary. They were the licence under the wrong name, so if
either is set and no licence is configured, the chart uses the value as the
licence JWT rather than leaving the install broken. There is no second
credential: the product's "API key" belongs to the console and MCP surfaces, and
the forwarder never presents one.

### Health checks

The container runs two processes joined by one pipe.

```
exec filebeat "$@" 2>&1 | tenx-edge run ...
```

An engine that **exits** needs no probe. The entrypoint wraps that pipe in
`set -euo pipefail`, so the engine's exit status takes PID 1 down and Kubernetes
restarts the container in about three seconds, with or without this chart.

An engine that **freezes** is what these probes are for, and it is silent.
`SIGSTOP`, a traced process, a deadlock: the pid stays in the process table,
nothing breaks the pipe, the entrypoint never returns. Measured on 1.1.39 with
the old Filebeat-only probes, a `SIGSTOP`ped engine held the pod 1/1 Ready for
150 seconds while 5.2MB backed up in the pipe. With the engine-aware probes the
same freeze fails the next probe 22 seconds in, reporting
`FAIL: engine pid 12 is stopped (state 'T'): frozen, not running`, and the
container is restarted at 29 seconds.

With `tenx.healthcheck.enabled` (the default) both probes run
`/etc/tenx/probes/tenx-health.sh`, which keeps the Filebeat test and adds four
engine tests.

| Test | Catches |
|------|---------|
| `pgrep -x tenx-edge` finds the process | engine exited. Redundant with the entrypoint, kept because it costs nothing |
| scheduler state is not `T`, `t`, `Z` or `X` | engine `SIGSTOP`ped, traced, or an unreaped corpse |
| Filebeat's stdout inode is the engine's stdin inode | the two ends are no longer the same pipe |
| cumulative CPU advanced within `tenx.healthcheck.stallSeconds` | engine deadlocked while still schedulable |

The process test is matched on `comm` with `-x`, never on the command line with
`-f`: the probe's own shell mentions `tenx-edge`, so `pgrep -f` would match the
probe itself and report a dead engine as alive.

Nothing here keys off event flow, because an idle node is a healthy node. The
engine accrues CPU on its own timers whatever the traffic: measured idle on
1.1.38, cumulative CPU advanced 33 ticks in 151 seconds, and the longest stretch
with no advance at all was 20 seconds. `stallSeconds` defaults to 60, three times
that worst case.

Set `tenx.healthcheck.enabled: false` to fall back to the Filebeat-only probes.
A dead engine still restarts the container through the entrypoint; a frozen one
becomes invisible to Kubernetes again.

## Configuration

### Log10x Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tenx.enabled` | Enable Log10x engine | `true` |
| `tenx.variant` | Image tag suffix on `log10x/filebeat-10x:<appVersion>-<variant>`. Must be `jit` or `native`; any other value, or null, fails the render. `native` is the only variant still built; `jit` is retired. | `native` |
| `tenx.debug` | Enable debug logging | `false` |
| `tenx.licenseJwt` | Log10x licence JWT. Required: the engine does not start without one. The chart stores it in a Secret. | `""` |
| `tenx.licenseSecret` | Name of an existing Secret holding the licence. Takes precedence over `licenseJwt`. | `""` |
| `tenx.licenseSecretKey` | Key inside the licence Secret | `license-jwt` |
| `tenx.licenseDelivery` | `file` projects the Secret and sets `TENX_LICENSE_FILE`; `env` injects `TENX_LICENSE_KEY` | `file` |
| `tenx.healthcheck.enabled` | Make the probes observe the engine, not just Filebeat | `true` |
| `tenx.healthcheck.stallSeconds` | How long the engine may burn no CPU before the probes call it frozen | `60` |
| `tenx.healthcheck.readinessFilebeatTest` | Filebeat test the readiness probe runs: `output`, `http` or `none`. `output` cannot test `output.file`; use `http` there. | `output` |
| `tenx.apiKey` | Deprecated. Used to set `TENX_API_KEY`, which nothing reads. Used as the licence JWT when no licence is configured. | `""` |
| `tenx.license` | Deprecated. Same as `tenx.apiKey`. | `""` |
| `tenx.kind` | Operation mode: `report`, `receive`, or `optimize` | `receive` |
| `tenx.runtimeName` | Optional name for this runtime instance | `""` |
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

### Filebeat Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image` | Filebeat Docker image | `log10x/filebeat-10x` |
| `imageTag` | Image tag for both the DaemonSet and the Deployment (defaults to `{appVersion}-{variant}`) | `""` |
| `daemonset.enabled` | Enable DaemonSet deployment | `true` |
| `daemonset.filebeatConfig` | Filebeat configuration for DaemonSet | see values.yaml |
| `daemonset.resources` | Resource requests and limits | see values.yaml |
| `daemonset.tolerations` | Tolerations for DaemonSet | `[]` |
| `daemonset.nodeSelector` | Node selector for DaemonSet | `{}` |
| `daemonset.secretMounts` | Secret mounts (e.g., certificates) | see values.yaml |
| `deployment.enabled` | Enable Deployment (instead of DaemonSet) | `false` |
| `deployment.filebeatConfig` | Filebeat configuration for Deployment | see values.yaml |
| `hostPathRoot` | Root path for persistent data | `/var/lib` |
| `extraContainers` | Extra containers | `""` |
| `extraInitContainers` | Extra init containers | `[]` |
| `priorityClassName` | Priority class name | `""` |
| `updateStrategy` | Update strategy for DaemonSet | `RollingUpdate` |

For the complete list of configuration options, see [values.yaml](./values.yaml).

## Usage Notes

- The chart deploys a DaemonSet by default, collecting logs from all nodes
- The Log10x engine is bundled in the `log10x/filebeat-10x` image
- Default configuration sends logs to Elasticsearch using credentials from `elasticsearch-master-credentials` secret
- Kubernetes metadata enrichment is enabled by default
- The `receive` and `optimize` modes use a JavaScript processor to integrate with the Log10x pipeline

### Output Limitation

> **Important:** When Log10x is enabled (`tenx.enabled: true`), **do not use `output.console`** as the Filebeat output.

The Log10x engine communicates with Filebeat through a stdout pipe (`filebeat ... 2>&1 | tenx-edge run ...`). The Filebeat JavaScript processor (`tenx-*.js`) writes marked events to stdout, and the 10x engine reads them from stdin using a `"tenx":true` marker to distinguish real events from Filebeat's internal log messages.

`output.console` also writes to stdout, injecting multi-line pretty-printed JSON into the same pipe. This causes JSON parsing errors in the 10x engine because event boundaries become corrupted.

**Supported outputs:** `output.elasticsearch`, `output.logstash`, `output.file`, `output.kafka`, `output.redis`, and any other output that uses a network protocol or file — anything that does **not** write to stdout.

**For local testing without Elasticsearch**, use `output.file`:

```yaml
daemonset:
  filebeatConfig:
    filebeat.yml: |
      # ... your inputs ...
      output.file:
        path: "/tmp/filebeat-output"
        filename: filebeat-events
        rotate_every_kb: 10000
```

### Workloads: DaemonSet and Deployment

The chart ships two workloads. The DaemonSet is on by default and collects node
logs. The Deployment (`deployment.enabled: true`) is the singleton for inputs
that must run once per cluster rather than once per node, such as the `aws`
input.

Both run the same image and the same in-container engine, and from chart 1.5.0
both are wired for 10x from the same templates in `_tenx.tpl`: the licence, the
engine environment, the engine-aware probes and the git config fetcher.

Before 1.5.0 the Deployment had none of that. It rendered no `TENX_*` variable
at all, so the engine fell back to the limited key baked into the image, failed
the licence gate on `metricOutput` and took the container down through the
entrypoint's `pipefail`. A Deployment install with `tenx.enabled` at its default
of `true` crash-looped from the first second. Its default `filebeatConfig` also
had no read-back input and no script processor, so even a licensed engine would
have had nothing routed to it.

Set `daemonset.enabled: false` if you want the Deployment alone.

### Chart CI

`ct install` runs one install per file in `charts/filebeat/ci/`, one for the
DaemonSet and one for the Deployment, with `tenx.enabled: true`. The licence
comes from the `TENX_LICENSE_JWT` repository secret, written to a file and
passed as `--set-file tenx.licenseJwt=...` so the token stays out of the process
table; the chart puts it in a Secret of its own.

Pull requests from forks cannot read repository secrets. Those runs install with
`tenx.enabled=false` and the job prints a warning saying the engine went
untested, rather than failing on a licence they were never going to have.

### Sample Values Files

See the [samples](../../samples/) directory for example configurations:
- `filebeat-report.yaml` - Receiver in read-only mode (metrics-only observation)
- `filebeat-receive.yaml` - Receiver in filter mode
- `filebeat-optimize.yaml` - Receiver in optimize mode (filter and losslessly compact)

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Receiver Deployment](https://doc.log10x.com/apps/receiver/deploy/)

## License

This chart is licensed under the Apache License 2.0.

**Note:** The Log10x engine requires a commercial license. See [Log10x Pricing](https://www.log10x.com/pricing?utm_source=github&utm_medium=readme&utm_campaign=elastic-helm-charts&utm_content=inline) for details.
