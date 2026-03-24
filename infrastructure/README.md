# Infrastructure

`infrastructure/` contains the shared platform layers that applications depend on.

## Purpose

- Installs and configures foundational components required by all environments.
- Separates platform concerns from app-specific deployment manifests.
- Maintains an ordered dependency chain for predictable reconciliation.

## Subsections

- `p0/`: bootstrap-level prerequisites (CRDs, namespaces, essential operators).
- `controllers/`: continuously running control-plane extensions and operators.
- `configs/`: cluster configuration objects, dashboards, alerting, and shared policies.
- `gateway/`: ingress and service exposure definitions.

## Dependency role

Infrastructure layers are reconciled before applications to guarantee required APIs, classes, and routing primitives exist.

## See also

- [Repository root](../README.md)
- [P0 prerequisites](p0/README.md)
- [Controllers](controllers/README.md)
- [Configs](configs/README.md)
- [Gateway](gateway/README.md)