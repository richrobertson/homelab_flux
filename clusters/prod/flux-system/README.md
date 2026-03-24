# Prod Flux System

`clusters/prod/flux-system/` contains Flux bootstrap manifests for the production cluster.

## Purpose

- Defines the Flux control-plane components installed in-cluster.
- Configures Git source synchronization and reconciliation root for production.
- Serves as generated/managed bootstrap state for Flux lifecycle.

## In this folder

- `gotk-components.yaml`: Flux controller component manifests.
- `gotk-sync.yaml`: GitRepository/Kustomization sync configuration.
- `kustomization.yaml`: kustomize entrypoint for flux-system resources.

## See also

- [Prod cluster docs](../README.md)
- [Clusters overview](../../README.md)
- [Staging Flux bootstrap docs](../../staging/flux-system/README.md)
- [Repository root](../../../README.md)


## Parent/Siblings

- Parent: [Prod](../README.md)
- Siblings: None.
