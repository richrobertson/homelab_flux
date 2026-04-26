# Ceph Public/Client Thunderbolt Cutover

This runbook stages the Ceph public/client network move from `192.168.10.0/24` to the Thunderbolt ring `10.0.0.0/24`.

## Current State

- Ceph backend replication/recovery traffic is already on `cluster_network = 10.0.0.0/24`.
- OSD backend addresses should report `10.0.0.83-85` in the `proxmox_ceph_osd_address_on_thunderbolt{address_role="back"}` metric.
- Ceph public/client traffic remains on `public_network = 192.168.10.0/24`.
- Kubernetes client manifests still reference `192.168.10.3` and must not be reconciled to `10.0.0.x` until Ceph monitors are listening there.

## Mapped Client References

Last verified: 2026-04-25.

### Proxmox Clients

- `/etc/pve/storage.cfg` currently has active Ceph clients for:
  - `rbd: p0` -> pool `p0`
  - `rbd: rook_prod` -> pool `rook_prod`
  - `cephfs: kubernetes-prod-cephfs` -> filesystem `kubernetes-prod-cephfs`
- Proxmox reads monitor addresses from `/etc/pve/ceph.conf`; update this only after monitors and OSD front addresses are listening on `10.0.0.83-85`.

### Kubernetes Clients

- Active production PV count by storage class:
  - `ceph-block`: 21 PVs
  - `ceph-block-p0`: 1 PV
  - `csi-cephfs-sc`: 53 PVs
- Active production PVC count by namespace and storage class:
  - `default/ceph-block`: 20 PVCs
  - `default/csi-cephfs-sc`: 48 PVCs
  - `monitoring/ceph-block`: 1 PVC
  - `monitoring/ceph-block-p0`: 1 PVC
- Rook external CSI live config currently advertises `192.168.10.4:6789`, `192.168.10.5:6789`, and `192.168.10.3:6789`.
- Standalone CephFS CSI live config currently advertises `192.168.10.3:6789`.
- Ceph external mgr metrics ServiceMonitor currently scrapes `192.168.10.3-5:9283`.

## GitOps References To Update

- `infrastructure/configs/rook-external-cluster.yaml`
  - `csi-cluster-config-json` monitor list
  - `rook-ceph-mon-endpoints` data
  - `rook-ceph-mon-endpoints` endpoint IPs
  - `rgw-endpoint`
  - `CephObjectStore.spec.gateway.externalRgwEndpoints`
- `infrastructure/controllers/ceph-csi/ceph-filesystem.yaml`
  - `monitors`
- `infrastructure/configs/ceph-servicemonitor.yaml`
  - external mgr metrics endpoint IPs
- Utility scripts and stale docs that hard-code `192.168.10.3:6789` should be updated after the client cutover is proven:
  - `scripts/namespace-audit.sh`
  - `scripts/RADOS_NAMESPACE_INVENTORY.md`

## Staged Cutover

1. Confirm the ring and Ceph backend are healthy:

   ```sh
   ceph -s
   ceph health detail
   ceph osd dump | grep -E 'cluster_network|public_network'
   ```

2. Confirm every Kubernetes node can reach the future monitor IPs:

   ```sh
   kubectl --context admin@prod get nodes -o wide
   kubectl --context admin@prod -n default run ceph-public-probe --rm -it --restart=Never --image=busybox:1.36 -- sh
   nc -vz 10.0.0.83 3300
   nc -vz 10.0.0.84 3300
   nc -vz 10.0.0.85 3300
   ```

3. Confirm the mapped Kubernetes clients above have not changed since this runbook was last verified:

   ```sh
   kubectl --context admin@prod get pv -o json | jq -r '[.items[] | select(.spec.storageClassName|test("ceph")) | .spec.storageClassName] | group_by(.)[] | "\(.[0])\t\(length)"'
   kubectl --context admin@prod get pvc -A -o json | jq -r '[.items[] | select((.spec.storageClassName // "")|test("ceph")) | {ns:.metadata.namespace, sc:.spec.storageClassName}] | group_by(.ns, .sc)[] | "\(.[0].ns)\t\(.[0].sc)\t\(length)"'
   rg -n '192\.168\.10\.[345]|10\.0\.0\.8[345]' infrastructure apps docs scripts -S
   ```

4. Move Ceph monitors and public OSD front addresses to `10.0.0.83-85` during a maintenance window. Do not update Kubernetes client references before this step succeeds.

5. Update the GitOps client references listed above from `192.168.10.3-5` to:

   ```text
   pve3 10.0.0.83
   pve4 10.0.0.84
   pve5 10.0.0.85
   ```

6. Reconcile the production Flux source and kustomization:

   ```sh
   flux --context admin@prod reconcile source git flux-system -n flux-system
   flux --context admin@prod reconcile kustomization infrastructure -n flux-system
   ```

7. Restart Ceph CSI/Rook consumers only if they do not pick up the new monitor endpoints:

   ```sh
   kubectl --context admin@prod -n ceph-csi rollout restart daemonset/ceph-csi-cephfs-nodeplugin
   kubectl --context admin@prod -n rook-ceph rollout restart daemonset/rook-ceph.rbd.csi.ceph.com-nodeplugin
   kubectl --context admin@prod -n rook-ceph rollout restart daemonset/rook-ceph.cephfs.csi.ceph.com-nodeplugin
   ```

## Rollback

1. Revert monitor/public addresses to `192.168.10.3-5`.
2. Revert the GitOps client reference commit.
3. Reconcile Flux.
4. Verify existing PVC mounts and new volume provisioning.

## Monitoring

- `Proxmox Thunderbolt Service Traffic` tracks backup route placement, Ceph backend placement, and public/client cutover status.
- `ProxmoxCephPublicNetworkCutoverPending` remains informational until the public network is intentionally moved.
- `ProxmoxCephClusterNetworkNotUsingThunderbolt` and `ProxmoxCephOSDBackendNotUsingThunderbolt` should stay quiet after the backend migration.
