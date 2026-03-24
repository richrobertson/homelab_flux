# P0 CRDs

CustomResourceDefinition manifests required before controller deployment.

## Purpose

- Installs foundational CRDs consumed by higher-level infrastructure layers.
- Prevents reconciliation failures caused by missing API types.

## In this folder

- CRD manifests that are treated as early bootstrap prerequisites.

## Notes

- Keep versions aligned with the controllers that own these APIs.


## Parent/Siblings

- Parent: [P0](../README.md)
- Siblings: [Namespaces](../namespaces/README.md); [Node Feature Discovery](../node-feature-discovery/README.md); [Vault Secrets Operator](../vault-secrets-operator/README.md).
