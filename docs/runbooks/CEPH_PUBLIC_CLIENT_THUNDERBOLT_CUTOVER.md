# Ceph Public/Client Thunderbolt Cutover

This runbook stages the Ceph public/client network move from `192.168.10.0/24` to the Thunderbolt ring `10.0.0.0/24`.

## Current State

- Ceph backend replication/recovery traffic is already on `cluster_network = 10.0.0.0/24`.
- OSD backend addresses should report `10.0.0.83-85` in the `proxmox_ceph_osd_address_on_thunderbolt{address_role="back"}` metric.
- Ceph public/client traffic remains on `public_network = 192.168.10.0/24`.
- Kubernetes client manifests still reference `192.168.10.3` and must not be reconciled to `10.0.0.x` until Ceph monitors are listening there.

## Client References To Update

- `infrastructure/configs/rook-external-cluster.yaml`
  - `csi-cluster-config-json` monitor list
  - `rook-ceph-mon-endpoints` data
  - `rook-ceph-mon-endpoints` endpoint IPs
  - `rgw-endpoint`
- `infrastructure/controllers/ceph-csi/ceph-filesystem.yaml`
  - `monitors`
- `infrastructure/configs/ceph-servicemonitor.yaml`
  - external mgr metrics endpoint IPs

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

3. Move Ceph monitors and public OSD front addresses to `10.0.0.83-85` during a maintenance window. Do not update Kubernetes client references before this step succeeds.

4. Update the GitOps client references listed above from `192.168.10.3-5` to:

   ```text
   pve3 10.0.0.83
   pve4 10.0.0.84
   pve5 10.0.0.85
   ```

5. Reconcile the production Flux source and kustomization:

   ```sh
   flux --context admin@prod reconcile source git flux-system -n flux-system
   flux --context admin@prod reconcile kustomization infrastructure -n flux-system
   ```

6. Restart Ceph CSI/Rook consumers only if they do not pick up the new monitor endpoints:

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
