# Ceph CSI Integration - Deep Root Cause Analysis
**Date**: March 28, 2026  
**Status**: ACTIVE - Core urgent fixes deployed, mount lifecycle instability still under investigation  
**Scope**: Both RBD and CephFS provisioning, with primary focus on CephFS lifecycle and migration reliability

---

## Executive Summary

The Ceph integration initially had **5 interconnected architectural failures**. Latest field validation confirms partial remediation:

1. **CephFS FUSE Mount Lifecycle Leaks** (PRIMARY, OPEN) - unmount/mount lifecycle can still stall, blocking migrations and some provisions
2. **Missing radosNamespace Parameters** (FIXED for active paths) - problematic test paths cleaned up
3. **Dual CSI Provider Configuration** (OPEN) - operational complexity remains across rook and standalone controllers
4. **Stale RGW Endpoints** (FIXED) - stale endpoint 192.168.10.4 removed from active RGW endpoint config
5. **Insufficient Timeout Handling** (PARTIALLY FIXED) - explicit RADOS timeouts added via client config, but CSI lifecycle fallback behavior still missing

---

## Latest Findings Addendum (March 28, 2026 - Post-Deployment)

### Confirmed Deployed Fixes

1. **Stale endpoint removed**
- 192.168.10.4 removed from CephObjectStore external RGW endpoints
- Active endpoints now: 192.168.10.3 and 192.168.10.5

2. **RADOS operation timeouts configured**
- ConfigMap `ceph-client-config` deployed with:
   - `rados_mon_op_timeout = 30`
   - `rados_osd_op_timeout = 30`
   - `client_mount_timeout = 30`

### Post-Fix Provisioning Validation

Observed after urgent fix deployment:
- **ceph-block (RBD)**: Bound successfully (~47s)
- **ceph-filesystem (Rook CephFS)**: Bound successfully (~47s)
- **csi-cephfs-sc (standalone CephFS)**: remained Pending (>180s in validation window)

Interpretation:
- Urgent fixes improved behavior for active RBD and rook-managed CephFS paths.
- Standalone CephFS path still shows separate provisioning latency/stall behavior and needs dedicated remediation.

### Sonarr Migration Findings (Latest)

During migration of Sonarr config storage to Ceph:
- Target PVC `sonarr-config-ceph` successfully reached **Bound** on `csi-cephfs-sc`.
- Migration pod `migrate-sonarr-config` remained in **ContainerCreating** while both old/new volumes were attached.
- Pod events showed successful scheduling and volume attach, but container never progressed to running within test window.

Interpretation:
- This aligns with ongoing CephFS lifecycle/mount path instability (stage/publish path), not with basic PVC creation.
- Practical impact: migration workflows can stall even when target PVC creation succeeds.

---

## Root Cause #1: CephFS Mount Lifecycle Leak - CRITICAL

### Manifestation
- PVC provisioning initiates with `CreateVolume` RPC
- After 150 seconds: `DeadlineExceeded` error from external-provisioner
- Retry hits: `operation with the given Volume ID already exists`
- Further retries loop forever with "Slow GRPC" log pattern
- User sees: `Pending` PVCs that never bind

### Technical Details

**CephFS uses FUSE (user-space filesystem)** instead of kernel mount:
```
ceph-fuse binary runs as daemon on worker node
└── Mount point: /var/lib/kubelet/plugins/kubernetes.io/csi/cephfs.csi.ceph.com/{HASH}/globalmount
    └── Bind-mounted to: /var/lib/kubelet/pods/{POD_UID}/volumes/kubernetes.io~csi/pvc-xxx/mount
        └── Exposed to app container
```

**The Lifecycle Should Be**:
1. **CreateVolume**: CSI creates subvolume in Ceph, returns volumeHandle (= subvolume path)
2. **ControllerPublish**: CSI validates access credentials (CephFS specific)
3. **NodeStageVolume**: Kubelet calls node plugin to setup FUSE mount globally
   - Starts `ceph-fuse` process
   - Creates globalmount point
   - Mounts via FUSE daemon
4. **NodePublishVolume**: Kubelet bind-mounts globalmount into pod
5. **NodeUnpublishVolume** (on deletion): Kubelet unmounts pod bind
6. **NodeUnstageVolume**: CSI node plugin unmounts FUSE mount
   - **PROBLEM**: This can hang indefinitely if FUSE is slow/blocked
7. **ControllerUnpublish**: CSI validates no active mounts
8. **DeleteVolume**: CSI removes subvolume from Ceph

