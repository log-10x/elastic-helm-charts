# Log10x Elastic Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

This repository contains [Helm](https://helm.sh/) charts for Elastic Stack components with integrated [Log10x](https://www.log10x.com/?utm_source=github&utm_medium=readme&utm_campaign=elastic-helm-charts&utm_content=hero) sidecar support.

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
| [logstash](./charts/logstash) | Log10x enhanced Logstash **(deprecated)** |

> [!NOTE]
> The **logstash** chart is deprecated (`deprecated: true`). Logstash now runs 10x as a
> `log10x/edge-10x` sidecar container on the upstream `elastic/logstash` chart, not via this
> fork. It stays installable for legacy use; see the
> [Receiver deployment guide](https://doc.log10x.com/apps/receiver/deploy/).

### Installation Examples

```bash
# Install Filebeat with Log10x
helm install my-filebeat log10x-elastic/filebeat -f values.yaml

# Install Logstash with Log10x (DEPRECATED - prefer the edge-10x sidecar on the upstream elastic/logstash chart)
helm install my-logstash log10x-elastic/logstash -f values.yaml
```

## Log10x Integration

Enable Log10x by setting `tenx.enabled: true` in your values file:

```yaml
tenx:
  enabled: true
  apiKey: "YOUR-LICENSE-KEY"
  kind: "receive"  # Options: report, receive, optimize
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
| `report` | Read-only observation. Emits cost and usage metrics without modifying the event stream |
| `receive` | Filter mode. Drops events per local or centralized policy |
| `optimize` | Filter and losslessly compact events |

## Documentation

- [Log10x Documentation](https://doc.log10x.com)
- [Receiver Deployment](https://doc.log10x.com/apps/receiver/deploy/)

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

### Log10x license

This repository contains deployment tooling for Log10x with Elastic Stack components. The tooling
is open source. The Log10x engine it deploys runs on the built-in Free tier with no license token on up to 10 nodes, with no expiry; above 10 nodes it takes a paid license.

| Component | License |
|-----------|---------|
| This repository (Helm charts) | Apache 2.0 (open source) |
| Log10x engine and runtime | Free tier on up to 10 nodes; paid license above 10 |

**What this means:**
- You can freely use, modify, and distribute these Helm charts
- The Log10x engine runs with no license token on up to 10 nodes
- Above 10 nodes, the engine takes a paid license

**Get Started:**
- [Log10x Pricing](https://www.log10x.com/pricing?utm_source=github&utm_medium=readme&utm_campaign=elastic-helm-charts&utm_content=footer)
- [Documentation](https://doc.log10x.com)
- [Contact Sales](mailto:sales@log10x.com)

## Credits

Based on the official [Elastic Helm Charts](https://github.com/elastic/helm-charts).
