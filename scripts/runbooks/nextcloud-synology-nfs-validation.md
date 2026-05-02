# Nextcloud Synology NFS Validation Commands

These commands are placeholders and validation helpers. Do not hardcode credentials in shell history, scripts, or Git.

## Kubernetes

```bash
kubectl get pv nextcloud-data-synology-nfs
kubectl get pvc -n nextcloud nextcloud-data
kubectl describe pv nextcloud-data-synology-nfs
kubectl describe pvc -n nextcloud nextcloud-data
kubectl get pods -n nextcloud
kubectl exec -n nextcloud <nextcloud-pod> -- df -h
kubectl exec -n nextcloud <nextcloud-pod> -- mount | grep nfs
kubectl exec -n nextcloud <nextcloud-pod> -- touch /var/www/html/data/.nfs-write-test
```

Temporary debug pod example:

```bash
kubectl run -n nextcloud nextcloud-nfs-write-test \
  --image=busybox:1.36 \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"busybox","image":"busybox:1.36","command":["sh","-c","mount | grep /data && date > /data/.nfs-write-test && ls -la /data/.nfs-write-test && sleep 3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"nextcloud-data"}}]}}'

kubectl logs -n nextcloud nextcloud-nfs-write-test
kubectl delete pod -n nextcloud nextcloud-nfs-write-test
```

## Nextcloud

Run inside the Nextcloud container or through the chart-supported maintenance command path:

```bash
php occ status
php occ maintenance:mode --on
php occ maintenance:mode --off
php occ files:scan --all
php occ files:cleanup
php occ maintenance:repair
```

## Database

Detect and use the active database backend. Do not hardcode credentials.

PostgreSQL placeholder:

```bash
PGHOST=<postgres-host> PGDATABASE=<database> PGUSER=<user> pg_dump --format=custom --file=nextcloud-pre-migration.dump
```

CNPG pod placeholder:

```bash
kubectl exec -n <namespace> <postgres-pod> -- pg_dump --format=custom --dbname=nextcloud --file=/tmp/nextcloud-pre-migration.dump
kubectl cp -n <namespace> <postgres-pod>:/tmp/nextcloud-pre-migration.dump ./nextcloud-pre-migration.dump
```

MySQL/MariaDB placeholder:

```bash
mysqldump --single-transaction --routines --triggers --databases <database> > nextcloud-pre-migration.sql
```

## AWS

Inventory the bucket. These commands are for backup/inventory only, not for migrating the bucket directly into the new Nextcloud data directory.

```bash
aws s3 ls s3://<nextcloud-bucket> --recursive --summarize
aws s3api list-objects-v2 --bucket <nextcloud-bucket> --query 'KeyCount'
```

Backup copy placeholder:

```bash
aws s3 sync s3://<nextcloud-bucket> s3://<protected-backup-bucket-or-prefix>/nextcloud-primary-objectstore-backup/
```

Do not use `aws s3 sync s3://<nextcloud-bucket> <new-data-directory>` as the Nextcloud migration.
