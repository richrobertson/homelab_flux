# Apps Prod

`apps/prod/` defines environment-specific overlays for the production cluster.

## Purpose

- Applies production-grade values and patches on top of `apps/base/`.
- Hosts stable, validated app configuration intended for daily use.
- Serves as the final target of promotion from staging.

## What belongs here

- Production-specific patches, values files, and app kustomizations.
- Stronger availability and retention settings where production differs from staging.
- Production ingress, hostnames, and integration references.

## Change guardrails

- Keep production-only deltas explicit and reviewable.
- Avoid introducing breaking drift between staging and prod unless required.
- Record major behavior differences in PR descriptions for auditability.
- Keep shared operational procedures in `../../docs/runbooks/` so the overlay stays focused on manifests.

## Documented directories

- Platform and support services: [Authelia](authelia/README.md), [Code Server](code-server/README.md), [External DNS](external-dns/README.md), [Guacamole](guacamole/README.md), [Mailu](mailu/README.md), [n8n](n8n/README.md), [Shared Storage](shared_storage/README.md), [VolSync](volsync/README.md)
- Media and sync services: [Bazarr](bazarr/README.md), [Immich](immich/README.md), [Lidarr](lidarr/README.md), [Mealie](mealie/README.md), [Overseerr](overseerr/README.md), [Plex](plex/README.md), [Prowlarr](prowlarr/README.md), [Radarr](radarr/README.md), [Sonarr](sonarr/README.md), [Syncthing](syncthing/README.md)
- Observability: [Loki Stack](loki-stack/README.md)

## Additional manifest directories

- These directories exist but do not have dedicated README files yet: `bitwarden`, `gotify`, `netbootxyz`, `nextcloud`, `ntfy`, `redis-operator`, `task-control-plane`, `tautulli`, `trilium`

## Operational docs

- [Runbook index](../../docs/runbooks/README.md)
- [App Ceph migration runbook](../../docs/runbooks/APP_CEPH_MIGRATION_RUNBOOK.md)
- [SynologyNAS container migration playbook](../../docs/runbooks/APP_SYNOLOGYNAS_CONTAINER_MIGRATION_PLAYBOOK.md)
- [VolSync production verification commands](volsync/README.md#operational-verification)

## See also

- [Apps overview](../README.md)
- [Shared base layer](../base/README.md)
- [Staging overlays](../staging/README.md)
