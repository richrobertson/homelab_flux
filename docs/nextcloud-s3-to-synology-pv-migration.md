# Nextcloud S3 Primary Storage to Synology NFS PV Migration

This is a controlled migration from Nextcloud primary AWS S3 object storage to filesystem-backed storage on a Kubernetes PVC backed by a Synology NFS shared folder.

Nextcloud primary object storage does not store the user-visible folder tree directly in the bucket. Bucket objects are blobs addressed by internal object IDs, while users, file IDs, paths, metadata, shares, versions, trashbin state, and storage mappings live in the Nextcloud database. A raw `aws s3 sync` from the bucket into the new data directory is not a valid migration.

## Non-Goals In This PR

- No production cutover is performed.
- No S3 objectstore configuration is removed from production.
- No S3 bucket deletion or destructive cleanup is introduced.
- No production Nextcloud data is mounted through hostPath.
- Database, Redis, app config, preview/cache when separately configurable, and search services remain on SSD-backed storage.
- Target user files on Synology NFS must be encrypted at rest by Nextcloud server-side encryption using `OC_DEFAULT_MODULE`.

## Phase 0: Inventory

Record the current state before making changes:

- Run `scripts/nextcloud-migration-inventory.sh` in `homelab_flux` for a
  non-secret source and encrypted target inventory. Use
  `PRINT_IDENTIFIERS=true` only when intentionally producing a controlled
  migration mapping file.
- Current Nextcloud version: `php occ status`
- Current objectstore configuration from `config.php`, Helm values, and Kubernetes secrets.
- S3 bucket name, endpoint, region, and IAM role or credential source.
- Database backend and version.
- Number of users.
- Approximate user storage used and bucket object count.
- Apps that affect files:
  - `files_versions`
  - `files_trashbin`
  - server-side encryption state and default module
  - full text search
  - external storage
  - Memories, Photos, or Preview Generator, if installed

## Phase 1: Backups Before Touching Anything

1. Put Nextcloud in maintenance mode:

   ```bash
   php occ maintenance:mode --on
   ```

2. Take a full database dump.
3. Back up `config.php` and Kubernetes secrets using the existing SOPS, VaultStaticSecret, SealedSecrets, or ExternalSecrets convention.
4. Back up the AWS S3 bucket or create a provider-side protected copy/versioned bucket.
5. Back up appdata.
6. Export the current Helm values and rendered manifests.
7. Verify backups are restorable.
8. Leave the original S3 bucket untouched until migration validation and retention windows are complete.

For a production backup capture rehearsal before the final maintenance window:

```bash
source ~/.bash_profile

scripts/nextcloud-prod-backup-capture.sh
```

The capture writes a sensitive local restore-set directory under
`/tmp/nextcloud-prod-backup-capture-*` containing `config.php`, a CNPG
custom-format database dump, selected Kubernetes resource snapshots, selected
Secret YAML, S3 inventory/versioning metadata, `pg_restore --list` verification
output, and `SHA256SUMS`. Do not commit or casually move this directory. Run it
again during maintenance mode for the final cutover backup.

## Phase 2: Provision Target Storage In Parallel

1. Apply the Ansible NFS client prep role to Kubernetes worker nodes.
2. Provision the Synology shared folders with the Ansible playbook in `homelab_ansible/ansible/synology/provision_nextcloud_nfs_share.yml`:
   - Staging shared folder: `nextcloud-data-stage`.
   - Production shared folder: `nextcloud-data-prod`.
   - Btrfs data checksums enabled.
   - Recycle bin disabled.
   - NFS enabled.
   - NFS export restricted to the matching Kubernetes worker node IPs.
   - SMB disabled for this share or no normal-user permissions granted.
   - Guest disabled.
   - Snapshots enabled.
   - Hyper Backup to Backblaze B2 configured.
3. Apply the Flux storage manifests for `nextcloud-storage-target`.
4. Confirm the PV/PVC bind.
5. Confirm a temporary debug pod can write to the PVC.
6. Do not point production Nextcloud at the new PVC yet.

