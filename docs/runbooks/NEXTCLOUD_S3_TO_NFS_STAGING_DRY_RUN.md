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
- `encryption`: enabled with default module `OC_DEFAULT_MODULE`

## What Has Been Proven

- The Synology-backed staging PVC binds as `nextcloud/nextcloud-data`.
- The migration sandbox starts successfully against a filesystem-backed data directory.
- The sandbox can write to `/var/www/html/data` as `www-data`.
- A staging database dump can be restored into the sandbox database for compatibility testing.
- Restoring the database alone is not a migration. The file blobs still live in the source S3 bucket until a metadata-aware migration method moves them.
- The clean Strategy A sandbox has Nextcloud server-side encryption enabled. Raw files on the NFS mount should have a Nextcloud encryption header, while WebDAV reads return plaintext through Nextcloud.

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

## Validate Target Encryption

The clean target must use Nextcloud-managed server-side encryption before any
real import. This is separate from Synology Btrfs checksums and from NFS export
controls.

```bash
source ~/.bash_profile

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  php occ encryption:status

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  sh -lc 'find /var/www/html/data -maxdepth 4 -path "*/files_encryption*" -print | head -40'
```

Expected result:

- `enabled: true`
- `defaultModule: OC_DEFAULT_MODULE`
- encrypted key material exists under `files_encryption`

After a WebDAV smoke test, raw target files should not be plaintext:

```bash
source ~/.bash_profile

scripts/nextcloud-encryption-target-validation.sh
```

Manual equivalent:

```bash
source ~/.bash_profile

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  sh -lc 'file="$(find /var/www/html/data/migration-dryrun/files -type f -name README.txt | tail -1)"; head -c 96 "${file}" | grep "HBEGIN:oc_encryption_module:OC_DEFAULT_MODULE"'
```

If any target files were written before encryption was enabled, keep the target
offline and run:

```bash
php occ encryption:encrypt-all
```

Back up the database, `config.php`, Kubernetes secrets, and `files_encryption`
key material as one restore set. Encrypted files may be unrecoverable if the
matching key material or Nextcloud secret is lost.

## Choose The Actual File Migration Method

Use one of these approaches before any production cutover.

Recommended path:

1. Use `apps/staging/nextcloud-migration-clean` as the clean filesystem-backed Nextcloud instance.
2. Verify `php occ encryption:status` reports `enabled: true` and `defaultModule: OC_DEFAULT_MODULE`.
3. Recreate users and groups through a controlled process.
4. Copy user-visible files through Nextcloud WebDAV or another metadata-aware path.
5. Verify raw NFS files are encrypted and WebDAV reads return the original content.
6. Rebuild previews and search indexes after import.
7. Decide separately whether shares, calendars, contacts, versions, and trashbin need migration or can be recreated.

Database-aware path:

1. Select a version-compatible migration tool that understands Nextcloud objectstore mappings.
2. Test it against the cloned database and a protected copy or snapshot of the S3 bucket.
3. Verify file counts, paths, shares, versions, and trashbin behavior.
4. Do not run unaudited scripts against production data.

## Strategy A WebDAV Smoke Test

Use this only for staging validation. It creates a tiny test file in the source
staging Nextcloud admin account, copies that file through WebDAV into the clean
filesystem-backed sandbox, and verifies the checksum. It does not read from or
write raw S3 objects.

