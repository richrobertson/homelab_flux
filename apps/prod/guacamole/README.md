# Guacamole (Prod)

Production overlay for Apache Guacamole.

## Purpose

- Exposes Guacamole publicly at `https://rdp.myrobertson.com`.
- Uses the production Authelia issuer at `https://auth.myrobertson.com`.
- Uses `one_factor` until Authelia MFA enrollment is complete.
- Fetches JWKS from the in-cluster Authelia service while keeping the public issuer and browser authorization URL.
- CloudNativePG object-store backups are deferred until the Vault Kubernetes role allows secrets in the `guacamole` namespace. The database PVC remains on `ceph-block`.

## Validation

Test the staging overlay first, then promote to this production overlay. See [Guacamole runbook](../../../docs/runbooks/GUACAMOLE_RUNBOOK.md).
