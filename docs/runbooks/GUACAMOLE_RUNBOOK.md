# Apache Guacamole Runbook

## Purpose

Apache Guacamole provides browser-based access to RDP, VNC, and SSH targets without exposing those protocols directly outside the cluster. This deployment is a remote desktop gateway, not a Nextcloud component.

## Architecture

```text
browser
  -> HTTPS Gateway API / Istio
  -> guacamole web pod
  -> guacd ClusterIP service
  -> internal RDP/VNC/SSH targets

guacamole web pod
  -> Authelia OIDC issuer
  -> Guacamole PostgreSQL database

Authelia
  -> LDAP-backed identity source
```

Guacamole authenticates users through Authelia OpenID Connect. Authelia continues to use LDAP for user identity. Guacamole PostgreSQL remains the source of truth for connection definitions, permissions, and connection metadata.

## Flux Deployment

- Shared manifests: `apps/base/guacamole`
- Staging overlay: `apps/staging/guacamole`
- Production overlay: `apps/prod/guacamole`
- Staging URL: `https://rdp.staging.myrobertson.net`
- Production URL: `https://rdp.myrobertson.com`

Reconcile:

```sh
flux reconcile kustomization apps -n flux-system
flux get kustomizations -A
```

## Validation

```sh
kustomize build apps/base/guacamole
kustomize build apps/staging
kustomize build apps/prod
./scripts/validate.sh

kubectl -n guacamole get pods,svc,pvc
kubectl -n guacamole get cluster,scheduledbackup
kubectl -n guacamole logs deploy/guacamole
kubectl -n guacamole logs deploy/guacd
kubectl -n guacamole logs job/guacamole-postgres-init
kubectl -n authelia get pods,svc
```

Check OIDC discovery from the Guacamole pod:

```sh
kubectl -n guacamole exec deploy/guacamole -- \
  sh -c 'curl -fsS https://auth.myrobertson.com/.well-known/openid-configuration'
```

For staging, use `https://auth.staging.myrobertson.net/.well-known/openid-configuration`.

## Database Bootstrap

The `guacamole-postgres-init` job renders the official Guacamole PostgreSQL schema from the pinned `guacamole/guacamole:1.6.0` image and applies it to the CNPG database. The job is idempotent enough for GitOps reconciliation: if `public.guacamole_user` exists, it skips.

The upstream schema creates the initial local `guacadmin` account. Use that account only for first setup, rotate its password immediately, grant permissions to Authelia/OIDC users or groups, and then disable or tightly protect local database login.

## SSO

Authelia has environment-specific OIDC clients:

- Staging: `guacamole_staging`, redirect URI `https://rdp.staging.myrobertson.net`, currently `one_factor` until Authelia MFA enrollment is complete
- Production: `guacamole`, redirect URI `https://rdp.myrobertson.com`, currently `one_factor` until Authelia MFA enrollment is complete

Guacamole uses:

- `OPENID_SCOPE=openid profile groups email`
- `OPENID_USERNAME_CLAIM_TYPE=preferred_username`
- `OPENID_GROUPS_CLAIM_TYPE=groups`
- `EXTENSION_PRIORITY=openid,postgresql,ban`

Staging and production keep their public issuers and browser authorization endpoints on the Authelia hostnames, but fetch JWKS from `http://authelia.default.svc.cluster.local/jwks.json` so the Guacamole JVM does not need to trust the public TLS chain.

Guacamole’s OpenID extension authenticates the browser session only. PostgreSQL/database auth must remain enabled so Guacamole can store and authorize connections.

## Secret Rotation

The current Guacamole OIDC clients are public clients because Guacamole’s OpenID extension uses implicit flow. No Guacamole OIDC client secret is committed.

If a future Guacamole release supports an authorization-code flow with a confidential client, store the client secret in the repo’s existing secret-management path and reference it from both Authelia and Guacamole through Vault Secrets Operator. Do not commit plaintext secrets.

## Adding Connections Safely

- Add RDP/VNC/SSH connections inside the Guacamole admin UI.
- Prefer hostnames that resolve only on trusted internal networks.
- Do not expose raw RDP, VNC, SSH, guacd, or PostgreSQL with LoadBalancers or Ingress/HTTPRoutes.
- Use Guacamole groups tied to Authelia `groups` claims where possible.
- Avoid sharing reusable privileged remote credentials.

## Backup and Restore

Production stores the Guacamole database on a `ceph-block` CloudNativePG PVC.

CNPG object-store backups for `guacamole-cnpg` are deferred until the Vault Kubernetes role allows the operator to sync `cnpg-backup-s3` into the `guacamole` namespace. Do not commit Backblaze credentials directly to Git.

Backup checks:

```sh
kubectl -n guacamole describe cluster guacamole-cnpg
kubectl -n guacamole get pvc
```

Until object-store backups are enabled, restore depends on restoring the `ceph-block` PVC from the storage platform. After CNPG object-store backups are enabled, use the normal CNPG restore workflow, then redeploy the Guacamole web and guacd deployments against the restored database.

## Theme Park

Theme Park has a Guacamole dark theme, but its documented deployment model requires proxy-side CSS injection. This repo exposes apps with Istio Gateway API, and the active gateway path does not provide a safe response-body injection mechanism.

Theme Park is therefore deferred. A disabled NGINX-style example lives in `apps/base/guacamole/examples/theme-park/`. Enable dark mode only after adding a compatible proxy layer, and keep the change easy to remove.

References:

- Apache Guacamole Docker deployment: `https://guacamole.apache.org/doc/gug/guacamole-docker.html`
- Apache Guacamole PostgreSQL setup: `https://guacamole.apache.org/doc/gug/postgresql-auth.html`
- Apache Guacamole OpenID Connect setup: `https://guacamole.apache.org/doc/gug/openid-auth.html`
- Theme Park Guacamole/dark docs: `https://docs.theme-park.dev/themes/guacamole/` and `https://docs.theme-park.dev/theme-options/dark/`

## Security Notes

- Production is publicly reachable at `https://rdp.myrobertson.com`; keep Authelia MFA policy enabled.
- Staging is private at `https://rdp.staging.myrobertson.net`.
- guacd and PostgreSQL are ClusterIP-only.
- NetworkPolicies deny default ingress/egress and allow only the Guacamole web, guacd, PostgreSQL, DNS, gateway, and OIDC paths required for operation.
- Do not commit admin credentials, remote desktop credentials, database passwords, or OIDC secrets.

## Rollback

1. Remove or suspend the `guacamole` overlay from `apps/staging/kustomization.yaml` or `apps/prod/kustomization.yaml`.
2. Reconcile the `apps` Flux Kustomization.
3. Keep the CNPG PVC and backups until you intentionally retire the deployment.
4. Remove the Authelia OIDC client only after the route and app are no longer in use.