```bash
source ~/.bash_profile

source_user="$(kubectl --context admin@staging -n default get secret nextcloud-secret -o jsonpath='{.data.NEXTCLOUD_ADMIN_USER}' | base64 -d)"
source_pass="$(kubectl --context admin@staging -n default get secret nextcloud-secret -o jsonpath='{.data.NEXTCLOUD_ADMIN_PASSWORD}' | base64 -d)"
run_id="$(date +%Y%m%d-%H%M%S)"

kubectl --context admin@staging -n nextcloud exec -i deploy/nextcloud-migration-clean -c nextcloud -- sh -s <<SCRIPT
set -eu
SOURCE_USER='${source_user}'
SOURCE_PASS='${source_pass}'
RUN_ID='${run_id}'
TARGET_USER="\${NEXTCLOUD_ADMIN_USER}"
TARGET_PASS="\${NEXTCLOUD_ADMIN_PASSWORD}"
FOLDER='migration-dryrun-webdav'
FILE="metadata-aware-import-\${RUN_ID}.txt"
SOURCE_BASE="http://nextcloud.default.svc.cluster.local/remote.php/dav/files/\${SOURCE_USER}/\${FOLDER}"
TARGET_BASE="http://127.0.0.1/remote.php/dav/files/\${TARGET_USER}/\${FOLDER}"
PAYLOAD="Nextcloud metadata-aware WebDAV dry run \${RUN_ID}\\nsource=staging-s3-primary\\ntarget=clean-synology-nfs\\n"

curl -fsS -u "\${SOURCE_USER}:\${SOURCE_PASS}" -X MKCOL "\${SOURCE_BASE}" >/dev/null || true
printf '%b' "\${PAYLOAD}" | curl -fsS -u "\${SOURCE_USER}:\${SOURCE_PASS}" -T - "\${SOURCE_BASE}/\${FILE}" >/dev/null
curl -fsS -u "\${TARGET_USER}:\${TARGET_PASS}" -X MKCOL "\${TARGET_BASE}" >/dev/null || true
curl -fsS -u "\${SOURCE_USER}:\${SOURCE_PASS}" "\${SOURCE_BASE}/\${FILE}" | curl -fsS -u "\${TARGET_USER}:\${TARGET_PASS}" -T - "\${TARGET_BASE}/\${FILE}" >/dev/null
SOURCE_SHA="\$(curl -fsS -u "\${SOURCE_USER}:\${SOURCE_PASS}" "\${SOURCE_BASE}/\${FILE}" | sha256sum | awk '{print \$1}')"
TARGET_SHA="\$(curl -fsS -u "\${TARGET_USER}:\${TARGET_PASS}" "\${TARGET_BASE}/\${FILE}" | sha256sum | awk '{print \$1}')"

if [ "\${SOURCE_SHA}" != "\${TARGET_SHA}" ]; then
  echo checksum_mismatch >&2
  exit 1
fi

printf 'webdav_import_ok file=%s/%s sha256=%s\\n' "\${FOLDER}" "\${FILE}" "\${TARGET_SHA}"
SCRIPT

unset source_pass
```

Confirm the target file landed on the filesystem-backed NFS mount with a normal
user-visible path:

```bash
source ~/.bash_profile

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  find /var/www/html/data/admin/files/migration-dryrun-webdav -maxdepth 1 -type f -name 'metadata-aware-import-*.txt' -print

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  php occ files:scan admin --path='admin/files/migration-dryrun-webdav'

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  sh -lc 'df -h /var/www/html/data && mount | grep /var/www/html/data'
```

## Strategy A Non-Admin WebDAV Smoke Test

Use this to validate the same metadata-aware path with a normal database-backed
user without resetting or borrowing a real user's credentials. It creates or
updates a temporary `migration-dryrun` user in both staging instances, uploads a
small file to the S3-backed source through WebDAV, copies it to the clean
NFS-backed sandbox through WebDAV, and verifies the checksum.

The temporary user is a staging test fixture. Remove it later with
`php occ user:delete migration-dryrun` only after its test files are no longer
needed.

For the repeatable version that creates a small nested folder tree and verifies
multiple checksums, run:

```bash
scripts/nextcloud-webdav-migration-smoke-test.sh
```