**What Actually Happens**:
- Step 6 (NodeUnstageVolume) times out or hangs
- FUSE daemon is not killed (becomes orphan)
- globalmount still present on node
- Ceph subvolume still marked "mounted" in CSI internals
- Step 3 on next pod tries to create volume with same ID
- CSI driver rejects: "mount point already exists" or "VolumeID already exists in registry"
- External-provisioner hits 150s timeout, marks provision as failed
- **Retries hit the in-flight lock, spinning in deadlock**

### Why FUSE Mounts Hang

From Ceph documentation and CSI issue #5419:
1. **Slow RADOS operations** - FUSE communicates to RADOS for every metadata op
   - Mon quorum issues (10.4 is down) cause timeouts
   - MDS slowness causes client stalls
2. **Long lock file paths** - Encryption metadata creates lock files with long names
   - Path too long errors (`rados: ret=-36`) block encryption subvolume creation
   - Cascades to NodeStageVolume failure
3. **Client eviction** - MDS can evict clients with session timeouts
   - FUSE process receives signal but cleanup hangs
4. **Network stalls** - Transient network issues to Ceph cluster
   - Client waits for Ceph response that never comes

### Evidence from Terminal History

```
Mount cleanup required (manual workaround):
  kubectl debug node/k8s-prod-worker-2 --profile=sysadmin --image=alpine:3.20 -- \
    nsenter -t 1 -m -- umount -l /var/lib/kubelet/plugins/kubernetes.io/csi/cephfs.csi.ceph.com/{HASH}/globalmount
  Result: After umount, PVC finally bound
```

This proves: **FUSE mount cleanup is the blocker**. Once manually cleared, provisioning succeeds.

### Duration of Stuck Operations  

Observed pattern from logs:
- **20-40 min stuck**: Mount hangs indefinitely
- **30 min after pod deletion**: Manual intervention required
- **No automatic recovery**: CSI doesn't timeout/recover

---

## Root Cause #2: Missing radosNamespace Parameter - HIGH

### The Issue

RADOS namespaces partition data within a pool. Different clients should use different namespaces to avoid key collisions.

**Current Config**:
```yaml
# rook-external-cluster.yaml (CORRECT)
cephFS:
  radosNamespace: cephfs-csi  # explicit namespace

# ceph-filesystem.yaml (CORRECT)  
cephFS:
  radosNamespace: cephfs-csi-standalone  # different namespace

# scripts/noenc-sc-test-20260325.yaml (WRONG)
parameters:
  # NO radosNamespace specified
  fsName: kubernetes-prod-cephfs
  pool: kubernetes-prod-cephfs_data
```

### Impact

Without radosNamespace, all CSI operations use **default RADOS namespace**.

**Symptom**: Multiple provisioners writing to same namespace
- Rook provisioner writes metadata object `.csi-volume-<ID>`  
- Standalone provisioner tries to write same key → conflicts
- Ceph RADOS returns "already exists" or "permission denied"

