# Cluster Staging

`clusters/staging/` is the Flux bootstrap and reconciliation root for the staging environment.

## Purpose

- Wires staging to shared infrastructure and app overlays.
- Provides a pre-production validation path for GitOps changes.
- Allows safe verification of upgrades and configuration changes.

## Typical contents

- `apps.yaml`: points Flux to `apps/staging`.
- `infrastructure.yaml`: points Flux to shared infrastructure layers.
- `flux-system/`: Flux bootstrap artifacts and source configuration.

## Operational notes

- Use the staging Kubernetes context before manual reconcile commands.
- Expect lower scale and less strict SLO targets than production.
- Keep staging representative enough to catch upgrade and config regressions.

## See also

- [Clusters overview](../README.md)
- [Production cluster docs](../prod/README.md)
- [Staging Flux bootstrap docs](flux-system/README.md)
- [Staging app overlays](../../apps/staging/README.md)
- [Shared infrastructure](../../infrastructure/README.md)