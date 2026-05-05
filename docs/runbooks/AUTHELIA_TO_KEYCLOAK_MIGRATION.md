# Authelia to Keycloak Migration

This runbook tracks the migration from Authelia to Keycloak while keeping Authelia live until each dependent application has been tested.

## Status

- Date started: 2026-05-04
- Current phase: steps 1, 2, and 3 staged; staging is now managed by Flux/GitOps.
- Keycloak target model: users stay in Microsoft Active Directory and Keycloak federates them over LDAPS.
- AD LDAPS source inherited from Authelia:
  - Connection URL: `ldaps://rhonda.myrobertson.net`
  - Users DN: `cn=Users,dc=myrobertson,dc=net`
  - Bind DN: `ldap@myrobertson.net`
- CA trust source: neutral Kubernetes Secret `ad-ldap-ca`, derived from the same AD CA material Authelia uses.
- Keycloak realm: `homelab`
- Keycloak public identity endpoints:
  - Prod: `https://sso.myrobertson.com`
  - Staging: `https://sso.staging.myrobertson.net`

## Step 1: Authelia Inventory

Authelia currently has two auth surfaces:

1. OIDC provider clients historically configured in `apps/prod/authelia/authelia-values.yaml` and `apps/staging/authelia/authelia-values.yaml`; active Kubernetes app OIDC clients are now upserted into Keycloak by `apps/base/keycloak/grafana-clients-job.yaml`.
2. Istio external authorization policies pointing at the `authelia` extension provider.

### OIDC Clients

| Environment | Client ID | Application | Redirect URIs | Notes |
| --- | --- | --- | --- | --- |
| prod | `mealie_prod` | Mealie | `https://mealie.myrobertson.com/login` | Confidential client, `client_secret_basic`, scopes `openid profile email groups`. |
| prod | `grafana_prod` | Grafana Prod | `https://grafana.prod.myrobertson.net/login/generic_oauth` | Confidential client, `client_secret_basic`, scopes `openid profile email groups`. |
| prod | `vikunja_prod` | Vikunja | `https://tasks.myrobertson.com/auth/openid/authelia` | Confidential client, `client_secret_basic`, scopes `openid profile email groups`. |
| prod | `nextcloud_prod` | Nextcloud | `https://cloud.myrobertson.com/apps/user_oidc/code`, `https://cloud.myrobertson.com/index.php/apps/user_oidc/code` | Confidential client, `client_secret_post`, custom `nextcloud_uid` claim. |
| prod | `guacamole_prod` | Apache Guacamole | `https://rdp.myrobertson.com` | Public implicit client. Replace with authorization-code + PKCE if Guacamole supports it cleanly. |
| prod | `proxmox_prod` | Proxmox VE cl0 | `https://cl0.myrobertson.net:8006`, `https://pve3.myrobertson.net:8006`, `https://pve4.myrobertson.net:8006`, `https://pve5.myrobertson.net:8006`, plus trailing-slash variants | Keycloak confidential client using the existing `pve_oidc` secret; emits `proxmox_groups`. Proxmox role mappings should grant access only to `proxAdmins`. |
| prod | `pbs_prod` | Proxmox Backup Server | `https://pbs.myrobertson.net:8007`, trailing slash variant | Keycloak confidential client using the existing `pbs_oidc` secret. PBS role mappings should grant access only to `proxAdmins`. |
| prod | `synology_scooter_prod` | Synology Scooter | `https://scooter.myrobertson.net:5011/webman/ssoclient/token_relay.html`, `https://scooter.myrobertson.net:5001/webman/ssoclient/token_relay.html` | Confidential client, `client_secret_post`. |
| prod | `synology_kermit_prod` | Synology Kermit | `https://kermit.myrobertson.com/webman/ssoclient/token_relay.html` | Confidential client, `client_secret_post`. |
| staging | `mealie_staging` | Mealie Staging | `https://mealie.staging.myrobertson.net/login` | Confidential client, `client_secret_basic`. |
| staging | `grafana_staging` | Grafana Staging | `https://grafana.staging.myrobertson.net/login/generic_oauth` | Confidential client, `client_secret_basic`. |
| staging | `vikunja_staging` | Vikunja Staging | `https://tasks.staging.myrobertson.net/auth/openid/authelia` | Confidential client, `client_secret_basic`. |
| staging | `nextcloud_staging` | Nextcloud Staging | `https://cloud.staging.myrobertson.net/apps/user_oidc/code`, `https://cloud.staging.myrobertson.net/index.php/apps/user_oidc/code` | Confidential client, `client_secret_post`. |
| staging | `guacamole_staging` | Apache Guacamole Staging | `https://rdp.staging.myrobertson.net` | Public implicit client. |

