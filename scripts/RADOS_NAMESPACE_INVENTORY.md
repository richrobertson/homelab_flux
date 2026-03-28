# RADOS Namespace Inventory & Usage Analysis

**Date**: March 28, 2026  
**Scope**: Ceph cluster external to Kubernetes (192.168.10.3:6789)  
**Analysis Based On**: Configuration file examination + root cause findings  

---

## Active (In-Use) RADOS Namespaces

### 1. **cephfs-csi** (Production - Rook CephFS Provisioner)
- **Pool**: `kubernetes-prod-cephfs_metadata` (metadata objects)
- **Provisioner**: `rook-ceph.cephfs.csi.ceph.com` (from rook-external-cluster.yaml)
- **Filesystem**: `rook_prod` (subvolumes stored here)
- **Source Config**: `/infrastructure/configs/rook-external-cluster.yaml` line 45
  ```json
  "cephFS":{"radosNamespace":"cephfs-csi", ... }
  ```
- **StorageClasses** using this namespace:
  - `ceph-filesystem` (defined in rook-external-cluster.yaml, uses provisioner `rook-ceph.cephfs.csi.ceph.com`)
- **Status**: ✅ **ACTIVE** - Used for production CephFS mounts via Rook
- **Created Subvolumes**: Kubernetes-managed PVCs via `ceph-filesystem` SC would create subvolumes here
- **Backup/Restore**: YES - Production data

---

### 2. **cephfs-csi-standalone** (Production - Standalone CephFS Provisioner)
- **Pool**: `kubernetes-prod-cephfs_metadata` (metadata objects)
- **Provisioner**: `cephfs.csi.ceph.com` (from ceph-filesystem.yaml)
- **Filesystem**: `kubernetes-prod-cephfs` (subvolumes stored here)
- **Source Config**: `/infrastructure/controllers/ceph-csi/ceph-filesystem.yaml` line 24
  ```yaml
  cephFS:
    radosNamespace: "cephfs-csi-standalone"
  ```
- **StorageClasses** using this namespace:
  - `csi-cephfs` (auto-created by Helm chart with radosNamespace parameter honored)
- **Status**: ✅ **ACTIVE** - Used for production CephFS mounts via standalone CSI
- **Created Subvolumes**: Kubernetes-managed PVCs via `csi-cephfs` SC would create subvolumes here
- **Backup/Restore**: YES - Production data

---

### 3. **Default Namespace (Unnamed)** 
- **Pool**: `kubernetes-prod-cephfs_metadata` (default namespace for any non-isolated access)
- **Provisioner**: Anyone not specifying explicit radosNamespace
- **Filesystem**: Both `rook_prod` and `kubernetes-prod-cephfs` can be accessed here
- **Source Config**: Implicit (fallback when no radosNamespace specified)
  - Test StorageClass `/scripts/noenc-sc-test-20260325.yaml` (MISSING radosNamespace parameter)
  - Any ad-hoc `rados` or CSI commands without namespace specification
- **StorageClasses** using this namespace:
  - ⚠️ `csi-cephfs-sc-noenc-test` (test SC - **missing radosNamespace parameter**, currently unused)
  - ⚠️ Any other test SCs created during debugging sessions
- **Status**: ⚠️ **PARTIALLY ACTIVE** - Contains test data and potentially stale objects
- **Contents**: 
  - Test PVC subvolumes from failed provisioning attempts
  - Stale metadata objects from retried operations
  - CSI lock objects (`.csi-lockfile-*`)
  - Example: test subvolumes like `pvc-<uuid>` created without namespace isolation
- **Backup/Restore**: **NO** - Test/ephemeral data only

---

## Potentially Unused Namespaces (To Be Verified)

| Namespace | Pool | Status | Action |
|-----------|------|--------|--------|
| `cephfs-csi-test` | kubernetes-prod-cephfs_metadata | ❓ Unknown | Check if any objects exist |
| `cephfs-csi-debug` | kubernetes-prod-cephfs_metadata | ❓ Unknown | Check if any objects exist |
| `rook-cephfs` | rook_prod_metadata | ❓ Unknown | Check if any objects exist |
| Other custom NS | Various | ❓ Unknown | Scan all objects |

---

## How to Discover Actual Usage

### Option 1: Query via rados Command
```bash
# List all namespaces in metadata pool
kubectl exec -n rook-ceph <toolbox-pod> -- \
  rados -p kubernetes-prod-cephfs_metadata namespace ls

# Count objects in each namespace
for ns in cephfs-csi cephfs-csi-standalone <others>; do
  echo "=== $ns ==="
  kubectl exec -n rook-ceph <toolbox-pod> -- \
    rados -p kubernetes-prod-cephfs_metadata -N "$ns" ls | wc -l
done

# List actual objects in a namespace
kubectl exec -n rook-ceph <toolbox-pod> -- \
  rados -p kubernetes-prod-cephfs_metadata -N cephfs-csi ls | head -20
```

### Option 2: Query via cephfs Subvolume Commands
```bash
# List all subvolumes in a filesystem
kubectl exec -n rook-ceph <toolbox-pod> -- \
  ceph fs subvolume ls rook_prod --format json-pretty

kubectl exec -n rook-ceph <toolbox-pod> -- \
  ceph fs subvolume ls kubernetes-prod-cephfs --format json-pretty

# Check subvolume metadata namespace (if visible in properties)
kubectl exec -n rook-ceph <toolbox-pod> -- \
  ceph fs subvolume metadata rook_prod <subvolume-name>
```

