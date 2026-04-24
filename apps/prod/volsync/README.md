# VolSync (Prod)

Production helper resources for VolSync backups to Backblaze B2 via the S3-compatible API.

## Purpose

- Provides helper PVCs and cleanup CronJobs used by production VolSync backups.
- Documents the shared Backblaze secret contract used to render per-repository restic secrets.
- Keeps operational notes close to the backup workflows.
- Leaves the shared VolSync controller and most live repository/ReplicationSource resources under `infrastructure/`.

## In this folder

- Kustomization wiring for prod VolSync helper resources.
- V3 backup-source PVC definitions.
- Cleanup CronJobs for stale locks and released backup PVs.

## Active Source Of Truth

- Controller manifests live under `infrastructure/controllers/volsync`.
- Shared Backblaze `SecretTransformation`, most active `VaultStaticSecret`, and most `ReplicationSource` manifests live under `infrastructure/configs/volsync`.
- App-scoped prod backups for `n8n` and `task-control-plane` still live under their app overlays and reuse the shared Backblaze transformation.
- This folder intentionally excludes those live resources to avoid Flux ownership drift.

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
- plex-config-ceph

## Vault secret requirements

Shared Vault path:

- `secret/backblaze/k8s/prod/volsync`

The shared path should provide:

- `RESTIC_PASSWORD`
- Either `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` or Backblaze-style app key fields such as `applicationKeyId`/`applicationKey`

Optional overrides supported by the shared transformation:

- `AWS_REGION` or `AWS_DEFAULT_REGION`
- `S3_ENDPOINT`, `AWS_ENDPOINT`, or `B2_ENDPOINT`
- `S3_BUCKET`, `B2_BUCKET`, or `BUCKET_NAME`

The transformation renders the Kubernetes repository secret fields VolSync expects:

- `RESTIC_REPOSITORY`
- `RESTIC_PASSWORD`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_DEFAULT_REGION`

Seed reference:

- [Vault seed template](VAULT_SEED_TEMPLATE.md)
- Region is centralized in the template via AWS_REGION for one-line changes.

## Known Issues & Remediation

### Stale Restic Locks

**Problem:** When a volsync pod crashes without releasing its lock, the lock persists in the S3 backend indefinitely, blocking all subsequent backups.

**Evidence:** [Incident post-mortem (2026-04-11)](INCIDENT_POSTMORTEM_2026-04-11.md)

**Automation:** A CronJob `volsync-stale-lock-cleanup` runs every 10 minutes to detect and remove stale locks across all repositories.

**Manual Recovery (if needed):** See the post-mortem appendix for quick recovery commands.

---

## References

- [Incident Post-Mortem: Stale Lock Contention (2026-04-11)](INCIDENT_POSTMORTEM_2026-04-11.md)

## Bucket structure

- CNPG backups: s3://homelab-prod-backups/cnpg/<cluster-name>
- VolSync backups: s3://myrobertson-k8s-prod-volsync/volsync/default/<pvc-name>

For VolSync restic secrets, the shared transformation renders `RESTIC_REPOSITORY` with the Backblaze endpoint and path-style URL format, for example:

- s3:https://s3.us-west-002.backblazeb2.com/myrobertson-k8s-prod-volsync/volsync/default/immich-data-files-pvc-ceph

## Encryption

- Restic encrypts repository contents client-side using `RESTIC_PASSWORD`; production backups remain unreadable without that key.

## Retention policy (prod)

VolSync retain settings are defined per ReplicationSource in `infrastructure/configs/volsync/replicationsources.yaml`:

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
