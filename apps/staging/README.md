# Apps Staging

`apps/staging/` defines environment-specific overlays for the staging cluster.

## Purpose

- Applies staging-safe values and patches on top of `apps/base/`.
- Enables validation of app changes before production rollout.
- Supports lower-risk experimentation for chart and version changes.

## What belongs here

- Kustomization entries that include or patch base app resources.
- Staging-only values such as reduced replicas, sandbox hostnames, and lower resource requests.
- Optional staging-only app inclusion or exclusion decisions.

## Operational intent

- Staging should remain production-like enough to catch deployment issues.
- Differences from production should be intentional and minimal.
- Use this layer to prove upgrades before promoting to `apps/prod/`.
- Use `../../docs/runbooks/` for cross-app operational procedures.

## Documented directories

- Platform and support services: [Authelia](authelia/README.md), [Code Server](code-server/README.md), [External DNS](external-dns/README.md), [Shared Storage](shared_storage/README.md), [VolSync](volsync/README.md)
- Media and sync services: [Bazarr](bazarr/README.md), [Immich](immich/README.md), [Lidarr](lidarr/README.md), [Mealie](mealie/README.md), [Overseerr](overseerr/README.md), [Plex](plex/README.md), [Prowlarr](prowlarr/README.md), [Radarr](radarr/README.md), [Sonarr](sonarr/README.md), [Syncthing](syncthing/README.md)
- Observability: [Loki Stack](loki-stack/README.md)

## Additional manifest directories

- These directories exist but do not have dedicated README files yet: `bitwarden`, `gotify`, `n8n`, `netbootxyz`, `nextcloud`, `ntfy`, `redis-operator`, `redis-operator-bootstrap`, `task-control-plane`, `tautulli`, `trilium`

## See also

- [Apps overview](../README.md)
- [Runbook index](../../docs/runbooks/README.md)
- [Shared base layer](../base/README.md)
- [Production overlays](../prod/README.md)
