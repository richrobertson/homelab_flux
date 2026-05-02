# Nextcloud S3 to Synology NFS Production Cutover - 2026-05-02

Production Nextcloud was cut over from AWS S3 primary object storage to a
filesystem-backed, Synology NFS-backed Kubernetes PVC on 2026-05-02.

## Final State

- Public route: `cloud.myrobertson.com` routes to
  `nextcloud/nextcloud-migration-ldap`.
- Target user data: `nextcloud/nextcloud-data` mounted at
  `/var/www/html/data` from Synology NFS path
  `/volume1/nextcloud-data-prod/strategy-a-prod-ldap-data/data`.
- Target app/config PVC: `nextcloud-migration-ldap-html` on CephFS.
- Target database: `nextcloud-migration-ldap-cnpg` on `ceph-block`.
- Target auth: LDAP-backed users validated with `php occ ldap:test-config s01`.
- Target encryption: Nextcloud server-side encryption enabled with
  `OC_DEFAULT_MODULE`.
- Source S3-backed stack: `default/nextcloud` retained for rollback and
  history. After validation, the old source app was scaled to zero; its CNPG
  database, app/config PVC, S3 bucket, secrets, manifests, and restore captures
  remain retained.
- S3 bucket: retained. It was not deleted or raw-copied into the target data
  directory.

## Accepted Boundary

The cutover intentionally migrated current WebDAV-visible user files only.
Trashbin data was explicitly accepted as out of scope. Historical file versions
were not migrated as Nextcloud version state by the plain WebDAV Strategy A
copy.

Final aggregate source boundary before cutover:

- Current visible files: `80`
- Current visible bytes: `42,408,414`
- Trashbin files: `968`
- Trashbin bytes: `7,524,015,414`
- Version rows: `1,046`

## Final Copy

Final copy report directory:

```text
/tmp/nextcloud-prod-ldap-target-final-webdav-copy-20260502-013416
```

Final copy totals:

- Reports: `10`
- Planned files: `80`
- Planned bytes: `42,408,414`
- Copied files: `80`
- Copied bytes: `42,408,414`
- Raw target files failing encryption header validation: `0`

The copy path used WebDAV only and did not read or copy raw S3 object IDs.

## Backups And Restore Sets

Final source restore-set capture while the old S3-backed source was in
maintenance mode:

```text
/tmp/nextcloud-prod-backup-capture-20260502-015110
```

Target restore-set capture after cutover:

```text
/tmp/nextcloud-prod-target-backup-capture-20260502-020331
```

The target capture includes:

- `config.php`
- custom-format CNPG database dump verified with `pg_restore --list`
- Kubernetes resource snapshots
- selected Kubernetes Secret YAML
- checksum manifest

Encrypted target restore requires these items together:

- `nextcloud-migration-ldap-cnpg` database backup or dump
- target `config.php` and Nextcloud secret
- `nextcloud-migration-ldap-cnpg-app` database secret
- `nextcloud/nextcloud-data` encrypted user files and `files_encryption`
  material
- Synology snapshot or Hyper Backup copy of the NFS share

## Ongoing Backup Coverage

Added in commit `ae82a3b`:

- CNPG ScheduledBackup:
  `nextcloud/nextcloud-migration-ldap-cnpg-daily`
- CNPG destination:
  `s3://myrobertson-k8s-prod-volsync/cnpg/nextcloud-migration-ldap-cnpg`
- VolSync ReplicationSource:
  `nextcloud/nextcloud-migration-ldap-html-backup`
- VolSync repository:
  `volsync/nextcloud/nextcloud-migration-ldap-html`

Manual backup verification after applying the manifests:

- CNPG Backup:
  `nextcloud-migration-ldap-cnpg-manual-20260502020249`
  completed.
- VolSync manual trigger:
  `manual-20260502020249`
  produced `status.lastSyncTime=2026-05-02T09:03:02Z`.

After target backup validation, the old S3-backed source backup controllers
were paused in Git:

