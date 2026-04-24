# Apps Base

`apps/base/` contains reusable, environment-agnostic app definitions.

## Purpose

- Holds the baseline app manifests shared by all environments.
- Defines source-of-truth chart sources, default chart values, and common Kubernetes objects.
- Reduces duplication in environment overlays.

## Conventions

- Put settings that should be identical in both environments here.
- Keep secure environment-specific values out of base manifests.
- Treat this layer as the contract consumed by `apps/staging/` and `apps/prod/`.
- Keep reusable migration and operational procedures in `../../docs/runbooks/`.

## Documented directories

- Platform and support services: [Authelia](authelia/README.md), [Code Server](code-server/README.md), [External DNS](external-dns/README.md), [n8n](n8n/README.md), [Shared Storage](shared_storage/README.md), [VolSync](volsync/README.md)
- Media and sync services: [Bazarr](bazarr/README.md), [Immich](immich/README.md), [Jellyfin](jellyfin/README.md), [Lidarr](lidarr/README.md), [Mealie](mealie/README.md), [Overseerr](overseerr/README.md), [Plex](plex/README.md), [Prowlarr](prowlarr/README.md), [Radarr](radarr/README.md), [Sonarr](sonarr/README.md), [Syncthing](syncthing/README.md)
- Observability: [Loki Stack](loki-stack/README.md)

## Additional manifest directories

- These directories exist but do not have dedicated README files yet: `bitwarden`, `gotify`, `mailu`, `netbootxyz`, `nextcloud`, `ntfy`, `redis-operator`, `task-control-plane`, `tautulli`, `trilium`

## See also

- [Apps overview](../README.md)
- [Runbook index](../../docs/runbooks/README.md)
- [Staging overlays](../staging/README.md)
- [Production overlays](../prod/README.md)
