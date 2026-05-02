# Nextcloud Clean Migration Sandbox

This staging-only app is the clean Strategy A target for S3-primary to
filesystem-backed migration testing.

Use this instance for metadata-aware import experiments such as WebDAV/API
copying from the current staging Nextcloud instance into a fresh
filesystem-backed Nextcloud install.

- Namespace: `nextcloud`
- Release: `nextcloud-migration-clean`
- Database: `nextcloud-migration-clean-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-clean-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data`, mounted at subpath `strategy-a-clean-data`
- Server-side encryption: enabled with Nextcloud's `OC_DEFAULT_MODULE`
- App secret: `nextcloud-migration-secret`, manually mirrored from Vault path
  `secret/nextcloud/staging/migration/app`

There is intentionally no public HTTPRoute. Access it with a local-only
port-forward:

```bash
source ~/.bash_profile
kubectl --context admin@staging -n nextcloud port-forward svc/nextcloud-migration-clean 8089:80
```

Open `http://127.0.0.1:8089/login`.

## Safety Notes

- Do not attach this instance to the source S3 primary objectstore.
- Keep Nextcloud server-side encryption enabled before importing any real data.
- Do not restore the source database here; keep this instance clean for
  Strategy A testing.
- Do not copy raw `urn:oid:*` bucket objects into this data directory.
- Use Nextcloud-aware import methods so files land in the filesystem-backed
  data directory with normal user-visible names and metadata.

## Validation

```bash
source ~/.bash_profile
kubectl --context admin@staging -n nextcloud get pvc,cluster,hr,pod -o wide
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ status
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ encryption:status
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ config:system:get objectstore || true
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- df -h /var/www/html /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- mount | grep /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- \
  sh -lc 'su -s /bin/sh www-data -c "touch /var/www/html/data/.nfs-write-test && rm -f /var/www/html/data/.nfs-write-test"'
```

Expected storage placement:

- `/var/www/html`: `nextcloud-migration-clean-html` on `csi-cephfs-sc`.
- `/var/www/html/data`: `nextcloud-data` on Synology NFS subpath
  `strategy-a-clean-data`.
- Database PVCs: `ceph-block`.
- Redis: ephemeral.

`php occ config:system:get objectstore` should return no value.
`php occ encryption:status` should report `enabled: true` and
`defaultModule: OC_DEFAULT_MODULE`.

## WebDAV Smoke Test

The staging dry-run runbook includes tiny admin and non-admin WebDAV copy tests
from the current S3-backed staging Nextcloud instance into this clean
filesystem-backed sandbox:

```text
docs/runbooks/NEXTCLOUD_S3_TO_NFS_STAGING_DRY_RUN.md
```

The smoke test is intentionally metadata-aware: it uses Nextcloud WebDAV on both
ends and never copies raw `urn:oid:*` bucket objects into the data directory.
