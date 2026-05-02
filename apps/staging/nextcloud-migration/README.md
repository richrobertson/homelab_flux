# Nextcloud Migration Sandbox

This staging-only app stands up a temporary Nextcloud instance for migration
dry runs from S3 primary object storage to filesystem storage.

- Namespace: `nextcloud`
- Release: `nextcloud-migration`
- Database: `nextcloud-migration-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data`, backed by
  `scooter.myrobertson.net:/volume1/nextcloud-data-stage`
- App secret: `nextcloud-migration-secret`, manually mirrored from Vault path
  `secret/nextcloud/staging/migration/app` into the `nextcloud` namespace

There is intentionally no public HTTPRoute. Access it with a port-forward or
temporary debug workflow during migration testing.

Do not connect this sandbox to the production S3 bucket or production database.

## Access

Start a local-only port-forward:

```bash
source ~/.bash_profile
kubectl --context admin@staging -n nextcloud port-forward svc/nextcloud-migration 8088:80
```

Open `http://127.0.0.1:8088/login`.

To mirror the app secret from Vault without printing values:

```bash
source ~/.bash_profile
tmp="$(mktemp)"
vault kv get -format=json secret/nextcloud/staging/migration/app > "${tmp}"
kubectl --context admin@staging -n nextcloud create secret generic nextcloud-migration-secret \
  --from-literal=NEXTCLOUD_ADMIN_USER="$(jq -r '.data.data.NEXTCLOUD_ADMIN_USER' "${tmp}")" \
  --from-literal=NEXTCLOUD_ADMIN_PASSWORD="$(jq -r '.data.data.NEXTCLOUD_ADMIN_PASSWORD' "${tmp}")" \
  --from-literal=SMTP_USERNAME="$(jq -r '.data.data.SMTP_USERNAME' "${tmp}")" \
  --from-literal=SMTP_PASSWORD="$(jq -r '.data.data.SMTP_PASSWORD' "${tmp}")" \
  --dry-run=client -o yaml | kubectl --context admin@staging apply -f -
rm -f "${tmp}"
```

## Validation

```bash
source ~/.bash_profile
kubectl --context admin@staging -n nextcloud get pvc,cluster,hr,pod -o wide
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- php occ status
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- php occ config:system:get objectstore
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- df -h /var/www/html /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- mount | grep /var/www/html/data
kubectl --context admin@staging -n nextcloud exec deploy/nextcloud-migration -c nextcloud -- \
  sh -lc 'su -s /bin/sh www-data -c "touch /var/www/html/data/.nfs-write-test && rm -f /var/www/html/data/.nfs-write-test"'
```

Expected storage placement:

- `/var/www/html`: `nextcloud-migration-html` on `csi-cephfs-sc`.
- `/var/www/html/data`: `nextcloud-data` on Synology NFS.
- Database PVCs: `ceph-block`.
- Redis: ephemeral.

`php occ config:system:get objectstore` should return no value. A populated
`objectstore` value means the sandbox is no longer testing filesystem-backed
storage.
