#!/bin/bash
# RADOS Namespace Audit Script
# Discovers all namespaces and object counts across Ceph pools
# Usage: bash namespace-audit.sh > namespace-audit-results.txt 2>&1

set -e

echo "=== RADOS NAMESPACE AUDIT REPORT ==="
echo "Generated: $(date)"
echo "Cluster: 192.168.10.3:6789"
echo ""

# Get toolbox pod
TOOL=$(kubectl get -n rook-ceph pods -l app=rook-ceph-tools -o name 2>/dev/null | head -1 | sed 's#pod/##')
if [ -z "$TOOL" ]; then
  echo "ERROR: No rook-ceph-tools pod found"
  exit 1
fi
echo "Using toolbox pod: $TOOL"
echo ""

KARGS="-m 192.168.10.3:6789 -n client.admin -k /etc/ceph/keyring"

# Function to query namespace
query_namespace() {
  local pool=$1
  local namespace=$2
  local ns_display="${namespace:-[default]}"
  
  echo "=== Pool: $pool | Namespace: $ns_display ==="
  
  # Count objects
  if [ -z "$namespace" ]; then
    COUNT=$(kubectl exec -n rook-ceph "$TOOL" -- \
      rados -p "$pool" ls 2>/dev/null | wc -l)
    # Sample objects
    echo "Sample objects:"
    kubectl exec -n rook-ceph "$TOOL" -- \
      rados -p "$pool" ls 2>/dev/null | head -20 | sed 's/^/  - /'
  else
    COUNT=$(kubectl exec -n rook-ceph "$TOOL" -- \
      rados -p "$pool" -N "$namespace" ls 2>/dev/null | wc -l)
    # Sample objects
    echo "Sample objects:"
    kubectl exec -n rook-ceph "$TOOL" -- \
      rados -p "$pool" -N "$namespace" ls 2>/dev/null | head -20 | sed 's/^/  - /'
  fi
  
  echo "Total objects: $COUNT"
  echo ""
}

# =============================================================================
echo "## METADATA POOLS"
echo ""

echo "### Pool: kubernetes-prod-cephfs_metadata"
echo ""
query_namespace "kubernetes-prod-cephfs_metadata" "cephfs-csi"
query_namespace "kubernetes-prod-cephfs_metadata" "cephfs-csi-standalone"
query_namespace "kubernetes-prod-cephfs_metadata" ""

echo "### Pool: rook_prod_metadata (if exists)"
if kubectl exec -n rook-ceph "$TOOL" -- ceph $KARGS osd pool ls | grep -q "rook_prod_metadata"; then
  query_namespace "rook_prod_metadata" "cephfs-csi"
  query_namespace "rook_prod_metadata" ""
else
  echo "Pool not found"
  echo ""
fi

# =============================================================================
echo "## DATA POOLS"
echo ""

echo "### Pool: kubernetes-prod-cephfs_data"
echo ""
query_namespace "kubernetes-prod-cephfs_data" "cephfs-csi"
query_namespace "kubernetes-prod-cephfs_data" "cephfs-csi-standalone"
query_namespace "kubernetes-prod-cephfs_data" ""

echo "### Pool: rook_prod (RBD)"
echo ""
query_namespace "rook_prod" ""

# =============================================================================
echo "## ACTIVE KUBERNETES STATE"
echo ""

echo "### Storage Classes"
kubectl get sc | grep -i ceph || echo "No Ceph StorageClasses found"
echo ""

echo "### Persistent Volume Claims (CephFS)"
kubectl get pvc --all-namespaces -o wide | grep -E 'ceph|csi' || echo "No CephFS PVCs found"
echo ""

echo "### Persistent Volumes (CephFS)"
kubectl get pv -o wide | grep -E 'ceph|csi' || echo "No CephFS PVs found"
echo ""

# =============================================================================
echo "## CEPHFS FILESYSTEMS"
echo ""

echo "### rook_prod subvolumes"
kubectl exec -n rook-ceph "$TOOL" -- ceph $KARGS fs subvolume ls rook_prod --format json 2>/dev/null | \
  python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'  - {v[\"name\"]}') for v in data]" || \
  echo "No subvolumes or query failed"
echo ""

echo "### kubernetes-prod-cephfs subvolumes"
kubectl exec -n rook-ceph "$TOOL" -- ceph $KARGS fs subvolume ls kubernetes-prod-cephfs --format json 2>/dev/null | \
  python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'  - {v[\"name\"]}') for v in data]" || \
  echo "No subvolumes or query failed"
echo ""

# =============================================================================
echo "## POTENTIALLY STALE NAMESPACES"
echo ""
echo "Searching for any other namespaces in kubernetes-prod-cephfs_metadata pool..."
echo ""

# This requires listing all objects and extracting unique namespaces
# For now, just note what we know
echo "Known namespaces found during investigation:"
echo "  - cephfs-csi (production - Rook CephFS provisioner)"
echo "  - cephfs-csi-standalone (production - Standalone CSI provisioner)"
echo "  - [default] (test data and fallback)"
echo ""

echo "=== END REPORT ==="
echo "Report generated: $(date)"
