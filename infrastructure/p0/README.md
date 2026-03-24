# Infrastructure P0

`infrastructure/p0/` contains the earliest prerequisite resources in the Flux dependency chain.

## Purpose

- Ensures cluster-scoped prerequisites exist before higher-level controllers/configs are applied.
- Installs essential CRDs and namespaces consumed by later layers.
- Bootstraps critical base operators for downstream infrastructure.

## Subsections

- `crds/`: custom resource definitions needed by managed controllers.
- `namespaces/`: baseline namespace declarations.
- `node-feature-discovery/`: hardware capability discovery setup.
- `vault-secrets-operator/`: secrets operator bootstrap resources.

## Guidance

- Keep this layer minimal and stable.
- Add only true prerequisites here to avoid overloading bootstrap risk.
- Validate CRD compatibility before upgrading dependent controllers.

## See also

- [Infrastructure overview](../README.md)
- [CRDs](crds/README.md)
- [Namespaces](namespaces/README.md)
- [Node Feature Discovery](node-feature-discovery/README.md)
- [Vault Secrets Operator](vault-secrets-operator/README.md)
