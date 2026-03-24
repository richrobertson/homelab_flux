# Infrastructure Controllers

`infrastructure/controllers/` manages long-running Kubernetes operators and core control-plane extensions.

## Purpose

- Installs/maintains controller stacks required for storage, networking, observability, and hardware integration.
- Centralizes controller lifecycle (chart source, chart version, values, dependencies).
- Provides shared platform behavior used by application workloads.

## Current controller subsets

- `ceph-csi`: Ceph CSI integration for dynamic storage provisioning.
- `general`: shared generic controller resources and cross-cutting defaults.
- `intel-device-plugin-operator`: Intel device plugin operator management.
- `istio`: service mesh control-plane resources and related APIs.
- `kube-prometheus-stack`: metrics, alerting, and visualization stack.
- `rook-ceph`: Ceph storage operator lifecycle.
- `storage-classes`: default and specialized storage class definitions.
- `synology-iscsi-csi`: Synology iSCSI CSI storage integration.

## Change safety

- Prefer staged upgrades for controller charts and CRDs.
- Validate downstream compatibility (storage classes, CRDs, APIs) before promotion.
- Keep rollback paths clear by using focused commits.

## See also

- [Infrastructure overview](../README.md)
- [Ceph CSI](ceph-csi/README.md)
- [General controllers](general/README.md)
- [Intel Device Plugin Operator](intel-device-plugin-operator/README.md)
- [Istio controllers](istio/README.md)
- [Kube Prometheus Stack](kube-prometheus-stack/README.md)
- [Rook Ceph](rook-ceph/README.md)
- [Storage Classes](storage-classes/README.md)
- [Synology iSCSI CSI](synology-iscsi-csi/README.md)
