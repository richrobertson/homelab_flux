# Ceph Pool Consolidation Runbook
**Date**: April 12, 2026
**Status**: Draft plan, safe to execute in phases
**Goal**: Reduce pool sprawl and operational overhead while preserving data and service continuity.

---

## 1. Current State (Post-Cleanup Snapshot)

Cluster observations from latest checks:

- `HEALTH_OK`
- 3 OSDs, 3/3 up+in
- Raw usage approx `66%`
- Filesystems online:
  - `cephfs`
  - `kubernetes-prod-cephfs`
  - `rook_prod`

Top pools by raw usage:

1. `p0` (RBD)
2. `kubernetes-prod-cephfs_data`
3. `cephfs_data`
4. `rook_prod`

Active pool families:

- RBD: `p0`, `rook_prod`
- CephFS:
  - `cephfs_data` + `cephfs_metadata`
  - `kubernetes-prod-cephfs_data` + `kubernetes-prod-cephfs_metadata`
  - `rook_prod_data` + `rook_prod_metadata`
- RGW system/object pools: `.rgw.root`, `default.rgw.*`

### Staging Validation (April 12, 2026)

Staging context (`admin@staging`) currently uses Ceph-backed StorageClasses that map to both legacy and target backends:

- `ceph-block` -> RBD pool `rook_prod`
- `ceph-filesystem` and `ceph-filesystem-fuse` -> filesystem `rook_prod` / pool `rook_prod_data`
- `csi-cephfs-sc` and `csi-cephfs-sc-nokms-test` -> filesystem `kubernetes-prod-cephfs` / pool `kubernetes-prod-cephfs_data`

Observed staging PVC usage confirms active consumers on both families, so any consolidation must include staging migration sequencing, not prod-only sequencing.

---

## 2. Consolidation Target

Recommended target layout:

1. **Primary CephFS**: `kubernetes-prod-cephfs`
2. **Primary RBD**: `p0`
3. Keep RGW pools as-is unless decommissioning object storage entirely

Rationale:

- `kubernetes-prod-cephfs` already carries most active CephFS workload.
- `p0` already serves primary RBD workloads.
- Removing duplicate/legacy CephFS filesystems can reduce operational complexity.

---

## 3. What Can Be Consolidated

### 3.1 CephFS (high-value consolidation)

Potentially retire after migration:

- `cephfs` filesystem + pools `cephfs_data`, `cephfs_metadata`
- `rook_prod` filesystem + pools `rook_prod_data`, `rook_prod_metadata`

Prerequisite: all clients/PVCs moved to `kubernetes-prod-cephfs`.

### 3.2 RBD (optional)

Potentially retire after migration:

- `rook_prod` RBD pool

Prerequisite: all RBD images on `rook_prod` copied/migrated to `p0` and consumers switched.

### 3.3 RGW pools (do not consolidate now)

Do not remove unless object storage is fully decommissioned:

- `.rgw.root`
- `default.rgw.log`
- `default.rgw.control`
- `default.rgw.meta`
- `default.rgw.buckets.index`
- `default.rgw.buckets.data`

### 3.4 Can we consolidate to only `default.*` pools?

Short answer: **No**.

Reason:

- `default.*` pools in this cluster are RGW/object-store pools with `application rgw`.
- CephFS workloads require pools with `application cephfs` (data + metadata pair).
- RBD workloads require pools with `application rbd`.

Therefore, consolidating everything to only `default.*` would break block and filesystem consumers.

If desired, you can consolidate within each service family:

- CephFS family consolidation toward `kubernetes-prod-cephfs_*`
- RBD family consolidation toward `p0`
- Keep RGW in `default.rgw.*` while object storage remains in use

---

## 4. Guardrails (Must Pass Before Any Deletion)

Run these checks before each destructive step:

```bash
ceph -s
ceph health detail
ceph fs status
ceph osd pool ls detail
ceph df
```

