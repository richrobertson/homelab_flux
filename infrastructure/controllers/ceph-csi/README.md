# Ceph CSI

Controller resources for Ceph CSI integration.

## Purpose

- Enables dynamic provisioning and attachment of Ceph-backed volumes.
- Defines storage interface behavior required by stateful workloads.

## In this folder

- Helm/chart or kustomize resources for Ceph CSI controller/node components.

## Notes

- Keep CSI and storage-class compatibility aligned with Ceph/Rook versions.


## Parent/Siblings

- Parent: [Controllers](../README.md)
- Siblings: [General Controllers](../general/README.md); [Intel Device Plugin Operator](../intel-device-plugin-operator/README.md); [Istio](../istio/README.md); [Kube Prometheus Stack](../kube-prometheus-stack/README.md); [Rook Ceph](../rook-ceph/README.md); [Storage Classes](../storage-classes/README.md); [Synology iSCSI CSI](../synology-iscsi-csi/README.md).
