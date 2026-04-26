# Runbooks

`docs/runbooks/` is the standard home for reusable operational procedures in this repository.

## Runbook index

- [App Ceph migration runbook](APP_CEPH_MIGRATION_RUNBOOK.md): migrate app config PVCs from Synology-backed storage to CephFS.
- [Ceph public/client Thunderbolt cutover](CEPH_PUBLIC_CLIENT_THUNDERBOLT_CUTOVER.md): staged process for moving Ceph client traffic to the Thunderbolt ring.
- [Bitwarden Synology to Ceph migration runbook](APP_BITWARDEN_MIGRATION_RUNBOOK.md): historical execution reference for the Vaultwarden cutover.
- [SynologyNAS container migration playbook](APP_SYNOLOGYNAS_CONTAINER_MIGRATION_PLAYBOOK.md): reusable migration pattern for stateful Synology-to-Kubernetes moves.
- [Ceph pool consolidation runbook](CEPH_POOL_CONSOLIDATION_RUNBOOK.md): staged storage-pool consolidation plan and validation sequence.
- [Plex VAAPI option 3 runbook](PLEX_VAAPI_OPTION3_RUNBOOK.md): custom image build and rollout procedure for Plex hardware transcoding.

## Conventions

- Put reusable operational procedures here.
- Keep incident reports, postmortems, and experiment recaps next to the affected component unless there is a strong reason to centralize them.
- Prefer linking to these docs from README indexes instead of duplicating instructions across the repo.

## See also

- [Docs overview](../README.md)
- [Repository root](../../README.md)
- [Scripts overview](../../scripts/README.md)
- [Prod VolSync backups and retention](../../apps/prod/volsync/README.md)
