# Dashboards

`infrastructure/configs/dashboards/` stores Grafana dashboard JSON definitions.

## Purpose

- Version controls dashboard layout and query logic as code.
- Enables reproducible observability views across clusters.
- Supports reviewable changes to SRE/operator UX.

## What this subset contains

- Service-level and gateway-level drilldown dashboards.
- Performance, traffic, and error-rate visualizations.
- Domain-specific dashboards tied to infrastructure components.

## Maintenance guidelines

- Keep dashboard IDs, titles, and folder targets stable when possible.
- Prefer incremental panel/query updates over full rewrites.
- Validate Prometheus query compatibility when metrics sources change.


## Parent/Siblings

- Parent: [Configs](../README.md)
- Siblings: None.
