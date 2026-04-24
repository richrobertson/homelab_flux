# Shared Storage (Base)

`apps/base/shared_storage/` is a documentation anchor for storage patterns shared across multiple applications.

## Current state

- There are no standalone base manifests in this directory today.
- Shared storage behavior is currently modeled through app-local PVC manifests under `apps/base/<app>/` and cluster-wide storage classes under `infrastructure/controllers/storage-classes/`.
- Backup and replication workflows are documented with VolSync rather than here.

## See also

- [Apps Base](../README.md)
- [VolSync base](../volsync/README.md)
- [Storage Classes](../../../infrastructure/controllers/storage-classes/README.md)
