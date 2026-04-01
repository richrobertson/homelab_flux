# SynologyNAS Container -> Kubernetes Migration Playbook

## Scope

This playbook captures the repeatable process used to migrate a stateful container from SynologyNAS into Kubernetes storage with minimal downtime and controlled rollback.

Use this when:
- Source app is running on SynologyNAS.
- Destination app runs in-cluster with PVC-backed data.
- You need staged cutover and GitOps ownership.

## High-level workflow

1. Prepare in-cluster app manifests in a safe staged mode (`replicas: 0`).
2. Keep the external route to Synology active until data migration is validated.
3. Add migration secret sync via Vault -> VaultStaticSecret.
4. Run migration job in dry-run mode and inspect logs.
5. Run real copy mode and verify data on the target PVC.
6. Ensure backup strategy is in place (VolSync and/or app-level backup where needed).
7. Cut over traffic to in-cluster app through GitOps.
8. Remove old external route.
9. Clean up one-off migration artifacts.

## Repository pattern

Recommended structure (adapt names per app):
- `apps/base/<app>/deployment.yaml`
- `apps/base/<app>/service.yaml`
- `apps/base/<app>/data-ceph-pvc.yaml`
- `apps/base/<app>/migration-secret.yaml`
- `apps/base/<app>/synology-data-seed-job.yaml` (suspended by default)
- `apps/prod/<app>/kustomization.yaml`
- `apps/prod/<app>/httpRoute.yaml`

If using VolSync:
- `apps/prod/volsync/restic-repository-secrets.yaml`
- `apps/prod/volsync/replicationsources.yaml`
- `infrastructure/configs/volsync/restic-repository-secrets.yaml`
- `infrastructure/configs/volsync/replicationsources.yaml`

## Phase 1: Stage destination app safely

1. Add app resources under `apps/base/<app>/`.
2. Set destination deployment replicas to `0` while preparing migration.
3. Confirm app is rendered by the environment kustomization but does not receive traffic yet.

Validation:
```bash
kubectl --context admin@prod get deploy -n default <app>
kubectl --context admin@prod get pvc -n default <target-pvc>
```

## Phase 2: Migration credentials and source access

Use Vault + VaultStaticSecret for migration credentials; do not commit secrets.

Recommended secret keys:
- `host`
- `port`
- `username`
- `sourcePath`
- `knownHosts` (SSH mode)
- `sshPrivateKey` (SSH mode)
- `sourceShare` and `sourcePassword` (SMB mode)

Validation:
```bash
kubectl --context admin@prod get vaultstaticsecret -n default <app>-synology-migration -o wide
kubectl --context admin@prod get secret -n default <app>-synology-migration -o yaml | sed -n '1,80p'
```

## Phase 3: Seed job design

Keep the seed job suspended in Git and support source mode switching via env vars:
- `SOURCE_MODE=ssh|rsync-daemon|smb`
- `DRY_RUN=true|false`
- `ALLOW_NON_EMPTY_TARGET=false` by default

Important behavior:
- Guard against non-empty target to prevent accidental overwrite.
- Use an explicit marker file on successful real copy (example: `.migration-from-synology-complete`).

## Phase 4: Dry-run migration

1. Unsuspend job and set `DRY_RUN=true`.
2. Tail logs and validate source path resolution.
3. Delete completed job and let Flux restore suspended template state.

Commands:
```bash
kubectl --context admin@prod patch job -n default <app>-data-seed-from-synology \
  --type merge -p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"true"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context admin@prod logs -n default job/<app>-data-seed-from-synology -f
```

## Phase 5: Real copy

1. Run with `DRY_RUN=false`.
2. Keep `ALLOW_NON_EMPTY_TARGET=false` unless intentionally re-running.
3. Validate job completion and target data consistency.

Commands:
```bash
kubectl --context admin@prod patch job -n default <app>-data-seed-from-synology \
  --type merge -p '{"spec":{"suspend":false,"template":{"spec":{"containers":[{"name":"seed","env":[{"name":"DRY_RUN","value":"false"},{"name":"ALLOW_NON_EMPTY_TARGET","value":"false"}]}]}}}}'

kubectl --context admin@prod logs -n default job/<app>-data-seed-from-synology -f
kubectl --context admin@prod get job -n default <app>-data-seed-from-synology
```

## Source-mode troubleshooting notes

1. SSH failures (`Permission denied`): verify key/user, shell access, path visibility.
2. rsync-daemon failures (`account system disabled`): account can list modules but lacks module auth rights.
3. SMB fallback: often the most reliable for Synology shares when shell auth is unavailable.

For SMB mode:
- Ensure share and subpath are handled correctly.
- Verify source path maps to the expected app data directory.

## CephFS compatibility note

If rsync reports xattr/SELinux errors (example `lsetxattr ... security.selinux ... Not supported (95)`), avoid ACL/xattr preservation flags.

Use conservative rsync flags for copy compatibility:
- Prefer `-aH --numeric-ids --delete`
- Avoid `-A` and `-X` when target filesystem does not support source xattrs/ACLs

## Phase 6: Backup readiness before/after cutover

1. Ensure target PVC is protected by VolSync `ReplicationSource`.
2. Ensure `VaultStaticSecret` for restic repo config is healthy.
3. Trigger and verify at least one manual backup run.

Validation:
```bash
kubectl --context admin@prod get replicationsource -n default | grep <target-pvc>
kubectl --context admin@prod get vaultstaticsecret -n default | grep restic-config-<app>
```

## Phase 7: Cutover (GitOps-first)

1. Route destination traffic to in-cluster service.
2. Scale app deployment to `1` (or intended replica count).
3. Remove external Synology route from gateway kustomization.
4. Reconcile Flux source and impacted kustomizations.

Commands:
```bash
flux --context=admin@prod reconcile source git flux-system -n flux-system
flux --context=admin@prod reconcile kustomization infra-gateway -n flux-system --with-source
flux --context=admin@prod reconcile kustomization apps -n flux-system --with-source
```

## Phase 8: Post-cutover validation

1. Deployment rollout succeeded.
2. In-cluster HTTPRoute is `Accepted=True` and `ResolvedRefs=True`.
3. Public URL responds successfully.
4. Legacy external route objects are absent.

Validation examples:
```bash
kubectl --context admin@prod rollout status deployment/<app> -n default --timeout=180s
kubectl --context admin@prod get httproute -n default <app> -o yaml | sed -n '1,220p'
kubectl --context admin@prod get httproute -n default | grep <app>-ext-route || echo "<app>-ext-route: not found"
```

## Phase 9: Cleanup

1. Delete one-off migration Jobs in cluster.
2. Remove one-off migration manifests from working tree.
3. Keep only reusable suspended migration templates in Git.
4. Update app-specific runbook with final state and caveats.

## Operational guardrails

- Keep production source route active until real-copy validation completes.
- Prefer GitOps changes for durable state; use direct kubectl only for short-lived migration operations.
- Never commit secrets or plaintext credentials.
- Avoid destructive PVC operations unless explicitly part of a tested rollback/retry plan.

## Reusable checklist

- [ ] App staged in-cluster with replicas set to 0
- [ ] Target PVC bound and writable
- [ ] Vault secret seeded and synced through VaultStaticSecret
- [ ] Seed Job dry-run successful
- [ ] Real copy successful
- [ ] VolSync backup configured and verified
- [ ] In-cluster route enabled
- [ ] External Synology route removed
- [ ] Post-cutover app and route health checks passed
- [ ] One-off migration artifacts removed
