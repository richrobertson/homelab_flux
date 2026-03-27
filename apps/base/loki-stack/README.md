# Loki Stack (Base)

Base manifests for centralized logging components (Loki and related agents).

## Purpose

- Defines shared chart sources and logging defaults.
- Establishes baseline retention/collection behavior consumed by all environments.
- Keeps logging topology consistent between staging and production.

## In this folder

- Helm source/release objects and logging support manifests.

## Overlay expectations

- Environment-specific storage/performance tuning should be patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