### Istio External Authorization Policies

These applications are protected by Gateway-scoped Istio `AuthorizationPolicy` resources using provider `authelia`.

| Environment | Host | Policy | Path exceptions |
| --- | --- | --- | --- |
| prod | `bazarr.myrobertson.com` | `apps/prod/bazarr/auth-policy.yaml` | `/api/*` |
| prod | `code.myrobertson.com` | `apps/prod/code-server/auth-policy.yaml` | none |
| prod | `lidarr.myrobertson.com` | `apps/prod/lidarr/auth-policy.yaml` | `/api/*` |
| prod | `webmail.myrobertson.com` | `apps/prod/mailu/auth-policy.yaml` | none |
| prod | `n8n.myrobertson.com` | `apps/prod/n8n/auth-policy.yaml` | `/webhook*`, `/webhook-test*`, `/webhook-waiting*` |
| prod | `cloud.myrobertson.com` | `apps/prod/nextcloud/auth-policy.yaml` | none |
| prod | `ntfy.myrobertson.com` | `apps/prod/ntfy/auth-policy.yaml` | none |
| prod | `seerr.myrobertson.com` | `apps/prod/overseerr/auth-policy.yaml` | `/api/v1/*` |
| prod | `prowlarr.myrobertson.com` | `apps/prod/prowlarr/auth-policy.yaml` | `/{*}/api`, `/{*}/download` |
| prod | `radarr.myrobertson.com` | `apps/prod/radarr/auth-policy.yaml` | `/api/*` |
| prod | `sonarr.myrobertson.com` | `apps/prod/sonarr/auth-policy.yaml` | `/api/*` |
| prod | `syncthing.myrobertson.com` | `apps/prod/syncthing/auth-policy.yaml` | none |
| staging | `bazarr.staging.myrobertson.net` | `apps/staging/bazarr/auth-policy.yaml` | `/api/*` |
| staging | `code.staging.myrobertson.net` | `apps/staging/code-server/auth-policy.yaml` | none |
| staging | `lidarr.staging.myrobertson.net` | `apps/staging/lidarr/auth-policy.yaml` | `/api/*` |
| staging | `n8n.staging.myrobertson.net` | `apps/staging/n8n/auth-policy.yaml` | `/webhook*`, `/webhook-test*`, `/webhook-waiting*` |
| staging | `cloud.staging.myrobertson.net` | `apps/staging/nextcloud/auth-policy.yaml` | Collabora WOPI paths |
| staging | `ntfy.staging.myrobertson.net` | `apps/staging/ntfy/auth-policy.yaml` | none |
| staging | `seerr.staging.myrobertson.net` | `apps/staging/overseerr/auth-policy.yaml` | `/api/v1/*` |
| staging | `prowlarr.staging.myrobertson.net` | `apps/staging/prowlarr/auth-policy.yaml` | `/{*}/api`, `/{*}/download` |
| staging | `radarr.staging.myrobertson.net` | `apps/staging/radarr/auth-policy.yaml` | `/api/*` |
| staging | `sonarr.staging.myrobertson.net` | `apps/staging/sonarr/auth-policy.yaml` | `/api/*` |
| staging | `syncthing.staging.myrobertson.net` | `apps/staging/syncthing/auth-policy.yaml` | none |

Apps in this table need a replacement enforcement layer because Keycloak is not an Authelia external-authz drop-in. Candidate patterns are native app OIDC where available, or an OIDC-aware proxy in front of apps that do not speak OIDC.

## Step 2: Keycloak Model

The initial Keycloak model is intentionally narrow:

- One realm named `homelab`.
- Microsoft Active Directory remains the user and password source.
- Keycloak federates AD users through LDAPS.
- Keycloak imports user records locally for Keycloak metadata, but password validation stays with AD.
- Keycloak bootstrap admin is local and should be treated as break-glass only.
- WebAuthn/passkeys are the target MFA method after AD username/password.
- AD group `proxAdmins` is pre-created in the realm model for Proxmox/PBS claim migration.
- OIDC application clients are migrated in small staging-first waves.
- First low-risk staging clients in the realm import: `mealie_staging` and `vikunja_staging`.

The base realm import lives in `apps/base/keycloak/realm-configmap.yaml`. It configures the AD user federation provider with:

- `vendor`: `ad`
- `connectionUrl`: `ldaps://rhonda.myrobertson.net`
- `usersDn`: `cn=Users,dc=myrobertson,dc=net`
- `bindDn`: `ldap@myrobertson.net`
- `bindCredential`: `${KC_LDAP_BIND_CREDENTIAL}`
- `useTruststoreSpi`: `ldapsOnly`
- `importEnabled`: `true`
- `editMode`: `READ_ONLY`

The first client scope added is `groups`, which emits group membership as a `groups` claim in ID tokens, access tokens, and userinfo responses.

## MFA and Passkey Model

WebAuthn/passkeys are the primary MFA method for the Keycloak migration. The initial model is password plus WebAuthn/passkey: AD still validates the user password over LDAPS, and Keycloak challenges for WebAuthn as the second factor.

TOTP remains enabled as a backup MFA method during and after migration so administrators have a recovery path if a passkey is lost or a device platform has an issue.

The local bootstrap admin is break-glass only. It should not be used for ordinary administration once AD `Domain Admins` access is confirmed.

Passkeys should be enrolled only against the permanent SSO hostnames:

- `https://sso.myrobertson.com`
- `https://sso.staging.myrobertson.net`

Do not enroll passkeys against `keycloak.myrobertson.com`, `keycloak.staging.myrobertson.net`, `keycloak.dev.myrobertson.net`, temporary test hostnames, or direct service URLs. WebAuthn binds credentials to the relying party/origin, so enrolling against a temporary hostname creates credentials that may not work after the final SSO hostname is cut over.

The `keycloak-webauthn-default-flow-v3` Job binds the `homelab` realm to `homelab-webauthn-browser-v2` and makes WebAuthn registration a default required action. Users still authenticate with their AD username/password first, but passwords are treated as already-compromisable and are never sufficient by themselves. Keycloak requires users to enroll or use a second factor, with WebAuthn/passkeys as the preferred method. TOTP remains available in the browser flow as the backup MFA method. Passwordless-only login is not enabled.

Manual staging enablement order:

1. Verify the staging discovery issuer:

   ```sh
   curl -fsS https://sso.staging.myrobertson.net/realms/homelab/.well-known/openid-configuration | jq '.issuer'
   ```

   Expected: `https://sso.staging.myrobertson.net/realms/homelab`

2. Verify an AD `Domain Admins` user can log in to `https://sso.staging.myrobertson.net/admin/homelab/console/` and has realm-admin access.
3. Enroll TOTP backup before making WebAuthn required.
4. Enroll at least two passkey-capable factors for the admin account.
5. Confirm `homelab-webauthn-browser-v2` is the realm browser flow.
6. Confirm `webauthn-register` is enabled as a default required action.
7. Confirm WebAuthn/passkey and TOTP are both available as second-factor options after AD password.
8. Test with a private browser session and from a second device.
9. Keep the master-realm bootstrap admin path available as break-glass.

Do not automate passkey enrollment. Passkey registration is intentionally an interactive user action tied to the final relying-party hostname.

## Step 3: Parallel Keycloak Deployment

Initial manifests have been added:

- `apps/base/keycloak/`
- `apps/prod/keycloak/`
- `apps/staging/keycloak/`

The deployment uses:

- Keycloak image `quay.io/keycloak/keycloak:26.6.1`
- CNPG PostgreSQL cluster `keycloak-cnpg`
- Vault-sourced Kubernetes Secret `keycloak-secret`
- Neutral AD CA Secret `ad-ldap-ca`
- HTTP enabled behind the Istio Gateway TLS terminator
- `KC_PROXY_HEADERS=xforwarded`
- `KC_TRUSTSTORE_PATHS=/opt/keycloak/conf/truststores`
- An `import-realm` init container running `kc.sh import --dir /opt/keycloak/data/import --override false`
- A `bootstrap-admin` init container running `kc.sh bootstrap-admin user`
- A `keycloak-domain-admins-rbac` Job that configures the AD group mapper and grants `realm-management` `realm-admin` to `Domain Admins`.