Kubernetes checks:

```bash
kubectl --context=admin@prod get pvc -A
kubectl --context=admin@prod get sc
kubectl --context=admin@prod get pods -A | grep -Ei 'ceph|volsync|rook|csi'
```

Stop criteria:

- Any PG not `active+clean`
- Any filesystem client surge/errors during migration
- Any application read/write validation failure

---

## 5. Phase Plan

## Phase 0: Freeze and Inventory

1. Freeze storage-class changes (no ad-hoc edits during migration).
2. Export baseline state:

```bash
ceph fs ls
ceph fs status
ceph osd pool ls detail
ceph df -f json-pretty > /tmp/ceph-df-before.json
kubectl --context=admin@prod get pvc -A -o wide > /tmp/pvc-before.txt
kubectl --context=admin@prod get sc -o yaml > /tmp/sc-before.yaml
```

3. Map each app/PVC to source filesystem and target filesystem.

Deliverable:
- App-by-app migration table with owner and change window.

## Phase 1: Migrate CephFS Consumers to kubernetes-prod-cephfs

For each workload currently using `ceph-filesystem`/`rook_prod` or legacy `cephfs`:

1. Create target PVC on `csi-cephfs-sc` (`kubernetes-prod-cephfs`).
2. Quiesce app writes (scale down or maintenance mode).
3. Copy data (rsync/cp with verification).
4. Update deployment/statefulset to target PVC.
5. Scale app up and run validation.

Validation command pattern:

```bash
kubectl --context=admin@prod get pod -n <ns>
kubectl --context=admin@prod describe pod -n <ns> <pod>
kubectl --context=admin@prod logs -n <ns> <pod> --tail=200
```

Exit criteria for Phase 1:

- No active production PVCs remain on retiring filesystems.
- Filesystem client count for retiring FS drops to 0 (or expected system-only).

## Phase 2: Decommission Legacy CephFS Filesystems

Once fully drained:

1. Verify no clients:

```bash
ceph fs status <fs_name>
```

2. Remove filesystem and metadata/data pools (only after confirmed empty/no consumers).

Example sequence (replace names):

```bash
ceph fs fail <fs_name>
ceph fs rm <fs_name> --yes-i-really-mean-it
ceph osd pool delete <metadata_pool> <metadata_pool> --yes-i-really-really-mean-it
ceph osd pool delete <data_pool> <data_pool> --yes-i-really-really-mean-it
```

Apply this to:

- `cephfs`
- `rook_prod` (CephFS side)

## Phase 3: Optional RBD Consolidation (rook_prod -> p0)

Only if desired and planned:

1. List images in `rook_prod`.
2. Migrate/copy images to `p0`.
3. Repoint consumers (StorageClass/PV mapping strategy).
4. Validate workloads.
5. Delete `rook_prod` pool only when empty and unreferenced.

---

## 6. Rollback Plan

Per-app rollback during migration:

1. Scale app down.
2. Repoint workload to old PVC.
3. Scale app up.
4. Re-validate functionality and data integrity.

If filesystem-level issues appear:

1. Halt further migrations.
2. Keep legacy filesystems online.
3. Restore previous StorageClass defaults if changed.
4. Re-run health checks and investigate before continuing.

---

## 7. Success Criteria

1. Single primary CephFS for Kubernetes apps (`kubernetes-prod-cephfs`).
2. Legacy CephFS filesystems removed or fully idle.
3. Optional: single primary RBD pool (`p0`) for VM/block workloads.
4. `ceph -s` remains healthy with stable client I/O and clean PGs.
5. Fewer pools and lower operational complexity without app regressions.

---

## 8. Immediate Next Step

Start with a **dry-run inventory report** only:

1. Enumerate PVCs by StorageClass and map to filesystem/pool.
2. Produce a migration queue ordered by lowest risk first.
3. Execute one pilot app migration end-to-end before bulk cutover.
