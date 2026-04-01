# Staging Plex iGPU Validation Report (2026-04-01)

## Scope
This report documents staging validation for Plex hardware transcoding on Talos-based Kubernetes, including Proxmox passthrough checks and backup-state verification before production rollout.

## Summary
- Proxmox staging worker VMs now have `hostpci0=0000:00:02.0,pcie=1` in both saved and runtime config.
- Proxmox task logs show VM start with VFIO Intel display OpRegion detected.
- Talos/Kubernetes workers still do not expose `/dev/dri` and do not advertise `gpu.intel.com/i915` allocatable resources.
- Staging backup cleanup completed:
  - Live `ReplicationSource`, `ScheduledBackup`, and `Backup` objects were deleted from staging.
  - The VolSync controller remains installed as shared infrastructure owned by `infra-controllers`, but no backup schedules remain.

## Data Collected

### 1) Proxmox passthrough runtime state
Validated with API checks against VMIDs:
- `k8s-stg-worker-0` (`pve3/209`)
- `k8s-stg-worker-1` (`pve4/219`)
- `k8s-stg-worker-2` (`pve5/218`)

Observed:
- `status=running`
- `saved.hostpci0=0000:00:02.0,pcie=1`
- `current.hostpci0=0000:00:02.0,pcie=1`

Observed in recent VM task logs:
- `kvm: ... vfio-pci,host=0000:00:02.0 ... info: OpRegion detected on Intel display ...`
- `TASK OK`

### 2) Kubernetes/Talos device visibility
From staging worker diagnostic pods with host mounts:
- `/host-dev/dri`: not present on workers.
- `/host-sys/class/drm`: only `version` file present.

From node inventory:
- `intel.feature.node.kubernetes.io/gpu`: not present.
- `gpu.intel.com/i915` allocatable: not present.

### 3) Talos extension evidence
From staging node labels:
- Present: `extensions.talos.dev/intel-ucode`, `extensions.talos.dev/iscsi-tools`, `extensions.talos.dev/qemu-guest-agent`.
- Missing (required for Intel iGPU path): `extensions.talos.dev/i915`, `extensions.talos.dev/mei`, `extensions.talos.dev/intel-ice-firmware`.

## Backup State Check (Staging)

### VolSync
Live query returned many `replicationsource.volsync.backube/*` objects in namespace `default`.
Additional findings:
- `apps/staging/kustomization.yaml` still included `volsync` and was updated to remove it.
- A live `HelmRelease/OCIRepository` for `volsync` remained present in `default`, but it is owned by `infra-controllers`, not the staging apps set.
- Live `ReplicationSource` objects had no Flux ownership metadata.

Cleanup result:
- `ReplicationSource` count after cleanup: `0`

Conclusion: staging no longer has active VolSync backup schedules.

### CNPG
Live query returned:
- `cluster.postgresql.cnpg.io/*` (healthy clusters)
- `scheduledbackup.postgresql.cnpg.io/cluster-immich-ceph-daily`
- multiple `backup.postgresql.cnpg.io/*` (failed backup attempts)

Additional findings:
- `cluster-immich-ceph-daily` had no Flux ownership metadata.
- No staging Git manifest defined a `ScheduledBackup`; the object was unmanaged drift.

Cleanup result:
- `ScheduledBackup` count after cleanup: `0`
- `Backup` count after cleanup: `0`

Conclusion: staging no longer has active CNPG backup schedules or retained `Backup` objects.

## Procedure Validation Outcome
The currently validated procedure is partially successful:
- PASS: Proxmox passthrough config is being applied at runtime.
- FAIL: Guest Talos nodes still do not surface DRM device nodes and Kubernetes GPU allocatable resources.

This means VM passthrough alone is insufficient in the current Talos image/config state.

## Required Changes Before Production

1. Talos image/extensions
- Move to a Talos image schematic that includes:
  - `siderolabs/i915`
  - `siderolabs/intel-ice-firmware`
  - `siderolabs/intel-ucode`
  - `siderolabs/mei`

2. Remove fake GPU labeling
- Do not set `intel.feature.node.kubernetes.io/gpu=true` manually in worker machine config patches.
- Require label to be discovered by NFD + Intel rules only.

3. Terraform codification
- Codify worker `hostpci` passthrough in the bootstrap Terraform VM module path.
- Avoid one-off API/manual VM edits.

4. Validation gates (must pass in this order)
- Host/guest: `/dev/dri/renderD*` present on workers.
- Labels: `intel.feature.node.kubernetes.io/gpu=true` appears naturally.
- Resources: `gpu.intel.com/i915` appears in node allocatable.
- Workload: Plex pod requests GPU and can access `/dev/dri`.
- App test: confirmed hardware transcode under active stream.

5. Backup policy for staging (if desired)
- Keep `volsync` out of `apps/staging/kustomization.yaml`.
- Reconcile staging Flux after Git changes.
- Delete unmanaged live `ReplicationSource`, `ScheduledBackup`, and historical `Backup` objects from staging.
- Re-verify no `ReplicationSource`, `ScheduledBackup`, or `Backup` resources remain.

## Final Staging Backup State
- `ReplicationSource`: `0`
- `ReplicationDestination`: `0`
- `ScheduledBackup`: `0`
- `Backup`: `0`
- VolSync controller: still installed in `default`, owned by `infra-controllers`

## References
- Breadnet implementation notes used during validation:
  - https://breadnet.co.uk/intel-gpus-on-talos/
- Bootstrap repo areas to align for production:
  - `homelab_bootstrap/terraform/kubernetes/talos/main.tf`
  - `homelab_bootstrap/terraform/kubernetes/nodes/main.tf`
  - `homelab_bootstrap/terraform/kubernetes/talos_vm/main.tf`
