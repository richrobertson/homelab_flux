# Apps

This directory contains all application-level GitOps manifests managed by Flux.

## Purpose

- Defines the user-facing and platform-adjacent services deployed into the cluster.
- Separates reusable application definitions from environment-specific overlays.
- Provides a clean promotion model from `staging` to `prod`.

## Subsections

- `base/`: canonical app definitions (Helm repositories/releases, common resources).
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

## See also

- [Repository root](../README.md)
- [Apps base](base/README.md)
- [Apps staging overlays](staging/README.md)
- [Apps production overlays](prod/README.md)