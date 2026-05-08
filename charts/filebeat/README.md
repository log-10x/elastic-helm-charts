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
  apiKey: "YOUR-LICENSE-KEY"
  # optimize: false  # losslessly compact events for 50-65% volume reduction
  # readOnly: false  # observe-only, no return loop (mutually exclusive with optimize)
  variant: "jit"    # Options: jit, native
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

| Flags | Mode | Description |
|-------|------|-------------|
| both `false` (default) | filter | Drops events per local or centralized policy |
| `optimize: true` | optimize | Filter and losslessly compact events for 50-65% volume reduction |
| `readOnly: true` | report | Read-only observation. Emits cost and usage metrics without modifying the event stream |

`tenx.optimize` and `tenx.readOnly` are mutually exclusive.

## Configuration

### Log10x Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tenx.enabled` | Enable Log10x engine | `true` |
| `tenx.variant` | Runtime variant: `jit` or `native` | `jit` |
| `tenx.debug` | Enable debug logging | `false` |
| `tenx.apiKey` | Log10x API key (license) | `""` |
| `tenx.optimize` | Losslessly compact events for 50-65% volume reduction (mutually exclusive with `readOnly`) | `false` |
| `tenx.readOnly` | Read-only mode: observe events and emit metrics without modifying the stream (mutually exclusive with `optimize`) | `false` |
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
| `imageTag` | Image tag (defaults to `{appVersion}-{variant}`) | `""` |
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
- All modes use a JavaScript processor to integrate with the Log10x pipeline; the read-back input is omitted in `readOnly` mode

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

**Note:** The Log10x engine requires a commercial license. See [Log10x Pricing](https://log10x.com/pricing) for details.
