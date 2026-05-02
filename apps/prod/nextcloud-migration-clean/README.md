# Nextcloud Production Clean Migration Target

This app is the isolated production Strategy A target for migrating from
primary S3 object storage to filesystem-backed storage on Synology NFS.

- Namespace: `nextcloud`
- Release: `nextcloud-migration-clean`
- Database: `nextcloud-migration-clean-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-clean-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data`, mounted at subpath `strategy-a-prod-data`
- Server-side encryption: enabled with Nextcloud's `OC_DEFAULT_MODULE`
- App secret: rendered from Vault path `secret/nextcloud/prod/app`
- Public route: none

Safety boundaries:

- Do not attach this instance to the source S3 primary objectstore.
- Do not expose this instance publicly before cutover.
- Do not copy raw `urn:oid:*` bucket objects into this data directory.
- Keep the live production Nextcloud in `default/nextcloud` unchanged until an
  explicit cutover step.

Validation:

```bash
source ~/.bash_profile
kubectl --context admin@prod -n nextcloud get pvc,cluster,hr,pod -o wide
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ encryption:status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- php occ config:system:get objectstore || true
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- df -h /var/www/html /var/www/html/data
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-clean -c nextcloud -- mount | grep /var/www/html/data
```
