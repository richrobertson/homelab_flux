# Guacamole (Base)

Base manifests for Apache Guacamole, a browser-based remote desktop gateway.

## Purpose

- Runs the official Guacamole web application, guacd daemon, and PostgreSQL-backed configuration database.
- Keeps guacd and PostgreSQL cluster-internal only.
- Uses Authelia OpenID Connect for authentication while PostgreSQL stores connection definitions, permissions, and metadata.

## Version pin

- `guacamole/guacamole:1.6.0`
- `guacamole/guacd:1.6.0`

The official Guacamole image enables version-matched PostgreSQL and OpenID extensions from the same image when `POSTGRESQL_ENABLED` and `OPENID_ENABLED` are set. No custom image is required for the first milestone.

## Database bootstrap

`guacamole-postgres-init` renders the official PostgreSQL schema with `/opt/guacamole/bin/initdb.sh --postgresql` and applies it with `psql`. The job exits without changes if the `guacamole_user` table already exists.

The upstream schema creates the initial local `guacadmin` account. Use it only for first-time administration, rotate it immediately, and then disable or tightly protect local database login once Authelia OIDC users/groups have the intended permissions.

## Theme Park

Theme Park for Guacamole requires proxy-side response body injection. This repo currently exposes apps through Istio Gateway API, which does not provide the NGINX/Traefik subfilter pattern used by Theme Park. See `examples/theme-park/` and the Guacamole runbook for the deferred dark-theme path.

## Parent/Siblings

- Parent: [Base](../README.md)
- Runbook: [Guacamole runbook](../../../docs/runbooks/GUACAMOLE_RUNBOOK.md)

