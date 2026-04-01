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

## Bucket structure

- CNPG backups: s3://myrobertson-homelab-terraform/cnpg/<cluster-name>
- VolSync backups: s3://myrobertson-homelab-terraform/volsync/default/<pvc-name>

For VolSync restic secrets, set RESTIC_REPOSITORY with the S3 endpoint and path-style URL format, for example:

- s3:s3.us-west-2.amazonaws.com/myrobertson-homelab-terraform/volsync/default/immich-data-files-pvc-ceph

## Parent/Siblings

- Parent: [Prod](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md).
