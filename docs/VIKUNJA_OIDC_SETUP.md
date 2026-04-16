# Vikunja OIDC Integration with Authelia

This document outlines the Vikunja OIDC authentication setup through Authelia's LDAP backend.

## Overview

Vikunja is configured to authenticate users via Authelia's OIDC provider, which in turn uses your LDAP/Active Directory server (rhonda.myrobertson.net) for user authentication. This provides seamless SSO for Vikunja users.

## Configuration Changes Made

### 1. Authelia OIDC Clients

Added OIDC client registrations to Authelia in both production and staging environments:

**Production** (`apps/prod/authelia/authelia-values.yaml`):
```yaml
- client_id: vikunja_prod
  client_name: Vikunja
  client_secret: '$2b$12$G4e2wFGmXCHkQowZZZKOrecbdJik.gd7L5ORyoRVOL7uMZue8SpBW'
  redirect_uris:
    - https://tasks.myrobertson.com/auth/openidCallback
```

**Staging** (`apps/staging/authelia/authelia-values.yaml`):
```yaml
- client_id: vikunja_staging
  client_name: Vikunja Staging
  client_secret: '$2b$12$G4e2wFGmXCHkQowZZZKOrecbdJik.gd7L5ORyoRVOL7uMZue8SpBW'
  redirect_uris:
    - https://tasks.staging.myrobertson.net/auth/openidCallback
```

### 2. Vikunja Helm Release Configuration

Updated Vikunja base release (`apps/base/task-control-plane/vikunja/release.yaml`) with OIDC environment variables:

```yaml
VIKUNJA_AUTH_OPENID_ENABLED: "true"
VIKUNJA_AUTH_OPENID_PROVIDER: https://auth.myrobertson.com
VIKUNJA_AUTH_OPENID_CLIENTID: (from secret)
VIKUNJA_AUTH_OPENID_CLIENTSECRET: (from secret)
VIKUNJA_AUTH_OPENID_SCOPES: "openid profile email groups"
VIKUNJA_AUTH_OPENID_LOGOUTURL: https://auth.myrobertson.com/logout
```

### 3. Kubernetes VaultStaticSecret

Created new `VaultStaticSecret` for OIDC credentials:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: vikunja-oidc-secret
spec:
  type: kv-v2
  mount: secret
  path: task-control-plane/env/vikunja-oidc
  destination:
    create: true
    name: vikunja-oidc-secret
```

### 4. Kustomization Overlays

Added patches to environment overlays to point to environment-specific Vault paths:

**Production** (`apps/prod/task-control-plane/kustomization.yaml`):
```yaml
- patch: |
    - op: replace
      path: /spec/path
      value: task-control-plane/prod/vikunja-oidc
  target:
    kind: VaultStaticSecret
    name: vikunja-oidc-secret
```

**Staging** (`apps/staging/task-control-plane/kustomization.yaml`):
```yaml
- patch: |
    - op: replace
      path: /spec/path
      value: task-control-plane/staging/vikunja-oidc
  target:
    kind: VaultStaticSecret
    name: vikunja-oidc-secret
- patch: |
    - op: replace
      path: /spec/values/vikunja/env/VIKUNJA_AUTH_OPENID_PROVIDER
      value: https://auth.staging.myrobertson.net
    - op: replace
      path: /spec/values/vikunja/env/VIKUNJA_AUTH_OPENID_LOGOUTURL
      value: https://auth.staging.myrobertson.net/logout
    - op: replace
      path: /spec/values/vikunja/configMaps/config/data/config\.yml
      value: |
        service:
          publicurl: https://tasks.staging.myrobertson.net/
          enableregistration: false
          timezone: UTC
        log:
          level: INFO
  target:
    kind: HelmRelease
    name: vikunja
