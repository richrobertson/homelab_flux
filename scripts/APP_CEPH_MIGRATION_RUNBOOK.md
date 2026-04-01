# App Config PVC Migration to CephFS

Last updated: 2026-03-31

This document captures the repeatable migration process used to move app config PVCs from Synology (`synology-iscsi-storage`) to CephFS (`csi-cephfs-sc`) with minimal risk.

## Scope

- Source PVC: `<app>-config` (Synology RWX)
- Target PVC: `<app>-config-ceph` (CephFS RWX)
- Workload type: app deployed via Flux HelmRelease in `apps/base/<app>/release.yaml`

## Standard migration sequence

Use this exact order for each app.

1. Verify source and target PVC state.
2. If target Ceph PVC does not exist, create it from `apps/base/<app>/config-ceph-pvc.yaml`.
3. Scale app deployment to `0` replicas to stop writes.
4. Run one-shot copy pod from `scripts/migrate-<app>-config-pod.yaml`.
5. Wait for copy pod status `Succeeded` and confirm logs show `copied-<app>`.
6. Update `apps/base/<app>/release.yaml`:
	- `persistence.config.storageClass: csi-cephfs-sc`
	- `persistence.config.existingClaim: <app>-config-ceph`
7. Commit and push the manifest change.
8. Reconcile Flux:
	- `flux reconcile source git flux-system -n flux-system`
	- `flux reconcile kustomization apps -n flux-system`
9. Verify new pod is running and mounts `config=<app>-config-ceph`.
10. Delete completed copy pod.

## Command template

Replace `<app>` with the app name (for example `sonarr`, `radarr`).

```bash
# 1) Ensure target PVC exists
kubectl -n default apply -f apps/base/<app>/config-ceph-pvc.yaml
kubectl -n default wait --for=jsonpath='{.status.phase}'=Bound pvc/<app>-config-ceph --timeout=300s

# 2) Stop app
kubectl -n default scale deployment/<app> --replicas=0
kubectl -n default rollout status deployment/<app> --timeout=240s

# 3) Copy latest data
kubectl -n default delete pod migrate-<app>-config --ignore-not-found
kubectl -n default apply -f scripts/migrate-<app>-config-pod.yaml
kubectl -n default wait --for=jsonpath='{.status.phase}'=Succeeded pod/migrate-<app>-config --timeout=1200s
kubectl -n default logs migrate-<app>-config --tail=50

# 4) Push HelmRelease claim switch in Git
git add apps/base/<app>/release.yaml
git commit -m "feat(<app>): migrate config persistence to cephfs"
git push origin main

# 5) Reconcile and verify
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization apps -n flux-system
kubectl -n default get pods -l app.kubernetes.io/name=<app>
kubectl -n default get pod <new-pod-name> -o jsonpath='{range .spec.volumes[*]}{.name}{"="}{.persistentVolumeClaim.claimName}{"\n"}{end}'

# 6) Cleanup
kubectl -n default delete pod migrate-<app>-config
```

## Current migration status

As of 2026-03-30:

| App | HelmRelease state | Running pod | Mounted config claim | Copy status | Git commit |
|---|---|---|---|---|---|
| Sonarr | Ready=True, upgrade succeeded (`sonarr.v54`) | `sonarr-7fd9dd897f-78j2b` | `sonarr-config-ceph` | Completed (`copied-sonarr`) | `dcd29e1` |
| Radarr | Ready=True, upgrade succeeded (`radarr.v66`) | `radarr-6677f99c78-cwwgc` | `radarr-config-ceph` | Completed (`copied-radarr`) | `6e38835` |
| Lidarr | Ready=True, upgrade succeeded (`lidarr.v51`) | `lidarr-79c965dd46-dxv25` | `lidarr-config-ceph` | Completed (`copied-lidarr`) | `982acb1` |
| Overseerr | Ready=True, upgrade succeeded (`overseerr.v38`) | `overseerr-cc6bc56d-stzrh` | `overseerr-config-ceph` | Completed (`copied-overseerr`) | `982acb1` |
| Prowlarr | Ready=True, upgrade succeeded (`prowlarr.v47`) | `prowlarr-7f58b458d4-xrd48` | `prowlarr-config-ceph` | Completed (`copied-prowlarr`) | `982acb1` |

| Immich | Ready=True, upgrade succeeded (`immich.v16`) | `immich-server-6dff8f56fd-88k42` | `immich-data-files-pvc-ceph` | Completed (`copied-immich-data`) | `337bbf3` |

PVC status snapshot:

- `sonarr-config`: Bound (`synology-iscsi-storage`)
- `sonarr-config-ceph`: Bound (`csi-cephfs-sc`)
- `radarr-config`: Bound (`synology-iscsi-storage`)
- `radarr-config-ceph`: Bound (`csi-cephfs-sc`)
- `lidarr-config`: Bound (`synology-iscsi-storage`)
- `lidarr-config-ceph`: Bound (`csi-cephfs-sc`)
- `overseerr-config`: Bound (`synology-iscsi-storage`)
- `overseerr-config-ceph`: Bound (`csi-cephfs-sc`)
- `prowlarr-config`: Bound (`synology-iscsi-storage`)
- `prowlarr-config-ceph`: Bound (`csi-cephfs-sc`)
- `immich-data-files-pvc`: Bound (`synology-iscsi-storage`) (kept for now; not mounted by current server pod)
- `immich-data-files-pvc-v2`: Bound (`synology-iscsi-storage`) (legacy intermediate claim; not mounted by current server pod)
- `immich-data-files-pvc-ceph`: Bound (`csi-cephfs-sc`) (active mounted claim)

## Post-cutover notes

- Keep legacy Synology PVCs until app behavior is validated for an agreed soak period.
- If rollback is needed, revert `existingClaim` in `apps/base/<app>/release.yaml` back to `<app>-config`, commit, push, and reconcile apps.
- Avoid deleting source PVCs during the same maintenance window as cutover.

## Backup verification after migration

After each app cutover to Ceph-backed PVCs, confirm backups are still healthy for both CNPG and VolSync.

1. Reconcile source and apps kustomization.
2. Confirm ReplicationSource objects report recent successful sync times.
3. Confirm CNPG Backup resources are still completing.
4. Confirm backup objects are present under the expected S3 prefixes.

Suggested commands:

```bash
flux --context=admin@prod reconcile source git flux-system -n flux-system
flux --context=admin@prod reconcile kustomization apps -n flux-system

kubectl --context admin@prod get replicationsource -n default \
	-o custom-columns=NAME:.metadata.name,LASTSYNC:.status.lastSyncTime,MSG:.status.conditions[0].message

kubectl --context admin@prod get backups.postgresql.cnpg.io -n default -o wide
```

Retention reference:

- VolSync retention for prod is documented in `apps/prod/volsync/README.md` and implemented in `apps/prod/volsync/replicationsources.yaml` as daily 7, weekly 4, monthly 3, yearly 100.
