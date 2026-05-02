# Nextcloud S3 to NFS Staging Dry Run

Last updated: 2026-05-01

This runbook captures the staging dry-run path for moving Nextcloud from primary S3 object storage to filesystem-backed storage on the Synology NFS PVC.

The staging sandbox is for validation only. It must not be treated as a production cutover path until a migration method has been selected, tested, and documented.

## Current Staging Layout

Source instance:

- Namespace: `default`
- App: `nextcloud`
- Current storage: primary S3 object storage
- Database: CNPG cluster `nextcloud-cnpg`

Migration sandbox:

- Namespace: `nextcloud`
- HelmRelease: `nextcloud-migration`
- Database: CNPG cluster `nextcloud-migration-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data` on Synology NFS
- Public route: none

Clean Strategy A sandbox:

- Namespace: `nextcloud`
- HelmRelease: `nextcloud-migration-clean`
- Database: CNPG cluster `nextcloud-migration-clean-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-clean-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data` on Synology NFS subpath `strategy-a-clean-data`
- Public route: none

Expected sandbox mounts:

- `/var/www/html`: CephFS app/config storage
- `/var/www/html/data`: Synology NFS user data storage
- `objectstore`: empty

## What Has Been Proven

- The Synology-backed staging PVC binds as `nextcloud/nextcloud-data`.
- The migration sandbox starts successfully against a filesystem-backed data directory.
- The sandbox can write to `/var/www/html/data` as `www-data`.
- A staging database dump can be restored into the sandbox database for compatibility testing.
- Restoring the database alone is not a migration. The file blobs still live in the source S3 bucket until a metadata-aware migration method moves them.

## Important Safety Boundary

Do not copy S3 objects directly into `/var/www/html/data`.

The source bucket stores blobs by internal object IDs such as `urn:oid:*`. The user-visible namespace, shares, versions, trashbin state, file IDs, and metadata are in the Nextcloud database. A raw bucket copy would put the wrong names and paths into the filesystem-backed data directory.

## Access The Sandbox

Start a local-only port-forward:

```bash
source ~/.bash_profile
kubectl --context admin@staging -n nextcloud port-forward svc/nextcloud-migration 8088:80
```

Open:

```text
http://127.0.0.1:8088/login
```

If the sandbox database was restored from the source staging database, login state and users follow that database. The bootstrap admin password from `nextcloud-migration-secret` only applies to a clean install before a database restore.

## Capture Source Inventory

Use commands that show structure without printing secret values.

```bash
source ~/.bash_profile

kubectl --context admin@staging -n default exec deploy/nextcloud -c nextcloud -- php occ status
kubectl --context admin@staging -n default exec deploy/nextcloud -c nextcloud -- php occ app:list | grep -E 'files_versions|files_trashbin|photos|preview|memories|richdocuments|user_ldap|user_oidc|fulltext|encryption'
kubectl --context admin@staging -n default get cluster nextcloud-cnpg -o yaml > /tmp/nextcloud-cnpg-cluster.yaml
kubectl --context admin@staging -n default get helmrelease nextcloud -o yaml > /tmp/nextcloud-helmrelease.yaml
kubectl --context admin@staging -n default get configmap nextcloud-s3-staging -o yaml > /tmp/nextcloud-s3-configmap.yaml
kubectl --context admin@staging -n default get secret nextcloud-s3-staging -o json | jq '.data | keys'
```

For bucket inventory, use backup or inventory commands only:

```bash
aws s3 ls s3://<nextcloud-staging-bucket> --recursive --summarize
aws s3api list-objects-v2 --bucket <nextcloud-staging-bucket> --query '{object_count: KeyCount}'
```

Do not use the AWS inventory output as a filesystem import list unless the selected migration tool understands the Nextcloud database mappings.

## Take A Staging Database Dump

This keeps credentials out of Git and avoids hardcoding them in shell history.

