# n8n Base

`apps/base/n8n/` defines the shared n8n application resources used by the staging and production overlays.

## Purpose

- Deploy n8n from the official OCI Helm chart.
- Use external CloudNativePG PostgreSQL and Redis operator Redis for queue mode.
- Keep secure values in Vault instead of in Git.

## Components

- `repository.yaml`: Flux `OCIRepository` for the official n8n chart.
- `release.yaml`: shared `HelmRelease` defaults for queue mode.
- `postgres.yaml`: CNPG `Cluster` for the n8n application database.
- `redis.yaml`: Redis operator `Redis` resource for queue storage.
- `secret.yaml`: Vault-backed core n8n secret reference.

## Required Vault data

Vault mount assumptions in this repo:

- mount: `secret`

### App secrets

The overlays patch the Vault path per environment:

- staging: `secret/n8n/staging/app`
- prod: `secret/n8n/prod/app`

Required keys:

- `N8N_ENCRYPTION_KEY`
- `N8N_HOST`
- `N8N_PORT`
- `N8N_PROTOCOL`

Recommended values:

- staging host: `n8n.staging.myrobertson.net`
- prod host: `n8n.myrobertson.com`
- port: `5678`
- protocol: `https`

Example:

```bash
vault kv put secret/n8n/prod/app \
  N8N_ENCRYPTION_KEY='<long-random-value>' \
  N8N_HOST='n8n.myrobertson.com' \
  N8N_PORT='5678' \
  N8N_PROTOCOL='https'
```

### Production VolSync secrets

The production overlay expects these Vault paths:

- `secret/volsync/prod/n8n-cnpg-1`

Required keys for each path:

- `RESTIC_REPOSITORY`
- `RESTIC_PASSWORD`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Rollout sequence

1. Commit and push the repo changes. Flux currently reconciles only committed Git revisions.
2. Seed the Vault app secret path for the target environment.
3. Seed the production VolSync secret path if deploying prod.
4. Reconcile `infra-gateway` first so the shared `.com` gateway exposes `n8n.myrobertson.com`.
5. Reconcile `apps` after the gateway is ready.

## Post-deploy checks

### Flux

```bash
flux get kustomizations -A
kubectl get helmrelease -n default n8n
```

### n8n resources

```bash
kubectl get pods,svc,deploy -n default | grep -i n8n
kubectl get cluster,scheduledbackup,redis -n default | grep -i n8n
```

### Gateway and remote access

```bash
kubectl get gateway myrobertson-com-gateway -n default -o yaml | grep -A6 'name: n8n'
kubectl get httproute n8n -n default -o yaml
kubectl get secret n8n-myrobertson-com-cert -n default
curl -Ik https://n8n.myrobertson.com
```

## Auth constraint

This repo protects n8n with Authelia at the gateway layer. That provides front-door auth, but it does not replace the native n8n login page. n8n LDAP login is a licensed feature and is not configured here.