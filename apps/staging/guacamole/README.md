# Guacamole (Staging)

Staging overlay for Apache Guacamole.

## Purpose

- Exposes Guacamole privately at `https://rdp.staging.myrobertson.net`.
- Uses the staging Keycloak issuer at `https://sso.staging.myrobertson.net/realms/homelab`.
- Keeps the staging PostgreSQL database small for validation before production promotion.

## Validation

See [Guacamole runbook](../../../docs/runbooks/GUACAMOLE_RUNBOOK.md) for reconcile, login, and database bootstrap checks.
