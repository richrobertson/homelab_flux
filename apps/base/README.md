# Apps Base

`apps/base/` contains reusable, environment-agnostic app definitions.

## Purpose

- Holds the baseline app manifests that should be shared by all environments.
- Defines source-of-truth chart sources, default chart values, and shared Kubernetes objects.
- Reduces duplication in environment overlays.

## Contents

- One directory per application/service (for example: `immich`, `loki-stack`, `authelia`).
- Typical files include:
  - `repository.yaml` for HelmRepository or OCI source.
  - `release.yaml` for HelmRelease and default values.
  - Supporting manifests such as namespaces, secrets references, or app-specific resources.

## How to use this section

- Put settings that should be identical in both environments here.
- Keep secure environment-specific values out of base manifests.
- Treat this layer as the contract consumed by `apps/staging/` and `apps/prod/`.

## App catalog

- `authelia`: identity and authentication gateway for protected services.
- `external-dns`: DNS record automation from Kubernetes resources.
- `immich`: self-hosted photo/video management stack.
- `jellyfin`: media server for local streaming.
- `lidarr`: music collection management and automation.
- `loki-stack`: log aggregation and collection components.
- `mealie`: recipe management application.
- `overseerr`: media request management interface.
- `prowlarr`: indexer management for media automation tools.
- `radarr`: movie library management and automation.
- `shared_storage`: storage objects consumed by multiple apps.
- `sonarr`: TV show library management and automation.
- `syncthing`: peer-to-peer file synchronization.
- `volsync`: persistent volume replication/synchronization.

## See also

- [Apps overview](../README.md)
- [Staging overlays](../staging/README.md)
- [Production overlays](../prod/README.md)

Leaf docs:

- [Authelia base](authelia/README.md)
- [External DNS base](external-dns/README.md)
- [Immich base](immich/README.md)
- [Jellyfin base](jellyfin/README.md)
- [Lidarr base](lidarr/README.md)
- [Loki Stack (Base)](loki-stack/README.md)
- [Mealie base](mealie/README.md)
- [Overseerr base](overseerr/README.md)
- [Prowlarr base](prowlarr/README.md)
- [Radarr base](radarr/README.md)
- [Shared Storage (Base)](shared_storage/README.md)
- [Sonarr base](sonarr/README.md)
- [Syncthing base](syncthing/README.md)
- [VolSync base](volsync/README.md)