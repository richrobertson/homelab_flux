# Apps

This directory contains the application-level GitOps manifests managed by Flux.

## Purpose

- Defines the user-facing and platform-adjacent services deployed into the cluster.
- Separates reusable application definitions from environment-specific overlays.
- Provides a clean promotion path from `staging` to `prod`.

## Layout

- `base/`: shared app definitions, repositories, and common manifests.
- `staging/`: staging overlays and environment-specific patches.
- `prod/`: production overlays and environment-specific patches.

## Workflow

1. Add or update shared resources in `base/` first.
2. Apply environment-specific overrides in `staging/` and/or `prod/`.
3. Reconcile the `apps` Flux Kustomization for the target cluster context.

## Conventions

- Keep names, namespaces, and chart references consistent across environments.
- Avoid copying full manifests into overlays when a patch is sufficient.
- Put defaults in `base/`, then override only what differs by environment.
- Keep cross-app operational procedures in `../docs/runbooks/`.

## Documentation notes

- `base/README.md`, `staging/README.md`, and `prod/README.md` are the main app indexes.
- Not every app directory has a dedicated README yet; the environment index pages call that out explicitly.
- Shared storage references resolve through lightweight `shared_storage/README.md` placeholders in each app layer.

## See also

- [Repository root](../README.md)
- [Docs overview](../docs/README.md)
- [Runbook index](../docs/runbooks/README.md)
- [Apps base](base/README.md)
- [Apps staging overlays](staging/README.md)
- [Apps production overlays](prod/README.md)
