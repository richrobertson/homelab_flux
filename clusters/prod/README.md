# Cluster Prod

`clusters/prod/` is the Flux bootstrap and reconciliation root for the production environment.

## Purpose

- Connects production clusters to infrastructure and app manifests.
- Represents the authoritative live state for user-facing workloads.
- Applies validated changes promoted from staging.

## Typical contents

- `apps.yaml`: points Flux to `apps/prod`.
- `infrastructure.yaml`: points Flux to shared infrastructure layers.
- `flux-system/`: Flux bootstrap artifacts and source configuration.

## Operational notes

- Use production context carefully before any forced reconcile.
- Keep rollout changes small and monitor health during reconciliation.
- Prefer staging-first verification for chart upgrades and major config edits.

## See also

- [Clusters overview](../README.md)
- [Staging cluster docs](../staging/README.md)
- [Production Flux bootstrap docs](flux-system/README.md)
- [Production app overlays](../../apps/prod/README.md)
- [Shared infrastructure](../../infrastructure/README.md)