Combines with RADOS timeout issue (Root Cause #5):
- Timeout to default namespace → retry
- Retry hits stale cache with collision → deadlock

### Configuration Patterns

**All CephFS StorageClasses must specify**:
```yaml
parameters:
  radosNamespace: "<unique-namespace-per-provisioner>"
  fsName: kubernetes-prod-cephfs
  pool: kubernetes-prod-cephfs_data
  # ... other params
```

**Recommended Convention**:
```
rook provisioner       → radosNamespace: cephfs-csi
standalone provisioner → radosNamespace: cephfs-csi-standalone
other provisioners     → radosNamespace: cephfs-<purpose>
```

---

## Root Cause #3: Stale RGW Endpoint - HIGH

### Current Status (Updated)
- **Status**: FIXED in active RGW endpoint configuration.
- 192.168.10.4 has been removed from active external endpoint list used by object store gateway config.
- Remaining risk is configuration drift/reintroduction; keep endpoint validation in runbooks.

### Evidence

ConfigMap `rook-ceph-mon-endpoints` in rook-ceph-external NS:
```yaml
data:
  externalMons: ""
  mapping: '{"node":{}}'
  maxMonId: "0"
  data: pve3=192.168.10.3:6789  # ONLY 10.3 present
  
# BUT historical endpoints included:
# 192.168.10.4:6789 (DOWN - connection refuses)
# 192.168.10.5:6789 (may be unstable)
```

### What Rook Does

Rook operator monitors the external Ceph cluster and updates mon endpoints in ConfigMap.

**Historical Bug Behavior (pre-fix)**:
- Operator queried Mon quorum via `192.168.10.4:6789`
- Connection refused → logs "failed to validate external ceph version ... this must never happen"
- Endpoint refresh drifted and stale values persisted

**Current Behavior (post-fix)**:
- Active external RGW endpoint configuration no longer includes `192.168.10.4`
- Operational risk shifted from active failure to regression/drift risk

### Impact on CSI

Historical CSI retry pattern when stale mon existed:
```
monitors: ["192.168.10.3:6789", "192.168.10.4:6789", "192.168.10.5:6789"]
```

**Retry Pattern**:
1. Provision CreateVolume → attempt 192.168.10.3:6789 (success or timeout)
2. Mon responds or timeout after 30s
3. Retry mechanism attempts 10.4:6789 (dead → immediate refuse)
4. Fall back to 10.3:6789 (but loses 3-5 seconds per retry)
5. Loop repeats, accumulating delay

**Historical latency impact**: +5-10s per each failed mon attempt × number of retries

**Current residual risk**:
- If stale RGW endpoints are reintroduced through config drift, this latency pattern will return.
- Keep post-reconcile endpoint validation as a required guardrail.

---

## Root Cause #4: Dual CSI Provider Conflict - MEDIUM

### Configuration Issue

Two CephFS controller stacks are active in the cluster, each owning different StorageClasses and operational paths:

```yaml
# infrastructure/controllers/ceph-csi/ceph-filesystem.yaml
metadata:
  name: ceph-csi-cephfs
spec:
  chart: ceph-csi-cephfs
   provisioner: cephfs.csi.ceph.com

# infrastructure/configs/rook-external-cluster.yaml
provisioner: rook-ceph.cephfs.csi.ceph.com
```

**Active provisioner ownership model**:
- **Rook CephFS path**: `rook-ceph.cephfs.csi.ceph.com`
- **Standalone CephFS path**: `cephfs.csi.ceph.com`

**The real problem is not a single duplicate provisioner string**; it is operational split across two CephFS stacks with different behavior, lifecycle handling, and observability.

**StorageClass Confusion**:
```yaml
# Some SCs use rook provisioner
provisioner: rook-ceph.cephfs.csi.ceph.com

# Other test SCs use generic name
provisioner: cephfs.csi.ceph.com

# Result: Different controllers manage different SCs
# Inconsistent behavior, some mount fine, others hang
```

### Current Impact
- Rook-managed CephFS paths are currently meeting expected provisioning behavior.
- Standalone CephFS paths still show pending/stall behavior in some scenarios.
- App migrations can fail asymmetrically depending on which StorageClass/controller path is selected.

---

## Root Cause #5: Insufficient Timeout Handling - MEDIUM

### Current Status (Updated)
- **Status**: PARTIALLY FIXED.
- Explicit RADOS timeouts are now configured via `ceph-client-config`.
- Remaining gap: CSI lifecycle operations (especially unstage/unmount fallback and stale mount cleanup) still require hardening.

### Kubernetes CSI Timeout Architecture

**External-Provisioner** (cloud.google.com/gke-release/csi-provisioner):
- Default CreateVolume RPC timeout: **150 seconds**
- Times out after 150s
- Marks volume as ProvisioningFailed
- **Does NOT** automatically retry (caller must retry)

**CSI Driver** (ceph-csi):
- Base RADOS operation timeouts are now configured via `ceph-client-config`
- Remaining risk: lifecycle operations can still hang during stage/unstage/unmount paths
- Node plugin still lacks robust cleanup fallback for stuck unmounts

### Cascading Failures

```
0s:   CreateVolume RPC starts
30s:  First mon attempt times out (if mon unavailable)
60s:  Retry second mon attempt
90s:  Retry third mon attempt
150s: External-provisioner gives up → DeadlineExceeded
170s: User or operator retries
        → CSI still has stale in-flight op
        → immediately rejects with "already exists"
```

### Missing Safeguards

1. **NodeUnstageVolume timeout**: No timeout for FUSE unmount
   - Should fail after 30s, fallback to lazy unmount (`umount -l`)
   - Should kill ceph-fuse process if unmount fails

2. **Pod webhook timeout**: No validation that mount cleanup will complete
   - Should block pod termination if stale mount detected

3. **Lease-based cleanup**: No background cleanup of orphaned mounts
   - Should run periodic job to detect and clean leaked mounts

---

## Synthesis: Failure Evolution

### Historical Cascade (Pre-Fix)

1. **Encryption enabled on test SC** (KMS integration)
   - Creates longer lock file paths → "File Name Too Long" errors
   - RADOS operations take longer from path encoding
   
2. **Mon 10.4 becomes unavailable**
   - Rook operator fails to validate version → stops updating ConfigMap  
   - Stale 10.4 remains in CSI config
   
3. **First PVC provision hits FUSE slow path**
   - Encryption metadata operations timeout waiting for MDS
   - CreateVolume hangs past 150s → DeadlineExceeded
   
4. **FUSE cleanup on delete hangs**
   - ceph-fuse waiting for RADOS response (to 10.4?)
   - NodeUnstageVolume never completes
   - Mount point remains, ceph-fuse orphaned
   
5. **Next PVC with same subvolume name tries  to mount**
   - CreateVolume sees existing subvolume/mount point
   - Returns "already exists"
   - External-provisioner retries hit same lock
   - **Deadlock achieved**: volume stuck Pending forever

6. **Dual CSI configuration accelerates failure**
   - Provisioners interfere with each other's namespaces
   - Some PVCs go to rook, others to standalone
   - Different retry behavior and timeouts
   - Unpredictable success/failure

### Current Failure Mode (Post-Fix)

1. Monitor endpoint staleness is no longer the primary active blocker.
2. Base RADOS timeout configuration is now present.
3. Remaining dominant risk is CephFS lifecycle instability (stage/unstage/unmount) plus dual-stack operational complexity, most visible on standalone CephFS paths and migration pods.

---

## Verification: Why Manual `umount -l` Fixes It

When you manually unmounted the FUSE mount point on worker nodes:
- **FUSE cleanup barrier removed** → next provision can attempt
- Old orphaned mount gone → no "already exists" collision
- New CreateVolume succeeds
- **Proves**: The issue is not Ceph cluster health, but mount lifecycle on nodes

---

## Recommended Fixes (Priority Order)

### IMMEDIATE (Next Session)

1. **Remove test StorageClasses with missing radosNamespace**
   - Delete any SC without explicit `radosNamespace` parameter
   - Document requirement: all CephFS SCs must declare namespace

2. **Consolidate CSI setup**
   - Choose standalone ceph-csi OR rook-ceph, not both
   - Remove conflicting deployment
   - Update all SCs to reference single provisioner consistently

3. **Fix monitor endpoint staleness**
    - **Completed**: stale 192.168.10.4 removed from active RGW endpoint configuration.
    - Remaining hardening:
       - Add validation to prevent dead endpoints from being committed/deployed.
       - Add a post-reconcile check that all configured endpoints respond.

### HIGH Priority (This Week)

4. **Add RADOS operation timeouts**
    - **Completed (base config)**: `ceph-client-config` deployed with 30s mon/osd/mount timeout settings.
    - Remaining hardening:
       - Confirm all relevant CSI components consume the config consistently.
       - Keep timeout values aligned across controllers and node plugins.

5. **Implement NodeUnstageVolume timeout**
   - Add 30-second timeout to unmount operations
   - Fallback to lazy unmount (`umount -l`) on timeout
   - Kill orphaned ceph-fuse processes
   - **Requires CSI driver patch** OR replace with timeout-aware deployment

6. **Disable KMS encryption initially**
   - Test with `encrypted: false` in StorageClass
   - Removes overhead of encryption metadata operations
   - Crypto can be re-enabled once base path is stable

### MEDIUM Priority (Week 2+)

7. **Add background mount cleanup job**
   - DaemonSet running on all workers
   - Detects stale FUSE mounts not bound to any PVC
   - Cleans up periodically (every 5 min)
   - Logs all cleanup operations

8. **Add network resilience monitoring**
   - Monitor TCP connections from CSI to mons
   - Alert if mon becomes unreachable
   - Automatically trigger operator ConfigMap refresh

9. **Resource limits on CSI pods**
   - Provisioner: `memory: 512Mi`, `cpu: 250m`
   - Node plugin: `memory: 256Mi`, `cpu: 100m`
   - Prevents memory leaks from consuming all node resources

10. **Migration runbook hardening for app cutovers (new)**
    - For apps like Sonarr, perform migration using a deterministic sequence:
       - Scale app down to 0 before copy
       - Validate source and target mounts inside migration pod before copy
       - Copy with retries and integrity checks (`rsync` + count/hash spot checks)
       - Switch PVC reference only after successful copy validation
    - Avoid partial merge patches that overwrite full `volumes` arrays; use full manifest updates in Git.

### Standalone CephFS Remediation (Focused)

11. **Instrument standalone controller path end-to-end**
    - Verify leader election health and active worker in `ceph-csi-cephfs-provisioner`
    - Confirm `CreateVolume` reaches plugin container for each pending PVC UID
    - Correlate controller events with node-stage/node-publish logs by volume ID

12. **Add preflight mount checks for migration pods**
    - Before copy, assert both source and target mount points are readable/writable
    - Fail fast if pod remains in `ContainerCreating` beyond threshold
    - Emit a clear event/log marker so stalled cutovers are immediately detectable

13. **Define rollback-safe cutover flow for Sonarr-class apps**
    - Keep original PVC untouched until copy + app startup checks pass
    - Cut over deployment only after validation gates pass
    - If startup fails, revert PVC reference to prior claim in one change

---

## Acceptance Criteria (Explicit)

The incident is considered remediated only when all criteria below are met:

1. **Endpoint hygiene**
   - No active Ceph endpoint config includes 192.168.10.4
   - Post-reconcile check validates all configured endpoints respond

2. **Timeout effectiveness**
   - CSI controller and node plugin paths use timeout configuration consistently
   - Repeated provisioning under load does not produce indefinite hangs

3. **Provisioning SLOs**
   - RBD and rook CephFS test PVCs bind within 60s in repeated runs
   - Standalone CephFS either binds within 240s or emits diagnosable failure signals (not silent Pending)

4. **Lifecycle cleanup**
   - PVC delete/recreate cycles do not require manual `umount -l`
   - No stale globalmount paths remain after cleanup checks

5. **Migration reliability**
   - Sonarr-style migration pod reaches Running and completes copy with verification
   - App starts successfully on target PVC without manual node-level cleanup

---

## Testing Plan

Once fixes applied, test with:

```bash
# 1. Clean start - ensure no stale mounts
kubectl get nodes -o wide | while read node _; do
  kubectl debug node/$node --profile=sysadmin --image=alpine -- \
    findmnt /var/lib/kubelet/plugins/kubernetes.io/csi/cephfs.csi.ceph.com
done

# 2. Create test namespace
kubectl create ns ceph-integration-test

# 3. Apply test PVC with explicit radosNamespace
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs
  namespace: ceph-integration-test
spec:
  accessModes: [ReadWriteMany]
  storageClassName: ceph-filesystem
  resources:
    requests:
      storage: 1Gi
EOF

# 4. Wait for binding on rook CephFS (target SLO: <=60s)
kubectl wait -n ceph-integration-test \
  --for=jsonpath='{.status.phase}'=Bound \
  pvc/test-cephfs \
   --timeout=60s

# 5. Create test pod to mount
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-mounter
  namespace: ceph-integration-test
spec:
  containers:
  - name: app
    image: alpine
    command: [sleep, "300"]
    volumeMounts:
    - name: data
      mountPath: /mnt
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-cephfs
EOF

# 6. Wait for pod to mount
kubectl wait -n ceph-integration-test \
  --for=condition=Ready \
  pod/test-mounter \
  --timeout=30s

# 7. Delete and verify cleanup
kubectl delete -n ceph-integration-test pod/test-mounter pvc/test-cephfs
sleep 10
# Should see no stale mounts after cleanup

# 8. Standalone CephFS validation (target SLO: <=240s or clear error)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-standalone
  namespace: ceph-integration-test
spec:
  accessModes: [ReadWriteMany]
  storageClassName: csi-cephfs-sc
  resources:
    requests:
      storage: 1Gi
EOF

kubectl wait -n ceph-integration-test \
  --for=jsonpath='{.status.phase}'=Bound \
  pvc/test-cephfs-standalone \
  --timeout=240s || kubectl describe pvc -n ceph-integration-test test-cephfs-standalone
```

---

## References

- **Ceph CSI Issue #5419**: Mount failures with encryption enabled
- **Ceph CSI Issue #5462**: NodeGetVolumeStats with hanging staging paths
- **CephFS Admin Guide**: https://docs.ceph.com/en/latest/cephfs/
- **RADOS Namespace**: https://docs.ceph.com/en/latest/rados/operations/pools/#namespaces
-  **CSI Spec Timeouts**: https://github.com/container-storage-interface/spec/blob/master/spec.md

---

## Appendix: Log Patterns to Monitor

**Found Patterns Indicating Root Cause #1** (Mount leak):
```
"Slow GRPC" + VolumeID repeated
"operation with the given Volume ID already exists"
"deadlineExceeded" in external-provisioner
"kubelet.*Unmount.*timeout"
```

**Found Patterns Indicating Root Cause #3 Regression** (Stale mon reintroduced):
```
"failed to validate external ceph version"
"connection refused" to 192.168.10.4:6789
"rbd: ret=-110 Connection timed out"
```

**Found Patterns Indicating Root Cause #5** (Insufficient timeout):
```
"context deadline exceeded"
"GRPC error (14|7)" (unavailable/permission errors)
"Mount leaked" on node after pod deletion
```

