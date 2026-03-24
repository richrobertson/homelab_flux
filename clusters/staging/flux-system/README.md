# Staging Flux System

`clusters/staging/flux-system/` contains Flux bootstrap manifests for the staging cluster.

## Purpose

- Defines the Flux control-plane components installed in-cluster.
- Configures Git source synchronization and reconciliation root for staging.
- Serves as generated/managed bootstrap state for Flux lifecycle.

## In this folder

- `gotk-components.yaml`: Flux controller component manifests.
- `gotk-sync.yaml`: GitRepository/Kustomization sync configuration.
- `kustomization.yaml`: kustomize entrypoint for flux-system resources.

## See also

- [Staging cluster docs](../README.md)
- [Clusters overview](../../README.md)
- [Production Flux bootstrap docs](../../prod/flux-system/README.md)
- [Repository root](../../../README.md)


## Parent/Siblings

- Parent: [Staging](../README.md)
- Siblings: None.