Before reconciling Keycloak, create Vault secrets with these keys:

```text
secret/keycloak/stage
  admin-password=<bootstrap admin password>
  ldap-bind-password=<password for ldap@myrobertson.net>
  mealie-staging-client-secret=<plaintext Keycloak client secret>
  vikunja-staging-client-secret=<plaintext Keycloak client secret>

secret/keycloak/prod
  admin-password=<bootstrap admin password>
  ldap-bind-password=<password for ldap@myrobertson.net>
```

Gateway listeners have been added for:

- `sso.myrobertson.com`
- `sso.staging.myrobertson.net`

Flux ordering:

- `infra-gateway` owns the Gateway listener, certificate, and DNS prerequisites for `sso.*`.
- `keycloak` owns the Keycloak VaultStaticSecret, CNPG database, deployment, service, HTTPRoute, redirect route, and Domain Admins bootstrap job.
- `apps` depends on `keycloak`, so apps that consume Keycloak OIDC reconcile only after Keycloak has applied and passed health checks.
- `apps-operators` remains a staging dependency for app operators that are unrelated to Keycloak.

Kubernetes object names remain `keycloak`; only the public identity endpoint is `sso.*`.

The bare SSO hostnames redirect into the `homelab` realm admin console:

- `https://sso.staging.myrobertson.net/` redirects to `/admin/homelab/console/`.
- `https://sso.myrobertson.com/` redirects to `/admin/homelab/console/`.
- `/admin` redirects to `/admin/homelab/console/` on both SSO hostnames.
- Public `/realms/master` and `/admin/master` paths redirect to the `homelab` realm so stale browser flows do not land on the master realm.

Use an internal/port-forward path for break-glass master realm administration if it is ever required.

## Controlled Staging App Migration

Mealie staging is the first intended low-risk app for validation against Keycloak on `sso.staging.myrobertson.net`.

Mealie staging GitOps configuration:

- Client ID: `mealie_staging`
- Discovery URL: `https://sso.staging.myrobertson.net/realms/homelab/.well-known/openid-configuration`
- Redirect/callback: `https://mealie.staging.myrobertson.net/login`
- Client secret source: `keycloak-secret` key `mealie-staging-client-secret`

Vikunja staging has already been moved to the `sso.staging` issuer as part of the staging troubleshooting work. Treat it as already actively switched, not as the next app to newly migrate. Validate Mealie first, then validate Vikunja as the second already-prepared staging app before moving to any additional applications.

Vikunja staging has an app-specific Keycloak browser flow managed by `keycloak-vikunja-passkey-flow-v2`. The flow is bound only to the `vikunja_staging` client and requires username/password. WebAuthn/passkey is preferred and challenged when already enrolled, while TOTP is not accepted for this client-specific flow. The flow disables the Keycloak cookie authenticator for this client so an existing SSO session cannot bypass the Tasks login ceremony. Do not hard-require WebAuthn in this flow until admin passkeys have been enrolled and tested; otherwise users with no WebAuthn credential can fail before enrollment.

Current GitOps state migrates the Kubernetes-native OIDC clients to the `sso.*` Keycloak issuers:

- Staging: Mealie, Grafana, Vikunja/Tasks, Nextcloud, and Guacamole.
- Production: Mealie, Grafana, Vikunja/Tasks, Nextcloud, Nextcloud migration LDAP, Guacamole, Proxmox VE, and Proxmox Backup Server.

Authelia remains live and external-authz policies are intentionally unchanged. Proxmox VE and PBS are now Keycloak-prepared in GitOps, but their application-side realm changes are still applied on the Proxmox/PBS hosts rather than by Kubernetes manifests. Synology clients remain later/manual cutovers.

## Proxmox and PBS Keycloak Cutover

Keycloak clients are created by `apps/base/keycloak/grafana-clients-job.yaml`:

