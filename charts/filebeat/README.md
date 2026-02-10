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
  kind: "regulate"  # Options: report, regulate, optimize
  variant: "jit"    # Options: jit, native
  runtimeName: "my-filebeat-instance"

  # Optional: GitOps configuration
  github:
    config:
      enabled: true
      token: "YOUR-GITHUB-TOKEN"
      repo: "YOUR-ORG/YOUR-CONFIG-REPO"
      branch: "main"  # Optional
    symbols:
      enabled: true
      token: "YOUR-GITHUB-TOKEN"
      repo: "YOUR-ORG/YOUR-SYMBOLS-REPO"
      branch: "main"  # Optional
      path: "path/to/symbols"  # Optional
```

### Log10x Modes

| Mode | Description |
|------|-------------|
| `report` | Analytics-only mode - generates cost and usage metrics without modifying logs |
| `regulate` | Filtering mode - reduces log volume based on configured rules |
| `optimize` | Full optimization - reduces log volume while preserving information |

## Configuration

### Log10x Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tenx.enabled` | Enable Log10x engine | `true` |
| `tenx.variant` | Runtime variant: `jit` or `native` | `jit` |
| `tenx.debug` | Enable debug logging | `false` |
| `tenx.apiKey` | Log10x API key (license) | `""` |
| `tenx.kind` | Operation mode: `report`, `regulate`, or `optimize` | `regulate` |
| `tenx.runtimeName` | Optional name for this runtime instance | `""` |
| `tenx.github.image.repository` | GitHub config fetcher image | `ghcr.io/log-10x/github-config-fetcher` |
| `tenx.github.image.tag` | GitHub config fetcher image tag | `0.9.0` |
| `tenx.github.config.enabled` | Enable fetching config from GitHub | `false` |
| `tenx.github.config.token` | GitHub access token for config repo | `""` |
| `tenx.github.config.repo` | Config repository (e.g., `org/repo`) | `""` |
| `tenx.github.config.branch` | Branch to pull (optional) | `""` |
| `tenx.github.symbols.enabled` | Enable fetching symbols from GitHub | `false` |
| `tenx.github.symbols.token` | GitHub access token for symbols repo | `""` |
| `tenx.github.symbols.repo` | Symbols repository (e.g., `org/repo`) | `""` |
| `tenx.github.symbols.branch` | Branch to pull (optional) | `""` |
| `tenx.github.symbols.path` | Sub-path within repo for symbols | `""` |

### Filebeat Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image` | Filebeat Docker image | `ghcr.io/log-10x/filebeat-10x` |
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
- The Log10x engine is bundled in the `ghcr.io/log-10x/filebeat-10x` image
- Default configuration sends logs to Elasticsearch using credentials from `elasticsearch-master-credentials` secret
- Kubernetes metadata enrichment is enabled by default
- The `regulate` and `optimize` modes use a JavaScript processor to integrate with the Log10x pipeline

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
- `filebeat-report.yaml` - Reporter mode for analytics
- `filebeat-regulate.yaml` - Regulator mode for filtering
- `filebeat-optimize.yaml` - Optimizer mode for full optimization

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Edge Reporter Deployment](https://doc.log10x.com/apps/edge/reporter/deploy/)
- [Edge Regulator Deployment](https://doc.log10x.com/apps/edge/regulator/deploy/)
- [Edge Optimizer Deployment](https://doc.log10x.com/apps/edge/optimizer/deploy/)

## License

This chart is licensed under the Apache License 2.0.

**Note:** The Log10x engine requires a commercial license. See [Log10x Pricing](https://log10x.com/pricing) for details.
