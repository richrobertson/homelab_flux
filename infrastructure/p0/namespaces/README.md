# P0 Namespaces

Baseline namespace definitions for the platform.

## Purpose

- Ensures required namespaces exist before dependent resources reconcile.
- Provides consistent namespace ownership and lifecycle via GitOps.

## In this folder

- Namespace objects and optional labels/annotations required at bootstrap.

## Notes

- Treat namespace renames/deletions as high-impact changes.


## Parent/Siblings

- Parent: [P0](../README.md)
- Siblings: [CRDs](../crds/README.md); [Node Feature Discovery](../node-feature-discovery/README.md); [Vault Secrets Operator](../vault-secrets-operator/README.md).
