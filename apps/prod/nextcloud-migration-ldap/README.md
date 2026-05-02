# Nextcloud Production LDAP Migration Target

This app is the isolated production Strategy A target for validating a
filesystem-backed migration with production LDAP authentication before any
public route cutover.

- Namespace: `nextcloud`
- Release: `nextcloud-migration-ldap`
- Database: `nextcloud-migration-ldap-cnpg` on `ceph-block`
- App/config PVC: `nextcloud-migration-ldap-html` on `csi-cephfs-sc`
- User data PVC: `nextcloud-data`, mounted at subpath
  `strategy-a-prod-ldap-data`
- Server-side encryption: enabled with Nextcloud's `OC_DEFAULT_MODULE`
- Public route: `default/nextcloud` may reference this service during cutover;
  `reference-grant.yaml` allows that cross-namespace Gateway API backend ref.

Safety boundaries:

- Do not attach this instance to the source S3 primary objectstore.
- Do not expose this instance publicly before cutover validation.
- Do not copy raw S3 bucket objects into this data directory.
- Use this target instead of the local-user rehearsal target when validating
  production LDAP login behavior.

Manual secret mirrors required before first reconcile:

```bash
source ~/.bash_profile

kubectl --context admin@prod -n default get secret nextcloud-secret -o json | \
  jq 'del(.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields,.metadata.annotations,.metadata.ownerReferences)
      | .metadata.name = "nextcloud-migration-secret"
      | .metadata.namespace = "nextcloud"
      | .metadata.labels = {"app.kubernetes.io/name":"nextcloud-migration-ldap"}' | \
  kubectl --context admin@prod apply -f -

kubectl --context admin@prod -n default get secret nextcloud-ldap-secret -o json | \
  jq 'del(.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields,.metadata.annotations,.metadata.ownerReferences)
      | .metadata.namespace = "nextcloud"
      | .metadata.labels = {"app.kubernetes.io/name":"nextcloud-migration-ldap"}' | \
  kubectl --context admin@prod apply -f -
```

Validation:

```bash
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ encryption:status
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ ldap:test-config s01
kubectl --context admin@prod -n nextcloud exec deploy/nextcloud-migration-ldap -c nextcloud -- php occ config:system:get objectstore || true
```
