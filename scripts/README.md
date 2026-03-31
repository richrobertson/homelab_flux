# Scripts

`scripts/` contains helper automation used for local and CI validation workflows.

## Purpose

- Provides repeatable checks before changes are reconciled by Flux.
- Standardizes validation behavior across developer machines and pipelines.
- Reduces broken-manifest risk by enforcing schema and render checks.

## Current contents

- `validate.sh`: end-to-end repo validation workflow.
- `APP_CEPH_MIGRATION_RUNBOOK.md`: repeatable cutover process for app config PVC migration from Synology to CephFS, including latest execution status.
- `noenc-sc-test-20260325.yaml`: ad-hoc StorageClass manifest used for CephFS no-encryption provisioning diagnostics.
- `noenc-pvc-ab-20260325.yaml`: ad-hoc PVC probes used with the no-encryption test StorageClass during CephFS diagnostics.

## Expected validation flow

The validation script is designed to:

1. Pull required schemas/dependencies for validation.
2. Lint YAML structure and basic consistency.
3. Validate cluster manifests against schemas.
4. Build kustomizations and validate rendered output.

## Usage guidance

- Run validation before pushing or opening a PR.
- Use the same tooling versions in CI where possible.
- Treat validation failures as blockers for promotion.

## See also

- [Repository root](../README.md)
- [App Ceph migration runbook](./APP_CEPH_MIGRATION_RUNBOOK.md)


## Parent/Siblings

- Parent: [homelab_flux](../README.md)
- Siblings: [Apps](../apps/README.md); [Clusters](../clusters/README.md); [Infrastructure](../infrastructure/README.md).