For production readiness, run:

```bash
source ~/.bash_profile

scripts/nextcloud-prod-preflight.sh
```

The preflight checks Flux readiness, production Nextcloud health, S3
objectstore presence, CNPG backup objects, the Synology NFS PV/PVC path and
binding, and a temporary write marker on the target PVC using the `www-data`
UID/GID expected by the Nextcloud container. It does not change the production
Nextcloud deployment, remove S3 config, copy user files, or read raw S3
objects.

## Phase 3: Choose Migration Strategy

### Strategy A: New Clean Instance And Metadata-Aware Copy (Recommended)

Stand up a temporary or parallel Nextcloud instance using filesystem-backed storage on the new PVC. Mount or expose old data through the old Nextcloud API/WebDAV or another controlled export path, then copy user-visible files through Nextcloud/WebDAV or another metadata-aware process so files land in the new filesystem storage with normal names.

Before importing real data, enable Nextcloud server-side encryption on the clean target, set `OC_DEFAULT_MODULE` as the default module, and verify a newly imported file is encrypted on the raw NFS mount while remaining readable through WebDAV. Back up `config.php`, the Nextcloud database, and the `files_encryption` key material together; losing any required key material can make encrypted files unrecoverable.

Recreate users, groups, shares, calendars, contacts, and app settings as needed, or migrate database state only where there is a tested supported path. This is slower, but safer because it does not depend on interpreting raw S3 object IDs.

Before implementing the final Strategy A copy workflow, generate a dry-run plan
with `scripts/nextcloud-strategy-a-plan.sh`. The plan is read-only and
summarizes missing users/groups, group membership gaps, user/group share
recreation candidates, special shares that need manual review, and the
versions/trashbin boundary. Treat the generated JSON artifact as operational
data because it contains user, group, and share identifiers.

Use `scripts/nextcloud-webdav-copy-root.sh` for reviewed one-folder rehearsals.
It requires an explicit `COPY_ROOT`, defaults to `APPLY=false`, uses WebDAV
only, verifies source/target checksums when copying, and verifies the copied
raw target files carry the Nextcloud encryption header.

Use `scripts/nextcloud-user-group-reconcile.sh` to prepare the clean target
identity set before copying files. It defaults to dry-run, creates users/groups
only on the target when `APPLY=true`, and writes temporary target WebDAV
passwords to a sensitive local TSV under `/tmp`. Do not commit that password
file.

### Strategy B: In-Place Database-Aware Migration

Use this only if a tested, version-compatible migration tool or script is selected. The tool must understand Nextcloud filecache and storage mappings and convert object IDs into filesystem paths. It must be tested against a cloned database and copied bucket first, and it must preserve versions, trashbin, and shares if those are required.

Do not use unaudited scripts against production data.

### Explicit Warnings

- Do not `aws s3 sync` the bucket directly into the new data directory as the migration.
- Do not simply remove objectstore config and point `datadirectory` at the PV.
- Do not allow users or sync clients to write during migration.
- Do not let users access the Synology share directly over SMB or NFS.
- Do not delete the S3 bucket after cutover until restore validation and retention windows are complete.

## Phase 4: Dry Run

1. Clone the production database into a test namespace/database.
2. Copy or snapshot a representative subset of the S3 bucket.
3. Deploy a temporary Nextcloud test instance. The staging sandbox in
   `apps/staging/nextcloud-migration` is the current private target for this:
   it has no public route, uses `ceph-block` for its database, uses
   `csi-cephfs-sc` for app/config storage, and mounts the Synology-backed
   `nextcloud-data` PVC only at the Nextcloud data path.
   The staging execution runbook is
   `docs/runbooks/NEXTCLOUD_S3_TO_NFS_STAGING_DRY_RUN.md`.
