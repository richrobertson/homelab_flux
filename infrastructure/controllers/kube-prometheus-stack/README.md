# Kube Prometheus Stack

Controller resources for metrics, alerting, and dashboarding.

## Purpose

- Deploys Prometheus/Grafana/Alertmanager stack components.
- Provides core observability foundations for cluster and app monitoring.

## In this folder

- Helm source/release manifests and observability-specific controller settings.

## Notes

- Coordinate with alert rules and dashboards in `infrastructure/configs`.


## Parent/Siblings

- Parent: [Controllers](../README.md)
- Siblings: [Ceph CSI](../ceph-csi/README.md); [General Controllers](../general/README.md); [Intel Device Plugin Operator](../intel-device-plugin-operator/README.md); [Istio](../istio/README.md); [Rook Ceph](../rook-ceph/README.md); [Storage Classes](../storage-classes/README.md); [Synology iSCSI CSI](../synology-iscsi-csi/README.md).
