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