- `default/nextcloud-cnpg-daily` has `spec.suspend: true`.
- `default/nextcloud-data-pvc-ceph-backup` has `spec.paused: true`.

The old source app, database, app/config PVC, and S3 bucket remain retained for
rollback; only stale scheduled backups are stopped.

After the target was validated, the old S3-backed source app was scaled to zero
in Git. Old source-owned Collabora, Redis, metrics, and cron runtime components
were disabled. The old source CNPG database, app/config PVC, S3 bucket, secrets,
manifests, and restore captures remain retained. This reduces stale source
surface area without deleting rollback data.

## Post-Cutover App Parity

After cutover, the LDAP/NFS target was updated to install and enable the
user-facing apps that were enabled on the S3-backed source, including Calendar,
Contacts, Mail, Notes, Talk, Tables, Whiteboard, Draw.io, and Collabora
integration.

Collabora ownership moved to the target HelmRelease. The public
`office.myrobertson.com` route now points at
`nextcloud/nextcloud-migration-ldap-collabora`, and the retained old source no
longer needs to own the public Office backend.

Post-app-parity backup checkpoint:

- CNPG Backup:
  `nextcloud-migration-ldap-cnpg-manual-20260502093132`
  completed.
- VolSync app/config ReplicationSource:
  `nextcloud-migration-ldap-html-backup`
  last successful sync observed at `2026-05-02T09:26:23Z`.

## Post-Cutover Client Auth

After migration app-password cleanup, desktop and mobile sync clients may keep
retrying old credentials against WebDAV and can trigger Nextcloud brute-force
protection for the user's source IP. The server-side recovery is:

```bash
source ~/.bash_profile

kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- \
  php occ security:bruteforce:attempts <client-ip>
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- \
  php occ security:bruteforce:reset <client-ip>
```

For the cutover, `50.47.197.121/32` was temporarily added to the
`bruteForce` app allowlist so the browser login could recover while stale
clients were still retrying. Remove that allowlist entry after desktop and
mobile clients have been reconnected with fresh app passwords.

## Validation Commands

```bash
source ~/.bash_profile

curl -k -fsS https://cloud.myrobertson.com/status.php

kubectl --context admin@prod -n default get httproute nextcloud \
  -o jsonpath='{.spec.rules[0].backendRefs[0].name}{"\t"}{.spec.rules[0].backendRefs[0].namespace}{"\n"}'

kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ encryption:status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ ldap:test-config s01
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ app:list
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ config:list richdocuments --private
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ config:system:get objectstore || true
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- df -h /var/www/html/data
kubectl --context admin@prod -n nextcloud get scheduledbackup nextcloud-migration-ldap-cnpg-daily
kubectl --context admin@prod -n nextcloud get replicationsource nextcloud-migration-ldap-html-backup

kubectl --context admin@prod -n default get deploy nextcloud -o jsonpath='{.spec.replicas}{"\n"}'
kubectl --context admin@prod -n default get cluster nextcloud-cnpg
kubectl --context admin@prod -n default get pvc nextcloud-data-pvc-ceph-v2 nextcloud-cnpg-1 nextcloud-cnpg-1-wal
```

## Retention And Rollback Notes

- Keep the old source database, app/config PVC, and S3 bucket retained while
  rollback remains possible.
- The old source HelmRelease is intentionally scaled to zero after validation.
  If rollback is required, restore the old source replica count, re-enable old
  source Redis, metrics, cron, and Collabora as needed, wait for pods to become
  ready, point the `default/nextcloud` HTTPRoute back to service
  `default/nextcloud`, disable maintenance on the source, and investigate any
  writes that occurred on the target after cutover.
- Keep the source S3 bucket read-only or otherwise protected.
- Do not delete the source S3 bucket until the retention window has passed and
  restore testing from the new target backups has succeeded.
- Do not delete the old source database or app/config PVC until restore testing
  and rollback decisions are complete.
