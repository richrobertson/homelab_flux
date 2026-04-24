# Vault Seed Template (Prod Backups on Backblaze B2)

This template documents the shared Vault KV path and keys required by the production CNPG and VolSync backup configuration after the Backblaze B2 migration.

## Assumptions

- Vault KV mount: `secret`
- Shared Backblaze path: `secret/backblaze/k8s/prod/volsync`
- Bucket: `myrobertson-k8s-prod-volsync`
- Endpoint: `s3.us-west-002.backblazeb2.com`
- Region: `us-west-002`

## CNPG shared credentials

Kubernetes secret:

- `cnpg-backup-s3`

Source Vault path:

- `secret/backblaze/k8s/prod/volsync`

The `cnpg-backup-s3` secret is rendered from the shared Backblaze application key path via the `cnpg-backblaze-b2` transformation and exposes only:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Shared Backblaze secret

Path:

- `secret/backblaze/k8s/prod/volsync`

At minimum this shared path should contain:

- `RESTIC_PASSWORD`
- Either AWS-style S3 credentials:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- Or Backblaze-style application key fields:
  - `applicationKeyId`
  - `applicationKey`

Optional overrides supported by the shared transformation:

- `AWS_REGION` or `AWS_DEFAULT_REGION`
- `S3_ENDPOINT`, `AWS_ENDPOINT`, or `B2_ENDPOINT`
- `S3_BUCKET`, `B2_BUCKET`, or `BUCKET_NAME`

The shared transformations render:

- CNPG secret `cnpg-backup-s3` with:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- Per-repository VolSync Kubernetes secrets with:
  - `RESTIC_REPOSITORY`
  - `RESTIC_PASSWORD`
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
  - `AWS_DEFAULT_REGION`

Rendered repository format:

- `s3:https://${S3_ENDPOINT}/${S3_BUCKET}/volsync/default/<repository-name>`

## Example seed command

Using Backblaze application key field names:

```bash
vault kv put secret/backblaze/k8s/prod/volsync \
  applicationKeyId='<set-me>' \
  applicationKey='<set-me>' \
  RESTIC_PASSWORD='<long-random-restic-password>' \
  AWS_REGION='us-west-002' \
  AWS_DEFAULT_REGION='us-west-002' \
  S3_ENDPOINT='s3.us-west-002.backblazeb2.com' \
  S3_BUCKET='myrobertson-k8s-prod-volsync'
```

Using AWS-style field names:

```bash
vault kv put secret/backblaze/k8s/prod/volsync \
  AWS_ACCESS_KEY_ID='<set-me>' \
  AWS_SECRET_ACCESS_KEY='<set-me>' \
  RESTIC_PASSWORD='<long-random-restic-password>' \
  AWS_REGION='us-west-002' \
  AWS_DEFAULT_REGION='us-west-002' \
  S3_ENDPOINT='s3.us-west-002.backblazeb2.com' \
  S3_BUCKET='myrobertson-k8s-prod-volsync'
```

## Encryption

- Restic uses `RESTIC_PASSWORD` to encrypt repository contents client-side before upload.
