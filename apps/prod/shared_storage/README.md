# Shared Storage (Prod)

`apps/prod/shared_storage/` is a documentation placeholder for production storage behavior shared across overlays.

## Current state

- No dedicated production manifests live here today.
- Durable storage behavior is expressed in individual app overlays, shared storage classes, and VolSync backup definitions.
- Use the runbooks under `../../../docs/runbooks/` when making storage migrations or cutover changes.

## See also

- [Apps Prod](../README.md)
- [Shared Storage (Base)](../../base/shared_storage/README.md)
- [VolSync production](../volsync/README.md)
- [Storage Classes](../../../infrastructure/controllers/storage-classes/README.md)
