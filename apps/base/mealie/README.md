# Mealie (Base)

Base manifests for Mealie recipe management services.

## Purpose

- Provides common chart source and default app configuration.
- Defines shared runtime and persistence assumptions.
- Supports consistent deployment behavior across environments.

## In this folder

- Helm repository/release resources and supporting base manifests.

## Overlay expectations

- Hostnames, auth integration details, and environment-specific values belong in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
