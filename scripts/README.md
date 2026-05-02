# Scripts

`scripts/` contains helper automation, diagnostics, and one-off manifests used during validation and day-2 operations.

## What lives here

- Validation: `validate.sh`
- Diagnostics and maintenance helpers: `namespace-audit.sh`, `cephfs-mds-tuning-pass.sh`, `telegram_backfill.py`
- Nextcloud migration validation: `nextcloud-webdav-migration-smoke-test.sh`, `nextcloud-share-migration-smoke-test.sh`
- One-off migration manifests: `migrate-*-config-pod.yaml`, `recovery-synology-pvcs.yaml`, and `migrations/`
- Historical notes that are still colocated here for now: `CEPH_ROOTCAUSE_ANALYSIS.md`, `RADOS_NAMESPACE_INVENTORY.md`, `STAGING_PLEX_IGPU_VALIDATION_2026-04-01.md`, `CLEANUP_READY_TO_PUSH.md`, `CLEANUP_COMPLETION_REPORT.md`

## Expected validation flow

The validation script is designed to:

1. Pull required schemas and dependencies for validation.
2. Lint YAML structure and basic consistency.
3. Validate cluster manifests against schemas.
4. Build kustomizations and validate rendered output.

## Operational docs

- Shared runbooks and migration playbooks now live in `../docs/runbooks/`.
- Keep reusable procedures there instead of adding more runbooks to `scripts/`.
- Leave script-adjacent notes here only when they are tightly coupled to a helper or investigation artifact.

## Usage guidance

- Run validation before pushing or opening a PR.
- Use the same tooling versions in CI where possible.
- Treat validation failures as blockers for promotion.

## See also

- [Repository root](../README.md)
- [Docs overview](../docs/README.md)
- [Runbook index](../docs/runbooks/README.md)
- [App Ceph migration runbook](../docs/runbooks/APP_CEPH_MIGRATION_RUNBOOK.md)
- [SynologyNAS container migration playbook](../docs/runbooks/APP_SYNOLOGYNAS_CONTAINER_MIGRATION_PLAYBOOK.md)
- [Prod VolSync backups and retention](../apps/prod/volsync/README.md)
