# Bitwarden Synology -> Ceph Migration Runbook

## Scope

This runbook migrates Vaultwarden data from the Synology-hosted container (`192.168.1.215`) into the Kubernetes PVC `bitwarden-data-ceph`, then performs a controlled traffic cutover.

## Current staged state

- External route to Synology is still active (`infrastructure/gateway/externalServices/bitwarden.yaml`).
- In-cluster Bitwarden deployment is present but scaled to 0 replicas (`apps/base/bitwarden/deployment.yaml`).
- Backup jobs are present:
  - `bitwarden-db-backup`
  - `bitwarden-files-backup`
- One-time migration Job is present and suspended:
  - `bitwarden-data-seed-from-synology`

## Prerequisites

1. Confirm Synology source path for Vaultwarden data (usually container `/data`).
2. Confirm SSH user and key that can read source files on `192.168.1.215`.
3. Store migration credentials in Vault at `secret/data/bitwarden/prod/migration` with keys:
   - `host`
   - `port`
   - `username`
   - `sourcePath`
   - `sshPrivateKey`
   - `knownHosts` (optional)
4. Reconcile Flux to sync `VaultStaticSecret` to Kubernetes.

## Seed the migration secret

Use Vault values (preferred) and avoid committing credentials.

```bash
vault kv put secret/bitwarden/prod/migration \
  host=192.168.1.215 \
  port=22 \
  username=<ssh_user> \
  sourcePath=</absolute/path/to/vaultwarden/data> \
  sshPrivateKey=@/path/to/id_ed25519 \
  knownHosts="$(ssh-keyscan -p 22 192.168.1.215 2>/dev/null)"
```

## Preflight checks

```bash
kubectl --context admin@prod get vaultstaticsecret -n default bitwarden-synology-migration -o wide
kubectl --context admin@prod get secret -n default bitwarden-synology-migration -o yaml | sed -n '1,80p'
kubectl --context admin@prod get pvc -n default bitwarden-data-ceph
kubectl --context admin@prod get deployment -n default bitwarden -o jsonpath='{.spec.replicas}{"\n"}'
```

Expected:
- `bitwarden-synology-migration` secret exists.
- `bitwarden-data-ceph` is `Bound`.
- Bitwarden replicas are `0` before copy.

## Dry run sync

Patch the suspended job to run as dry run first:

```bash
kubectl --context admin@prod patch job -n default bitwarden-data-seed-from-synology \
  --type merge -p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"true"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context admin@prod logs -n default job/bitwarden-data-seed-from-synology -f
```

After verification, delete and recreate the Job from GitOps state (still suspended) before real copy:

```bash
kubectl --context admin@prod delete job -n default bitwarden-data-seed-from-synology
flux --context=admin@prod reconcile source git flux-system -n flux-system
flux --context=admin@prod reconcile kustomization apps -n flux-system --with-source
```

## Real copy

```bash
kubectl --context admin@prod patch job -n default bitwarden-data-seed-from-synology \
  --type merge -p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"false"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context admin@prod logs -n default job/bitwarden-data-seed-from-synology -f
kubectl --context admin@prod get job -n default bitwarden-data-seed-from-synology
```

Success criteria:
- Job `Complete`.
- Marker file exists in PVC: `/data/.migration-from-synology-complete`.

## Validation before cutover

Run an ephemeral pod to validate key files:

```bash
kubectl --context admin@prod run bitwarden-data-check -n default --rm -it --restart=Never \
  --image=alpine:3.20 --overrides='{
    "spec":{
      "containers":[{
        "name":"check",
        "image":"alpine:3.20",
        "command":["/bin/sh","-ec","ls -lah /data; ls -lah /data/backups || true"],
        "volumeMounts":[{"name":"data","mountPath":"/data"}]
      }],
      "volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"bitwarden-data-ceph"}}]
    }
  }'
```

## Cutover (GitOps)

1. Scale in-cluster Bitwarden to 1 replica:
   - update `apps/base/bitwarden/deployment.yaml` (`replicas: 1`).
2. Route traffic to in-cluster service:
   - add `httpRoute.yaml` into `apps/prod/bitwarden/kustomization.yaml` resources.
3. Remove old external route:
   - remove `externalServices/bitwarden.yaml` from `infrastructure/gateway/kustomization.yaml`.

Then reconcile:

```bash
flux --context=admin@prod reconcile source git flux-system -n flux-system
flux --context=admin@prod reconcile kustomization infra-gateway -n flux-system --with-source
flux --context=admin@prod reconcile kustomization apps -n flux-system --with-source
```

## Post-cutover checks

```bash
kubectl --context admin@prod rollout status deployment/bitwarden -n default --timeout=180s
kubectl --context admin@prod get httproute -n default bitwarden
kubectl --context admin@prod get pod -n default -l app.kubernetes.io/name=bitwarden
```

Validate application login and encrypted item access.

## Backup validation

Trigger each backup job once:

```bash
kubectl --context admin@prod create job --from=cronjob/bitwarden-db-backup -n default bitwarden-db-backup-manual-$(date +%s)
kubectl --context admin@prod create job --from=cronjob/bitwarden-files-backup -n default bitwarden-files-backup-manual-$(date +%s)
kubectl --context admin@prod get jobs -n default | egrep 'bitwarden-(db|files)-backup'
```

Check logs and artifacts under `/data/backups`.
