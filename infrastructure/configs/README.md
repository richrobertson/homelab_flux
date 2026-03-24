# Infrastructure Configs

`infrastructure/configs/` contains shared cluster configuration resources that tune platform behavior.

## Purpose

- Defines non-controller platform objects such as issuers, pool configs, monitors, alerts, and dashboards.
- Keeps policy and operational config separate from controller lifecycle manifests.
- Provides cluster-wide settings consumed by observability and gateway layers.

## Typical resource groups

- Certificate and issuer configuration.
- Load balancer/BGP/IP pool configuration.
- Prometheus alert and scrape definitions.
- Dashboard provisioning ConfigMaps and dashboard JSON assets.
- Miscellaneous operational tooling manifests.

## Subsections

- `dashboards/`: JSON dashboards used for Grafana provisioning.

## Conventions

- Treat this directory as shared config for both environments unless an overlay explicitly diverges.
- Name resources consistently to simplify alert/dashboard traceability.
- Keep high-impact defaults reviewed with production behavior in mind.

## See also

- [Infrastructure overview](../README.md)
- [Dashboards](dashboards/README.md)
