# Immich (Base)

Base manifests for the Immich self-hosted photo and video platform.

## Purpose

- Maintains common chart source and default app settings.
- Defines shared persistence and service-level defaults.
- Provides a stable baseline for staging and production overlays.

## In this folder

- Helm source/release resources and shared storage/support manifests.

## Overlay expectations

- Capacity, ingress hostnames, and secrets are tuned in environment directories.


## Parent/Siblings

- Parent: [Base](../README.md)
- Siblings: [Authelia](../authelia/README.md); [External DNS](../external-dns/README.md); [Jellyfin](../jellyfin/README.md); [Lidarr](../lidarr/README.md); [Loki Stack](../loki-stack/README.md); [Mealie](../mealie/README.md); [Overseerr](../overseerr/README.md); [Prowlarr](../prowlarr/README.md); [Radarr](../radarr/README.md); [Shared Storage](../shared_storage/README.md); [Sonarr](../sonarr/README.md); [Syncthing](../syncthing/README.md); [VolSync](../volsync/README.md); [Whisparr](../whisparr/README.md).
