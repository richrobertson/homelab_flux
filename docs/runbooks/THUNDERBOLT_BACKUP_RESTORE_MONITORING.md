# Thunderbolt Backup/Restore Monitoring

This runbook tracks the Proxmox Backup Server client path that is published through the Thunderbolt ring.

## Current Path

- Proxmox PBS storage definitions point at `10.0.0.87:8007`.
- `10.0.0.87/32` is advertised locally on `pve5`.
- `pve5` proxies `10.0.0.87:8007` to the Scooter-hosted PBS VM at `192.168.1.217:8007`.
- The PBS datastore remains on Scooter/Synology hard drives.

## Grafana

- Dashboard: `Proxmox Thunderbolt Service Traffic`
- Backup/restore panels:
  - `Backup/Restore Route`
  - `Backup Failures 24h`
  - `Last Successful Backup Age`
  - `Restore Failures 24h`
  - `Backup/Restore Tasks`
  - `Backup Storage Routes`

## Alerts

- `ProxmoxBackupStorageNotUsingThunderbolt`
  - Fires when any configured PBS storage does not route through the Thunderbolt service path.
- `ProxmoxBackupTasksFailing`
  - Fires when a Proxmox `vzdump` task has failed in the last 24 hours.
- `ProxmoxBackupSuccessStale`
  - Fires when a Proxmox node has not reported a successful backup in more than 36 hours.

## Verification

```sh
kubectl --context admin@prod -n monitoring run prom-query-pbs-tb --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- sh -c 'curl -fsS --data-urlencode "query=min(proxmox_backup_storage_route_up{job=\"proxmox-node-exporter\",expected_network=\"thunderbolt\"})" http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query'
kubectl --context admin@prod -n monitoring run prom-query-pbs-tasks --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- sh -c 'curl -fsS --data-urlencode "query=proxmox_backup_restore_tasks_24h{job=\"proxmox-node-exporter\"}" http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query'
```

Expected healthy state:

- `min(proxmox_backup_storage_route_up{expected_network="thunderbolt"}) == 1`
- `sum(proxmox_backup_restore_tasks_24h{operation="backup",status="failed"}) == 0`
- `time() - max(proxmox_backup_restore_last_task_timestamp_seconds{operation="backup",status="ok"}) < 129600`