- `proxmox_prod`: confidential OIDC client, secret sourced from `authelia-secret/pve_oidc`, issuer `https://sso.myrobertson.com/realms/homelab`, redirect URIs for `cl0`, `pve3`, `pve4`, and `pve5` on port `8006`, with the `proxmox_groups` scope attached.
- `pbs_prod`: confidential OIDC client, secret sourced from `authelia-secret/pbs_oidc`, issuer `https://sso.myrobertson.com/realms/homelab`, redirect URI for `pbs.myrobertson.net:8007`.

Use these values when updating Proxmox VE and PBS identity providers:

- Issuer URL: `https://sso.myrobertson.com/realms/homelab`
- Authorization endpoint: `https://sso.myrobertson.com/realms/homelab/protocol/openid-connect/auth`
- Token endpoint: `https://sso.myrobertson.com/realms/homelab/protocol/openid-connect/token`
- Userinfo endpoint: `https://sso.myrobertson.com/realms/homelab/protocol/openid-connect/userinfo`
- JWKS URL: `https://sso.myrobertson.com/realms/homelab/protocol/openid-connect/certs`
- Username claim: `preferred_username`
- Display name claim: `name`
- Email claim: `email`
- Proxmox group claim: `proxmox_groups`
- Scopes for Proxmox VE: `openid profile email groups proxmox_groups`
- Scopes for PBS: `openid profile email groups`

Keep local `pam`/`root@pam` or another break-glass admin path enabled while testing. Grant Proxmox/PBS privileges to the `proxAdmins` group from Keycloak claims, test a Domain Admin account, then test a non-admin AD account to confirm it does not receive administrative access.

## Validation

After Flux reconciles the staging deployment:

```sh
kubectl --context admin@staging -n default get deploy keycloak
kubectl --context admin@staging -n default rollout status deploy/keycloak
kubectl --context admin@staging -n default get cluster keycloak-cnpg
curl -fsS https://sso.staging.myrobertson.net/realms/homelab/.well-known/openid-configuration | jq '.issuer'
curl -fsS https://sso.myrobertson.com/realms/homelab/.well-known/openid-configuration | jq '.issuer'
```

Expected issuers:

- Staging: `https://sso.staging.myrobertson.net/realms/homelab`
- Prod: `https://sso.myrobertson.com/realms/homelab`

Then test in the Keycloak Admin Console:

1. Log in as local bootstrap admin.
2. Open realm `homelab`.
3. Open User federation.
4. Select `Microsoft Active Directory LDAPS`.
5. Test connection and authentication.
6. Sync a small user set or search for a known AD user.
7. Verify group visibility for `proxAdmins` before cutting Proxmox/PBS over to Keycloak.

### Staging Validation Checklist

Required issuer check:

```sh
curl -fsS https://sso.staging.myrobertson.net/realms/homelab/.well-known/openid-configuration | jq '.issuer'
```

Expected:

```text
https://sso.staging.myrobertson.net/realms/homelab
```

Then verify:

- `https://sso.staging.myrobertson.net/admin/homelab/console/` loads.
- AD `Domain Admins` users receive realm-admin access.
- TOTP backup is enrolled for admin users before WebAuthn is required.
- Passkeys are enrolled against `sso.staging.myrobertson.net`.
- Mealie staging login redirects through Keycloak and creates/updates the expected Mealie user.
- Grafana staging login redirects through Keycloak at `https://grafana.staging.myrobertson.net/login/generic_oauth`.
- Logout and session expiration behavior are acceptable.
- Authelia still protects apps that have not migrated.
- Vikunja staging remains stable if validating the already-prepared second app.

### Staging Smoke Test: 2026-05-04

Before these manifests were committed, the staging smoke test was applied directly with `kubectl` using `/tmp/keycloak-staging-smoke.yaml` with `VaultStaticSecret` filtered out. A throwaway `keycloak-secret` was created in staging using:

- LDAP bind password copied from the existing `authelia-secret` key `authentication.ldap.password.txt`
- generated bootstrap admin password
- generated `mealie_staging` client secret
- generated `vikunja_staging` client secret

Results:

- `deployment/keycloak`: `1/1` ready.
- `cluster.postgresql.cnpg.io/keycloak-cnpg`: healthy.
- `secret/ad-ldap-ca`: present with two CA entries.
- `httproute/keycloak`: accepted by the staging Gateway.
- Discovery endpoint returns issuer `https://sso.staging.myrobertson.net/realms/homelab`.
- Keycloak logs show the truststore loading `myrobertson-dc1-ca.crt` and `myrobertson-dc1-ca-1.crt`.
- An in-cluster OpenSSL probe to `rhonda.myrobertson.net:636` using `/ad-ca/myrobertson-dc1-ca.crt` returned `Verify return code: 0 (ok)`.
- `kcadm.sh` confirmed `mealie_staging` and `vikunja_staging` clients exist and are enabled in realm `homelab`.
- `keycloak-domain-admins-rbac` completed successfully.
- The `AD groups` LDAP mapper was created under the Microsoft AD LDAPS provider.
- Keycloak group `Domain Admins` was created and granted the `realm-management` client role `realm-admin`.

Smoke-test fixes discovered and folded into the manifests:

- Keycloak 26 realm import rejects `providerType` in component exports, so the LDAP component now omits it.
- Running `start --import-realm` caused the long-running pod to exit during import; the manifests now use a dedicated import init container and plain `start` for the main container.
- Bootstrap admin creation must happen after import initializes the DB, so the manifests now include a `bootstrap-admin` init container.
- Keycloak client scopes `profile`, `email`, `groups`, `basic`, `roles`, `web-origins`, and `acr` are defined explicitly for new realm imports.
- The `keycloak-standard-client-scopes-v5` Job backfills the standard Keycloak OIDC scopes, the role token mapper config, and the `account-console` to `account/manage-account` client scope mapping for existing realms so the Account Console and Admin Console receive the expected `sub`, role, origin, ACR, and account-management token claims.
- LDAP user attribute mappers are required for AD imports; without the `username` mapper, Keycloak can find the AD user but fails with `User returned from LDAP has null username`.
- AD built-in groups can have multiple parents, so the group mapper uses flattened groups with `preserve.group.inheritance=false`.

The throwaway staging Secret has since been replaced with `VaultStaticSecret/keycloak-secret` reading `secret/keycloak/stage`; the synced Kubernetes Secret is owned by Vault Secrets Operator.

## Domain Admin Console Access

AD users who are members of `Domain Admins` should use:

```text
https://sso.staging.myrobertson.net/admin/homelab/console/
```

The group-to-admin mapping is handled by `apps/base/keycloak/domain-admins-rbac-job.yaml`:

- LDAP group mapper name: `AD groups`
- AD groups DN: `cn=Users,dc=myrobertson,dc=net`
- Keycloak group: `Domain Admins`
- Granted client role: `realm-management` / `realm-admin`
- Required LDAP user attribute mappers: `username`, `firstName`, `lastName`, and `email`.
- Group inheritance is intentionally flattened because AD reports `Domain Admins` under several built-in parent groups.

If a Domain Admin authenticates successfully but does not see admin permissions, trigger or verify LDAP group synchronization and confirm the user is mapped into the Keycloak `Domain Admins` group.

## Next Work

1. Validate Mealie staging through Keycloak on `sso.staging`.
2. Verify `Domain Admins` admin access.
3. Enroll TOTP backup for admin users.
4. Enroll admin passkeys in staging.
5. Manually tune the Keycloak browser flow for WebAuthn MFA after password, starting with admin users.
6. Validate Vikunja staging as the already-prepared second app.
7. Design the replacement OIDC/proxy pattern before touching Istio external-authz policies.
8. Validate the Proxmox/PBS Keycloak cutover with a Domain Admin and a non-admin AD test user.

## Do Not Do Yet

- Do not remove Authelia.
- Do not modify Istio external-authz policies yet.
- Do not enable passwordless-only login.
- Do not tighten beyond password plus MFA into passwordless-only login until admin recovery paths are proven.
- Do not enroll passkeys against any hostname except `sso.myrobertson.com` or `sso.staging.myrobertson.net`.

## References

- Keycloak container runtime: https://www.keycloak.org/server/containers
- Keycloak reverse proxy configuration: https://www.keycloak.org/server/reverseproxy
- Keycloak hostname configuration: https://www.keycloak.org/server/hostname
- Keycloak trusted certificates and `KC_TRUSTSTORE_PATHS`: https://www.keycloak.org/server/keycloak-truststore
- Keycloak import/export behavior: https://www.keycloak.org/server/importExport
- Keycloak download/version reference for `26.6.1`: https://www.keycloak.org/downloads