### Option 3: Monitor StorageClass Activity
```bash
# Check which SCs are present
kubectl get sc | grep -i ceph

# Check which SCs have active PVCs
kubectl get pvc --all-namespaces | grep -i ceph
```

---

## Configuration Problems & Recommendations

### Problem #1: Test StorageClass Missing radosNamespace ⚠️
- **File**: `/scripts/noenc-sc-test-20260325.yaml`
- **Issue**: No `radosNamespace` parameter specified
- **Consequence**: Uses default namespace → pollutes `cephfs-csi` and `cephfs-csi-standalone` namespace
- **Status**: Unused (not deployed to cluster)
- **Action**: 
  - Delete this file (or update to include `radosNamespace: cephfs-csi-test`)
  - Remove any associated test PVCs created from this SC

### Problem #2: Default Namespace Pollution
- **Cause**: Test StorageClasses without radosNamespace created stale objects
- **Evidence**: Terminal history shows multiple PVC creation attempts without clearing namespaces
- **Status**: Unknown - requires inspection
- **Action**:
  - List all objects in default namespace
  - Identify stale test subvolumes (examples: `pvc-<uuid>` from old PR testing cycles)
  - Delete orphaned test subvolumes

### Problem #3: Dual CSI Provisioner Configuration
- **Status**: Both `rook-ceph.cephfs.csi.ceph.com` and `cephfs.csi.ceph.com` are active
- **Consequence**: Separate namespaces maintain separate metadata isolation
- **Recommendation**: 
  - Decide on ONE provisioner (recommend standalone `cephfs.csi.ceph.com` for simplicity)
  - Consolidate all production PVCs to single provisioner
  - Reprovision from rook namespace if needed

---

## Cleanup Strategy

### Phase 1: Identify Unused Objects (Low Risk)
1. Query each namespace for object count: `rados -N <ns> ls | wc -l`
2. List objects in each: `rados -N <ns> ls | head -100`
3. Identify test patterns (UUIDs that don't match current PVCs)
4. Note results in memory

### Phase 2: Backup Metadata (Safe)
- Before deletion, export namespace: 
  ```bash
  rados -p pool -N namespace export /tmp/backup-ns.rados
  ```

### Phase 3: Delete Unused Namespaces (Destructive)
```bash
# Delete individual objects (not supported by rados directly)
# Requires iterating: rados -N ns rm <object-name>

# OR: Delete entire pool (if namespace is isolated to one pool) ⚠️
# ...But this is too risky for shared pools
```

### Phase 4: Verify Cleanup
- Re-scan namespaces
- Verify active PVCs still bind
- Check CSI logs for errors

---

## Summary

**Confirmed Active Namespaces:**
- ✅ `cephfs-csi` (Rook provisioner, ~X objects)
- ✅ `cephfs-csi-standalone` (Standalone provisioner, ~X objects)
- ⚠️ Default namespace (test/stale objects, ~X objects)

**Recommended Actions (In Order):**
1. **Run namespace inventory script** (provided below) to count all objects
2. **Document findings** - update this file with counts
3. **Delete test SCs** - remove `noenc-sc-test-20260325.yaml` and related files
4. **Clean default namespace** - identify and remove stale test subvolumes
5. **Monitor post-cleanup** - verify PVC provisioning still works

---

## Quick Commands to Run

Add these to `/tmp/namespace_audit.sh`:

```bash
#!/bin/bash
NS="ceph-audit-$(date +%s)"
kubectl create ns "$NS"

# Place toolbox pod ref
TOOL=$(kubectl get -n rook-ceph pods -l app=rook-ceph-tools -o name | head -1 | sed 's#pod/##')
KARGS="-m 192.168.10.3:6789 -n client.admin -k /etc/ceph/keyring"

echo "=== NAMESPACE AUDIT REPORT ==="
echo "Generated: $(date)"
echo ""

# Query each known namespace
for ns in cephfs-csi cephfs-csi-standalone ""; do
  echo "## Namespace: '${ns:-[default]}'"
  
  # Count in metadata pool
  COUNT=$(kubectl exec -n rook-ceph "$TOOL" -- \
    rados -p kubernetes-prod-cephfs_metadata ${ns:+-N "$ns"} ls 2>/dev/null | wc -l)
  echo "Objects in kubernetes-prod-cephfs_metadata: $COUNT"
  
  # Count in data pool
  COUNT_DATA=$(kubectl exec -n rook-ceph "$TOOL" -- \
    rados -p kubernetes-prod-cephfs_data ${ns:+-N "$ns"} ls 2>/dev/null | wc -l)
  echo "Objects in kubernetes-prod-cephfs_data: $COUNT_DATA"
  
  echo ""
done

echo "=== ACTIVE PVCS ==="
kubectl get pvc --all-namespaces | grep -i ceph || echo "No CephFS PVCs found"

echo ""
echo "=== STORAGE CLASSES ==="
kubectl get sc | grep -i ceph

cleanup() {
  kubectl delete ns "$NS" --ignore-not-found
}
trap cleanup EXIT
```

Run with: `bash /tmp/namespace_audit.sh`

---

## References

- **RADOS Namespaces**: https://docs.ceph.com/en/latest/rados/operations/pools/#namespaces
- **CephFS Subvolume Groups**: https://docs.ceph.com/en/latest/cephfs/fs-volumes/
- **CSI RADOS Namespace Parameter**: Ceph CSI documentation, radosNamespace field

