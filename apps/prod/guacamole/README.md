# Guacamole (Prod)

Production overlay for Apache Guacamole.

## Purpose

- Exposes Guacamole publicly at `https://rdp.myrobertson.com`.
- Uses the production Authelia issuer at `https://auth.myrobertson.com`.
- Enables CloudNativePG object-store backups for the Guacamole PostgreSQL database.

## Validation

Test the staging overlay first, then promote to this production overlay. See [Guacamole runbook](../../../docs/runbooks/GUACAMOLE_RUNBOOK.md).
