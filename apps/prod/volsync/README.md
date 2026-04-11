# VolSync (Prod)

Production overlay for VolSync backups to S3-compatible object storage.

## Purpose

- Enables scheduled Restic backups for production PVCs.
- Uses Vault-managed restic repository secrets per PVC.
- Keeps VolSync chart defaults in base and applies prod-specific values here.

## In this folder

- kustomization wiring for prod VolSync resources.
- VaultStaticSecret resources for restic repository configuration.
- ReplicationSource resources for each protected production PVC.

## Covered PVCs

- authelia-config-ceph
- cluster-authelia-ceph-1
- immich-data-files-pvc-ceph
- cluster-immich-ceph-1
- lidarr-config-ceph
- lidarr-data-files-pvc
- mealie-data-ceph
- mealie-cnpg-main-1
- mealie-cnpg-main-1-wal
- overseerr-config-ceph
- overseerr-data-files-pvc
- prowlarr-config-ceph
- prowlarr-data-files-pvc
- radarr-config-ceph
- radarr-data-files-pvc
- sonarr-config-ceph
- sonarr-data-files-pvc
- syncthing-config-ceph

## Vault secret requirements

Each Vault path under secret/volsync/prod/<pvc-name> should provide:

- RESTIC_REPOSITORY
- RESTIC_PASSWORD
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

Seed reference:

- [Vault seed template](VAULT_SEED_TEMPLATE.md)
- Region is centralized in the template via AWS_REGION for one-line changes.

## Known Issues & Remediation

### Stale Restic Locks

**Problem:** When a volsync pod crashes without releasing its lock, the lock persists in the S3 backend indefinitely, blocking all subsequent backups.

**Evidence:** [Incident post-mortem (2026-04-11)](INCIDENT_POSTMORTEM_2026-04-11.md)

**Automation:** A CronJob `volsync-stale-lock-cleanup` runs every 2 hours to detect and remove stale locks across all repositories.

**Manual Recovery (if needed):** See the post-mortem appendix for quick recovery commands.

---

## References

- [Incident Post-Mortem: Stale Lock Contention (2026-04-11)](INCIDENT_POSTMORTEM_2026-04-11.md)

## Bucket structure

- CNPG backups: s3://homelab-prod-backups/cnpg/<cluster-name>
- VolSync backups: s3://homelab-prod-backups/volsync/default/<pvc-name>

For VolSync restic secrets, set RESTIC_REPOSITORY with the S3 endpoint and path-style URL format, for example:

- s3:s3.us-west-2.amazonaws.com/homelab-prod-backups/volsync/default/immich-data-files-pvc-ceph

## Retention policy (prod)

VolSync retain settings are defined per ReplicationSource in `replicationsources.yaml`:

- schedule: every hour at the source's assigned minute offset
- hourly: 4
- daily: 0
- weekly: 0
- monthly: 0
- yearly: 0
- pruneIntervalDays: 1

Policy intent:

- Run each protected PVC backup once per hour.
- Keep only the latest 4 hourly snapshots per repository.
- Prune daily so expired hourly snapshots are reclaimed promptly.

## Operational verification

Check current retain settings in-cluster:

```bash
kubectl --context admin@prod get replicationsource -n default \
  -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.trigger.schedule,HOURLY:.spec.restic.retain.hourly,DAILY:.spec.restic.retain.daily,WEEKLY:.spec.restic.retain.weekly,MONTHLY:.spec.restic.retain.monthly,YEARLY:.spec.restic.retain.yearly,PRUNE_DAYS:.spec.restic.pruneIntervalDays
```

Check recent sync status:

```bash
kubectl --context admin@prod get replicationsource -n default \
 -o custom-columns=NAME:.metadata.name,LASTSYNC:.status.lastSyncTime,CONDITIONS:.status.conditions
```

## Parent/Siblings

- Parent: [Prod](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
