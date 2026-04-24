# Shared Storage (Staging)

`apps/staging/shared_storage/` is a documentation placeholder for staging storage behavior shared across overlays.

## Current state

- No dedicated staging manifests live here today.
- Storage differences are expressed in individual app overlays plus shared infrastructure resources.
- Use staging to validate PVC, storage class, and migration changes before promotion to production.

## See also

- [Apps Staging](../README.md)
- [Shared Storage (Base)](../../base/shared_storage/README.md)
- [VolSync staging](../volsync/README.md)
- [Storage Classes](../../../infrastructure/controllers/storage-classes/README.md)
