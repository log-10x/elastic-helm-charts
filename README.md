# Log10x Elastic Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

This repository contains [Helm](https://helm.sh/) charts for Elastic Stack components with integrated [Log10x](https://log10x.com) sidecar support.

**Forked from:** [elastic/helm-charts](https://github.com/elastic/helm-charts)

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repo as follows:

```console
helm repo add log10x-elastic https://log-10x.github.io/elastic-helm-charts
```

## Helm Charts

You can then run `helm search repo elastic` to see the charts.

| Chart | Description |
|-------|-------------|
| [filebeat](./charts/filebeat) | Log10x enhanced Filebeat |
| [logstash](./charts/logstash) | Log10x enhanced Logstash |

### Installation Examples

```bash
# Install Filebeat with Log10x
helm install my-filebeat log10x-elastic/filebeat -f values.yaml

# Install Logstash with Log10x
helm install my-logstash log10x-elastic/logstash -f values.yaml
```

## Log10x Integration

Enable Log10x by setting `tenx.enabled: true` in your values file:

```yaml
tenx:
  enabled: true
  apiKey: "YOUR-LICENSE-KEY"
  kind: "regulate"  # Options: report, regulate, optimize
  runtimeName: "my-instance"

  # Optional: GitOps configuration
  github:
    config:
      enabled: true
      token: "YOUR-GITHUB-TOKEN"
      repo: "YOUR-ORG/YOUR-CONFIG-REPO"
```

### Log10x Modes

| Mode | Description |
|------|-------------|
| `report` | Analytics-only mode - generates cost and usage metrics without modifying logs |
| `regulate` | Filtering mode - reduces log volume based on configured rules |
| `optimize` | Full optimization - reduces log volume while preserving information |

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Edge Reporter Deployment](https://doc.log10x.com/apps/edge/reporter/deploy/)
- [Edge Regulator Deployment](https://doc.log10x.com/apps/edge/regulator/deploy/)
- [Edge Optimizer Deployment](https://doc.log10x.com/apps/edge/optimizer/deploy/)

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

### Important: Log10x Product License Required

This repository contains deployment tooling for Log10x with Elastic Stack components. While the tooling
itself is open source, **using Log10x requires a commercial license**.

| Component | License |
|-----------|---------|
| This repository (Helm charts) | Apache 2.0 (open source) |
| Log10x engine and runtime | Commercial license required |

**What this means:**
- You can freely use, modify, and distribute these Helm charts
- The Log10x software that these charts deploy requires a paid subscription
- A valid Log10x API key is required to run the deployed software

**Get Started:**
- [Log10x Pricing](https://log10x.com/pricing)
- [Documentation](https://doc.log10x.com)
- [Contact Sales](mailto:sales@log10x.com)

## Credits

Based on the official [Elastic Helm Charts](https://github.com/elastic/helm-charts).
