# Guacamole (Prod)

Production overlay for Apache Guacamole.

## Purpose

- Exposes Guacamole publicly at `https://rdp.myrobertson.com`.
- Uses the production Keycloak issuer at `https://sso.myrobertson.com/realms/homelab`.
- Requires the Keycloak realm MFA/passkey policy before Guacamole receives an OIDC token.
- Fetches JWKS from the public Keycloak realm certificate endpoint.
- CloudNativePG object-store backups are deferred until the Vault Kubernetes role allows secrets in the `guacamole` namespace. The database PVC remains on `ceph-block`.

## Validation

Test the staging overlay first, then promote to this production overlay. See [Guacamole runbook](../../../docs/runbooks/GUACAMOLE_RUNBOOK.md).