4. Run the selected migration method.
5. Validate:
   - Users can log in.
   - Folder trees are correct.
   - File counts match.
   - `php occ encryption:status` reports `enabled: true` and `defaultModule: OC_DEFAULT_MODULE` on the target.
   - Newly imported files are encrypted on the raw NFS mount and readable through Nextcloud/WebDAV.
   - Shares still work if expected.
   - Versions and trashbin expectations are understood.
   - Previews regenerate.
   - Full-text search can be rebuilt.
   - Mobile and desktop sync clients behave correctly.

## Phase 5: Production Cutover

1. Announce downtime.
2. Stop sync clients if possible.
3. Put production Nextcloud in maintenance mode:

   ```bash
   php occ maintenance:mode --on
   ```

4. Take the final database dump.
5. Take the final config and secrets backup.
6. Make the final S3 bucket backup or snapshot.
7. Run the final migration.
8. Update Nextcloud config to remove AWS S3 primary objectstore settings and use the filesystem data directory on the mounted PVC.
9. Ensure Nextcloud server-side encryption is enabled on the target before reopening access:

   ```bash
   php occ app:enable encryption
   php occ encryption:enable
   php occ encryption:set-default-module OC_DEFAULT_MODULE
   php occ encryption:status
   ```

   If any files were written to the target before encryption was enabled, keep maintenance mode on and run:

   ```bash
   php occ encryption:encrypt-all
   ```

10. Ensure ownership and permissions are correct for the Nextcloud container user.
11. Run required `occ` commands:

    ```bash
    php occ maintenance:repair
    php occ files:scan --all
    php occ files:cleanup
    php occ preview:pre-generate
    ```

    Run `preview:pre-generate` only if Preview Generator is installed; otherwise document the equivalent preview regeneration approach.

12. Turn maintenance mode off:

    ```bash
    php occ maintenance:mode --off
    ```

13. Validate application behavior before reopening normal access.

## Phase 6: Post-Cutover

- Keep the AWS S3 bucket read-only or retained for rollback.
- Do not delete it immediately.
- Monitor Nextcloud logs.
- Monitor Kubernetes events.
- Monitor Synology NFS performance.
- Monitor database slow queries.
- Rebuild the full-text search index if needed.
- Confirm Hyper Backup to Backblaze B2 is running.
- Test restore from a Synology snapshot.
- Test restore from Backblaze backup.
- Test restore of encrypted files with the matching database, `config.php`, secrets, and `files_encryption` key material.
- Document rollback steps, including how to restore the pre-cutover database, config, secrets, S3 bucket state, encryption keys, and Helm values.

## Security Controls

### Synology

- Restrict the NFS export to Kubernetes node IPs or the storage VLAN.
- Disable SMB for this share or grant no normal-user SMB permissions.
- Disable guest access.
- Hide the share from network browsing if SMB is enabled elsewhere.
- Use dedicated admin or service accounts.
- Enable snapshots.
- Enable snapshot replication if a second Synology is available.
- Configure Hyper Backup to Backblaze B2.
- Do not make Backblaze credentials available to the Nextcloud pod.

### Kubernetes

- Keep the target PVC scoped to the Nextcloud namespace or the eventual workload namespace.
- Mount the PVC only into Nextcloud and controlled validation pods.
- Avoid privileged pods in the Nextcloud namespace.
- Use NetworkPolicy if the cluster supports it.
- Commit no secrets to Git.
- Use the existing VaultStaticSecret, SOPS, SealedSecrets, or ExternalSecrets convention.

## Cutover Overlay Notes

The staged target PVC is currently `nextcloud/nextcloud-data`. The current Nextcloud app renders into the `default` namespace. Kubernetes cannot mount a PVC across namespaces, so the cutover PR must either move the workload into the `nextcloud` namespace or create an equivalent same-namespace PVC binding for the workload namespace.

The disabled review patch is stored at:

```text
apps/base/nextcloud/migration-overlays/synology-filesystem-data-pvc.patch.yaml
```
