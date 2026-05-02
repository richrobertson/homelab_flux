# Nextcloud Synology NFS Storage Target

This Kustomize base provisions the future filesystem-backed Nextcloud data target:

- `PersistentVolume/nextcloud-data-synology-nfs`
- `PersistentVolumeClaim/nextcloud-data` in the `nextcloud` namespace
- `persistentVolumeReclaimPolicy: Retain`

The current production Nextcloud instance is not cut over by this base. It only creates the target storage so it can be validated in parallel.

Kubernetes mounts the Synology NFS export directly through the PV. The Ansible diagnostic mount in `homelab_ansible/roles/kubernetes_nfs_client` is only for validating node NFS client readiness and export reachability.

The NFS server uses the local-only Synology DNS name that the Kubernetes nodes
resolve through the PowerDNS recursor and AD DNS:

```yaml
nfs:
  server: scooter.myrobertson.net
  path: /volume1/nextcloud-data
```
