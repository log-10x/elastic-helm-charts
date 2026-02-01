# 10x + Elastic Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/elastic-helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/elastic-helm-charts/actions)

## Add the 10x + Elastic Helm repository

```sh
helm repo add log10x-elastic https://log-10x.github.io/elastic-helm-charts
```

You can then run `helm search repo elastic` to see the charts.

## Install Filebeat + 10x observability engine

```sh
helm upgrade -i filebeat-10x log10x-elastic/filebeat
```

For more details on installing Filebeat + 10x observability engine please see the [chart's README](https://github.com/log-10x/elastic-helm-charts/tree/main/charts/filebeat).


## Install Logstash + 10x observability engine

```sh
helm upgrade -i logstash-10x log10x-elastic/logstash
```

For more details on installing Logstash + 10x observability engine please see the [chart's README](https://github.com/log-10x/elastic-helm-charts/tree/main/charts/logstash).

## License

[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)