```bash
source ~/.bash_profile
set -euo pipefail

user="migration-dryrun"
group="migration-dryrun"
pass="$(openssl rand -base64 36 | tr -d '\n')"

for ns_app in "default deploy/nextcloud" "nextcloud deploy/nextcloud-migration-clean"; do
  ns="${ns_app%% *}"
  deploy="${ns_app#* }"

  kubectl --context admin@staging -n "${ns}" exec "${deploy}" -c nextcloud -- \
    php occ group:add "${group}" >/dev/null 2>&1 || true

  if kubectl --context admin@staging -n "${ns}" exec "${deploy}" -c nextcloud -- \
    php occ user:info "${user}" >/dev/null 2>&1; then
    kubectl --context admin@staging -n "${ns}" exec "${deploy}" -c nextcloud -- \
      env OC_PASS="${pass}" php occ user:resetpassword --password-from-env "${user}" >/dev/null
  else
    kubectl --context admin@staging -n "${ns}" exec "${deploy}" -c nextcloud -- \
      env OC_PASS="${pass}" php occ user:add --password-from-env \
      --display-name "Migration Dry Run" \
      --group "${group}" \
      "${user}" >/dev/null
  fi

  kubectl --context admin@staging -n "${ns}" exec "${deploy}" -c nextcloud -- \
    php occ group:adduser "${group}" "${user}" >/dev/null 2>&1 || true
done

run_id="$(date +%Y%m%d-%H%M%S)"

kubectl --context admin@staging -n nextcloud exec -i deploy/nextcloud-migration-clean -c nextcloud -- sh -s <<SCRIPT
set -eu
USER_ID='${user}'
USER_PASS='${pass}'
RUN_ID='${run_id}'
FOLDER='migration-dryrun-user-webdav'
FILE="non-admin-import-\${RUN_ID}.txt"
SOURCE_BASE="http://nextcloud.default.svc.cluster.local/remote.php/dav/files/\${USER_ID}/\${FOLDER}"
TARGET_BASE="http://127.0.0.1/remote.php/dav/files/\${USER_ID}/\${FOLDER}"
PAYLOAD="Nextcloud non-admin WebDAV dry run \${RUN_ID}\\nsource=staging-s3-primary\\ntarget=clean-synology-nfs\\nuser=\${USER_ID}\\n"

curl -fsS -u "\${USER_ID}:\${USER_PASS}" -X MKCOL "\${SOURCE_BASE}" >/dev/null || true
printf '%b' "\${PAYLOAD}" | curl -fsS -u "\${USER_ID}:\${USER_PASS}" -T - "\${SOURCE_BASE}/\${FILE}" >/dev/null
curl -fsS -u "\${USER_ID}:\${USER_PASS}" -X MKCOL "\${TARGET_BASE}" >/dev/null || true
curl -fsS -u "\${USER_ID}:\${USER_PASS}" "\${SOURCE_BASE}/\${FILE}" | curl -fsS -u "\${USER_ID}:\${USER_PASS}" -T - "\${TARGET_BASE}/\${FILE}" >/dev/null
SOURCE_SHA="\$(curl -fsS -u "\${USER_ID}:\${USER_PASS}" "\${SOURCE_BASE}/\${FILE}" | sha256sum | awk '{print \$1}')"
TARGET_SHA="\$(curl -fsS -u "\${USER_ID}:\${USER_PASS}" "\${TARGET_BASE}/\${FILE}" | sha256sum | awk '{print \$1}')"

if [ "\${SOURCE_SHA}" != "\${TARGET_SHA}" ]; then
  echo checksum_mismatch >&2
  exit 1
fi

printf 'non_admin_webdav_import_ok user=%s file=%s/%s sha256=%s\\n' "\${USER_ID}" "\${FOLDER}" "\${FILE}" "\${TARGET_SHA}"
SCRIPT

unset pass
```

Confirm the target file landed on the clean sandbox's NFS data directory:

```bash
source ~/.bash_profile

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  find /var/www/html/data/migration-dryrun/files/migration-dryrun-user-webdav -maxdepth 1 -type f -name 'non-admin-import-*.txt' -print

kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  php occ files:scan migration-dryrun --path='migration-dryrun/files/migration-dryrun-user-webdav'
```

## Strategy A Share Recreation Smoke Test

File shares are Nextcloud metadata. A WebDAV file copy does not preserve shares
by itself, so shares must be recreated through a supported Nextcloud API or a
carefully tested migration process.

The staging share smoke test creates disposable owner and recipient users,
uploads files to the S3-backed source, creates source user and group shares
through the OCS Share API, copies the files through WebDAV into the clean
NFS-backed sandbox, recreates the shares through the target OCS Share API, and
verifies that the recipient can read the shared files with matching checksums.

```bash
scripts/nextcloud-share-migration-smoke-test.sh
```

The script accepts the same environment overrides as the WebDAV smoke test:
`KUBE_CONTEXT`, `SOURCE_NAMESPACE`, `SOURCE_DEPLOYMENT`, `TARGET_NAMESPACE`,
`TARGET_DEPLOYMENT`, `SOURCE_SERVICE_URL`, and `TARGET_SERVICE_URL`.

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
