# Vault Seed Template (Prod Backups)

This template documents the Vault KV paths and keys required by the production CNPG and VolSync backup configuration.

## Assumptions

- Vault KV mount: secret
- Bucket: homelab-prod-backups

## Region variable

Set this once and reuse it in all commands:

```bash
AWS_REGION='us-west-2'
AWS_S3_ENDPOINT="s3.${AWS_REGION}.amazonaws.com"
BACKUP_BUCKET='homelab-prod-backups'
```

## CNPG shared credentials

Path:

- secret/cnpg/prod/backup-s3

Required keys:

- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

Example:

```bash
vault kv put secret/cnpg/prod/backup-s3 \
  AWS_ACCESS_KEY_ID='<set-me>' \
  AWS_SECRET_ACCESS_KEY='<set-me>'
```

## VolSync per-PVC restic secrets

Each path below must contain:

- RESTIC_REPOSITORY
- RESTIC_PASSWORD
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY

RESTIC_REPOSITORY format:

- s3:s3.${AWS_REGION}.amazonaws.com/${BACKUP_BUCKET}/volsync/default/<pvc-name>

### Paths to create

- secret/volsync/prod/authelia-config-ceph
- secret/volsync/prod/cluster-authelia-ceph-1
- secret/volsync/prod/bitwarden-data-ceph
- secret/volsync/prod/immich-data-files-pvc-ceph
- secret/volsync/prod/cluster-immich-ceph-1
- secret/volsync/prod/lidarr-config-ceph
- secret/volsync/prod/lidarr-data-files-pvc
- secret/volsync/prod/mealie-data-ceph
- secret/volsync/prod/mealie-cnpg-main-1
- secret/volsync/prod/mealie-cnpg-main-1-wal
- secret/volsync/prod/overseerr-config-ceph
- secret/volsync/prod/overseerr-data-files-pvc
- secret/volsync/prod/prowlarr-config-ceph
- secret/volsync/prod/prowlarr-data-files-pvc
- secret/volsync/prod/radarr-config-ceph
- secret/volsync/prod/radarr-data-files-pvc
- secret/volsync/prod/sonarr-config-ceph
- secret/volsync/prod/sonarr-data-files-pvc
- secret/volsync/prod/syncthing-config-ceph

### Example seed command

```bash
PVC_NAME='immich-data-files-pvc-ceph'
AWS_REGION='us-west-2'
AWS_S3_ENDPOINT="s3.${AWS_REGION}.amazonaws.com"
BACKUP_BUCKET='homelab-prod-backups'

vault kv put "secret/volsync/prod/${PVC_NAME}" \
  RESTIC_REPOSITORY="s3:${AWS_S3_ENDPOINT}/${BACKUP_BUCKET}/volsync/default/${PVC_NAME}" \
  RESTIC_PASSWORD='<set-me-unique-per-repo>' \
  AWS_ACCESS_KEY_ID='<set-me>' \
  AWS_SECRET_ACCESS_KEY='<set-me>'
```