```bash
source ~/.bash_profile
snapshot_dir="/tmp/nextcloud-staging-migration-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${snapshot_dir}"

pg_user="$(kubectl --context admin@staging -n default get secret nextcloud-cnpg-app -o jsonpath='{.data.user}' | base64 -d)"
pg_database="$(kubectl --context admin@staging -n default get secret nextcloud-cnpg-app -o jsonpath='{.data.dbname}' | base64 -d)"
pg_password="$(kubectl --context admin@staging -n default get secret nextcloud-cnpg-app -o jsonpath='{.data.password}' | base64 -d)"

kubectl --context admin@staging -n default exec nextcloud-cnpg-1 -- \
  env PGPASSWORD="${pg_password}" pg_dump \
  -h 127.0.0.1 \
  -U "${pg_user}" \
  -d "${pg_database}" \
  --format=custom \
  --file=/tmp/nextcloud-db.dump

kubectl --context admin@staging -n default cp \
  nextcloud-cnpg-1:/tmp/nextcloud-db.dump \
  "${snapshot_dir}/nextcloud-db.dump"

unset pg_password
```

## Restore The Dump Into The Sandbox

Scale the sandbox app down so no process writes while the database is replaced.

```bash
source ~/.bash_profile
snapshot_dir="<path-from-previous-step>"

kubectl --context admin@staging -n nextcloud scale deploy/nextcloud-migration --replicas=0
kubectl --context admin@staging -n nextcloud rollout status deploy/nextcloud-migration --timeout=300s

pg_user="$(kubectl --context admin@staging -n nextcloud get secret nextcloud-migration-cnpg-app -o jsonpath='{.data.user}' | base64 -d)"
pg_database="$(kubectl --context admin@staging -n nextcloud get secret nextcloud-migration-cnpg-app -o jsonpath='{.data.dbname}' | base64 -d)"
pg_password="$(kubectl --context admin@staging -n nextcloud get secret nextcloud-migration-cnpg-app -o jsonpath='{.data.password}' | base64 -d)"

kubectl --context admin@staging -n nextcloud exec -i nextcloud-migration-cnpg-1 -- \
  env PGPASSWORD="${pg_password}" pg_restore \
  -h 127.0.0.1 \
  -U "${pg_user}" \
  -d "${pg_database}" \
  --clean \
  --if-exists \
  --no-owner \
  < "${snapshot_dir}/nextcloud-db.dump"

unset pg_password

kubectl --context admin@staging -n nextcloud scale deploy/nextcloud-migration --replicas=1
kubectl --context admin@staging -n nextcloud rollout status deploy/nextcloud-migration --timeout=600s
```

## Validate Sandbox Storage Placement

```bash
source ~/.bash_profile

kubectl --context admin@staging -n nextcloud get pvc,cluster,hr,pod -o wide
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- php occ status
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- php occ config:system:get objectstore || true
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- df -h /var/www/html /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- mount | grep /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- \
  sh -lc 'su -s /bin/sh www-data -c "touch /var/www/html/data/.nfs-write-test && rm -f /var/www/html/data/.nfs-write-test"'
```

Expected result:

- `objectstore` prints no value.
- `/var/www/html/data` is an NFS mount from the staging Synology share.
- The write test succeeds.

## Choose The Actual File Migration Method

Use one of these approaches before any production cutover.

Recommended path:

1. Use `apps/staging/nextcloud-migration-clean` as the clean filesystem-backed Nextcloud instance.
2. Recreate users and groups through a controlled process.
3. Copy user-visible files through Nextcloud WebDAV or another metadata-aware path.
4. Rebuild previews and search indexes after import.
5. Decide separately whether shares, calendars, contacts, versions, and trashbin need migration or can be recreated.

Database-aware path:

1. Select a version-compatible migration tool that understands Nextcloud objectstore mappings.
2. Test it against the cloned database and a protected copy or snapshot of the S3 bucket.
3. Verify file counts, paths, shares, versions, and trashbin behavior.
4. Do not run unaudited scripts against production data.

## Dry-Run Validation Checklist

- Users can log in to the sandbox.
- Representative folder trees are visible.
- Representative files open and checksums match.
- File counts match expected source counts for migrated users.
- Shares work if they are in scope.
- Versions and trashbin behavior is understood.
- Previews regenerate.
- Full-text search can be rebuilt if enabled.
- Desktop and mobile sync clients can connect to the sandbox target without writing to production.

## Cleanup

Stop any local port-forward:

```bash
pkill -f 'kubectl.*port-forward.*svc/nextcloud-migration 8088:80' || true
```

Delete local dumps only after they are no longer needed:

```bash
rm -rf /tmp/nextcloud-staging-migration-<timestamp>
```

Do not delete the source S3 bucket, source database, source secrets, or source Helm values as part of this dry run.
