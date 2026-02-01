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
  apiKey: "YOUR-LICENSE-KEY"
  kind: "regulate"  # Options: report, regulate, optimize
  runtimeName: "my-logstash-instance"

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
| `tenx.enabled` | Enable Log10x sidecar container | `false` |
| `tenx.image.repository` | Log10x container image repository | `ghcr.io/log-10x/tenx` |
| `tenx.image.tag` | Log10x container image tag | `0.35.1-jit` |
| `tenx.variant` | Runtime variant: `jit` or `native` | `jit` |
| `tenx.apiKey` | Log10x API key (license) | `""` |
| `tenx.kind` | Operation mode: `report`, `regulate`, or `optimize` | `regulate` |
| `tenx.runtimeName` | Optional name for this runtime instance | `""` |
| `tenx.resources` | Resource limits for Log10x sidecar | see values.yaml |
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
- When using Log10x, the sidecar container communicates with Logstash via Unix socket
- Configuration files can be set via ConfigMap using `logstashConfig`
- When overriding `logstash.yml`, always include `http.host: 0.0.0.0` for probes to work

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Edge Reporter Deployment](https://doc.log10x.com/apps/edge/reporter/deploy/)
- [Edge Regulator Deployment](https://doc.log10x.com/apps/edge/regulator/deploy/)
- [Edge Optimizer Deployment](https://doc.log10x.com/apps/edge/optimizer/deploy/)

## License

This chart is licensed under the Apache License 2.0.

**Note:** The Log10x engine requires a commercial license. See [Log10x Pricing](https://log10x.com/pricing) for details.