```

## Required Vault Secrets

You need to create the following secrets in Vault:

### Production
**Path**: `secret/task-control-plane/prod/vikunja-oidc`

```bash
vault kv put secret/task-control-plane/prod/vikunja-oidc \
  client_id="vikunja_prod" \
  client_secret='$2b$12$G4e2wFGmXCHkQowZZZKOrecbdJik.gd7L5ORyoRVOL7uMZue8SpBW'
```

### Staging
**Path**: `secret/task-control-plane/staging/vikunja-oidc`

```bash
vault kv put secret/task-control-plane/staging/vikunja-oidc \
  client_id="vikunja_staging" \
  client_secret='$2b$12$G4e2wFGmXCHkQowZZZKOrecbdJik.gd7L5ORyoRVOL7uMZue8SpBW'
```

## How It Works

1. **User clicks "Login with OIDC"** in Vikunja
2. **Vikunja redirects** to Authelia's OIDC endpoint with client_id and redirect_uri
3. **Authelia requests** user credentials
4. **User enters LDAP credentials** (ldap@myrobertson.net)
5. **Authelia validates** against LDAP server (rhonda.myrobertson.net)
6. **Authelia returns JWT** with user info (email, groups, etc.)
7. **Vikunja processes** JWT and creates/updates local user record
8. **User is logged in** to Vikunja

## LDAP Configuration Reference

The LDAP backend is configured in Authelia with:
- **Address**: ldap://rhonda.myrobertson.net
- **Base DN**: cn=Users,dc=myrobertson,dc=net
- **Bind User**: ldap@myrobertson.net
- **Implementation**: activedirectory

## Troubleshooting

### Vikunja shows login screen but OIDC button doesn't work
- Verify Authelia OIDC provider is configured correctly
- Check `kubectl logs -n default deploy/authelia` for OIDC errors

### OIDC callback fails
- Verify redirect_uris match exactly in Authelia config
- Check Vikunja logs: `kubectl logs -n default deploy/vikunja`
- Ensure vikunja-oidc-secret exists: `kubectl get secret vikunja-oidc-secret`

### LDAP authentication fails in Authelia
- Check LDAP connectivity: `kubectl exec -it authelia-pod -- ldapsearch -H ldap://rhonda.myrobertson.net -D ldap@myrobertson.net ...`
- Verify Authelia has the correct LDAP password in vault
- Check Authelia logs: `kubectl logs -n default deploy/authelia`

### Users can't login with LDAP credentials
- Verify user account exists in LDAP
- Check Authelia access control rules permit the domain
- Confirm LDAP search base includes the user's DN path

## User Attribute Mapping

The OIDC scope `openid profile email groups` will populate:
- **openid**: Required for OIDC (user subject identifier)
- **profile**: First name, last name, username
- **email**: Email address
- **groups**: LDAP group memberships (if available in LDAP provider)

Vikunja will use these to populate user profile fields automatically.

## Security Considerations

1. **Client Secret**: The same bcrypt-hashed secret is shared with Mealie and Grafana for consistency. Consider rotating if needed.
2. **LDAP Password**: Stored securely in Vault, synced to K8s secrets by Vault Secrets Operator
3. **HTTPS Only**: All OIDC communication uses HTTPS (auth.myrobertson.com)
4. **Session Timeout**: Authelia session configured to 1 hour expiration with 5 minute inactivity timeout

## Next Steps

After the Vault secrets are created:

1. Reconcile Flux to apply the configuration:
   ```bash
   kubectl -n flux-system annotate kustomization apps \
     reconcile.fluxcd.io/requestedAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --overwrite
   ```

2. Wait for Deployments to be ready:
   ```bash
   kubectl rollout status deploy/authelia
   kubectl rollout status deploy/vikunja
   ```

3. Test OIDC login:
   - Navigate to https://tasks.myrobertson.com
   - Click "Login" or the OIDC provider button
   - Authenticate with your LDAP credentials
   - Verify you're logged in to Vikunja

4. Verify user creation:
   ```bash
   # In Vikunja database
   SELECT * FROM users WHERE email LIKE '%@myrobertson.net' LIMIT 5;
   ```
