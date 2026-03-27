# Jellyfin (Base)

Base manifests for Jellyfin media streaming services.

## Purpose

- Defines reusable chart source and default runtime settings.
- Centralizes base storage and service configuration.
- Allows environment overlays to only patch the deltas.

## In this folder

- Helm source/release manifests for Jellyfin and shared app resources.

## Overlay expectations

- Environment-specific networking, resources, and secret values are patched in overlays.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Immich](../immich/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md).
