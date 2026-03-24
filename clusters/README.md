# Clusters

`clusters/` contains Flux entrypoints for each managed environment.

## Purpose

- Defines the reconciliation roots Flux bootstraps from for each cluster.
- Establishes ordering and dependency flow for infrastructure and applications.
- Keeps environment wiring explicit and isolated by cluster.

## Subsections

- `staging/`: Flux manifests and kustomization chain for staging.
- `prod/`: Flux manifests and kustomization chain for production.

## Reconciliation model

Each cluster directory typically orchestrates the same staged dependency order:

`infra-p0 -> infra-controllers -> infra-configs -> infra-gateway -> apps`

This order ensures foundational resources exist before higher-level services are applied.

## See also

- [Repository root](../README.md)
- [Staging cluster docs](staging/README.md)
- [Production cluster docs](prod/README.md)