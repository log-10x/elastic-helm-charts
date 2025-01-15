# Log10x Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/fluent-helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/fluent-helm-charts/actions)

## Add the Log10x Elastic Helm repository

```sh
helm repo add log10x-elastic https://log-10x.github.io/elastic-helm-charts
```

You can then run `helm search repo log10x-elastic` to see the charts.

## Install Log10x Filebeat

```sh
helm upgrade -i log10x-filebeat log10x-elastic/log10x-filebeat
```

For more details on installing Log10x Filebeat please see the [chart's README](https://github.com/log-10x/elastic-helm-charts/tree/main/charts/filebeat).

## License

[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)
